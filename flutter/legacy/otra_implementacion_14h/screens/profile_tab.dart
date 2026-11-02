import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../app_state.dart';
import '../ui.dart';
import 'edit_profile_screen.dart';
import 'password_screen.dart';
import 'privacy_screen.dart';
import 'vote_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _busy = false;

  Future<void> _changePhoto() async {
    final app = AppScope.of(context);
    final uid = app.access!.id;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Quitar mi foto'),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (choice == 'remove') {
        await Api.removeProfilePhoto(uid);
      } else {
        final picked = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
        );
        if (picked == null) return;
        await Api.saveProfilePhoto(uid, await picked.readAsBytes());
      }
      PhotoCache.invalidate(uid);
      app.bumpPhoto();
      if (mounted) showMsg(context, choice == 'remove' ? 'Foto eliminada.' : 'Foto actualizada.');
    } catch (e) {
      if (mounted) showMsg(context, 'No se pudo actualizar la foto.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final access = app.access!;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        GradientHero(
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  UserAvatar(name: access.fullName, userId: access.id, size: 104, ring: true),
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _busy ? null : _changePhoto,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Icon(Icons.photo_camera_rounded, size: 20, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                access.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              Text(access.email, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Apariencia'),
              FwtCard(
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Sistema')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Claro')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Oscuro')),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ),
              const SectionTitle('Mi cuenta'),
              _MenuTile(icon: Icons.edit_rounded, label: 'Editar mi perfil', onTap: () => _push(const EditProfileScreen())),
              _MenuTile(icon: Icons.visibility_rounded, label: 'Privacidad', onTap: () => _push(const PrivacyScreen())),
              _MenuTile(icon: Icons.how_to_vote_rounded, label: 'Votar', onTap: () => _push(const VoteScreen())),
              _MenuTile(icon: Icons.lock_rounded, label: 'Seguridad y contraseña', onTap: () => _push(const PasswordScreen())),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await confirmDialog(context, 'Se cerrará tu sesión en este teléfono.',
                      okLabel: 'Cerrar sesión', title: 'Cerrar sesión');
                  if (ok) await app.signOut();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('Frederick Escolar 2.0', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FwtCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
