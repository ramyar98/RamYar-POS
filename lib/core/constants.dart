import 'package:flutter/material.dart';

class AppConstants {
  // پادینگەکان بەپێی ستانداردی دیزاینەکەت
  static const double paddingXS = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXL = 32.0;

  // چەماوانەی کارت و دوگمەکان (Border Radius)
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXL = 24.0;
  static const double radiusXXL = 28.0;

  // ئەنیمەیشنەکان بۆ ئەوەی زۆر نەرم و خێرا بن
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 250);

  // سێبەرەکان بە ڕەنگی نەرم بەپێی دیزاینەکە
  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: const Color(0xFF1E252B).withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  // ناونیشانی فۆڵدەرەکان
  static const String imagePath = 'assets/images/';
}
