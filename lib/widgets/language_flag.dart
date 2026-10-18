import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/language.dart';

/// Flag colors (approximate official values).
const _kurdRed = Color(0xFFE62129);
const _kurdGreen = Color(0xFF2E8B57);
const _kurdYellow = Color(0xFFFCD116);
const _iraqGreen = Color(0xFF007A3D);
const _iranGreen = Color(0xFF239F40);
const _iranRed = Color(0xFFDA0000);
const _usaRed = Color(0xFFB22234);
const _usaBlue = Color(0xFF3C3B6E);
const _turkeyRed = Color(0xFFE30A17);

/// A small rounded flag icon for an app language.
///
/// Flags are drawn with [CustomPaint] so no binary assets are needed and they
/// stay crisp on any device (280px phones up to 1920px desktops). The default
/// size follows the classic 3:2 flag ratio.
class FlagIcon extends StatelessWidget {
  final AppLanguage language;
  final double width;

  const FlagIcon({super.key, required this.language, this.width = 22});

  @override
  Widget build(BuildContext context) {
    final height = width * 2 / 3;
    final painter = _FlagPainter(language, width, height);
    if (language == AppLanguage.arabic) {
      // Official Flag of Iraq (2008–present): red/white/black tricolor with the
      // green Kufic takbeer "الله اكبر" centred on the white band. The text is
      // stretched (FittedBox) so it spans the band like the real calligraphy
      // instead of a tiny unreadable blob.
      return ClipRRect(
        borderRadius: BorderRadius.circular(2.5),
        child: Stack(
          children: [
            CustomPaint(size: Size(width, height), painter: painter),
            Positioned(
              left: width * 0.06,
              right: width * 0.06,
              top: height / 3,
              height: height / 3,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    'الله اكبر',
                    maxLines: 1,
                    style: TextStyle(
                      color: _iraqGreen,
                      fontSize: height * 0.5,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(2.5),
      child: CustomPaint(size: Size(width, height), painter: painter),
    );
  }
}

class _FlagPainter extends CustomPainter {
  final AppLanguage language;
  final double w;
  final double h;

  _FlagPainter(this.language, this.w, this.h);

  @override
  void paint(Canvas canvas, Size size) {
    switch (language) {
      case AppLanguage.kurdish:
      case AppLanguage.badini:
        _paintKurdistan(canvas);
      case AppLanguage.arabic:
        _paintTricolor(canvas, const [_kurdRed, Colors.white, Color(0xFF1D1D1B)]);
      case AppLanguage.persian:
        _paintIran(canvas);
      case AppLanguage.english:
        _paintUsa(canvas);
      case AppLanguage.turkish:
        _paintTurkey(canvas);
    }
  }

  Rect get _full => Rect.fromLTWH(0, 0, w, h);

  void _paintKurdistan(Canvas canvas) {
    // Horizontal stripes: red / white / green.
    final stripe = h / 3;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, stripe), Paint()..color = _kurdRed);
    canvas.drawRect(Rect.fromLTWH(0, stripe, w, stripe), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(0, stripe * 2, w, stripe), Paint()..color = _kurdGreen);

    // Yellow sun: inner disc + 21 rays.
    final center = Offset(w / 2, h / 2);
    final rInner = h * 0.13;
    final rOuter = h * 0.235;
    final ray = Paint()
      ..color = _kurdYellow
      ..strokeWidth = h * 0.07
      ..strokeCap = StrokeCap.round;
    const rays = 21;
    for (var i = 0; i < rays; i++) {
      final a = -math.pi / 2 + (i * 2 * math.pi) / rays;
      final a0 = Offset(center.dx + rInner * math.cos(a), center.dy + rInner * math.sin(a));
      final a1 = Offset(center.dx + rOuter * math.cos(a), center.dy + rOuter * math.sin(a));
      canvas.drawLine(a0, a1, ray);
    }
    canvas.drawCircle(center, rInner, Paint()..color = _kurdYellow);
  }

  void _paintTricolor(Canvas canvas, List<Color> colors) {
    final stripe = h / 3;
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, stripe * i, w, stripe),
        Paint()..color = colors[i],
      );
    }
  }

  void _paintIran(Canvas canvas) {
    _paintTricolor(canvas, const [_iranGreen, Colors.white, _iranRed]);
    // Simplified red tulip emblem centred on the white band.
    final paint = Paint()..color = _iranRed;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.30)
      ..quadraticBezierTo(w * 0.80, h * 0.42, w * 0.62, h * 0.60)
      ..quadraticBezierTo(w * 0.50, h * 0.74, w * 0.38, h * 0.60)
      ..quadraticBezierTo(w * 0.20, h * 0.42, w * 0.50, h * 0.30)
      ..close();
    canvas.drawPath(path, paint);
    final stem = Paint()
      ..color = _iranRed
      ..strokeWidth = math.max(1.2, h * 0.05)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.5, h * 0.62), Offset(w * 0.5, h * 0.78), stem);
    canvas.drawLine(Offset(w * 0.5, h * 0.66), Offset(w * 0.42, h * 0.80), stem);
    canvas.drawLine(Offset(w * 0.5, h * 0.66), Offset(w * 0.58, h * 0.80), stem);
  }

  void _paintUsa(Canvas canvas) {
    // 13 stripes: red / white alternating, starting and ending with red.
    final stripe = h / 13;
    for (var i = 0; i < 13; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, stripe * i, w, stripe),
        Paint()..color = i.isEven ? _usaRed : Colors.white,
      );
    }
    // Navy canton over the first 7 stripes, with a simplified star field.
    final cw = w * 0.40;
    final ch = stripe * 7;
    canvas.drawRect(Rect.fromLTWH(0, 0, cw, ch), Paint()..color = _usaBlue);
    final star = Paint()..color = Colors.white;
    const rowCounts = [3, 4, 3, 3]; // 13 stars
    for (var r = 0; r < rowCounts.length; r++) {
      final n = rowCounts[r];
      final y = ch * (r + 0.5) / rowCounts.length;
      for (var c = 0; c < n; c++) {
        final x = cw * (c + 1) / (n + 1);
        canvas.drawCircle(Offset(x, y), math.max(0.6, h * 0.03), star);
      }
    }
  }

  void _paintTurkey(Canvas canvas) {
    canvas.drawRect(_full, Paint()..color = _turkeyRed);
    final cy = h / 2;
    final r = h * 0.34;
    final cx = w * 0.42;
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.white);
    // Carve the crescent with an offset red disc.
    canvas.drawCircle(
      Offset(cx + w * 0.10, cy),
      r * 0.80,
      Paint()..color = _turkeyRed,
    );
    // White star to the right of the crescent.
    canvas.drawPath(_star(Offset(w * 0.62, cy), r * 0.42), Paint()..color = Colors.white);
  }

  Path _star(Offset center, double radius) {
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : radius * 0.42;
      final a = -math.pi / 2 + (i * math.pi) / points;
      final o = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) {
    return oldDelegate.language != language ||
        oldDelegate.w != w ||
        oldDelegate.h != h;
  }
}

/// Flag + language name in a single row (flag first in reading order).
///
/// Used by the language selectors (login, cashier welcome, cashier drawer,
/// waiter settings and the profile menu) so every choice shows its national
/// flag next to the language name.
class LanguageLabel extends StatelessWidget {
  final AppLanguage language;
  final TextStyle? textStyle;
  final double flagWidth;

  const LanguageLabel({
    super.key,
    required this.language,
    this.textStyle,
    this.flagWidth = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlagIcon(language: language, width: flagWidth),
        SizedBox(width: flagWidth >= 28 ? 8 : 6),
        Flexible(
          child: Text(
            LanguageHelper.getLanguageName(language),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}