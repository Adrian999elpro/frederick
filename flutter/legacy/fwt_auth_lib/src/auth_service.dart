import 'package:supabase_flutter/supabase_flutter.dart';

import 'access.dart';
import 'config.dart';
import 'secure_storage.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Traduce los errores del servidor a mensajes para la persona usuaria.
String friendlyError(Object e, [String fallback = 'No se pudo completar la operación.']) {
  const map = {
    'already_voted': 'Ya registraste tu voto en esta votación.',
    'election_not_open': 'Esta votación no está abierta.',
    'invalid_list': 'La lista seleccionada no es válida.',
    'forbidden': 'No tienes permiso para esta acción.',
    'results_hidden': 'Los resultados se publican cuando la votación se cierre.',
  };
  final m = e is PostgrestException ? e.message : e.toString();
  for (final k in map.keys) {
    if (m.contains(k)) return map[k]!;
  }
  return fallback;
}

/// Punto único de acceso a la autenticación. Inicializar una vez con [FwtAuth.init].
class FwtAuth {
  FwtAuth._(this.config);
  static late FwtAuth instance;

  final FwtConfig config;
  SupabaseClient get client => Supabase.instance.client;

  Access? _access;
  DateTime _accessAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> init(FwtConfig config, {bool secureStorage = true}) async {
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.anonKey,
      authOptions: FlutterAuthClientOptions(localStorage: secureStorage ? SecureLocalStorage() : null),
    );
    instance = FwtAuth._(config);
  }

  /// Inicio de sesión vía Edge Function (límite de intentos y cuenta activa verificados en el servidor).
  Future<void> signIn(String email, String password) async {
    try {
      final res = await client.functions.invoke('auth-login', body: {'email': email.trim(), 'password': password});
      final session = (res.data as Map)['session'] as Map;
      await client.auth.setSession(session['refresh_token'] as String);
    } on FunctionException catch (e) {
      final d = e.details;
      throw AuthFailure(d is Map && d['message'] is String ? d['message'] as String : 'No se pudo iniciar sesión.');
    } catch (_) {
      throw AuthFailure('No se pudo iniciar sesión.');
    }
  }

  Future<void> signUp({required String email, required String password, required String fullName}) async {
    try {
      await client.auth.signUp(email: email.trim(), password: password, data: {'full_name': fullName.trim()});
    } catch (_) {
      // Mensaje único: no se revela si el correo existe ni por qué se rechazó.
      throw AuthFailure('No pudimos completar el registro. Revisa los datos o consulta con el administrador.');
    }
  }

  /// Siempre parece exitoso: no revela si el correo está registrado.
  Future<void> sendRecovery(String email) async {
    try {
      await client.auth.resetPasswordForEmail(email.trim(),
          redirectTo: config.resetRedirectUrl.isEmpty ? null : config.resetRedirectUrl);
    } catch (_) {}
  }

  Future<String> registrationMode() async {
    try {
      return (await client.rpc('public_registration_mode')) as String? ?? 'closed';
    } catch (_) {
      return 'closed';
    }
  }

  Future<void> signOut() async {
    _access = null;
    await client.auth.signOut(scope: SignOutScope.local);
  }

  /// Perfil + rol + permisos en una sola llamada, con caché de 5 minutos.
  /// Devuelve null si no hay sesión o la cuenta está desactivada.
  Future<Access?> access({bool force = false}) async {
    if (!force && _access != null && DateTime.now().difference(_accessAt) < const Duration(minutes: 5)) {
      return _access;
    }
    final data = await client.rpc('get_my_access');
    if (data == null) {
      _access = null;
      return null;
    }
    _access = Access.fromJson(Map<String, dynamic>.from(data as Map));
    _accessAt = DateTime.now();
    return _access;
  }

  Future<void> updateProfile({required String fullName, String? phone}) async {
    final a = await access();
    if (a == null) throw AuthFailure('Sesión no válida.');
    await client.from('profiles').update({'full_name': fullName.trim(), 'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim()}).eq('id', a.id);
    await access(force: true);
  }

  Future<void> changePassword(String current, String next) async {
    final a = await access();
    if (a == null) throw AuthFailure('Sesión no válida.');
    try {
      await signIn(a.email, current); // reautenticación
      await client.auth.updateUser(UserAttributes(password: next));
      await client.rpc('ack_password_changed');
      await access(force: true);
    } on AuthFailure {
      throw AuthFailure('La contraseña actual no es correcta.');
    } catch (_) {
      throw AuthFailure('No se pudo cambiar la contraseña.');
    }
  }
}
