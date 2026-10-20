import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../core/table_status_visuals.dart';
import '../../database/local_db.dart';
import '../../models/table_model.dart';
import '../../providers/waiter_provider.dart';
import '../../services/app_localizations.dart';

class MergePage extends ConsumerStatefulWidget {
  final int? sourceTableId;
  const MergePage({super.key, this.sourceTableId});

  @override
  ConsumerState<MergePage> createState() => _MergePageState();
}

class _MergePageState extends ConsumerState<MergePage> {
  int? _selectedSourceId;
  int? _selectedTargetId;
  int _step = 1;

  /// True while the merge write is in flight. The confirm button stayed live
  /// during the await, so a second tap re-ran the transfer against the already
  /// emptied source and reported success a second time.
  bool _merging = false;

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
          context.tr('تێکەڵکردنی مێز'),
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
          final sourceId = widget.sourceTableId ?? _selectedSourceId;
          final sourceTable = sourceId != null
              ? tables.where((t) => t.id == sourceId).firstOrNull
              : null;

          return Column(
            children: [
              _buildStepIndicator(),
              if (_step == 1)
                _buildSourceStep(tables, sourceTable)
              else
                _buildTargetStep(tables, sourceTable),
              if (sourceTable != null) _buildSelectedSourceTile(sourceTable),
              const SizedBox(height: 4),
              if (_step == 2 && _selectedTargetId != null)
                _buildConfirmSection(tables, sourceTable),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _stepDot(1, context.tr('سەرچاوە'), Icons.source_rounded),
          Expanded(
            child: Container(
              height: 2,
              color: _step >= 2 ? AppColors.primary : AppColors.borderSide,
            ),
          ),
          _stepDot(2, context.tr('ئامانج'), Icons.arrow_forward_rounded),
          Expanded(
            child: Container(
              height: 2,
              color: _step >= 3 ? AppColors.primary : AppColors.borderSide,
            ),
          ),
          _stepDot(3, context.tr('پشتڕاستکردنەوە'), Icons.check_circle_rounded),
        ],
      ),
    );
  }

  Widget _stepDot(int step, String label, IconData icon) {
    final isDone = _step >= step;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDone ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDone ? AppColors.primary : AppColors.borderSide,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isDone ? Colors.white : AppColors.softText,
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 76),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDone ? AppColors.primary : AppColors.softText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceStep(List<TableModel> tables, TableModel? sourceTable) {
    final occupiedTables = tables
        .where((t) => t.status != TableStatus.empty)
        .toList();

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
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
                      context.tr('مێزێکی گیراو هەڵبژێرە بۆ تێکەڵکردن'),
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
            const SizedBox(height: 16),
            Expanded(
              child: occupiedTables.isEmpty
                  ? Center(
                      child: Text(
                        context.tr('هیچ مێزێکی گیراو نییە'),
                        style: TextStyle(color: AppColors.softText),
                      ),
                    )
                  : _buildGrid(occupiedTables, sourceTable, isSource: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetStep(List<TableModel> tables, TableModel? sourceTable) {
    if (sourceTable == null) return const SizedBox.shrink();
    final targetTables = tables.where((t) => t.id != sourceTable.id).toList();

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.touch_app_rounded,
                    size: 18,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr(
                        'مێزی ئامانج هەڵبژێرە (بڕگەکانی سەرچاوە دەگوازرێنە ئەم مێزە)',
                      ),
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _buildGrid(targetTables, sourceTable, isSource: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedSourceTile(TableModel table) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Row(
        children: [
          const Icon(Icons.source_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${context.tr('سەرچاوە')}: ${table.name} • ${context.tr('د.ع')} ${money(table.totalAmount)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
          ),
          const Spacer(),
          if (widget.sourceTableId == null)
            SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _selectedSourceId = null;
                  _step = 1;
                  _selectedTargetId = null;
                }),
                icon: const Icon(Icons.close_rounded, size: 14),
                label: Text(
                  context.tr('گۆڕین'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfirmSection(
    List<TableModel> tables,
    TableModel? sourceTable,
  ) {
    final targetTable = tables
        .where((t) => t.id == _selectedTargetId)
        .firstOrNull;
    if (sourceTable == null || targetTable == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.call_merge_rounded,
                color: AppColors.success,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('تێکەڵکردن'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.darkText,
                ),
              ),
              const Spacer(),
              Text(
                '${context.tr('د.ع')} ${money((sourceTable.totalAmount + targetTable.totalAmount))}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sourceTable.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      Text(
                        '${context.tr('د.ع')} ${money(sourceTable.totalAmount)}',
                        style: TextStyle(
                          color: AppColors.softText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        targetTable.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      Text(
                        '${context.tr('د.ع')} ${money(targetTable.totalAmount)}',
                        style: TextStyle(
                          color: AppColors.softText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _merging ? null : () => _executeMerge(sourceTable, targetTable),
              icon: const Icon(Icons.call_merge_rounded, size: 18),
              label: Text(context.tr('تێکەڵکردن')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    List<TableModel> tables,
    TableModel? sourceTable, {
    required bool isSource,
  }) {
    final selectedId = isSource ? _selectedSourceId : _selectedTargetId;
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Responsive.gridColumns(context, mobile: 3, tablet: 5),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: Responsive.isPhone(context) ? 1.2 : 1.1,
      ),
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final table = tables[index];
        final color = _statusColor(table.status);
        final isEmpty = table.status == TableStatus.empty;
        final isSel = selectedId == table.id;
        final canSelect = isSource ? !isEmpty : true;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canSelect ? () => _onTableTap(table, isSource) : null,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isSel
                  ? Border.all(
                      color: isSource ? AppColors.primary : AppColors.success,
                      width: 2,
                    )
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
                      fontSize: 12,
                      color: AppColors.darkText,
                    ),
                  ),
                  if (!isEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${context.tr('د.ع')} ${money(table.totalAmount)}',
                      style: TextStyle(
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
                      style: TextStyle(color: AppColors.softText, fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onTableTap(TableModel table, bool isSource) {
    if (isSource) {
      if (table.status == TableStatus.empty) return;
      setState(() {
        _selectedSourceId = table.id;
        _step = 2;
        _selectedTargetId = null;
      });
    } else {
      if (table.id == _selectedSourceId) return;
      setState(() => _selectedTargetId = table.id);
    }
  }

  Future<void> _executeMerge(TableModel source, TableModel target) async {
    if (_merging) return;
    _merging = true;
    try {
      final db = ref.read(localDbProvider);
      await db.transferItems(source.id, target.id);
      await ref.read(waiterProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.trp('مێزی {source} تێکەڵکرا بە {target}', {
              'source': source.name,
              'target': target.name,
            }),
          ),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() {
        _selectedSourceId = null;
        _selectedTargetId = null;
        _step = 1;
      });
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
      _merging = false;
    }
  }
}
