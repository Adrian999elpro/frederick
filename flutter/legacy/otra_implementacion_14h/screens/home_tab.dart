import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../nfc.dart';
import '../theme.dart';
import '../ui.dart';
import 'announcements_screen.dart';
import 'vote_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.onGoto});
  final void Function(int index) onGoto;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<List<Json>> _news;
  late Future<List<Json>> _grades;
  late Future<List<Json>> _elections;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final uid = AppScope.read(context).access!.id;
    _news = Api.announcements(limit: 3);
    _grades = Api.myGrades(uid);
    _elections = Api.openElections();
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await Future.wait([_news, _grades, _elections]);
    } catch (_) {}
  }

  Future<void> _activateTerminal() async {
    final app = AppScope.of(context);
    final ok = await confirmDialog(
      context,
      'El teléfono quedará en modo terminal escolar con la pantalla fijada. Para salir necesitarás la tarjeta del encargado.',
      okLabel: 'Activar',
      title: 'Activar terminal',
    );
    if (!ok || !mounted) return;
    await app.setTerminalMode('announcements');
    await app.setTerminal(true);
    try {
      await NfcBridge.pin();
    } on NfcException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final access = app.access!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHero(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(name: access.fullName, userId: access.id, size: 56, ring: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TU ESPACIO ESCOLAR',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'Hola, ${access.firstName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    const FwtLogo(size: 44),
                  ],
                ),
                const SizedBox(height: 22),
                FutureBuilder<List<Json>>(
                  future: _grades,
                  builder: (context, snap) {
                    final rows = snap.data ?? const <Json>[];
                    final scores = rows.map((g) => asDouble(g['score'])).whereType<double>().toList();
                    final avg = scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
                    return Row(
                      children: [
                        Expanded(
                          child: _HeroStat(
                            label: 'Promedio general',
                            value: avg == null ? '—' : avg.toStringAsFixed(2),
                            icon: Icons.stars_rounded,
                            onTap: () => widget.onGoto(1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FutureBuilder<List<Json>>(
                            future: _elections,
                            builder: (context, es) {
                              final pending = (es.data ?? const <Json>[])
                                  .where((e) => (e['my_receipt'] as List?)?.isEmpty ?? true)
                                  .length;
                              return _HeroStat(
                                label: 'Votaciones abiertas',
                                value: '$pending',
                                icon: Icons.how_to_vote_rounded,
                                onTap: () => Navigator.of(context)
                                    .push(MaterialPageRoute<void>(builder: (_) => const VoteScreen())),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (access.can('terminal.operate')) ...[
                  const SizedBox(height: 16),
                  FwtCard(
                    color: FwtColors.ink,
                    onTap: _activateTerminal,
                    child: const Row(
                      children: [
                        Icon(Icons.tablet_android_rounded, color: FwtColors.gold, size: 32),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Terminal escolar',
                                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                              Text('Asistencia, votaciones y registro de tarjetas',
                                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.white70),
                      ],
                    ),
                  ),
                ],
                const SectionTitle('Accesos rápidos'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    _QuickTile(icon: Icons.school_rounded, label: 'Mis notas', onTap: () => widget.onGoto(1)),
                    _QuickTile(
                      icon: Icons.campaign_rounded,
                      label: 'Novedades',
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const AnnouncementsScreen())),
                    ),
                    _QuickTile(
                      icon: Icons.how_to_vote_rounded,
                      label: 'Votar',
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const VoteScreen())),
                    ),
                    _QuickTile(icon: Icons.emoji_events_rounded, label: 'Ranking', onTap: () => widget.onGoto(3)),
                  ],
                ),
                SectionTitle(
                  'Últimas novedades',
                  action: 'Ver todas',
                  onAction: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const AnnouncementsScreen())),
                ),
                AsyncView<List<Json>>(
                  future: _news,
                  onRetry: _refresh,
                  builder: (context, items) {
                    if (items.isEmpty) {
                      return const EmptyBox(
                        icon: Icons.mark_email_unread_outlined,
                        title: 'Sin novedades por ahora',
                        message: 'Los avisos del colegio aparecerán aquí.',
                      );
                    }
                    return Column(
                      children: [
                        for (final n in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AnnouncementCard(item: n, compact: true),
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

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, required this.icon, required this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: FwtColors.gold, size: 22),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FwtCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: cs.primary),
          ),
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
