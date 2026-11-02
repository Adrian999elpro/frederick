import 'package:flutter/services.dart';

/// Puente con el lector NFC y la fijación de pantalla de Android (MainActivity.kt).
class Nfc {
  Nfc._();
  static const _channel = MethodChannel('ec.frederick.escolar/nfc');

  /// Espera una tarjeta y devuelve su UID (ej. "04:A2:3B:5C"). Lanza PlatformException si falla.
  static Future<String> scan() async {
    final uid = await _channel.invokeMethod<String>('scan');
    if (uid == null || uid.isEmpty) {
      throw PlatformException(code: 'scan_failed', message: 'No se pudo leer la tarjeta.');
    }
    return uid;
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  /// Devuelve "dedicated" si el teléfono es un dispositivo administrado, o "pinning".
  static Future<String> pin() async => (await _channel.invokeMethod<String>('pin')) ?? 'pinning';

  static Future<void> unpin() => _channel.invokeMethod<void>('unpin');
}
