import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../ui.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _loading = true;
  bool _allowed = false;
  bool _public = false;
  bool _showGrades = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final access = AppScope.read(context).access!;
    try {
      final results = await Future.wait<Object?>([Api.privacySettings(), Api.myCustomization(access.id)]);
      final settings = results[0] as Json;
      final c = results[1] as Json?;
      _allowed = settings['student_choice'] == true || access.can('users.manage');
      _public = c?['visibility'] == 'public';
      _showGrades = c?['show_grades'] == true;
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
      await Api.savePrivacy(AppScope.of(context).access!.id, _public ? 'public' : 'private', _showGrades);
      if (mounted) showMsg(context, 'Privacidad actualizada.');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad')),
      body: _loading
          ? const LoadingBox()
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Decide qué pueden ver tus compañeros.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
                  if (!_allowed) ...[
                    const SizedBox(height: 14),
                    FwtCard(
                      child: Row(
                        children: [
                          Icon(Icons.admin_panel_settings_rounded, color: cs.primary),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('El colegio gestiona la privacidad. Pide a un administrador si necesitas un cambio.'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FwtCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _public,
                          onChanged: _allowed ? (v) => setState(() => _public = v) : null,
                          title: const Text('Perfil público en el colegio', style: TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: const Text('Si lo apagas, tu foto y presentación no se muestran a otras cuentas.'),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          value: _showGrades,
                          onChanged: _allowed ? (v) => setState(() => _showGrades = v) : null,
                          title: const Text('Mostrar mis calificaciones', style: TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: const Text('Se verán en tu perfil público y en el ranking.'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: (!_allowed || _busy) ? null : _save,
                    child: Text(_busy ? 'Guardando…' : 'Guardar'),
                  ),
                ],
              ),
            ),
    );
  }
}
