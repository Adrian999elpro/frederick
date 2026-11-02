import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

const _categories = {
  'general': ('General', Icons.info_outline_rounded),
  'academico': ('Académico', Icons.menu_book_rounded),
  'evento': ('Evento', Icons.event_rounded),
  'urgente': ('Urgente', Icons.priority_high_rounded),
};

Color _categoryColor(BuildContext context, String key) => switch (key) {
      'urgente' => Fwt.accent,
      'academico' => const Color(0xFF0369A1),
      'evento' => const Color(0xFF7E22CE),
      _ => context.muted,
    };

Future<List<Map<String, dynamic>>> loadAnnouncements({String? category, int? limit}) {
  var query = Api.instance.client.from('announcements').select('*, profiles(full_name), school_levels(name)');
  if (category != null) query = query.eq('category', category);
  final ordered = query.order('is_pinned', ascending: false).order('created_at', ascending: false);
  return Api.instance.rows(limit == null ? ordered : ordered.limit(limit));
}

String _date(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class AnnouncementCard extends StatefulWidget {
  const AnnouncementCard({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  State<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<AnnouncementCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final key = (d['category'] as String?) ?? 'general';
    final cat = _categories[key] ?? _categories['general']!;
    final color = _categoryColor(context, key);
    final author = (d['profiles'] as Map?)?['full_name'] as String? ?? '';
    final role = d['author_role_title'] as String? ?? '';
    final level = (d['school_levels'] as Map?)?['name'] as String?;
    final pinned = d['is_pinned'] == true;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(cat.$2, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(cat.$1, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
              if (pinned) ...[
                const SizedBox(width: 8),
                const Icon(Icons.push_pin_rounded, size: 16, color: Fwt.gold),
              ],
              const Spacer(),
              Text(_date(d['created_at'] as String?), style: TextStyle(color: context.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            Text(d['title'] as String? ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              d['content'] as String? ?? '',
              maxLines: _open ? null : 3,
              overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 10),
            Text(
              [if (author.isNotEmpty) author, if (role.isNotEmpty) role, if (level != null) level].join(' · '),
              style: TextStyle(color: context.muted, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Lista de anuncios sin barra superior; se reutiliza en el terminal.
class AnnouncementsBody extends StatefulWidget {
  const AnnouncementsBody({super.key});

  @override
  State<AnnouncementsBody> createState() => _AnnouncementsBodyState();
}

class _AnnouncementsBodyState extends State<AnnouncementsBody> {
  String? _filter;

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: const Text('Todos'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
              ),
              for (final e in _categories.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value.$1),
                    selected: _filter == e.key,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<List<Map<String, dynamic>>>(
            refreshKey: _filter,
            load: () => loadAnnouncements(category: _filter),
            builder: (context, items, reload) => items.isEmpty
                ? const EmptyState(icon: Icons.campaign_outlined, text: 'No hay anuncios por ahora.')
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => AnnouncementCard(data: items[i]),
                    ),
                  ),
          ),
        ),
      ]);
}

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Anuncios')),
        body: const AnnouncementsBody(),
      );
}
