import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../core/table_status_visuals.dart';
import '../../database/local_db.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/waiter_provider.dart';
import '../../services/app_localizations.dart';

class TransferPage extends ConsumerStatefulWidget {
  final int? sourceTableId;
  const TransferPage({super.key, this.sourceTableId});

  @override
  ConsumerState<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends ConsumerState<TransferPage> {
  int? _selectedSourceId;
  int _filterIndex = 0;

  /// True while the move is being written. Without it, tapping the destination
  /// table twice ran `transferItems` twice and popped the route twice - the
  /// second pop closed the table page underneath this one.
  bool _transferring = false;

  /// A captain moves a table onto an empty one only: two occupied tables can
  /// never become one by their hand, because that merges two parties' food -
  /// a till decision. The page is shared with the cashier, who keeps the full
  /// merge.
  bool get _isCaptain => ref.read(authProvider)?.role == UserRole.waiter;

  Color _statusColor(TableStatus status) => TableStatusVisuals.color(status);

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(waiterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.tr('گواستنەوەی مێز'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (tables) {
          final sourceTable = widget.sourceTableId != null
              ? tables.where((t) => t.id == widget.sourceTableId).firstOrNull
              : (_selectedSourceId != null
                    ? tables.where((t) => t.id == _selectedSourceId).firstOrNull
                    : null);
          final emptyTables = tables
              .where(
                (t) =>
                    t.status == TableStatus.empty &&
                    t.id != widget.sourceTableId &&
                    t.id != _selectedSourceId,
              )
              .toList();
          final occupiedTables = tables
              .where(
                (t) =>
                    t.status != TableStatus.empty &&
                    t.id != widget.sourceTableId &&
                    t.id != _selectedSourceId,
              )
              .toList();

          return Column(
            children: [
              if (sourceTable != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  color: AppColors.primary.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.source_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          sourceTable.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (widget.sourceTableId == null) ...[
                        // 40px tall (was 30): clears the minimum tap-target
                        // floor without changing the button's slim look.
                        SizedBox(
                          height: 40,
                          child: FilledButton.tonalIcon(
                            onPressed: () =>
                                setState(() => _selectedSourceId = null),
                            icon: const Icon(Icons.close_rounded, size: 14),
                            label: Text(
                              context.tr('لابردن'),
                              style: const TextStyle(fontSize: 11),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (widget.sourceTableId == null && _selectedSourceId == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.touch_app_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(
                              'لەسەر مێزێکی گیراو کلیک بکە بۆ سەرچاوە، دواتر مێزی ئامانج هەڵبژێرە',
                            ),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isCaptain &&
                  (widget.sourceTableId != null || _selectedSourceId != null))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.softText.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chair_outlined,
                          size: 18,
                          color: AppColors.softText,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr('تەنها دەتوانیت بۆ مێزی بەتاڵ بگوازیتەوە'),
                            style: const TextStyle(
                              color: AppColors.softText,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingMedium,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _filterButton(
                      0,
                      context.tr('هەموو'),
                      Icons.grid_view_rounded,
                    ),
                    const SizedBox(width: 8),
                    _filterButton(
                      1,
                      context.tr('مێزی بەتاڵ'),
                      Icons.chair_outlined,
                    ),
                    const SizedBox(width: 8),
                    _filterButton(
                      2,
                      context.tr('مێزەگیراوەکان'),
                      Icons.people_alt_rounded,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: 4,
                  ),
                  children: [
                    if (_filterIndex != 2) ...[
                      _sectionTitle(
                        emptyTables.length,
                        context.tr('مێزی بەتاڵ'),
                        Icons.chair_outlined,
                        const Color(0xFF2C3539),
                      ),
                      const SizedBox(height: 8),
                      if (emptyTables.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              context.tr('هیچ مێزێکی بەتاڵ نییە'),
                              style: const TextStyle(color: AppColors.softText),
                            ),
                          ),
                        )
                      else
                        _buildGrid(emptyTables, _selectedSourceId),
                    ],
                    if (_filterIndex == 0) const SizedBox(height: 20),
                    if (_filterIndex != 1) ...[
                      _sectionTitle(
                        occupiedTables.length,
                        context.tr('مێزەگیراوەکان'),
                        Icons.people_alt_rounded,
                        AppColors.success,
                      ),
                      const SizedBox(height: 8),
                      if (occupiedTables.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              context.tr('هیچ مێزێکی گیراو نییە'),
                              style: const TextStyle(color: AppColors.softText),
                            ),
                          ),
                        )
                      else
                        _buildGrid(occupiedTables, _selectedSourceId),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterButton(int index, String label, IconData icon) {
    final isSelected = _filterIndex == index;
    return Expanded(
      child: Material(
        color: isSelected ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _filterIndex = index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.borderSide,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : AppColors.softText,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(int count, String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<TableModel> tables, int? selectedSourceId) {
    return ResponsiveGridView(
      shrinkWrap: true,
      // The 6-column desktop row only fits a true laptop; iPads (740-1099)
      // keep the roomier 4/tile layout so the fixed table tiles don't clip.
      desktopColumns: Responsive.safeGridColumns(
        context,
        desktop: 6,
        tablet: 4,
        mobile: 3,
      ),
      tabletColumns: 4,
      mobileColumns: 3,
      spacing: 10,
      runSpacing: 10,
      childAspectRatio: 1.1,
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final table = tables[index];
        final isSel =
            selectedSourceId == table.id || _selectedSourceId == table.id;
        final color = _statusColor(table.status);
        final isEmpty = table.status == TableStatus.empty;
        // A target has been picked, so the next tap chooses the destination.
        // A captain's destination may only be an empty table: occupied tiles
        // become inert, so two tables can never merge by their hand.
        final destinationMode =
            widget.sourceTableId != null || _selectedSourceId != null;
        final blockedMerge = _isCaptain && destinationMode && !isEmpty;
        final isClickable =
            blockedMerge ? false : (!isEmpty || destinationMode);
        Widget tile = Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isSel
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isEmpty ? 0.04 : 0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isEmpty ? 0.06 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.table_restaurant_rounded,
                    size: 18,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  table.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.darkText,
                  ),
                ),
                if (!isEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${context.tr('د.ع')} ${money(table.totalAmount)}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (isEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    context.tr('بەتاڵ'),
                    style: const TextStyle(
                      color: AppColors.softText,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
        if (blockedMerge) {
          tile = Stack(
            children: [
              tile,
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.softText.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    size: 14,
                    color: AppColors.softText,
                  ),
                ),
              ),
            ],
          );
          tile = Opacity(opacity: 0.55, child: tile);
        }
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isClickable ? () => _onTableTap(table) : null,
          child: tile,
        );
      },
    );
  }

  void _onTableTap(TableModel target) {
    if (widget.sourceTableId != null) {
      if (target.id == widget.sourceTableId) return;
      if (_captainBlockedTarget(target)) return;
      _executeTransfer(widget.sourceTableId!, target.id, target.name);
      return;
    }

    if (_selectedSourceId == null) {
      if (target.status == TableStatus.empty) return;
      setState(() => _selectedSourceId = target.id);
      return;
    }

    if (target.id == _selectedSourceId) {
      setState(() => _selectedSourceId = null);
      return;
    }

    if (_captainBlockedTarget(target)) return;
    _executeTransfer(_selectedSourceId!, target.id, target.name);
  }

  /// A captain may end a transfer only on an empty table. Telling them beats
  /// guessing: the tile is already inert, but every path in, not just the tap
  /// that draws the greyed tile, has to say the same thing.
  bool _captainBlockedTarget(TableModel target) {
    if (!_isCaptain || target.status == TableStatus.empty) return false;
    _showCaptainMergeBlocked();
    return true;
  }

  void _showCaptainMergeBlocked() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.tr('ناتوانیت بۆ مێزێکی گیراو بگوازیتەوە؛ تەنها کاشێر دەتوانێت'),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
  }

  Future<void> _executeTransfer(
    int sourceId,
    int targetId,
    String targetName,
  ) async {
    if (_transferring) return;
    final db = ref.read(localDbProvider);
    final target = _isCaptain
        ? (ref.read(waiterProvider).asData?.value ?? const <TableModel>[])
            .where((t) => t.id == targetId)
            .firstOrNull
        : null;
    if (target != null && target.status != TableStatus.empty) {
      _showCaptainMergeBlocked();
      return;
    }
    _transferring = true;
    try {
      await db.transferItems(sourceId, targetId);
      ref.invalidate(tableOrdersProvider(sourceId));
      ref.invalidate(tableOrdersProvider(targetId));
      await ref.read(waiterProvider.notifier).refreshSilent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.trp('گوازرایەوە بۆ {name}', {'name': targetName}),
          ),
          backgroundColor: AppColors.success,
        ),
      );
      if (widget.sourceTableId != null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _selectedSourceId = null);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('گوازدنەوە سەرکەوتوو نەبوو')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      _transferring = false;
    }
  }
}
