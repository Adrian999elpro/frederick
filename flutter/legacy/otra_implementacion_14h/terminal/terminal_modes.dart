import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';
import '../ui.dart';
import '../screens/announcements_screen.dart';
import '../screens/poll_flow.dart';

// =============================================================== asistencia

class AttendanceMode extends StatefulWidget {
  const AttendanceMode({super.key});

  @override
  State<AttendanceMode> createState() => _AttendanceModeState();
}

class _AttendanceModeState extends State<AttendanceMode> {
  bool _busy = false;
  Json? _result;
  String? _error;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    _reset?.cancel();
    setState(() {
      _result = null;
      _error = null;
    });
    final uid = await askCard(context);
    if (uid == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await Api.recordAttendance(uid);
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'No se pudo registrar la asistencia.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _reset = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _result = null;
          _error = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _result;
    final ok = r?['ok'] == true;
    final name = '${r?['full_name'] ?? r?['student_name'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        if (r == null && _error == null)
          const EmptyBox(
            icon: Icons.contactless_rounded,
            title: 'Registro de asistencia',
            message: 'Pulsa el botón y acerca la tarjeta del estudiante. Se registra una asistencia por día.',
          ),
        if (r != null)
          FwtCard(
            color: (ok ? FwtColors.ok : FwtColors.warn).withValues(alpha: 0.12),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(ok ? Icons.check_circle_rounded : Icons.info_rounded,
                    size: 72, color: ok ? FwtColors.ok : FwtColors.warn),
                const SizedBox(height: 12),
                if (name.isNotEmpty)
                  Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  '${r['message'] ?? (ok ? 'Asistencia registrada.' : 'No se pudo registrar.')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17),
                ),
              ],
            ),
          ),
        if (_error != null)
          FwtCard(
            color: cs.error.withValues(alpha: 0.1),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontWeight: FontWeight.w800)),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: _busy ? null : _read,
          icon: const Icon(Icons.nfc_rounded, size: 28),
          label: Text(_busy ? 'Registrando…' : (r == null ? 'Leer tarjeta y registrar' : 'Siguiente estudiante')),
        ),
      ],
    );
  }
}

// =============================================================== votaciones con tarjeta

class PollsMode extends StatefulWidget {
  const PollsMode({super.key, required this.kind});
  final String kind;

  @override
  State<PollsMode> createState() => _PollsModeState();
}

class _PollsModeState extends State<PollsMode> {
  late Future<List<Json>> _future = Api.openPolls(widget.kind);

  void _reload() => setState(() => _future = Api.openPolls(widget.kind));

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await _future;
        } catch (_) {}
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AsyncView<List<Json>>(
            future: _future,
            onRetry: _reload,
            builder: (context, polls) {
              if (polls.isEmpty) {
                return EmptyBox(
                  icon: Icons.how_to_vote_outlined,
                  title: widget.kind == 'council' ? 'No hay votación del consejo abierta' : 'No hay votaciones abiertas',
                  message: 'Cuando el encargado abra una votación, aparecerá aquí.',
                );
              }
              return Column(
                children: [
                  for (final p in polls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: FwtCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('${p['title']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text('${p['purpose'] ?? ''}'),
                            const SizedBox(height: 6),
                            Text('Cierra ${fmtDate(p['ends_at'])}',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                              onPressed: () => startPollVote(context, p, onDone: _reload),
                              icon: const Icon(Icons.nfc_rounded),
                              label: const Text('Leer tarjeta para votar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================== novedades y consulta de perfil

class ConsultMode extends StatefulWidget {
  const ConsultMode({super.key});

  @override
  State<ConsultMode> createState() => _ConsultModeState();
}

class _ConsultModeState extends State<ConsultMode> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.campaign_rounded), label: Text('Novedades')),
              ButtonSegment(value: 1, icon: Icon(Icons.badge_rounded), label: Text('Mi perfil y notas')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          child: _tab == 0 ? const AnnouncementsScreen(embedded: true) : const _ProfileConsult(),
        ),
      ],
    );
  }
}

class _ProfileConsult extends StatefulWidget {
  const _ProfileConsult();

  @override
  State<_ProfileConsult> createState() => _ProfileConsultState();
}

class _ProfileConsultState extends State<_ProfileConsult> {
  static const _seconds = 60;
  Json? _profile;
  bool _busy = false;
  String? _error;
  int _left = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _wipe();
    super.dispose();
  }

  void _wipe() {
    final id = _profile?['id'];
    if (id != null) PhotoCache.invalidate('$id');
  }

  void _finish() {
    _timer?.cancel();
    _wipe();
    if (mounted) {
      setState(() {
        _profile = null;
        _left = 0;
      });
    }
  }

  Future<void> _read() async {
    _finish();
    setState(() => _error = null);
    final uid = await askCard(context, title: 'Acerca tu tarjeta');
    if (uid == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final p = await Api.terminalStudentProfile(uid);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _left = _seconds;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_left <= 1) {
          _finish();
        } else {
          setState(() => _left--);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'No se pudo consultar. Revisa que tu tarjeta esté registrada.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _profile;
    if (p == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const EmptyBox(
            icon: Icons.badge_outlined,
            title: 'Consulta tu perfil y tus notas',
            message: 'Acerca tu tarjeta. Tus datos se ocultarán solos después de un minuto.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontWeight: FontWeight.w800)),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            onPressed: _busy ? null : _read,
            icon: const Icon(Icons.nfc_rounded, size: 28),
            label: Text(_busy ? 'Consultando…' : 'Leer mi tarjeta'),
          ),
        ],
      );
    }
    final fullName = '${p['full_name'] ?? ''}';
    final nickname = '${p['nickname'] ?? ''}'.trim();
    final grades = ((p['grades'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: _left / _seconds, minHeight: 6, borderRadius: BorderRadius.circular(99)),
        const SizedBox(height: 14),
        FwtCard(
          child: Row(
            children: [
              UserAvatar(name: fullName, userId: '${p['id']}', size: 72, ring: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nickname.isNotEmpty ? nickname : fullName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    if ('${p['level'] ?? ''}'.isNotEmpty) Pill('${p['level']}'),
                    if ('${p['headline'] ?? ''}'.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${p['headline']}', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if ('${p['bio'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          FwtCard(child: Text('${p['bio']}')),
        ],
        const SectionTitle('Mis calificaciones'),
        if (grades.isEmpty)
          const EmptyBox(icon: Icons.assignment_outlined, title: 'Todavía no hay notas registradas')
        else
          FwtCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final g in grades)
                  ListTile(
                    dense: true,
                    title: Text('${g['subject']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${g['period']}'),
                    trailing: Text(
                      '${fmtScore(g['score'])} / 10',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: scoreColor(context, asDouble(g['score'])),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _finish, child: const Text('Terminar y ocultar mis datos')),
      ],
    );
  }
}

// =============================================================== registro de tarjetas y cuentas

class RegisterMode extends StatefulWidget {
  const RegisterMode({super.key});

  @override
  State<RegisterMode> createState() => _RegisterModeState();
}

class _RegisterModeState extends State<RegisterMode> {
  late final Future<List<Object?>> _setup = Future.wait<Object?>([Api.levels(), Api.registrationMode()]);
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  String? _card;
  String? _levelId;
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _again]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear() {
    for (final c in [_name, _email, _phone, _password, _again]) {
      c.clear();
    }
    _card = null;
    _levelId = null;
  }

  Future<void> _readCard() async {
    final uid = await askCard(context);
    if (uid != null && mounted) setState(() => _card = uid);
  }

  Future<void> _submit() async {
    if (_card == null) {
      setState(() => _error = 'Lee primero la tarjeta.');
      return;
    }
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Escribe el nombre completo.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    if (_levelId == null) {
      setState(() => _error = 'Elige el curso.');
      return;
    }
    if (_password.text.length < AppConfig.minPassword) {
      setState(() => _error = 'La contraseña debe tener al menos ${AppConfig.minPassword} caracteres.');
      return;
    }
    if (_password.text != _again.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.registerStudent(
        fullName: _name.text,
        email: _email.text,
        phone: _phone.text,
        levelId: _levelId!,
        password: _password.text,
        cardUid: _card!,
      );
      if (!mounted) return;
      setState(() {
        _clear();
        _done = 'Revisa tu correo para confirmar la cuenta. El colegio revisará la tarjeta antes de activarla.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo completar el registro. Revisa los datos o consulta al encargado.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AsyncView<List<Object?>>(
      future: _setup,
      builder: (context, data) {
        final levels = data[0] as List<Json>;
        final mode = data[1] as String;
        if (mode == 'closed') {
          return const EmptyBox(
            icon: Icons.lock_outline_rounded,
            title: 'El registro está cerrado',
            message: 'Pide al colegio que cree tu cuenta.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_done != null) ...[
              FwtCard(
                color: FwtColors.ok.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    const Icon(Icons.mark_email_read_rounded, color: FwtColors.ok, size: 32),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_done!)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            const SectionTitle('1. Lee tu tarjeta'),
            OutlinedButton.icon(
              onPressed: _busy ? null : _readCard,
              icon: Icon(_card == null ? Icons.nfc_rounded : Icons.check_circle_rounded),
              label: Text(_card == null ? 'Leer tarjeta NFC' : 'Tarjeta leída: $_card'),
            ),
            const SectionTitle('2. Tus datos'),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo electrónico'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in levels)
                  ChoiceChip(
                    label: Text('${l['name']}'),
                    selected: _levelId == l['id'],
                    onSelected: (_) => setState(() => _levelId = '${l['id']}'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Contraseña personal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _again,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Repite tu contraseña'),
            ),
            const SizedBox(height: 8),
            Text('Después debes confirmar tu correo. El colegio revisará tu tarjeta antes de activarla.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Creando cuenta…' : 'Crear cuenta y solicitar tarjeta')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => setState(() {
                    _clear();
                    _error = null;
                    _done = null;
                  }),
              child: const Text('Borrar mis datos'),
            ),
          ],
        );
      },
    );
  }
}
