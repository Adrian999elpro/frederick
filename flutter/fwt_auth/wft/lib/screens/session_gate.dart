import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../terminal/terminal_shell.dart';
import '../widgets/common.dart';
import 'shell.dart';

enum _View { terminal, unlocked, account }

/// Tras iniciar sesión con la cuenta administrativa, el teléfono arranca como terminal escolar:
/// estudiantes y docentes acercan su tarjeta para ver su perfil y sus datos.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late Future<Access?> _boot = Api.instance.access(force: true);
  _View _view = _View.terminal;

  @override
  Widget build(BuildContext context) => FutureBuilder<Access?>(
        future: _boot,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: EmptyState(
                icon: Icons.cloud_off_rounded,
                text: friendlyError(snapshot.error!),
                actionLabel: 'Reintentar',
                onAction: () => setState(() => _boot = Api.instance.access(force: true)),
              ),
            );
          }
          final access = snapshot.data;
          if (access == null) {
            // Cuenta desactivada o sin perfil: se cierra la sesión.
            WidgetsBinding.instance.addPostFrameCallback((_) => Api.instance.signOut());
            return const Scaffold(
              body: EmptyState(icon: Icons.lock_outline_rounded, text: 'Tu cuenta no está activa. Consulta con el colegio.'),
            );
          }
          if (!access.can('terminal.operate')) return const _NotAuthorized();
          return switch (_view) {
            _View.terminal => TerminalShell(access: access, onExit: () => setState(() => _view = _View.unlocked)),
            _View.account => AppShell(access: access),
            _View.unlocked => _Unlocked(
                access: access,
                onTerminal: () => setState(() => _view = _View.terminal),
                onAccount: () => setState(() => _view = _View.account),
              ),
          };
        },
      );
}

class _NotAuthorized extends StatelessWidget {
  const _NotAuthorized();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SchoolLogo(size: 72),
              const SizedBox(height: 22),
              Text('Esta cuenta no puede usar este teléfono',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text(
                'El teléfono del colegio solo se inicia con una cuenta administrativa autorizada. '
                'Los estudiantes y docentes no inician sesión: acercan su tarjeta al teléfono del colegio para ver su perfil y sus datos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted, height: 1.45),
              ),
              const SizedBox(height: 26),
              FilledButton(onPressed: () => Api.instance.signOut(), child: const Text('Cerrar sesión')),
            ]),
          ),
        ),
      );
}

class _Unlocked extends StatelessWidget {
  const _Unlocked({required this.access, required this.onTerminal, required this.onAccount});
  final Access access;
  final VoidCallback onTerminal;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          HeroHeader(
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 40, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SchoolLogo(size: 56),
              const SizedBox(height: 18),
              const Text('Terminal desbloqueado',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Sesión de ${access.fullName.isEmpty ? access.email : access.fullName}', style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              FilledButton.icon(onPressed: onTerminal, icon: const Icon(Icons.contactless_rounded), label: const Text('Volver al terminal')),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: onAccount, icon: const Icon(Icons.person_rounded), label: const Text('Abrir mi cuenta')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirm(context, '¿Cerrar la sesión administrativa de este teléfono?', okLabel: 'Cerrar sesión')) {
                    await Api.instance.signOut();
                  }
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
              ),
            ]),
          ),
        ]),
      );
}
