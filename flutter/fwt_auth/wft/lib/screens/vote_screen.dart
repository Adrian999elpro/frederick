import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'applications_screen.dart';

class _Ballot {
  _Ballot(this.election, this.lists, this.photos, this.voted);
  final Map<String, dynamic> election;
  final List<Map<String, dynamic>> lists;
  final Map<String, String> photos;
  final bool voted;
}

Future<List<_Ballot>> _loadBallots() async {
  final api = Api.instance;
  final now = DateTime.now().toUtc().toIso8601String();
  final elections = await api.rows(api.client
      .from('elections')
      .select('id, title, description, ends_at, my_receipt:vote_receipts(voted_at)')
      .eq('status', 'open')
      .lte('starts_at', now)
      .gt('ends_at', now)
      .order('ends_at'));
  final pending = elections.where((e) => ((e['my_receipt'] as List?) ?? const []).isEmpty).toList();
  var lists = <Map<String, dynamic>>[];
  if (pending.isNotEmpty) {
    lists = await api.rows(api.client
        .from('election_lists')
        .select('id, election_id, number, name, slogan, president_name, president_photo')
        .inFilter('election_id', pending.map((e) => e['id'] as String).toList())
        .order('number'));
  }
  final photos = <String, String>{};
  for (final l in lists) {
    final path = l['president_photo'] as String?;
    if (path == null || path.isEmpty) continue;
    try {
      photos[path] = await api.client.storage.from('election-photos').createSignedUrl(path, 600);
    } catch (_) {}
  }
  return [
    for (final e in elections)
      _Ballot(
        e,
        lists.where((l) => l['election_id'] == e['id']).toList(),
        photos,
        ((e['my_receipt'] as List?) ?? const []).isNotEmpty,
      ),
  ];
}

class VoteScreen extends StatefulWidget {
  const VoteScreen({super.key, required this.access});
  final Access access;

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Votar')),
        body: AsyncView<List<_Ballot>>(
          refreshKey: _reload,
          load: _loadBallots,
          builder: (context, ballots, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              if (ballots.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(icon: Icons.how_to_vote_outlined, text: 'No hay votaciones abiertas por ahora.'),
                ),
              for (final b in ballots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: b.voted
                      ? _DoneCard(title: b.election['title'] as String)
                      : _BallotCard(ballot: b, onVoted: () => setState(() => _reload++)),
                ),
              _ApplicationsLink(access: widget.access),
              const SizedBox(height: 12),
              const _TerminalNote(),
            ]),
          ),
        ),
      );
}

class _TerminalNote extends StatelessWidget {
  const _TerminalNote();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(Icons.contactless_rounded, color: context.brandText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Las votaciones del consejo y las personalizadas se hacen en el terminal del colegio, acercando tu tarjeta.',
                style: TextStyle(color: context.muted, height: 1.35),
              ),
            ),
          ]),
        ),
      );
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Fwt.ok, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text('Tu voto quedó registrado. Gracias por participar.', style: TextStyle(color: context.muted)),
              ]),
            ),
          ]),
        ),
      );
}

class _BallotCard extends StatefulWidget {
  const _BallotCard({required this.ballot, required this.onVoted});
  final _Ballot ballot;
  final VoidCallback onVoted;

  @override
  State<_BallotCard> createState() => _BallotCardState();
}

class _BallotCardState extends State<_BallotCard> {
  static const _blank = '__blank__';
  String? _choice;
  bool _busy = false;

  Future<void> _vote() async {
    final b = widget.ballot;
    final label = _choice == _blank
        ? 'voto en blanco'
        : (b.lists.firstWhere((l) => l['id'] == _choice)['name'] as String);
    final ok = await confirm(context, 'Vas a votar por: $label. Esta acción no se puede deshacer.', okLabel: 'Emitir voto');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.instance.client.rpc('cast_vote', params: {
        'p_election': b.election['id'],
        'p_list': _choice == _blank ? null : _choice,
      });
      if (mounted) snack(context, 'Voto registrado.');
    } catch (e) {
      if (mounted) snack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onVoted();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.ballot;
    final ends = DateTime.tryParse('${b.election['ends_at']}')?.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(b.election['title'] as String, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            'Tu voto es secreto y no se puede cambiar.${ends == null ? '' : ' Cierra el ${ends.day}/${ends.month} a las ${ends.hour.toString().padLeft(2, '0')}:${ends.minute.toString().padLeft(2, '0')}.'}',
            style: TextStyle(color: context.muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          RadioGroup<String>(
            groupValue: _choice,
            onChanged: (v) => setState(() => _choice = v),
            child: Column(children: [
              for (final l in b.lists)
                _Option(
                  value: l['id'] as String,
                  selected: _choice == l['id'],
                  number: '${l['number']}',
                  title: l['name'] as String? ?? '',
                  subtitle: 'Presidente/a: ${l['president_name'] ?? ''}',
                  slogan: l['slogan'] as String?,
                  photo: b.photos[l['president_photo']],
                ),
              _Option(value: _blank, selected: _choice == _blank, number: '—', title: 'Voto en blanco'),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _choice == null || _busy ? null : _vote, child: const Text('Emitir voto')),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.value,
    required this.selected,
    required this.number,
    required this.title,
    this.subtitle,
    this.slogan,
    this.photo,
  });
  final String value;
  final bool selected;
  final String number;
  final String title;
  final String? subtitle;
  final String? slogan;
  final String? photo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? Fwt.brand.withValues(alpha: 0.1) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? Fwt.brand : context.line, width: selected ? 2 : 1),
          ),
          child: RadioListTile<String>(
            value: value,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(children: [
              Avatar(name: number, url: photo, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Lista $number · $title'.replaceFirst('Lista — · ', ''), style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(color: context.muted, fontSize: 12)),
                  if (slogan != null && slogan!.isNotEmpty)
                    Text(slogan!, style: TextStyle(color: context.muted, fontSize: 12, fontStyle: FontStyle.italic)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _ApplicationsLink extends StatelessWidget {
  const _ApplicationsLink({required this.access});
  final Access access;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: Icon(Icons.groups_rounded, color: context.brandText),
          title: const Text('Postulaciones al consejo', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Envía tu lista y mira la respuesta'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ApplicationsScreen(access: access))),
        ),
      );
}
