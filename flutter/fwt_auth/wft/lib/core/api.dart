import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'errors.dart';
import 'terminal_prefs.dart';

/// Perfil, rol y permisos de la persona que inició sesión.
class Access {
  Access({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.mustChangePassword,
    required this.permissions,
  });

  factory Access.fromJson(Map<String, dynamic> json) => Access(
        id: json['id'] as String,
        email: (json['email'] as String?) ?? '',
        fullName: (json['full_name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        role: (json['role'] as String?) ?? '',
        mustChangePassword: json['must_change_password'] == true,
        permissions: ((json['permissions'] as List?) ?? const []).map((e) => '$e').toList(),
      );

  final String id;
  final String email;
  final String fullName;
  final String phone;
  final String role;
  final bool mustChangePassword;
  final List<String> permissions;

  bool can(String permission) => permissions.contains(permission);
  bool get isStudent => role == 'estudiante';
  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.first.isEmpty ? 'bienvenido' : parts.first;
  }
}

const _secure = FlutterSecureStorage();
const _sessionKey = 'fwt_session';

/// Guarda la sesión en el almacén seguro de Android (Keystore).
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _secure.containsKey(key: _sessionKey);

  @override
  Future<String?> accessToken() => _secure.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => _secure.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secure.write(key: _sessionKey, value: persistSessionString);
}

/// Punto único de acceso al servidor. La autorización real la exigen RLS y las
/// funciones de Supabase; esta clase solo las invoca.
class Api {
  Api._();
  static final Api instance = Api._();

  SupabaseClient get client => Supabase.instance.client;
  Access? _access;
  DateTime _accessAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> init() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureLocalStorage()),
    );
  }

  bool get hasSession => client.auth.currentSession != null;

  /// Inicio de sesión mediante la función del servidor (límite de intentos y cuenta activa).
  Future<void> signIn(String email, String password) async {
    try {
      final res = await client.functions.invoke('auth-login', body: {'email': email.trim(), 'password': password});
      final session = (res.data as Map)['session'] as Map;
      await client.auth.setSession(session['refresh_token'] as String);
      _access = null;
    } on FunctionException catch (e) {
      final d = e.details;
      throw AuthFailure(d is Map && d['message'] is String ? d['message'] as String : 'No se pudo iniciar sesión.');
    } catch (_) {
      throw AuthFailure('No se pudo iniciar sesión. Revisa tu conexión.');
    }
  }

  /// Registra una persona nueva con su tarjeta (solo administradores). Crea una cuenta
  /// pendiente: la persona la activa después en la web con un código del terminal.
  Future<Map<String, dynamic>> registerPerson({required String uid, required String name, required String role, String? levelId}) async {
    try {
      final res = await client.functions.invoke('terminal-register-card', body: {'card_uid': uid, 'full_name': name, 'role': role, 'level_id': levelId});
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      final code = d is Map ? '${d['error']}' : '';
      if (code == 'card_already_assigned') {
        final owner = d is Map ? '${d['owner'] ?? ''}' : '';
        throw AuthFailure(owner.isEmpty ? 'Esta tarjeta ya está registrada.' : 'Esta tarjeta ya está registrada a nombre de $owner.');
      }
      if (code == 'admin_session_required') throw AuthFailure('Un administrador debe acercar su tarjeta e ingresar su PIN.');
      if (code == 'forbidden') throw AuthFailure('Solo un administrador puede registrar tarjetas.');
      if (code == 'invalid_name') throw AuthFailure('Revisa el nombre.');
      throw AuthFailure('No se pudo registrar. Inténtalo de nuevo.');
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('No se pudo registrar. Revisa la conexión.');
    }
  }

  /// Parece exitoso siempre: no revela si el correo existe.
  Future<void> sendRecovery(String email) async {
    try {
      await client.auth.resetPasswordForEmail(email.trim(), redirectTo: resetRedirectUrl);
    } catch (_) {}
  }

  Future<void> signOut() async {
    _access = null;
    // El modo y la votación fijados en el terminal terminan con la sesión.
    await TerminalPrefs.save('profile', null);
    await client.auth.signOut(scope: SignOutScope.local);
  }

  /// Perfil, rol y permisos; null si no hay sesión o la cuenta está desactivada.
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

  Future<List<Map<String, dynamic>>> rows(Future<dynamic> query) async {
    final data = await query;
    return (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> rpcList(String fn, [Map<String, dynamic>? params]) =>
      rows(client.rpc(fn, params: params));

  Future<Map<String, dynamic>> rpcMap(String fn, [Map<String, dynamic>? params]) async {
    final data = await client.rpc(fn, params: params);
    return Map<String, dynamic>.from(data as Map);
  }

  // ---- Foto de perfil ----
  final Map<String, ({String? url, DateTime at})> _photoCache = {};

  /// Igual que [photoUrl] pero recuerda el enlace firmado unos minutos (listas de personas y chats).
  Future<String?> photoUrlCached(String userId) async {
    final hit = _photoCache[userId];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 4)) return hit.url;
    final url = await photoUrl(userId);
    _photoCache[userId] = (url: url, at: DateTime.now());
    return url;
  }

  Future<String?> photoUrl(String userId) async {
    try {
      final files = await client.storage.from(photoBucket).list(path: userId, searchOptions: const SearchOptions(search: 'avatar', limit: 1));
      if (!files.any((f) => f.name == 'avatar')) return null;
      return await client.storage.from(photoBucket).createSignedUrl('$userId/avatar', 300);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePhoto(String userId, Uint8List bytes) async {
    await client.storage.from(photoBucket).uploadBinary(
          '$userId/avatar',
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg', cacheControl: '0'),
        );
    _photoCache.remove(userId);
  }

  Future<void> removePhoto(String userId) async {
    await client.storage.from(photoBucket).remove(['$userId/avatar']);
    _photoCache.remove(userId);
  }

  /// Cambia la contraseña tras reautenticar con la actual.
  Future<void> changePassword(String current, String next) async {
    final a = await access();
    if (a == null) throw AuthFailure('Sesión no válida.');
    try {
      await signIn(a.email, current);
    } on AuthFailure {
      throw AuthFailure('La contraseña actual no es correcta.');
    }
    try {
      await client.auth.updateUser(UserAttributes(password: next));
      await client.rpc('ack_password_changed');
      await access(force: true);
    } catch (_) {
      throw AuthFailure('No se pudo cambiar la contraseña.');
    }
  }
}
