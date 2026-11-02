import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';
import '../community/person.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../screens/announcements_screen.dart';
import '../widgets/common.dart';
import 'card_waiting.dart';
import 'terminal_context.dart';

/// Botón grande de "leer tarjeta", pensado para tocarse sin mirar.
class _BigScanButton extends StatelessWidget {
  const _BigScanButton({required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(68), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Icon(Icons.contactless_rounded, size: 28),
        label: Text(label),
      );
}

// ---------------------------------------------------------------------------
// Perfil con tarjeta (pantalla principal del terminal)
// ---------------------------------------------------------------------------

/// Abre el perfil de una persona (ya leído con `terminal_scan`) y lo deja abierto hasta que lo cierre.
Future<void> openStudentProfile(BuildContext context, Map<String, dynamic> profile, TerminalCtx ctx, {String? uid}) async {
  Person? person;
  try {
    person = Person.maybe(await Api.instance.client.rpc('school_person_card', params: {'p_id': profile['id']}));
  } catch (_) {}
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentProfilePage(profile: profile, person: person, ctx: ctx, uid: uid)));
}

/// Pantalla de espera: la tarjeta decide si es un administrador (abre su panel) o una persona
/// (abre su perfil). Lee de forma continua, sin tocar ningún botón.
class ProfileCardMode extends StatelessWidget {
  const ProfileCardMode({super.key, required this.ctx});
  final TerminalCtx ctx;

  @override
  Widget build(BuildContext context) => CardWaiting(
        title: 'Acerca tu tarjeta',
        busyTitle: 'Buscando tu perfil…',
        hint: 'Estudiantes y docentes: apoya tu tarjeta en la parte trasera del teléfono para ver tu perfil y tus notas.',
        onCard: (uid) async {
          try {
            final scan = await ctx.handleCard(uid);
            if (scan == null || !context.mounted) return;
            await openStudentProfile(context, scan.profile!, ctx, uid: scan.uid);
          } catch (e) {
            if (context.mounted) snack(context, friendlyError(e, 'No se pudo consultar. Revisa que tu tarjeta esté registrada.'), error: true);
          }
        },
      );
}

// ---------------------------------------------------------------------------
// Anuncios
// ---------------------------------------------------------------------------
class AnnouncementsMode extends StatefulWidget {
  const AnnouncementsMode({super.key, required this.ctx});
  final TerminalCtx ctx;

  @override
  State<AnnouncementsMode> createState() => _AnnouncementsModeState();
}

class _AnnouncementsModeState extends State<AnnouncementsMode> {
  bool _busy = false;

  Future<void> _consult() async {
    final uid = await scanCard(context, title: 'Acerca tu tarjeta para ver tu perfil');
    if (uid == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final scan = await widget.ctx.handleCard(uid);
      if (scan == null || !mounted) return;
      await openStudentProfile(context, scan.profile!, widget.ctx, uid: scan.uid);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo consultar. Revisa que tu tarjeta esté registrada.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: _BigScanButton(label: 'Ver mi perfil y mis notas', onPressed: _consult, busy: _busy),
        ),
        const Expanded(child: AnnouncementsBody()),
      ]);
}

/// Perfil y datos de la persona que acercó su tarjeta. Queda abierto hasta que ella lo cierre
/// (o hasta que un administrador lo cierre acercando su tarjeta).
class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({super.key, required this.profile, required this.ctx, this.person, this.uid});
  final Map<String, dynamic> profile;
  final String? uid;
  final Person? person;
  final TerminalCtx ctx;

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> with CardLoopMixin<StudentProfilePage> {
  String? _photo;

  @override
  void initState() {
    super.initState();
    final id = widget.profile['id'] as String?;
    if (id != null) {
      Api.instance.photoUrl(id).then((url) {
        if (mounted) setState(() => _photo = url);
      });
    }
    startCardLoop();
  }

  @override
  void dispose() {
    stopCardLoop();
    super.dispose();
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  bool _codeBusy = false;

  /// Código de un solo uso (1 día) para activar la cuenta web. Solo se muestra mientras
  /// la tarjeta todavía no tiene un correo vinculado.
  Future<void> _showActivationCode() async {
    final uid = widget.uid;
    if (uid == null) return;
    setState(() => _codeBusy = true);
    try {
      final res = await Api.instance.rpcMap('terminal_issue_activation_code', {'p_card_uid': uid});
      if (!mounted) return;
      final until = DateTime.tryParse('${res['expires_at']}')?.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      final untilText = until == null ? 'mañana' : '${two(until.day)}/${two(until.month)} a las ${two(until.hour)}:${two(until.minute)}';
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Tu código de activación'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: SelectableText('${res['code']}', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 4, fontFamily: 'monospace')),
            ),
            const SizedBox(height: 14),
            Text('Válido hasta el $untilText y sirve una sola vez. Si pides otro, este deja de servir.', style: TextStyle(color: context.muted)),
            const SizedBox(height: 10),
            const Text('En la página web del colegio elige «Primera vez: activar mi cuenta», escribe este código, tu correo y la contraseña que quieras.'),
            const SizedBox(height: 10),
            const Text('Anótalo o tómale una foto antes de cerrar: no se vuelve a mostrar.', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Listo, ya lo anoté'))],
        ),
      );
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo generar el código. Inténtalo de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _codeBusy = false);
    }
  }

  /// Mientras un perfil está abierto, otra tarjeta no lo reemplaza: solo la de un administrador
  /// puede cerrarlo (por ejemplo, si alguien se fue sin cerrar su perfil).
  @override
  Future<void> onCardRead(String uid) async {
    final scan = await widget.ctx.scan(uid);
    if (!mounted) return;
    if (scan.isAdmin) {
      snack(context, 'Perfil cerrado por el encargado.');
      _close();
    } else {
      snack(context, 'Hay un perfil abierto. Ciérralo para que la siguiente persona acerque su tarjeta.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final name = ((p['nickname'] as String?)?.isNotEmpty ?? false) ? p['nickname'] as String : (p['full_name'] as String? ?? '');
    final grades = ((p['grades'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final bySubject = <String, List<Map<String, dynamic>>>{};
    for (final g in grades) {
      bySubject.putIfAbsent('${g['subject']}', () => []).add(g);
    }
    double score(Map<String, dynamic> g) => double.tryParse('${g['score']}') ?? 0;
    final average = grades.isEmpty ? null : grades.map(score).reduce((a, b) => a + b) / grades.length;
    final subtitle = widget.person?.label ?? (p['level'] as String? ?? '');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _close,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cerrar mi perfil'),
            ),
          ),
        ),
        body: ListView(padding: EdgeInsets.zero, children: [
          HeroHeader(
            child: Column(children: [
              Avatar(name: name, url: _photo, size: 96),
              const SizedBox(height: 12),
              Text(name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              if (subtitle.isNotEmpty) Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Fwt.gold, fontWeight: FontWeight.w700)),
              if ((p['headline'] as String?)?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(p['headline'] as String, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                ),
              const SizedBox(height: 10),
              const Text('Tu perfil sigue abierto hasta que lo cierres', style: TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (p['activation_pending'] == true && widget.uid != null)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Activa tu acceso a la web', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text('Aún no tienes correo vinculado. Pide tu código (dura 1 día) y actívalo desde cualquier computadora o teléfono.', style: TextStyle(color: context.muted, height: 1.35)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _codeBusy ? null : _showActivationCode,
                        icon: const Icon(Icons.vpn_key_rounded),
                        label: const Text('Activar mi acceso a la web'),
                      ),
                    ]),
                  ),
                ),
              if ((p['bio'] as String?)?.isNotEmpty ?? false)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p['bio'] as String, style: const TextStyle(height: 1.4))),
              if (average != null)
                Row(children: [
                  Expanded(child: _Stat(label: 'Promedio', value: average.toStringAsFixed(2))),
                  const SizedBox(width: 12),
                  Expanded(child: _Stat(label: 'Materias', value: '${bySubject.length}')),
                ]),
              const SectionTitle('Calificaciones'),
              if (grades.isEmpty)
                Text('Todavía no hay notas registradas.', style: TextStyle(color: context.muted))
              else
                for (final entry in bySubject.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          for (final g in entry.value)
                            Chip(visualDensity: VisualDensity.compact, label: Text('${g['period']}: ${score(g).toStringAsFixed(2)}')),
                        ]),
                      ]),
                    ),
                  ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: context.brandText)),
            Text(label, style: TextStyle(color: context.muted)),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Asistencia (lectura continua; la tarjeta de un administrador abre su panel)
// ---------------------------------------------------------------------------
class AttendanceMode extends StatefulWidget {
  const AttendanceMode({super.key, required this.ctx});
  final TerminalCtx ctx;

  @override
  State<AttendanceMode> createState() => _AttendanceModeState();
}

class _AttendanceModeState extends State<AttendanceMode> {
  bool? _ok;
  String _message = '';
  String _student = '';
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  Future<void> _card(String uid) async {
    if (await widget.ctx.handleCard(uid) == null) return;
    if (!mounted) return;
    _clear?.cancel();
    try {
      final data = await Api.instance.rpcMap('record_attendance_nfc', {'p_card_uid': uid});
      final ok = data['ok'] == true;
      if (!mounted) return;
      setState(() {
        _ok = ok;
        _message = (data['message'] as String?) ?? (ok ? 'Asistencia registrada.' : 'No se pudo registrar.');
        _student = (data['full_name'] ?? data['student_name'] ?? '') as String;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _message = friendlyError(e, 'No se pudo registrar la asistencia.');
        _student = '';
      });
    }
    _clear = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _ok = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _ok == true ? Fwt.ok : Fwt.accent;
    return CardWaiting(
      title: 'Acerca la tarjeta del estudiante',
      busyTitle: 'Registrando…',
      hint: 'Se registra una asistencia por estudiante y día.',
      onCard: _card,
      header: _ok == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_ok == true ? Icons.check_circle_rounded : Icons.error_rounded, size: 84, color: color),
                const SizedBox(height: 10),
                if (_student.isNotEmpty)
                  Text(_student, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(_message, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: color, fontWeight: FontWeight.w700)),
              ]),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Registro de tarjetas (solo administradores)
// ---------------------------------------------------------------------------
class RegistrationMode extends StatefulWidget {
  const RegistrationMode({super.key, required this.ctx});
  final TerminalCtx ctx;

  @override
  State<RegistrationMode> createState() => _RegistrationModeState();
}

class _RegistrationModeState extends State<RegistrationMode> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  int _tab = 0; // 0 = persona nueva, 1 = alguien que ya tiene cuenta
  int _formVersion = 0;
  String? _uid;
  String _role = 'estudiante';
  String? _level;
  bool _busy = false;
  String? _status;
  bool _statusOk = false;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _person;

  /// ¿Hay una sesión de administrador abierta (tarjeta + PIN)? El servidor la exige para registrar.
  bool? _session;
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    _checkSession();
    _sessionTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkSession());
  }

  Future<void> _checkSession() async {
    try {
      final res = await Api.instance.rpcMap('terminal_admin_session_status');
      if (mounted) setState(() => _session = res['active'] == true);
    } catch (_) {
      if (mounted && _session == null) setState(() => _session = false);
    }
  }

  Future<void> _endSession() async {
    try {
      await Api.instance.client.rpc('terminal_end_admin_session');
    } catch (_) {}
    if (mounted) setState(() => _session = false);
  }

  Future<List<Map<String, dynamic>>> _loadLevels() {
    final api = Api.instance;
    return api.rows(api.client.from('school_levels').select('id, name').order('order_index'));
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _say(String message, {bool ok = false}) => setState(() {
        _status = message;
        _statusOk = ok;
      });

  void _clearForm() {
    _name.clear();
    setState(() {
      _uid = null;
      _level = null;
      _formVersion++;
    });
  }

  Future<void> _read() async {
    final uid = await scanCard(context, title: 'Acerca la tarjeta que vas a registrar');
    if (uid != null && mounted) setState(() => _uid = uid);
  }

  Future<void> _registerNew() async {
    if (_uid == null) return _say('Lee primero la tarjeta.');
    if (_name.text.trim().length < 2) return _say('Escribe el nombre completo.');
    if (_role == 'estudiante' && _level == null) return _say('Elige el curso del estudiante.');
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final res = await Api.instance.registerPerson(uid: _uid!, name: _name.text.trim(), role: _role, levelId: _role == 'estudiante' ? _level : null);
      final name = '${res['name'] ?? _name.text.trim()}';
      _clearForm();
      _say('Registrado: $name. Ya puede acercar su tarjeta; cuando quiera entrar a la web, pedirá su código en su perfil.', ok: true);
    } catch (e) {
      _say(friendlyError(e, 'No se pudo registrar. Inténtalo de nuevo.'));
      _checkSession();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.length < 2) return _say('Escribe al menos 2 letras del nombre.');
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final rows = await Api.instance.rpcList('terminal_search_people', {'p_query': q});
      if (mounted) {
        setState(() => _results = rows);
        if (rows.isEmpty) _say('No hay personas con ese nombre.');
      }
    } catch (e) {
      _say(friendlyError(e, 'No se pudo buscar.'));
      _checkSession();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign() async {
    final person = _person;
    if (person == null) return;
    final uid = await scanCard(context, title: 'Acerca la tarjeta de ${person['full_name']}');
    if (uid == null || !mounted) return;
    final hasCard = person['has_card'] == true;
    if (hasCard) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('¿Reemplazar su tarjeta?'),
          content: Text('${person['full_name']} ya tiene una tarjeta. La anterior dejará de funcionar.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reemplazar')),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await Api.instance.rpcMap('terminal_assign_card', {'p_card_uid': uid, 'p_profile_id': person['id'], 'p_replace': hasCard});
      setState(() {
        _person = null;
        _results = [];
        _search.clear();
      });
      _say('Tarjeta ${hasCard ? 'reemplazada' : 'asignada'} a ${person['full_name']}.', ok: true);
    } on PostgrestException catch (e) {
      final owner = (e.details is String && (e.details as String).isNotEmpty) ? ' (${e.details})' : '';
      _say(e.message.contains('card_already_assigned') ? 'Esa tarjeta ya pertenece a otra persona$owner.' : friendlyError(e, 'No se pudo asignar la tarjeta.'));
    } catch (e) {
      _say(friendlyError(e, 'No se pudo asignar la tarjeta.'));
      _checkSession();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _statusLine() => _status == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(_status!, style: TextStyle(color: _statusOk ? Fwt.ok : context.brandText, fontWeight: FontWeight.w700)),
          ),
        );

  Widget _newPerson() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadLevels(),
        builder: (context, snap) {
          final levels = snap.data ?? const <Map<String, dynamic>>[];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('1. Lee la tarjeta', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _BigScanButton(label: _uid == null ? 'Leer tarjeta NFC' : 'Tarjeta leída ✓  (tocar para cambiar)', onPressed: _read),
            const SizedBox(height: 22),
            Text('2. Datos de la persona', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'estudiante', label: Text('Estudiante'), icon: Icon(Icons.school_rounded)),
                ButtonSegment(value: 'docente', label: Text('Docente'), icon: Icon(Icons.person_pin_rounded)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            if (_role == 'estudiante') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('level$_formVersion'),
                initialValue: _level,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Curso'),
                items: [for (final l in levels) DropdownMenuItem(value: l['id'] as String, child: Text(l['name'] as String))],
                onChanged: (v) => setState(() => _level = v),
              ),
            ],
            _statusLine(),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : _registerNew,
              child: const Text('Registrar persona y tarjeta'),
            ),
            const SizedBox(height: 10),
            Text(
              'No se crea ninguna contraseña. Más tarde la persona acerca su tarjeta, pide su código de 1 día y activa su cuenta en la web con su propio correo.',
              style: TextStyle(color: context.muted, height: 1.4),
            ),
          ]);
        },
      );

  Widget _existing() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Para asignar la tarjeta a alguien que ya tiene cuenta, o reemplazar una tarjeta perdida.', style: TextStyle(color: context.muted, height: 1.4)),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _doSearch(),
          decoration: InputDecoration(
            labelText: 'Buscar por nombre o correo',
            suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _busy ? null : _doSearch),
          ),
        ),
        _statusLine(),
        const SizedBox(height: 8),
        if (_person != null) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text('${_person!['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_person!['has_card'] == true ? 'Ya tiene tarjeta: se reemplazará' : 'Todavía no tiene tarjeta'),
              trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _person = null)),
            ),
          ),
          const SizedBox(height: 8),
          _BigScanButton(label: 'Leer la tarjeta nueva', busy: _busy, onPressed: _assign),
        ] else
          for (final r in _results)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([r['role'], r['level']].where((e) => e != null && '$e'.isNotEmpty).join(' · ')),
                trailing: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(r['has_card'] == true ? 'Con tarjeta' : 'Sin tarjeta'),
                ),
                onTap: () => setState(() {
                  _person = r;
                  _status = null;
                }),
              ),
            ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const Center(child: CircularProgressIndicator());
    if (_session == false) {
      return CardWaiting(
        title: 'Registro de tarjetas',
        hint: 'Un administrador debe acercar su tarjeta e ingresar su PIN para registrar o asignar tarjetas.',
        busyTitle: 'Verificando…',
        onCard: (uid) async {
          if (await widget.ctx.adminUnlock(uid)) await _checkSession();
        },
      );
    }
    return _form(context);
  }

  Widget _form(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Icon(Icons.verified_user_rounded, color: Fwt.ok, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Sesión de administrador abierta', style: TextStyle(fontWeight: FontWeight.w700))),
          TextButton(onPressed: _endSession, child: const Text('Cerrar')),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Persona nueva'), icon: Icon(Icons.person_add_alt_1_rounded)),
            ButtonSegment(value: 1, label: Text('Ya tiene cuenta'), icon: Icon(Icons.manage_search_rounded)),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() {
            _tab = s.first;
            _status = null;
          }),
        ),
        const SizedBox(height: 18),
        if (_tab == 0) _newPerson() else _existing(),
      ]);
}

// ---------------------------------------------------------------------------
// Votación fijada por el administrador (voto por turno con tarjeta)
// ---------------------------------------------------------------------------
class PollsMode extends StatefulWidget {
  const PollsMode({super.key, required this.ctx});
  final TerminalCtx ctx;

  @override
  State<PollsMode> createState() => _PollsModeState();
}

class _PollsModeState extends State<PollsMode> {
  Map<String, dynamic>? _poll;
  String? _loadError;
  bool _loading = true;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _load(quiet: true));
  }

  @override
  void didUpdateWidget(covariant PollsMode old) {
    super.didUpdateWidget(old);
    if (old.ctx.pollId != widget.ctx.pollId) _load();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final id = widget.ctx.pollId;
    if (id == null) {
      if (mounted) setState(() {
        _poll = null;
        _loading = false;
        _loadError = null;
      });
      return;
    }
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final rows = await Api.instance.rows(Api.instance.client
          .from('school_polls')
          .select('*, school_poll_options(id, label, application_id)')
          .eq('id', id)
          .limit(1));
      if (!mounted) return;
      setState(() {
        _poll = rows.isEmpty ? null : rows.first;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(e);
        _loading = false;
      });
    }
  }

  bool get _isOpen {
    final p = _poll;
    if (p == null || p['status'] != 'open') return false;
    final ends = DateTime.tryParse('${p['ends_at']}');
    return ends == null || ends.isAfter(DateTime.now());
  }

  Future<void> _card(String uid) async {
    if (await widget.ctx.handleCard(uid) == null) {
      await _load();
      return;
    }
    if (!mounted) return;
    final poll = _poll;
    if (poll == null || !_isOpen) {
      await _load();
      if (mounted) snack(context, 'No hay una votación abierta. Avisa al encargado.', error: true);
      return;
    }
    final scan = await Api.instance.rpcMap('scan_school_poll_card', {'p_poll_id': poll['id'], 'p_card_uid': uid});
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _TurnPage(poll: poll, scan: scan)));
    if (mounted) await _load(quiet: true);
  }

  Widget? _header() {
    final p = _poll;
    if (p == null) return null;
    final secret = p['secret'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${p['title']}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          if ('${p['purpose'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${p['purpose']}', textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (secret ? Fwt.ok : Fwt.gold).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              secret
                  ? 'Voto secreto: el resultado no relaciona nombres con opciones.'
                  : 'Voto identificado: tu nombre y tu elección aparecerán en los resultados.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return EmptyState(icon: Icons.cloud_off_rounded, text: _loadError!, actionLabel: 'Reintentar', onAction: _load);
    }
    final open = _isOpen;
    final String title;
    final String hint;
    if (widget.ctx.pollId == null || _poll == null) {
      title = 'Sin votación asignada';
      hint = 'El encargado debe elegir una votación acercando su tarjeta.';
    } else if (!open) {
      final draft = _poll!['status'] == 'draft';
      title = draft ? 'La votación aún no abre' : 'Votación cerrada';
      hint = draft ? 'El encargado debe abrirla con su tarjeta.' : 'Esta votación ya terminó. El encargado puede elegir otra.';
    } else {
      title = 'Acerca tu tarjeta para votar';
      hint = 'Cada estudiante vota una sola vez. Tienes 90 segundos después de leer tu tarjeta.';
    }
    return CardWaiting(title: title, hint: hint, busyTitle: 'Verificando tarjeta…', header: _header(), onCard: _card);
  }
}

/// Turno de un estudiante: 90 segundos desde la lectura para elegir y confirmar.
class _TurnPage extends StatefulWidget {
  const _TurnPage({required this.poll, required this.scan});
  final Map<String, dynamic> poll;
  final Map<String, dynamic> scan;

  @override
  State<_TurnPage> createState() => _TurnPageState();
}

class _TurnPageState extends State<_TurnPage> {
  static const _seconds = 90;
  int _left = _seconds;
  Timer? _timer;
  String? _choice;
  bool _busy = false;
  bool _done = false;
  bool _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        if (!_done) setState(() => _expired = true);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    final options = _options;
    final label = options.firstWhere((o) => o['id'] == _choice)['label'];
    final ok = await confirm(context, '¿Confirmar tu voto por «$label»? No podrás cambiarlo después.', okLabel: 'Confirmar voto');
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.client.rpc('cast_school_poll_vote', params: {'p_ticket': widget.scan['ticket'], 'p_option': _choice});
      _timer?.cancel();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = '${friendlyError(e, 'No se registró el voto.')} Lee de nuevo tu tarjeta.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> get _options =>
      ((widget.poll['school_poll_options'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final secret = widget.poll['secret'] == true;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: _done || _expired
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_done ? Icons.check_circle_rounded : Icons.timer_off_rounded, size: 100, color: _done ? Fwt.ok : Fwt.gold),
                    const SizedBox(height: 18),
                    Text(
                      _done ? 'Voto registrado' : 'Turno vencido',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _done ? 'Turno terminado; puede acercarse el siguiente estudiante.' : 'Vuelve a leer la tarjeta para votar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.muted, fontSize: 16),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Listo')),
                  ]),
                ),
              )
            : ListView(padding: EdgeInsets.zero, children: [
                HeroHeader(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Turno de', style: const TextStyle(color: Fwt.gold, fontWeight: FontWeight.w800)),
                    Text('${widget.scan['student_name']}', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('Te quedan $_left segundos. ${secret ? 'Tu voto es secreto.' : 'Tu voto aparecerá con tu nombre.'}',
                        style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${widget.poll['title']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 12),
                    RadioGroup<String>(
                      groupValue: _choice,
                      onChanged: (v) => setState(() => _choice = v),
                      child: Column(children: [
                        for (final o in _options)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: _choice == o['id'] ? Fwt.brand.withValues(alpha: 0.1) : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: _choice == o['id'] ? Fwt.brand : context.line, width: _choice == o['id'] ? 2 : 1),
                              ),
                              child: RadioListTile<String>(
                                value: o['id'] as String,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                title: Text('${o['label']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    if (_error != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.brandText))),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _choice == null || _busy ? null : _confirm, child: const Text('Confirmar voto')),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar turno')),
                  ]),
                ),
              ]),
      ),
    );
  }
}
