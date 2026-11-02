import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/nfc.dart';
import '../core/terminal_prefs.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'admin_panel.dart';
import 'modes.dart';
import 'pin_gate.dart';
import 'terminal_context.dart';

final terminalModes = <TerminalMode>[
  TerminalMode('profile', 'Perfil con tarjeta', Icons.badge_rounded, 'terminal.operate', (c) => ProfileCardMode(ctx: c)),
  TerminalMode('announcements', 'Anuncios', Icons.campaign_rounded, 'terminal.operate', (c) => AnnouncementsMode(ctx: c)),
  TerminalMode('attendance', 'Asistencia', Icons.fact_check_rounded, 'nfc.attendance', (c) => AttendanceMode(ctx: c)),
  TerminalMode('polls', 'Votación', Icons.how_to_vote_rounded, 'polls.operate', (c) => PollsMode(ctx: c)),
  TerminalMode('card-registration', 'Registrar tarjetas', Icons.nfc_rounded, 'cards.register', (c) => RegistrationMode(ctx: c)),
];

/// Teléfono del colegio. La sesión administrativa se mantiene abierta y la tarjeta decide quién
/// es quién: un administrador abre el panel (modo, votaciones, desbloqueo); cualquier otra
/// persona ve su perfil. El modo y la votación fijados se conservan hasta que un administrador
/// los cambie con su tarjeta o se cierre la sesión.
class TerminalShell extends StatefulWidget {
  const TerminalShell({super.key, required this.access, required this.onExit});
  final Access access;
  final VoidCallback onExit;

  @override
  State<TerminalShell> createState() => _TerminalShellState();
}

class _TerminalShellState extends State<TerminalShell> {
  String _mode = 'profile';
  String? _pollId;
  bool _loaded = false;
  bool _panelOpen = false;
  bool _controlling = false;
  String? _notice;

  /// true = todavía no existe ninguna tarjeta de administrador: hay que registrar la primera.
  bool _needsAdminCard = false;
  bool _registeringCard = false;

  List<TerminalMode> get _allowed => terminalModes.where((m) => widget.access.can(m.permission)).toList();

  @override
  void initState() {
    super.initState();
    _restore();
    _pin();
    _checkAdminCard();
  }

  /// Instalación nueva: sin tarjeta de administrador nadie podría abrir el panel ni registrar
  /// tarjetas. La cuenta administrativa de este teléfono registra la primera (una sola vez).
  Future<void> _checkAdminCard() async {
    if (widget.access.role != 'admin' || !widget.access.can('nfc.manage')) return;
    try {
      final registered = await Api.instance.client.rpc('admin_card_registration_status');
      if (mounted) setState(() => _needsAdminCard = registered != true);
    } catch (_) {}
  }

  Future<void> _registerFirstAdminCard() async {
    if (_registeringCard) return;
    final ok = await confirm(
      context,
      'La tarjeta que acerques quedará vinculada a tu cuenta de administrador. Esto solo se puede hacer una vez; después se pedirá tarjeta y PIN.',
      okLabel: 'Leer tarjeta',
    );
    if (!ok || !mounted) return;
    final uid = await scanCard(context, title: 'Acerca tu tarjeta de administrador');
    if (uid == null || !mounted) return;
    setState(() => _registeringCard = true);
    try {
      await Api.instance.client.rpc('register_initial_admin_card', params: {'p_card_uid': uid});
      if (!mounted) return;
      setState(() => _needsAdminCard = false);
      snack(context, 'Tarjeta registrada. Acércala otra vez para crear tu PIN.');
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo registrar la tarjeta. Inténtalo de nuevo.'), error: true);
      _checkAdminCard();
    } finally {
      if (mounted) setState(() => _registeringCard = false);
    }
  }

  Future<void> _restore() async {
    final saved = await TerminalPrefs.load();
    if (!mounted) return;
    setState(() {
      _mode = saved.mode;
      _pollId = saved.pollId;
      _loaded = true;
    });
  }

  Future<void> _pin() async {
    try {
      final mode = await Nfc.pin();
      if (mounted) {
        setState(() => _notice = mode == 'dedicated'
            ? 'Bloqueo de dispositivo dedicado activo.'
            : 'Terminal activo. Acepta la fijación de pantalla de Android para limitar el cambio de app.');
      }
    } catch (e) {
      if (mounted) setState(() => _notice = friendlyError(e, 'Activa la fijación de pantalla en los ajustes de Android.'));
    }
  }

  void _setMode(String mode, {String? pollId}) {
    setState(() {
      _mode = mode;
      _pollId = pollId ?? _pollId;
    });
    TerminalPrefs.save(_mode, _pollId);
  }

  /// Una sola llamada al servidor decide si la tarjeta es de un administrador o de una persona.
  Future<CardScan> _scan(String uid) async {
    final data = await Api.instance.rpcMap('terminal_scan', {'p_card_uid': uid});
    if (data['kind'] == 'admin') {
      return CardScan.admin('${data['ticket']}', '${data['name'] ?? ''}', pinSet: data['pin_set'] == true, pinOk: data['pin_ok'] == true);
    }
    return CardScan.person(Map<String, dynamic>.from(data['profile'] as Map), uid);
  }

  /// Tarjeta de administrador leída: pide el PIN (si no hay sesión abierta) y abre el panel.
  Future<void> _openPanel(CardScan scan) async {
    if (_panelOpen || !mounted) return;
    _panelOpen = true;
    try {
      if (!await askAdminPin(context, scan) || !mounted) return;
      final ticket = scan.ticket!;
      final result = await Navigator.of(context).push<String>(MaterialPageRoute<String>(
        builder: (_) => AdminPanelPage(
          ctx: _ctx(),
          modes: _allowed.where((m) => m.id != 'polls').toList(),
          ticket: ticket,
          reauthorize: _reauthorize,
        ),
      ));
      if (result == 'unlocked') widget.onExit();
    } finally {
      _panelOpen = false;
    }
  }

  /// Pide la tarjeta de administrador y devuelve su lectura (sin PIN todavía), o null.
  Future<CardScan?> _scanAdmin() async {
    final uid = await scanCard(context, title: 'Acerca la tarjeta del administrador');
    if (uid == null || !mounted) return null;
    try {
      final result = await _scan(uid);
      if (!result.isAdmin) {
        if (mounted) snack(context, 'Esa tarjeta no es de un administrador autorizado.', error: true);
        return null;
      }
      return result;
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo verificar la tarjeta. Revisa la conexión.'), error: true);
      return null;
    }
  }

  /// Tarjeta + PIN otra vez (para desbloquear si pasó mucho tiempo). Devuelve el permiso nuevo.
  Future<String?> _reauthorize() async {
    final scan = await _scanAdmin();
    if (scan == null || !mounted) return null;
    return await askAdminPin(context, scan) ? scan.ticket : null;
  }

  /// Lee una tarjeta ya leída por otra pantalla y abre la sesión de administrador con el PIN.
  Future<bool> _adminUnlock(String uid) async {
    try {
      final result = await _scan(uid);
      if (!result.isAdmin) {
        if (mounted) snack(context, 'Esa tarjeta no es de un administrador autorizado.', error: true);
        return false;
      }
      if (!mounted) return false;
      return askAdminPin(context, result);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo verificar la tarjeta. Revisa la conexión.'), error: true);
      return false;
    }
  }

  /// Botón «Encargado»: abre el panel con la tarjeta, sin esperar a otro modo.
  Future<void> _control() async {
    if (_controlling || _panelOpen) return;
    _controlling = true;
    try {
      final scan = await _scanAdmin();
      if (scan != null && mounted) await _openPanel(scan);
    } finally {
      _controlling = false;
    }
  }

  TerminalCtx _ctx() => TerminalCtx(
        access: widget.access,
        mode: _mode,
        pollId: _pollId,
        scan: _scan,
        openPanel: _openPanel,
        adminUnlock: _adminUnlock,
        setMode: _setMode,
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final modes = _allowed;
    final current = modes.firstWhere((m) => m.id == _mode, orElse: () => modes.first);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _control();
      },
      child: Scaffold(
        body: Column(children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 12, 14),
            decoration: const BoxDecoration(
              gradient: Fwt.heroGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(children: [
              const SchoolLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('TERMINAL ESCOLAR',
                      style: TextStyle(color: Fwt.gold, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
                  Text(current.label, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                ]),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Fwt.brandDeep,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _control,
                icon: const Icon(Icons.admin_panel_settings_rounded, size: 20),
                label: const Text('Encargado'),
              ),
            ]),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_notice!, textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 12)),
            ),
          if (_needsAdminCard)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Falta la tarjeta de administrador', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      'Este terminal aún no tiene ninguna. Regístrala ahora para poder abrir el panel, crear tu PIN y registrar las tarjetas del colegio.',
                      style: TextStyle(color: context.muted, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _registeringCard ? null : _registerFirstAdminCard,
                      icon: const Icon(Icons.nfc_rounded),
                      label: const Text('Registrar mi tarjeta de administrador'),
                    ),
                  ]),
                ),
              ),
            ),
          Expanded(child: KeyedSubtree(key: ValueKey(current.id), child: current.build(_ctx()))),
        ]),
      ),
    );
  }
}
