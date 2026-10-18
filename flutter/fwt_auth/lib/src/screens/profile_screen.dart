import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../access.dart';
import '../auth_service.dart';
import '../theme.dart';

/// Perfil institucional, especialidades técnicas y personalización.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.access, this.forced = false, this.onChanged});
  final Access access;
  final bool forced;
  final VoidCallback? onChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileForm = GlobalKey<FormState>();
  final _passForm = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.access.fullName);
  late final _phone = TextEditingController(text: widget.access.phone ?? '');
  final _bioController = TextEditingController();
  final _cur = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();

  String _notesVisibility = 'private';
  String _avatarTheme = 'classic';
  String _schoolLevelName = '';
  String _schoolLevelCode = '';
  bool _isBachillerato = false;

  String? _chosenSpecialtyId;
  List<String> _interestedSpecialties = [];
  List<Map<String, dynamic>> _allSpecialties = [];

  List<Map<String, dynamic>> _teacherAssignments = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCustomProfile();
  }

  Future<void> _loadCustomProfile() async {
    final client = Supabase.instance.client;
    final isStudent = widget.access.role == 'estudiante';
    final isTeacher = widget.access.role == 'docente';

    if (isStudent) {
      try {
        // Cargar especialidades oficiales FWT
        final specs = await client.from('technical_specialties').select().order('name');
        if (specs.isNotEmpty && mounted) {
          setState(() {
            _allSpecialties = List<Map<String, dynamic>>.from(specs);
          });
        }

        // Cargar detalle del estudiante
        final detail = await client
            .from('student_details')
            .select('bio, avatar_theme, notes_visibility, chosen_specialty_id, interested_specialties, school_levels(name, code, order_index)')
            .eq('profile_id', widget.access.id)
            .maybeSingle();

        if (detail != null && mounted) {
          final levelMap = detail['school_levels'] as Map?;
          final code = levelMap?['code']?.toString() ?? '';
          final order = (levelMap?['order_index'] as num?)?.toInt() ?? 0;
          final isBach = code.contains('BACH') || order >= 4;

          final interested = detail['interested_specialties'];
          List<String> interestedList = [];
          if (interested is List) {
            interestedList = interested.map((e) => e.toString()).toList();
          }

          setState(() {
            _bioController.text = detail['bio'] ?? '';
            _avatarTheme = detail['avatar_theme'] ?? 'classic';
            _notesVisibility = detail['notes_visibility'] ?? 'private';
            _chosenSpecialtyId = detail['chosen_specialty_id']?.toString();
            _interestedSpecialties = interestedList;
            _schoolLevelName = levelMap?['name'] ?? '';
            _schoolLevelCode = code;
            _isBachillerato = isBach;
          });
        }
      } catch (_) {}
    } else if (isTeacher) {
      try {
        final res = await client.rpc('get_teacher_assignments', params: {'p_teacher_id': widget.access.id});
        if (res is List && mounted) {
          setState(() {
            _teacherAssignments = List<Map<String, dynamic>>.from(res);
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _bioController, _cur, _next, _again]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() job, String ok) async {
    setState(() => _busy = true);
    try {
      await job();
      _snack(ok);
    } on AuthFailure catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = FwtAuth.instance;
    final min = auth.config.minPassword;
    final isStudent = widget.access.role == 'estudiante';
    final isTeacher = widget.access.role == 'docente';

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.forced)
          Card(
            color: Colors.amber.shade100,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Tu cuenta usa una contraseña temporal. Cámbiala para continuar.',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF78350F)),
              ),
            ),
          ),

        // INDICADOR DOCENTE: MATERIAS QUE IMPARTE
        if (isTeacher)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: FwtColors.brand, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.school, color: FwtColors.brand),
                      SizedBox(width: 8),
                      Text(
                        'Mis Materias y Cursos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_teacherAssignments.isEmpty)
                    Text('Aún no tienes materias asignadas.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _teacherAssignments.map((a) {
                        return Chip(
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          side: const BorderSide(color: FwtColors.brand),
                          avatar: const Icon(Icons.book, size: 18, color: FwtColors.brand),
                          label: Text(
                            '${a['subject_name']} (${a['level_name']})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),

        // FORMULARIO: DATOS PERSONALES
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _profileForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Datos Personales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: widget.access.email,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Correo Institucional'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre Completo'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe tu nombre' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  Text('Rol Institucional: ${widget.access.role.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_profileForm.currentState!.validate()) {
                              _run(
                                () => auth.updateProfile(fullName: _name.text, phone: _phone.text),
                                'Perfil actualizado.',
                              );
                            }
                          },
                    child: const Text('Guardar Datos Personales'),
                  ),
                ],
              ),
            ),
          ),
        ),

        // CUSTOMIZACIÓN DE ESTUDIANTE + ESPECIALIDADES FWT
        if (isStudent)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.blue.shade300, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      const Text('Personalización Estudiantil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if (_schoolLevelName.isNotEmpty)
                        Chip(
                          label: Text(_schoolLevelName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.blue.shade50,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bioController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Biografía / Frase de Estudio',
                      hintText: 'Escribe tu lema o meta académica...',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _avatarTheme,
                    decoration: const InputDecoration(labelText: 'Tema de Avatar'),
                    items: const [
                      DropdownMenuItem(value: 'classic', child: Text('Clásico Institucional')),
                      DropdownMenuItem(value: 'tech', child: Text('Técnico Científico')),
                      DropdownMenuItem(value: 'gold', child: Text('Académico de Honor (Dorado)')),
                      DropdownMenuItem(value: 'modern', child: Text('Moderno Minimalista')),
                    ],
                    onChanged: (v) => setState(() => _avatarTheme = v ?? 'classic'),
                  ),
                  const SizedBox(height: 16),

                  // SECCIÓN ESPECIALIDAD: BACHILLERATO VS BÁSICA
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: _isBachillerato
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.workspace_premium, color: FwtColors.brand, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Especialidad de Bachillerato Técnico:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _chosenSpecialtyId,
                                decoration: InputDecoration(
                                  labelText: 'Especialidad Oficial FWT',
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                ),
                                isExpanded: true,
                                items: _allSpecialties.map((s) {
                                  return DropdownMenuItem<String>(
                                    value: s['id'].toString(),
                                    child: Text(s['name']),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _chosenSpecialtyId = val),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Mecanizado · Desarrollo de Software · Automotriz · Música',
                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.explore, color: FwtColors.brand, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Orientación Vocacional (Educación Básica):',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '¿Qué especialidades te gustan para el Bachillerato Técnico? Puedes elegir varias:',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildInterestChip('mecanizado', '⚙️ Mecanizado'),
                                  _buildInterestChip('software', '💻 Software'),
                                  _buildInterestChip('automotriz', '🚗 Automotriz'),
                                  _buildInterestChip('musica', '🎵 Música'),
                                ],
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FwtColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Privacidad de Calificaciones:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        RadioListTile<String>(
                          dense: true,
                          title: const Text('🌐 Públicas (Aparecer en el Ranking Institucional)', style: TextStyle(fontWeight: FontWeight.w600)),
                          value: 'public',
                          groupValue: _notesVisibility,
                          activeColor: FwtColors.brand,
                          onChanged: (val) => setState(() => _notesVisibility = val!),
                        ),
                        RadioListTile<String>(
                          dense: true,
                          title: const Text('🔒 Privadas (Ocultas del Ranking Escolar)', style: TextStyle(fontWeight: FontWeight.w600)),
                          value: 'private',
                          groupValue: _notesVisibility,
                          activeColor: FwtColors.brand,
                          onChanged: (val) => setState(() => _notesVisibility = val!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await _run(() async {
                              // Guardar bio, avatar, notas
                              await Supabase.instance.client.rpc('update_student_custom_profile', params: {
                                'p_bio': _bioController.text.trim(),
                                'p_avatar_theme': _avatarTheme,
                                'p_notes_visibility': _notesVisibility,
                              });

                              // Guardar especialidades o intereses vocacionales
                              await Supabase.instance.client.rpc('update_student_specialties', params: {
                                'p_chosen_specialty_id': _chosenSpecialtyId,
                                'p_interested_specialties': _interestedSpecialties,
                              });
                            }, 'Personalización y especialidades guardadas.');
                          },
                    child: const Text('Guardar Mi Personalización'),
                  ),
                ],
              ),
            ),
          ),

        // CAMBIO DE CONTRASEÑA
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _passForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Seguridad: Cambiar Contraseña', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cur,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña Actual'),
                    validator: (v) => (v ?? '').isEmpty ? 'Obligatoria' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _next,
                    obscureText: true,
                    decoration: InputDecoration(labelText: 'Nueva Contraseña', helperText: 'Mínimo $min caracteres'),
                    validator: (v) => (v ?? '').length < min
                        ? 'Mínimo $min caracteres'
                        : (v == _cur.text ? 'Debe ser distinta de la actual' : null),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _again,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirmar Nueva Contraseña'),
                    validator: (v) => v == _next.text ? null : 'No coinciden',
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!_passForm.currentState!.validate()) return;
                            await _run(
                              () => auth.changePassword(_cur.text, _next.text),
                              'Contraseña actualizada.',
                            );
                            _cur.clear();
                            _next.clear();
                            _again.clear();
                            if (widget.forced) widget.onChanged?.call();
                          },
                    child: const Text('Actualizar Contraseña'),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),
        TextButton(
          onPressed: auth.signOut,
          child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ),
      ],
    );

    return widget.forced ? Scaffold(appBar: AppBar(title: const Text('Mi Perfil')), body: body) : body;
  }

  Widget _buildInterestChip(String code, String label) {
    final isSelected = _interestedSpecialties.contains(code);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: FwtColors.brand.withOpacity(0.2),
      checkmarkColor: FwtColors.brand,
      labelStyle: TextStyle(
        color: isSelected ? FwtColors.brand : Theme.of(context).colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (bool selected) {
        setState(() {
          if (selected) {
            _interestedSpecialties.add(code);
          } else {
            _interestedSpecialties.remove(code);
          }
        });
      },
    );
  }
}
