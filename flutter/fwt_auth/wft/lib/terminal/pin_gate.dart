import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import 'terminal_context.dart';

/// La tarjeta de administrador sola no basta: hace falta su PIN de 6 dígitos.
/// - Si todavía no tiene PIN, lo crea ahora (dos veces).
/// - Si ya lo tiene, lo escribe. 5 fallos bloquean 15 minutos.
/// - Si hay una sesión de administrador abierta (menos de 10 minutos), no lo vuelve a pedir.
/// Devuelve true cuando el servidor dejó el permiso (ticket) listo para usarse.
Future<bool> askAdminPin(BuildContext context, CardScan scan) async {
  if (scan.pinOk) return true;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinDialog(scan: scan),
  );
  return ok == true;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.scan});
  final CardScan scan;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _creating => !widget.scan.pinSet;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  String _lockedText(dynamic until) {
    final at = DateTime.tryParse('$until')?.toLocal();
    if (at == null) return 'Demasiados intentos. Espera unos minutos.';
    final minutes = at.difference(DateTime.now()).inMinutes + 1;
    return 'Demasiados intentos. Vuelve a intentar en $minutes min.';
  }

  Future<void> _submit() async {
    final pin = _pin.text;
    if (pin.length != 6) return setState(() => _error = 'El PIN tiene 6 números.');
    if (_creating && pin != _again.text) return setState(() => _error = 'Los dos PIN no coinciden.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Api.instance.rpcMap(
        _creating ? 'terminal_pin_set' : 'terminal_pin_verify',
        {'p_ticket': widget.scan.ticket, 'p_pin': pin},
      );
      if (res['ok'] == true) {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      _pin.clear();
      _again.clear();
      setState(() {
        if (res['locked_until'] != null) {
          _error = _lockedText(res['locked_until']);
        } else {
          final left = res['attempts_left'];
          _error = left == null ? 'PIN incorrecto.' : 'PIN incorrecto. Te quedan $left intentos.';
        }
      });
    } catch (e) {
      setState(() => _error = friendlyError(e, 'No se pudo comprobar el PIN. Revisa la conexión.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {bool last = false}) => TextField(
        controller: c,
        autofocus: c == _pin,
        obscureText: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w800),
        decoration: InputDecoration(labelText: label, counterText: ''),
        onChanged: (v) {
          // Al PIN de entrada se envía solo al llegar a 6 números.
          if (!_creating && c == _pin && v.length == 6 && !_busy) _submit();
        },
        onSubmitted: (_) => last ? _submit() : null,
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_creating ? 'Crea tu PIN' : 'Escribe tu PIN'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              _creating
                  ? 'Hola, ${widget.scan.name ?? ''}. Elige un PIN de 6 números. Lo pedirá este terminal junto con tu tarjeta; no lo compartas.'
                  : 'Hola, ${widget.scan.name ?? ''}. Escribe el PIN de tu tarjeta de administrador.',
              style: TextStyle(color: context.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            _field(_pin, _creating ? 'Nuevo PIN' : 'PIN'),
            if (_creating) ...[
              const SizedBox(height: 8),
              _field(_again, 'Repite el PIN', last: true),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: context.brandText, fontWeight: FontWeight.w700))),
              ),
            if (!_creating)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('¿Lo olvidaste? Restablécelo en la web: Seguridad → «Restablecer mi PIN».', style: TextStyle(color: context.muted, fontSize: 12)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_creating ? 'Guardar PIN' : 'Entrar')),
        ],
      );
}
