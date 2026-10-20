import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../core/digits.dart';
import '../core/fmt.dart';
import '../services/app_localizations.dart';
import 'amount_input_formatter.dart';

class CloseShiftResult {
  final double collected;
  const CloseShiftResult(this.collected);
}

class CloseShiftDialog extends StatefulWidget {
  final String startedAt;
  final double shiftExpenses;

  const CloseShiftDialog({
    super.key,
    required this.startedAt,
    required this.shiftExpenses,
  });

  @override
  State<CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<CloseShiftDialog> {
  final _collectedCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _collectedCtrl.dispose();
    super.dispose();
  }

  bool _closing = false;

  double _parseCollected(String text) {
    // One normaliser for every digit form (Arabic-Indic, Persian, fullwidth) -
    // the hand-written ٠-٩ table here missed ۰-۹, so a Persian keyboard made
    // every amount invalid.
    final cleaned = toLatinDigits(text)
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('.', '');
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite || value < 0) {
      return -1;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final collected = _parseCollected(_collectedCtrl.text);
    final collectedValid = collected >= 0;
    final net = collectedValid ? collected - widget.shiftExpenses : 0;
    return AlertDialog(
      title: Text(context.tr('داخستنی شەفت')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.trp('شەفت دەستی پێکردووە لە {time}', {
                // Parsed, not sliced: `substring(11, 19)` throws a RangeError
                // on any stored value shorter than 19 chars.
                'time': _hhmm(widget.startedAt),
              }),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    context.tr('کۆی خەرجیەکان'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${context.tr('د.ع')} ${money(widget.shiftExpenses)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _collectedCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [AmountInputFormatter()],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: context.tr('کۆی پارەی کۆکراوە (د.ع)'),
                errorText: _error,
                errorMaxLines: 2,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (collectedValid && collected > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      context.tr('خاو (کۆکراوە - خەرجی)'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${context.tr('د.ع')} ${money(net)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: net >= 0 ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('ڕەتکردنەوە')),
        ),
        FilledButton(
          onPressed: () {
            if (_closing) return;
            final value = _parseCollected(_collectedCtrl.text);
            if (value < 0) {
              setState(
                () => _error = context.tr('بڕایەکی دروست بنووسە (ژمارە تەنیا)'),
              );
              return;
            }
            _closing = true;
            Navigator.pop(context, CloseShiftResult(value));
          },
          child: Text(context.tr('داخستن')),
        ),
      ],
    );
  }

  /// «08:34» for a stored ISO timestamp; the raw value when it cannot be parsed.
  String _hhmm(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
