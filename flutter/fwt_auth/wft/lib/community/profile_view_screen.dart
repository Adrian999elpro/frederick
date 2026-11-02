import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'chat_room_screen.dart';
import 'person.dart';

const _badges = {
  'school': '🎓 Aprender',
  'science': '🔬 Ciencia',
  'music': '🎵 Música',
  'sports': '⚽ Deporte',
  'code': '💻 Tecnología',
  'art': '🎨 Arte',
};

class _ProfileData {
  _ProfileData(this.person, this.profile);
  final Person? person;
  final Map<String, dynamic>? profile;
}

Future<_ProfileData> _load(String id) async {
  final api = Api.instance;
  final card = await api.client.rpc('school_person_card', params: {'p_id': id});
  final list = await api.rpcList('school_profiles', {'p_id': id, 'p_search': '', 'p_offset': 0});
  return _ProfileData(Person.maybe(card), list.isEmpty ? null : list.first);
}

/// Perfil de otra persona del colegio; si es privado lo dice con claridad.
class ProfileViewScreen extends StatefulWidget {
  const ProfileViewScreen({super.key, required this.personId, required this.access});
  final String personId;
  final Access access;

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  bool _busy = false;

  Future<void> _message() async {
    setState(() => _busy = true);
    try {
      final roomId = await Api.instance.client.rpc('school_chat_direct', params: {'p_other': widget.personId});
      final state = await Api.instance.rpcMap('school_chat_list');
      final rooms = (state['rooms'] as List).map((e) => Map<String, dynamic>.from(e as Map));
      final room = rooms.firstWhere((r) => r['id'] == roomId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatRoomScreen(access: widget.access, room: room, sanction: state['sanction'] as Map<String, dynamic>?),
      ));
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo abrir la conversación.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Perfil escolar')),
        body: AsyncView<_ProfileData>(
          load: () => _load(widget.personId),
          builder: (context, data, reload) {
            final person = data.person;
            if (person == null) {
              return const EmptyState(icon: Icons.person_off_rounded, text: 'Esta persona no está disponible.');
            }
            final p = data.profile;
            final grades = ((p?['grades'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            final interests = ((p?['interests'] as List?) ?? const []).map((e) => '$e').toList();
            final nickname = (p?['nickname'] as String?) ?? '';
            return ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: PersonAvatar(person: person, size: 96)),
              const SizedBox(height: 12),
              Text(nickname.isNotEmpty ? nickname : person.name,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              if (nickname.isNotEmpty) Text(person.name, textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
              const SizedBox(height: 4),
              Text(person.label, textAlign: TextAlign.center, style: TextStyle(color: person.rankColor, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              if (widget.personId != widget.access.id)
                FilledButton.icon(
                  onPressed: _busy ? null : _message,
                  icon: const Icon(Icons.chat_bubble_rounded),
                  label: const Text('Enviar mensaje'),
                ),
              const SizedBox(height: 16),
              if (p == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(children: [
                      Icon(Icons.lock_rounded, color: context.muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.personId == widget.access.id
                              ? 'Guarda tu presentación en Perfil para ver la vista previa.'
                              : 'Este perfil es privado, así que no se puede ver.',
                          style: TextStyle(color: context.muted, height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((p['badge'] as String?) != null && _badges.containsKey(p['badge']))
                        Text(_badges[p['badge']]!, style: const TextStyle(fontWeight: FontWeight.w800)),
                      if ((p['headline'] as String?)?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(p['headline'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      if ((p['bio'] as String?)?.isNotEmpty ?? false)
                        Padding(padding: const EdgeInsets.only(top: 8), child: Text(p['bio'] as String, style: const TextStyle(height: 1.4))),
                      if ((p['specialty'] as String?)?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Especialidad: ${p['specialty']}', style: TextStyle(color: context.muted)),
                        ),
                      if (interests.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Me interesa: ${interests.join(', ')}', style: TextStyle(color: context.muted)),
                        ),
                    ]),
                  ),
                ),
              if (p != null) ...[
                const SectionTitle('Calificaciones'),
                if (grades.isEmpty)
                  Text(
                    p['show_grades'] == true && p['visibility'] == 'public'
                        ? 'Todavía no hay calificaciones para mostrar.'
                        : 'Las calificaciones no se comparten.',
                    style: TextStyle(color: context.muted),
                  )
                else
                  for (final g in grades)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('${g['subject']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${g['period']}'),
                        trailing: Text('${g['score']} / 10', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
              ],
            ]);
          },
        ),
      );
}
