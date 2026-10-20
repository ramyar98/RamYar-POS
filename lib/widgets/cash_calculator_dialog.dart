import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../core/fmt.dart';
import '../services/app_localizations.dart';
import 'amount_input_formatter.dart';

class CashCalculatorResult {
  final double cashReceived;
  final double changeDue;
  final bool confirmed;

  const CashCalculatorResult({
    required this.cashReceived,
    required this.changeDue,
    required this.confirmed,
  });
}

class CashCalculatorDialog extends StatefulWidget {
  final double totalDue;
  final String tableName;
  final String currency;

  const CashCalculatorDialog({
    super.key,
    required this.totalDue,
    required this.tableName,
    this.currency = 'IQD',
  });

  static Future<CashCalculatorResult?> show(
    BuildContext context, {
    required double totalDue,
    required String tableName,
    String currency = 'IQD',
  }) {
    return showDialog<CashCalculatorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CashCalculatorDialog(
        totalDue: totalDue,
        tableName: tableName,
        currency: currency,
      ),
    );
  }

  @override
  State<CashCalculatorDialog> createState() => _CashCalculatorDialogState();
}

class _CashCalculatorDialogState extends State<CashCalculatorDialog> {
  final _cashController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _cashController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double get _cashReceived => parseAmount(_cashController.text).toDouble();
  double get _changeDue => _cashReceived - widget.totalDue;
  bool get _sufficientFunds => _cashReceived >= widget.totalDue;

  void _quickAmount(int amount) {
    _cashController.text = money(amount);
    setState(() {});
  }

  void _confirm() {
    if (!_sufficientFunds) return;
    Navigator.of(context).pop(
      CashCalculatorResult(
        cashReceived: _cashReceived,
        changeDue: _changeDue,
        confirmed: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final totalInt = widget.totalDue.toInt();
    final cashInt = _cashReceived.toInt();
    final changeInt = _changeDue.toInt();
    final isExact = _cashReceived > 0 && _cashReceived == widget.totalDue;
    final needsChange = _cashReceived > widget.totalDue;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 40 : 16,
        vertical: isLandscape ? 8 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SafeArea(
          bottom: keyboardHeight > 0,
          child: Material(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20 + keyboardHeight,
              ),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.monetization_on_rounded,
                            color: AppColors.success,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('واسڵ کردنی پارە'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.darkText,
                                ),
                              ),
                              Text(
                                widget.tableName,
                                style: const TextStyle(
                                  color: AppColors.softText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('داخستن'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            tr('بڕی حیساب'),
                            style: const TextStyle(
                              color: AppColors.softText,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${money(totalInt)} ${widget.currency}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _cashController,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [AmountInputFormatter()],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkText,
                      ),
                      decoration: InputDecoration(
                        hintText: tr('بڕی پارەی وەرگیراو'),
                        hintStyle: TextStyle(
                          color: AppColors.softText.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        prefixText: '${widget.currency} ',
                        prefixStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.softText,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _confirm(),
                    ),
                    if (_cashReceived > 0) ...[
                      const SizedBox(height: 12),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: needsChange
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : isExact
                              ? AppColors.success.withValues(alpha: 0.08)
                              : AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: needsChange
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : isExact
                                ? AppColors.success.withValues(alpha: 0.2)
                                : AppColors.danger.withValues(alpha: 0.2),
                          ),
                        ),
                        child: needsChange
                            ? Row(
                                children: [
                                  const Icon(
                                    Icons.trending_up_rounded,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr('بڕی پارەی پێدراو'),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.softText,
                                          ),
                                        ),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '${money(cashInt)} ${widget.currency}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.darkText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        tr('بڕی باقی'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.softText,
                                        ),
                                      ),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '+ ${money(changeInt)} ${widget.currency}',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : isExact
                            ? Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppColors.success,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    tr('بڕی حیساب ڕێکە'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppColors.danger,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      tr('بڕی پارەکە کەمترە لە حیساب'),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (needsChange) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  '${tr('بڕی پێویستە بگەڕێتەوە بۆ موشتەری')}: ',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.darkText,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${money(changeInt)} ${widget.currency}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        // The exact bill always leads the suggestions, so the
                        // cashier never has to type it by hand - whatever the
                        // table costs, that same figure is one tap away. The
                        // regular denominations follow, minus any duplicate.
                        for (final amount in <int>{
                          if (totalInt > 0) totalInt,
                          1000,
                          5000,
                          10000,
                          25000,
                          50000,
                          100000,
                        })
                          _quickChip(amount, isExactAmount: amount == totalInt),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(
                                tr('ڕەتکردنەوە'),
                                style: const TextStyle(fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.softText,
                                side: const BorderSide(
                                  color: AppColors.borderSide,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _sufficientFunds ? _confirm : null,
                              icon: const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _sufficientFunds
                                    ? tr('واسڵ کردن')
                                    : tr('بڕی پارە تەواو نیە'),
                                style: const TextStyle(fontSize: 13),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.success,
                                disabledBackgroundColor: AppColors.borderSide,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickChip(int amount, {bool isExactAmount = false}) {
    final isSelected = _cashReceived == amount;
    // The exact-bill chip is drawn in success green so it reads as "the
    // amount to settle", not just another denomination.
    final accent = isExactAmount ? AppColors.success : AppColors.primary;
    final emphasized = isExactAmount || isSelected;
    return Material(
      color: emphasized ? accent.withValues(alpha: 0.1) : AppColors.background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _quickAmount(amount),
        child: Container(
          // 40px tall so the chip is a comfortable touch target; the old 8px
          // vertical padding gave ~34px.
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: emphasized ? accent : AppColors.borderSide,
              width: emphasized ? 1.5 : 1,
            ),
          ),
          child: Text(
            money(amount),
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.bold : FontWeight.normal,
              color: emphasized ? accent : AppColors.darkText,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
