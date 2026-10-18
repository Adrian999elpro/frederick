import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = true;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      var query = Supabase.instance.client
          .from('announcements')
          .select('*, profiles(full_name, email), school_levels(name)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);

      if (_selectedCategory != null) {
        query = query.eq('category', _selectedCategory!);
      }

      final data = await query;
      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novedades y Anuncios FWT'),
      ),
      body: Column(
        children: [
          // Filtros por Categoría
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('Todos', null),
                const SizedBox(width: 8),
                _buildFilterChip('🚨 Urgentes', 'urgente'),
                const SizedBox(width: 8),
                _buildFilterChip('📘 Académicos', 'academico'),
                const SizedBox(width: 8),
                _buildFilterChip('🎉 Eventos', 'evento'),
                const SizedBox(width: 8),
                _buildFilterChip('📌 General', 'general'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: FwtColors.brand))
                : _announcements.isEmpty
                    ? Center(
                        child: Text(
                          'No hay comunicados en esta categoría.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAnnouncements,
                        color: FwtColors.brand,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _announcements.length,
                          itemBuilder: (context, index) {
                            final item = _announcements[index];
                            final isPinned = item['is_pinned'] == true;
                            final category = item['category'] ?? 'general';
                            final author = item['profiles']?['full_name'] ?? 'Institucional';
                            final role = item['author_role_title'] ?? 'Docente';
                            final target = item['school_levels']?['name'] ?? 'Todo el Plantel';

                            Color borderLeftColor = FwtColors.brand;
                            if (category == 'urgente') borderLeftColor = Colors.red;
                            if (category == 'academico') borderLeftColor = Colors.blue;
                            if (category == 'evento') borderLeftColor = Colors.amber.shade800;

                            return Card(
                              elevation: isPinned ? 3 : 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: borderLeftColor, width: isPinned ? 2 : 1),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (isPinned)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              '📌 FIJADO',
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        Chip(
                                          label: Text(
                                            category.toUpperCase(),
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                          backgroundColor: borderLeftColor.withOpacity(0.1),
                                          labelStyle: TextStyle(color: borderLeftColor),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item['title'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item['content'] ?? '',
                                      style: const TextStyle(fontSize: 14, height: 1.4),
                                    ),
                                    const Divider(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Para: $target', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                        Text(
                                          'Firma: $author ($role)',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? category) {
    final isSelected = _selectedCategory == category;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: FwtColors.brand,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      onSelected: (_) {
        setState(() => _selectedCategory = category);
        _loadAnnouncements();
      },
    );
  }
}
