import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;

List<Json> _rows(dynamic v) => (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// Traduce los errores del servidor a mensajes para estudiantes.
String friendlyError(Object e, [String fallback = 'No se pudo completar la operación. Inténtalo de nuevo.']) {
  const map = {
    'writing_suspended': 'No puedes escribir ahora.',
    'applications_closed': 'Las postulaciones están cerradas.',
    'scan_required': 'Acerca tu tarjeta otra vez para continuar.',
    'already_accepted': 'Tu lista ya fue aprobada.',
    'card_not_authorized': 'Esta tarjeta no tiene permiso para desbloquear el terminal.',
    'already_voted': 'Ya registraste tu voto en esta votación.',
    'election_not_open': 'Esta votación no está abierta.',
    'invalid_list': 'La lista seleccionada no es válida.',
    'forbidden': 'No tienes permiso para esta acción.',
    'results_hidden': 'Los resultados se publican cuando la votación se cierre.',
    'not_eligible': 'Este estudiante no estaba habilitado cuando se abrió la votación.',
    'invalid_card': 'Tarjeta no registrada o inactiva.',
    'privacy_managed_by_school': 'El colegio gestiona la privacidad de los perfiles.',
  };
  final text = e is PostgrestException ? '${e.message} ${e.code ?? ''}' : e.toString();
  for (final entry in map.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  if (e is PostgrestException && e.code == '42501') return map['forbidden']!;
  if (e is AuthException) return e.message;
  return fallback;
}

/// Acceso a los datos. Toda la autorización real la hace el servidor (RLS y funciones RPC).
class Api {
  // ---------- Catálogos ----------
  static Future<List<Json>> levels() async =>
      _rows(await _db.from('school_levels').select('id,name,code').order('order_index'));

  // ---------- Calificaciones y perfil ----------
  static Future<List<Json>> myGrades(String uid) async => _rows(await _db
      .from('grades')
      .select('score,feedback,subjects(name,code),grade_periods(name,order_index)')
      .eq('student_id', uid));

  static Future<Json?> myStudentDetails(String uid) async {
    final r = await _db
        .from('student_details')
        .select('student_code,school_levels(name,code)')
        .eq('profile_id', uid)
        .maybeSingle();
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  static Future<Json?> myCustomization(String uid) async {
    final r = await _db.from('profile_customizations').select().eq('profile_id', uid).maybeSingle();
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  static Future<void> saveProfile({
    required String uid,
    required String fullName,
    required String phone,
    required Json customization,
  }) async {
    await _db.from('profiles').update({'full_name': fullName.trim(), 'phone': phone.trim()}).eq('id', uid);
    await _db.from('profile_customizations').upsert({'profile_id': uid, ...customization}, onConflict: 'profile_id');
  }

  static Future<Json> privacySettings() async {
    final r = await _db.rpc('profile_privacy_settings');
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static Future<void> savePrivacy(String uid, String visibility, bool showGrades) async {
    await _db
        .from('profile_customizations')
        .upsert({'profile_id': uid, 'visibility': visibility, 'show_grades': showGrades}, onConflict: 'profile_id');
  }

  // ---------- Foto de perfil ----------
  static Future<String?> profilePhotoUrl(String userId, {int seconds = 3600}) async {
    try {
      final files = await _db.storage
          .from('profile-photos')
          .list(path: userId, searchOptions: SearchOptions(search: 'avatar', limit: 1));
      if (!files.any((f) => f.name == 'avatar')) return null;
      return await _db.storage.from('profile-photos').createSignedUrl('$userId/avatar', seconds);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProfilePhoto(String userId, Uint8List bytes) async {
    await _db.storage.from('profile-photos').uploadBinary(
          '$userId/avatar',
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/jpeg', cacheControl: '0'),
        );
  }

  static Future<void> removeProfilePhoto(String userId) async {
    await _db.storage.from('profile-photos').remove(['$userId/avatar']);
  }

  // ---------- Anuncios y ranking ----------
  static Future<List<Json>> announcements({String? category, int? limit}) async {
    final base = _db
        .from('announcements')
        .select('id,title,content,category,is_pinned,author_role_title,created_at,school_levels(name)');
    final filtered = category == null ? base : base.eq('category', category);
    final ordered = filtered.order('is_pinned', ascending: false).order('created_at', ascending: false);
    final res = await (limit == null ? ordered : ordered.limit(limit));
    return _rows(res);
  }

  static Future<List<Json>> ranking(String? levelId) async =>
      _rows(await _db.rpc('get_academic_ranking', params: {'p_level_id': levelId}));

  // ---------- Elecciones (voto con sesión) ----------
  static Future<List<Json>> openElections() async {
    final now = DateTime.now().toUtc().toIso8601String();
    return _rows(await _db
        .from('elections')
        .select('id,title,description,ends_at,my_receipt:vote_receipts(voted_at)')
        .eq('status', 'open')
        .lte('starts_at', now)
        .gt('ends_at', now)
        .order('ends_at'));
  }

  static Future<List<Json>> electionLists(List<String> electionIds) async {
    if (electionIds.isEmpty) return [];
    return _rows(await _db
        .from('election_lists')
        .select('id,election_id,number,name,slogan,president_name,president_photo')
        .inFilter('election_id', electionIds)
        .order('number'));
  }

  static Future<Map<String, String>> electionPhotoUrls(List<String> paths) async {
    final uniq = paths.where((p) => p.isNotEmpty).toSet().toList();
    if (uniq.isEmpty) return {};
    try {
      final res = await _db.storage.from('election-photos').createSignedUrls(uniq, 3600);
      final out = <String, String>{};
      for (final r in res) {
        final url = r.signedUrl.toString();
        if (url.isNotEmpty && url != 'null') out[r.path.toString()] = url;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> castVote(String electionId, String? listId) async {
    await _db.rpc('cast_vote', params: {'p_election': electionId, 'p_list': listId});
  }

  // ---------- Votaciones del consejo y personalizadas (con tarjeta) ----------
  static Future<List<Json>> openPolls(String kind) async {
    final rows = _rows(await _db
        .from('school_polls')
        .select('id,kind,title,purpose,secret,status,ends_at,school_poll_options(id,label)')
        .eq('kind', kind)
        .eq('status', 'open')
        .order('created_at', ascending: false));
    final now = DateTime.now();
    return rows.where((p) {
      final end = DateTime.tryParse('${p['ends_at']}');
      return end == null || end.isAfter(now);
    }).toList();
  }

  static Future<Json> scanPollCard(String pollId, String cardUid) async {
    final r = await _db.rpc('scan_school_poll_card', params: {'p_poll_id': pollId, 'p_card_uid': cardUid});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> castPollVote(String ticket, String optionId) async {
    await _db.rpc('cast_school_poll_vote', params: {'p_ticket': ticket, 'p_option': optionId});
  }

  // ---------- Mi tarjeta ----------
  static Future<Json?> myEnrollment(String uid) async {
    final r = await _db.from('enrollment_requests').select().eq('profile_id', uid).maybeSingle();
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  static Future<void> submitEnrollment({
    required String fullName,
    required String phone,
    required String levelId,
    String? cardUid,
  }) async {
    await _db.rpc('submit_enrollment', params: {
      'p_full_name': fullName.trim(),
      'p_phone': phone.trim(),
      'p_level_id': levelId,
      // Igual que la web: sin separadores y en mayúsculas.
      'p_card_uid': (cardUid == null || cardUid.isEmpty) ? null : cardUid.replaceAll(RegExp(r'[: -]'), '').toUpperCase(),
    });
  }

  // ---------- Seguridad ----------
  static Future<void> changePassword({required String email, required String current, required String next}) async {
    // Reautenticación con la contraseña actual.
    final res = await _db.auth.signInWithPassword(email: email, password: current);
    if (res.session == null) throw AuthException('La contraseña actual no es correcta.');
    await _db.auth.updateUser(UserAttributes(password: next));
    await _db.rpc('ack_password_changed');
  }

  // ---------- Terminal escolar ----------
  static Future<String> authorizeTerminalCard(String cardUid) async {
    final r = await _db.rpc('authorize_terminal_card', params: {'p_card_uid': cardUid});
    return '$r';
  }

  static Future<bool> consumeTerminalUnlock(String ticket) async {
    final r = await _db.rpc('consume_terminal_unlock', params: {'p_token': ticket});
    return r == true;
  }

  static Future<Json> terminalStudentProfile(String cardUid) async {
    final r = await _db.rpc('terminal_student_profile', params: {'p_card_uid': cardUid});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Json> recordAttendance(String cardUid) async {
    final r = await _db.rpc('record_attendance_nfc', params: {'p_card_uid': cardUid});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<String> registrationMode() async {
    try {
      return (await _db.rpc('public_registration_mode')) as String? ?? 'closed';
    } catch (_) {
      return 'closed';
    }
  }

  /// Crea una cuenta de estudiante con un cliente aparte, sin tocar la sesión del encargado.
  static Future<void> registerStudent({
    required String fullName,
    required String email,
    required String phone,
    required String levelId,
    required String password,
    required String cardUid,
  }) async {
    final isolated = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.anonKey,
      authOptions: AuthClientOptions(autoRefreshToken: false),
    );
    try {
      await isolated.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: AppConfig.registerRedirect,
        data: {
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'registration_level': levelId,
          'registration_card': cardUid,
        },
      );
    } finally {
      await isolated.dispose();
    }
  }
}
