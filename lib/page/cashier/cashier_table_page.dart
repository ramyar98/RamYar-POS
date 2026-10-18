import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/responsive.dart';
import 'dart:async';
import '../../database/local_db.dart';
import '../../models/table_model.dart';
import '../../models/order_model.dart';
import '../../models/debt_model.dart';
import '../../models/settlement_model.dart';
import '../../models/printer_model.dart';
import '../../providers/waiter_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/print_router.dart';
import '../../widgets/print_preview_dialog.dart';
import 'transfer_page.dart';

class CashierTablePage extends ConsumerStatefulWidget {
  final int tableNumber;
  const CashierTablePage({super.key, required this.tableNumber});

  @override
  ConsumerState<CashierTablePage> createState() => _CashierTablePageState();
}

class _CashierTablePageState extends ConsumerState<CashierTablePage> {
  final _discountController = TextEditingController();
  final _usdRateController = TextEditingController();
  final _usdInputController = TextEditingController();
  final _iqdInputController = TextEditingController();

  @override
  void dispose() {
    _discountController.dispose();
    _usdRateController.dispose();
    _usdInputController.dispose();
    _iqdInputController.dispose();
    super.dispose();
  }

  int _parseDiscount() => int.tryParse(_discountController.text) ?? 0;

  double _parseAmount(String text) =>
      double.tryParse(text.replaceAll(',', '')) ?? 0;

  String _formatIqd(double value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }

  String _formatUsd(double value) => value.toStringAsFixed(2);

  void _onUsdChanged(String value) {
    final rate = _parseAmount(_usdRateController.text);
    final usd = _parseAmount(value);
    if (rate > 0 && usd > 0) {
      _iqdInputController.text = _formatIqd(usd * rate / 100);
    } else {
      _iqdInputController.text = '';
    }
  }

  void _onIqdChanged(String value) {
    final rate = _parseAmount(_usdRateController.text);
    final iqd = _parseAmount(value);
    if (rate > 0 && iqd > 0) {
      _usdInputController.text = _formatUsd(iqd * 100 / rate);
    } else {
      _usdInputController.text = '';
    }
  }

  double _calcDiscountedTotal(double total, int discountPercent) {
    if (discountPercent <= 0 || discountPercent >= 100) return total;
    return total * (1 - discountPercent / 100);
  }

  Future<void> _moveToDebts(double amount) async {
    final db = ref.read(localDbProvider);
    final user = ref.read(authProvider);
    final now = DateTime.now().toIso8601String();
    // Tied to the open shift so closing it drops the debt from the till.
    final shift = user != null ? await db.getActiveShift(user.id) : null;
    // Snapshot the dishes before the order is cleared so the debt still shows
    // what was ordered when it is opened later.
    final items = await db.getOrderItems(widget.tableNumber);
    final snapshot = encodeDebtLines(
      items.map(
        (i) => DebtLine(name: i.name, price: i.price, quantity: i.quantity),
      ),
    );
    await db.addDebt(
      DebtModel(
        id: 0,
        tableId: widget.tableNumber,
        tableName: 'مێزی ${widget.tableNumber}',
        amount: amount,
        reason: 'قەرز',
        createdAt: now,
        createdBy: user?.id ?? 0,
        shiftId: shift?.id ?? 0,
        itemsJson: snapshot,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('گوازرایەوە بۆ قەرزەکان')),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Widget _billItemRow(OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${context.tr('د.ع')} ${money(item.price)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'x${item.quantity}',
            style: const TextStyle(color: AppColors.softText),
          ),
          // 8px instead of the original 16, and 2px between the two icon
          // buttons instead of 4: together they keep the row's fixed content
          // under the width of the narrowest panel (280px screen) now that
          // the action buttons carry a 40px tap target.
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              '${context.tr('د.ع')} ${money((item.price * item.quantity))}',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 40x40 tap target (18px icon + 11px padding); the old 6px padding
          // made a ~30px target that was easy to miss with a thumb.
          InkWell(
            onTap: () => _showTransferSingleItemDialog(item.id, item.name),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () async {
              final db = ref.read(localDbProvider);
              final user = ref.read(authProvider);
              await db.addRefund(
                Refund(
                  tableId: widget.tableNumber,
                  itemName: item.name,
                  quantity: item.quantity,
                  price: item.price,
                  refundedAt: DateTime.now().toIso8601String(),
                  refundedBy: user?.id ?? 0,
                ),
              );
              ref
                  .read(waiterProvider.notifier)
                  .removeItem(widget.tableNumber, item.id);
            },
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTransferSingleItemDialog(String itemId, String itemName) {
    final tablesAsync = ref.read(waiterProvider);
    tablesAsync.whenData((tables) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          int? selectedId;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final emptyTables = tables
                  .where(
                    (t) =>
                        t.status == TableStatus.empty &&
                        t.id != widget.tableNumber,
                  )
                  .toList();
              final occupiedTables = tables
                  .where(
                    (t) =>
                        t.status != TableStatus.empty &&
                        t.id != widget.tableNumber,
                  )
                  .toList();
              return AlertDialog(
                title: Text(
                  context.trp('گواستنەوەی {itemName}', {'itemName': itemName}),
                ),
                content: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('بەتاڵەکان:'),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      if (emptyTables.isEmpty)
                        Text(
                          context.tr('نییە'),
                          style: TextStyle(color: AppColors.softText),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: emptyTables.map((t) {
                            final isSel = selectedId == t.id;
                            return ChoiceChip(
                              label: Text(
                                t.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: isSel,
                              onSelected: (_) =>
                                  setDialogState(() => selectedId = t.id),
                              selectedColor: AppColors.success.withValues(
                                alpha: 0.2,
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr('گیراوەکان:'),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      if (occupiedTables.isEmpty)
                        Text(
                          context.tr('نییە'),
                          style: TextStyle(color: AppColors.softText),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: occupiedTables.map((t) {
                            final isSel = selectedId == t.id;
                            return ChoiceChip(
                              label: Text(
                                t.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: isSel,
                              onSelected: (_) =>
                                  setDialogState(() => selectedId = t.id),
                              selectedColor: AppColors.primary.withValues(
                                alpha: 0.2,
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.tr('ڕەتکردنەوە')),
                  ),
                  FilledButton(
                    onPressed: selectedId == null
                        ? null
                        : () => Navigator.pop(ctx, selectedId!),
                    child: Text(context.tr('گواستنەوە')),
                  ),
                ],
              );
            },
          );
        },
      ).then((targetId) async {
        if (targetId == null) return;
        final db = ref.read(localDbProvider);
        await db.transferSingleItem(
          widget.tableNumber,
          targetId as int,
          itemId,
        );
        ref.invalidate(tableOrdersProvider(widget.tableNumber));
        ref.invalidate(tableOrdersProvider(targetId));
        await ref.read(waiterProvider.notifier).refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.trp('{itemName} گوازرایەوە', {'itemName': itemName}),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(tableOrdersProvider(widget.tableNumber));
    final tableAsync = ref.watch(tableDetailProvider(widget.tableNumber));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.trp('مێزی {tableNumber} - کاشێر', {
            'tableNumber': widget.tableNumber.toString(),
          }),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (orderItems) {
          final table = tableAsync.valueOrNull;
          final total = orderItems.fold<double>(
            0,
            (sum, item) => sum + (item.price * item.quantity),
          );
          final discountPercent = _parseDiscount();
          final discountedTotal = _calcDiscountedTotal(total, discountPercent);
          final discountAmount = total - discountedTotal;

          final isPhone = Responsive.isPhone(context);
          final itemsCard = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.receipt_rounded,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.trp('مێزی {tableNumber} - حیساب', {
                              'tableNumber': widget.tableNumber.toString(),
                            }),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                          if (table != null)
                            Text(
                              context.trp(
                                'میوان: {guestCount} کەس • کاتی دانیشتن: {seatedTime}',
                                {
                                  'guestCount': table.guestCount.toString(),
                                  'seatedTime': table.seatedTimeDisplay,
                                },
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.softText,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (isPhone)
                  orderItems.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              context.tr('هیچ خواردنێک تۆمارنەکراوە'),
                              style: TextStyle(color: AppColors.softText),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: orderItems.length,
                          itemBuilder: (context, index) =>
                              _billItemRow(orderItems[index]),
                        ),
                if (!isPhone)
                  Expanded(
                    child: orderItems.isEmpty
                        ? Center(
                            child: Text(
                              context.tr('هیچ خواردنێک تۆمارنەکراوە'),
                              style: TextStyle(color: AppColors.softText),
                            ),
                          )
                        : ListView.builder(
                            itemCount: orderItems.length,
                            itemBuilder: (context, index) =>
                                _billItemRow(orderItems[index]),
                          ),
                  ),
              ],
            ),
          );
          final payCard = SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('وردەکاری پارەدان'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  if (discountPercent > 0 && discountPercent < 100) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.tr('داشکاندن'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '-${context.tr('د.ع')} ${money(discountAmount)} ($discountPercent%)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.tr('کۆی پاش داشکاندن'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${context.tr('د.ع')} ${money(discountedTotal)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.discount_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          context.tr('داشکاندن (%)'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '0',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 6,
                            ),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          context.tr('کۆی گشتی'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${context.tr('د.ع')} ${money(total)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('گۆڕینەوەی نرخ'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          context.tr('نرخی 100\$:'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _usdRateController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('د.ع'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _usdInputController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.tr('USD \$'),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          onChanged: _onUsdChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _iqdInputController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.tr('IQD د.ع'),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          onChanged: _onIqdChanged,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final finalAmount =
                                discountPercent > 0 && discountPercent < 100
                                ? discountedTotal
                                : total;
                            final db = ref.read(localDbProvider);
                            final user = ref.read(authProvider);
                            final shift = user != null
                                ? await db.getActiveShift(user.id)
                                : null;
                            await db.settleTable(
                              widget.tableNumber,
                              finalAmount,
                              discountPercent.toDouble(),
                              discountAmount,
                              user?.id ?? 0,
                              shiftId: shift?.id ?? 0,
                            );
                            await ref.read(waiterProvider.notifier).refresh();
                            if (!context.mounted) return;
                            Navigator.pop(context, true);
                          },
                          icon: const Icon(Icons.monetization_on_rounded),
                          label: Text(
                            discountPercent > 0 && discountPercent < 100
                                ? 'د.ع ${money(discountedTotal)}'
                                : context.tr('پارە (کاش)'),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            backgroundColor: AppColors.success,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final finalAmount =
                                discountPercent > 0 && discountPercent < 100
                                ? discountedTotal
                                : total;
                            final db = ref.read(localDbProvider);
                            final user = ref.read(authProvider);
                            final shift = user != null
                                ? await db.getActiveShift(user.id)
                                : null;
                            await db.settleTable(
                              widget.tableNumber,
                              finalAmount,
                              discountPercent.toDouble(),
                              discountAmount,
                              user?.id ?? 0,
                              shiftId: shift?.id ?? 0,
                            );
                            await ref.read(waiterProvider.notifier).refresh();
                            if (!context.mounted) return;
                            Navigator.pop(context, true);
                          },
                          icon: const Icon(Icons.credit_card_rounded),
                          label: Text(
                            discountPercent > 0 && discountPercent < 100
                                ? 'د.ع ${money(discountedTotal)}'
                                : context.tr('کارت'),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            backgroundColor: AppColors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final db = ref.read(localDbProvider);
                            final printerState = ref.read(printerProvider);
                            final cashierPrinter = printerState.printers
                                .where(
                                  (p) => p.printerType == PrinterType.cashier,
                                )
                                .firstOrNull;
                            if (cashierPrinter != null) {
                              final tableModel = table;
                              final currentUser = ref.read(authProvider);
                              final confirmed =
                                  await PrintPreview.showReceiptPreview(
                                    context,
                                    tableNumber: widget.tableNumber,
                                    guestCount: tableModel?.guestCount ?? 0,
                                    items: orderItems,
                                    subtotal: total,
                                    discountPercent: discountPercent.toDouble(),
                                    discountAmount: discountAmount,
                                    total:
                                        discountPercent > 0 &&
                                            discountPercent < 100
                                        ? discountedTotal
                                        : total,
                                    cashierName: currentUser?.name ?? '',
                                    printerName: cashierPrinter.name,
                                  );
                              if (confirmed) {
                                await db.markAsPrinted(widget.tableNumber);
                                await PrintRouter.dispatchReceipt(
                                  tableNumber: widget.tableNumber,
                                  guestCount: tableModel?.guestCount ?? 0,
                                  items: orderItems,
                                  subtotal: total,
                                  discountPercent: discountPercent.toDouble(),
                                  discountAmount: discountAmount,
                                  total:
                                      discountPercent > 0 &&
                                          discountPercent < 100
                                      ? discountedTotal
                                      : total,
                                  printer: cashierPrinter,
                                  cashierName: currentUser?.name ?? '',
                                );
                              }
                            }
                            await ref.read(waiterProvider.notifier).refresh();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  context.tr('بە سەرکەوتووی چاپکرا'),
                                ),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          },
                          icon: const Icon(Icons.print_rounded),
                          label: Text(context.tr('چاپ')),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            foregroundColor: AppColors.darkText,
                            side: const BorderSide(color: AppColors.borderSide),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _moveToDebts(
                            discountPercent > 0 && discountPercent < 100
                                ? discountedTotal
                                : total,
                          ),
                          icon: const Icon(
                            Icons.bookmark_add_rounded,
                            color: AppColors.danger,
                          ),
                          label: Text(
                            context.tr('قەرز'),
                            style: TextStyle(color: AppColors.danger),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                TransferPage(sourceTableId: widget.tableNumber),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.swap_horiz_rounded,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        context.tr('گواستنەوەی هەموو'),
                        style: TextStyle(color: AppColors.primary),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final db = ref.read(localDbProvider);
                        // A table with food on it can never be deleted: tell the
                        // cashier why and leave everything alone.
                        final openFood = await db.getOrderItems(
                          widget.tableNumber,
                        );
                        if (!context.mounted) return;
                        if (openFood.isNotEmpty) {
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(ctx.tr('سڕینەوەی مێز')),
                              content: Text(
                                ctx.tr(
                                  'ناتوانیت مێز بسڕیتەوە چونکە خواردن لەناو مێزەکەدایە. سەرەتا حیسابەکە واسڵ بکە یان خواردنەکە بۆ مێزێکی تر بگوازەوە.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text(ctx.tr('باشە')),
                                ),
                              ],
                            ),
                          );
                          return;
                        }
                        final user = ref.read(authProvider);
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(ctx.tr('سڕینەوەی مێز')),
                            content: Text(
                              ctx.trp(
                                'دڵنیایت دەتەوێت مێزی {tableNumber} بسڕیتەوە؟',
                                {'tableNumber': widget.tableNumber.toString()},
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(ctx.tr('ڕەتکردنەوە')),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(ctx.tr('سڕینەوە')),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await db.deleteTable(
                            widget.tableNumber,
                            cancelledBy: user?.id ?? 0,
                            cancelledByName: user?.name ?? '',
                          );
                          await ref.read(waiterProvider.notifier).refresh();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: AppColors.danger,
                      ),
                      label: Text(
                        context.tr('سڕینەوەی مێز'),
                        style: TextStyle(color: AppColors.danger),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        side: const BorderSide(color: AppColors.danger),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          if (isPhone) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [payCard, const SizedBox(height: 12), itemsCard],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: payCard),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: itemsCard),
              ],
            ),
          );
        },
      ),
    );
  }
}
