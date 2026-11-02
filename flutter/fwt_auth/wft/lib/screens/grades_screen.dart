import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class _Subject {
  _Subject(this.name);
  final String name;
  final List<({String period, int order, double score})> scores = [];
  double get average => scores.isEmpty ? 0 : scores.map((s) => s.score).reduce((a, b) => a + b) / scores.length;
}

Future<List<_Subject>> _loadGrades(String studentId) async {
  final rows = await Api.instance.rows(Api.instance.client
      .from('grades')
      .select('score, subjects(name), grade_periods(name, order_index)')
      .eq('student_id', studentId));
  final bySubject = <String, _Subject>{};
  for (final r in rows) {
    final name = (r['subjects'] as Map?)?['name'] as String? ?? 'Materia';
    final period = r['grade_periods'] as Map?;
    final subject = bySubject.putIfAbsent(name, () => _Subject(name));
    subject.scores.add((
      period: period?['name'] as String? ?? '',
      order: (period?['order_index'] as num?)?.toInt() ?? 0,
      score: (r['score'] as num).toDouble(),
    ));
  }
  final list = bySubject.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  for (final s in list) {
    s.scores.sort((a, b) => a.order.compareTo(b.order));
  }
  return list;
}

Color _scoreColor(double v) => v >= 9 ? Fwt.ok : (v >= 7 ? Fwt.gold : Fwt.accent);

class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key, required this.access});
  final Access access;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mis notas')),
        body: AsyncView<List<_Subject>>(
          load: () => _loadGrades(access.id),
          builder: (context, subjects, reload) {
            if (subjects.isEmpty) {
              return const EmptyState(icon: Icons.grading_rounded, text: 'Todavía no hay notas registradas.');
            }
            final all = subjects.expand((s) => s.scores).map((s) => s.score).toList();
            final general = all.reduce((a, b) => a + b) / all.length;
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(gradient: Fwt.heroGradient, borderRadius: BorderRadius.circular(22)),
                  child: Row(children: [
                    const Expanded(
                      child: Text('Promedio general', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    Text(general.toStringAsFixed(2),
                        style: const TextStyle(color: Fwt.gold, fontSize: 34, fontWeight: FontWeight.w900)),
                    const Text(' / 10', style: TextStyle(color: Colors.white70)),
                  ]),
                ),
                const SizedBox(height: 12),
                for (final s in subjects)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                            Text(s.average.toStringAsFixed(2),
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: _scoreColor(s.average))),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            for (final p in s.scores)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('${p.period}: ${p.score.toStringAsFixed(2)}'),
                              ),
                          ]),
                        ]),
                      ),
                    ),
                  ),
              ]),
            );
          },
        ),
      );
}
