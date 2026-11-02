import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'chat_room_screen.dart';
import 'person.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.access});
  final Access access;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  int _reload = 0;

  Future<Map<String, dynamic>> _load() => Api.instance.rpcMap('school_chat_list');

  Future<void> _open(Map<String, dynamic> room, Map<String, dynamic>? sanction) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatRoomScreen(access: widget.access, room: room, sanction: sanction),
    ));
    if (mounted) setState(() => _reload++);
  }

  Future<void> _createGroup(Map<String, dynamic>? sanction) async {
    final created = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _CreateGroupSheet(),
    );
    if (created == null || !mounted) return;
    try {
      await Api.instance.client.rpc('school_chat_create', params: {
        'p_kind': 'group',
        'p_title': created['title'],
        'p_description': created['description'],
      });
      if (mounted) {
        snack(context, 'Grupo creado.');
        setState(() => _reload++);
      }
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo crear el grupo.'), error: true);
    }
  }

  Future<void> _newMessage(Map<String, dynamic>? sanction) async {
    final room = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const _PeopleSearchScreen()),
    );
    if (room == null || !mounted) return;
    await _open(room, sanction);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Comunidad'),
            bottom: const TabBar(tabs: [Tab(text: 'Foro'), Tab(text: 'Grupos'), Tab(text: 'Privados')]),
          ),
          body: AsyncView<Map<String, dynamic>>(
            refreshKey: _reload,
            load: _load,
            builder: (context, state, reload) {
              final rooms = (state['rooms'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
              final sanction = state['sanction'] as Map<String, dynamic>?;
              return TabBarView(children: [
                _RoomList(
                  rooms: rooms.where((r) => r['kind'] == 'forum').toList(),
                  empty: 'Todavía no hay foros.',
                  sanction: sanction,
                  onOpen: (r) => _open(r, sanction),
                  onRefresh: reload,
                ),
                _RoomList(
                  rooms: rooms.where((r) => r['kind'] == 'group').toList(),
                  empty: 'Todavía no hay grupos. ¡Crea el primero!',
                  sanction: sanction,
                  onOpen: (r) => _open(r, sanction),
                  onRefresh: reload,
                  action: FilledButton.icon(
                    onPressed: sanction != null ? null : () => _createGroup(sanction),
                    icon: const Icon(Icons.group_add_rounded),
                    label: const Text('Crear grupo'),
                  ),
                ),
                _RoomList(
                  rooms: rooms.where((r) => r['kind'] == 'direct').toList(),
                  empty: 'Aún no tienes mensajes privados.',
                  sanction: sanction,
                  onOpen: (r) => _open(r, sanction),
                  onRefresh: reload,
                  action: FilledButton.icon(
                    onPressed: sanction != null ? null : () => _newMessage(sanction),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Escribir a alguien'),
                  ),
                ),
              ]);
            },
          ),
        ),
      );
}

class _RoomList extends StatelessWidget {
  const _RoomList({
    required this.rooms,
    required this.empty,
    required this.sanction,
    required this.onOpen,
    required this.onRefresh,
    this.action,
  });
  final List<Map<String, dynamic>> rooms;
  final String empty;
  final Map<String, dynamic>? sanction;
  final void Function(Map<String, dynamic>) onOpen;
  final Future<void> Function() onRefresh;
  final Widget? action;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          if (sanction != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Fwt.gold.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: Text(
                'Tu escritura está suspendida ${sanction!['permanent'] == true ? 'de forma permanente' : 'hasta ${shortTime(sanction!['until'])}'}. Motivo: ${sanction!['reason']}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (action != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: action),
          if (rooms.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 40), child: EmptyState(icon: Icons.forum_outlined, text: empty))
          else
            for (final r in rooms)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: _RoomCard(room: r, onTap: () => onOpen(r))),
        ]),
      );
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onTap});
  final Map<String, dynamic> room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = room['kind'] as String;
    final other = Person.maybe(room['other']);
    final closed = room['closed'] == true;
    final status = closed
        ? 'Solo lectura'
        : kind == 'group'
            ? (room['joined'] == true ? 'Ya eres miembro' : 'Grupo abierto del colegio')
            : kind == 'forum'
                ? 'Foro abierto'
                : 'Conversación';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            if (kind == 'direct' && other != null)
              PersonAvatar(person: other, size: 46)
            else
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: Fwt.brand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(kind == 'forum' ? Icons.forum_rounded : Icons.groups_rounded, color: context.brandText),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind == 'direct' ? (other?.name ?? 'Cuenta no disponible') : '${room['title']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(kind == 'direct' ? (other?.label ?? '') : ((room['description'] as String?)?.isNotEmpty ?? false ? '${room['description']}' : status),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted, fontSize: 13)),
                if (kind != 'direct') Text(status, style: TextStyle(color: context.brandText, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet();

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Crear grupo', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Cualquier persona del colegio podrá encontrarlo y unirse. Los moderadores pueden leerlo.', style: TextStyle(color: context.muted)),
            const SizedBox(height: 14),
            TextField(controller: _title, maxLength: 100, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ejemplo: Club de ciencias')),
            const SizedBox(height: 4),
            TextField(controller: _description, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.brandText))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (_title.text.trim().length < 2) {
                  setState(() => _error = 'Escribe un nombre de al menos 2 letras.');
                  return;
                }
                Navigator.pop(context, {'title': _title.text.trim(), 'description': _description.text.trim()});
              },
              child: const Text('Crear'),
            ),
          ]),
        ),
      );
}

/// Busca personas y abre (o crea) la conversación privada con la elegida.
class _PeopleSearchScreen extends StatefulWidget {
  const _PeopleSearchScreen();

  @override
  State<_PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<_PeopleSearchScreen> {
  final _query = TextEditingController();
  final List<Person> _people = [];
  bool _loading = true;
  bool _more = false;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool reset = false}) async {
    if (reset) {
      _people.clear();
      setState(() => _loading = true);
    }
    try {
      final data = await Api.instance.client.rpc('school_chat_people', params: {'p_search': _search, 'p_offset': _people.length});
      final list = (data as List).map((e) => Person.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      setState(() {
        _people.addAll(list);
        _more = list.length == 24;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start(Person p) async {
    try {
      final id = await Api.instance.client.rpc('school_chat_direct', params: {'p_other': p.id});
      final state = await Api.instance.rpcMap('school_chat_list');
      final rooms = (state['rooms'] as List).map((e) => Map<String, dynamic>.from(e as Map));
      final room = rooms.firstWhere((r) => r['id'] == id);
      if (mounted) Navigator.pop(context, room);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo abrir la conversación.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Escribir a alguien')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _search = v.trim();
                _fetch(reset: true);
              },
              decoration: InputDecoration(
                hintText: 'Buscar estudiante o profesor',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () {
                    _search = _query.text.trim();
                    _fetch(reset: true);
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? EmptyState(icon: Icons.cloud_off_rounded, text: _error!, actionLabel: 'Reintentar', onAction: () => _fetch(reset: true))
                    : _people.isEmpty
                        ? const EmptyState(icon: Icons.person_search_rounded, text: 'No se encontraron personas.')
                        : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                            for (final p in _people) PersonTile(person: p, onTap: () => _start(p), trailing: const Icon(Icons.chevron_right_rounded)),
                            if (_more) TextButton(onPressed: _fetch, child: const Text('Ver más personas')),
                          ]),
          ),
        ]),
      );
}
