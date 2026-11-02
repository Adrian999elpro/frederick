import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../ui.dart';

const _accents = <String, Color>{
  'red': Color(0xFFA81717),
  'blue': Color(0xFF0369A1),
  'green': Color(0xFF15803D),
  'purple': Color(0xFF7E22CE),
  'gold': Color(0xFFF59E0B),
};

const _badges = <String, (IconData, String)>{
  'school': (Icons.school_rounded, 'Colegio'),
  'science': (Icons.science_rounded, 'Ciencia'),
  'music': (Icons.music_note_rounded, 'Música'),
  'sports': (Icons.sports_soccer_rounded, 'Deporte'),
  'code': (Icons.code_rounded, 'Código'),
  'art': (Icons.palette_rounded, 'Arte'),
};

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _nickname = TextEditingController();
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  String _accent = 'red';
  String _badge = 'school';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = AppScope.read(context).access!;
    _name.text = a.fullName;
    _phone.text = a.phone ?? '';
    _load(a.id);
  }

  Future<void> _load(String uid) async {
    try {
      final c = await Api.myCustomization(uid);
      if (c != null) {
        _nickname.text = '${c['nickname'] ?? ''}';
        _headline.text = '${c['headline'] ?? ''}';
        _bio.text = '${c['bio'] ?? ''}';
        if (_accents.containsKey(c['accent'])) _accent = '${c['accent']}';
        if (_badges.containsKey(c['badge'])) _badge = '${c['badge']}';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _nickname, _headline, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Escribe tu nombre completo.');
      return;
    }
    final app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Json custom = {
        'nickname': _nickname.text.trim(),
        'headline': _headline.text.trim(),
        'bio': _bio.text.trim(),
        'accent': _accent,
        'badge': _badge,
      };
      await Api.saveProfile(uid: app.access!.id, fullName: _name.text, phone: _phone.text, customization: custom);
      await app.loadAccess();
      if (!mounted) return;
      showMsg(context, 'Perfil guardado.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'No se pudo guardar tu perfil.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Editar mi perfil')),
      body: _loading
          ? const LoadingBox()
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextField(controller: _name, maxLength: 120, decoration: const InputDecoration(labelText: 'Nombre completo')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 30,
                    decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
                  ),
                  const SectionTitle('Cómo te ven los demás'),
                  TextField(controller: _nickname, maxLength: 40, decoration: const InputDecoration(labelText: 'Apodo')),
                  const SizedBox(height: 8),
                  TextField(controller: _headline, maxLength: 100, decoration: const InputDecoration(labelText: 'Frase corta')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bio,
                    maxLength: 400,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Sobre mí'),
                  ),
                  const SectionTitle('Color'),
                  Wrap(
                    spacing: 12,
                    children: [
                      for (final e in _accents.entries)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _accent = e.key),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: e.value,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _accent == e.key ? cs.onSurface : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: _accent == e.key ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                          ),
                        ),
                    ],
                  ),
                  const SectionTitle('Insignia'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _badges.entries)
                        ChoiceChip(
                          avatar: Icon(e.value.$1, size: 18),
                          label: Text(e.value.$2),
                          selected: _badge == e.key,
                          onSelected: (_) => setState(() => _badge = e.key),
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Guardando…' : 'Guardar cambios')),
                ],
              ),
            ),
    );
  }
}
