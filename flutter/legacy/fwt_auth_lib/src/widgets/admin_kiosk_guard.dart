import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/nfc_service.dart';
import '../theme.dart';

class AdminKioskGuard {
  /// Solicita acercar una tarjeta de Administrador al sensor NFC para autorizar
  /// la salida de la aplicación o el cambio de modo de operación.
  static Future<bool> requestAdminAuth(BuildContext context, {String reason = 'desbloquear opciones o salir'}) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AdminCardScanDialog(reason: reason),
    ) ?? false;
  }

  /// Cierra la app si la tarjeta de admin es válida
  static Future<void> exitAppWithAdminCard(BuildContext context) async {
    final ok = await requestAdminAuth(context, reason: 'salir de la aplicación');
    if (ok) {
      SystemNavigator.pop();
    }
  }
}

class _AdminCardScanDialog extends StatefulWidget {
  final String reason;
  const _AdminCardScanDialog({required this.reason});

  @override
  State<_AdminCardScanDialog> createState() => _AdminCardScanDialogState();
}

class _AdminCardScanDialogState extends State<_AdminCardScanDialog> {
  String _status = 'Acerque la tarjeta de Administrador al lector NFC...';
  bool _verifying = false;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    NfcCardService.instance.startListening(
      onCardScanned: _onCardDetected,
      onError: (err) {
        if (mounted) setState(() => _status = 'Error NFC: $err');
      },
    );
  }

  Future<void> _onCardDetected(String cardUid) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _status = 'Tarjeta detectada ($cardUid). Verificando privilegios de administrador...';
    });

    final res = await NfcCardService.instance.validateAdminCard(cardUid);
    final isAdmin = res['is_admin'] == true;

    if (!mounted) return;

    if (isAdmin) {
      setState(() {
        _isSuccess = true;
        _status = '✅ ¡Administrador verificado! (${res['admin_name'] ?? 'Admin'})';
      });
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _verifying = false;
        _status = '❌ Denegado: Esta tarjeta no tiene rango de Administrador.';
      });
    }
  }

  @override
  void dispose() {
    NfcCardService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.admin_panel_settings, color: FwtColors.brand, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Autorización Requerida',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _isSuccess
                  ? Colors.green.shade50
                  : _verifying
                  ? Colors.amber.shade50
                  : FwtColors.background,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isSuccess
                  ? Icons.check_circle
                  : Icons.nfc,
              size: 56,
              color: _isSuccess ? Colors.green : FwtColors.brand,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Se requiere tarjeta de Administrador para ${widget.reason}.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _isSuccess
                  ? Colors.green.shade800
                  : _verifying
                  ? Colors.amber.shade900
                  : Colors.grey.shade700,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancelar', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
