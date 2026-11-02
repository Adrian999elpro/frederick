import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _specialties = [];
  String? _selectedSpecialtyId;
  List<Map<String, dynamic>> _specialtyRanking = [];

  List<Map<String, dynamic>> _subjects = [];
  String? _selectedSubjectId;
  List<Map<String, dynamic>> _subjectRanking = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    final client = Supabase.instance.client;
    try {
      final specs = await client.from('technical_specialties').select().order('name');
      final subs = await client
          .from('subjects')
          .select('id, name, code, technical_specialties(short_name)')
          .order('name');

      if (mounted) {
        setState(() {
          _specialties = List<Map<String, dynamic>>.from(specs);
          _subjects = List<Map<String, dynamic>>.from(subs);
          if (_specialties.isNotEmpty) {
            _selectedSpecialtyId = _specialties.first['id'].toString();
          }
          if (_subjects.isNotEmpty) {
            _selectedSubjectId = _subjects.first['id'].toString();
          }
        });

        await Future.wait([
          if (_selectedSpecialtyId != null) _loadSpecialtyRanking(),
          if (_selectedSubjectId != null) _loadSubjectRanking(),
        ]);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSpecialtyRanking() async {
    if (_selectedSpecialtyId == null) return;
    try {
      final res = await Supabase.instance.client.rpc(
        'get_specialty_ranking',
        params: {'p_specialty_id': _selectedSpecialtyId!},
      );
      if (mounted && res is List) {
        setState(() {
          _specialtyRanking = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSubjectRanking() async {
    if (_selectedSubjectId == null) return;
    try {
      final res = await Supabase.instance.client.rpc(
        'get_subject_ranking',
        params: {'p_subject_id': _selectedSubjectId!},
      );
      if (mounted && res is List) {
        setState(() {
          _subjectRanking = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏆 Cuadro de Honor y Rankings'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: FwtColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '🎓 Por Especialidad', icon: Icon(Icons.workspace_premium)),
            Tab(text: '📘 Por Materia Única', icon: Icon(Icons.menu_book)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: FwtColors.brand))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSpecialtyTab(),
                _buildSubjectTab(),
              ],
            ),
    );
  }

  Widget _buildSpecialtyTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surface,
          child: DropdownButtonFormField<String>(
            value: _selectedSpecialtyId,
            decoration: const InputDecoration(
              labelText: 'Seleccionar Especialidad Técnica',
              prefixIcon: Icon(Icons.school, color: FwtColors.brand),
            ),
            isExpanded: true,
            items: _specialties.map((sp) {
              return DropdownMenuItem<String>(
                value: sp['id'].toString(),
                child: Text(sp['name'], overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              setState(() => _selectedSpecialtyId = val);
              _loadSpecialtyRanking();
            },
          ),
        ),
        Expanded(
          child: _specialtyRanking.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No hay notas públicas registradas para esta especialidad todavía.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _specialtyRanking.length,
                  itemBuilder: (context, index) {
                    final st = _specialtyRanking[index];
                    final rank = index + 1;
                    Color badgeColor = Colors.grey.shade400;
                    String medal = '';
                    if (rank == 1) { badgeColor = const Color(0xFFF59E0B); medal = '🥇 '; }
                    else if (rank == 2) { badgeColor = const Color(0xFF94A3B8); medal = '🥈 '; }
                    else if (rank == 3) { badgeColor = const Color(0xFFB45309); medal = '🥉 '; }

                    final techAvg = st['technical_average'] != null ? Number(st['technical_average']).toStringAsFixed(2) : '--';
                    final genAvg = st['average_score'] != null ? Number(st['average_score']).toStringAsFixed(2) : '--';

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: badgeColor,
                          foregroundColor: Colors.white,
                          child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        title: Text(
                          '$medal${st['full_name']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${st['level_name']}'),
                            if (st['bio'] != null && st['bio'].toString().isNotEmpty)
                              Text('"${st['bio']}"', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              techAvg,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: FwtColors.brand),
                            ),
                            Text('Gral: $genAvg', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSubjectTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surface,
          child: DropdownButtonFormField<String>(
            value: _selectedSubjectId,
            decoration: const InputDecoration(
              labelText: 'Materia Específica',
              prefixIcon: Icon(Icons.book, color: FwtColors.brand),
            ),
            isExpanded: true,
            items: _subjects.map((sub) {
              final spName = sub['technical_specialties']?['short_name'] ?? 'Tronco Común';
              return DropdownMenuItem<String>(
                value: sub['id'].toString(),
                child: Text('[$spName] ${sub['name']}', overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) {
              setState(() => _selectedSubjectId = val);
              _loadSubjectRanking();
            },
          ),
        ),
        Expanded(
          child: _subjectRanking.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No hay calificaciones registradas o públicas en esta materia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _subjectRanking.length,
                  itemBuilder: (context, index) {
                    final st = _subjectRanking[index];
                    final rank = index + 1;
                    Color badgeColor = Colors.grey.shade400;
                    String medal = '';
                    if (rank == 1) { badgeColor = const Color(0xFFF59E0B); medal = '🥇 '; }
                    else if (rank == 2) { badgeColor = const Color(0xFF94A3B8); medal = '🥈 '; }
                    else if (rank == 3) { badgeColor = const Color(0xFFB45309); medal = '🥉 '; }

                    final scoreStr = st['score'] != null ? Number(st['score']).toStringAsFixed(2) : '--';

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: badgeColor,
                          foregroundColor: Colors.white,
                          child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        title: Text(
                          '$medal${st['full_name']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${st['level_name']} · ${st['specialty_name']}'),
                        trailing: Text(
                          scoreStr,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: FwtColors.brand),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  num Number(dynamic val) {
    if (val is num) return val;
    return num.tryParse(val.toString()) ?? 0;
  }
}
