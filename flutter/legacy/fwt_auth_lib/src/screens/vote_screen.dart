import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_service.dart';

/// Papeleta de votación: una tarjeta por lista con la foto del presidente, voto en blanco y confirmación.
class VoteScreen extends StatefulWidget {
  const VoteScreen({super.key});
  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  late Future<_Data> _future = _load();
  final Map<String, String> _choice = {}; // electionId -> listId ('' = voto en blanco)

  Future<_Data> _load() async {
    final c = FwtAuth.instance.client;
    final now = DateTime.now().toUtc().toIso8601String();
    // Una consulta: votaciones abiertas + si ya votó (RLS solo deja ver el propio comprobante).
    final elections = await c
        .from('elections')
        .select('id,title,ends_at,my_receipt:vote_receipts(voted_at)')
        .eq('status', 'open')
        .lte('starts_at', now)
        .gt('ends_at', now)
        .order('ends_at');
    final pending = [for (final e in elections) if ((e['my_receipt'] as List).isEmpty) e['id'] as String];
    var lists = <Map<String, dynamic>>[];
    var urls = <String, String>{};
    if (pending.isNotEmpty) {
      lists = List<Map<String, dynamic>>.from(
          await c.from('election_lists').select('id,election_id,number,name,slogan,president_name,president_photo').inFilter('election_id', pending).order('number'));
      final paths = {for (final l in lists) if (l['president_photo'] != null) l['president_photo'] as String}.toList();
      if (paths.isNotEmpty) {
        final signed = await c.storage.from('election-photos').createSignedUrls(paths, 3600); // una sola llamada
        urls = {for (final s in signed) s.path: s.signedUrl};
      }
    }
    return _Data(List<Map<String, dynamic>>.from(elections), lists, urls);
  }

  Future<void> _vote(Map<String, dynamic> e, List<Map<String, dynamic>> lists) async {
    final id = e['id'] as String;
    final choice = _choice[id];
    if (choice == null) return;
    final label = choice.isEmpty ? 'voto en blanco' : lists.firstWhere((l) => l['id'] == choice)['name'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar voto'),
        content: Text('Vas a votar por: $label. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Emitir voto')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FwtAuth.instance.client.rpc('cast_vote', params: {'p_election': id, 'p_list': choice.isEmpty ? null : choice});
      _snack('Voto registrado.');
    } on PostgrestException catch (ex) {
      _snack(friendlyError(ex));
    }
    if (mounted) setState(() => _future = _load());
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('No se pudieron cargar las votaciones.'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          if (d.elections.isEmpty) return const Center(child: Text('No hay votaciones abiertas por ahora.'));
          return ListView(padding: const EdgeInsets.all(16), children: [for (final e in d.elections) _ballot(context, e, d)]);
        },
      );

  Widget _ballot(BuildContext context, Map<String, dynamic> e, _Data d) {
    final t = Theme.of(context);
    final id = e['id'] as String;
    if ((e['my_receipt'] as List).isNotEmpty) {
      return Card(child: ListTile(title: Text(e['title'] as String), subtitle: const Text('Tu voto quedó registrado. Gracias por participar.'), leading: const Icon(Icons.check_circle)));
    }
    final lists = d.lists.where((l) => l['election_id'] == id).toList();
    Widget option({required String value, required Widget leading, required String title, String? subtitle}) {
      final selected = _choice[id] == value;
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: selected ? t.colorScheme.primary : t.dividerColor, width: selected ? 2 : 1)),
        child: InkWell(
          onTap: () => setState(() => _choice[id] = value),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (subtitle != null) Text(subtitle),
              ])),
              Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, size: 32, semanticLabel: selected ? 'Seleccionada' : 'No seleccionada'),
            ]),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: t.colorScheme.onSurface, width: 2), borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(e['title'] as String, style: t.textTheme.titleLarge),
        const Text('Tu voto es secreto y no se puede cambiar.'),
        const Divider(),
        for (final l in lists)
          option(
            value: l['id'] as String,
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${l['number']}', style: t.textTheme.headlineMedium),
              const SizedBox(width: 10),
              _photo(d.urls[l['president_photo']], l['president_name'] as String),
            ]),
            title: 'Lista ${l['number']} · ${l['name']}',
            subtitle: 'Presidente/a: ${l['president_name']}${(l['slogan'] as String).isEmpty ? '' : '\n${l['slogan']}'}',
          ),
        option(value: '', leading: const SizedBox(width: 56, child: Icon(Icons.not_interested)), title: 'Voto en blanco'),
        const SizedBox(height: 8),
        FilledButton(onPressed: _choice[id] == null ? null : () => _vote(e, lists), child: const Text('Emitir voto')),
      ]),
    );
  }

  Widget _photo(String? url, String name) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56,
          height: 56,
          child: url == null
              ? ColoredBox(color: Colors.black12, child: Center(child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))))
              : Image.network(url, fit: BoxFit.cover, semanticLabel: 'Foto de $name', errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12)),
        ),
      );
}

class _Data {
  _Data(this.elections, this.lists, this.urls);
  final List<Map<String, dynamic>> elections;
  final List<Map<String, dynamic>> lists;
  final Map<String, String> urls;
}
