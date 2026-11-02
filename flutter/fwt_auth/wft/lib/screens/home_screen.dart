import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'announcements_screen.dart';
import 'grades_screen.dart';
import 'ranking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.access, required this.go});
  final Access access;
  final void Function(String tab) go;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<String?> _photo = Api.instance.photoUrl(widget.access.id);
  int _reload = 0;

  Future<void> _refresh() async {
    setState(() {
      _photo = Api.instance.photoUrl(widget.access.id);
      _reload++;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  String get _roleLabel {
    final r = widget.access.role;
    return r.isEmpty ? '' : '${r[0].toUpperCase()}${r.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.access;
    final tiles = <(String, IconData, String, VoidCallback)>[
      if (a.isStudent) ('Carnet', Icons.badge_rounded, 'Mi carnet digital', () => widget.go('Carnet')),
      if (a.isStudent) ('Votar', Icons.how_to_vote_rounded, 'Votaciones y postulaciones', () => widget.go('Votar')),
      ('Comunidad', Icons.forum_rounded, 'Foro, grupos y mensajes', () => widget.go('Comunidad')),
      (
        'Ranking',
        Icons.emoji_events_rounded,
        'Mejores promedios',
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RankingScreen())),
      ),
      if (a.isStudent)
        (
          'Mis notas',
          Icons.grading_rounded,
          'Por materia y período',
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GradesScreen(access: a))),
        ),
      ('Perfil', Icons.person_rounded, 'Mi perfil y privacidad', () => widget.go('Perfil')),
    ];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: EdgeInsets.zero, children: [
        HeroHeader(
          child: Row(children: [
            FutureBuilder<String?>(
              future: _photo,
              builder: (_, s) => Avatar(name: a.fullName, url: s.data, size: 64),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TU ESPACIO ESCOLAR',
                    style: TextStyle(color: Fwt.gold, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text('Hola, ${a.firstName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                if (_roleLabel.isNotEmpty) Text(_roleLabel, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
            const SchoolLogo(size: 44),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('¿Qué necesitas hacer hoy?'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [for (final t in tiles) _Tile(label: t.$1, icon: t.$2, subtitle: t.$3, onTap: t.$4)],
            ),
            SectionTitle(
              'Últimos anuncios',
              action: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AnnouncementsScreen())),
                child: const Text('Ver todos'),
              ),
            ),
            AsyncView<List<Map<String, dynamic>>>(
              refreshKey: _reload,
              load: () => loadAnnouncements(limit: 3),
              builder: (context, items, _) => items.isEmpty
                  ? const Padding(padding: EdgeInsets.all(24), child: EmptyState(icon: Icons.campaign_outlined, text: 'No hay anuncios por ahora.'))
                  : Column(children: [
                      for (final d in items) Padding(padding: const EdgeInsets.only(bottom: 12), child: AnnouncementCard(data: d)),
                    ]),
            ),
            if (a.can('users.manage') || a.can('roles.manage') || a.can('grades.upload'))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.admin_panel_settings_rounded, color: context.brandText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('La administración (usuarios, roles y notas) se hace desde la web de Frederick.',
                          style: TextStyle(color: context.muted)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.icon, required this.subtitle, required this.onTap});
  final String label;
  final IconData icon;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Fwt.brand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: context.brandText),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(subtitle, style: TextStyle(color: context.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ),
      );
}
