import 'package:flutter/material.dart';

import '../core/api.dart';
import 'announcements_screen.dart';
import '../community/community_screen.dart';
import 'card_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'ranking_screen.dart';
import 'vote_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.build);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function(Access access, void Function(String) go) build;
}

/// App principal con barra inferior. Las pestañas dependen del rol.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.access});
  final Access access;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  late final List<_Tab> _tabs = _buildTabs(widget.access);

  @override
  void initState() {
    super.initState();
    if (widget.access.mustChangePassword) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showChangePasswordSheet(context, forced: true);
      });
    }
  }

  List<_Tab> _buildTabs(Access a) => [
        _Tab('Inicio', Icons.home_outlined, Icons.home_rounded, (a, go) => HomeScreen(access: a, go: go)),
        _Tab('Comunidad', Icons.forum_outlined, Icons.forum_rounded, (a, go) => CommunityScreen(access: a)),
        if (a.isStudent)
          _Tab('Carnet', Icons.badge_outlined, Icons.badge_rounded, (a, go) => CardScreen(access: a)),
        if (a.isStudent)
          _Tab('Votar', Icons.how_to_vote_outlined, Icons.how_to_vote_rounded, (a, go) => VoteScreen(access: a)),
        if (!a.isStudent)
          _Tab('Ranking', Icons.emoji_events_outlined, Icons.emoji_events_rounded, (a, go) => const RankingScreen()),
        if (!a.isStudent)
          _Tab('Anuncios', Icons.campaign_outlined, Icons.campaign_rounded, (a, go) => const AnnouncementsScreen()),
        _Tab('Perfil', Icons.person_outline_rounded, Icons.person_rounded, (a, go) => ProfileScreen(access: a)),
      ];

  /// Cambia de pestaña por su nombre ("Carnet", "Votar"…); si no existe para este rol, no hace nada.
  void _go(String label) {
    final target = _tabs.indexWhere((t) => t.label == label);
    if (target >= 0) setState(() => _index = target);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _index = 0);
        },
        child: Scaffold(
          body: IndexedStack(
            index: _index,
            children: [for (final t in _tabs) t.build(widget.access, _go)],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final t in _tabs)
                NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
            ],
          ),
        ),
      );
}
