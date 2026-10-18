import 'dart:convert';
import '../models/printer_model.dart';
import '../models/receipt_design_model.dart';

/// One line of a receipt, before it is turned into ESC/POS bytes.
///
/// The same list drives the printed receipt and the on-screen design preview, so
/// what the admin sees on the design screen is exactly what the till prints.
class ReceiptLine {
  final String text;
  final bool center;
  final bool bold;

  /// Double width and height (the shop's name).
  final bool big;

  /// Double height only (the receipt title and the grand total).
  final bool tall;

  const ReceiptLine(
    this.text, {
    this.center = false,
    this.bold = false,
    this.big = false,
    this.tall = false,
  });
}

class EscPosBuilder {
  static const _esc = 0x1B;
  static const _lf = 0x0A;
  static const _lineW = 40;

  static List<int> _bytes(List<int> data) => data;
  static List<int> _text(String s) => utf8.encode(s);
  static List<int> _cmd(int a, [int? b, int? c]) =>
      b == null ? [_esc, a] : c == null ? [_esc, a, b] : [_esc, a, b, c];

  static List<int> _init() => _cmd(0x40);
  static List<int> _alignC() => _cmd(0x61, 1);
  static List<int> _alignL() => _cmd(0x61, 0);
  static List<int> _bold(bool on) => on ? _cmd(0x45, 1) : _cmd(0x45, 0);
  static List<int> _dh() => _cmd(0x21, 0x10);
  static List<int> _dBoth() => _cmd(0x21, 0x30);
  static List<int> _normal() => _cmd(0x21, 0x00);
  static List<int> _cut() => _bytes([0x1D, 0x56, 0x42]);
  static List<int> _feed(int n) => n > 0 ? List.filled(n, _lf) : [];
  static List<int> _enc() => _bytes([_esc, 0x74, 0xFF]);

  static List<int> buildDrawerKick() => [27, 112, 0, 25, 250];

  static String _padL(String s, int w) => s.length >= w ? s : s + ' ' * (w - s.length);
  static String _padR(String s, int w) => s.length >= w ? s : ' ' * (w - s.length) + s;
  static String _padC(String s, int w) {
    final p = ((w - s.length) / 2).floor();
    return ' ' * p + s + ' ' * (w - s.length - p);
  }

  static String _lr(String l, String r, [int? w]) {
    final width = w ?? _lineW;
    final need = width - l.length - r.length;
    return need > 0 ? '$l${' ' * need}$r' : '$l $r';
  }

  static String _dash([int? w]) => '─' * (w ?? _lineW);
  static String _eq([int? w]) => '═' * (w ?? _lineW);
  static String _dot([int? w]) => '·' * (w ?? _lineW);

  static String _fmtP(double p) {
    final n = p.toInt().abs();
    final s = n.toString();
    final len = s.length;
    if (len <= 3) return s;
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(s[i]);
      final remaining = len - 1 - i;
      if (remaining > 0 && remaining % 3 == 0) sb.write(',');
    }
    return sb.toString();
  }

  static String _typeTitle(PrinterType t) {
    switch (t) {
      case PrinterType.kitchen: return 'داواکاری مەتبەخ';
      case PrinterType.bar: return 'داواکاری باڕ';
      case PrinterType.hookah: return 'داواکاری نێرگیلە';
      case PrinterType.cashier: return '';
    }
  }

  static String _fmtTime(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) {
      if (iso.contains('T')) return iso.split('T').last.length >= 5 ? iso.split('T').last.substring(0, 5) : iso;
      return iso.length >= 5 ? iso.substring(0, 5) : iso;
    }
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static List<int> _header(List<int> buf) {
    buf.addAll(_init());
    buf.addAll(_enc());
    buf.addAll(_feed(2));
    buf.addAll(_alignC());
    buf.addAll(_dBoth());
    buf.addAll(_bold(true));
    buf.addAll(_text(_padC('B I A B L O', _lineW)));
    buf.addAll(_bytes([_lf]));
    buf.addAll(_normal());
    buf.addAll(_bold(false));
    buf.addAll(_feed(1));
    return buf;
  }

  static List<int> _footer(List<int> buf) {
    buf.addAll(_alignC());
    buf.addAll(_feed(2));
    buf.addAll(_text(_eq()));
    buf.addAll(_bytes([_lf]));
    buf.addAll(_bold(false));
    buf.addAll(_normal());
    buf.addAll(_feed(4));
    buf.addAll(_cut());
    return buf;
  }

  static List<int> buildKitchenTicket(PrintJob job) {
    final buf = <int>[];
    _header(buf);
    buf.addAll(_alignC());
    buf.addAll(_bold(true));
    buf.addAll(_dh());
    buf.addAll(_text(_padC(_typeTitle(job.printerType), _lineW)));
    buf.addAll(_bytes([_lf]));
    buf.addAll(_normal());
    buf.addAll(_bold(false));
    buf.addAll(_feed(1));
    buf.addAll(_text(_dash()));
    buf.addAll(_bytes([_lf]));

    final first = job.items.first;
    buf.addAll(_alignL());
    buf.addAll(_feed(1));
    buf.addAll(_bold(true));
    buf.addAll(_text(_lr(
        first.tableLabel.isNotEmpty
            ? first.tableLabel
            : 'مێز: ${first.tableNumber}',
        'کاپتن: ${first.waiterName}',
    )));
    buf.addAll(_bytes([_lf]));
    buf.addAll(_bold(false));
    buf.addAll(_text(_lr(_fmtTime(DateTime.now().toIso8601String()), '')));
    buf.addAll(_bytes([_lf]));
    buf.addAll(_feed(1));
    buf.addAll(_text(_dash()));
    buf.addAll(_bytes([_lf]));
    buf.addAll(_feed(1));

    for (final item in job.items) {
      buf.addAll(_bold(true));
      buf.addAll(_text('  ${item.name}'));
      buf.addAll(_bold(false));
      buf.addAll(_text(_padR('x${item.quantity}', 6)));
      buf.addAll(_bytes([_lf]));
      if (item.notes.isNotEmpty) {
        buf.addAll(_text('    ${item.notes}'));
        buf.addAll(_bytes([_lf]));
      }
    }

    buf.addAll(_feed(1));
    buf.addAll(_text(_dash()));
    buf.addAll(_bytes([_lf]));
    buf.addAll(_alignC());
    buf.addAll(_bold(true));
    buf.addAll(_text(_padC('کۆی خواردنەکان: ${job.items.length}', _lineW)));
    buf.addAll(_bold(false));
    buf.addAll(_bytes([_lf]));
    _footer(buf);
    return buf;
  }

  /// The receipt as a list of lines, honouring every option in [design].
  ///
  /// Kept separate from the byte encoding so the design screen can show the
  /// exact same lines as a preview. [buildCashierReceipt] renders this to
  /// ESC/POS; the admin's «دیزاینی پرێنت» page renders it to the screen.
  static List<ReceiptLine> receiptLayout({
    required int tableNumber,
    required int guestCount,
    required List<PrintJobItem> items,
    required double subtotal,
    required double discountPercent,
    required double discountAmount,
    required double total,
    String waiterName = '',
    String cashierName = '',
    String seatedAt = '',
    String tableLabel = '',
    ReceiptDesign design = ReceiptDesign.standard,
  }) {
    final w = design.paperWidth;
    final out = <ReceiptLine>[];

    String sep() {
      switch (design.separatorStyle) {
        case 'equals':
          return _eq(w);
        case 'dots':
          return _dot(w);
        default:
          return _dash(w);
      }
    }

    if (design.showShopName && design.shopName.trim().isNotEmpty) {
      out.add(
        ReceiptLine(
          _padC(design.shopName.trim(), w),
          center: true,
          bold: true,
          big: true,
        ),
      );
    }
    if (design.showHeaderTitle && design.headerTitle.trim().isNotEmpty) {
      out.add(
        ReceiptLine(
          _padC(design.headerTitle.trim(), w),
          center: true,
          bold: true,
          tall: true,
        ),
      );
    }
    out.add(ReceiptLine(sep()));

    // A delivery slot's number is internal, so the receipt names it instead.
    final tableText = tableLabel.isNotEmpty ? tableLabel : 'مێز: $tableNumber';
    if (design.showTable && design.showGuestCount) {
      out.add(ReceiptLine(_lr(tableText, 'میوان: $guestCount', w), bold: true));
    } else if (design.showTable) {
      out.add(ReceiptLine(tableText, bold: true));
    } else if (design.showGuestCount) {
      out.add(ReceiptLine('میوان: $guestCount', bold: true));
    }
    if (design.showSeatedAt && seatedAt.isNotEmpty) {
      out.add(ReceiptLine('کاتی دانیشتن: ${_fmtTime(seatedAt)}'));
    }
    if (design.showLeaveTime) {
      out.add(
        ReceiptLine('کاتی ڕۆیشتن: ${_fmtTime(DateTime.now().toIso8601String())}'),
      );
    }
    if (design.showDate) {
      final now = DateTime.now();
      out.add(
        ReceiptLine(
          'بەروار: ${now.year}/${now.month.toString().padLeft(2, '0')}/'
          '${now.day.toString().padLeft(2, '0')}',
        ),
      );
    }
    if (design.showWaiter && waiterName.isNotEmpty) {
      out.add(ReceiptLine('کاپتن: $waiterName'));
    }
    if (design.showCashier && cashierName.isNotEmpty) {
      out.add(ReceiptLine('کاشێر: $cashierName'));
    }
    out.add(ReceiptLine(sep()));

    if (design.showItems) {
      out.add(ReceiptLine(_padC('خواردنەکان', w), center: true, bold: true));
      out.add(ReceiptLine(_dot(w)));
      for (final item in items) {
        final qty = 'x${item.quantity}';
        final price = _fmtP(item.price * item.quantity);
        final line = '  ${item.name}';
        final trailing = '${_padR(qty, 6)}  ${_padR(price, 8)}';
        final available = w - 2 - trailing.length;
        if (line.length <= available) {
          out.add(ReceiptLine(_padL(line, available) + trailing));
        } else {
          out.add(ReceiptLine(line));
          out.add(ReceiptLine(' ' * 2 + trailing));
        }
      }
      out.add(ReceiptLine(sep()));
    }

    if (design.showSubtotal) {
      out.add(ReceiptLine(_lr('کۆی یەکەم', _padR('${_fmtP(subtotal)} د.ع', 14), w)));
    }
    if (design.showDiscount && discountAmount > 0) {
      final pct = (discountPercent > 0 && discountPercent < 100)
          ? ' ($discountPercent%)'
          : '';
      out.add(ReceiptLine(_lr('داشکاندن$pct', _padR('-${_fmtP(discountAmount)} د.ع', 14), w)));
    }
    if (design.showTotal) {
      out.add(ReceiptLine(_eq(w)));
      out.add(
        ReceiptLine(
          _lr('کۆی گشتی', _padR('${_fmtP(total)} د.ع', 14), w),
          bold: true,
          tall: design.bigTotal,
        ),
      );
    }
    if (design.showFooter && design.footerText.trim().isNotEmpty) {
      for (final line in design.footerText.split('\n')) {
        out.add(ReceiptLine(_padC(line, w), center: true));
      }
      out.add(ReceiptLine(_eq(w), center: true));
    }
    return out;
  }

  /// The plain-text form of the receipt, for the design screen's live preview.
  static String buildCashierReceiptText({
    required int tableNumber,
    required int guestCount,
    required List<PrintJobItem> items,
    required double subtotal,
    required double discountPercent,
    required double discountAmount,
    required double total,
    String waiterName = '',
    String cashierName = '',
    String seatedAt = '',
    String tableLabel = '',
    ReceiptDesign design = ReceiptDesign.standard,
  }) {
    return receiptLayout(
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
      tableLabel: tableLabel,
      design: design,
    ).map((l) => l.text).join('\n');
  }

  static List<int> buildCashierReceipt({
    required int tableNumber,
    required int guestCount,
    required List<PrintJobItem> items,
    required double subtotal,
    required double discountPercent,
    required double discountAmount,
    required double total,
    String waiterName = '',
    String cashierName = '',
    String seatedAt = '',
    String tableLabel = '',
    ReceiptDesign design = ReceiptDesign.standard,
  }) {
    final layout = receiptLayout(
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
      tableLabel: tableLabel,
      design: design,
    );

    final buf = <int>[];
    buf.addAll(_init());
    buf.addAll(_enc());
    buf.addAll(_feed(2));
    for (final line in layout) {
      buf.addAll(line.center ? _alignC() : _alignL());
      buf.addAll(line.big ? _dBoth() : (line.tall ? _dh() : _normal()));
      buf.addAll(_bold(line.bold));
      buf.addAll(_text(line.text));
      buf.addAll(_bytes([_lf]));
    }
    buf.addAll(_normal());
    buf.addAll(_bold(false));
    buf.addAll(_feed(design.feedBeforeCut));
    buf.addAll(_cut());
    return buf;
  }
}
