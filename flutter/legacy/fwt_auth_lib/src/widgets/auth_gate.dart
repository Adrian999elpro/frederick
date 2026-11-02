import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access.dart';
import '../auth_service.dart';
import '../screens/login_screen.dart';
import '../screens/profile_screen.dart';

/// Decide qué mostrar: acceso (sin sesión), cambio obligatorio de contraseña, o la app.
/// También cierra la sesión por inactividad.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.signedIn});

  /// Construye la aplicación para un usuario autenticado y activo.
  final Widget Function(BuildContext context, Access access) signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Access?> _future;
  late final StreamSubscription<AuthState> _sub;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _sub = FwtAuth.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.signedOut) _reload();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load(force: true));
  }

  Future<Access?> _load({bool force = false}) async {
    final auth = FwtAuth.instance;
    if (auth.client.auth.currentSession == null) return null;
    try {
      final a = await auth.access(force: force);
      if (a == null) await auth.signOut(); // cuenta desactivada
      return a;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Access?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final a = snap.data;
          if (a == null) return const LoginScreen();
          return _IdleGuard(
            minutes: FwtAuth.instance.config.idleMinutes,
            onTimeout: () => FwtAuth.instance.signOut(),
            child: a.mustChangePassword ? ProfileScreen(access: a, forced: true, onChanged: _reload) : widget.signedIn(context, a),
          );
        },
      );
}

class _IdleGuard extends StatefulWidget {
  const _IdleGuard({required this.minutes, required this.onTimeout, required this.child});
  final int minutes;
  final VoidCallback onTimeout;
  final Widget child;

  @override
  State<_IdleGuard> createState() => _IdleGuardState();
}

class _IdleGuardState extends State<_IdleGuard> with WidgetsBindingObserver {
  DateTime _last = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _check() {
    if (DateTime.now().difference(_last) > Duration(minutes: widget.minutes)) {
      _last = DateTime.now();
      widget.onTimeout();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _last = DateTime.now(),
        child: widget.child,
      );
}
