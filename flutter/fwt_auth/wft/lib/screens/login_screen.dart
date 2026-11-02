import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.signIn(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'No se pudo iniciar sesión.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _RecoverSheet(initialEmail: _email.text),
    );
    if (sent == true && mounted) {
      snack(context, 'Si el correo está registrado, recibirás un enlace para restablecer tu contraseña.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            HeroHeader(
              padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 40, 24, 44),
              child: Column(children: [
                const SchoolLogo(size: 84),
                const SizedBox(height: 18),
                const Text(appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(tagline, style: const TextStyle(color: Fwt.gold, fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Acceso administrativo',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Solo para la cuenta del colegio que activa este teléfono. Estudiantes y docentes no inician sesión: acercan su tarjeta.', style: TextStyle(color: context.muted, height: 1.4)),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline_rounded)),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Escribe un correo válido' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _hide ? 'Mostrar contraseña' : 'Ocultar contraseña',
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Fwt.brand.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline_rounded, color: context.brandText),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!)),
                          ]),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _busy ? null : _recover, child: const Text('Olvidé mi contraseña')),
                    const SizedBox(height: 12),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
}

class _RecoverSheet extends StatefulWidget {
  const _RecoverSheet({required this.initialEmail});
  final String initialEmail;

  @override
  State<_RecoverSheet> createState() => _RecoverSheetState();
}

class _RecoverSheetState extends State<_RecoverSheet> {
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.text.contains('@')) return;
    setState(() => _busy = true);
    await Api.instance.sendRecovery(_email.text);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Recuperar contraseña',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Te enviaremos un enlace al correo de tu cuenta.', style: TextStyle(color: context.muted)),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo electrónico'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Enviar enlace'),
          ),
        ]),
      );
}
