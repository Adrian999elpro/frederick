import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/nfc_service.dart';
import '../theme.dart';
import '../widgets/admin_kiosk_guard.dart';

class NfcVoteScreen extends StatefulWidget {
  final VoidCallback? onExitRequested;
  const NfcVoteScreen({super.key, this.onExitRequested});

  @override
  State<NfcVoteScreen> createState() => _NfcVoteScreenState();
}

enum _VoteStep { waitForCard, chooseList, completed }

class _NfcVoteScreenState extends State<NfcVoteScreen> {
  _VoteStep _step = _VoteStep.waitForCard;
  Map<String, dynamic>? _selectedElection;
  List<Map<String, dynamic>> _candidateLists = [];
  String? _scannedCardUid;
  String? _identifiedStudentName;
  String? _selectedListId;
  String _statusMessage = 'Acerque su tarjeta de estudiante al sensor NFC para votar...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadOpenElection();
  }

  Future<void> _loadOpenElection() async {
    setState(() => _isLoading = true);
    try {
      final elections = await Supabase.instance.client
          .from('elections')
          .select()
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(1);

      if (elections.isNotEmpty) {
        _selectedElection = elections.first;
        final lists = await Supabase.instance.client
            .from('election_lists')
            .select()
            .eq('election_id', _selectedElection!['id'])
            .order('number');

        _candidateLists = List<Map<String, dynamic>>.from(lists);
        _startListeningForVoter();
      } else {
        setState(() => _statusMessage = 'No hay ninguna elección abierta en este momento.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error al cargar elección: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startListeningForVoter() {
    NfcCardService.instance.startListening(
      onCardScanned: _handleVoterCard,
      onError: (err) {
        if (mounted) setState(() => _statusMessage = 'Error NFC: $err');
      },
    );
  }

  Future<void> _handleVoterCard(String cardUid) async {
    if (_step != _VoteStep.waitForCard || _selectedElection == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Identificando estudiante...';
    });

    try {
      // 1. Obtener estudiante por tarjeta
      final cards = await Supabase.instance.client
          .from('nfc_cards')
          .select('profile_id, profiles(full_name, email, status)')
          .eq('card_uid', cardUid)
          .eq('active', true)
          .maybeSingle();

      if (cards == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = '❌ Tarjeta NFC no registrada en la institución.';
        });
        return;
      }

      final profileId = cards['profile_id'];
      final studentName = cards['profiles']?['full_name'] ?? 'Estudiante';

      // 2. Verificar si ya votó en esta elección
      final alreadyVoted = await Supabase.instance.client
          .from('vote_receipts')
          .select('voted_at')
          .eq('election_id', _selectedElection!['id'])
          .eq('voter_id', profileId)
          .maybeSingle();

      if (alreadyVoted != null) {
        setState(() {
          _isLoading = false;
          _statusMessage = '⚠️ Ya has votado: $studentName ya emitió su voto en esta elección. No se permiten votos repetidos.';
        });
        return;
      }

      // Detener sensor mientras emite el voto en pantalla
      await NfcCardService.instance.stopListening();

      setState(() {
        _isLoading = false;
        _scannedCardUid = cardUid;
        _identifiedStudentName = studentName;
        _step = _VoteStep.chooseList;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error al validar tarjeta: $e';
      });
    }
  }

  Future<void> _submitVote() async {
    if (_scannedCardUid == null || _selectedElection == null) return;

    setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client.rpc(
        'cast_vote_nfc',
        params: {
          'p_election': _selectedElection!['id'],
          'p_list': _selectedListId, // null = voto en blanco
          'p_card_uid': _scannedCardUid!,
        },
      );

      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] == true) {
        setState(() => _step = _VoteStep.completed);
        await Future.delayed(const Duration(seconds: 4));
        _resetForNextVoter();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(map['message'] ?? 'Error al registrar voto')),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  void _resetForNextVoter() {
    if (!mounted) return;
    setState(() {
      _step = _VoteStep.waitForCard;
      _scannedCardUid = null;
      _identifiedStudentName = null;
      _selectedListId = null;
      _isLoading = false;
      _statusMessage = 'Acerque su tarjeta de estudiante al sensor NFC para votar...';
    });
    _startListeningForVoter();
  }

  @override
  void dispose() {
    NfcCardService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedElection?['title'] ?? 'Votaciones Estudiantiles FWT'),
        leading: IconButton(
          icon: const Icon(Icons.lock_outline),
          onPressed: () async {
            final ok = await AdminKioskGuard.requestAdminAuth(context, reason: 'salir de la cabina de votación');
            if (ok && mounted) {
              widget.onExitRequested?.call() ?? Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: FwtColors.brand))
          : _buildCurrentStep(),
    );
  }

  Widget _buildCurrentStep() {
    if (_selectedElection == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    switch (_step) {
      case _VoteStep.waitForCard:
        return _buildWaitForCard();
      case _VoteStep.chooseList:
        return _buildBallotSelection();
      case _VoteStep.completed:
        return _buildCompletedSuccess();
    }
  }

  Widget _buildWaitForCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: FwtColors.brand.withOpacity(0.2), blurRadius: 20, spreadRadius: 6),
                ],
              ),
              child: const Icon(Icons.nfc, size: 80, color: FwtColors.brand),
            ),
            const SizedBox(height: 28),
            const Text(
              '🗳️ Cabina Electoral Escolar FWT',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: FwtColors.brand),
            ),
            const SizedBox(height: 12),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'El sensor identificará al estudiante mediante su carnet NFC.\nCada estudiante solo puede emitir su voto una única vez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBallotSelection() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: FwtColors.brand,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            children: [
              Text(
                'Estudiante: $_identifiedStudentName',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const Text(
                'Tu voto es secreto y personal. Selecciona tu lista preferida:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ..._candidateLists.map((list) {
                final isSelected = _selectedListId == list['id'];
                return Card(
                  elevation: isSelected ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isSelected ? FwtColors.accent : Colors.grey.shade300,
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: CircleAvatar(
                      radius: 26,
                      backgroundColor: FwtColors.brand,
                      child: Text(
                        '#${list['number']}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    title: Text(
                      list['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Presidente/a: ${list['president_name'] ?? '---'}'),
                        if (list['slogan'] != null && list['slogan'].toString().isNotEmpty)
                          Text('"${list['slogan']}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                      ],
                    ),
                    trailing: Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? FwtColors.accent : Colors.grey,
                      size: 28,
                    ),
                    onTap: () => setState(() => _selectedListId = list['id']),
                  ),
                );
              }),
              const SizedBox(height: 8),
              // Voto en blanco
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _selectedListId == '__BLANK__' ? FwtColors.accent : Colors.grey.shade300,
                    width: _selectedListId == '__BLANK__' ? 2.5 : 1,
                  ),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.block, color: Colors.white),
                  ),
                  title: const Text('Voto en Blanco', style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Icon(
                    _selectedListId == '__BLANK__' ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: _selectedListId == '__BLANK__' ? FwtColors.accent : Colors.grey,
                  ),
                  onTap: () => setState(() => _selectedListId = '__BLANK__'),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetForNextVoter,
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _selectedListId == null ? null : _submitVote,
                  child: const Text('Emitir Voto'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, size: 90, color: Colors.green),
            SizedBox(height: 24),
            Text(
              '¡Voto Registrado con Éxito!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.green),
            ),
            SizedBox(height: 12),
            Text(
              'Gracias por participar en la fiesta democrática de la Unidad Educativa Frederick Winslow Taylor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
            ),
            SizedBox(height: 20),
            Text(
              'Preparando el sensor para el siguiente votante...',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
