import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_service.dart';
import '../theme.dart';

/// Estadísticas Electorales: participación y resultados por lista (una sola llamada al servidor).
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<Map<String, dynamic>> _elections = [];
  String? _selected;
  Map<String, dynamic>? _result;
  Map<String, String> _urls = {};
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = FwtAuth.instance.client;
      _elections = List<Map<String, dynamic>>.from(await c.from('elections').select('id,title,status').order('created_at', ascending: false));
      if (_elections.isNotEmpty) {
        _selected = _elections.first['id'] as String;
        await _loadResults();
        return;
      }
    } catch (_) {
      _message = 'No se pudieron cargar las votaciones.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadResults() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final c = FwtAuth.instance.client;
    try {
      final r = Map<String, dynamic>.from(await c.rpc('election_results', params: {'p_election': _selected}) as Map);
      final paths = [for (final l in r['lists'] as List) if (l['president_photo'] != null) l['president_photo'] as String];
      var urls = <String, String>{};
      if (paths.isNotEmpty) {
        final signed = await c.storage.from('election-photos').createSignedUrls(paths, 3600);
        urls = {for (final s in signed) s.path: s.signedUrl};
      }
      _result = r;
      _urls = urls;
    } on PostgrestException catch (e) {
      _result = null;
      _message = friendlyError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _fmt(double x) => '${x.toStringAsFixed(1).replaceAll('.', ',')} %';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_elections.isEmpty && !_loading) return Center(child: Text(_message ?? 'Aún no hay votaciones.'));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Estadísticas Electorales', style: t.textTheme.headlineSmall),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _selected,
            decoration: const InputDecoration(labelText: 'Votación'),
            items: [for (final e in _elections) DropdownMenuItem(value: e['id'] as String, child: Text(e['title'] as String, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              _selected = v;
              _loadResults();
            },
          ),
        ),
        IconButton(onPressed: _loadResults, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
      ]),
      const SizedBox(height: 16),
      if (_loading) const Center(child: CircularProgressIndicator()),
      if (_message != null) Card(color: t.colorScheme.tertiaryContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!))),
      if (!_loading && _result != null) ..._content(t),
    ]);
  }

  List<Widget> _content(ThemeData t) {
    final r = _result!;
    final total = r['total_votes'] as int, eligible = r['eligible'] as int, blank = r['blank'] as int;
    final closed = r['status'] == 'closed';
    final lists = List<Map<String, dynamic>>.from(r['lists'] as List);
    final top = lists.fold<int>(0, (m, l) => (l['votes'] as int) > m ? l['votes'] as int : m);
    double pct(int n, int d) => d == 0 ? 0 : n * 100 / d;
    Widget stat(String big, String label) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(big, style: t.textTheme.headlineSmall), Text(label, style: t.textTheme.bodySmall)]))));
    return [
      if (!closed) Card(color: t.colorScheme.tertiaryContainer, child: const Padding(padding: EdgeInsets.all(12), child: Text('Resultados parciales: la votación sigue abierta.'))),
      Row(children: [stat('$total', 'votos emitidos'), stat(_fmt(pct(total, eligible)), 'participación ($total de $eligible)'), stat('$blank', 'en blanco')]),
      const SizedBox(height: 8),
      for (final l in lists)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: _urls[l['president_photo']] != null ? NetworkImage(_urls[l['president_photo']]!) : null,
              child: _urls[l['president_photo']] == null ? Text((l['president_name'] as String).isEmpty ? '?' : (l['president_name'] as String)[0].toUpperCase()) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Lista ${l['number']} · ${l['name']} — ${l['president_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: pct(l['votes'] as int, total) / 100,
                minHeight: 12,
                borderRadius: BorderRadius.circular(8),
                color: closed && top > 0 && l['votes'] == top ? FwtColors.accent : null,
              ),
              Text('${l['votes']} votos · ${_fmt(pct(l['votes'] as int, total))}', style: t.textTheme.bodySmall),
            ])),
          ]),
        ),
    ];
  }
}
