import 'package:flutter/services.dart';

import '../core/digits.dart';

/// Text input for a whole-dinar amount: it only ever holds digits and comma
/// thousands separators, and it re-formats on every keystroke so the field
/// reads the way the shop writes money - "5,000", "125,000".
///
/// "5000", "5,000" and localized digit forms (Arabic-Indic, Persian,
/// fullwidth) all land as "5,000"; letters and symbols are dropped. The caret
/// is kept where the user is editing, accounting for the separators that get
/// inserted in front of it.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({this.maxValue});

  /// Optional ceiling applied after formatting - e.g. a dinar discount can
  /// never exceed the bill it is taken from. null means no limit.
  final int? maxValue;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = toLatinDigits(newValue.text).replaceAll(
      RegExp('[^0-9]'),
      '',
    );
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    // "007" is 7; a lone "0" stays "0".
    final trimmed = digits.length > 1
        ? digits.replaceFirst(RegExp('^0+'), '')
        : digits;
    var number = trimmed.isEmpty ? '0' : trimmed;
    final max = maxValue;
    if (max != null && (int.tryParse(number) ?? 0) > max) {
      number = '$max';
    }
    final formatted = _groupDigits(number);
    final caret = _caretAfterDigits(
      formatted,
      _digitCountBefore(newValue, newValue.selection.baseOffset),
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// "5000" -> "5,000", "1200000" -> "1,200,000".
  static String _groupDigits(String digits) {
    final sb = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      sb.write(digits[i]);
      final remaining = digits.length - 1 - i;
      if (remaining > 0 && remaining % 3 == 0) sb.write(',');
    }
    return sb.toString();
  }

  /// How many actual digits sit before [offset] in [value], so the caret can
  /// be mapped onto the comma-grouped result.
  static int _digitCountBefore(TextEditingValue value, int offset) {
    final end = offset < 0
        ? 0
        : offset > value.text.length
        ? value.text.length
        : offset;
    var count = 0;
    for (var i = 0; i < end; i++) {
      final ch = toLatinDigits(value.text[i]);
      if (ch.length == 1 &&
          ch.codeUnitAt(0) >= 0x30 &&
          ch.codeUnitAt(0) <= 0x39) {
        count++;
      }
    }
    return count;
  }

  /// The character offset in [formatted] right after [digitCount] digits, i.e.
  /// the "5|00" spot in "5,000" when the user is editing behind the first
  /// digit.
  static int _caretAfterDigits(String formatted, int digitCount) {
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (seen == digitCount) return i;
      if (formatted[i] != ',') seen++;
    }
    return formatted.length;
  }
}