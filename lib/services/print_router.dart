import 'dart:async';
import '../models/printer_model.dart';
import '../models/order_model.dart';
import '../models/receipt_design_model.dart';
import '../providers/printer_provider.dart';
import 'esc_pos_builder.dart';
import 'printer_discovery_service.dart';

class PrintJobResult {
  final PrintJob job;
  final bool success;
  final String? error;

  const PrintJobResult({
    required this.job,
    required this.success,
    this.error,
  });
}

class PrintRouter {
  final PrinterProviderState config;

  const PrintRouter(this.config);

  List<PrintJob> routeOrder(
    List<OrderItem> items, {
    String waiterName = '',
    int tableNumber = 0,
    String tableLabel = '',
  }) {
    final jobs = <PrintJob>[];
    final groups = <PrinterType, List<OrderItem>>{};

    for (final item in items) {
      final types = _resolvePrintersForItem(item);
      for (final type in types) {
        groups.putIfAbsent(type, () => []).add(item);
      }
    }

    for (final entry in groups.entries) {
      final printerConfig = _printerForType(entry.key);
      // When a targeted printer type has no printer configured, keep the job
      // with an empty printer name so the dispatch fails loudly instead of
      // silently dropping those items from the ticket while others print.
      jobs.add(PrintJob(
        items: entry.value.map((item) => PrintJobItem(
          name: item.name,
          quantity: item.quantity,
          category: item.category,
          waiterName: waiterName,
          tableNumber: tableNumber,
          tableLabel: tableLabel,
          price: item.price,
          itemId: item.id,
        )).toList(),
        printerType: entry.key,
        printerName: printerConfig?.name ?? '',
        printerPort: printerConfig?.portName ?? '',
      ));
    }

    return jobs;
  }

  List<PrinterType> _resolvePrintersForItem(OrderItem item) {
    final multi = config.itemPrinterAssignments[item.name];
    if (multi != null && multi.isNotEmpty) return multi;

    final override = config.itemOverrides[item.name];
    if (override != null) return [override];

    final mapping = config.categoryMappings[item.category];
    if (mapping != null) return [mapping];

    return [PrinterType.kitchen];
  }

  List<PrinterType> resolvePrintersForItem(OrderItem item) =>
      _resolvePrintersForItem(item);

  PrinterConfig? _printerForType(PrinterType type) {
    final printers = config.printers
        .where((p) => p.printerType == type && p.name.isNotEmpty)
        .toList();
    if (printers.isEmpty) return null;
    final defaultPrinter = printers.where((p) => p.isDefault).firstOrNull;
    return defaultPrinter ?? printers.first;
  }

  static Future<PrintJobResult> dispatchPrintJob(PrintJob job) async {
    try {
      if (job.printerName.trim().isEmpty) {
        return PrintJobResult(job: job, success: false, error: 'No printer configured for type ${job.printerType.name}');
      }
      final data = _buildTicket(job);
      if (data.isEmpty) {
        return PrintJobResult(job: job, success: false, error: 'Empty ticket data');
      }
      final ok = await PrinterDiscoveryService.printRaw(job.printerName, data, portName: job.printerPort);
      if (ok) {
        return PrintJobResult(job: job, success: true);
      }
      return PrintJobResult(job: job, success: false, error: 'Print command returned false');
    } catch (e) {
      return PrintJobResult(job: job, success: false, error: e.toString());
    }
  }

  static Future<PrintJobResult> dispatchPrintJobWithFallback(
    PrintJob job,
    PrinterConfig fallbackPrinter,
  ) async {
    final result = await dispatchPrintJob(job);
    if (result.success) return result;

    final fallbackJob = PrintJob(
      items: job.items,
      printerType: job.printerType,
      printerName: fallbackPrinter.name,
      printerPort: fallbackPrinter.portName,
    );
    final fallbackResult = await dispatchPrintJob(fallbackJob);
    return PrintJobResult(
      job: fallbackResult.success ? fallbackJob : job,
      success: fallbackResult.success,
      error: fallbackResult.success
          ? null
          : 'Primary and fallback both failed: ${result.error}',
    );
  }

  static Future<List<PrintJobResult>> dispatchAllJobs(
    List<PrintJob> jobs,
    PrinterConfig? globalFallback,
  ) async {
    final results = <PrintJobResult>[];
    for (final job in jobs) {
      // A group whose printer type has no configured device is a real failure
      // and must not be silently re-routed to the cashier fallback.
      if (globalFallback != null && job.printerName.trim().isNotEmpty) {
        results.add(await dispatchPrintJobWithFallback(job, globalFallback));
      } else {
        results.add(await dispatchPrintJob(job));
      }
    }
    return results;
  }

  static Future<bool> dispatchReceipt({
    required int tableNumber,
    required int guestCount,
    required List<OrderItem> items,
    required double subtotal,
    required double discountPercent,
    required double discountAmount,
    required double total,
    required PrinterConfig printer,
    PrinterConfig? fallbackPrinter,
    String waiterName = '',
    String cashierName = '',
    String seatedAt = '',
    String tableLabel = '',
    ReceiptDesign design = ReceiptDesign.standard,
  }) async {
    final receiptItems = items.map((item) => PrintJobItem(
      name: item.name,
      quantity: item.quantity,
      category: item.category,
      price: item.price,
    )).toList();

    final data = EscPosBuilder.buildCashierReceipt(
      tableNumber: tableNumber,
      guestCount: guestCount,
      items: receiptItems,
      subtotal: subtotal,
      discountPercent: discountPercent,
      discountAmount: discountAmount,
      total: total,
      waiterName: waiterName,
      cashierName: cashierName,
      seatedAt: seatedAt,
      tableLabel: tableLabel,
      design: design,
    );

    bool ok = await PrinterDiscoveryService.printRaw(printer.name, data, portName: printer.portName);
    if (!ok && fallbackPrinter != null) {
      ok = await PrinterDiscoveryService.printRaw(fallbackPrinter.name, data, portName: fallbackPrinter.portName);
    }
    return ok;
  }

  static Future<bool> dispatchRawCommand(PrinterConfig printer, List<int> data) async {
    return await PrinterDiscoveryService.printRaw(printer.name, data, portName: printer.portName);
  }

  static List<int> _buildTicket(PrintJob job) {
    return EscPosBuilder.buildKitchenTicket(job);
  }
}
