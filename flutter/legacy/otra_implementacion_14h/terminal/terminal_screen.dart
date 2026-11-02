import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../nfc.dart';
import '../theme.dart';
import '../ui.dart';
import 'terminal_modes.dart';

/// Modo y permiso del servidor que exige cada uno (la web usa los mismos).
const terminalModes = <(String, String, String, IconData, String)>[
  ('attendance', 'Asistencia', 'nfc.attendance', Icons.fact_check_rounded, 'Registrar la asistencia de cada estudiante'),
  ('council', 'Consejo estudiantil', 'polls.operate', Icons.groups_rounded, 'Votación del consejo con tarjeta'),
  ('card-registration', 'Registrar tarjetas', 'terminal.operate', Icons.nfc_rounded, 'Crear cuenta y solicitar tarjeta'),
  ('announcements', 'Novedades y perfiles', 'terminal.operate', Icons.campaign_rounded, 'Anuncios y consulta de notas con tarjeta'),
  ('custom-polls', 'Votaciones', 'polls.operate', Icons.how_to_vote_rounded, 'Votaciones personalizadas con tarjeta'),
];

(String, String, String, IconData, String) _modeInfo(String id) =>
    terminalModes.firstWhere((m) => m.$1 == id, orElse: () => terminalModes[3]);

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  bool _controlOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pin());
  }

  Future<void> _pin() async {
    try {
      final result = await NfcBridge.pin();
      if (!mounted) return;
      showMsg(
        context,
        result == 'dedicated'
            ? 'Bloqueo de dispositivo dedicado activo.'
            : 'Terminal activo. Acepta la fijación de pantalla de Android para limitar el cambio de app.',
      );
    } on NfcException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    }
  }

  Future<void> _control() async {
    if (_controlOpen) return;
    _controlOpen = true;
    final app = AppScope.of(context);
    try {
      final uid = await askCard(context, title: 'Tarjeta del encargado');
      if (uid == null || !mounted) return;
      final String ticket;
      try {
        ticket = await Api.authorizeTerminalCard(uid);
      } catch (_) {
        if (mounted) {
          showMsg(context, 'Se necesita una tarjeta activa con permiso para desbloquear el terminal.', error: true);
        }
        return;
      }
      if (!mounted) return;
      final access = app.access!;
      final allowed = terminalModes.where((m) => access.can(m.$3)).toList();
      final choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ControlSheet(modes: allowed, current: app.terminalMode),
      );
      if (choice == null || !mounted) return;
      if (choice == 'unlock') {
        bool ok = false;
        try {
          ok = await Api.consumeTerminalUnlock(ticket);
        } catch (_) {}
        if (!mounted) return;
        if (ok) {
          await app.setTerminal(false);
        } else {
          showMsg(context, 'Autorización vencida. Lee otra vez la tarjeta del encargado.', error: true);
        }
      } else {
        await app.setTerminalMode(choice);
      }
    } finally {
      _controlOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final info = _modeInfo(app.terminalMode);
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _control();
      },
      child: Scaffold(
        body: Column(
          children: [
            GradientHero(
              bottomRadius: 24,
              child: Row(
                children: [
                  const FwtLogo(size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TERMINAL ESCOLAR',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          info.$2,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: FwtColors.ink,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: _control,
                    icon: const Icon(Icons.key_rounded, size: 20),
                    label: const Text('Encargado'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(app.terminalMode),
                  child: switch (app.terminalMode) {
                    'attendance' => const AttendanceMode(),
                    'council' => const PollsMode(kind: 'council'),
                    'custom-polls' => const PollsMode(kind: 'custom'),
                    'card-registration' => const RegisterMode(),
                    _ => const ConsultMode(),
                  },
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: cs.surface,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: SafeArea(
                top: false,
                child: Text(
                  'Pulsa «Encargado» o el botón Atrás y acerca la tarjeta del encargado para cambiar de modo o salir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlSheet extends StatefulWidget {
  const _ControlSheet({required this.modes, required this.current});
  final List<(String, String, String, IconData, String)> modes;
  final String current;

  @override
  State<_ControlSheet> createState() => _ControlSheetState();
}

class _ControlSheetState extends State<_ControlSheet> {
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    // La autorización del encargado caduca a los 60 segundos.
    _timeout = Timer(const Duration(seconds: 60), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Control del terminal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Tarjeta autorizada. Elige un modo.', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            for (final m in widget.modes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FwtCard(
                  onTap: () => Navigator.pop(context, m.$1),
                  color: m.$1 == widget.current ? cs.primary.withValues(alpha: 0.1) : null,
                  child: Row(
                    children: [
                      Icon(m.$4, color: cs.primary, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.$2, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            Text(m.$5, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (m.$1 == widget.current) Icon(Icons.check_circle_rounded, color: cs.primary),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'unlock'),
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Desbloquear app'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ],
        ),
      ),
    );
  }
}
