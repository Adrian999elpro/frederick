import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

const _roles = {
  'admin': 'Administrador',
  'rector': 'Rector',
  'director': 'Director',
  'docente': 'Profesor/a',
  'estudiante': 'Estudiante',
  'encargado_consejo': 'Encargado del consejo',
  'moderador_anuncios': 'Encargado de anuncios',
  'moderador_comunidad': 'Moderador',
  'usuario': 'Comunidad',
};

/// Persona tal como la devuelve `school_person_card` (nombre, rol, curso o materias).
class Person {
  Person({required this.id, required this.name, required this.role, this.level, this.subjects = const []});

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? 'Usuario',
        role: (json['role'] as String?) ?? '',
        level: json['level'] as String?,
        subjects: ((json['subjects'] as List?) ?? const []).map((e) => '$e').toList(),
      );

  static Person? maybe(Object? json) => json is Map ? Person.fromJson(Map<String, dynamic>.from(json)) : null;

  final String id;
  final String name;
  final String role;
  final String? level;
  final List<String> subjects;

  String get label {
    if (role == 'docente') return subjects.isEmpty ? 'Profesor/a' : 'Profesor/a de ${subjects.join(', ')}';
    if (role == 'estudiante') return 'Estudiante · ${level ?? 'Curso pendiente'}';
    return _roles[role] ?? (role.isEmpty ? 'Comunidad' : role.replaceAll('_', ' '));
  }

  /// Color que identifica el rango, como en la web.
  Color get rankColor => switch (role) {
        'admin' || 'rector' || 'director' => Fwt.brand,
        'docente' => const Color(0xFF0369A1),
        'estudiante' => Fwt.ok,
        _ => Fwt.silver,
      };
}

/// Foto de la persona (si es visible) o su inicial, con un aro del color de su rango.
class PersonAvatar extends StatefulWidget {
  const PersonAvatar({super.key, required this.person, this.size = 40});
  final Person person;
  final double size;

  @override
  State<PersonAvatar> createState() => _PersonAvatarState();
}

class _PersonAvatarState extends State<PersonAvatar> {
  String? _url;

  @override
  void initState() {
    super.initState();
    Api.instance.photoUrlCached(widget.person.id).then((url) {
      if (mounted && url != null) setState(() => _url = url);
    });
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.person.rankColor, width: 2)),
        child: Avatar(name: widget.person.name, url: _url, size: widget.size),
      );
}

/// Fila con foto, nombre y cargo; al tocarla abre el perfil.
class PersonTile extends StatelessWidget {
  const PersonTile({super.key, required this.person, this.onTap, this.trailing, this.compact = false});
  final Person person;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
          child: Row(children: [
            PersonAvatar(person: person, size: compact ? 30 : 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(person.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted, fontSize: 12)),
              ]),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      );
}

String shortTime(Object? iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
  return '${d.day}/${d.month} $hm';
}
