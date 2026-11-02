import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../ui.dart';

class GradesTab extends StatefulWidget {
  const GradesTab({super.key});

  @override
  State<GradesTab> createState() => _GradesTabState();
}

class _GradesTabState extends State<GradesTab> {
  late Future<List<Json>> _future;

  @override
  void initState() {
    super.initState();
    _future = Api.myGrades(AppScope.read(context).access!.id);
  }

  void _reload() => setState(() => _future = Api.myGrades(AppScope.read(context).access!.id));

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
          FutureBuilder<List<Json>>(
            future: _future,
            builder: (context, snap) {
              final rows = snap.data ?? const <Json>[];
              final scores = rows.map((g) => asDouble(g['score'])).whereType<double>().toList();
              final avg = scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
              return GradientHero(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mis calificaciones',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          avg == null ? '—' : avg.toStringAsFixed(2),
                          style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, height: 1),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('/ 10 promedio general',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${scores.length} ${scores.length == 1 ? 'nota registrada' : 'notas registradas'}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: AsyncView<List<Json>>(
              future: _future,
              onRetry: _reload,
              builder: (context, rows) {
                if (rows.isEmpty) {
                  return const EmptyBox(
                    icon: Icons.assignment_outlined,
                    title: 'Todavía no hay notas',
                    message: 'Cuando tus docentes registren calificaciones, las verás aquí.',
                  );
                }
                // Agrupa por período, ordenado por order_index.
                final byPeriod = <String, List<Json>>{};
                final order = <String, num>{};
                for (final g in rows) {
                  final p = (g['grade_periods'] as Map?) ?? const {};
                  final name = '${p['name'] ?? 'Período'}';
                  byPeriod.putIfAbsent(name, () => []).add(g);
                  order[name] = (p['order_index'] as num?) ?? 0;
                }
                final names = byPeriod.keys.toList()..sort((a, b) => order[a]!.compareTo(order[b]!));
                return Column(
                  children: [
                    for (final name in names)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PeriodCard(name: name, grades: byPeriod[name]!),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.name, required this.grades});
  final String name;
  final List<Json> grades;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = [...grades]..sort((a, b) =>
        '${(a['subjects'] as Map?)?['name']}'.compareTo('${(b['subjects'] as Map?)?['name']}'));
    final scores = sorted.map((g) => asDouble(g['score'])).whereType<double>().toList();
    final avg = scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
    return FwtCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          subtitle: Text('${sorted.length} materias'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scoreColor(context, avg).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              fmtScore(avg),
              style: TextStyle(color: scoreColor(context, avg), fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
          children: [
            for (final g in sorted)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${(g['subjects'] as Map?)?['name'] ?? 'Materia'}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          if ('${g['feedback'] ?? ''}'.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('${g['feedback']}',
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      fmtScore(g['score']),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: g['score'] == null ? FwtColors.silver : scoreColor(context, asDouble(g['score'])),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
