import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _sessionKey = 'fwt_session';
const _store = FlutterSecureStorage();

/// Guarda la sesión de Supabase en el almacén seguro de Android (Keystore)
/// en lugar de SharedPreferences.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage()
      : super(
          initialize: () async {},
          hasAccessToken: () => _store.containsKey(key: _sessionKey),
          accessToken: () => _store.read(key: _sessionKey),
          removePersistedSession: () => _store.delete(key: _sessionKey),
          persistSession: (value) => _store.write(key: _sessionKey, value: value),
        );
}
