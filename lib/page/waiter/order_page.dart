import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../database/local_db.dart';
import '../../models/order_model.dart';
import '../../models/printer_model.dart';
import '../../providers/waiter_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/print_router.dart';
import '../../services/sync_provider.dart';
import '../../widgets/print_preview_dialog.dart';

class OrderPage extends ConsumerStatefulWidget {
  final int tableNumber;
  const OrderPage({super.key, required this.tableNumber});

  @override
  ConsumerState<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends ConsumerState<OrderPage> {
  /// True while a print preview is open (or its dispatch is still running).
  /// Both print buttons used to stay live, so a double tap opened two stacked
  /// previews and confirming each sent the same dishes to the kitchen twice.
  bool _printing = false;

  Future<void> _printKitchenTickets() async {
    if (_printing) return;
    final printerState = ref.read(printerProvider);
    final router = PrintRouter(printerState);
    final user = ref.read(authProvider);
    final items =
        ref.read(tableOrdersProvider(widget.tableNumber)).valueOrNull ?? [];
    if (items.isEmpty) return;
    final jobs = router.routeOrder(
      items,
      waiterName: user?.name ?? '',
      tableNumber: widget.tableNumber,
    );
    if (jobs.isEmpty) return;
    _printing = true;
    try {
      final confirmed = await PrintPreview.showAllJobsPreview(context, jobs);
      if (confirmed) {
        await dispatchOrderPrintJobs(ref.read(localDbProvider), jobs,
            tableId: widget.tableNumber);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('بە سەرکەوتووی چاپکرا')),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } finally {
      _printing = false;
    }
  }

  Future<void> _printReceipt(List<OrderItem> items, double total) async {
    if (_printing) return;
    final printerState = ref.read(printerProvider);
    final cashierPrinter = printerState.printers
        .where((p) => p.printerType == PrinterType.cashier)
        .firstOrNull;
    if (cashierPrinter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('هیچ پرینتەری کاشێر نەدۆزرایەوە')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    _printing = true;
    try {
      final user = ref.read(authProvider);
      final db = ref.read(localDbProvider);
      final table = await db.getTable(widget.tableNumber);
      final design = await db.getReceiptDesign();
      if (!mounted) return;
      final guestCount = table?.guestCount ?? 1;
      final confirmed = await PrintPreview.showReceiptPreview(
        context,
        tableNumber: widget.tableNumber,
        guestCount: guestCount,
        items: items,
        subtotal: total,
        discountPercent: 0,
        discountAmount: 0,
        total: total,
        waiterName: user?.name ?? '',
        printerName: cashierPrinter.name,
        design: design,
      );
      if (confirmed) {
        await db.markAsPrinted(widget.tableNumber);
        await PrintRouter.dispatchReceipt(
          tableNumber: widget.tableNumber,
          guestCount: guestCount,
          items: items,
          subtotal: total,
          discountPercent: 0,
          discountAmount: 0,
          total: total,
          printer: cashierPrinter,
          waiterName: user?.name ?? '',
          design: design,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('بە سەرکەوتووی چاپکرا')),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } finally {
      _printing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(tableOrdersProvider(widget.tableNumber));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '${context.tr('داواکاری')} - ${context.tr('مێزی')} ${widget.tableNumber}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded, color: AppColors.primary),
            tooltip: context.tr('چاپی خواردن'),
            onPressed: _printing ? null : () => _printKitchenTickets(),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (orderItems) {
          final total = orderItems.fold<double>(
            0,
            (sum, item) => sum + (item.price * item.quantity),
          );
          return Column(
            children: [
              Expanded(
                child: orderItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: AppColors.softText.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.tr('هیچ داواکاریەک نییە'),
                              style: const TextStyle(
                                fontSize: 18,
                                color: AppColors.softText,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(
                          AppConstants.paddingMedium,
                        ),
                        itemCount: orderItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = orderItems[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.fastfood,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${context.tr('د.ع')} ${money(item.price)}',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: AppColors.danger,
                                  ),
                                  onPressed: () {
                                    if (item.quantity > 1) {
                                      ref
                                          .read(waiterProvider.notifier)
                                          .updateItemQuantity(
                                            widget.tableNumber,
                                            item.id,
                                            item.quantity - 1,
                                          );
                                    }
                                  },
                                ),
                                Text(
                                  '${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkText,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    color: AppColors.success,
                                  ),
                                  onPressed: () {
                                    ref
                                        .read(waiterProvider.notifier)
                                        .updateItemQuantity(
                                          widget.tableNumber,
                                          item.id,
                                          item.quantity + 1,
                                        );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            context.tr('کۆی گشتی'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${context.tr('د.ع')} ${money(total)}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => ref
                            .read(waiterProvider.notifier)
                            .requestBill(widget.tableNumber),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          context.tr('ناردن بۆ کاشێر'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _printReceipt(orderItems, total),
                        icon: const Icon(Icons.receipt_rounded, size: 18),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          foregroundColor: AppColors.darkText,
                          side: const BorderSide(color: AppColors.borderSide),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        label: Text(
                          context.tr('چاپی ڕەسید'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
