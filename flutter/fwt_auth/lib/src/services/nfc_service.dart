import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NfcCardService {
  static final NfcCardService instance = NfcCardService._();
  NfcCardService._();

  bool _isListening = false;
  bool get isListening => _isListening;

  /// Verifica si el hardware NFC está disponible en este dispositivo Android
  Future<bool> isAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Inicia la escucha continua del sensor NFC
  Future<void> startListening({
    required Function(String cardUid) onCardScanned,
    Function(String error)? onError,
  }) async {
    final available = await isAvailable();
    if (!available) {
      onError?.call('El sensor NFC no está disponible o está apagado en este dispositivo.');
      return;
    }

    if (_isListening) await stopListening();
    _isListening = true;

    try {
      NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          final uid = extractUid(tag);
          if (uid != null && uid.isNotEmpty) {
            onCardScanned(uid);
          } else {
            onError?.call('No se pudo leer el identificador UID de la tarjeta.');
          }
        },
        onError: (e) async {
          _isListening = false;
          onError?.call(e.message);
        },
      );
    } catch (e) {
      _isListening = false;
      onError?.call(e.toString());
    }
  }

  /// Detiene la sesión del sensor NFC
  Future<void> stopListening() async {
    _isListening = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  /// Extrae el UID del tag NFC de manera compatible con múltiples estándares
  String? extractUid(NfcTag tag) {
    Uint8List? identifier;

    // Intentar leer tags Android comunes
    final nfcA = NfcA.from(tag);
    if (nfcA != null) identifier = nfcA.identifier;

    if (identifier == null) {
      final nfcB = NfcB.from(tag);
      if (nfcB != null) identifier = nfcB.identifier;
    }

    if (identifier == null) {
      final isoDep = IsoDep.from(tag);
      if (isoDep != null) identifier = isoDep.identifier;
    }

    if (identifier == null) {
      final mifareClassic = MifareClassic.from(tag);
      if (mifareClassic != null) identifier = mifareClassic.identifier;
    }

    if (identifier == null) {
      final mifareUltralight = MifareUltralight.from(tag);
      if (mifareUltralight != null) identifier = mifareUltralight.identifier;
    }

    // Fallback: buscar en el mapa raw de Android
    if (identifier == null && tag.data.containsKey('identifier')) {
      final raw = tag.data['identifier'];
      if (raw is List<int>) identifier = Uint8List.fromList(raw);
    }

    if (identifier == null) return null;

    // Formatear como HEX en mayúsculas (ej: 04:A2:3B:5C)
    return identifier.map((e) => e.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
  }

  /// Valida en Supabase si una tarjeta escaneada pertenece a un Administrador
  Future<Map<String, dynamic>> validateAdminCard(String cardUid) async {
    try {
      final res = await Supabase.instance.client.rpc(
        'validate_admin_card',
        params: {'p_card_uid': cardUid},
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'is_admin': false, 'message': 'Respuesta inválida del servidor.'};
    } catch (e) {
      return {'is_admin': false, 'message': 'No se pudo verificar la tarjeta. Intente de nuevo.'};
    }
  }
}
