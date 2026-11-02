import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../nfc.dart';
import '../theme.dart';
import '../ui.dart';

class CardTab extends StatefulWidget {
  const CardTab({super.key});

  @override
  State<CardTab> createState() => _CardTabState();
}

class _CardTabState extends State<CardTab> {
  late Future<List<Object?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Object?>> _load() {
    final uid = AppScope.read(context).access!.id;
    return Future.wait<Object?>([
      Api.myStudentDetails(uid).catchError((Object _) => null),
      Api.myCustomization(uid).catchError((Object _) => null),
      Api.myEnrollment(uid).catchError((Object _) => null),
    ]);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openEnrollment() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _EnrollmentSheet(),
    );
    if (sent == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final access = AppScope.of(context).access!;
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await _future;
        } catch (_) {}
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHero(
            child: const Text('Mi carnet',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: AsyncView<List<Object?>>(
              future: _future,
              onRetry: _reload,
              builder: (context, data) {
                final details = data[0] as Json?;
                final custom = data[1] as Json?;
                final enrollment = data[2] as Json?;
                final level = (details?['school_levels'] as Map?)?['name'];
                final code = details?['student_code'];
                final nickname = '${custom?['nickname'] ?? ''}'.trim();
                final status = enrollment?['status'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _IdCard(
                      name: nickname.isNotEmpty ? nickname : access.fullName,
                      fullName: access.fullName,
                      userId: access.id,
                      level: level == null ? null : '$level',
                      code: code == null ? null : '$code',
                      headline: '${custom?['headline'] ?? ''}'.trim(),
                    ),
                    const SectionTitle('Mi tarjeta NFC'),
                    FwtCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                status == 'approved'
                                    ? Icons.verified_rounded
                                    : status == 'pending'
                                        ? Icons.hourglass_top_rounded
                                        : status == 'rejected'
                                            ? Icons.error_outline_rounded
                                            : Icons.contactless_outlined,
                                color: status == 'approved'
                                    ? FwtColors.ok
                                    : status == 'rejected'
                                        ? FwtColors.danger
                                        : FwtColors.gold,
                                size: 30,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  switch (status) {
                                    'approved' => 'Tarjeta vinculada y aprobada',
                                    'pending' => 'Solicitud en revisión por el colegio',
                                    'rejected' => 'Solicitud rechazada. Revisa tus datos y vuelve a enviarla.',
                                    _ => 'Aún no has solicitado vincular tu tarjeta',
                                  },
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          if (enrollment?['card_uid'] != null) ...[
                            const SizedBox(height: 8),
                            Text('Código: ${enrollment!['card_uid']}',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _openEnrollment,
                            icon: const Icon(Icons.nfc_rounded),
                            label: Text(status == null ? 'Vincular mi tarjeta' : 'Actualizar mis datos'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'El colegio revisa tus datos antes de activar la tarjeta. Cuida tu tarjeta: es personal.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _IdCard extends StatelessWidget {
  const _IdCard({
    required this.name,
    required this.fullName,
    required this.userId,
    required this.level,
    required this.code,
    required this.headline,
  });
  final String name;
  final String fullName;
  final String userId;
  final String? level;
  final String? code;
  final String headline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: FwtColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: FwtColors.brand.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FwtLogo(size: 40),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'CARNET ESTUDIANTIL',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 13),
                ),
              ),
              Icon(Icons.contactless_rounded, color: Colors.white.withValues(alpha: 0.85)),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              UserAvatar(name: fullName, userId: userId, size: 84, ring: true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    if (name != fullName)
                      Text(fullName, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
                    const SizedBox(height: 6),
                    if (level != null) const SizedBox(height: 0),
                    if (level != null) Pill(level!, color: FwtColors.gold),
                  ],
                ),
              ),
            ],
          ),
          if (headline.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(headline, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                code == null ? 'Código pendiente' : 'Código  $code',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              Text(AppConfig.tagline, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnrollmentSheet extends StatefulWidget {
  const _EnrollmentSheet();

  @override
  State<_EnrollmentSheet> createState() => _EnrollmentSheetState();
}

class _EnrollmentSheetState extends State<_EnrollmentSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  late final Future<List<Json>> _levels = Api.levels();
  String? _levelId;
  String? _card;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = AppScope.read(context).access!;
    _name.text = a.fullName;
    _phone.text = a.phone ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _readCard() async {
    final uid = await askCard(context);
    if (uid != null && mounted) setState(() => _card = uid);
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Escribe tu nombre completo.');
      return;
    }
    if (_levelId == null) {
      setState(() => _error = 'Elige tu curso.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.submitEnrollment(fullName: _name.text, phone: _phone.text, levelId: _levelId!, cardUid: _card);
      if (!mounted) return;
      showMsg(context, 'Datos enviados. El colegio los revisará.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Vincular mi tarjeta', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('El colegio revisará tus datos antes de activarla.', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Json>>(
              future: _levels,
              builder: (context, snap) {
                final levels = snap.data ?? const <Json>[];
                if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final l in levels)
                      ChoiceChip(
                        label: Text('${l['name']}'),
                        selected: _levelId == l['id'],
                        onSelected: (_) => setState(() => _levelId = '${l['id']}'),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _readCard,
              icon: Icon(_card == null ? Icons.nfc_rounded : Icons.check_circle_rounded),
              label: Text(_card == null ? 'Leer mi tarjeta con NFC' : 'Tarjeta leída: $_card'),
            ),
            const SizedBox(height: 6),
            Text('Puedes enviar tus datos sin tarjeta y vincularla después.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Enviando…' : 'Enviar para revisión')),
          ],
        ),
      ),
    );
  }
}
