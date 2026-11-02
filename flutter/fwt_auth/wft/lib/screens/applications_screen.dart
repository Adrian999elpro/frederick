import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class _AppsData {
  _AppsData(this.openPolls, this.mine);
  final List<Map<String, dynamic>> openPolls;
  final List<Map<String, dynamic>> mine;
}

Future<_AppsData> _load(String studentId) async {
  final api = Api.instance;
  final polls = await api.rows(api.client
      .from('school_polls')
      .select('id, title')
      .eq('kind', 'council')
      .eq('status', 'draft')
      .eq('applications_open', true));
  final mine = await api.rows(api.client
      .from('council_applications')
      .select('*, school_polls(title)')
      .eq('student_id', studentId)
      .order('updated_at', ascending: false));
  return _AppsData(polls, mine);
}

/// Postulación de una lista al consejo estudiantil y seguimiento de su respuesta.
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key, required this.access});
  final Access access;

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  int _reload = 0;

  Future<void> _openForm(List<Map<String, dynamic>> polls) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ApplicationForm(polls: polls),
    );
    if (sent == true && mounted) {
      snack(context, 'Postulación enviada.');
      setState(() => _reload++);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Postulaciones al consejo')),
        body: AsyncView<_AppsData>(
          refreshKey: _reload,
          load: () => _load(widget.access.id),
          builder: (context, data, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text('Presenta tu lista y tu plan de trabajo. Aquí verás la respuesta y el motivo de una devolución.',
                  style: TextStyle(color: context.muted, height: 1.4)),
              const SizedBox(height: 14),
              if (data.openPolls.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _openForm(data.openPolls),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Postular mi lista'),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(Icons.lock_clock_rounded, color: context.muted),
                      const SizedBox(width: 12),
                      Expanded(child: Text('No hay convocatorias abiertas para nuevas postulaciones.', style: TextStyle(color: context.muted))),
                    ]),
                  ),
                ),
              const SectionTitle('Mis postulaciones'),
              if (data.mine.isEmpty)
                Text('Todavía no has enviado ninguna.', style: TextStyle(color: context.muted))
              else
                for (final a in data.mine) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ApplicationCard(data: a)),
            ]),
          ),
        ),
      );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final (String label, Color color) = switch (status) {
      'accepted' => ('Aprobada', Fwt.ok),
      'rejected' => ('Rechazada: corrige y vuelve a enviar', Fwt.accent),
      _ => ('En revisión', Fwt.gold),
    };
    final reason = data['reason'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${data['list_name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          Text('${(data['school_polls'] as Map?)?['title'] ?? ''}', style: TextStyle(color: context.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Respuesta del encargado: $reason', style: const TextStyle(height: 1.4)),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('Plan de trabajo', style: TextStyle(fontWeight: FontWeight.w700)),
            children: [Align(alignment: Alignment.centerLeft, child: Text('${data['work_plan']}', style: const TextStyle(height: 1.4)))],
          ),
        ]),
      ),
    );
  }
}

class _ApplicationForm extends StatefulWidget {
  const _ApplicationForm({required this.polls});
  final List<Map<String, dynamic>> polls;

  @override
  State<_ApplicationForm> createState() => _ApplicationFormState();
}

class _ApplicationFormState extends State<_ApplicationForm> {
  final _list = TextEditingController();
  final _plan = TextEditingController();
  late String _poll = widget.polls.first['id'] as String;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _list.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_list.text.trim().length < 2) return setState(() => _error = 'Escribe el nombre de tu lista.');
    if (_plan.text.trim().length < 50) return setState(() => _error = 'El plan de trabajo necesita al menos 50 caracteres.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.client.rpc('submit_council_application', params: {
        'p_poll_id': _poll,
        'p_list_name': _list.text.trim(),
        'p_work_plan': _plan.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Postular mi lista', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (widget.polls.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _poll,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Convocatoria'),
                items: [for (final p in widget.polls) DropdownMenuItem(value: p['id'] as String, child: Text('${p['title']}'))],
                onChanged: (v) => setState(() => _poll = v ?? _poll),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: _list, maxLength: 80, decoration: const InputDecoration(labelText: 'Nombre de tu lista')),
            const SizedBox(height: 4),
            TextField(
              controller: _plan,
              maxLength: 6000,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Plan de trabajo',
                alignLabelWithHint: true,
                hintText: 'Describe tus propuestas, actividades, responsables y fechas.',
              ),
            ),
            Text('Mínimo 50 caracteres. Si se devuelve, podrás corregirla mientras la convocatoria siga abierta.',
                style: TextStyle(color: context.muted, fontSize: 12)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: context.brandText))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Enviar postulación'),
            ),
          ]),
        ),
      );
}
