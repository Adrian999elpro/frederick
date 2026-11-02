import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../core/theme_controller.dart';
import '../widgets/common.dart';
import 'grades_screen.dart';

const _accents = {'red': 'Rojo Frederick', 'blue': 'Azul', 'green': 'Verde', 'purple': 'Violeta', 'gold': 'Dorado'};
const _badges = {
  'school': '🎓 Aprender',
  'science': '🔬 Ciencia',
  'music': '🎵 Música',
  'sports': '⚽ Deporte',
  'code': '💻 Tecnología',
  'art': '🎨 Arte',
};

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.access});
  final Access access;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Access _access = widget.access;
  String? _photo;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final url = await Api.instance.photoUrl(_access.id);
    if (mounted) setState(() => _photo = url);
  }

  Future<void> _refreshAccess() async {
    final fresh = await Api.instance.access(force: true);
    if (fresh != null && mounted) setState(() => _access = fresh);
  }

  Future<void> _changePhoto() async {
    setState(() => _photoBusy = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) snack(context, 'La foto debe pesar como máximo 5 MB.', error: true);
        return;
      }
      await Api.instance.savePhoto(_access.id, bytes);
      await _loadPhoto();
      if (mounted) snack(context, 'Foto guardada.');
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo guardar la foto.'), error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      await Api.instance.removePhoto(_access.id);
      await _loadPhoto();
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _sheet(Widget Function(BuildContext) builder) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: builder,
      );

  Future<void> _logout() async {
    if (!await confirm(context, '¿Cerrar sesión en este teléfono?', okLabel: 'Cerrar sesión')) return;
    await Api.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final a = _access;
    return ListView(padding: EdgeInsets.zero, children: [
      HeroHeader(
        child: Column(children: [
          Stack(alignment: Alignment.bottomRight, children: [
            Avatar(name: a.fullName, url: _photo, size: 96),
            Material(
              color: Fwt.gold,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _photoBusy ? null : _changePhoto,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _photoBusy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Fwt.ink))
                      : const Icon(Icons.photo_camera_rounded, size: 18, color: Fwt.ink),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(a.fullName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          Text(a.email, style: const TextStyle(color: Colors.white70)),
          if (_photo != null) TextButton(onPressed: _removePhoto, child: const Text('Quitar foto', style: TextStyle(color: Colors.white70))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (a.isStudent) ...[
            const SectionTitle('Académico'),
            _Item(
              icon: Icons.grading_rounded,
              title: 'Mis notas',
              subtitle: 'Calificaciones por materia y período',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GradesScreen(access: a))),
            ),
          ],
          const SectionTitle('Mi cuenta'),
          _Item(
            icon: Icons.person_outline_rounded,
            title: 'Datos personales',
            subtitle: 'Nombre y teléfono',
            onTap: () => _sheet((_) => _PersonalSheet(access: a, onSaved: _refreshAccess)),
          ),
          const SizedBox(height: 8),
          _Item(
            icon: Icons.palette_outlined,
            title: 'Así quiero presentarme',
            subtitle: 'Frase, descripción, color e insignia',
            onTap: () => _sheet((_) => _PresentationSheet(access: a)),
          ),
          const SizedBox(height: 8),
          _Item(
            icon: Icons.lock_outline_rounded,
            title: 'Privacidad',
            subtitle: 'Quién ve mi perfil y mis notas',
            onTap: () => _sheet((_) => _PrivacySheet(access: a)),
          ),
          const SizedBox(height: 8),
          _Item(
            icon: Icons.key_rounded,
            title: 'Cambiar contraseña',
            subtitle: 'Mínimo $minPassword caracteres',
            onTap: () => showChangePasswordSheet(context),
          ),
          const SectionTitle('Apariencia'),
          const _ThemePicker(),
          const SizedBox(height: 24),
          OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout_rounded), label: const Text('Cerrar sesión')),
          const SizedBox(height: 12),
          Text('$appName · $schoolName', textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 11)),
        ]),
      ),
    ]);
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Fwt.brand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: context.brandText),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) => SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Claro')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Oscuro')),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Sistema')),
          ],
          selected: {ThemeController.instance.mode},
          onSelectionChanged: (s) => ThemeController.instance.set(s.first),
        ),
      );
}

/// Estructura común de las hojas de formulario.
class _FormSheet extends StatelessWidget {
  const _FormSheet({required this.title, required this.children, required this.busy, required this.onSave, this.error, this.saveLabel = 'Guardar'});
  final String title;
  final List<Widget> children;
  final bool busy;
  final VoidCallback? onSave;
  final String? error;
  final String saveLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            ...children,
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: context.brandText))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : onSave,
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(saveLabel),
            ),
          ]),
        ),
      );
}

class _PersonalSheet extends StatefulWidget {
  const _PersonalSheet({required this.access, required this.onSaved});
  final Access access;
  final Future<void> Function() onSaved;

  @override
  State<_PersonalSheet> createState() => _PersonalSheetState();
}

class _PersonalSheetState extends State<_PersonalSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.access.fullName);
  late final TextEditingController _phone = TextEditingController(text: widget.access.phone);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Escribe tu nombre completo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.client
          .from('profiles')
          .update({'full_name': _name.text.trim(), 'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim()})
          .eq('id', widget.access.id);
      await widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Datos guardados.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
        title: 'Datos personales',
        busy: _busy,
        error: _error,
        onSave: _save,
        children: [
          Text('El correo y el teléfono no se muestran a tus compañeros.', style: TextStyle(color: context.muted)),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre completo')),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
        ],
      );
}

class _PresentationSheet extends StatefulWidget {
  const _PresentationSheet({required this.access});
  final Access access;

  @override
  State<_PresentationSheet> createState() => _PresentationSheetState();
}

class _PresentationSheetState extends State<_PresentationSheet> {
  final _nick = TextEditingController();
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
    _load();
  }

  @override
  void dispose() {
    _nick.dispose();
    _headline.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Api.instance.client.from('profile_customizations').select('*').eq('profile_id', widget.access.id).maybeSingle();
      if (data != null) {
        _nick.text = (data['nickname'] as String?) ?? '';
        _headline.text = (data['headline'] as String?) ?? '';
        _bio.text = (data['bio'] as String?) ?? '';
        final accent = data['accent'] as String?;
        final badge = data['badge'] as String?;
        if (_accents.containsKey(accent)) _accent = accent!;
        if (_badges.containsKey(badge)) _badge = badge!;
      }
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.client.from('profile_customizations').upsert({
        'profile_id': widget.access.id,
        'nickname': _nick.text.trim(),
        'headline': _headline.text.trim(),
        'bio': _bio.text.trim(),
        'accent': _accent,
        'badge': _badge,
      }, onConflict: 'profile_id');
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Presentación guardada.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))
      : _FormSheet(
          title: 'Así quiero presentarme',
          busy: _busy,
          error: _error,
          onSave: _save,
          children: [
            TextField(controller: _nick, maxLength: 40, decoration: const InputDecoration(labelText: 'Nombre para mostrar (opcional)')),
            const SizedBox(height: 4),
            TextField(controller: _headline, maxLength: 100, decoration: const InputDecoration(labelText: 'Mi frase')),
            const SizedBox(height: 4),
            TextField(controller: _bio, maxLength: 400, maxLines: 3, decoration: const InputDecoration(labelText: 'Sobre mí')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _accent,
              decoration: const InputDecoration(labelText: 'Color de mi perfil'),
              items: [for (final e in _accents.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _accent = v ?? _accent),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _badge,
              decoration: const InputDecoration(labelText: 'Mi insignia'),
              items: [for (final e in _badges.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _badge = v ?? _badge),
            ),
          ],
        );
}

class _PrivacySheet extends StatefulWidget {
  const _PrivacySheet({required this.access});
  final Access access;

  @override
  State<_PrivacySheet> createState() => _PrivacySheetState();
}

class _PrivacySheetState extends State<_PrivacySheet> {
  String _visibility = 'private';
  bool _showGrades = false;
  bool _allowed = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await Api.instance.client.rpc('profile_privacy_settings');
      final choice = settings is Map && settings['student_choice'] == true;
      _allowed = choice || widget.access.can('users.manage');
      final data = await Api.instance.client
          .from('profile_customizations')
          .select('visibility, show_grades')
          .eq('profile_id', widget.access.id)
          .maybeSingle();
      if (data != null) {
        _visibility = data['visibility'] == 'public' ? 'public' : 'private';
        _showGrades = data['show_grades'] == true;
      }
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.client.from('profile_customizations').upsert(
        {'profile_id': widget.access.id, 'visibility': _visibility, 'show_grades': _showGrades},
        onConflict: 'profile_id',
      );
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Privacidad actualizada.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()))
      : _FormSheet(
          title: 'Privacidad',
          busy: _busy,
          error: _error,
          onSave: _allowed ? _save : null,
          children: [
            if (!_allowed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('El colegio gestiona la privacidad. Contacta con un administrador para solicitar cambios.',
                    style: TextStyle(color: context.muted)),
              ),
            RadioGroup<String>(
              groupValue: _visibility,
              onChanged: (v) {
                if (_allowed && v != null) setState(() => _visibility = v);
              },
              child: const Column(children: [
                RadioListTile<String>(
                  value: 'private',
                  title: Text('Privado'),
                  subtitle: Text('Tu presentación no se muestra a otras cuentas.'),
                ),
                RadioListTile<String>(
                  value: 'public',
                  title: Text('Público en el colegio'),
                  subtitle: Text('Verán tu foto, presentación y especialidades. Nunca tu correo ni teléfono.'),
                ),
              ]),
            ),
            SwitchListTile(
              value: _showGrades,
              onChanged: _allowed ? (v) => setState(() => _showGrades = v) : null,
              title: const Text('Compartir mis calificaciones'),
              subtitle: const Text('Solo se muestran si tu perfil es público. También permite participar en los rankings.'),
            ),
          ],
        );
}

/// Cambio de contraseña; con [forced] se exige tras un restablecimiento o cuenta nueva.
Future<void> showChangePasswordSheet(BuildContext context, {bool forced = false}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: !forced,
      enableDrag: !forced,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _PasswordSheet(forced: forced),
    );

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.forced});
  final bool forced;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text.length < minPassword) {
      setState(() => _error = 'La nueva contraseña debe tener al menos $minPassword caracteres.');
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _error = 'Las contraseñas nuevas no coinciden.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.changePassword(_current.text, _next.text);
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Contraseña cambiada.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !widget.forced,
        child: _FormSheet(
          title: widget.forced ? 'Cambia tu contraseña para continuar' : 'Cambiar contraseña',
          busy: _busy,
          error: _error,
          onSave: _save,
          saveLabel: 'Cambiar contraseña',
          children: [
            TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña actual')),
            const SizedBox(height: 12),
            TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña nueva')),
            const SizedBox(height: 12),
            TextField(controller: _again, obscureText: true, decoration: const InputDecoration(labelText: 'Repite la contraseña nueva')),
          ],
        ),
      );
}
