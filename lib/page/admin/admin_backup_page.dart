import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';

class AdminBackupPage extends ConsumerStatefulWidget {
  const AdminBackupPage({super.key});

  @override
  ConsumerState<AdminBackupPage> createState() => _AdminBackupPageState();
}

class _AdminBackupPageState extends ConsumerState<AdminBackupPage> {
  List<Map<String, dynamic>> _backups = [];
  bool _loading = true;
  bool _exporting = false;
  bool _restoring = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _loading = true);
    _backups = await ref.read(localDbProvider).listBackups();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _exportBackup() async {
    setState(() => _exporting = true);
    final path = await ref.read(localDbProvider).exportBackup();
    await _loadBackups();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.trp('بەکاپ کرایە: {name}', {'name': path.split('\\').last.split('/').last})),
          backgroundColor: AppColors.success),
    );
    setState(() => _exporting = false);
  }

  Future<void> _restoreBackup(Map<String, dynamic> backup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('گەڕاندنەوەی بەکاپ')),
        content: Text(context.trp('دڵنیایت دەتەوێت بەکاپی {name} بگەڕێنیتەوە؟ هەموو داتاکانی ئێستا دەسڕێتەوە.',
            {'name': _backupDisplayName(backup['name'] as String)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('ڕەتکردنەوە'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('گەڕاندنەوە'))),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _restoring = true);
      final db = ref.read(localDbProvider);
      await db.restoreBackup(backup['path'] as String);
      await _loadBackups();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('بەکاپ بە سەرکەوتووی گەڕایەوە')),
            backgroundColor: AppColors.success),
      );
      setState(() => _restoring = false);
    }
  }

  Future<void> _resetAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('سڕینەوەی هەموو داتاکان')),
        content: Text(context.tr('دڵنیایت دەتەوێت هەموو داتاکان بسڕیتەوە؟ هەموو حیسابەکان، قەرزەکان، ئۆردەرەکان و مێزەکان دەسڕدرێنەوە و بۆ دۆخە سەرەتاییەکە دەگەڕێتەوە. ئەم کارە ناتوانرێت بگەڕێتەوە.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('ڕەتکردنەوە'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(context.tr('سڕینەوە')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _resetting = true);
    await ref.read(localDbProvider).resetAllData();
    await _loadBackups();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('هەموو داتاکان سڕانەوە و بۆ دۆخە سەرەتاییەکە گەڕایەوە')),
          backgroundColor: AppColors.success),
    );
    setState(() => _resetting = false);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  /// Strips the new (`ramyar_pos_backup_`) or legacy (`biablo_/biablu_backup_`)
  /// prefix so backup names read as plain timestamps in the UI.
  String _backupDisplayName(String name) {
    return name
        .replaceAll('ramyar_pos_backup_', '')
        .replaceAll('biablo_backup_', '')
        .replaceAll('biablu_backup_', '')
        .replaceAll('.db', '');
  }

  Widget _buildBackupTile(Map<String, dynamic> backup) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _restoring ? null : () => _restoreBackup(backup),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storage_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_backupDisplayName(backup['name'] as String),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkText)),
                    const SizedBox(height: 2),
                    Text('${_formatTime(backup['modified'] as String)} • ${_formatSize(backup['size'] as int)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.softText, fontSize: 12)),
                  ],
                ),
              ),
              if (_restoring)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(context.tr('گەڕاندنەوە'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(context.tr('بەکاپ و گەڕاندنەوە'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: _exporting
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    icon: const Icon(Icons.backup_rounded, color: AppColors.primary),
                    tooltip: context.tr('دروستکردنی بەکاپ'),
                    onPressed: _exportBackup,
                  ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          final header = Container(
            margin: const EdgeInsets.all(AppConstants.paddingMedium),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.backup_rounded, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('بەکاپ و گەڕاندنەوەی داتاکان'),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkText)),
                      const SizedBox(height: 4),
                      Text(context.tr('بەکاپ لە فایلێکی .db هەڵدەگرێت و دەتوانیت بیگەڕێنیتەوە'),
                          maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.softText, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          );
          final footer = Container(
            margin: const EdgeInsets.fromLTRB(AppConstants.paddingMedium, 0, AppConstants.paddingMedium, AppConstants.paddingMedium),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('سڕینەوەی هەموو داتاکان'),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.darkText)),
                          const SizedBox(height: 2),
                          Text(context.tr('هەموو حیساب و ئۆردەر و قەرزەکان دەسڕێتەوە'),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.softText, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _resetting
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger))
                      : FilledButton.icon(
                          onPressed: _resetAllData,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(context.tr('سڕینەوە')),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                        ),
                ),
              ],
            ),
          );
          final empty = Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.backup_outlined, size: 64, color: AppColors.softText.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(context.tr('هیچ بەکاپێک نییە'), style: TextStyle(color: AppColors.softText)),
                  const SizedBox(height: 8),
                  Text(context.tr('کرتە لە دوگمەی بەکاپ بکە بۆ دروستکردنی یەکەم بەکاپ'),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.softText, fontSize: 12)),
                ],
              ),
            ),
          );
          final list = _loading
              ? const Center(child: CircularProgressIndicator())
              : _backups.isEmpty
                  ? empty
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium),
                      itemCount: _backups.length,
                      itemBuilder: (context, index) => _buildBackupTile(_backups[index]),
                    );
          if (!isNarrow) {
            return Column(
              children: [
                header,
                Expanded(child: list),
                footer,
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: [
                header,
                if (_loading)
                  const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                else if (_backups.isEmpty)
                  const SizedBox(height: 120, child: SizedBox.shrink())
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium),
                    child: Column(
                      children: [for (final b in _backups) _buildBackupTile(b)],
                    ),
                  ),
                const SizedBox(height: 8),
                footer,
              ],
            ),
          );
        },
      ),
    );
  }
}
