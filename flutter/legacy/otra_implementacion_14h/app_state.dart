import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'nfc.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Estado global: sesión, permisos, tema y modo terminal.
class AppState extends ChangeNotifier {
  AppState(this._prefs);

  final SharedPreferences _prefs;
  StreamSubscription<AuthState>? _authSub;

  SupabaseClient get client => Supabase.instance.client;

  bool booting = true;
  Access? access;
  ThemeMode themeMode = ThemeMode.system;
  bool terminalActive = false;
  String terminalMode = 'announcements';

  /// Sube al cambiar la foto de perfil para que los avatares se vuelvan a cargar.
  int photoRev = 0;

  Future<void> init() async {
    final saved = _prefs.getString('theme_mode');
    themeMode = saved == 'light'
        ? ThemeMode.light
        : saved == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    terminalActive = _prefs.getBool('terminal_active') ?? false;
    terminalMode = _prefs.getString('terminal_mode') ?? 'announcements';

    _authSub = client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut && access != null) {
        access = null;
        notifyListeners();
      }
    });

    if (client.auth.currentSession != null) {
      try {
        await loadAccess();
      } catch (_) {
        // Sin conexión: se conserva la sesión y se reintenta al entrar.
      }
    }
    booting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Perfil, rol y permisos en una sola llamada. Devuelve null si la cuenta no está activa.
  Future<Access?> loadAccess() async {
    final data = await client.rpc('get_my_access');
    if (data == null) {
      access = null;
      await client.auth.signOut(scope: SignOutScope.local);
    } else {
      access = Access.fromJson(Map<String, dynamic>.from(data as Map));
      if (terminalActive && !access!.can('terminal.operate')) {
        await setTerminal(false);
      }
    }
    notifyListeners();
    return access;
  }

  /// Inicio de sesión mediante la función de servidor (límite de intentos y cuenta activa verificados allí).
  Future<void> signIn(String email, String password) async {
    try {
      final res = await client.functions.invoke('auth-login', body: {'email': email.trim(), 'password': password});
      final session = (res.data as Map)['session'] as Map;
      await client.auth.setSession(session['refresh_token'] as String);
    } on FunctionException catch (e) {
      final d = e.details;
      throw AuthFailure(d is Map && d['message'] is String ? d['message'] as String : 'No se pudo iniciar sesión.');
    } catch (_) {
      throw AuthFailure('No se pudo iniciar sesión. Revisa tu conexión a internet.');
    }
    Access? a;
    try {
      a = await loadAccess();
    } catch (_) {
      throw AuthFailure('Entraste, pero no se pudo cargar tu perfil. Inténtalo de nuevo.');
    }
    if (a == null) throw AuthFailure('Tu cuenta no tiene acceso activo.');
  }

  Future<void> signOut() async {
    await setTerminal(false);
    access = null;
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _prefs.setString('theme_mode', mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system');
    notifyListeners();
  }

  Future<void> setTerminal(bool active) async {
    if (!active && terminalActive) await NfcBridge.unpin();
    terminalActive = active;
    await _prefs.setBool('terminal_active', active);
    notifyListeners();
  }

  Future<void> setTerminalMode(String mode) async {
    terminalMode = mode;
    await _prefs.setString('terminal_mode', mode);
    notifyListeners();
  }

  void bumpPhoto() {
    photoRev++;
    notifyListeners();
  }
}

/// Acceso al estado desde cualquier pantalla: AppScope.of(context).
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({Key? key, required AppState state, required Widget child})
      : super(key: key, notifier: state, child: child);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }

  /// Para usar dentro de initState y callbacks (no se suscribe a los cambios).
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }
}
