import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'person.dart';
import 'profile_view_screen.dart';

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Foro, grupo o conversación privada. Se actualiza sola cada 10 segundos.
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.access, required this.room, this.sanction});
  final Access access;
  final Map<String, dynamic> room;
  final Map<String, dynamic>? sanction;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  late Map<String, dynamic> _room = widget.room;
  final Map<int, Map<String, dynamic>> _items = {};
  final TextEditingController _text = TextEditingController();
  final Map<String, Future<String?>> _images = {};
  Timer? _timer;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasOlder = false;
  bool _sending = false;
  bool _busyRoom = false;
  String? _error;
  Uint8List? _pendingPhoto;

  String get _kind => _room['kind'] as String;
  bool get _closed => _room['closed'] == true;
  bool get _readable => _room['readable'] == true;
  bool get _joined => _room['joined'] == true;
  bool get _canWrite => widget.sanction == null && !_closed && (_kind != 'group' || _joined);
  Person? get _other => Person.maybe(_room['other']);

  @override
  void initState() {
    super.initState();
    if (_readable) {
      _load();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _load(silent: true);
      });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({bool older = false, bool silent = false}) async {
    if (older && _loadingOlder) return;
    if (older) setState(() => _loadingOlder = true);
    try {
      final before = older && _items.isNotEmpty ? _items.keys.reduce(min) : null;
      final data = await Api.instance.client.rpc('school_chat_messages_page', params: {'p_room': _room['id'], 'p_before': before});
      final list = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        for (final m in list) {
          _items[int.parse('${m['id']}')] = m;
        }
        if (older || _items.length <= 50) _hasOlder = list.length >= 50;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = friendlyError(e));
      if (mounted) setState(() => _loading = false);
    } finally {
      if (older && mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _refreshRoom() async {
    final state = await Api.instance.rpcMap('school_chat_list');
    final rooms = (state['rooms'] as List).map((e) => Map<String, dynamic>.from(e as Map));
    final fresh = rooms.where((r) => r['id'] == _room['id']);
    if (fresh.isNotEmpty && mounted) setState(() => _room = fresh.first);
  }

  Future<void> _toggleJoin() async {
    setState(() => _busyRoom = true);
    try {
      await Api.instance.client.rpc('school_chat_join', params: {'p_room': _room['id'], 'p_join': !_joined});
      await _refreshRoom();
      if (_readable && _timer == null) {
        _timer = Timer.periodic(const Duration(seconds: 10), (_) {
          if (mounted) _load(silent: true);
        });
      }
      if (_readable) await _load();
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busyRoom = false);
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) snack(context, 'La foto debe pesar como máximo 5 MB.', error: true);
        return;
      }
      setState(() => _pendingPhoto = bytes);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo elegir la foto.'), error: true);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty && _pendingPhoto == null) return;
    setState(() => _sending = true);
    try {
      String? path;
      if (_pendingPhoto != null) {
        path = '${widget.access.id}/${_room['id']}/${_uuid()}.jpg';
        await Api.instance.client.storage.from('school-chat').uploadBinary(
              path,
              _pendingPhoto!,
              fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '0', upsert: false),
            );
      }
      await Api.instance.client.rpc('school_chat_send', params: {'p_room': _room['id'], 'p_body': body, 'p_image': path});
      _text.clear();
      setState(() => _pendingPhoto = null);
      await _load(silent: true);
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo enviar el mensaje.'), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _removeOwn(Map<String, dynamic> m) async {
    if (!await confirm(context, '¿Retirar tu mensaje de la conversación?', okLabel: 'Retirar')) return;
    try {
      await Api.instance.client.rpc('school_chat_remove', params: {'p_message': m['id'], 'p_reason': null});
      _items.clear();
      await _load();
    } catch (e) {
      if (mounted) snack(context, friendlyError(e, 'No se pudo retirar el mensaje.'), error: true);
    }
  }

  Future<String?> _signed(String path) => _images.putIfAbsent(path, () async {
        try {
          return await Api.instance.client.storage.from('school-chat').createSignedUrl(path, 300);
        } catch (_) {
          return null;
        }
      });

  void _openProfile(Person p) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ProfileViewScreen(personId: p.id, access: widget.access)),
      );

  @override
  Widget build(BuildContext context) {
    final rows = _items.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final other = _other;
    return Scaffold(
      appBar: AppBar(
        title: _kind == 'direct' && other != null
            ? InkWell(onTap: () => _openProfile(other), child: PersonTile(person: other, compact: true))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_room['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                if ((_room['description'] as String?)?.isNotEmpty ?? false)
                  Text('${_room['description']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: context.muted)),
              ]),
        actions: [
          if (_kind == 'group' && !_closed)
            TextButton(
              onPressed: _busyRoom || widget.sanction != null ? null : _toggleJoin,
              child: Text(_joined ? 'Salir' : 'Unirme'),
            ),
        ],
      ),
      body: Column(children: [
        if (widget.sanction != null)
          Container(
            width: double.infinity,
            color: Fwt.gold.withValues(alpha: 0.18),
            padding: const EdgeInsets.all(12),
            child: Text(
              'Tu escritura está suspendida ${widget.sanction!['permanent'] == true ? 'de forma permanente' : 'hasta ${shortTime(widget.sanction!['until'])}'}. Motivo: ${widget.sanction!['reason']}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        if (_closed)
          Container(
            width: double.infinity,
            color: context.line,
            padding: const EdgeInsets.all(10),
            child: const Text('Este espacio está cerrado para nuevos mensajes.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ),
        Expanded(
          child: !_readable
              ? const EmptyState(icon: Icons.group_add_rounded, text: 'Únete al grupo para leer y participar.')
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && rows.isEmpty
                      ? EmptyState(icon: Icons.cloud_off_rounded, text: _error!, actionLabel: 'Reintentar', onAction: _load)
                      : rows.isEmpty
                          ? const EmptyState(icon: Icons.forum_outlined, text: 'Aún no hay mensajes. Puedes empezar la conversación.')
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              itemCount: rows.length + (_hasOlder ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i == rows.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _loadingOlder
                                        ? const Center(child: CircularProgressIndicator())
                                        : TextButton(onPressed: () => _load(older: true), child: const Text('Cargar mensajes anteriores')),
                                  );
                                }
                                final m = rows[i].value;
                                return _Bubble(
                                  message: m,
                                  mine: Person.maybe(m['author'])?.id == widget.access.id,
                                  showAuthor: _kind != 'direct',
                                  signed: _signed,
                                  onAuthor: _openProfile,
                                  onRemove: () => _removeOwn(m),
                                );
                              },
                            ),
        ),
        if (_readable) _composer(context),
      ]),
    );
  }

  Widget _composer(BuildContext context) {
    if (!_canWrite) {
      final text = widget.sanction != null
          ? 'No puedes escribir mientras dure la suspensión.'
          : _closed
              ? 'Solo lectura.'
              : 'Únete al grupo para escribir.';
      return SafeArea(
        child: Padding(padding: const EdgeInsets.all(14), child: Text(text, style: TextStyle(color: context.muted))),
      );
    }
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(color: context.surface, border: Border(top: BorderSide(color: context.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_pendingPhoto != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_pendingPhoto!, height: 84, fit: BoxFit.cover)),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => setState(() => _pendingPhoto = null),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(3),
                        child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(tooltip: 'Adjuntar foto', onPressed: _sending ? null : _pickPhoto, icon: const Icon(Icons.photo_outlined)),
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                maxLength: 3000,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(3000)],
                decoration: const InputDecoration(hintText: 'Escribe con respeto…', counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Fwt.brand, foregroundColor: Colors.white),
              tooltip: 'Enviar mensaje',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showAuthor,
    required this.signed,
    required this.onAuthor,
    required this.onRemove,
  });
  final Map<String, dynamic> message;
  final bool mine;
  final bool showAuthor;
  final Future<String?> Function(String path) signed;
  final void Function(Person) onAuthor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final author = Person.maybe(message['author']);
    final removed = message['removed'] == true;
    final image = message['image_path'] as String?;
    final bg = mine ? Fwt.brand : (context.isDark ? Fwt.darkSurface : Colors.white);
    final fg = mine ? Colors.white : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine && author != null)
            GestureDetector(onTap: () => onAuthor(author), child: PersonAvatar(person: author, size: 30)),
          const SizedBox(width: 6),
          Flexible(
            child: GestureDetector(
              onLongPress: mine && !removed ? onRemove : null,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  border: mine ? null : Border.all(color: context.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!mine && showAuthor && author != null)
                    GestureDetector(
                      onTap: () => onAuthor(author),
                      child: Text('${author.name} · ${author.label}',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: author.rankColor)),
                    ),
                  if (removed)
                    Text('Mensaje retirado. ${message['reason'] ?? ''}', style: TextStyle(fontStyle: FontStyle.italic, color: mine ? Colors.white70 : context.muted))
                  else ...[
                    if ((message['body'] as String?)?.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('${message['body']}', style: TextStyle(color: fg, height: 1.35)),
                      ),
                    if (image != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FutureBuilder<String?>(
                          future: signed(image),
                          builder: (context, s) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: s.data == null
                                ? Container(
                                    height: 120,
                                    width: 200,
                                    color: Colors.black12,
                                    alignment: Alignment.center,
                                    child: s.connectionState == ConnectionState.done
                                        ? const Text('Foto no disponible')
                                        : const CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Image.network(s.data!, width: 220, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                  ],
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(shortTime(message['created_at']), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : context.muted)),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
