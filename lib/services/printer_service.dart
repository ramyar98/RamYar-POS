import 'dart:async';
import '../core/app_log.dart';
import '../models/order_model.dart';
import '../models/printer_model.dart';
import '../providers/printer_provider.dart';
import 'print_router.dart';

class PrintJobSummary {
  final int totalJobs;
  final int successfulJobs;
  final int failedJobs;
  final List<String> errors;

  const PrintJobSummary({
    required this.totalJobs,
    required this.successfulJobs,
    required this.failedJobs,
    required this.errors,
  });

  bool get allSucceeded => failedJobs == 0;
}

class PrinterService {
  final PrinterProviderState _config;

  PrinterService(this._config);

  Future<PrintJobSummary> printOrder({
    required int tableNumber,
    required List<OrderItem> items,
    required String waiterName,
  }) async {
    if (items.isEmpty) {
      return const PrintJobSummary(
        totalJobs: 0,
        successfulJobs: 0,
        failedJobs: 0,
        errors: [],
      );
    }

    try {
      final router = PrintRouter(_config);
      final jobs = router.routeOrder(
        items,
        waiterName: waiterName,
        tableNumber: tableNumber,
      );

      if (jobs.isEmpty) {
        appLog('[PrinterService] No printers configured for order items');
        return const PrintJobSummary(
          totalJobs: 0, successfulJobs: 0, failedJobs: 0, errors: ['No printers configured'],
        );
      }

      final cashierPrinter = _findCashierPrinter();
      final results = await PrintRouter.dispatchAllJobs(jobs, cashierPrinter);

      final summary = PrintJobSummary(
        totalJobs: results.length,
        successfulJobs: results.where((r) => r.success).length,
        failedJobs: results.where((r) => !r.success).length,
        errors: results
            .where((r) => !r.success && r.error != null)
            .map((r) => '${r.job.printerType.name}: ${r.error}')
            .toList(),
      );

      appLog('[PrinterService] Printed $tableNumber: '
          '${summary.successfulJobs}/${summary.totalJobs} jobs OK');
      if (summary.failedJobs > 0) {
        appLog('[PrinterService] Print failures: ${summary.errors}');
      }

      return summary;
    } catch (e) {
      appLog('[PrinterService] printOrder error: $e');
      return PrintJobSummary(
        totalJobs: 0, successfulJobs: 0, failedJobs: 1, errors: [e.toString()],
      );
    }
  }

  Future<bool> printReceipt({
    required int tableNumber,
    required int guestCount,
    required List<OrderItem> items,
    required double subtotal,
    required double discountPercent,
    required double discountAmount,
    required double total,
    required String waiterName,
    required String cashierName,
    required String seatedAt,
  }) async {
    try {
      final cashierPrinter = _findCashierPrinter();
      if (cashierPrinter == null) {
        appLog('[PrinterService] No cashier printer configured for receipt');
        return false;
      }

      final fallbackPrinter = _findFallbackFor(cashierPrinter);
      return await PrintRouter.dispatchReceipt(
        tableNumber: tableNumber,
        guestCount: guestCount,
        items: items,
        subtotal: subtotal,
        discountPercent: discountPercent,
        discountAmount: discountAmount,
        total: total,
        waiterName: waiterName,
        cashierName: cashierName,
        seatedAt: seatedAt,
        printer: cashierPrinter,
        fallbackPrinter: fallbackPrinter,
      );
    } catch (e) {
      appLog('[PrinterService] printReceipt error: $e');
      return false;
    }
  }

  PrinterConfig? _findCashierPrinter() {
    final printers = _config.printers
        .where((p) => p.printerType == PrinterType.cashier && p.name.isNotEmpty)
        .toList();
    if (printers.isEmpty) return null;
    return printers.where((p) => p.isDefault).firstOrNull ?? printers.first;
  }

  PrinterConfig? _findFallbackFor(PrinterConfig primary) {
    final others = _config.printers
        .where((p) => p.id != primary.id && p.name.isNotEmpty)
        .toList();
    if (others.isEmpty) return null;
    return others.first;
  }
}
