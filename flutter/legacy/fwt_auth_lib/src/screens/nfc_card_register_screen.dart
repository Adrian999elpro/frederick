import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/nfc_service.dart';
import '../theme.dart';
import '../widgets/admin_kiosk_guard.dart';

class NfcCardRegisterScreen extends StatefulWidget {
  final VoidCallback? onExitRequested;
  const NfcCardRegisterScreen({super.key, this.onExitRequested});

  @override
  State<NfcCardRegisterScreen> createState() => _NfcCardRegisterScreenState();
}

class _NfcCardRegisterScreenState extends State<NfcCardRegisterScreen> {
  String? _scannedUid;
  String? _selectedProfileId;
  String _cardType = 'estudiante';
  final _labelController = TextEditingController();
  List<Map<String, dynamic>> _studentsList = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String _statusMessage = 'Acerque una tarjeta o carnet al sensor NFC para registrarla...';

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _startNfcListener();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email, roles(name), student_details(level_id, school_levels(name))')
          .eq('status', 'active')
          .order('full_name');

      setState(() {
        _studentsList = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar alumnos: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startNfcListener() {
    NfcCardService.instance.startListening(
      onCardScanned: (uid) {
        setState(() {
          _scannedUid = uid;
          _statusMessage = 'Tarjeta detectada con éxito. UID: $uid';
        });
      },
      onError: (err) {
        if (mounted) setState(() => _statusMessage = 'Error NFC: $err');
      },
    );
  }

  Future<void> _saveCardAssignment() async {
    if (_scannedUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debe escanear una tarjeta con el sensor')),
      );
      return;
    }

    if (_selectedProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione el estudiante o usuario a asignar')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client.from('nfc_cards').upsert({
        'card_uid': _scannedUid!,
        'profile_id': _selectedProfileId!,
        'card_type': _cardType,
        'label': _labelController.text.trim(),
        'active': true,
      }, onConflict: 'card_uid');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ ¡Tarjeta vinculada y asignada exitosamente!')),
      );

      setState(() {
        _scannedUid = null;
        _selectedProfileId = null;
        _labelController.clear();
        _statusMessage = 'Tarjeta guardada. Acerque la siguiente tarjeta para registrar...';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    NfcCardService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Tarjetas NFC'),
        leading: IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Desbloquear con tarjeta Administrador',
          onPressed: () async {
            final ok = await AdminKioskGuard.requestAdminAuth(
              context,
              reason: 'salir de la pantalla de registro',
            );
            if (ok && mounted) {
              widget.onExitRequested?.call() ?? Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: FwtColors.brand))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Banner sensor
                  Card(
                    color: _scannedUid != null ? Colors.green.shade50 : FwtColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _scannedUid != null ? Colors.green : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            _scannedUid != null ? Icons.credit_card : Icons.nfc,
                            size: 60,
                            color: _scannedUid != null ? Colors.green : FwtColors.brand,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _scannedUid ?? 'Sensor a la espera...',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _scannedUid != null ? Colors.green.shade900 : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Asignar datos del Estudiante o Administrador:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),

                  // Selector de Estudiante
                  DropdownButtonFormField<String>(
                    value: _selectedProfileId,
                    decoration: const InputDecoration(
                      labelText: 'Estudiante / Usuario',
                      prefixIcon: Icon(Icons.person),
                    ),
                    isExpanded: true,
                    items: _studentsList.map((st) {
                      final name = st['full_name'] ?? st['email'];
                      final role = st['roles']?['name'] ?? '';
                      final level = st['student_details']?['school_levels']?['name'] ?? '';
                      final detail = level.isNotEmpty ? '($level)' : '[$role]';

                      return DropdownMenuItem<String>(
                        value: st['id'],
                        child: Text('$name $detail', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedProfileId = val),
                  ),
                  const SizedBox(height: 16),

                  // Tipo de Tarjeta
                  DropdownButtonFormField<String>(
                    value: _cardType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Tarjeta NFC',
                      prefixIcon: Icon(Icons.security),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'estudiante',
                        child: Text('Estudiante (Asistencia y Voto Escolar)'),
                      ),
                      DropdownMenuItem(
                        value: 'docente',
                        child: Text('Docente'),
                      ),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('🔑 Tarjeta Administrador (Permite salir de la App Kiosko)'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _cardType = val ?? 'estudiante'),
                  ),
                  const SizedBox(height: 16),

                  // Etiqueta
                  TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta o Código de Carnet (Opcional)',
                      hintText: 'Ej: Carnet FWT-2026-089',
                      prefixIcon: Icon(Icons.badge),
                    ),
                  ),
                  const SizedBox(height: 28),

                  ElevatedButton(
                    onPressed: (_scannedUid == null || _selectedProfileId == null || _isSaving)
                        ? null
                        : _saveCardAssignment,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Vincular y Guardar Tarjeta'),
                  ),
                ],
              ),
            ),
    );
  }
}
