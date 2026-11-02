import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Ranking'),
            bottom: const TabBar(tabs: [Tab(text: 'General'), Tab(text: 'Por materia')]),
          ),
          body: const TabBarView(children: [_GeneralRanking(), _SubjectRanking()]),
        ),
      );
}

Color _medal(int index) => switch (index) {
      0 => Fwt.gold,
      1 => Fwt.silver,
      _ => Fwt.bronze,
    };

class _Podium extends StatelessWidget {
  const _Podium({required this.entries});
  final List<({String name, String detail, double score})> entries;

  @override
  Widget build(BuildContext context) {
    // Orden visual: 2.º, 1.º, 3.º
    final order = [if (entries.length > 1) 1, 0, if (entries.length > 2) 2];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final i in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
                decoration: BoxDecoration(
                  color: _medal(i).withValues(alpha: 0.12),
                  border: Border.all(color: _medal(i), width: i == 0 ? 2 : 1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: i == 0 ? 40 : 32,
                    height: i == 0 ? 40 : 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _medal(i), shape: BoxShape.circle),
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 8),
                  Text(entries[i].name,
                      maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.2)),
                  const SizedBox(height: 2),
                  Text(entries[i].detail,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.muted, fontSize: 11)),
                  const SizedBox(height: 6),
                  Text(entries[i].score.toStringAsFixed(2),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: i == 0 ? 22 : 18, color: _medal(i))),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _RankRows extends StatelessWidget {
  const _RankRows({required this.entries, required this.onRefresh});
  final List<({String name, String detail, double score})> entries;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(icon: Icons.emoji_events_outlined, text: 'Todavía no hay notas públicas para mostrar.');
    }
    final top = entries.take(3).toList();
    final rest = entries.skip(3).toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        _Podium(entries: top),
        for (var i = 0; i < rest.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: context.line,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: Text('${i + 4}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                title: Text(rest[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(rest[i].detail, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(rest[i].score.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              ),
            ),
          ),
      ]),
    );
  }
}

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class _GeneralRanking extends StatefulWidget {
  const _GeneralRanking();

  @override
  State<_GeneralRanking> createState() => _GeneralRankingState();
}

class _GeneralRankingState extends State<_GeneralRanking> with AutomaticKeepAliveClientMixin {
  String? _level;
  late final Future<List<Map<String, dynamic>>> _levels =
      Api.instance.rows(Api.instance.client.from('school_levels').select('id, name').order('order_index'));

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _levels,
        builder: (context, s) => SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: const Text('Todos'), selected: _level == null, onSelected: (_) => setState(() => _level = null)),
              ),
              for (final l in s.data ?? const <Map<String, dynamic>>[])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(l['name'] as String),
                    selected: _level == l['id'],
                    onSelected: (_) => setState(() => _level = l['id'] as String),
                  ),
                ),
            ],
          ),
        ),
      ),
      Expanded(
        child: AsyncView<List<Map<String, dynamic>>>(
          refreshKey: _level,
          load: () => Api.instance.rpcList('get_academic_ranking', {'p_level_id': _level}),
          builder: (context, rows, reload) => _RankRows(
            onRefresh: reload,
            entries: [
              for (final r in rows)
                (
                  name: (r['full_name'] as String?) ?? '',
                  detail: [r['level_name'], if ((r['specialty_name'] ?? '') != '') r['specialty_name']].join(' · '),
                  score: _num(r['average_score']),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _SubjectRanking extends StatefulWidget {
  const _SubjectRanking();

  @override
  State<_SubjectRanking> createState() => _SubjectRankingState();
}

class _SubjectRankingState extends State<_SubjectRanking> with AutomaticKeepAliveClientMixin {
  String? _subject;
  late final Future<List<Map<String, dynamic>>> _subjects =
      Api.instance.rows(Api.instance.client.from('subjects').select('id, name, code').order('name'));

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _subjects,
          builder: (context, s) => DropdownButtonFormField<String>(
            initialValue: _subject,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Materia'),
            items: [
              for (final m in s.data ?? const <Map<String, dynamic>>[])
                DropdownMenuItem(value: m['id'] as String, child: Text(m['name'] as String, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _subject = v),
          ),
        ),
      ),
      Expanded(
        child: _subject == null
            ? const EmptyState(icon: Icons.menu_book_rounded, text: 'Elige una materia para ver su cuadro de honor.')
            : AsyncView<List<Map<String, dynamic>>>(
                refreshKey: _subject,
                load: () => Api.instance.rpcList('get_subject_ranking', {'p_subject_id': _subject}),
                builder: (context, rows, reload) => _RankRows(
                  onRefresh: reload,
                  entries: [
                    for (final r in rows)
                      (
                        name: (r['full_name'] as String?) ?? '',
                        detail: '${r['level_name'] ?? ''}',
                        score: _num(r['score']),
                      ),
                  ],
                ),
              ),
      ),
    ]);
  }
}
