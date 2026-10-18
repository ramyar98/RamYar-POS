import 'package:flutter/material.dart';

// پێناسەکردنی هەر ٦ زمانە داواکراوەکە
enum AppLanguage { kurdish, badini, arabic, persian, english, turkish }

class LanguageHelper {
  // وەرگرتنی ناوی زمانەکان بۆ پیشاندان لە ناو مینیوی ڕێکخستن یان لۆگین
  static String getLanguageName(AppLanguage language) {
    switch (language) {
      case AppLanguage.kurdish:
        return 'کوردی (سۆرانی)';
      case AppLanguage.badini:
        return 'کوردی (بادینی)';
      case AppLanguage.arabic:
        return 'العربية';
      case AppLanguage.persian:
        return 'فارسی';
      case AppLanguage.english:
        return 'English';
      case AppLanguage.turkish:
        return 'Türkçe';
    }
  }

  // دیاریکردنی ئاراستەی نووسین بەپێی زمانەکە (RTL یان LTR)
  static TextDirection getTextDirection(AppLanguage language) {
    switch (language) {
      case AppLanguage.kurdish:
      case AppLanguage.badini:
      case AppLanguage.arabic:
      case AppLanguage.persian:
        return TextDirection.rtl;
      case AppLanguage.english:
      case AppLanguage.turkish:
        return TextDirection.ltr;
    }
  }

  // دەستنیشانکردنی RTL یان LTL بۆ زمانەکان
  static bool isRtl(AppLanguage language) {
    return getTextDirection(language) == TextDirection.rtl;
  }

  // دروستکردنی لۆکاڵی فەرمی فلاتەر بۆ زمانەکان
  static Locale getLocale(AppLanguage language) {
    switch (language) {
      case AppLanguage.kurdish:
      case AppLanguage.badini:
        return const Locale('ku', 'IQ');
      case AppLanguage.arabic:
        return const Locale('ar', 'AE');
      case AppLanguage.persian:
        return const Locale('fa', 'IR');
      case AppLanguage.english:
        return const Locale('en', 'US');
      case AppLanguage.turkish:
        return const Locale('tr', 'TR');
    }
  }
}
