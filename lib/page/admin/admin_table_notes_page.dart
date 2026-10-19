import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../database/local_db.dart';
import '../../models/table_model.dart';
import '../../services/app_localizations.dart';
import '../../services/table_note_policy.dart';
import '../../widgets/admin_date_filter_bar.dart';

class AdminTableNotesPage extends ConsumerStatefulWidget {
  const AdminTableNotesPage({super.key});

  @override
  ConsumerState<AdminTableNotesPage> createState() =>
      _AdminTableNotesPageState();
}

class _AdminTableNotesPageState extends ConsumerState<AdminTableNotesPage> {
  AdminDatePeriod _period = AdminDatePeriod.all;
  AdminDatePeriodRange _range = resolveAdminDatePeriod(AdminDatePeriod.all);

  /// Sticky: the admin's chosen period survives reopening the page.
  static const String _prefKey = 'admin_table_notes_date_filter';
  late Future<List<TableModel>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _notesFuture = _loadNotes();
  }

  Future<List<TableModel>> _loadNotes() async {
    final db = ref.read(localDbProvider);
    final tables = await db.getAllTables();
    return tables.where((table) {
      if (table.note.trim().isEmpty) return false;
      // هەموو also keeps notes written before the edit time was recorded -
      // their date is unknown, so no narrower period can place them.
      if (_period == AdminDatePeriod.all) return true;
      final dt = DateTime.tryParse(table.noteUpdatedAt);
      if (dt == null) return false;
      return _range.contains(dt);
    }).toList();
  }

  Map<String, String> _decodeNote(String raw) => TableNote.decode(raw);

  /// Compact "2026/10/19 04:30 PM" stamp for a note's last edit.
  String _formatNoteTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '${two(dt.year)}/${two(dt.month)}/${two(dt.day)} '
        '${two(h)}:${two(dt.minute)} $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.tr('تێبینیی مێزەکان'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: AdminDateFilterBar(
              options: const [
                AdminDatePeriod.all,
                AdminDatePeriod.today,
                AdminDatePeriod.yesterday,
                AdminDatePeriod.dayBeforeYesterday,
                AdminDatePeriod.custom,
              ],
              initial: _period,
              persist: true,
              prefKey: _prefKey,
              onChanged: (period, range) {
                setState(() {
                  _period = period;
                  _range = range;
                  _notesFuture = _loadNotes();
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<TableModel>>(
              future: _notesFuture,
              builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return Center(child: Text(context.tr('هیچ زانیاریەک نییە')));
          }
          final notes = snapshot.data!;
          if (notes.isEmpty) {
            return Center(
              child: Text(
                context.tr('هیچ تێبینییەک نییە'),
                style: const TextStyle(color: AppColors.softText, fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final table = notes[index];
              final decoded = _decodeNote(table.note);
              final captainNote = decoded['captain'] ?? '';
              final adminNote = decoded['admin'] ?? '';

              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.table_restaurant_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  table.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkText,
                                  ),
                                ),
                                if (table.noteUpdatedAt.isNotEmpty)
                                  Text(
                                    _formatNoteTime(table.noteUpdatedAt),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.softText,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (captainNote.isNotEmpty) ...[
                        Text(
                          context.tr('تێبینیی کاپتن'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          captainNote,
                          style: const TextStyle(
                            height: 1.6,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (adminNote.isNotEmpty) ...[
                        Text(
                          context.tr('تێبینی بۆ ئادمێن'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          adminNote,
                          style: const TextStyle(
                            height: 1.6,
                            color: AppColors.darkText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
              },
            ),
          ),
        ],
      ),
    );
  }
}
