import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../database/local_db.dart';
import '../../models/cancelled_item_model.dart';
import '../../models/order_model.dart';
import '../../models/table_model.dart';
import '../../providers/waiter_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_localizations.dart';

/// «ڕەتکراوەکان»: what the cashier threw out and has not put back yet.
///
/// [canMoveBack] is the whole difference between the two roles. A captain opens
/// the same list to see that a dish they rang in was rejected - that is the
/// point of showing it to them - but the button that puts food back on a table
/// belongs to the cashier alone, because moving an item back writes onto a live
/// table order and seats a guest. So on a captain's device the page is a window,
/// not a tool: the queue is visible and nothing on it can be pressed.
class CashierCancelledItemsPage extends ConsumerStatefulWidget {
  const CashierCancelledItemsPage({super.key, this.canMoveBack = true});

  final bool canMoveBack;

  @override
  ConsumerState<CashierCancelledItemsPage> createState() =>
      _CashierCancelledItemsPageState();
}

class _CashierCancelledItemsPageState
    extends ConsumerState<CashierCancelledItemsPage> {
  // The list lives in [pendingCancelledItemsProvider], which watches the order
  // revision notifier. That is the fix for a captain staring at this screen:
  // when the cashier moves a rejected dish back onto a table, the
  // markCancelledItemServed mutation lands on this device, the database bumps
  // the revision, and this page repaints on its own - the row disappears here
  // at the same second it disappears at the till, without closing and
  // reopening the page or pulling to refresh.
  Future<void> _reload() => ref.refresh(pendingCancelledItemsProvider.future);

  String _timeAmPm(String iso) {
    if (iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ap = dt.hour >= 12 ? context.tr('د.ن') : context.tr('پ.ن');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} ${two(h)}:${two(dt.minute)} $ap';
  }

  String _tableLabel(TableModel t) {
    final m = RegExp(r'^مێز\s+(\d+)$').firstMatch(t.name.trim());
    return m != null ? m.group(1)! : t.name;
  }

  /// «کاپتن ئاراس» / «کاشێر شیلان» rather than a bare name: staff of both
  /// roles ring dishes onto tables, and only the role says who actually did.
  /// Old records (no role resolved) fall back to the name alone.
  String _requesterLabel(CancelledItem item) {
    final role = switch (item.requestedByRole) {
      0 => context.tr('کاپتن'),
      1 => context.tr('کاشێر'),
      _ => '',
    };
    if (role.isEmpty) return item.requestedByName;
    return '$role ${item.requestedByName}';
  }

  Future<void> _moveToTable(CancelledItem item) async {
    if (!widget.canMoveBack) return;
    final db = ref.read(localDbProvider);
    final tables = await db.getAllTables();
    if (!mounted) return;
    final candidates = tables.toList();
    if (candidates.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('هیچ مێزێک نییە بۆ گواستنەوە')),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final selectedId = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.trp('گواستنەوەی {itemName} بۆ مێز', {
            'itemName': item.itemName,
          }),
        ),
        content: SizedBox(
          width: 360,
          height: 340,
          child: GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemCount: candidates.length,
            itemBuilder: (ctx, i) {
              final t = candidates[i];
              final occupied = t.status != TableStatus.empty;
              final bgColor = t.status == TableStatus.billRequested
                  ? AppColors.blue
                  : t.status == TableStatus.overdue
                  ? AppColors.danger
                  : occupied
                  ? AppColors.success
                  : AppColors.softText;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, t.id),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: bgColor.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.table_restaurant_rounded,
                        size: 24,
                        color: bgColor,
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          _tableLabel(t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: bgColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('ڕەتکردنەوە')),
          ),
        ],
      ),
    );
    if (selectedId == null || !mounted) return;
    var targetWasEmpty = false;
    for (final t in candidates) {
      if (t.id == selectedId) {
        targetWasEmpty = t.status == TableStatus.empty;
        break;
      }
    }
    final newId = ref.read(waiterProvider.notifier).generateId();
    final mover = ref.read(authProvider);
    await ref
        .read(waiterProvider.notifier)
        .addItemToOrder(
          selectedId,
          OrderItem(
            id: newId,
            name: item.itemName,
            price: item.itemPrice,
            quantity: item.quantity,
            category: item.category,
            // Moving a rejected dish is ringing it in again: it gets a fresh
            // ordering moment rather than inheriting the old one.
            createdAt: DateTime.now().toIso8601String(),
            waiterName: item.requestedByName.isNotEmpty
                ? item.requestedByName
                : item.cancelledByName,
            // Keep the dish attributed to whoever ordered it originally, not to
            // the cashier who rescued it from «ڕەتکراوەکان».
            waiterRole: item.requestedByRole,
          ),
        );
    if (targetWasEmpty) {
      // The mover seated this table, so they are its opener - a captain here
      // reads under their own name, not the previous sitting's.
      await db.occupyTable(
        selectedId,
        mover?.id.toString() ?? '',
        guestCount: 1,
      );
      await ref.read(waiterProvider.notifier).refresh();
    }
    await db.markCancelledItemServed(
      item.id,
      cancelledAt: item.cancelledAt,
      tableId: item.tableId,
      itemName: item.itemName,
      itemPrice: item.itemPrice,
      cancelledBy: item.cancelledBy,
      quantity: item.quantity,
    );
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('کرا: خواردنەکە گوێزرایەوە')),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(pendingCancelledItemsProvider);
    final items = async.asData?.value ?? const <CancelledItem>[];
    final totalValue = items.fold<double>(
      0,
      (s, i) => s + (i.itemPrice * i.quantity),
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.block_rounded,
                color: AppColors.danger,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr('ڕەتکراوەکان'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: async.isLoading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.block_rounded,
                    size: 72,
                    color: AppColors.softText.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      context.tr('هیچ خواردنێکی ڕەتکراو نییە'),
                      style: TextStyle(fontSize: 16, color: AppColors.softText),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_rounded,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.trp('{count} خواردنی ڕەتکراو', {
                              'count': items.length.toString(),
                            }),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                        Text(
                          '${context.tr('د.ع')} ${money(totalValue)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.canMoveBack) ...[
                    const SizedBox(height: 10),
                    _readOnlyNotice(),
                  ],
                  const SizedBox(height: 12),
                  ...items.map(_buildItemCard),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildItemCard(CancelledItem item) {
    final subtotal = item.itemPrice * item.quantity;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.darkText,
                  ),
                ),
              ),
              Text(
                '${item.quantity} × ${context.tr('د.ع')} ${money(item.itemPrice)}',
                style: const TextStyle(fontSize: 13, color: AppColors.softText),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _chip(
                Icons.table_restaurant_rounded,
                context.trp('مێزی {name}', {'name': item.tableName}),
                AppColors.primary,
              ),
              if (item.requestedAt.isNotEmpty)
                _chip(
                  Icons.add_circle_outline_rounded,
                  '${context.tr('کاتی داواکردن')}: ${_timeAmPm(item.requestedAt)}',
                  AppColors.primary,
                ),
              _chip(
                Icons.block_rounded,
                '${context.tr('کاتی ڕەتکردنەوە')}: ${_timeAmPm(item.cancelledAt)}',
                AppColors.danger,
              ),
              if (item.requestedByName.isNotEmpty)
                _chip(
                  Icons.person_rounded,
                  '${context.tr('داواکەر')}: ${_requesterLabel(item)}',
                  AppColors.primary,
                ),
              if (item.cancelledByName.isNotEmpty)
                _chip(
                  Icons.person_off_outlined,
                  '${context.tr('ڕەتکەر')}: ${item.cancelledByName}',
                  AppColors.danger,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                '${context.tr('کۆی گشتی')}: ${context.tr('د.ع')} ${money(subtotal)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.danger,
                ),
              ),
              // The cashier's tool. On a captain's device there is no button at
              // all - a hidden control they can never press, rather than one
              // they can press and be refused.
              if (widget.canMoveBack) ...[
                FilledButton.icon(
                  onPressed: () => _moveToTable(item),
                  icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                  label: Text(context.tr('گواستنەوە بۆ مێز')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// One quiet line telling a captain what this screen is and, more importantly,
  /// what it is not. Without it a captain can see a rejected dish on their table
  /// with no way to put it back and no explanation of who can.
  Widget _readOnlyNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softText.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_rounded,
            size: 16,
            color: AppColors.softText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('تەنها بینین؛ گواستنەوە بۆ مێز تەنها کاشێر دەکات'),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.softText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
