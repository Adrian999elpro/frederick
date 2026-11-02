import 'package:flutter/services.dart';

class NfcException implements Exception {
  NfcException(this.message);
  final String message;
  bool get cancelled => message.toLowerCase().contains('cancelad');
  @override
  String toString() => message;
}

/// Puente con el código nativo de Android (MainActivity.kt):
/// lectura NFC y fijación de pantalla del terminal escolar.
class NfcBridge {
  static const _channel = MethodChannel('ec.frederick.escolar/nfc');

  /// Espera una tarjeta y devuelve su UID en formato 04:A2:3B:5C.
  static Future<String> scan() async {
    try {
      final uid = await _channel.invokeMethod<String>('scan');
      if (uid == null || uid.isEmpty) throw NfcException('No se pudo leer la tarjeta.');
      return uid;
    } on PlatformException catch (e) {
      throw NfcException(e.message ?? 'No se pudo leer la tarjeta.');
    } on MissingPluginException {
      throw NfcException('Esta función solo está disponible en Android con NFC.');
    }
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  /// Fija la pantalla. Devuelve «dedicated» si el teléfono es dispositivo dedicado, «pinning» si es fijación normal.
  static Future<String> pin() async {
    try {
      return await _channel.invokeMethod<String>('pin') ?? 'pinning';
    } on PlatformException catch (e) {
      throw NfcException(e.message ?? 'No se pudo fijar la pantalla.');
    } on MissingPluginException {
      return 'pinning';
    }
  }

  static Future<void> unpin() async {
    try {
      await _channel.invokeMethod<void>('unpin');
    } catch (_) {}
  }
}
