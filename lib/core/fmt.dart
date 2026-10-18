import 'digits.dart';

/// Whole-number money formatting with comma thousands separators.
///
/// Every bill, price and shift total shown in the app reads the way the shop
/// writes them on paper: 5000 -> "5,000", 1200000 -> "1,200,000". Negative
/// amounts keep their minus sign ("-5,000"), and anything under a thousand is
/// returned untouched.
String money(num value) {
  final digits = value.toInt().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final remaining = digits.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) buffer.write(',');
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// Parses a whole-dinar amount a cashier typed or pasted, the way fields like
/// the discount box and the cash calculator display it: comma thousands
/// separators ("5,000") and localized digit forms (Arabic-Indic, Persian,
/// fullwidth) are all reduced to a plain integer. Letters, symbols and empty
/// input are dropped to 0.
int parseAmount(String text) {
  final digits = toLatinDigits(text).replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.parse(digits);
}
