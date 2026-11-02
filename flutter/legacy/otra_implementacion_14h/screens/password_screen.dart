import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../config.dart';
import '../ui.dart';

/// Cambio de contraseña. Con [forced] es obligatorio (contraseña temporal) y no se puede omitir.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key, this.forced = false});
  final bool forced;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
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
    if (_next.text.length < AppConfig.minPassword) {
      setState(() => _error = 'Usa al menos ${AppConfig.minPassword} caracteres.');
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (_next.text == _current.text) {
      setState(() => _error = 'Elige una contraseña diferente a la actual.');
      return;
    }
    final app = AppScope.of(context);
    final access = app.access;
    if (access == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.changePassword(email: access.email, current: _current.text, next: _next.text);
      await app.loadAccess();
      if (!mounted) return;
      showMsg(context, 'Contraseña actualizada.');
      if (!widget.forced) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cambiar. Revisa tu contraseña actual.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.forced ? 'Crea tu contraseña' : 'Seguridad'),
          automaticallyImplyLeading: !widget.forced,
          actions: [
            if (widget.forced) TextButton(onPressed: app.signOut, child: const Text('Salir')),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.forced)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('Tu contraseña es temporal. Cámbiala para continuar.', style: TextStyle(fontSize: 16)),
                ),
              TextField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña actual', prefixIcon: Icon(Icons.lock_outline_rounded)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _next,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Nueva contraseña',
                  helperText: 'Mínimo ${AppConfig.minPassword} caracteres',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _again,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repite la nueva contraseña', prefixIcon: Icon(Icons.vpn_key_outlined)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 22),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Guardando…' : 'Cambiar contraseña')),
            ],
          ),
        ),
      ),
    );
  }
}
