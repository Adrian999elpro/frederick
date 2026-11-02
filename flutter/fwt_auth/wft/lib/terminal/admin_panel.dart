import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/nfc.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'terminal_context.dart';

/// Panel que se abre al acercar la tarjeta de un administrador. Lo que se cambie aquí queda fijo
/// en el terminal hasta que un administrador lo vuelva a cambiar con su tarjeta.
class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({
    super.key,
    required this.ctx,
    required this.modes,
    required this.ticket,
    required this.reauthorize,
  });

  final TerminalCtx ctx;

  /// Modos que se pueden elegir (sin «Votación», que se fija desde la lista de votaciones).
  final List<TerminalMode> modes;

  /// Permiso de un solo uso que se obtuvo con la tarjeta; sirve para desbloquear la app.
  final String ticket;

  /// Pide otra vez la tarjeta del administrador y devuelve un permiso nuevo (o null).
  final Future<String?> Function() reauthorize;

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  late String _mode = widget.ctx.mode;
  late String? _pollId = widget.ctx.pollId;
  late String _ticket = widget.ticket;
  DateTime _issuedAt = DateTime.now();

  List<Map<String, dynamic>> _polls = const [];
  bool _loadingPolls = true;
  String? _pollsError;
  String? _working;

  Access get _access => widget.ctx.access;
  bool get _showPolls => _access.can('polls.operate') || _access.can('polls.manage');

  @override
  void initState() {
    super.initState();
    if (_showPolls) {
      _loadPolls();
    } else {
      _loadingPolls = false;
    }
  }

  Future<void> _loadPolls() async {
    setState(() {
      _loadingPolls = true;
      _pollsError = null;
    });
    try {
      final api = Api.instance;
      final rows = await api.rows(api.client
          .from('school_polls')
          .select('*, school_poll_options(id, label)')
          .order('created_at', ascending: false));
      if (!mounted) return;
      setState(() {
        _polls = rows;
        _loadingPolls = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pollsError = friendlyError(e);
        _loadingPolls = false;
      });
    }
  }

  /// Anota en el servidor lo que hace el administrador. Es un registro: si falla no se detiene nada.
  Future<void> _log(String event, [Map<String, dynamic> detail = const {}]) async {
    try {
      await Api.instance.client.rpc('log_terminal_event', params: {'p_ticket': _ticket, 'p_event': event, 'p_detail': detail});
    } catch (_) {}
  }

  void _chooseMode(String id) {
    _log('mode_changed', {'mode': id});
    widget.ctx.setMode(id);
    setState(() => _mode = id);
    snack(context, 'Modo cambiado. Queda fijo hasta que un administrador lo cambie.');
  }

  void _usePoll(Map<String, dynamic> poll) {
    final id = poll['id'] as String;
    _log('poll_pinned', {'poll_id': id});
    widget.ctx.setMode('polls', pollId: id);
    setState(() {
      _mode = 'polls';
      _pollId = id;
    });
    snack(context, 'Votación fijada en este terminal.');
  }

  String _status(Map<String, dynamic> p) {
    final ends = DateTime.tryParse('${p['ends_at']}');
    if (p['status'] == 'closed' || (p['status'] == 'open' && ends != null && !ends.isAfter(DateTime.now()))) return 'closed';
    return '${p['status']}';
  }

  Future<void> _act(Map<String, dynamic> poll, String action) async {
    final String question;
    switch (action) {
      case 'open':
        question = 'Se fijará la lista de estudiantes habilitados y empezará el tiempo de votación. Ya no se podrán aceptar postulaciones. ¿Abrir?';
      case 'close':
        question = '¿Cerrar la votación y publicar sus resultados?';
      default:
        question = '';
    }
    if (question.isNotEmpty && !await confirm(context, question, okLabel: action == 'open' ? 'Abrir' : 'Cerrar')) return;
    setState(() => _working = poll['id'] as String);
    try {
      if (action == 'applications') {
        final open = poll['applications_open'] != true;
        await Api.instance.client.rpc('set_council_applications_open', params: {'p_poll_id': poll['id'], 'p_open': open});
        _log('applications_toggled', {'poll_id': poll['id'], 'open': open});
      } else {
        await Api.instance.client.rpc('change_school_poll_status', params: {'p_id': poll['id'], 'p_action': action});
        _log('poll_status', {'poll_id': poll['id'], 'action': action});
      }
      await _loadPolls();
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo completar. Revisa que esta cuenta tenga ese permiso.'), error: true);
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _results(Map<String, dynamic> poll) async {
    setState(() => _working = poll['id'] as String);
    try {
      final data = await Api.instance.rpcMap('school_poll_results', {'p_id': poll['id']});
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => _ResultsSheet(title: '${poll['title']}', data: data),
      );
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudieron cargar los resultados.'), error: true);
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _NewPollSheet(),
    );
    if (created != null) {
      _log('poll_created', {'kind': created});
      if (mounted) snack(context, 'Borrador creado. Ábrelo cuando esté listo.');
      await _loadPolls();
    }
  }

  Future<void> _unlock() async {
    if (!await confirm(context, '¿Desbloquear la app? Se suelta la fijación de pantalla y el terminal deja de estar protegido.', okLabel: 'Desbloquear')) {
      return;
    }
    var ticket = _ticket;
    if (DateTime.now().difference(_issuedAt) > const Duration(seconds: 45)) {
      final fresh = await widget.reauthorize();
      if (fresh == null) return;
      ticket = fresh;
      _ticket = fresh;
      _issuedAt = DateTime.now();
    }
    try {
      final ok = await Api.instance.client.rpc('consume_terminal_unlock', params: {'p_token': ticket});
      if (ok != true) {
        _issuedAt = DateTime.fromMillisecondsSinceEpoch(0);
        if (mounted) snack(context, 'La autorización venció. Toca de nuevo «Desbloquear» y acerca la tarjeta.', error: true);
        return;
      }
      await Nfc.unpin();
      if (mounted) Navigator.of(context).pop('unlocked');
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo desbloquear. Revisa la conexión.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(padding: EdgeInsets.zero, children: [
          HeroHeader(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PANEL DEL ENCARGADO', style: TextStyle(color: Fwt.gold, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              const Text('Tarjeta autorizada', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                'Lo que elijas queda fijo en este teléfono hasta que un administrador lo cambie con su tarjeta.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionTitle('Qué hace este terminal'),
              for (final m in widget.modes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    color: m.id == _mode ? Fwt.brand.withValues(alpha: 0.12) : null,
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      leading: Icon(m.icon, color: context.brandText),
                      title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: m.id == _mode ? const Icon(Icons.check_circle_rounded, color: Fwt.ok) : null,
                      onTap: () => _chooseMode(m.id),
                    ),
                  ),
                ),
              if (_showPolls) ...[
                Row(children: [
                  const Expanded(child: SectionTitle('Votaciones')),
                  if (_access.can('polls.manage'))
                    FilledButton.tonalIcon(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Nueva')),
                ]),
                if (_loadingPolls)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                else if (_pollsError != null)
                  EmptyState(icon: Icons.cloud_off_rounded, text: _pollsError!, actionLabel: 'Reintentar', onAction: _loadPolls)
                else if (_polls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Todavía no hay votaciones. Crea una con «Nueva».', style: TextStyle(color: context.muted)),
                  )
                else
                  for (final p in _polls) _pollCard(p),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _unlock,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Desbloquear la app'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar panel y volver al terminal'),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ]),
      );

  Widget _pollCard(Map<String, dynamic> p) {
    final status = _status(p);
    final id = p['id'] as String;
    final assigned = _mode == 'polls' && _pollId == id;
    final isCouncil = p['kind'] == 'council';
    final label = switch (status) {
      'draft' => isCouncil ? 'Borrador / postulaciones' : 'Borrador',
      'open' => 'Abierta',
      _ => 'Cerrada',
    };
    final color = switch (status) {
      'open' => Fwt.ok,
      'draft' => Fwt.gold,
      _ => context.muted,
    };
    final busy = _working == id;
    final options = ((p['school_poll_options'] as List?) ?? const []).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: assigned ? Fwt.brand : Colors.transparent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${p['title']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _Pill(label, color),
            _Pill(isCouncil ? 'Consejo estudiantil' : 'Personalizada', context.muted),
            _Pill(p['secret'] == true ? 'Secreta' : 'Identificada', context.muted),
            if (!isCouncil || options > 0) _Pill('$options opciones', context.muted),
            if (isCouncil && status == 'draft') _Pill(p['applications_open'] == true ? 'Postulaciones abiertas' : 'Postulaciones cerradas', context.muted),
            if (assigned) const _Pill('En este terminal', Fwt.brand),
          ]),
          const SizedBox(height: 10),
          if (busy)
            const Center(child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator()))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (status != 'closed' && _access.can('polls.operate') && !assigned)
                FilledButton.tonalIcon(onPressed: () => _usePoll(p), icon: const Icon(Icons.push_pin_rounded, size: 18), label: const Text('Usar en el terminal')),
              if (status == 'draft' && isCouncil && _access.can('council.open'))
                OutlinedButton(
                  onPressed: () => _act(p, 'applications'),
                  child: Text(p['applications_open'] == true ? 'Cerrar postulaciones' : 'Abrir postulaciones'),
                ),
              if (status == 'draft' && _access.can('polls.manage'))
                FilledButton(onPressed: () => _act(p, 'open'), child: const Text('Abrir votación')),
              if (status == 'open' && _access.can('polls.manage'))
                FilledButton(onPressed: () => _act(p, 'close'), child: const Text('Cerrar votación')),
              if (status != 'draft' && (_access.can('polls.manage') || status == 'closed'))
                OutlinedButton(onPressed: () => _results(p), child: const Text('Resultados')),
            ]),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color == Fwt.gold ? context.brandText : color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _ResultsSheet extends StatelessWidget {
  const _ResultsSheet({required this.title, required this.data});
  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final closed = data['closed'] == true;
    final options = ((data['options'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final people = ((data['participants'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final secret = data['secret'] == true;
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final maxVotes = options.fold<int>(1, (m, o) => ((o['votes'] as num?)?.toInt() ?? 0) > m ? (o['votes'] as num).toInt() : m);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(closed ? 'Resultados finales' : 'Resultados parciales', style: TextStyle(color: context.muted)),
        const SizedBox(height: 10),
        Text(
          '$total votos de ${data['eligible']} estudiantes. ${data['no_vote']} ${closed ? 'sin voto (nulo por no participación)' : 'pendientes'}.',
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
        ),
        const SizedBox(height: 14),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${o['label']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${o['votes']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(minHeight: 8, value: ((o['votes'] as num?)?.toDouble() ?? 0) / maxVotes),
              ),
            ]),
          ),
        if (people.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Participación', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final v in people)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${v['name']}'),
              subtitle: secret ? null : Text('${v['choice'] ?? '—'}'),
              trailing: Text(v['voted'] == true ? 'Votó' : (closed ? 'Sin voto' : 'Pendiente'),
                  style: TextStyle(color: v['voted'] == true ? Fwt.ok : context.muted, fontWeight: FontWeight.w700)),
            ),
        ],
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
      ]),
    );
  }
}

class _NewPollSheet extends StatefulWidget {
  const _NewPollSheet();

  @override
  State<_NewPollSheet> createState() => _NewPollSheetState();
}

class _NewPollSheetState extends State<_NewPollSheet> {
  final _title = TextEditingController();
  final _purpose = TextEditingController();
  final _options = TextEditingController();
  String _kind = 'custom';
  int _minutes = 60;
  bool _secret = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _purpose.dispose();
    _options.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final options = _options.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (_title.text.trim().length < 3) return setState(() => _error = 'Escribe un título.');
    if (_purpose.text.trim().length < 10) return setState(() => _error = 'Explica el motivo (mínimo 10 caracteres).');
    if (_kind == 'custom' && (options.length < 2 || options.length > 20 || options.toSet().length != options.length)) {
      return setState(() => _error = 'Escribe entre 2 y 20 opciones diferentes, una por línea.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.client.rpc('create_school_poll', params: {
        'p_kind': _kind,
        'p_title': _title.text.trim(),
        'p_purpose': _purpose.text.trim(),
        'p_duration_minutes': _minutes,
        'p_secret': _secret,
        'p_options': _kind == 'custom' ? options : <String>[],
      });
      if (mounted) Navigator.of(context).pop(_kind);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, 'No se pudo crear. Revisa los datos y que esta cuenta pueda administrar votaciones.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nueva votación', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'custom', label: Text('Personalizada')),
                ButtonSegment(value: 'council', label: Text('Consejo')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Título')),
            const SizedBox(height: 12),
            TextField(controller: _purpose, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo de la votación')),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _minutes,
              decoration: const InputDecoration(labelText: 'Duración una vez abierta'),
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 minutos')),
                DropdownMenuItem(value: 30, child: Text('30 minutos')),
                DropdownMenuItem(value: 60, child: Text('1 hora')),
                DropdownMenuItem(value: 120, child: Text('2 horas')),
                DropdownMenuItem(value: 240, child: Text('4 horas')),
                DropdownMenuItem(value: 1440, child: Text('1 día')),
              ],
              onChanged: (v) => setState(() => _minutes = v ?? 60),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Voto secreto'),
              subtitle: Text(_secret ? 'Los resultados no relacionan nombres con opciones.' : 'Se publicará quién votó por cada opción.'),
              value: _secret,
              onChanged: (v) => setState(() => _secret = v),
            ),
            if (_kind == 'custom') ...[
              TextField(
                controller: _options,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Opciones (una por línea)', alignLabelWithHint: true),
              ),
            ] else
              Text('Las opciones serán las listas aprobadas durante las postulaciones.', style: TextStyle(color: context.muted)),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: context.brandText, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Creando…' : 'Crear borrador')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          ]),
        ),
      );
}
