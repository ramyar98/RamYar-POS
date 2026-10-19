import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/fmt.dart';
import '../../database/local_db.dart';
import '../../models/order_model.dart';
import '../../models/printer_model.dart';
import '../../models/settlement_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/print_router.dart';
import '../../widgets/print_preview_dialog.dart';
import '../admin/payment_method_style.dart';

/// «داواکاری پێشوو»: what the tables of the cashier's own shift have already
/// had on them.
///
/// The cashier opens this when a guest walks back in and asks "what did we
/// order last time?" - the question the flat receipt list could not answer,
/// because it listed settlements, not tables, and carried no dishes at all.
/// So the top level is the tables that were settled in the running shift, and
/// tapping one opens its visits.
///
/// It is deliberately scoped to the open shift. A shift is the cashier's own
/// book: once it closes, this list is empty and the record lives on the admin's
/// shift report instead. That keeps the list to the room this cashier actually
/// served rather than every table the shop has ever closed.
class CashierPreviousOrdersPage extends ConsumerStatefulWidget {
  const CashierPreviousOrdersPage({super.key, required this.shiftId});

  /// The running shift's row id. A sentinel that cannot exist (a closed shift,
  /// or no shift at all) yields an empty list rather than an error.
  final int shiftId;

  @override
  ConsumerState<CashierPreviousOrdersPage> createState() =>
      _CashierPreviousOrdersPageState();
}

class _CashierPreviousOrdersPageState
    extends ConsumerState<CashierPreviousOrdersPage> {
  late Future<List<_TableSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_TableSummary>> _load() async {
    final orders = await ref
        .read(localDbProvider)
        .getSettledOrdersByShiftId(widget.shiftId);
    // `getSettledOrdersByShiftId` comes back newest first, so the first time a
    // table is seen is already its latest visit - the summary only has to add
    // the rest up.
    final byTable = <int, _TableSummary>{};
    for (final order in orders) {
      final existing = byTable[order.tableId];
      if (existing == null) {
        byTable[order.tableId] = _TableSummary(
          tableId: order.tableId,
          tableName: order.tableName,
          visits: 1,
          lastSettledAt: order.settledAt,
          total: order.totalAmount,
        );
      } else {
        byTable[order.tableId] = existing.copyWith(
          visits: existing.visits + 1,
          total: existing.total + order.totalAmount,
          lastSettledAt:
              order.settledAt.compareTo(existing.lastSettledAt) > 0
                  ? order.settledAt
                  : existing.lastSettledAt,
        );
      }
    }
    // Most recently served table first: a cashier reaching for this mid-service
    // is almost always asking about the table that just left.
    final summaries = byTable.values.toList()
      ..sort((a, b) => b.lastSettledAt.compareTo(a.lastSettledAt));
    return summaries;
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  void _openTable(_TableSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CashierTableHistoryPage(
          tableId: summary.tableId,
          tableName: summary.tableName,
          shiftId: widget.shiftId,
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
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.blue,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr('داواکاری پێشوو'),
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
      body: FutureBuilder<List<_TableSummary>>(
        future: _future,
        builder: (context, snapshot) {
          final summaries = snapshot.data ?? const <_TableSummary>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              summaries.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (summaries.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 72,
                    color: AppColors.softText.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      context.tr('هیچ داواکارییەکی پێشوو نییە لەم شەفتەدا'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.softText,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              children: [
                _summaryHeader(summaries),
                const SizedBox(height: 12),
                ...summaries.map(_tableRow),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryHeader(List<_TableSummary> summaries) {
    final total = summaries.fold<double>(0, (sum, s) => sum + s.total);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.table_bar_rounded, color: AppColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.trp('{count} مێز', {
                'count': summaries.length.toString(),
              }),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.darkText,
              ),
            ),
          ),
          Text(
            '${context.tr('د.ع')} ${money(total)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableRow(_TableSummary summary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSide),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openTable(summary),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.table_restaurant_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.tableName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        _chip(
                          Icons.repeat_rounded,
                          context.trp('{count} سەردان', {
                            'count': summary.visits.toString(),
                          }),
                          AppColors.primary,
                        ),
                        _chip(
                          Icons.schedule_rounded,
                          formatShiftTime(context, summary.lastSettledAt),
                          AppColors.softText,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${context.tr('د.ع')} ${money(summary.total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.softText,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }
}

/// One table's visits in the running shift: each settlement with the dishes it
/// closed, newest first.
///
/// Grouped per visit rather than summed into one dish list on purpose: "the
/// table had 3 kebabs" answers a different question from "last time they had a
/// kebab and a tea". The cashier is asking the second one.
class CashierTableHistoryPage extends ConsumerStatefulWidget {
  const CashierTableHistoryPage({
    super.key,
    required this.tableId,
    required this.tableName,
    required this.shiftId,
  });

  final int tableId;
  final String tableName;
  final int shiftId;

  @override
  ConsumerState<CashierTableHistoryPage> createState() =>
      _CashierTableHistoryPageState();
}

class _CashierTableHistoryPageState
    extends ConsumerState<CashierTableHistoryPage> {
  late Future<List<_Visit>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Visit>> _load() async {
    final db = ref.read(localDbProvider);
    final orders = await db.getSettledOrdersByShiftId(widget.shiftId);
    final mine = orders.where((o) => o.tableId == widget.tableId).toList();
    final visits = <_Visit>[];
    for (final order in mine) {
      final items = await db.getSettledOrderItems(order.id);
      visits.add(_Visit(order: order, items: items));
    }
    return visits;
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
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
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.table_restaurant_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.tableName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.darkText,
                    ),
                  ),
                  Text(
                    context.tr('مێژووی مێز'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.softText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: FutureBuilder<List<_Visit>>(
        future: _future,
        builder: (context, snapshot) {
          final visits = snapshot.data ?? const <_Visit>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              visits.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (visits.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 72,
                    color: AppColors.softText.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      context.tr('هیچ داواکارییەکی پێشوو نییە لەم شەفتەدا'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: AppColors.softText),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              children: [
                ...visits.asMap().entries.map(
                      (e) => _visitCard(e.value, visits.length - e.key),
                    ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _visitCard(_Visit visit, int ordinal) {
    final order = visit.order;
    final methodColor = paymentMethodColor(order.paymentMethod);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.trp('{count} سەردان', {'count': ordinal.toString()}),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatShiftTime(context, order.settledAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.softText,
                  ),
                ),
              ),
              _methodChip(methodColor, order.paymentMethod),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...visit.items.map(_itemRow),
          if (order.discountAmount > 0) ...[
            const SizedBox(height: 6),
            _totalLine(
              context.tr('داشکاندن'),
              '- ${context.tr('د.ع')} ${money(order.discountAmount)}',
              AppColors.success,
            ),
          ],
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _totalLine(
                  context.tr('کۆی گشتی'),
                  '${context.tr('د.ع')} ${money(order.totalAmount)}',
                  AppColors.primary,
                  bold: true,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _reprint(order, visit.items),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: Text(context.tr('چاپکردنەوەی حیساب')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemRow(SettledOrderItem item) {
    final subtotal = item.itemPrice * item.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.itemName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: AppColors.darkText),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.quantity} × ${context.tr('د.ع')} ${money(item.itemPrice)}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.softText),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              '${context.tr('د.ع')} ${money(subtotal)}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalLine(String label, String value, Color color, {bool bold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _methodChip(Color color, String method) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(paymentMethodIcon(method), size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            paymentMethodLabel(context, method),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Reprints one visit's receipt, the way the old «داواکارییەکانی پێشوو»
  /// sheet could. The dishes come from the settled record, not the live table,
  /// so a table that has since been re-seated still prints what it actually
  /// paid for.
  Future<void> _reprint(SettledOrder order, List<SettledOrderItem> items) async {
    final user = ref.read(authProvider);
    final cashierName = user?.name ?? '';
    final printerState = ref.read(printerProvider);
    final cashierPrinter = printerState.printers
        .where((p) => p.printerType == PrinterType.cashier)
        .firstOrNull;
    final orderItems = items
        .map(
          (i) => OrderItem(
            id: i.id.toString(),
            name: i.itemName,
            price: i.itemPrice,
            quantity: i.quantity,
            category: i.category,
          ),
        )
        .toList();
    final design = await ref.read(localDbProvider).getReceiptDesign();
    if (!mounted) return;
    final confirmed = await PrintPreview.showReceiptPreview(
      context,
      tableNumber: order.tableId,
      guestCount: 1,
      items: orderItems,
      subtotal: order.totalAmount + order.discountAmount,
      discountPercent: order.discountPercent,
      discountAmount: order.discountAmount,
      total: order.totalAmount,
      waiterName: '',
      cashierName: cashierName,
      printerName: cashierPrinter?.name ?? '',
      seatedAt: order.seatedAt,
      design: design,
    );
    if (confirmed && context.mounted && cashierPrinter != null) {
      await PrintRouter.dispatchReceipt(
        tableNumber: order.tableId,
        guestCount: 1,
        items: orderItems,
        subtotal: order.totalAmount + order.discountAmount,
        discountPercent: order.discountPercent,
        discountAmount: order.discountAmount,
        total: order.totalAmount,
        printer: cashierPrinter,
        waiterName: '',
        cashierName: cashierName,
        seatedAt: order.seatedAt,
        design: design,
      );
    }
  }
}

/// A table's settled orders in one shift, folded into the row the list draws.
class _TableSummary {
  final int tableId;
  final String tableName;
  final int visits;
  final String lastSettledAt;
  final double total;

  const _TableSummary({
    required this.tableId,
    required this.tableName,
    required this.visits,
    required this.lastSettledAt,
    required this.total,
  });

  _TableSummary copyWith({
    String? tableName,
    int? visits,
    String? lastSettledAt,
    double? total,
  }) {
    return _TableSummary(
      tableId: tableId,
      tableName: tableName ?? this.tableName,
      visits: visits ?? this.visits,
      lastSettledAt: lastSettledAt ?? this.lastSettledAt,
      total: total ?? this.total,
    );
  }
}

/// One settlement with the dishes it closed.
class _Visit {
  final SettledOrder order;
  final List<SettledOrderItem> items;

  const _Visit({required this.order, required this.items});
}
