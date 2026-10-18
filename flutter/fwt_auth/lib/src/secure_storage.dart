import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _key = 'fwt_session';
const _store = FlutterSecureStorage();

/// Guarda la sesión en el almacén seguro del sistema (Keychain / Keystore)
/// en lugar de SharedPreferences.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage()
      : super(
          initialize: () async {},
          hasAccessToken: () => _store.containsKey(key: _key),
          accessToken: () => _store.read(key: _key),
          removePersistedSession: () => _store.delete(key: _key),
          persistSession: (value) => _store.write(key: _key, value: value),
        );
}
