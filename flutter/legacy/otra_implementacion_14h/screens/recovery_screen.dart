import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../ui.dart';

/// Recuperación en dos pasos: 1) recibir el código por correo, 2) escribir el código y la nueva contraseña.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  bool get _validEmail => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());

  Future<void> _sendCode() async {
    if (!_validEmail) {
      setState(() => _error = 'Escribe un correo electrónico válido.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).client.auth.resetPasswordForEmail(_email.text.trim().toLowerCase());
      if (mounted) setState(() => _codeSent = true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.statusCode == '429'
            ? 'Demasiadas solicitudes. Espera un momento antes de intentarlo otra vez.'
            : 'No pudimos enviar el correo. Inténtalo más tarde o contacta con el colegio.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos enviar el correo. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9]{6,10}$').hasMatch(code)) {
      setState(() => _error = 'Escribe el código completo que recibiste por correo.');
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
    final client = AppScope.of(context).client;
    try {
      final res = await client.auth.verifyOTP(email: _email.text.trim().toLowerCase(), token: code, type: OtpType.recovery);
      if (res.session == null) throw AuthException('invalid');
      await client.auth.updateUser(UserAttributes(password: _password.text));
      await client.auth.signOut(scope: SignOutScope.local);
      if (!mounted) return;
      showMsg(context, 'Contraseña actualizada. Ya puedes entrar.');
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'El código no es válido o ya caducó. Revisa el correo o solicita uno nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _codeSent
                  ? 'Te enviamos un código a ${_email.text.trim()}. Escríbelo aquí y elige tu nueva contraseña.'
                  : 'Escribe el correo de tu cuenta y te enviaremos un código para crear una contraseña nueva.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.alternate_email_rounded)),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Código del correo', prefixIcon: Icon(Icons.pin_outlined)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nueva contraseña', prefixIcon: Icon(Icons.lock_outline_rounded)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _again,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repite la contraseña', prefixIcon: Icon(Icons.lock_reset_rounded)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
              child: Text(_busy ? 'Espera…' : (_codeSent ? 'Cambiar contraseña' : 'Enviar código')),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy ? null : () => setState(() {
                  _codeSent = false;
                  _error = null;
                }),
                child: const Text('Usar otro correo o pedir otro código'),
              ),
          ],
        ),
      ),
    );
  }
}
