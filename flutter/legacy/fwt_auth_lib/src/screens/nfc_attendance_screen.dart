import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/nfc_service.dart';
import '../theme.dart';
import '../widgets/admin_kiosk_guard.dart';

class NfcAttendanceScreen extends StatefulWidget {
  final VoidCallback? onExitRequested;
  const NfcAttendanceScreen({super.key, this.onExitRequested});

  @override
  State<NfcAttendanceScreen> createState() => _NfcAttendanceScreenState();
}

class _NfcAttendanceScreenState extends State<NfcAttendanceScreen> with SingleTickerProviderStateMixin {
  bool _isProcessing = false;
  Map<String, dynamic>? _lastResult;
  String _message = 'Acerque el carnet o tarjeta del estudiante al sensor NFC...';
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _startNfcListener();
  }

  void _startNfcListener() {
    NfcCardService.instance.startListening(
      onCardScanned: _handleCardScanned,
      onError: (err) {
        if (mounted) setState(() => _message = 'Error NFC: $err');
      },
    );
  }

  Future<void> _handleCardScanned(String cardUid) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _message = 'Leyendo tarjeta: $cardUid...';
    });

    try {
      final res = await Supabase.instance.client.rpc(
        'record_attendance_nfc',
        params: {'p_card_uid': cardUid},
      );

      if (!mounted) return;

      final map = Map<String, dynamic>.from(res as Map);
      setState(() {
        _lastResult = map;
        if (map['ok'] == true) {
          _message = '¡Asistencia registrada con éxito!';
        } else if (map['code'] == 'already_registered_today') {
          _message = 'Asistencia ya tomada hoy. Próximo registro disponible mañana.';
        } else {
          _message = map['message'] ?? 'Error desconocido';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastResult = {'ok': false, 'message': e.toString()};
          _message = 'Error de conexión: $e';
        });
      }
    } finally {
      // Esperar 3.5 segundos para que el alumno vea su pantalla y reiniciar escucha
      await Future.delayed(const Duration(milliseconds: 3500));
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _lastResult = null;
          _message = 'Listo. Acerque la siguiente tarjeta al sensor NFC...';
        });
      }
    }
  }

  Future<void> _handleExitAttempt() async {
    final authorized = await AdminKioskGuard.requestAdminAuth(
      context,
      reason: 'salir del terminal de asistencia',
    );
    if (authorized) {
      widget.onExitRequested?.call() ?? Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    NfcCardService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = _lastResult?['ok'] == true;
    final isAlreadyToday = _lastResult?['code'] == 'already_registered_today';
    final hasResult = _lastResult != null;

    Color bgStatusColor = FwtColors.background;
    Color iconColor = FwtColors.brand;
    IconData statusIcon = Icons.nfc;

    if (hasResult) {
      if (isSuccess) {
        bgStatusColor = Colors.green.shade50;
        iconColor = Colors.green.shade700;
        statusIcon = Icons.check_circle_rounded;
      } else if (isAlreadyToday) {
        bgStatusColor = Colors.amber.shade50;
        iconColor = Colors.amber.shade800;
        statusIcon = Icons.history_toggle_off_rounded;
      } else {
        bgStatusColor = Colors.red.shade50;
        iconColor = Colors.red.shade700;
        statusIcon = Icons.error_outline_rounded;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal de Asistencia NFC'),
        leading: IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Desbloquear con tarjeta Administrador',
          onPressed: _handleExitAttempt,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Salir de la App (Requiere Admin)',
            onPressed: () => AdminKioskGuard.exitAppWithAdminCard(context),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        color: bgStatusColor,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo FWT
            Image.network(
              'https://www.frederickwinslowtaylor.com/Imagenes/sello.png',
              width: 80,
              height: 80,
              errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 70, color: FwtColors.brand),
            ),
            const SizedBox(height: 8),
            const Text(
              'Unidad Educativa Técnica Particular\nFrederick Winslow Taylor',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              '#Calidad Más No Cantidad',
              style: TextStyle(fontStyle: FontStyle.italic, color: FwtColors.brand, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 32),

            // Sensor NFC Visualizer
            AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final scale = _isProcessing ? 1.0 : (1.0 + (_animController.value * 0.08));
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: iconColor.withOpacity(0.25),
                          blurRadius: 25,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(statusIcon, size: 84, color: iconColor),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),

            // Mensajes y Resultados
            if (hasResult) ...[
              if (isSuccess) ...[
                Text(
                  _lastResult!['student_name'] ?? 'Estudiante',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.green),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _lastResult!['level_name'] ?? '',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hora: ${_lastResult!['check_time']} · Estado: ${_lastResult!['status'] == 'late' ? 'Atraso' : 'Presente'}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ] else if (isAlreadyToday) ...[
                Text(
                  _lastResult!['student_name'] ?? 'Estudiante',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.amber.shade900),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '⚠️ ASISTENCIA YA REGISTRADA HOY',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF78350F)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fue registrada a las ${_lastResult!['previous_time']}.\nEl sensor no admitirá otro registro hasta el día de mañana.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Text(
                  _lastResult!['message'] ?? 'Error',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                ),
              ]
            ] else ...[
              Text(
                _message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Cada alumno registra una sola vez por día',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],

            const Spacer(),
            Text(
              '🔒 Modo Kiosko Seguro · Salir requiere tarjeta Administrador',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
