import 'package:flutter/material.dart';

import '../auth_service.dart';
import '../theme.dart';

enum _Mode { login, register, forgot }

/// Inicio de sesión, registro (si el administrador lo abrió) y recuperación de contraseña.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _again = TextEditingController();
  final _name = TextEditingController();
  _Mode _mode = _Mode.login;
  bool _busy = false;
  bool _canRegister = false;
  String? _msg;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    FwtAuth.instance.registrationMode().then((m) {
      if (mounted) setState(() => _canRegister = m != 'closed');
    });
  }

  @override
  void dispose() {
    for (final c in [_email, _pass, _again, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_Mode m) => setState(() {
        _mode = m;
        _msg = null;
      });

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    final auth = FwtAuth.instance;
    try {
      switch (_mode) {
        case _Mode.login:
          await auth.signIn(_email.text, _pass.text); // AuthGate reacciona a la sesión nueva
        case _Mode.register:
          await auth.signUp(email: _email.text, password: _pass.text, fullName: _name.text);
          _show('Revisa tu correo para confirmar la cuenta.', false);
        case _Mode.forgot:
          await auth.sendRecovery(_email.text);
          _show('Si el correo está registrado, recibirás un enlace para restablecer la contraseña.', false);
      }
    } on AuthFailure catch (e) {
      _show(e.message, true);
      _pass.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text, bool error) {
    if (mounted) setState(() {
      _msg = text;
      _isError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = FwtAuth.instance.config;
    final t = Theme.of(context);
    final titles = {_Mode.login: 'Iniciar sesión', _Mode.register: 'Crear una cuenta', _Mode.forgot: 'Recuperar contraseña'};
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Image.network(cfg.logoUrl, height: 96, errorBuilder: (_, __, ___) => const SizedBox(height: 96)),
                  const SizedBox(height: 12),
                  Text(cfg.appName, textAlign: TextAlign.center, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(cfg.tagline, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: FwtColors.accent)),
                  const SizedBox(height: 28),
                  Text(titles[_mode]!, style: t.textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  if (_msg != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: _isError ? t.colorScheme.errorContainer : t.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_msg!, semanticsLabel: _msg),
                    ),
                  if (_mode == _Mode.register) ...[
                    TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre completo'), autofillHints: const [AutofillHints.name], validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe tu nombre' : null),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Correo electrónico'), keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.username], validator: (v) => (v ?? '').contains('@') ? null : 'Escribe un correo válido'),
                  if (_mode != _Mode.forgot) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      decoration: const InputDecoration(labelText: 'Contraseña'),
                      obscureText: true,
                      autofillHints: [_mode == _Mode.login ? AutofillHints.password : AutofillHints.newPassword],
                      validator: (v) => (v ?? '').length < (_mode == _Mode.register ? cfg.minPassword : 1) ? 'Mínimo ${cfg.minPassword} caracteres' : null,
                    ),
                  ],
                  if (_mode == _Mode.register) ...[
                    const SizedBox(height: 12),
                    TextFormField(controller: _again, decoration: const InputDecoration(labelText: 'Repite la contraseña'), obscureText: true, validator: (v) => v == _pass.text ? null : 'Las contraseñas no coinciden'),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_busy ? 'Un momento…' : titles[_mode]!)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                    if (_mode != _Mode.login) TextButton(onPressed: () => _go(_Mode.login), child: const Text('Volver a iniciar sesión')),
                    if (_mode == _Mode.login) TextButton(onPressed: () => _go(_Mode.forgot), child: const Text('Olvidé mi contraseña')),
                    if (_mode == _Mode.login && _canRegister) TextButton(onPressed: () => _go(_Mode.register), child: const Text('Crear una cuenta')),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
