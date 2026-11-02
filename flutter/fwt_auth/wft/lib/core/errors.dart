import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _messages = {
  'writing_suspended': 'No puedes escribir ahora. Revisa si tienes una suspensión.',
  'chat_rate_limit': 'Has enviado varias solicitudes. Espera un momento.',
  'applications_closed': 'Las postulaciones están cerradas.',
  'reason_required': 'Explica el motivo.',
  'scan_required': 'Acerca tu tarjeta otra vez para continuar.',
  'already_accepted': 'Tu lista ya fue aprobada.',
  'card_not_authorized': 'Esta tarjeta no tiene permiso para desbloquear el terminal.',
  'already_voted': 'Ya registraste tu voto en esta votación.',
  'election_not_open': 'Esta votación no está abierta.',
  'election_closed': 'La votación ya está cerrada.',
  'invalid_list': 'La lista seleccionada no es válida.',
  'forbidden': 'No tienes permiso para esta acción.',
  'results_hidden': 'Los resultados se publican cuando la votación se cierre.',
  'not_eligible': 'Este estudiante no estaba habilitado cuando se abrió la votación.',
  'invalid_card': 'La tarjeta no está registrada o no está activa.',
  'need_options': 'Faltan opciones para abrir la votación.',
  'person_has_card': 'Esa persona ya tiene una tarjeta activa. Confirma el reemplazo.',
  'card_already_assigned': 'Esa tarjeta ya pertenece a otra persona.',
  'already_activated': 'Esta cuenta ya tiene correo vinculado.',
  'invalid_nfc_uid': 'No se pudo leer el código de la tarjeta. Acércala otra vez.',
  'person_not_found': 'No se encontró a la persona.',
  'admin_session_required': 'Un administrador debe acercar su tarjeta e ingresar su PIN.',
  'invalid_ticket': 'La tarjeta venció. Acércala otra vez.',
  'invalid_pin': 'El PIN debe tener 6 números.',
  'weak_pin': 'Ese PIN es muy fácil de adivinar. Elige otro.',
  'admin_card_already_registered': 'Ya existe una tarjeta de administrador de otra cuenta.',
};

/// Traduce errores del servidor y del lector NFC a mensajes claros para estudiantes.
String friendlyError(Object error, [String fallback = 'No se pudo completar la operación. Inténtalo de nuevo.']) {
  if (error is AuthFailure) return error.message;
  if (error is PlatformException) return error.message ?? fallback;
  final text = error is PostgrestException ? '${error.message} ${error.code ?? ''}' : error.toString();
  for (final entry in _messages.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  if (error is PostgrestException && error.code == '42501') return _messages['forbidden']!;
  if (text.contains('SocketException') || text.contains('ClientException') || text.contains('Failed host lookup')) {
    return 'Sin conexión con Frederick. Revisa tu internet.';
  }
  return fallback;
}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Deja solo los dígitos hexadecimales en mayúsculas ("04:a2" -> "04A2").
String normalizeUid(String value) => value.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');

/// Un UID NFC válido tiene entre 4 y 10 bytes.
bool isValidUid(String value) {
  final uid = normalizeUid(value);
  return uid.length >= 8 && uid.length <= 20 && uid.length.isEven;
}
