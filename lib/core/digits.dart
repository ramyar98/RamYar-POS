/// Guarantees every on-screen number is displayed with Latin (0-9) digits,
/// no matter which of the 5 app languages is active or what the OS keyboard
/// layout looks like.
///
/// Kurdish, Arabic, Persian, Turkish and English source strings in this app
/// never contain localized digits, but text typed with an Arabic/Persian
/// keyboard layout can carry Arabic-Indic (٠-٩), Persian (۰-۹) or fullwidth
/// (０-９) forms. [toLatinDigits] normalizes all of them back to the ASCII
/// forms used everywhere in RAMYAR POS so totals, PINs and IPs stay readable.
library;

/// Maps Arabic-Indic (٠-٩), Persian/Extended (۰-۹) and fullwidth (０-۹) digits
/// to ASCII 0-9. Every other character passes through unchanged.
String toLatinDigits(String input) {
  if (input.isEmpty) return input;
  final sb = StringBuffer();
  for (final c in input.codeUnits) {
    sb.writeCharCode(_latinDigitOf(c));
  }
  return sb.toString();
}

int _latinDigitOf(int c) {
  // Arabic-Indic digits ٠١٢٣٤٥٦٧٨٩ (U+0660..U+0669).
  if (c >= 0x0660 && c <= 0x0669) return c - 0x0660 + 0x30;
  // Persian / Extended Arabic-Indic digits ۰۱۲۳۴۵۶۷۸۹ (U+06F0..U+06F9).
  if (c >= 0x06F0 && c <= 0x06F9) return c - 0x06F0 + 0x30;
  // Fullwidth digits ０１２３４５６７８９ (U+FF10..U+FF19).
  if (c >= 0xFF10 && c <= 0xFF19) return c - 0xFF10 + 0x30;
  return c;
}