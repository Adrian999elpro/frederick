import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../ui.dart';

class RankingTab extends StatefulWidget {
  const RankingTab({super.key});

  @override
  State<RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<RankingTab> {
  String? _levelId;
  late final Future<List<Json>> _levels = Api.levels();
  late Future<List<Json>> _future = Api.ranking(null);

  void _reload() => setState(() => _future = Api.ranking(_levelId));

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await _future;
        } catch (_) {}
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHero(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ranking escolar',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Los estudiantes con mejor promedio',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder<List<Json>>(
                  future: _levels,
                  builder: (context, snap) {
                    final levels = snap.data ?? const <Json>[];
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos los cursos'),
                          selected: _levelId == null,
                          onSelected: (_) {
                            _levelId = null;
                            _reload();
                          },
                        ),
                        for (final l in levels)
                          ChoiceChip(
                            label: Text('${l['name']}'),
                            selected: _levelId == l['id'],
                            onSelected: (_) {
                              _levelId = '${l['id']}';
                              _reload();
                            },
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                AsyncView<List<Json>>(
                  future: _future,
                  onRetry: _reload,
                  builder: (context, rows) {
                    if (rows.isEmpty) {
                      return const EmptyBox(
                        icon: Icons.emoji_events_outlined,
                        title: 'Aún no hay ranking',
                        message: 'Aparecerá cuando haya calificaciones registradas.',
                      );
                    }
                    final top = rows.take(3).toList();
                    final rest = rows.skip(3).toList();
                    return Column(
                      children: [
                        _Podium(top: top),
                        const SizedBox(height: 16),
                        for (var i = 0; i < rest.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RankRow(position: i + 4, row: rest[i]),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _avgText(Json row) {
  final v = asDouble(row['average_score']);
  return v == null ? '🔒' : v.toStringAsFixed(2);
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top});
  final List<Json> top;

  @override
  Widget build(BuildContext context) {
    // Orden visual: 2.º, 1.º, 3.º
    final order = <int>[1, 0, 2].where((i) => i < top.length).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final i in order)
          Expanded(
            child: _PodiumSlot(position: i + 1, row: top[i]),
          ),
      ],
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  const _PodiumSlot({required this.position, required this.row});
  final int position;
  final Json row;

  @override
  Widget build(BuildContext context) {
    final color = position == 1 ? FwtColors.gold : position == 2 ? FwtColors.silver : FwtColors.bronze;
    final height = position == 1 ? 110.0 : position == 2 ? 84.0 : 68.0;
    final name = '${row['full_name'] ?? ''}';
    return Column(
      children: [
        if (position == 1) const Icon(Icons.workspace_premium_rounded, color: FwtColors.gold, size: 30),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 3)),
          child: UserAvatar(name: name, userId: '${row['student_id']}', size: position == 1 ? 64 : 54),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$position', style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900)),
              Text(_avgText(row), style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.position, required this.row});
  final int position;
  final Json row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = '${row['full_name'] ?? ''}';
    return FwtCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('$position', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          UserAvatar(name: name, userId: '${row['student_id']}', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${row['level_name'] ?? ''}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Text(_avgText(row), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
