import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../ui.dart';

/// Votación con tarjeta (consejo y votaciones personalizadas):
/// 1) lee la tarjeta, 2) el servidor entrega un turno de 90 s, 3) se elige y se confirma.
Future<void> startPollVote(BuildContext context, Json poll, {VoidCallback? onDone}) async {
  final uid = await askCard(context, title: 'Acerca tu tarjeta para votar');
  if (uid == null || !context.mounted) return;
  Json scan;
  try {
    scan = await Api.scanPollCard('${poll['id']}', uid);
  } catch (e) {
    if (context.mounted) showMsg(context, friendlyError(e, 'No se pudo validar la tarjeta.'), error: true);
    return;
  }
  if (!context.mounted) return;
  final voted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _BallotSheet(poll: poll, scan: scan),
  );
  if (voted == true) onDone?.call();
}

class _BallotSheet extends StatefulWidget {
  const _BallotSheet({required this.poll, required this.scan});
  final Json poll;
  final Json scan;

  @override
  State<_BallotSheet> createState() => _BallotSheetState();
}

class _BallotSheetState extends State<_BallotSheet> {
  static const _seconds = 90;
  String? _selected;
  int _left = _seconds;
  Timer? _timer;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        Navigator.pop(context, false);
        return;
      }
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Json> get _options =>
      ((widget.poll['school_poll_options'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _confirm() async {
    final choice = _options.firstWhere((o) => '${o['id']}' == _selected, orElse: () => <String, dynamic>{});
    final ok = await confirmDialog(
      context,
      'Vas a votar por: ${choice['label'] ?? ''}. No podrás cambiarlo después.',
      okLabel: 'Emitir voto',
      title: 'Confirmar voto',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.castPollVote('${widget.scan['ticket']}', _selected!);
      _timer?.cancel();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'No se registró el voto. Lee de nuevo la tarjeta.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secret = widget.poll['secret'] != false;
    if (_done) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, size: 72, color: Color(0xFF15803D)),
              const SizedBox(height: 12),
              const Text('Voto registrado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Gracias por participar.', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Terminar')),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Turno de ${widget.scan['student_name'] ?? ''}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
                Pill('$_left s', color: _left <= 15 ? cs.error : cs.primary),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              secret ? 'Tu voto es secreto.' : 'Tu voto aparecerá con tu nombre en los resultados.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            for (final o in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OptionTile(
                  label: '${o['label']}',
                  selected: _selected == '${o['id']}',
                  onTap: () => setState(() => _selected = '${o['id']}'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_selected == null || _busy) ? null : _confirm,
              child: Text(_busy ? 'Enviando…' : 'Confirmar voto'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar turno'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opción de papeleta: tarjeta grande y táctil con marca de selección.
class OptionTile extends StatelessWidget {
  const OptionTile({super.key, required this.label, required this.selected, required this.onTap, this.leading, this.subtitle});
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (subtitle != null) Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? cs.primary : cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
