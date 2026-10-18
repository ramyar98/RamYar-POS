import '../core/language.dart';

class FoodLocalization {
  static String localizedName(Map<String, dynamic> itemOrCategory, AppLanguage lang) {
    final name = itemOrCategory['name'] as String? ?? '';
    switch (lang) {
      case AppLanguage.arabic:
        return (itemOrCategory['name_ar'] as String? ?? '').isNotEmpty
            ? itemOrCategory['name_ar'] as String
            : name;
      case AppLanguage.persian:
        return (itemOrCategory['name_fa'] as String? ?? '').isNotEmpty
            ? itemOrCategory['name_fa'] as String
            : name;
      case AppLanguage.english:
        return (itemOrCategory['name_en'] as String? ?? '').isNotEmpty
            ? itemOrCategory['name_en'] as String
            : name;
      case AppLanguage.turkish:
        return (itemOrCategory['name_tr'] as String? ?? '').isNotEmpty
            ? itemOrCategory['name_tr'] as String
            : name;
      case AppLanguage.kurdish:
      case AppLanguage.badini:
        // Badini is served in the shared Kurdish script (same as Sorani), so
        // the Kurdish food name is used as-is. DB rows may add a dedicated
        // `name_bd` column in a future release.
        return name;
    }
  }
}
