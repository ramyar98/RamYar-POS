import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../core/fmt.dart';
import '../services/app_localizations.dart';
import '../models/printer_model.dart';
import '../models/order_model.dart';
import '../models/receipt_design_model.dart';

class PrintPreview {
  static Future<bool> showKitchenPreview(BuildContext context, PrintJob job) {
    if (job.items.isEmpty) return Future.value(false);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PrintPreviewDialog(
        title: ctx.tr('پێشبینینی چاپ'),
        subtitle: _typeLabel(job.printerType),
        sections: [
          _PreviewSection(
            label: ctx.tr('مێز و کات'),
            lines: [
              '${ctx.tr('مێز')}: ${job.items.first.tableNumber}',
              '${ctx.tr('وەیتەر')}: ${job.items.first.waiterName}',
              '${ctx.tr('کات')}: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            ],
          ),
          _PreviewSection(
            label: ctx.tr('خواردنەکان'),
            lines: job.items
                .map((item) => 'x${item.quantity} ${item.name}')
                .toList(),
          ),
        ],
        itemsCount: job.items.length,
        printerName: job.printerName,
      ),
    ).then((v) => v ?? false);
  }

  static Future<bool> showAllJobsPreview(
    BuildContext context,
    List<PrintJob> jobs,
  ) {
    if (jobs.isEmpty) return Future.value(false);
    if (jobs.length == 1) return showKitchenPreview(context, jobs.first);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        int totalItems = 0;
        for (final j in jobs) {
          totalItems += j.items.length;
        }
        return _PrintPreviewDialog(
          title: ctx.tr('پێشبینینی چاپ'),
          subtitle: ctx.trp('{count} پرینتەر', {
            'count': jobs.length.toString(),
          }),
          sections: jobs
              .expand(
                (job) => [
                  _PreviewSection(
                    label:
                        '${_typeLabel(job.printerType)} — ${job.printerName}',
                    lines: job.items
                        .map((item) => 'x${item.quantity} ${item.name}')
                        .toList(),
                  ),
                ],
              )
              .toList(),
          itemsCount: totalItems,
          printerName: null,
        );
      },
    ).then((v) => v ?? false);
  }

  static Future<bool> showReceiptPreview(
    BuildContext context, {
    required int tableNumber,
    required int guestCount,
    required List<OrderItem> items,
    required double subtotal,
    required double discountPercent,
    required double discountAmount,
    required double total,
    String waiterName = '',
    String cashierName = '',
    String printerName = '',
    String seatedAt = '',
    ReceiptDesign design = ReceiptDesign.standard,
  }) {
    final lines = <String>[];
    for (final item in items) {
      lines.add(
        '${item.name}  x${item.quantity}  ${_fmt(item.price * item.quantity, context.tr('د.ع'))}',
      );
    }

    // Only the rows the design turns on: the cashier confirms the slip that is
    // actually about to be printed, so a field the admin hid must not appear
    // here either.
    final tableLines = <String>[
      if (design.showTable && design.showGuestCount)
        '${context.tr('مێز')}: $tableNumber  ${context.tr('میوان')}: $guestCount'
      else if (design.showTable)
        '${context.tr('مێز')}: $tableNumber'
      else if (design.showGuestCount)
        '${context.tr('میوان')}: $guestCount',
      if (design.showSeatedAt && seatedAt.isNotEmpty)
        '${context.tr('کاتی دانیشتن')}: ${_fmtTime(seatedAt)}',
      if (design.showLeaveTime)
        '${context.tr('کاتی ڕۆیشتن')}: ${DateTime.now().toString().substring(0, 19)}',
      if (design.showWaiter && waiterName.isNotEmpty)
        '${context.tr('کاپتن')}: $waiterName',
      if (design.showCashier && cashierName.isNotEmpty)
        '${context.tr('کاشێر')}: $cashierName',
    ];

    final sections = <_PreviewSection>[
      if (tableLines.isNotEmpty)
        _PreviewSection(label: context.tr('زانیاری مێز'), lines: tableLines),
      if (design.showItems)
        _PreviewSection(label: context.tr('خواردنەکان'), lines: lines),
    ];

    final totalLines = <String>[
      if (design.showSubtotal)
        '${context.tr('کۆی یەکەم')}: ${_fmt(subtotal, context.tr('د.ع'))}',
      if (design.showDiscount && discountAmount > 0)
        '${context.tr('داشکاندن')}${discountPercent > 0 && discountPercent < 100 ? ' ($discountPercent%)' : ''}: -${_fmt(discountAmount, context.tr('د.ع'))}',
      if (design.showTotal)
        '${context.tr('کۆی پاش داشکاندن')}: ${_fmt(total, context.tr('د.ع'))}',
    ];
    if (totalLines.isNotEmpty) {
      sections.add(
        _PreviewSection(label: context.tr('کۆی گشتی'), lines: totalLines),
      );
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PrintPreviewDialog(
        title: ctx.tr('پێشبینینی چاپی حیساب'),
        subtitle: ctx.tr('حیسابی کاشێر'),
        sections: sections,
        printerName: printerName,
      ),
    ).then((v) => v ?? false);
  }

  static String _fmt(double v, String iqd) => '${money(v)} $iqd';
  static String _fmtTime(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso.length >= 5 ? iso.substring(0, 5) : iso;
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _typeLabel(PrinterType type) {
    switch (type) {
      case PrinterType.kitchen:
        return 'Kitchen';
      case PrinterType.bar:
        return 'Bar';
      case PrinterType.hookah:
        return 'Hookah';
      case PrinterType.cashier:
        return 'Cashier';
    }
  }
}

class _PreviewSection {
  final String label;
  final List<String> lines;
  const _PreviewSection({required this.label, required this.lines});
}

class _PrintPreviewDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_PreviewSection> sections;
  final String? printerName;
  final int? itemsCount;

  const _PrintPreviewDialog({
    required this.title,
    required this.subtitle,
    required this.sections,
    this.printerName,
    this.itemsCount,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderSide)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.print_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.softText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final section in sections) ...[
                    _buildSectionHeader(context, section.label),
                    const SizedBox(height: 8),
                    ...section.lines.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 12),
                        child: Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.darkText,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (itemsCount != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              context.trp('{count} جۆر خواردن', {
                                'count': itemsCount.toString(),
                              }),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (printerName != null && printerName!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.print_rounded,
                          size: 16,
                          color: AppColors.softText,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${context.tr('پرینتەر')}: $printerName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.softText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSide)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.softText,
                        side: const BorderSide(color: AppColors.borderSide),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        context.tr('ڕەتکردنەوە'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: Text(
                        context.tr('چاپکردن'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
        ),
      ],
    );
  }
}
