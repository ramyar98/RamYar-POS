import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../database/local_db.dart';
import '../../models/order_model.dart';
import '../../models/printer_model.dart';
import '../../models/receipt_design_model.dart';
import '../../providers/printer_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/esc_pos_builder.dart';
import '../../services/print_router.dart';

/// «دیزاینی پرێنت» - the admin designs the receipt the till prints.
///
/// Every part of the slip is a switch, a text field or a small choice: the
/// shop's name and the receipt title, which guest and staff lines appear, the
/// dish list and the money block, the closing message, the rule between
/// sections, the paper width and the blank paper fed before the cut.
///
/// The preview down the side is built from the *same* [EscPosBuilder.receiptLayout]
/// the printer uses, so what the admin sees is exactly what comes out of the
/// till. «چاپی تاقیکردنەوە» sends a sample slip to the cashier's printer, and
/// «پاشەکەوتکردن» stores the design and syncs it to every device.
class AdminPrintDesignPage extends ConsumerStatefulWidget {
  const AdminPrintDesignPage({super.key});

  @override
  ConsumerState<AdminPrintDesignPage> createState() =>
      _AdminPrintDesignPageState();
}

class _AdminPrintDesignPageState extends ConsumerState<AdminPrintDesignPage> {
  ReceiptDesign _design = ReceiptDesign.standard;
  bool _loading = true;
  bool _printing = false;

  final _shopCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();

  /// A small, fixed bill the preview and the test print always show, so the
  /// admin sees the same slip while they tweak it.
  static const List<PrintJobItem> _sampleItems = [
    PrintJobItem(name: 'شیرینی بەرگەری', quantity: 2, category: 'برنج', price: 5000),
    PrintJobItem(name: 'چای', quantity: 3, category: 'خواردنەوە', price: 1000),
  ];
  static const double _sampleSubtotal = 13000;
  static const double _sampleDiscount = 2000;
  static const double _sampleTotal = 11000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final design = await ref.read(localDbProvider).getReceiptDesign();
    if (!mounted) return;
    _apply(design);
    setState(() => _loading = false);
  }

  /// Puts a design into state and refreshes the text fields that mirror it.
  void _apply(ReceiptDesign design) {
    _design = design;
    _shopCtrl.text = design.shopName;
    _titleCtrl.text = design.headerTitle;
    _footerCtrl.text = design.footerText;
  }

  @override
  void dispose() {
    _shopCtrl.dispose();
    _titleCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  void _set(ReceiptDesign design) => setState(() => _design = design);

  Future<void> _save() async {
    await ref.read(localDbProvider).setReceiptDesign(_design);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('دیزاینەکە پاشەکەوت کرا')),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _testPrint() async {
    if (_printing) return;
    final cashierPrinter = ref
        .read(printerProvider)
        .printers
        .where((p) => p.printerType == PrinterType.cashier)
        .firstOrNull;
    final messenger = ScaffoldMessenger.of(context);
    if (cashierPrinter == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr('هیچ پرێنتەرێکی کاشێر ڕێک نەخراوە')),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _printing = true);
    try {
      final ok = await PrintRouter.dispatchReceipt(
        tableNumber: 1,
        guestCount: 2,
        items: _sampleItems
            .map(
              (i) => OrderItem(
                id: '',
                name: i.name,
                quantity: i.quantity,
                category: i.category,
                price: i.price,
              ),
            )
            .toList(),
        subtotal: _sampleSubtotal,
        discountPercent: 15,
        discountAmount: _sampleDiscount,
        total: _sampleTotal,
        printer: cashierPrinter,
        cashierName: 'Test',
        seatedAt: DateTime.now().toIso8601String(),
        tableLabel: 'مێز 1',
        design: _design,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok ? context.tr('چاپکرا') : context.tr('نەتوانرا چاپ بکرێت'),
          ),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr('نەتوانرا چاپ بکرێت')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 740;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(context.tr('دیزاینی پرێنت')),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_rounded, color: Colors.white),
            label: Text(
              context.tr('پاشەکەوتکردن'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isPhone
          ? ListView(
              padding: const EdgeInsets.all(12),
              children: [_preview(), const SizedBox(height: 12), ..._controls()],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: ListView(children: _controls())),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: Container(
                    color: AppColors.background,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(child: _preview()),
                  ),
                ),
              ],
            ),
    );
  }

  // ==================== Controls ====================

  List<Widget> _controls() {
    return [
      _section(context.tr('تایبەتمەندییەکان')),
      _textField(
        context.tr('ناوی دوکان'),
        _shopCtrl,
        (v) => _set(_design.copyWith(shopName: v)),
      ),
      _switchRow(
        context.tr('پیشاندانی ناوی دوکان'),
        _design.showShopName,
        (v) => _set(_design.copyWith(showShopName: v)),
      ),
      _textField(
        context.tr('ناونیشانی وەسڵ'),
        _titleCtrl,
        (v) => _set(_design.copyWith(headerTitle: v)),
      ),
      _switchRow(
        context.tr('پیشاندانی ناونیشان'),
        _design.showHeaderTitle,
        (v) => _set(_design.copyWith(showHeaderTitle: v)),
      ),

      _section(context.tr('زانیاری')),
      _switchRow(
        context.tr('مێز'),
        _design.showTable,
        (v) => _set(_design.copyWith(showTable: v)),
      ),
      _switchRow(
        context.tr('ژمارەی میوان'),
        _design.showGuestCount,
        (v) => _set(_design.copyWith(showGuestCount: v)),
      ),
      _switchRow(
        context.tr('کاتی دانیشتن'),
        _design.showSeatedAt,
        (v) => _set(_design.copyWith(showSeatedAt: v)),
      ),
      _switchRow(
        context.tr('کاتی ڕۆیشتن'),
        _design.showLeaveTime,
        (v) => _set(_design.copyWith(showLeaveTime: v)),
      ),
      _switchRow(
        context.tr('بەروار'),
        _design.showDate,
        (v) => _set(_design.copyWith(showDate: v)),
      ),
      _switchRow(
        context.tr('کاپتن'),
        _design.showWaiter,
        (v) => _set(_design.copyWith(showWaiter: v)),
      ),
      _switchRow(
        context.tr('کاشێر'),
        _design.showCashier,
        (v) => _set(_design.copyWith(showCashier: v)),
      ),

      _section(context.tr('خواردن و پارە')),
      _switchRow(
        context.tr('خواردنەکان'),
        _design.showItems,
        (v) => _set(_design.copyWith(showItems: v)),
      ),
      _switchRow(
        context.tr('کۆی یەکەم'),
        _design.showSubtotal,
        (v) => _set(_design.copyWith(showSubtotal: v)),
      ),
      _switchRow(
        context.tr('داشکاندن'),
        _design.showDiscount,
        (v) => _set(_design.copyWith(showDiscount: v)),
      ),
      _switchRow(
        context.tr('کۆی گشتی'),
        _design.showTotal,
        (v) => _set(_design.copyWith(showTotal: v)),
      ),
      _switchRow(
        context.tr('کۆی گشتی گەورە'),
        _design.bigTotal,
        (v) => _set(_design.copyWith(bigTotal: v)),
      ),

      _section(context.tr('ڕێکخستن')),
      _choiceRow(
        context.tr('جۆری هێڵ'),
        _design.separatorStyle,
        const [
          ('dash', 'هێڵی داشە'),
          ('equals', 'هێڵی دووانە'),
          ('dots', 'خاڵ'),
        ],
        (v) => _set(_design.copyWith(separatorStyle: v)),
      ),
      _choiceRow(
        context.tr('پانی کاغەز'),
        '${_design.paperWidth}',
        const [('32', '32 (58mm)'), ('40', '40'), ('48', '48 (80mm)')],
        (v) => _set(_design.copyWith(paperWidth: int.parse(v))),
      ),
      _sliderRow(
        context.tr('هێڵی سپی پێش بڕین'),
        _design.feedBeforeCut,
        0,
        10,
        (v) => _set(_design.copyWith(feedBeforeCut: v)),
      ),

      _section(context.tr('دەقی خوارەوە')),
      _switchRow(
        context.tr('پیشاندانی دەقی خوارەوە'),
        _design.showFooter,
        (v) => _set(_design.copyWith(showFooter: v)),
      ),
      _textField(
        context.tr('دەقی خوارەوە'),
        _footerCtrl,
        (v) => _set(_design.copyWith(footerText: v)),
        maxLines: 3,
      ),

      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _printing ? null : _testPrint,
              icon: _printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_rounded),
              label: Text(context.tr('چاپی تاقیکردنەوە')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _loading
            ? null
            : () => setState(() => _apply(ReceiptDesign.standard)),
        icon: const Icon(Icons.restart_alt_rounded),
        label: Text(context.tr('گەڕاندنەوە بۆ ڕەسەن')),
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: AppColors.primary,
      ),
    ),
  );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      activeThumbColor: AppColors.primary,
      onChanged: onChanged,
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _choiceRow(
    String label,
    String value,
    List<(String, String)> options,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Wrap(
            spacing: 6,
            children: options
                .map(
                  (o) => ChoiceChip(
                    label: Text(context.tr(o.$2)),
                    selected: value == o.$1,
                    onSelected: (_) => onChanged(o.$1),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value',
              activeColor: AppColors.primary,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text('$value', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  // ==================== Preview ====================

  Widget _preview() {
    final lines = EscPosBuilder.receiptLayout(
      tableNumber: 1,
      guestCount: 2,
      items: _sampleItems,
      subtotal: _sampleSubtotal,
      discountPercent: 15,
      discountAmount: _sampleDiscount,
      total: _sampleTotal,
      waiterName: 'کاپتن',
      cashierName: 'کاشێر',
      seatedAt: DateTime.now().toIso8601String(),
      tableLabel: 'مێز 1',
      design: _design,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              context.tr('پیشبینین'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.darkText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderSide),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: lines
                .map(
                  (line) => Text(
                    line.text,
                    textAlign: line.center ? TextAlign.center : TextAlign.left,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: line.big ? 17 : (line.tall ? 15 : 11.5),
                      fontWeight: line.bold
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: AppColors.darkText,
                      height: 1.35,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
