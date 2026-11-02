import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class _CardData {
  _CardData({this.details, this.specialty, this.request, this.hasCard, this.photo});
  final Map<String, dynamic>? details;
  final String? specialty;
  final Map<String, dynamic>? request;
  final bool? hasCard;
  final String? photo;
}

Future<_CardData> _loadCard(Access a) async {
  final api = Api.instance;
  final details = await api.client
      .from('student_details')
      .select('student_code, level_id, chosen_specialty_id, school_levels(name)')
      .eq('profile_id', a.id)
      .maybeSingle();
  String? specialty;
  final specId = details?['chosen_specialty_id'];
  if (specId != null) {
    final spec = await api.client.from('technical_specialties').select('name, short_name').eq('id', specId as Object).maybeSingle();
    specialty = (spec?['short_name'] ?? spec?['name']) as String?;
  }
  Map<String, dynamic>? request;
  try {
    request = await api.client.from('enrollment_requests').select('*').eq('profile_id', a.id).maybeSingle();
  } catch (_) {}
  bool? hasCard;
  try {
    final cards = await api.client.from('nfc_cards').select('id').eq('profile_id', a.id).eq('active', true).limit(1);
    hasCard = (cards as List).isNotEmpty;
  } catch (_) {}
  return _CardData(
    details: details == null ? null : Map<String, dynamic>.from(details),
    specialty: specialty,
    request: request == null ? null : Map<String, dynamic>.from(request),
    hasCard: hasCard,
    photo: await api.photoUrl(a.id),
  );
}

class CardScreen extends StatefulWidget {
  const CardScreen({super.key, required this.access});
  final Access access;

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  int _reload = 0;

  Future<void> _openEnrollment() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _EnrollmentSheet(access: widget.access),
    );
    if (sent == true && mounted) {
      snack(context, 'Datos enviados. El colegio los revisará.');
      setState(() => _reload++);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mi carnet')),
        body: AsyncView<_CardData>(
          refreshKey: _reload,
          load: () => _loadCard(widget.access),
          builder: (context, data, reload) {
            final level = (data.details?['school_levels'] as Map?)?['name'] as String?;
            final code = data.details?['student_code'] as String?;
            final status = data.request?['status'] as String?;
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                _IdCard(
                  name: widget.access.fullName,
                  level: level,
                  specialty: data.specialty,
                  code: code,
                  photo: data.photo,
                ),
                const SizedBox(height: 16),
                _StatusCard(hasCard: data.hasCard, status: status, linked: level != null),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openEnrollment,
                  icon: const Icon(Icons.contactless_rounded),
                  label: Text(level == null ? 'Vincular mi tarjeta y curso' : 'Actualizar mis datos o tarjeta'),
                ),
                if (status == 'rejected')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Tu solicitud fue rechazada. Revisa los datos y vuelve a enviarla.',
                        style: TextStyle(color: context.brandText)),
                  ),
              ]),
            );
          },
        ),
      );
}

class _IdCard extends StatelessWidget {
  const _IdCard({required this.name, this.level, this.specialty, this.code, this.photo});
  final String name;
  final String? level;
  final String? specialty;
  final String? code;
  final String? photo;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: Fwt.heroGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Fwt.brand.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SchoolLogo(size: 40),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('CARNET ESTUDIANTIL',
                  style: TextStyle(color: Fwt.gold, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 12)),
            ),
            const Icon(Icons.contactless_rounded, color: Colors.white70),
          ]),
          const SizedBox(height: 22),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: Fwt.gold, shape: BoxShape.circle),
              child: Avatar(name: name, url: photo, size: 84),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? 'Estudiante' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.15)),
                const SizedBox(height: 6),
                Text(level ?? 'Curso sin vincular', style: const TextStyle(color: Colors.white, fontSize: 15)),
                if (specialty != null) Text(specialty!, style: const TextStyle(color: Fwt.gold, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: Text(code == null || code!.isEmpty ? schoolName : 'Código: $code',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ),
          ]),
        ]),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.hasCard, required this.status, required this.linked});
  final bool? hasCard;
  final String? status;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String title, String text) = switch ((hasCard, status)) {
      (true, _) => (Icons.check_circle_rounded, Fwt.ok, 'Tarjeta activa', 'Puedes usar tu tarjeta en asistencia, votaciones y consulta de notas.'),
      (_, 'pending') => (Icons.hourglass_top_rounded, Fwt.gold, 'En revisión', 'El colegio está revisando tus datos antes de activar la tarjeta.'),
      (_, 'approved') => (Icons.check_circle_rounded, Fwt.ok, 'Solicitud aprobada', 'Tu solicitud fue aprobada.'),
      (_, 'rejected') => (Icons.cancel_rounded, Fwt.accent, 'Solicitud rechazada', 'Revisa tus datos y vuelve a enviarlos.'),
      _ => (Icons.info_outline_rounded, context.muted, 'Sin tarjeta vinculada', 'Vincula tu tarjeta NFC y tu curso para usar el terminal escolar.'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(text, style: TextStyle(color: context.muted, height: 1.35)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EnrollmentSheet extends StatefulWidget {
  const _EnrollmentSheet({required this.access});
  final Access access;

  @override
  State<_EnrollmentSheet> createState() => _EnrollmentSheetState();
}

class _EnrollmentSheetState extends State<_EnrollmentSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.access.fullName);
  late final TextEditingController _phone = TextEditingController(text: widget.access.phone);
  final TextEditingController _uid = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _levels =
      Api.instance.rows(Api.instance.client.from('school_levels').select('id, name').order('order_index'));
  String? _level;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _uid.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final uid = await scanCard(context);
    if (uid != null) setState(() => _uid.text = uid);
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2 || _level == null) {
      setState(() => _error = 'Escribe tu nombre y elige tu curso.');
      return;
    }
    if (_uid.text.trim().isNotEmpty && !isValidUid(_uid.text)) {
      setState(() => _error = 'Revisa el código de la tarjeta.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.client.rpc('submit_enrollment', params: {
        'p_full_name': _name.text.trim(),
        'p_phone': _phone.text.trim(),
        'p_level_id': _level,
        'p_card_uid': _uid.text.trim().isEmpty ? null : normalizeUid(_uid.text),
      });
      await Api.instance.access(force: true);
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
            Text('Mi tarjeta y curso', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('El colegio revisará tus datos antes de activar la tarjeta.', style: TextStyle(color: context.muted)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _levels,
              builder: (context, s) => DropdownButtonFormField<String>(
                initialValue: _level,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Mi curso'),
                items: [
                  for (final l in s.data ?? const <Map<String, dynamic>>[])
                    DropdownMenuItem(value: l['id'] as String, child: Text(l['name'] as String)),
                ],
                onChanged: (v) => setState(() => _level = v),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _uid,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Código de la tarjeta (opcional)',
                hintText: '04:A2:3B:5C',
                suffixIcon: IconButton(
                  tooltip: 'Leer con NFC',
                  icon: const Icon(Icons.contactless_rounded),
                  onPressed: _scan,
                ),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: context.brandText))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Enviar para revisión'),
            ),
          ]),
        ),
      );
}
