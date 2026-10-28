import 'package:flutter/material.dart';
import '../core/language.dart';
import '../core/app.dart';

extension AppLocalizations on BuildContext {
  AppLanguage _lang() {
    try {
      return AppState.of(this).currentLanguage;
    } catch (_) {
      return AppLanguage.kurdish;
    }
  }

  String tr(String key) {
    final lang = _lang();
    if (lang == AppLanguage.kurdish) return key;
    final map = _allTranslations[key];
    if (map == null) return key;
    return map[lang] ?? key;
  }

  String trp(String template, Map<String, String> params) {
    String result = tr(template);
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

/// The shop's word for a staff role, from a `UserRole` index
/// (0 = captain, 1 = cashier, 2 = admin, 3 = owner).
///
/// Shared so «کاپتن» / «کاشێر» read the same wherever a dish or a table is
/// labelled with the person who handled it. An index the app does not know -
/// an order line written before roles were recorded, or a role added later -
/// yields an empty string, and [staffLabel] then falls back to the bare name.
String staffRoleLabel(BuildContext context, int roleIndex) {
  switch (roleIndex) {
    case 0:
      return context.tr('کاپتن');
    case 1:
      return context.tr('کاشێر');
    case 2:
      return context.tr('ئادمێن');
    case 3:
      return context.tr('خاوەن سیستەم');
    default:
      return '';
  }
}

/// "کاپتن ئاراس" / "کاشێر شیلان" for an order line's adder, or the bare name
/// when the role is unknown.
String staffLabel(BuildContext context, int roleIndex, String name) {
  if (name.isEmpty) return '';
  final role = staffRoleLabel(context, roleIndex);
  return role.isEmpty ? name : '$role $name';
}

final Map<String, Map<AppLanguage, String>> _allTranslations = {
  // ===== App =====
  '30 ڕۆژ': {
    AppLanguage.badini: '30 ڕۆژ',
    AppLanguage.arabic: '30 يوماً',
    AppLanguage.persian: '30 روز',
    AppLanguage.english: '30 days',
    AppLanguage.turkish: '30 gün',
  },
  '7 ڕۆژ': {
    AppLanguage.badini: '7 ڕۆژ',
    AppLanguage.arabic: '7 أيام',
    AppLanguage.persian: '7 روز',
    AppLanguage.english: '7 days',
    AppLanguage.turkish: '7 gün',
  },

  // ===== Payment =====
  'IQD د.ع': {
    AppLanguage.badini: 'IQD د.ع',
    AppLanguage.arabic: 'IQD د.ع',
    AppLanguage.persian: 'IQD د.ع',
    AppLanguage.english: 'IQD',
    AppLanguage.turkish: 'IQD',
  },

  // ===== Menu / Food =====
  '{count} جۆر خواردن': {
    AppLanguage.badini: '{count} جۆر خوارن',
    AppLanguage.arabic: '{count} نوع طعام',
    AppLanguage.persian: '{count} نوع غذا',
    AppLanguage.english: '{count} food types',
    AppLanguage.turkish: '{count} yiyecek türü',
  },

  // ===== Cashier =====
  '{count} حیساب': {
    AppLanguage.badini: '{count} حیساب',
    AppLanguage.arabic: '{count} فاتورة',
    AppLanguage.persian: '{count} صورتحساب',
    AppLanguage.english: '{count} bills',
    AppLanguage.turkish: '{count} hesap',
  },
  '{count} ئاگەدارکردنەوە': {
    AppLanguage.badini: '{count} ئاگەدارکردنەوە',
    AppLanguage.arabic: '{count} إشعار',
    AppLanguage.persian: '{count} اعلان',
    AppLanguage.english: '{count} notifications',
    AppLanguage.turkish: '{count} bildirim',
  },

  // ===== Debt =====
  '{count} قەرز': {
    AppLanguage.badini: '{count} قەرز',
    AppLanguage.arabic: '{count} دين',
    AppLanguage.persian: '{count} بدهی',
    AppLanguage.english: '{count} debts',
    AppLanguage.turkish: '{count} borç',
  },

  // ===== App =====
  '{count} هەژمارە': {
    AppLanguage.badini: '{count} هەژمارە',
    AppLanguage.arabic: '{count} حساب',
    AppLanguage.persian: '{count} حساب',
    AppLanguage.english: '{count} accounts',
    AppLanguage.turkish: '{count} hesap',
  },

  // ===== Printers =====
  '{count} پرینتەر': {
    AppLanguage.badini: '{count} پرینتەر',
    AppLanguage.arabic: '{count} طابعة',
    AppLanguage.persian: '{count} چاپگر',
    AppLanguage.english: '{count} printers',
    AppLanguage.turkish: '{count} yazıcı',
  },

  // ===== Tables =====
  '{itemName} گوازرایەوە': {
    AppLanguage.badini: '{itemName} ڤەگوازرایەوە',
    AppLanguage.arabic: 'تم نقل {itemName}',
    AppLanguage.persian: '{itemName} منتقل شد',
    AppLanguage.english: '{itemName} transferred',
    AppLanguage.turkish: '{itemName} taşındı',
  },

  // ===== Admin =====
  'ئادمێن': {
    AppLanguage.badini: 'ئادمێن',
    AppLanguage.arabic: 'مدير',
    AppLanguage.persian: 'مدیر',
    AppLanguage.english: 'Admin',
    AppLanguage.turkish: 'Yönetici',
  },

  // ===== Tables =====
  'ئامانج': {
    AppLanguage.badini: 'ئامانج',
    AppLanguage.arabic: 'الهدف',
    AppLanguage.persian: 'مقصد',
    AppLanguage.english: 'Target',
    AppLanguage.turkish: 'Hedef',
  },

  // ===== App =====
  'ئایکۆن': {
    AppLanguage.badini: 'ئایکۆن',
    AppLanguage.arabic: 'أيقونة',
    AppLanguage.persian: 'آیکون',
    AppLanguage.english: 'Icon',
    AppLanguage.turkish: 'Simge',
  },

  // ===== Orders =====
  'ئۆردەرەکان': {
    AppLanguage.badini: 'ئۆردەرەکان',
    AppLanguage.arabic: 'الطلبات',
    AppLanguage.persian: 'سفارش‌ها',
    AppLanguage.english: 'Orders',
    AppLanguage.turkish: 'Siparişler',
  },

  // ===== App =====
  'ئەم مانگە': {
    AppLanguage.badini: 'ئەم مانگە',
    AppLanguage.arabic: 'هذا الشهر',
    AppLanguage.persian: 'این ماه',
    AppLanguage.english: 'This month',
    AppLanguage.turkish: 'Bu ay',
  },
  'ئەم هەفتەیە': {
    AppLanguage.badini: 'ئەم هەفتەیە',
    AppLanguage.arabic: 'هذا الأسبوع',
    AppLanguage.persian: 'این هفته',
    AppLanguage.english: 'This week',
    AppLanguage.turkish: 'Bu hafta',
  },

  // ===== Admin =====
  'ئەم وشە نهێنییە بوونی هەیە، ژمارەیەکی تر هەڵبژێرە': {
    AppLanguage.badini: 'ئەم وشە نهێنییە بوونی هەیە، ژمارەیەکی تر هەڵبژێرە',
    AppLanguage.arabic: 'كلمة المرور هذه موجودة، اختر رقماً آخر',
    AppLanguage.persian: 'این رمز عبور وجود دارد، شماره دیگری انتخاب کنید',
    AppLanguage.english: 'This PIN already exists, choose another number',
    AppLanguage.turkish: 'Bu şifre zaten var, başka bir numara seçin',
  },

  // ===== App =====
  'ئەمڕۆ': {
    AppLanguage.badini: 'ئێرۆ',
    AppLanguage.arabic: 'اليوم',
    AppLanguage.persian: 'امروز',
    AppLanguage.english: 'Today',
    AppLanguage.turkish: 'Bugün',
  },

  // ===== Tables =====
  'ببورە ئەم مێزە بوونی هەیە': {
    AppLanguage.badini: 'ببورە ئەم ماسەیە بوونی هەیە',
    AppLanguage.arabic: 'عذراً، هذه الطاولة موجودة مسبقاً',
    AppLanguage.persian: 'متأسفانه این میز قبلاً وجود دارد',
    AppLanguage.english: 'Sorry, this table already exists',
    AppLanguage.turkish: 'Üzgünüm, bu masa zaten var',
  },

  // ===== App =====
  'بڕی وەرگیراو': {
    AppLanguage.badini: 'بڕی وەرگیراو',
    AppLanguage.arabic: 'المبلغ المستلم',
    AppLanguage.persian: 'مبلغ دریافت شده',
    AppLanguage.english: 'Amount received',
    AppLanguage.turkish: 'Alınan miktar',
  },

  // ===== Admin =====
  'بۆ نموونە: 11221': {
    AppLanguage.badini: 'بۆ نموونە: 11221',
    AppLanguage.arabic: 'مثال: 11221',
    AppLanguage.persian: 'مثال: 11221',
    AppLanguage.english: 'Example: 11221',
    AppLanguage.turkish: 'Örnek: 11221',
  },

  // ===== App =====
  'بۆ نموونە: 51 یان Ramyar': {
    AppLanguage.badini: 'بۆ نموونە: 51 یان Ramyar',
    AppLanguage.arabic: 'مثال: 51 أو Ramyar',
    AppLanguage.persian: 'مثال: 51 یا Ramyar',
    AppLanguage.english: 'Example: 51 or Ramyar',
    AppLanguage.turkish: 'Örnek: 51 veya Ramyar',
  },

  // ===== Admin =====
  'بۆ نموونە: محمد': {
    AppLanguage.badini: 'بۆ نموونە: محمد',
    AppLanguage.arabic: 'مثال: محمد',
    AppLanguage.persian: 'مثال: محمد',
    AppLanguage.english: 'Example: Mohammad',
    AppLanguage.turkish: 'Örnek: Muhammed',
  },

  // ===== App =====
  'RAMYAR POS - سیستەمی خێراتری چێشتخانە': {
    AppLanguage.badini: 'RAMYAR POS - سیستەمی خێراتری چێشتخانە',
    AppLanguage.arabic: 'راميار - أسرع نظام مطعم',
    AppLanguage.persian: 'رامیار - سریعترین سیستم رستوران',
    AppLanguage.english: 'RAMYAR POS - Fastest Restaurant POS',
    AppLanguage.turkish: 'RAMYAR POS - En Hızlı Restoran Sistemi',
  },
  'بێ هۆکار': {
    AppLanguage.badini: 'بێ هۆکار',
    AppLanguage.arabic: 'بدون سبب',
    AppLanguage.persian: 'بدون دلیل',
    AppLanguage.english: 'No reason',
    AppLanguage.turkish: 'Sebepsiz',
  },

  // ===== Printers =====
  'بە سەرکەوتووی چاپکرا': {
    AppLanguage.badini: 'بە سەرکەوتووی چاپکرا',
    AppLanguage.arabic: 'تمت الطباعة بنجاح',
    AppLanguage.persian: 'با موفقیت چاپ شد',
    AppLanguage.english: 'Printed successfully',
    AppLanguage.turkish: 'Başarıyla yazdırıldı',
  },

  // ===== Delivery Status =====
  'گەیشت': {
    AppLanguage.badini: 'گەهیشت',
    AppLanguage.arabic: 'وصل',
    AppLanguage.persian: 'رسید',
    AppLanguage.english: 'Arrived',
    AppLanguage.turkish: 'Ulaştı',
  },
  'گەیشت و ڕەفز': {
    AppLanguage.badini: 'گەهیشت و ڕەفز',
    AppLanguage.arabic: 'الواصل والمرفوض',
    AppLanguage.persian: 'رسیده و رد شده',
    AppLanguage.english: 'Arrived & Rejected',
    AppLanguage.turkish: 'Ulaşan ve Reddedilen',
  },
  'هیچ داواکارییەک نەنێردراوە': {
    AppLanguage.badini: 'هیچ داواکارییەک نەنێردراوە',
    AppLanguage.arabic: 'لم يتم إرسال أي طلب بعد',
    AppLanguage.persian: 'هنوز هیچ سفارشی ارسال نشده',
    AppLanguage.english: 'No order has been sent yet',
    AppLanguage.turkish: 'Henüz sipariş gönderilmedi',
  },
  'پرێنت کرا': {
    AppLanguage.badini: 'پرێنت کرا',
    AppLanguage.arabic: 'تمت الطباعة',
    AppLanguage.persian: 'چاپ شد',
    AppLanguage.english: 'Printed',
    AppLanguage.turkish: 'Yazdırıldı',
  },
  'ڕەفز - دوبارە بووە': {
    AppLanguage.badini: 'ڕەفز - دوبارە بووە',
    AppLanguage.arabic: 'مرفوض - مكرر',
    AppLanguage.persian: 'رد شد - تکراری',
    AppLanguage.english: 'Rejected - Duplicate',
    AppLanguage.turkish: 'Reddedildi - Kopya',
  },
  'گەیشتە لای کاشێر - پرێنت نەکراوە': {
    AppLanguage.badini: 'گەهیشتە لای کاشێر - پرێنت نەکراوە',
    AppLanguage.arabic: 'وصل إلى الكاشير - لم تتم الطباعة',
    AppLanguage.persian: 'به کاشیر رسید - چاپ نشد',
    AppLanguage.english: 'Reached cashier - not printed',
    AppLanguage.turkish: 'Kasiyere ulaştı - yazdırılmadı',
  },
  'نەگەیشتە - چاوەڕێ': {
    AppLanguage.badini: 'نەگەهیشتە - چاوەڕێ',
    AppLanguage.arabic: 'لم يصل - في الانتظار',
    AppLanguage.persian: 'نرسیده - در انتظار',
    AppLanguage.english: 'Not arrived - Waiting',
    AppLanguage.turkish: 'Ulaşmadı - Bekliyor',
  },
  'سینک': {
    AppLanguage.badini: 'سینک',
    AppLanguage.arabic: 'مزامنة',
    AppLanguage.persian: 'همگامسازی',
    AppLanguage.english: 'Sync',
    AppLanguage.turkish: 'Senkron',
  },

  // ===== Waiter Home =====
  'بەتاڵ': {
    AppLanguage.badini: 'ڤالا',
    AppLanguage.arabic: 'فارغ',
    AppLanguage.persian: 'خالی',
    AppLanguage.english: 'Empty',
    AppLanguage.turkish: 'Boş',
  },
  'بەتاڵە': {
    AppLanguage.badini: 'ڤالایە',
    AppLanguage.arabic: 'فارغة',
    AppLanguage.persian: 'خالی است',
    AppLanguage.english: 'Empty',
    AppLanguage.turkish: 'Boş',
  },
  'بەتاڵەکان': {
    AppLanguage.badini: 'ڤالاکان',
    AppLanguage.arabic: 'الفارغة',
    AppLanguage.persian: 'خالی‌ها',
    AppLanguage.english: 'Empty Tables',
    AppLanguage.turkish: 'Boş Masalar',
  },
  'بەتاڵەکان:': {
    AppLanguage.badini: 'ڤالاکان:',
    AppLanguage.arabic: 'الفارغة:',
    AppLanguage.persian: 'خالی:',
    AppLanguage.english: 'Empty:',
    AppLanguage.turkish: 'Boş:',
  },
  'بەخێربێیت': {
    AppLanguage.badini: 'بەخێرهاتی',
    AppLanguage.arabic: 'أهلاً وسهلاً',
    AppLanguage.persian: 'خوش آمدید',
    AppLanguage.english: 'Welcome',
    AppLanguage.turkish: 'Hoş geldiniz',
  },
  'بەخێربێیت! ژمارەی کڕیاران هەڵبژێرە': {
    AppLanguage.badini: 'بەخێرهاتی! هژمارا کڕیاران هەڵبژێرە',
    AppLanguage.arabic: 'أهلاً! اختر عدد الضيوف',
    AppLanguage.persian: 'خوش آمدید! تعداد مهمانان را انتخاب کنید',
    AppLanguage.english: 'Welcome! Select number of guests',
    AppLanguage.turkish: 'Hoş geldiniz! Misafir sayısını seçin',
  },

  // ===== App =====
  'بەردەوامبوون': {
    AppLanguage.badini: 'بەردەوامبوون',
    AppLanguage.arabic: 'استمرار',
    AppLanguage.persian: 'ادامه',
    AppLanguage.english: 'Continue',
    AppLanguage.turkish: 'Devam',
  },

  // ===== Menu / Food =====
  'بەش': {
    AppLanguage.badini: 'بەش',
    AppLanguage.arabic: 'قسم',
    AppLanguage.persian: 'بخش',
    AppLanguage.english: 'Section',
    AppLanguage.turkish: 'Bölüm',
  },
  'بەشی سەرەکی': {
    AppLanguage.badini: 'بەشی سەرەکی',
    AppLanguage.arabic: 'القسم الرئيسي',
    AppLanguage.persian: 'بخش اصلی',
    AppLanguage.english: 'Main Section',
    AppLanguage.turkish: 'Ana Bölüm',
  },
  'بەشێک هەڵبژێرە': {
    AppLanguage.badini: 'بەشەکێ هەڵبژێرە',
    AppLanguage.arabic: 'اختر قسماً',
    AppLanguage.persian: 'یک بخش انتخاب کنید',
    AppLanguage.english: 'Select a section',
    AppLanguage.turkish: 'Bir bölüm seçin',
  },
  'بەشەکان': {
    AppLanguage.badini: 'بەشەکان',
    AppLanguage.arabic: 'الأقسام',
    AppLanguage.persian: 'بخش‌ها',
    AppLanguage.english: 'Sections',
    AppLanguage.turkish: 'Bölümler',
  },

  // ===== Admin =====
  'بەڕێوەبردنی بەکارهێنەران': {
    AppLanguage.badini: 'بەڕێوەبردنی بەکارهێنەران',
    AppLanguage.arabic: 'إدارة المستخدمين',
    AppLanguage.persian: 'مدیریت کاربران',
    AppLanguage.english: 'User Management',
    AppLanguage.turkish: 'Kullanıcı Yönetimi',
  },
  'بەڕێوەبردنی مێز': {
    AppLanguage.badini: 'بەڕێوەبردنی مێز',
    AppLanguage.arabic: 'إدارة الطاولات',
    AppLanguage.persian: 'مدیریت میزها',
    AppLanguage.english: 'Table Management',
    AppLanguage.turkish: 'Masa Yönetimi',
  },
  'بەڕێوەبردنی مێنیو': {
    AppLanguage.badini: 'بەڕێوەبردنی مێنیو',
    AppLanguage.arabic: 'إدارة القائمة',
    AppLanguage.persian: 'مدیریت منو',
    AppLanguage.english: 'Menu Management',
    AppLanguage.turkish: 'Menü Yönetimi',
  },

  // ===== Backup =====
  'بەکاپ': {
    AppLanguage.badini: 'بەکاپ',
    AppLanguage.arabic: 'نسخ احتياطي',
    AppLanguage.persian: 'پشتیبان',
    AppLanguage.english: 'Backup',
    AppLanguage.turkish: 'Yedek',
  },
  'بەکاپ بە سەرکەوتووی گەڕایەوە': {
    AppLanguage.badini: 'بەکاپ بە سەرکەوتووی گەڕایەوە',
    AppLanguage.arabic: 'تم استعادة النسخة الاحتياطية بنجاح',
    AppLanguage.persian: 'پشتیبان با موفقیت بازیابی شد',
    AppLanguage.english: 'Backup restored successfully',
    AppLanguage.turkish: 'Yedek başarıyla geri yüklendi',
  },
  'بەکاپ لە فایلێکی .db هەڵدەگرێت و دەتوانیت بیگەڕێنیتەوە': {
    AppLanguage.badini:
        'بەکاپ لە فایلێکی .db هەڵدەگرێت و دەتوانیت بیگەڕێنیتەوە',
    AppLanguage.arabic: 'يتم حفظ النسخة الاحتياطية في ملف .db ويمكن استعادتها',
    AppLanguage.persian:
        'پشتیبان در یک فایل .db ذخیره می‌شود و می‌توانید آن را بازیابی کنید',
    AppLanguage.english: 'Backup is saved as a .db file and can be restored',
    AppLanguage.turkish:
        'Yedek .db dosyası olarak kaydedilir ve geri yüklenebilir',
  },
  'بەکاپ و گەڕاندنەوە': {
    AppLanguage.badini: 'بەکاپ و گەڕاندنەوە',
    AppLanguage.arabic: 'النسخ الاحتياطي والاستعادة',
    AppLanguage.persian: 'پشتیبان و بازیابی',
    AppLanguage.english: 'Backup & Restore',
    AppLanguage.turkish: 'Yedekleme ve Geri Yükleme',
  },
  'بەکاپ و گەڕاندنەوەی داتاکان': {
    AppLanguage.badini: 'بەکاپ و گەڕاندنەوەی داتاکان',
    AppLanguage.arabic: 'النسخ الاحتياطي واستعادة البيانات',
    AppLanguage.persian: 'پشتیبان و بازیابی داده‌ها',
    AppLanguage.english: 'Backup & Restore Data',
    AppLanguage.turkish: 'Veri Yedekleme ve Geri Yükleme',
  },
  'بەکاپ کرایە: {name}': {
    AppLanguage.badini: 'بەکاپ کرایە: {name}',
    AppLanguage.arabic: 'تم إنشاء النسخة الاحتياطية: {name}',
    AppLanguage.persian: 'پشتیبان ایجاد شد: {name}',
    AppLanguage.english: 'Backup created: {name}',
    AppLanguage.turkish: 'Yedek oluşturuldu: {name}',
  },

  // ===== App =====
  'تایبەت': {
    AppLanguage.badini: 'تایبەت',
    AppLanguage.arabic: 'خاص',
    AppLanguage.persian: 'خصوصی',
    AppLanguage.english: 'Private',
    AppLanguage.turkish: 'Özel',
  },
  'تۆمارکردن': {
    AppLanguage.badini: 'تۆمارکرن',
    AppLanguage.arabic: 'تسجيل',
    AppLanguage.persian: 'ثبت',
    AppLanguage.english: 'Register',
    AppLanguage.turkish: 'Kayıt',
  },

  // ===== Admin =====
  'تۆمارکردنی خەرجی': {
    AppLanguage.badini: 'تۆمارکردنی خەرجی',
    AppLanguage.arabic: 'تسجيل المصروف',
    AppLanguage.persian: 'ثبت هزینه',
    AppLanguage.english: 'Record Expense',
    AppLanguage.turkish: 'Gider Kaydet',
  },

  // ===== Tables =====
  'تێکەڵکردن': {
    AppLanguage.badini: 'تێکەڵکردن',
    AppLanguage.arabic: 'دمج',
    AppLanguage.persian: 'ادغام',
    AppLanguage.english: 'Merge',
    AppLanguage.turkish: 'Birleştir',
  },
  'تێکەڵکردنی مێز': {
    AppLanguage.badini: 'تێکەڵکردنی مێز',
    AppLanguage.arabic: 'دمج الطاولات',
    AppLanguage.persian: 'ادغام میزها',
    AppLanguage.english: 'Merge Tables',
    AppLanguage.turkish: 'Masaları Birleştir',
  },

  // ===== Admin =====
  'تەنها ئادمێن دەتوانێت قەرز بسڕێتەوە.': {
    AppLanguage.badini: 'تەنها ئادمێن دەتوانێت قەرز بسڕێتەوە.',
    AppLanguage.arabic: 'فقط المدير يمكنه حذف الديون.',
    AppLanguage.persian: 'فقط مدیر می‌تواند بدهی را حذف کند.',
    AppLanguage.english: 'Only admin can delete debts.',
    AppLanguage.turkish: 'Sadece yönetici borçları silebilir.',
  },

  // ===== Payment =====
  'جۆری کارت': {
    AppLanguage.badini: 'جۆری کارت',
    AppLanguage.arabic: 'نوع البطاقة',
    AppLanguage.persian: 'نوع کارت',
    AppLanguage.english: 'Card Type',
    AppLanguage.turkish: 'Kart Türü',
  },
  'چاپکردنی وەسڵ': {
    AppLanguage.badini: 'چاپکرنی وەسڵ',
    AppLanguage.arabic: 'طباعة الإيصال',
    AppLanguage.persian: 'چاپ رسید',
    AppLanguage.english: 'Print Receipt',
    AppLanguage.turkish: 'Fiş Yazdır',
  },

  // ===== App =====
  'جێبەجێکردن': {
    AppLanguage.badini: 'جێبەجێکردن',
    AppLanguage.arabic: 'تنفيذ',
    AppLanguage.persian: 'اجرا',
    AppLanguage.english: 'Execute',
    AppLanguage.turkish: 'Çalıştır',
  },

  // ===== Cashier =====
  'حسابەکان': {
    AppLanguage.badini: 'حسابەکان',
    AppLanguage.arabic: 'الحسابات',
    AppLanguage.persian: 'حساب‌ها',
    AppLanguage.english: 'Accounts',
    AppLanguage.turkish: 'Hesaplar',
  },
  'حیساب': {
    AppLanguage.badini: 'حیساب',
    AppLanguage.arabic: 'فاتورة',
    AppLanguage.persian: 'صورتحساب',
    AppLanguage.english: 'Bill',
    AppLanguage.turkish: 'Hesap',
  },
  'حیسابی کاشێر': {
    AppLanguage.badini: 'حیسابی کاشێر',
    AppLanguage.arabic: 'فاتورة الكاشير',
    AppLanguage.persian: 'صورتحساب صندوقدار',
    AppLanguage.english: 'Cashier Bill',
    AppLanguage.turkish: 'Kasiyer Hesabı',
  },

  // ===== App =====
  'خاو': {
    AppLanguage.badini: 'خاو',
    AppLanguage.arabic: 'خام',
    AppLanguage.persian: 'خام',
    AppLanguage.english: 'Gross',
    AppLanguage.turkish: 'Brüt',
  },
  'خاو (نێت)': {
    AppLanguage.badini: 'خاو (نێت)',
    AppLanguage.arabic: 'خام (صافي)',
    AppLanguage.persian: 'خام (خالص)',
    AppLanguage.english: 'Net',
    AppLanguage.turkish: 'Net',
  },

  // ===== Admin =====
  'خاو (کۆکراوە - خەرجی)': {
    AppLanguage.badini: 'خاو (کۆکراوە - خەرجی)',
    AppLanguage.arabic: 'الصافي (المحصل - المصروفات)',
    AppLanguage.persian: 'خالص (جمع‌آوری - هزینه‌ها)',
    AppLanguage.english: 'Net (collected - expenses)',
    AppLanguage.turkish: 'Net (toplanan - giderler)',
  },

  // ===== Menu / Food =====
  'خواردن': {
    AppLanguage.badini: 'خوارن',
    AppLanguage.arabic: 'طعام',
    AppLanguage.persian: 'غذا',
    AppLanguage.english: 'Food',
    AppLanguage.turkish: 'Yiyecek',
  },
  'خواردن هەڵبژێرە': {
    AppLanguage.badini: 'خوارنەکێ هەڵبژێرە',
    AppLanguage.arabic: 'اختر الطعام',
    AppLanguage.persian: 'غذا را انتخاب کنید',
    AppLanguage.english: 'Select food',
    AppLanguage.turkish: 'Yiyecek seçin',
  },
  'خواردنەکان': {
    AppLanguage.badini: 'خوارنەکان',
    AppLanguage.arabic: 'الأطعمة',
    AppLanguage.persian: 'غذاها',
    AppLanguage.english: 'Foods',
    AppLanguage.turkish: 'Yiyecekler',
  },
  'خواردنەکان گوازرانەوە بۆ {name}': {
    AppLanguage.badini: 'خوارنەکان ڤەگوازرانەوە بۆ {name}',
    AppLanguage.arabic: 'تم نقل الأطعمة إلى {name}',
    AppLanguage.persian: 'غذاها به {name} منتقل شد',
    AppLanguage.english: 'Items transferred to {name}',
    AppLanguage.turkish: 'Yiyecekler {name} konumuna taşındı',
  },

  // ===== Admin =====
  'خەرجی': {
    AppLanguage.badini: 'خەرجی',
    AppLanguage.arabic: 'مصروف',
    AppLanguage.persian: 'هزینه',
    AppLanguage.english: 'Expense',
    AppLanguage.turkish: 'Gider',
  },
  'خەرجی و قەرز': {
    AppLanguage.badini: 'خەرجی و قەرز',
    AppLanguage.arabic: 'المصروفات والديون',
    AppLanguage.persian: 'هزینه‌ها و بدهی‌ها',
    AppLanguage.english: 'Expenses & Debts',
    AppLanguage.turkish: 'Giderler ve Borçlar',
  },
  'خەرجیەکان': {
    AppLanguage.badini: 'خەرجیەکان',
    AppLanguage.arabic: 'المصروفات',
    AppLanguage.persian: 'هزینه‌ها',
    AppLanguage.english: 'Expenses',
    AppLanguage.turkish: 'Giderler',
  },
  'گەڕانەوەی خەرجی': {
    AppLanguage.badini: 'گەڕانەوەی خەرجی',
    AppLanguage.arabic: 'إرجاع المصروف',
    AppLanguage.persian: 'بازگشت هزینه',
    AppLanguage.english: 'Expense Return',
    AppLanguage.turkish: 'Gider İadesi',
  },
  'گەڕاندنەوەی خەرجی': {
    AppLanguage.badini: 'گەڕاندنەوەی خەرجی',
    AppLanguage.arabic: 'إرجاع المصروف',
    AppLanguage.persian: 'بازگرداندن هزینه',
    AppLanguage.english: 'Return expense',
    AppLanguage.turkish: 'Gideri iade et',
  },
  'گەڕاندنەوەی ئەم خەرجییە': {
    AppLanguage.badini: 'گەڕاندنەوەیا ڤێ خەرجیێ',
    AppLanguage.arabic: 'إرجاع هذا المصروف',
    AppLanguage.persian: 'بازگرداندن این هزینه',
    AppLanguage.english: 'Return this expense',
    AppLanguage.turkish: 'Bu gideri iade et',
  },
  'گەڕان بە ناوی خەرجی': {
    AppLanguage.badini: 'گەڕان ب ناڤێ خەرجی',
    AppLanguage.arabic: 'ابحث باسم المصروف',
    AppLanguage.persian: 'جستجو با نام هزینه',
    AppLanguage.english: 'Search by expense name',
    AppLanguage.turkish: 'Gider adına göre ara',
  },
  'کۆی گەڕانەوەی خەرجی': {
    AppLanguage.badini: 'کۆیا گەڕاندنەوا خەرجی',
    AppLanguage.arabic: 'إجمالي المصروفات المرتجعة',
    AppLanguage.persian: 'مجموع هزینه‌های بازگشتی',
    AppLanguage.english: 'Total returned',
    AppLanguage.turkish: 'Toplam iade',
  },
  'خەرجی تۆمارکرا': {
    AppLanguage.badini: 'خەرجی هاتە تۆمارکرن',
    AppLanguage.arabic: 'تم تسجيل المصروف',
    AppLanguage.persian: 'هزینه ثبت شد',
    AppLanguage.english: 'Expense recorded',
    AppLanguage.turkish: 'Gider kaydedildi',
  },
  'خەرجی گەڕێنرایەوە': {
    AppLanguage.badini: 'خەرجی هاتە گەڕاندن',
    AppLanguage.arabic: 'تم إرجاع المصروف',
    AppLanguage.persian: 'هزینه بازگردانده شد',
    AppLanguage.english: 'Expense returned',
    AppLanguage.turkish: 'Gider iade edildi',
  },
  'پێویستە ناوی خەرجی بنووسیت': {
    AppLanguage.badini: 'پێدڤییە ناڤێ خەرجی بنڤیسی',
    AppLanguage.arabic: 'يجب كتابة اسم المصروف',
    AppLanguage.persian: 'نام هزینه الزامی است',
    AppLanguage.english: 'Expense name is required',
    AppLanguage.turkish: 'Gider adı gerekli',
  },
  'پێویستە بڕ بنووسیت': {
    AppLanguage.badini: 'پێدڤییە بری بنڤیسی',
    AppLanguage.arabic: 'يجب إدخال المبلغ',
    AppLanguage.persian: 'مبلغ الزامی است',
    AppLanguage.english: 'Amount is required',
    AppLanguage.turkish: 'Tutar gerekli',
  },

  // ===== Payment =====
  'د.ع': {
    AppLanguage.badini: 'د.ع',
    AppLanguage.arabic: 'د.ع',
    AppLanguage.persian: 'د.ع',
    AppLanguage.english: 'IQD',
    AppLanguage.turkish: 'IQD',
  },

  // ===== App =====
  'داخستن': {
    AppLanguage.badini: 'داخستن',
    AppLanguage.arabic: 'إغلاق',
    AppLanguage.persian: 'بستن',
    AppLanguage.english: 'Close',
    AppLanguage.turkish: 'Kapat',
  },
  'داخستن و چوونە دەرەوە': {
    AppLanguage.badini: 'داخستن و دەرکەڤتن',
    AppLanguage.arabic: 'إغلاق وخروج',
    AppLanguage.persian: 'بستن و خروج',
    AppLanguage.english: 'Close & Exit',
    AppLanguage.turkish: 'Kapat ve Çık',
  },

  // ===== Cashier =====
  'داخستنی شەفت': {
    AppLanguage.badini: 'داخستنا شەفتێ',
    AppLanguage.arabic: 'إنهاء الشيفت',
    AppLanguage.persian: 'پایان شیفت',
    AppLanguage.english: 'End Shift',
    AppLanguage.turkish: 'Vardiyayı Bitir',
  },

  // ===== App =====
  'داشبۆرد': {
    AppLanguage.badini: 'داشبۆرد',
    AppLanguage.arabic: 'لوحة القيادة',
    AppLanguage.persian: 'داشبورد',
    AppLanguage.english: 'Dashboard',
    AppLanguage.turkish: 'Panel',
  },

  // ===== Cashier =====
  'داشکاندن': {
    AppLanguage.badini: 'داشکاندن',
    AppLanguage.arabic: 'خصم',
    AppLanguage.persian: 'تخفیف',
    AppLanguage.english: 'Discount',
    AppLanguage.turkish: 'İndirim',
  },
  'داشکاندن (%)': {
    AppLanguage.badini: 'داشکاندن (%)',
    AppLanguage.arabic: 'الخصم (%)',
    AppLanguage.persian: 'تخفیف (%)',
    AppLanguage.english: 'Discount (%)',
    AppLanguage.turkish: 'İndirim (%)',
  },
  'داشکاندن (د.ع)': {
    AppLanguage.badini: 'داشکاندن (د.ع)',
    AppLanguage.arabic: 'الخصم (د.ع)',
    AppLanguage.persian: 'تخفیف (د.ع)',
    AppLanguage.english: 'Discount (IQD)',
    AppLanguage.turkish: 'İndirim (IQD)',
  },

  // ===== Waiter Home =====
  'دانیشتوو': {
    AppLanguage.badini: 'ڕوونیشتی',
    AppLanguage.arabic: 'جالس',
    AppLanguage.persian: 'نشسته',
    AppLanguage.english: 'Occupied',
    AppLanguage.turkish: 'Dolu',
  },

  // ===== Cashier =====
  'داهاتی خاو': {
    AppLanguage.badini: 'داهاتی خاو',
    AppLanguage.arabic: 'الدخل الخام',
    AppLanguage.persian: 'درآمد ناخالص',
    AppLanguage.english: 'Gross Income',
    AppLanguage.turkish: 'Brüt Gelir',
  },

  // ===== Orders =====
  'داواکاری': {
    AppLanguage.badini: 'داواکاری',
    AppLanguage.arabic: 'الطلب',
    AppLanguage.persian: 'سفارش',
    AppLanguage.english: 'Order',
    AppLanguage.turkish: 'Sipariş',
  },
  'داواکاری پارە': {
    AppLanguage.badini: 'داواکاری پارە',
    AppLanguage.arabic: 'طلب الدفع',
    AppLanguage.persian: 'درخواست پرداخت',
    AppLanguage.english: 'Payment Request',
    AppLanguage.turkish: 'Ödeme Talebi',
  },
  'داواکاری پێشوو': {
    AppLanguage.badini: 'داواکاری پێشوو',
    AppLanguage.arabic: 'طلب سابق',
    AppLanguage.persian: 'سفارش قبلی',
    AppLanguage.english: 'Previous Order',
    AppLanguage.turkish: 'Önceki Sipariş',
  },
  'داواکاری چالاک': {
    AppLanguage.badini: 'داواکاری چالاک',
    AppLanguage.arabic: 'الطلبات النشطة',
    AppLanguage.persian: 'سفارشات فعال',
    AppLanguage.english: 'Active Orders',
    AppLanguage.turkish: 'Aktif Siparişler',
  },
  'داواکارییەکانی پێشوو': {
    AppLanguage.badini: 'داواکارییەکانی پێشوو',
    AppLanguage.arabic: 'الطلبات السابقة',
    AppLanguage.persian: 'سفارش‌های قبلی',
    AppLanguage.english: 'Previous Orders',
    AppLanguage.turkish: 'Önceki Siparişler',
  },
  '{count} سەردان': {
    AppLanguage.badini: '{count} سەردان',
    AppLanguage.arabic: '{count} جلسة',
    AppLanguage.persian: '{count} نشست',
    AppLanguage.english: '{count} visits',
    AppLanguage.turkish: '{count} ziyaret',
  },
  '{count} مێز': {
    AppLanguage.badini: '{count} مێز',
    AppLanguage.arabic: '{count} طاولة',
    AppLanguage.persian: '{count} میز',
    AppLanguage.english: '{count} tables',
    AppLanguage.turkish: '{count} masa',
  },
  'مێژووی مێز': {
    AppLanguage.badini: 'مێژووی مێز',
    AppLanguage.arabic: 'سجل الطاولة',
    AppLanguage.persian: 'تاریخچه میز',
    AppLanguage.english: 'Table history',
    AppLanguage.turkish: 'Masa geçmişi',
  },
  'هیچ داواکارییەکی پێشوو نییە لەم شەفتەدا': {
    AppLanguage.badini: 'هیچ داواکارییەکی پێشوو نییە لەم شەفتەدا',
    AppLanguage.arabic: 'لا توجد طلبات سابقة في هذه الوردية',
    AppLanguage.persian: 'هیچ سفارش قبلی در این شیفت نیست',
    AppLanguage.english: 'No previous orders in this shift',
    AppLanguage.turkish: 'Bu vardiyada önceki sipariş yok',
  },
  'داوای حیسابی کردووە': {
    AppLanguage.badini: 'داوای حیسابی کردووە',
    AppLanguage.arabic: 'طلب الحساب',
    AppLanguage.persian: 'درخواست حساب',
    AppLanguage.english: 'Account requested',
    AppLanguage.turkish: 'Hesap istendi',
  },

  // ===== App =====
  'داڤبۆرد': {
    AppLanguage.badini: 'داڤبۆرد',
    AppLanguage.arabic: 'لوحة القيادة',
    AppLanguage.persian: 'داشبورد',
    AppLanguage.english: 'Dashboard',
    AppLanguage.turkish: 'Panel',
  },

  // ===== Backup =====
  'دروستکردنی بەکاپ': {
    AppLanguage.badini: 'دروستکردنی بەکاپ',
    AppLanguage.arabic: 'إنشاء نسخة احتياطية',
    AppLanguage.persian: 'ایجاد پشتیبان',
    AppLanguage.english: 'Create Backup',
    AppLanguage.turkish: 'Yedek Oluştur',
  },

  // ===== App =====
  'دواکەوتوو': {
    AppLanguage.badini: 'دواکەوتوو',
    AppLanguage.arabic: 'متأخر',
    AppLanguage.persian: 'تأخیر',
    AppLanguage.english: 'Overdue',
    AppLanguage.turkish: 'Gecikmiş',
  },
  'دوایین چالاکیەکان': {
    AppLanguage.badini: 'دوایین چالاکیەکان',
    AppLanguage.arabic: 'آخر النشاطات',
    AppLanguage.persian: 'آخرین فعالیت‌ها',
    AppLanguage.english: 'Recent Activity',
    AppLanguage.turkish: 'Son Aktiviteler',
  },
  'دوێنی': {
    AppLanguage.badini: 'دوێکە',
    AppLanguage.arabic: 'أمس',
    AppLanguage.persian: 'دیروز',
    AppLanguage.english: 'Yesterday',
    AppLanguage.turkish: 'Dün',
  },
  'دڵنیایت دەتەوێت {name} بسڕیتەوە؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت {name} بسڕیتەوە؟',
    AppLanguage.arabic: 'هل أنت متأكد من حذف {name}؟',
    AppLanguage.persian: 'آیا مطمئن هستید {name} را حذف کنید؟',
    AppLanguage.english: 'Are you sure you want to delete {name}?',
    AppLanguage.turkish: '{name} silmek istediğinize emin misiniz?',
  },
  'دڵنیایت دەتەوێت {printer} لابەریت؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت {printer} لابەریت؟',
    AppLanguage.arabic: 'هل أنت متأكد من إزالة {printer}؟',
    AppLanguage.persian: 'آیا مطمئن هستید {printer} را حذف کنید؟',
    AppLanguage.english: 'Are you sure you want to remove {printer}?',
    AppLanguage.turkish: '{printer} kaldırmak istediğinize emin misiniz?',
  },

  // ===== Menu / Food =====
  'دڵنیایت دەتەوێت بەشی {name} بسڕیتەوە؟ {count} خواردنیش دەسڕێتەوە.': {
    AppLanguage.badini:
        'دڵنیایت دەتەوێت بەشی {name} بسڕیتەوە؟ {count} خواردنیش دەسڕێتەوە.',
    AppLanguage.arabic:
        'هل أنت متأكد من حذف قسم {name}؟ سيتم حذف {count} طعام أيضاً.',
    AppLanguage.persian:
        'آیا مطمئن هستید بخش {name} را حذف کنید؟ {count} غذا نیز حذف خواهد شد.',
    AppLanguage.english:
        'Are you sure you want to delete section {name}? {count} food items will also be deleted.',
    AppLanguage.turkish:
        '{name} bölümünü silmek istediğinize emin misiniz? {count} yiyecek de silinecek.',
  },

  // ===== Backup =====
  'دڵنیایت دەتەوێت بەکاپی {name} بگەڕێنیتەوە؟ هەموو داتاکانی ئێستا دەسڕێتەوە.': {
    AppLanguage.badini:
        'دڵنیایت دەتەوێت بەکاپی {name} بگەڕێنیتەوە؟ هەموو داتاکانی ئێستا دەسڕێتەوە.',
    AppLanguage.arabic:
        'هل أنت متأكد من استعادة النسخة {name}؟ سيتم حذف جميع البيانات الحالية.',
    AppLanguage.persian:
        'آیا مطمئن هستید پشتیبان {name} را بازیابی کنید؟ تمام داده‌های فعلی حذف خواهند شد.',
    AppLanguage.english:
        'Are you sure you want to restore {name}? All current data will be deleted.',
    AppLanguage.turkish:
        '{name} yedeğini geri yüklemek istediğinize emin misiniz? Tüm mevcut veriler silinecek.',
  },

  // ===== Cashier =====
  'دڵنیایت دەتەوێت شەفت دەستپێبکەیت؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت شەفت دەستپێبکەیت؟',
    AppLanguage.arabic: 'هل أنت متأكد من بدء الشيفت؟',
    AppLanguage.persian: 'آیا مطمئن هستید شیفت را شروع کنید؟',
    AppLanguage.english: 'Are you sure you want to start the shift?',
    AppLanguage.turkish: 'Vardiyayı başlatmak istediğinize emin misiniz?',
  },

  // ===== Debt =====
  'دڵنیایت دەتەوێت قەرزی {name} - د.ع {amount} بسڕیتەوە؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت قەرزی {name} - د.ع {amount} بسڕیتەوە؟',
    AppLanguage.arabic: 'هل أنت متأكد من حذف دين {name} - {amount} د.ع؟',
    AppLanguage.persian:
        'آیا مطمئن هستید که بدهی {name} - {amount} د.ع را حذف کنید؟',
    AppLanguage.english:
        'Are you sure you want to delete debt {name} - IQD {amount}?',
    AppLanguage.turkish:
        '{name} - {amount} IQD borcunu silmek istediğinize emin misiniz?',
  },
  'دڵنیایت دەتەوێت قەرزی {name} - د.ع {amount} واسڵ بکەیت؟': {
    AppLanguage.badini:
        'دڵنیایت دەتەوێت قەرزی {name} - د.ع {amount} واسڵ بکەیت؟',
    AppLanguage.arabic: 'هل أنت متأكد من تسوية دين {name} - {amount} د.ع؟',
    AppLanguage.persian:
        'آیا مطمئن هستید که بدهی {name} - {amount} د.ع را تسویه کنید؟',
    AppLanguage.english:
        'Are you sure you want to settle debt {name} - IQD {amount}?',
    AppLanguage.turkish:
        '{name} - {amount} IQD borcunu kapatmak istediğinize emin misiniz?',
  },

  // ===== Tables =====
  'دڵنیایت دەتەوێت مێزی {tableNumber} بە {method} واسڵ بکەیت؟': {
    AppLanguage.badini:
        'دڵنیایت دەتەوێت مێزی {tableNumber} بە {method} واسڵ بکەیت؟',
    AppLanguage.arabic:
        'هل أنت متأكد من تسوية طاولة {tableNumber} بواسطة {method}؟',
    AppLanguage.persian:
        'آیا مطمئن هستید میز {tableNumber} با {method} تسویه شود؟',
    AppLanguage.english: 'Settle Table {tableNumber} with {method}?',
    AppLanguage.turkish:
        '{tableNumber} numaralı masayı {method} ile kapatmak istediğinize emin misiniz?',
  },
  'دڵنیایت دەتەوێت مێزی {tableNumber} بسڕیتەوە؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت مێزی {tableNumber} بسڕیتەوە؟',
    AppLanguage.arabic: 'هل أنت متأكد من حذف طاولة {tableNumber}؟',
    AppLanguage.persian: 'آیا مطمئن هستید میز {tableNumber} را حذف کنید؟',
    AppLanguage.english: 'Are you sure you want to delete Table {tableNumber}?',
    AppLanguage.turkish:
        '{tableNumber} numaralı masayı silmek istediğinize emin misiniz?',
  },

  // ===== Menu / Food =====
  'دڵنیایت دەتەوێت هەموو خواردنەکان بسڕیتەوە؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت هەموو خواردنەکان بسڕیتەوە؟',
    AppLanguage.arabic: 'هل أنت متأكد من حذف جميع الأطعمة؟',
    AppLanguage.persian: 'آیا مطمئن هستید همه غذاها را حذف کنید؟',
    AppLanguage.english: 'Are you sure you want to delete all items?',
    AppLanguage.turkish: 'Tüm yiyecekleri silmek istediğinize emin misiniz?',
  },

  // ===== Tables =====
  'دڵنیایت دەتەوێت هەموو خواردنەکانی مێزی {source} بگوازیتەوە بۆ {target}؟': {
    AppLanguage.badini:
        'دڵنیایت دەتەوێت هەموو خواردنەکانی مێزی {source} بگوازیتەوە بۆ {target}؟',
    AppLanguage.arabic:
        'هل أنت متأكد من نقل كل أطعمة طاولة {source} إلى {target}؟',
    AppLanguage.persian:
        'آیا مطمئن هستید که همه غذاهای میز {source} به {target} منتقل شود؟',
    AppLanguage.english:
        'Are you sure you want to transfer all items from Table {source} to {target}?',
    AppLanguage.turkish:
        '{source} numaralı masadaki tüm yiyecekleri {target} konumuna taşımak istediğinize emin misiniz?',
  },
  'دڵنیایت دەتەوێت ئەم مێزە بخەیتە بەشی قەرزەکانەوە؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت ئەم مێزە بخەیتە بەشی قەرزەکانەوە؟',
    AppLanguage.arabic: 'هل أنت متأكد أنك تريد وضع هذه الطاولة في قسم الديون؟',
    AppLanguage.persian:
        'آیا مطمئن هستید که می‌خواهید این میز را به بخش بدهی‌ها منتقل کنید؟',
    AppLanguage.english:
        'Are you sure you want to put this table in the debt section?',
    AppLanguage.turkish:
        'Bu masayı borçlar bölümüne koymak istediğinize emin misiniz?',
  },
  'دۆخی مێزەکان': {
    AppLanguage.badini: 'دۆخی ماسەکان',
    AppLanguage.arabic: 'حالة الطاولات',
    AppLanguage.persian: 'وضعیت میزها',
    AppLanguage.english: 'Table Status',
    AppLanguage.turkish: 'Masa Durumu',
  },

  // ===== App =====
  'دەرچوون': {
    AppLanguage.badini: 'دەرکەڤتن',
    AppLanguage.arabic: 'تسجيل الخروج',
    AppLanguage.persian: 'خروج',
    AppLanguage.english: 'Logout',
    AppLanguage.turkish: 'Çıkış Yap',
  },
  'دەستنیشانکردن': {
    AppLanguage.badini: 'دەستنیشانکردن',
    AppLanguage.arabic: 'تحديد',
    AppLanguage.persian: 'شناسایی',
    AppLanguage.english: 'Identify',
    AppLanguage.turkish: 'Belirle',
  },

  // ===== Printers =====
  'دەستنیشانکردنی چاپکەر': {
    AppLanguage.badini: 'دەستنیشانکردنی چاپکەر',
    AppLanguage.arabic: 'تحديد الطابعة',
    AppLanguage.persian: 'شناسایی چاپگر',
    AppLanguage.english: 'Printer Identification',
    AppLanguage.turkish: 'Yazıcı Belirleme',
  },

  // ===== App =====
  'دەستپێکردن': {
    AppLanguage.badini: 'دەستپێکرن',
    AppLanguage.arabic: 'بدء',
    AppLanguage.persian: 'شروع',
    AppLanguage.english: 'Start',
    AppLanguage.turkish: 'Başlat',
  },

  // ===== Cashier =====
  'دەستپێکردنی شەفت': {
    AppLanguage.badini: 'دەستپێکرنا شەفتێ',
    AppLanguage.arabic: 'بدء الشيفت',
    AppLanguage.persian: 'شروع شیفت',
    AppLanguage.english: 'Start Shift',
    AppLanguage.turkish: 'Vardiya Başlat',
  },

  // ===== App =====
  'دەستی پێکردووە لە {time}': {
    AppLanguage.badini: 'دەستی پێکردووە لە {time}',
    AppLanguage.arabic: 'بدأ في {time}',
    AppLanguage.persian: 'در {time} شروع شد',
    AppLanguage.english: 'Started at {time}',
    AppLanguage.turkish: '{time} başladı',
  },

  // ===== Tables =====
  'زانیاری مێز': {
    AppLanguage.badini: 'زانیاری ماسە',
    AppLanguage.arabic: 'معلومات الطاولة',
    AppLanguage.persian: 'اطلاعات میز',
    AppLanguage.english: 'Table Info',
    AppLanguage.turkish: 'Masa Bilgisi',
  },

  // ===== App =====
  'زیاترە': {
    AppLanguage.badini: 'زیاترە',
    AppLanguage.arabic: 'أكثر',
    AppLanguage.persian: 'بیشتر',
    AppLanguage.english: 'More',
    AppLanguage.turkish: 'Daha fazla',
  },
  'زیادکردن': {
    AppLanguage.badini: 'زیادکرن',
    AppLanguage.arabic: 'إضافة',
    AppLanguage.persian: 'افزودن',
    AppLanguage.english: 'Add',
    AppLanguage.turkish: 'Ekle',
  },
  'کەمکردن': {
    AppLanguage.badini: 'کێمکرن',
    AppLanguage.arabic: 'تقليل',
    AppLanguage.persian: 'کاهش',
    AppLanguage.english: 'Decrease',
    AppLanguage.turkish: 'Azalt',
  },

  // ===== Connect IP =====
  'IPـەکانی هەژمارەکانت:': {
    AppLanguage.badini: 'IPـەکانی هەژمارەکانت:',
    AppLanguage.arabic: 'عناوين IP لحساباتك:',
    AppLanguage.persian: 'آی‌پی حساب‌های شما:',
    AppLanguage.english: 'Your account IPs:',
    AppLanguage.turkish: 'Hesaplarınızın IP adresleri:',
  },
  'ئەو IPـانەی کە خاوەن سیستەم بۆ هەژمارەکانت دروستی کردووە لێرە زیاد بکە (تا 100 IP - بۆ نموونە ئادمێن و کاپتن لەسەر هەمان ئامێر) و پاشان کۆنێکت بکە، ئینجا بە PINـە 5 ژمارەییەکەت چوونە ژوورەوە بکە. هەتا ئەم IPـانە داخل نەکرێن، هیچ هەژمارەیەک لەم ئامێرەدا نابێت بێجگە لە خاوەن سیستەم.': {
    AppLanguage.badini:
        'ئەو IPـانەی کە خاوەن سیستەم بۆ هەژمارەکانت دروستی کردووە لێرە زیاد بکە (تا 100 IP - بۆ نموونە ئادمێن و کاپتن لەسەر هەمان ئامێر) و پاشان کۆنێکت بکە، ئینجا بە PINـە 5 ژمارەییەکەت چوونە ژوورەوە بکە. هەتا ئەم IPـانە داخل نەکرێن، هیچ هەژمارەیەک لەم ئامێرەدا نابێت بێجگە لە خاوەن سیستەم.',
    AppLanguage.arabic:
        'أدخل عناوين IP التي أنشأها صاحب النظام لحساباتك هنا (حتى 100 عنوان - مثلاً المدير والكابتن على نفس الجهاز) ثم اضغط اتصال، وبعدها سجل الدخول بالرمز السري المكون من 5 أرقام. حتى يتم إدخال هذه العناوين، لا يمكن لأي حساب تسجيل الدخول على هذا الجهاز سوى صاحب النظام.',
    AppLanguage.persian:
        'آی‌پی‌هایی که مدیر سیستم برای حساب‌های شما ایجاد کرده را اینجا اضافه کنید (تا 100 آی‌پی - مثلاً مدیر و کاپیتان روی یک دستگاه) سپس روی اتصال بزنید و با رمز 5 رقمی وارد شوید. تا زمانی که این آی‌پی‌ها وارد نشوند، هیچ حسابی به‌جز مدیر سیستم نمی‌تواند وارد این دستگاه شود.',
    AppLanguage.english:
        "Enter the IPs the system owner created for your accounts here (up to 100 IPs - e.g. Admin and Captain on the same device), then press Connect and log in with your 5-digit PIN. Until these IPs are entered, only the system owner can log in on this device.",
    AppLanguage.turkish:
        "Sistem sahibinin hesaplarınız için oluşturduğu IP'leri buraya ekleyin (100 IP'ye kadar - örn. aynı cihazda Yönetici ve Kaptan), ardından Bağlan'a basın ve 5 haneli PIN'inizle giriş yapın. Bu IP'ler girilene kadar bu cihazda yalnızca sistem sahibi giriş yapabilir.",
  },
  'IPـەکە زیادکرا': {
    AppLanguage.badini: 'IPـەکە زیادکرا',
    AppLanguage.arabic: 'تمت إضافة العنوان',
    AppLanguage.persian: 'آی‌پی اضافه شد',
    AppLanguage.english: 'IP added',
    AppLanguage.turkish: 'IP eklendi',
  },
  'ئەم IPـەیە پێشتر زیادکراوە': {
    AppLanguage.badini: 'ئەم IPـەیە پێشتر زیادکراوە',
    AppLanguage.arabic: 'هذا العنوان مضاف مسبقاً',
    AppLanguage.persian: 'این آی‌پی قبلاً اضافه شده است',
    AppLanguage.english: 'This IP was already added',
    AppLanguage.turkish: 'Bu IP zaten eklenmiş',
  },
  'گەیشتە {count} IP - بۆ زیادکردنی زیاتر یەکێک سڕەوە': {
    AppLanguage.badini: 'گەیشتە {count} IP - بۆ زیادکردنی زیاتر یەکێک سڕەوە',
    AppLanguage.arabic: 'وصلت إلى {count} عنوان - لحذف المزيد احذف أحدها أولاً',
    AppLanguage.persian:
        'به {count} آی‌پی رسیدید - برای افزودن بیشتر، یکی را حذف کنید',
    AppLanguage.english: 'Reached {count} IPs - remove one first to add more',
    AppLanguage.turkish:
        '{count} IP sınırına ulaşıldı - daha fazla eklemek için önce birini silin',
  },
  'لانی کەم یەک IP زیاد بکە و پاشان کۆنێکت بکە': {
    AppLanguage.badini: 'لانی کەم یەک IP زیاد بکە و پاشان کۆنێکت بکە',
    AppLanguage.arabic: 'أضف عنواناً واحداً على الأقل ثم اضغط اتصال',
    AppLanguage.persian: 'حداقل یک آی‌پی اضافه کنید سپس روی اتصال بزنید',
    AppLanguage.english: 'Add at least one IP, then press Connect',
    AppLanguage.turkish: "En az bir IP ekleyin, ardından Bağlan'a basın",
  },
  'هیچ IPـێک زیاد نەکراوە - دوگمەی زیادکردن لە خوارەوە بەکاربێنە': {
    AppLanguage.badini:
        'هیچ IPـێک زیاد نەکراوە - دوگمەی زیادکردن لە خوارەوە بەکاربێنە',
    AppLanguage.arabic: 'لم تتم إضافة أي عنوان - استخدم زر الإضافة أدناه',
    AppLanguage.persian:
        'هیچ آی‌پی اضافه نشده است - از دکمه افزودن استفاده کنید',
    AppLanguage.english: 'No IP added yet - use the Add button below',
    AppLanguage.turkish:
        'Henüz IP eklenmedi - aşağıdaki Ekle düğmesini kullanın',
  },
  'پەیوەندی سەرکەوتوو نەبوو - دڵنیابە IPـەکانت ڕاستن و ئامێری سێرڤەرەکە لەسەر هەمان وای-فایە': {
    AppLanguage.badini:
        'پەیوەندی سەرکەوتوو نەبوو - دڵنیابە IPـەکانت ڕاستن و ئامێری سێرڤەرەکە لەسەر هەمان وای-فایە',
    AppLanguage.arabic:
        'فشل الاتصال - تأكد من صحة العناوين وأن جهاز الخادم على نفس شبكة الواي فاي',
    AppLanguage.persian:
        'اتصال ناموفق - مطمئن شوید آی‌پی‌ها درست هستند و دستگاه سرور روی همان وای‌فای است',
    AppLanguage.english:
        'Connection failed - make sure the IPs are correct and the server device is on the same Wi-Fi',
    AppLanguage.turkish:
        "Bağlantı başarısız - IP adreslerinin doğru ve sunucu cihazının aynı Wi-Fi ağında olduğundan emin olun",
  },

  // ===== Admin =====
  'زیادکردنی {role}': {
    AppLanguage.badini: 'زیادکردنی {role}',
    AppLanguage.arabic: 'إضافة {role}',
    AppLanguage.persian: 'افزودن {role}',
    AppLanguage.english: 'Add {role}',
    AppLanguage.turkish: '{role} Ekle',
  },

  // ===== Menu / Food =====
  'زیادکردنی بەش': {
    AppLanguage.badini: 'زیادکردنی بەش',
    AppLanguage.arabic: 'إضافة قسم',
    AppLanguage.persian: 'افزودن بخش',
    AppLanguage.english: 'Add Section',
    AppLanguage.turkish: 'Bölüm Ekle',
  },

  // ===== App =====
  'زیادکردنی بەکارهێنەر': {
    AppLanguage.badini: 'زیادکردنی بەکارهێنەر',
    AppLanguage.arabic: 'إضافة مستخدم',
    AppLanguage.persian: 'افزودن کاربر',
    AppLanguage.english: 'Add User',
    AppLanguage.turkish: 'Kullanıcı Ekle',
  },

  // ===== Menu / Food =====
  'زیادکردنی خواردن': {
    AppLanguage.badini: 'زیادکردنی خواردن',
    AppLanguage.arabic: 'إضافة طعام',
    AppLanguage.persian: 'افزودن غذا',
    AppLanguage.english: 'Add Food',
    AppLanguage.turkish: 'Yiyecek Ekle',
  },

  // ===== Tables =====
  'زیادکردنی مێز': {
    AppLanguage.badini: 'زیادکردنی مێز',
    AppLanguage.arabic: 'إضافة طاولة',
    AppLanguage.persian: 'افزودن میز',
    AppLanguage.english: 'Add Table',
    AppLanguage.turkish: 'Masa Ekle',
  },
  'زیادکردنی مێزی نوێ': {
    AppLanguage.badini: 'زیادکردنی مێزی نوێ',
    AppLanguage.arabic: 'إضافة طاولة جديدة',
    AppLanguage.persian: 'افزودن میز جدید',
    AppLanguage.english: 'Add New Table',
    AppLanguage.turkish: 'Yeni Masa Ekle',
  },

  // ===== App =====
  'سڕینەوە': {
    AppLanguage.badini: 'ژێبرن',
    AppLanguage.arabic: 'حذف',
    AppLanguage.persian: 'حذف',
    AppLanguage.english: 'Delete',
    AppLanguage.turkish: 'Sil',
  },

  'زیادکردنی IP': {
    AppLanguage.badini: 'زیادکردنی IP',
    AppLanguage.arabic: 'إضافة عنوان IP',
    AppLanguage.persian: 'افزودن آی‌پی',
    AppLanguage.english: 'Add IP',
    AppLanguage.turkish: 'IP Ekle',
  },

  'کۆدی تایبەت': {
    AppLanguage.badini: 'کۆدی تایبەت',
    AppLanguage.arabic: 'رمز خاص',
    AppLanguage.persian: 'کد اختصاصی',
    AppLanguage.english: 'Special Code',
    AppLanguage.turkish: 'Özel Kod',
  },
  'کۆدی تایبەت بنووسە یان لە ئادمێن داوا بکە': {
    AppLanguage.badini: 'کۆدی تایبەت بنووسە یان لە ئادمێن داوا بکە',
    AppLanguage.arabic: 'أدخل الرمز الخاص أو اطلبه من الأدمن',
    AppLanguage.persian: 'کد اختصاصی را وارد کنید یا از ادمین بخواهید',
    AppLanguage.english: 'Enter your special code or ask the admin',
    AppLanguage.turkish: 'Özel kodunuzu girin veya yöneticiden isteyin',
  },

  'ژمارەی موشتەرییەکان': {
    AppLanguage.badini: 'ژمارەی موشتەرییەکان',
    AppLanguage.arabic: 'عدد العملاء',
    AppLanguage.persian: 'تعداد مشتریان',
    AppLanguage.english: 'Number of customers',
    AppLanguage.turkish: 'Müşteri sayısı',
  },
  'ژمارەیەکی دروست بنووسە': {
    AppLanguage.badini: 'ژمارەیەکی دروست بنووسە',
    AppLanguage.arabic: 'أدخل رقماً صحيحاً',
    AppLanguage.persian: 'عدد معتبر وارد کنید',
    AppLanguage.english: 'Enter a valid number',
    AppLanguage.turkish: 'Geçerli bir sayı girin',
  },

  // ===== Delivery =====
  'دلیڤەری': {
    AppLanguage.badini: 'دلیڤەری',
    AppLanguage.arabic: 'دليفري',
    AppLanguage.persian: 'پیک',
    AppLanguage.english: 'Delivery',
    AppLanguage.turkish: 'Kurye',
  },
  'زیادکردنی کۆمپانیا': {
    AppLanguage.badini: 'زیادکردنی کۆمپانیا',
    AppLanguage.arabic: 'إضافة شركة',
    AppLanguage.persian: 'افزودن شرکت',
    AppLanguage.english: 'Add Company',
    AppLanguage.turkish: 'Şirket Ekle',
  },
  'ناوی کۆمپانیای دلیڤەری': {
    AppLanguage.badini: 'ناوی کۆمپانیای دلیڤەری',
    AppLanguage.arabic: 'اسم شركة التوصيل',
    AppLanguage.persian: 'نام شرکت پیک',
    AppLanguage.english: 'Delivery company name',
    AppLanguage.turkish: 'Kurye şirketi adı',
  },
  'سڕینەوەی کۆمپانیا': {
    AppLanguage.badini: 'سڕینەوەی کۆمپانیا',
    AppLanguage.arabic: 'حذف الشركة',
    AppLanguage.persian: 'حذف شرکت',
    AppLanguage.english: 'Delete Company',
    AppLanguage.turkish: 'Şirketi Sil',
  },
  'دڵنیایت لە سڕینەوەی {name}؟': {
    AppLanguage.badini: 'دڵنیایت لە سڕینەوەی {name}؟',
    AppLanguage.arabic: 'هل أنت متأكد من حذف {name}؟',
    AppLanguage.persian: 'آیا از حذف {name} مطمئن هستید؟',
    AppLanguage.english: 'Are you sure you want to delete {name}?',
    AppLanguage.turkish: '{name} silmek istediğinize emin misiniz?',
  },
  'هیچ کۆمپانیایەک نییە — زیاد بکە': {
    AppLanguage.badini: 'هیچ کۆمپانیایەک نییە — زیاد بکە',
    AppLanguage.arabic: 'لا توجد شركات — أضف واحدة',
    AppLanguage.persian: 'شرکتی وجود ندارد — اضافه کنید',
    AppLanguage.english: 'No companies yet — add one',
    AppLanguage.turkish: 'Henüz şirket yok — ekleyin',
  },

  // ===== Menu / Food =====
  'سڕینەوەی بەش': {
    AppLanguage.badini: 'سڕینەوەی بەش',
    AppLanguage.arabic: 'حذف القسم',
    AppLanguage.persian: 'حذف بخش',
    AppLanguage.english: 'Delete Section',
    AppLanguage.turkish: 'Bölümü Sil',
  },

  // ===== Admin =====
  'سڕینەوەی بەکارهێنەر': {
    AppLanguage.badini: 'سڕینەوەی بەکارهێنەر',
    AppLanguage.arabic: 'حذف المستخدم',
    AppLanguage.persian: 'حذف کاربر',
    AppLanguage.english: 'Delete User',
    AppLanguage.turkish: 'Kullanıcıyı Sil',
  },

  // ===== Menu / Food =====
  'سڕینەوەی خواردن': {
    AppLanguage.badini: 'سڕینەوەی خواردن',
    AppLanguage.arabic: 'حذف الطعام',
    AppLanguage.persian: 'حذف غذا',
    AppLanguage.english: 'Delete Food',
    AppLanguage.turkish: 'Yiyeceği Sil',
  },

  // ===== Debt =====
  'سڕینەوەی قەرز': {
    AppLanguage.badini: 'سڕینەوەی قەرز',
    AppLanguage.arabic: 'حذف الدين',
    AppLanguage.persian: 'حذف بدهی',
    AppLanguage.english: 'Delete Debt',
    AppLanguage.turkish: 'Borcu Sil',
  },

  // ===== Tables =====
  'سڕینەوەی مێز': {
    AppLanguage.badini: 'سڕینەوەی مێز',
    AppLanguage.arabic: 'حذف الطاولة',
    AppLanguage.persian: 'حذف میز',
    AppLanguage.english: 'Delete Table',
    AppLanguage.turkish: 'Masayı Sil',
  },

  'ناتوانیت مێز بسڕیتەوە چونکە خواردن لەناو مێزەکەدایە. سەرەتا حیسابەکە واسڵ بکە یان خواردنەکە بۆ مێزێکی تر بگوازەوە.': {
    AppLanguage.badini:
        'ناتوانیت مێز بسڕیتەوە چونکە خواردن لەناو مێزەکەدایە. سەرەتا حیسابەکە واسڵ بکە یان خواردنەکە بۆ مێزێکی تر بگوازەوە.',
    AppLanguage.arabic:
        'لا يمكنك حذف هذه الطاولة لأن عليها طلبات. قم أولًا بتسوية الفاتورة أو نقل الطلبات إلى طاولة أخرى.',
    AppLanguage.persian:
        'نمی‌توانید این میز را حذف کنید زیرا روی آن سفارش وجود دارد. ابتدا فاکتور را تسویه کنید یا سفارش‌ها را به میز دیگری منتقل کنید.',
    AppLanguage.english:
        'You cannot delete this table because it has food on it. First settle the bill or move the items to another table.',
    AppLanguage.turkish:
        'Bu masa üzerinde yemek olduğu için silinemez. Önce hesabı kapatın veya yemekleri başka bir masaya taşıyın.',
  },

  // ===== App =====
  'سڕینەوەی هەموو': {
    AppLanguage.badini: 'ژێبرنا هەمی',
    AppLanguage.arabic: 'حذف الكل',
    AppLanguage.persian: 'حذف همه',
    AppLanguage.english: 'Delete All',
    AppLanguage.turkish: 'Tümünü Sil',
  },
  'سیستەم': {
    AppLanguage.badini: 'سیستەم',
    AppLanguage.arabic: 'النظام',
    AppLanguage.persian: 'سیستم',
    AppLanguage.english: 'System',
    AppLanguage.turkish: 'Sistem',
  },
  'حسابی سیستەم': {
    AppLanguage.badini: 'حسابی سیستەم',
    AppLanguage.arabic: 'حساب النظام',
    AppLanguage.persian: 'حساب سیستم',
    AppLanguage.english: 'System account',
    AppLanguage.turkish: 'Sistem hesabı',
  },
  'ڕێفرێش': {
    AppLanguage.badini: 'ڕێفرێش',
    AppLanguage.arabic: 'تحديث',
    AppLanguage.persian: 'تازه‌سازی',
    AppLanguage.english: 'Refresh',
    AppLanguage.turkish: 'Yenile',
  },

  // ===== Tables =====
  'سەرچاوە': {
    AppLanguage.badini: 'سەرچاوە',
    AppLanguage.arabic: 'المصدر',
    AppLanguage.persian: 'مبدأ',
    AppLanguage.english: 'Source',
    AppLanguage.turkish: 'Kaynak',
  },

  // ===== Cashier =====
  'سەرەتا شەفت دەستپێبکە': {
    AppLanguage.badini: 'پێشیڤ شەفت دەستپێبکە',
    AppLanguage.arabic: 'يرجى بدء الشيفت أولاً',
    AppLanguage.persian: 'لطفاً ابتدا شیفت را شروع کنید',
    AppLanguage.english: 'Please start a shift first',
    AppLanguage.turkish: 'Lütfen önce vardiyayı başlatın',
  },

  // ===== App =====
  'سەرەکی': {
    AppLanguage.badini: 'سەرەکی',
    AppLanguage.arabic: 'الرئيسية',
    AppLanguage.persian: 'اصلی',
    AppLanguage.english: 'Main',
    AppLanguage.turkish: 'Ana',
  },

  // ===== Printers =====
  'شوێنی چاپ': {
    AppLanguage.badini: 'شوێنی چاپ',
    AppLanguage.arabic: 'مكان الطباعة',
    AppLanguage.persian: 'محل چاپ',
    AppLanguage.english: 'Print Location',
    AppLanguage.turkish: 'Yazdırma Konumu',
  },

  // ===== Cashier =====
  'شەفت دەستی پێکردووە لە {time}': {
    AppLanguage.badini: 'شەفت دەستی پێکردووە لە {time}',
    AppLanguage.arabic: 'بدأ الشيفت في {time}',
    AppLanguage.persian: 'شیفت در {time} شروع شد',
    AppLanguage.english: 'Shift started at {time}',
    AppLanguage.turkish: 'Vardiya {time} başladı',
  },
  'شەفت چالاکە': {
    AppLanguage.badini: 'شەفت چالاکە',
    AppLanguage.arabic: 'الشيفت نشط',
    AppLanguage.persian: 'شیفت فعال است',
    AppLanguage.english: 'Shift is active',
    AppLanguage.turkish: 'Vardiya aktif',
  },
  'شەفتی کاشێر': {
    AppLanguage.badini: 'شەفتی کاشێر',
    AppLanguage.arabic: 'شيفت الكاشير',
    AppLanguage.persian: 'شیفت صندوقدار',
    AppLanguage.english: 'Cashier Shift',
    AppLanguage.turkish: 'Kasiyer Vardiyası',
  },
  'فرۆش': {
    AppLanguage.badini: 'فرۆتین',
    AppLanguage.arabic: 'بيع',
    AppLanguage.persian: 'فروش',
    AppLanguage.english: 'Sale',
    AppLanguage.turkish: 'Satış',
  },
  'فرۆشتنەکانی ئەمڕۆ': {
    AppLanguage.badini: 'فرۆتینەکانی ئێرۆ',
    AppLanguage.arabic: 'مبيعات اليوم',
    AppLanguage.persian: 'فروش امروز',
    AppLanguage.english: "Today's sales",
    AppLanguage.turkish: 'Bugünkü Satışlar',
  },

  // ===== Debt =====
  'قەرز': {
    AppLanguage.badini: 'قەرز',
    AppLanguage.arabic: 'دين',
    AppLanguage.persian: 'بدهی',
    AppLanguage.english: 'Debt',
    AppLanguage.turkish: 'Borç',
  },
  // «قەرزەکان» splits into the tables still on credit this shift and the debts
  // that were collected during it, so the admin can tell the two apart at a
  // glance instead of reading one flat, unlabelled list.
  'مێزەکانی قەرز': {
    AppLanguage.badini: 'مێزێن قەرزێ',
    AppLanguage.arabic: 'طاولات الدين',
    AppLanguage.persian: 'میزهای بدهی',
    AppLanguage.english: 'Tables on credit',
    AppLanguage.turkish: 'Borçlu masalar',
  },
  'مێزەکانی ماون': {
    AppLanguage.badini: 'مێزێن مان',
    AppLanguage.arabic: 'الطاولات المتبقية',
    AppLanguage.persian: 'میزهای باقی‌مانده',
    AppLanguage.english: 'Remaining tables',
    AppLanguage.turkish: 'Kalan masalar',
  },
  'هاتووە لە شەفتی پێشوو': {
    AppLanguage.badini: 'هاتیە ژ شەفتا بەری نوکە',
    AppLanguage.arabic: 'واردة من الوردية السابقة',
    AppLanguage.persian: 'منتقل‌شده از شیفت قبلی',
    AppLanguage.english: 'Carried over from the previous shift',
    AppLanguage.turkish: 'Önceki vardiyadan devredildi',
  },
  'حیسابکراوە': {
    AppLanguage.badini: 'حیسابکریە',
    AppLanguage.arabic: 'تمت التسوية',
    AppLanguage.persian: 'تسویه شده',
    AppLanguage.english: 'Settled',
    AppLanguage.turkish: 'Hesabı kapatıldı',
  },
  'ماوە': {
    AppLanguage.badini: 'مان',
    AppLanguage.arabic: 'متبقية',
    AppLanguage.persian: 'باقی‌مانده',
    AppLanguage.english: 'Still open',
    AppLanguage.turkish: 'Açık',
  },
  'هیچ مێزێکی ماوە نییە': {
    AppLanguage.badini: 'هیچ مێزێک نەما',
    AppLanguage.arabic: 'لا توجد طاولات متبقية',
    AppLanguage.persian: 'میز باقی‌مانده‌ای وجود ندارد',
    AppLanguage.english: 'No tables were left',
    AppLanguage.turkish: 'Kalan masa yok',
  },
  'قەرزی وەرگیراو': {
    AppLanguage.badini: 'قەرزێ وەرگیرای',
    AppLanguage.arabic: 'ديون محصّلة',
    AppLanguage.persian: 'بدهی وصول‌شده',
    AppLanguage.english: 'Collected debts',
    AppLanguage.turkish: 'Tahsil edilen borçlar',
  },
  'قەرزی سەرەتا': {
    AppLanguage.badini: 'قەرزی سەرەتا',
    AppLanguage.arabic: 'الدين الأولي',
    AppLanguage.persian: 'بدهی اولیه',
    AppLanguage.english: 'Initial Debt',
    AppLanguage.turkish: 'Başlangıç Borcu',
  },
  'قەرزەکان': {
    AppLanguage.badini: 'قەرزەکان',
    AppLanguage.arabic: 'الديون',
    AppLanguage.persian: 'بدهی‌ها',
    AppLanguage.english: 'Debts',
    AppLanguage.turkish: 'Borçlar',
  },

  // ===== App =====
  'لابردن': {
    AppLanguage.badini: 'لابردن',
    AppLanguage.arabic: 'إزالة',
    AppLanguage.persian: 'حذف',
    AppLanguage.english: 'Remove',
    AppLanguage.turkish: 'Kaldır',
  },

  // ===== Printers =====
  'لابردنی چاپکەر': {
    AppLanguage.badini: 'لابردنی چاپکەر',
    AppLanguage.arabic: 'إزالة الطابعة',
    AppLanguage.persian: 'حذف چاپگر',
    AppLanguage.english: 'Remove Printer',
    AppLanguage.turkish: 'Yazıcıyı Kaldır',
  },

  // ===== Tables =====
  'لەسەر مێزێکی گیراو کلیک بکە بۆ سەرچاوە، دواتر مێزی ئامانج هەڵبژێرە': {
    AppLanguage.badini:
        'لەسەر ماسەیەکی گیراو کلیک بکە بۆ سەرچاوە، دواتر ماسا ئامانج هەڵبژێرە',
    AppLanguage.arabic: 'اضغط على طاولة مشغولة كمصدر، ثم اختر الطاولة الهدف',
    AppLanguage.persian:
        'روی میز مشغول به عنوان مبدأ کلیک کنید، سپس میز مقصد را انتخاب کنید',
    AppLanguage.english:
        'Click on an occupied table as source, then select target table',
    AppLanguage.turkish:
        'Kaynak olarak dolu bir masaya tıklayın, ardından hedef masayı seçin',
  },

  // ===== Waiter Home =====
  'موشتەری دانیشتووە': {
    AppLanguage.badini: 'مۆشتەری ڕوونیشتی',
    AppLanguage.arabic: 'زبون جالس',
    AppLanguage.persian: 'مشتری نشسته',
    AppLanguage.english: 'Customer seated',
    AppLanguage.turkish: 'Müşteri oturuyor',
  },

  // ===== Tables =====
  'مێز': {
    AppLanguage.badini: 'ماسە',
    AppLanguage.arabic: 'طاولة',
    AppLanguage.persian: 'میز',
    AppLanguage.english: 'Table',
    AppLanguage.turkish: 'Masa',
  },
  'مێز و کات': {
    AppLanguage.badini: 'ماسە و کات',
    AppLanguage.arabic: 'الطاولة والوقت',
    AppLanguage.persian: 'میز و زمان',
    AppLanguage.english: 'Table & Time',
    AppLanguage.turkish: 'Masa ve Zaman',
  },
  'مێزی': {
    AppLanguage.badini: 'مێزی',
    AppLanguage.arabic: 'طاولة',
    AppLanguage.persian: 'میز',
    AppLanguage.english: 'Table',
    AppLanguage.turkish: 'Masa',
  },
  'مێزی {source} تێکەڵکرا بە {target}': {
    AppLanguage.badini: 'ماسا {source} تێکەڵکرا بە {target}',
    AppLanguage.arabic: 'تم دمج طاولة {source} مع {target}',
    AppLanguage.persian: 'میز {source} با {target} ادغام شد',
    AppLanguage.english: '{source} merged into {target}',
    AppLanguage.turkish: '{source}, {target} ile birleştirildi',
  },
  'مێزی {tableName}': {
    AppLanguage.badini: 'ماسا {tableName}',
    AppLanguage.arabic: 'طاولة {tableName}',
    AppLanguage.persian: 'میز {tableName}',
    AppLanguage.english: 'Table {tableName}',
    AppLanguage.turkish: 'Masa {tableName}',
  },
  'مێزی {tableNumber}': {
    AppLanguage.badini: 'ماسا {tableNumber}',
    AppLanguage.arabic: 'طاولة {tableNumber}',
    AppLanguage.persian: 'میز {tableNumber}',
    AppLanguage.english: 'Table {tableNumber}',
    AppLanguage.turkish: 'Masa {tableNumber}',
  },
  'مێزی {tableNumber} - حیساب': {
    AppLanguage.badini: 'ماسا {tableNumber} - حیساب',
    AppLanguage.arabic: 'طاولة {tableNumber} - فاتورة',
    AppLanguage.persian: 'میز {tableNumber} - صورتحساب',
    AppLanguage.english: 'Table {tableNumber} - Bill',
    AppLanguage.turkish: 'Masa {tableNumber} - Hesap',
  },
  'مێزی {tableNumber} - کاشێر': {
    AppLanguage.badini: 'ماسا {tableNumber} - کاشێر',
    AppLanguage.arabic: 'طاولة {tableNumber} - كاشير',
    AppLanguage.persian: 'میز {tableNumber} - صندوقدار',
    AppLanguage.english: 'Table {tableNumber} - Cashier',
    AppLanguage.turkish: 'Masa {tableNumber} - Kasiyer',
  },
  'مێزی ئامانج هەڵبژێرە (بڕگەکانی سەرچاوە دەگوازرێنە ئەم مێزە)': {
    AppLanguage.badini:
        'ماسا ئامانج هەڵبژێرە (بڕگەکانی سەرچاوە دەڤەگوازرێنە ئەم ماسەیە)',
    AppLanguage.arabic: 'اختر الطاولة الهدف (سيتم نقل عناصر المصدر إليها)',
    AppLanguage.persian:
        'میز مقصد را انتخاب کنید (آیتم‌های مبدأ به این میز منتقل می‌شوند)',
    AppLanguage.english:
        'Select target table (source items will be moved here)',
    AppLanguage.turkish: 'Hedef masayı seçin (kaynak öğeler buraya taşınacak)',
  },
  'مێزی بەتاڵ': {
    AppLanguage.badini: 'ماسەیەکی ڤالا',
    AppLanguage.arabic: 'طاولة فارغة',
    AppLanguage.persian: 'میز خالی',
    AppLanguage.english: 'Empty Table',
    AppLanguage.turkish: 'Boş Masa',
  },
  'مێزێک هەڵبژێرە بۆ بینینی وردەکاری': {
    AppLanguage.badini: 'ماسەکێ هەڵبژێرە بۆ بینینی وردەکاری',
    AppLanguage.arabic: 'اختر طاولة لعرض التفاصيل',
    AppLanguage.persian: 'یک میز برای مشاهده جزئیات انتخاب کنید',
    AppLanguage.english: 'Select a table to view details',
    AppLanguage.turkish: 'Detayları görmek için bir masa seçin',
  },
  'مێزێکی گیراو هەڵبژێرە بۆ تێکەڵکردن': {
    AppLanguage.badini: 'ماسەکێ گیراو هەڵبژێرە بۆ تێکەڵکرن',
    AppLanguage.arabic: 'اختر طاولة مشغولة للدمج',
    AppLanguage.persian: 'یک میز مشغول برای ادغام انتخاب کنید',
    AppLanguage.english: 'Select an occupied table to merge',
    AppLanguage.turkish: 'Birleştirmek için dolu bir masa seçin',
  },
  'مێزە چالاکەکان': {
    AppLanguage.badini: 'ماسە چالاکەکان',
    AppLanguage.arabic: 'الطاولات النشطة',
    AppLanguage.persian: 'میزهای فعال',
    AppLanguage.english: 'Active Tables',
    AppLanguage.turkish: 'Aktif Masalar',
  },
  'مێزەکان': {
    AppLanguage.badini: 'ماسەکان',
    AppLanguage.arabic: 'الطاولات',
    AppLanguage.persian: 'میزها',
    AppLanguage.english: 'Tables',
    AppLanguage.turkish: 'Masalar',
  },
  'مێزەگیراوەکان': {
    AppLanguage.badini: 'مێزەگیراوەکان',
    AppLanguage.arabic: 'الطاولات المشغولة',
    AppLanguage.persian: 'میزهای مشغول',
    AppLanguage.english: 'Occupied Tables',
    AppLanguage.turkish: 'Dolu Masalar',
  },
  'هەموو مێزەکان': {
    AppLanguage.badini: 'هەمی ماسەکان',
    AppLanguage.arabic: 'جميع الطاولات',
    AppLanguage.persian: 'همه میزها',
    AppLanguage.english: 'All Tables',
    AppLanguage.turkish: 'Tüm Masalar',
  },
  'مێزە گیراوەکان': {
    AppLanguage.badini: 'ماسە گیراوەکان',
    AppLanguage.arabic: 'الطاولات المشغولة',
    AppLanguage.persian: 'میزهای مشغول',
    AppLanguage.english: 'Occupied Tables',
    AppLanguage.turkish: 'Dolu Masalar',
  },
  'مێزە بەتاڵەکان': {
    AppLanguage.badini: 'ماسە ڤالاکان',
    AppLanguage.arabic: 'الطاولات الفارغة',
    AppLanguage.persian: 'میزهای خالی',
    AppLanguage.english: 'Empty Tables',
    AppLanguage.turkish: 'Boş Masalar',
  },

  // ===== Menu / Food =====
  'مێنیو': {
    AppLanguage.badini: 'مێنیو',
    AppLanguage.arabic: 'القائمة',
    AppLanguage.persian: 'منو',
    AppLanguage.english: 'Menu',
    AppLanguage.turkish: 'Menü',
  },

  // ===== Waiter Home =====
  'میوان: {guestCount} کەس • کاتی دانیشتن: {seatedTime}': {
    AppLanguage.badini: 'مێڤان: {guestCount} کەس • کاتی دانیشتن: {seatedTime}',
    AppLanguage.arabic: 'الضيوف: {guestCount} شخص • وقت الجلوس: {seatedTime}',
    AppLanguage.persian: 'مهمانان: {guestCount} نفر • زمان نشستن: {seatedTime}',
    AppLanguage.english: 'Guests: {guestCount} • Seated: {seatedTime}',
    AppLanguage.turkish: 'Misafir: {guestCount} kişi • Oturma: {seatedTime}',
  },

  // ===== Orders =====
  'مێژووی داواکارییەکان': {
    AppLanguage.badini: 'مێژووی داواکارییەکان',
    AppLanguage.arabic: 'تاريخ الطلبات',
    AppLanguage.persian: 'تاریخچه سفارشات',
    AppLanguage.english: 'Order History',
    AppLanguage.turkish: 'Sipariş Geçmişi',
  },

  // ===== App =====
  'ناردن': {
    AppLanguage.badini: 'شاندن',
    AppLanguage.arabic: 'إرسال',
    AppLanguage.persian: 'ارسال',
    AppLanguage.english: 'Send',
    AppLanguage.turkish: 'Gönder',
  },

  // ===== Cashier =====
  'ناردن بۆ کاشێر': {
    AppLanguage.badini: 'شاندن بۆ کاشێر',
    AppLanguage.arabic: 'إرسال إلى الكاشير',
    AppLanguage.persian: 'ارسال به صندوقدار',
    AppLanguage.english: 'Send to Cashier',
    AppLanguage.turkish: 'Kasiyere Gönder',
  },

  // ===== App =====
  'ناو': {
    AppLanguage.badini: 'ناڤ',
    AppLanguage.arabic: 'الاسم',
    AppLanguage.persian: 'نام',
    AppLanguage.english: 'Name',
    AppLanguage.turkish: 'Ad',
  },

  // ===== Admin =====
  'ناوی {role}': {
    AppLanguage.badini: 'ناڤی {role}',
    AppLanguage.arabic: 'اسم {role}',
    AppLanguage.persian: 'نام {role}',
    AppLanguage.english: '{role} name',
    AppLanguage.turkish: '{role} adı',
  },

  // ===== App =====
  'ناوی ئاشیا': {
    AppLanguage.badini: 'ناوی ئاشیا',
    AppLanguage.arabic: 'اسم المادة',
    AppLanguage.persian: 'نام کالا',
    AppLanguage.english: 'Item name',
    AppLanguage.turkish: 'Ürün adı',
  },

  // ===== Menu / Food =====
  'ناوی بەش': {
    AppLanguage.badini: 'ناڤی بەش',
    AppLanguage.arabic: 'اسم القسم',
    AppLanguage.persian: 'نام بخش',
    AppLanguage.english: 'Section name',
    AppLanguage.turkish: 'Bölüm adı',
  },
  'ناوی خواردن': {
    AppLanguage.badini: 'ناڤی خوارن',
    AppLanguage.arabic: 'اسم الطعام',
    AppLanguage.persian: 'نام غذا',
    AppLanguage.english: 'Food name',
    AppLanguage.turkish: 'Yiyecek adı',
  },

  // ===== Admin =====
  'ناوی خەرجی': {
    AppLanguage.badini: 'ناڤی خەرجی',
    AppLanguage.arabic: 'اسم المصروف',
    AppLanguage.persian: 'نام هزینه',
    AppLanguage.english: 'Expense name',
    AppLanguage.turkish: 'Gider adı',
  },

  // ===== Tables =====
  'ناوی مێز': {
    AppLanguage.badini: 'ناڤی ماسە',
    AppLanguage.arabic: 'اسم الطاولة',
    AppLanguage.persian: 'نام میز',
    AppLanguage.english: 'Table name',
    AppLanguage.turkish: 'Masa adı',
  },

  // ===== Payment =====
  'نرخ': {
    AppLanguage.badini: 'بەها',
    AppLanguage.arabic: 'السعر',
    AppLanguage.persian: 'قیمت',
    AppLanguage.english: 'Price',
    AppLanguage.turkish: 'Fiyat',
  },
  'نرخ (د.ع)': {
    AppLanguage.badini: 'بەها (د.ع)',
    AppLanguage.arabic: 'السعر (د.ع)',
    AppLanguage.persian: 'قیمت (د.ع)',
    AppLanguage.english: 'Price (IQD)',
    AppLanguage.turkish: 'Fiyat (IQD)',
  },
  'نرخی 100\$:': {
    AppLanguage.badini: 'بەهای 100\$:',
    AppLanguage.arabic: 'سعر 100\$:',
    AppLanguage.persian: 'نرخ 100\$:',
    AppLanguage.english: 'Rate per 100\$:',
    AppLanguage.turkish: '100\$ kuru:',
  },

  // ===== App =====
  'نییە': {
    AppLanguage.badini: 'نیە',
    AppLanguage.arabic: 'لا يوجد',
    AppLanguage.persian: 'وجود ندارد',
    AppLanguage.english: 'None',
    AppLanguage.turkish: 'Yok',
  },

  // ===== Printers =====
  'نەخشەکێشانی خواردن': {
    AppLanguage.badini: 'نەخشەکێشانی خواردن',
    AppLanguage.arabic: 'تخطيط الطعام',
    AppLanguage.persian: 'طرح‌ریزی غذا',
    AppLanguage.english: 'Food Mapping',
    AppLanguage.turkish: 'Yiyecek Eşlemesi',
  },
  'نەخشەکێشانی خواردن بۆ چاپکەر': {
    AppLanguage.badini: 'نەخشەکێشانی خواردن بۆ چاپکەر',
    AppLanguage.arabic: 'تخطيط الطعام للطابعة',
    AppLanguage.persian: 'طرح‌ریزی غذا برای چاپگر',
    AppLanguage.english: 'Food to Printer Mapping',
    AppLanguage.turkish: 'Yiyecek-Yazıcı Eşlemesi',
  },
  'نەخشەکێشانی پۆل': {
    AppLanguage.badini: 'نەخشەکێشانی پۆل',
    AppLanguage.arabic: 'تخطيط الفئة',
    AppLanguage.persian: 'طرح‌ریزی دسته',
    AppLanguage.english: 'Category Mapping',
    AppLanguage.turkish: 'Kategori Eşlemesi',
  },
  'نەخشەکێشانی پۆل بۆ چاپکەر': {
    AppLanguage.badini: 'نەخشەکێشانی پۆل بۆ چاپکەر',
    AppLanguage.arabic: 'تخطيط الفئة للطابعة',
    AppLanguage.persian: 'طرح‌ریزی دسته برای چاپگر',
    AppLanguage.english: 'Category to Printer Mapping',
    AppLanguage.turkish: 'Kategori-Yazıcı Eşlemesi',
  },

  // ===== App =====
  'هاتن': {
    AppLanguage.badini: 'هاتن',
    AppLanguage.arabic: 'دخول',
    AppLanguage.persian: 'ورود',
    AppLanguage.english: 'Login',
    AppLanguage.turkish: 'Giriş',
  },

  // ===== Admin =====
  'هیچ {role}ێک نییە': {
    AppLanguage.badini: 'هیچ {role}ەک نیە',
    AppLanguage.arabic: 'لا يوجد {role}',
    AppLanguage.persian: 'هیچ {role} وجود ندارد',
    AppLanguage.english: 'No {role}',
    AppLanguage.turkish: '{role} yok',
  },

  // ===== App =====
  'هیچ بڕگەیەک نییە': {
    AppLanguage.badini: 'هیچ بڕگەیەک نیە',
    AppLanguage.arabic: 'لا توجد عناصر',
    AppLanguage.persian: 'هیچ آیتمی وجود ندارد',
    AppLanguage.english: 'No items',
    AppLanguage.turkish: 'Hiç öğe yok',
  },

  // ===== Menu / Food =====
  'هیچ بەشێک نییە': {
    AppLanguage.badini: 'هیچ بەشەک نیە',
    AppLanguage.arabic: 'لا توجد أقسام',
    AppLanguage.persian: 'هیچ بخشی وجود ندارد',
    AppLanguage.english: 'No sections',
    AppLanguage.turkish: 'Bölüm yok',
  },

  // ===== App =====
  'هیچ بەکارهێنەرێک نییە': {
    AppLanguage.badini: 'هیچ بکارهێنەرەک نیە',
    AppLanguage.arabic: 'لا يوجد مستخدمون',
    AppLanguage.persian: 'هیچ کاربری وجود ندارد',
    AppLanguage.english: 'No users',
    AppLanguage.turkish: 'Kullanıcı yok',
  },

  // ===== Backup =====
  'هیچ بەکاپێک نییە': {
    AppLanguage.badini: 'هیچ بەکاپەک نیە',
    AppLanguage.arabic: 'لا توجد نسخ احتياطية',
    AppLanguage.persian: 'هیچ پشتیبان وجود ندارد',
    AppLanguage.english: 'No backups',
    AppLanguage.turkish: 'Yedek yok',
  },

  // ===== Menu / Food =====
  'هیچ جۆرە خواردنێک تۆمار نەکراوە': {
    AppLanguage.badini: 'هیچ جۆرە خواردنێک تۆمار نەکراوە',
    AppLanguage.arabic: 'لم يتم تسجيل أي نوع طعام',
    AppLanguage.persian: 'هیچ نوع غذایی ثبت نشده است',
    AppLanguage.english: 'No food type registered',
    AppLanguage.turkish: 'Hiç yiyecek türü kaydedilmedi',
  },
  'هیچ خواردنێک تۆمارنەکراوە': {
    AppLanguage.badini: 'هیچ خواردنێک تۆمارنەکراوە',
    AppLanguage.arabic: 'لم يتم تسجيل أي طعام',
    AppLanguage.persian: 'هیچ غذایی ثبت نشده است',
    AppLanguage.english: 'No food registered',
    AppLanguage.turkish: 'Hiç yiyecek kaydedilmedi',
  },
  'هیچ خواردنێک نییە': {
    AppLanguage.badini: 'هیچ خوارنەک نیە',
    AppLanguage.arabic: 'لا يوجد طعام',
    AppLanguage.persian: 'هیچ غذایی وجود ندارد',
    AppLanguage.english: 'No food',
    AppLanguage.turkish: 'Yiyecek yok',
  },
  'هیچ خواردنێک هەڵنەبژێردراوە': {
    AppLanguage.badini: 'هیچ خواردنێک هەڵنەبژێردراوە',
    AppLanguage.arabic: 'لم يتم اختيار أي طعام',
    AppLanguage.persian: 'هیچ غذایی انتخاب نشده است',
    AppLanguage.english: 'No food selected',
    AppLanguage.turkish: 'Hiç yiyecek seçilmedi',
  },

  // ===== Admin =====
  'هیچ خەرجی و قەرزێک نییە': {
    AppLanguage.badini: 'هیچ خەرجی و قەرزەک نیە',
    AppLanguage.arabic: 'لا توجد مصروفات أو ديون',
    AppLanguage.persian: 'هیچ هزینه یا بدهی وجود ندارد',
    AppLanguage.english: 'No expenses or debts',
    AppLanguage.turkish: 'Gider veya borç yok',
  },
  'هیچ خەرجییەک نییە': {
    AppLanguage.badini: 'هیچ خەرجیەک نیە',
    AppLanguage.arabic: 'لا توجد مصروفات',
    AppLanguage.persian: 'هیچ هزینه‌ای وجود ندارد',
    AppLanguage.english: 'No expenses',
    AppLanguage.turkish: 'Gider yok',
  },
  'هیچ گەڕانەوەی خەرجی نییە': {
    AppLanguage.badini: 'هیچ گەڕانەوەی خەرجی نیە',
    AppLanguage.arabic: 'لا توجد مصروفات مرتجعة',
    AppLanguage.persian: 'هیچ بازگشت هزینه‌ای وجود ندارد',
    AppLanguage.english: 'No returned expenses',
    AppLanguage.turkish: 'İade edilen gider yok',
  },
  'هیچ ئەنجامێک نەدۆزرایەوە': {
    AppLanguage.badini: 'هیچ ئەنجام نەهاتنە دیتن',
    AppLanguage.arabic: 'لا توجد نتائج',
    AppLanguage.persian: 'نتیجه‌ای یافت نشد',
    AppLanguage.english: 'No results found',
    AppLanguage.turkish: 'Sonuç bulunamadı',
  },

  // ===== Orders =====
  'هیچ داواکاریەک نییە': {
    AppLanguage.badini: 'هیچ داواکاریەک نیە',
    AppLanguage.arabic: 'لا توجد طلبات',
    AppLanguage.persian: 'هیچ سفارشی وجود ندارد',
    AppLanguage.english: 'No orders',
    AppLanguage.turkish: 'Sipariş yok',
  },
  'هیچ داواکاریەک نەدۆزرایەوە': {
    AppLanguage.badini: 'هیچ داواکاریەک نەدۆزرایەوە',
    AppLanguage.arabic: 'لم يتم العثور على أي طلب',
    AppLanguage.persian: 'هیچ سفارشی پیدا نشد',
    AppLanguage.english: 'No order found',
    AppLanguage.turkish: 'Sipariş bulunamadı',
  },

  // ===== Cashier =====
  'هیچ شەفتێک نییە': {
    AppLanguage.badini: 'هیچ شەفتەک نیە',
    AppLanguage.arabic: 'لا يوجد شيفت',
    AppLanguage.persian: 'هیچ شیفتی وجود ندارد',
    AppLanguage.english: 'No shift',
    AppLanguage.turkish: 'Vardiya yok',
  },

  // ===== Debt =====
  'هیچ قەرزێک نییە': {
    AppLanguage.badini: 'هیچ قەرزەک نیە',
    AppLanguage.arabic: 'لا توجد ديون',
    AppLanguage.persian: 'هیچ بدهی وجود ندارد',
    AppLanguage.english: 'No debts',
    AppLanguage.turkish: 'Borç yok',
  },

  // ===== Tables =====
  'هیچ مێزێکی بەتاڵ نییە': {
    AppLanguage.badini: 'هیچ ماسەیەکی ڤالا نینە',
    AppLanguage.arabic: 'لا توجد طاولات فارغة',
    AppLanguage.persian: 'هیچ میز خالی وجود ندارد',
    AppLanguage.english: 'No empty tables',
    AppLanguage.turkish: 'Boş masa yok',
  },
  'هیچ مێزێکی چالاک نییە': {
    AppLanguage.badini: 'هیچ ماسەیەکی چالاک نینە',
    AppLanguage.arabic: 'لا توجد طاولات نشطة',
    AppLanguage.persian: 'هیچ میز فعالی وجود ندارد',
    AppLanguage.english: 'No active tables',
    AppLanguage.turkish: 'Aktif masa yok',
  },
  'ئاگەدارکردنەوەی مێز': {
    AppLanguage.badini: 'ئاگەدارکردنەوەی ماسە',
    AppLanguage.arabic: 'إشعارات الطاولة',
    AppLanguage.persian: 'اعلان میز',
    AppLanguage.english: 'Table Notifications',
    AppLanguage.turkish: 'Masa Bildirimleri',
  },
  'هیچ ئاگەدارکردنەوەیەک نییە': {
    AppLanguage.badini: 'هیچ ئاگەدارکردنەوەیەک نیە',
    AppLanguage.arabic: 'لا توجد إشعارات',
    AppLanguage.persian: 'اعلانی وجود ندارد',
    AppLanguage.english: 'No notifications',
    AppLanguage.turkish: 'Bildirim yok',
  },
  'زەنگۆڵە': {
    AppLanguage.badini: 'زەنگۆڵە',
    AppLanguage.arabic: 'جرس',
    AppLanguage.persian: 'زنگ',
    AppLanguage.english: 'Bell',
    AppLanguage.turkish: 'Zil',
  },
  'بینین': {
    AppLanguage.badini: 'بینین',
    AppLanguage.arabic: 'عرض',
    AppLanguage.persian: 'مشاهده',
    AppLanguage.english: 'View',
    AppLanguage.turkish: 'Görüntüle',
  },
  'هیچ مێزێکی گیراو نییە': {
    AppLanguage.badini: 'هیچ ماسەیەکی گیراو نینە',
    AppLanguage.arabic: 'لا توجد طاولات مشغولة',
    AppLanguage.persian: 'هیچ میز مشغولی وجود ندارد',
    AppLanguage.english: 'No occupied tables',
    AppLanguage.turkish: 'Dolu masa yok',
  },

  // ===== Printers =====
  'هیچ پرینتەری کاشێر نەدۆزرایەوە': {
    AppLanguage.badini: 'هیچ پرینتەری کاشێر نەدۆزرایەوە',
    AppLanguage.arabic: 'لم يتم العثور على طابعة كاشير',
    AppLanguage.persian: 'هیچ چاپگر صندوقداری پیدا نشد',
    AppLanguage.english: 'No cashier printer found',
    AppLanguage.turkish: 'Kasiyer yazıcısı bulunamadı',
  },
  'هیچ چاپکەرێک ڕێکنەخراوە': {
    AppLanguage.badini: 'هیچ چاپکەرێک ڕێکنەخراوە',
    AppLanguage.arabic: 'لم يتم إعداد أية طابعة',
    AppLanguage.persian: 'هیچ چاپگری تنظیم نشده است',
    AppLanguage.english: 'No printer configured',
    AppLanguage.turkish: 'Hiç yazıcı yapılandırılmamış',
  },

  // ===== Orders =====
  'هیچ ڕەفزێک تۆمارنەکراوە': {
    AppLanguage.badini: 'هیچ ڕەفزێک تۆمارنەکراوە',
    AppLanguage.arabic: 'لم يتم تسجيل أي رفض',
    AppLanguage.persian: 'هیچ ردی ثبت نشده است',
    AppLanguage.english: 'No rejections recorded',
    AppLanguage.turkish: 'Hiç reddetme kaydedilmedi',
  },

  // ===== App =====
  'هیچ کڕینێک نییە': {
    AppLanguage.badini: 'هیچ کڕینەک نیە',
    AppLanguage.arabic: 'لا توجد مشتريات',
    AppLanguage.persian: 'هیچ خریدی وجود ندارد',
    AppLanguage.english: 'No purchases',
    AppLanguage.turkish: 'Satın alma yok',
  },

  // ===== Backup =====
  'هیچ گەڕاندنەوەیەک نییە': {
    AppLanguage.badini: 'هیچ گەڕاندنەوەیەک نیە',
    AppLanguage.arabic: 'لا توجد استعادة',
    AppLanguage.persian: 'هیچ بازیابی وجود ندارد',
    AppLanguage.english: 'No restore',
    AppLanguage.turkish: 'Geri yükleme yok',
  },

  // ===== App =====
  'هەموو': {
    AppLanguage.badini: 'هەمی',
    AppLanguage.arabic: 'الكل',
    AppLanguage.persian: 'همه',
    AppLanguage.english: 'All',
    AppLanguage.turkish: 'Tümü',
  },
  'هەوڵدنەوە': {
    AppLanguage.badini: 'هەوڵدنەوە',
    AppLanguage.arabic: 'إعادة المحاولة',
    AppLanguage.persian: 'تلاش مجدد',
    AppLanguage.english: 'Retry',
    AppLanguage.turkish: 'Tekrar Dene',
  },
  'هەڵبژێردراو': {
    AppLanguage.badini: 'هەڵبژارتی',
    AppLanguage.arabic: 'مختار',
    AppLanguage.persian: 'انتخاب شده',
    AppLanguage.english: 'Selected',
    AppLanguage.turkish: 'Seçili',
  },
  'هەڵنەبژێردراوە': {
    AppLanguage.badini: 'هەڵنەبژێردراوە',
    AppLanguage.arabic: 'غير مختار',
    AppLanguage.persian: 'انتخاب نشده',
    AppLanguage.english: 'Not selected',
    AppLanguage.turkish: 'Seçili değil',
  },

  // ===== Debt =====
  'واسڵ کردن': {
    AppLanguage.badini: 'واسڵکرن',
    AppLanguage.arabic: 'تسوية',
    AppLanguage.persian: 'تسویه',
    AppLanguage.english: 'Settle',
    AppLanguage.turkish: 'Kapat',
  },
  'واسڵکردن': {
    AppLanguage.badini: 'واسڵکرن',
    AppLanguage.arabic: 'تسوية',
    AppLanguage.persian: 'تسویه',
    AppLanguage.english: 'Settle',
    AppLanguage.turkish: 'Kapat',
  },
  'واسڵکردنی قەرز': {
    AppLanguage.badini: 'واسڵکردنی قەرز',
    AppLanguage.arabic: 'تسوية الدين',
    AppLanguage.persian: 'تسویه بدهی',
    AppLanguage.english: 'Settle Debt',
    AppLanguage.turkish: 'Borcu Kapat',
  },

  // ===== Cash payment =====
  'واسڵ کردنی پارە': {
    AppLanguage.badini: 'واسڵکرنا پارەی',
    AppLanguage.arabic: 'تسوية الدفع',
    AppLanguage.persian: 'تسویه پرداخت',
    AppLanguage.english: 'Settle Payment',
    AppLanguage.turkish: 'Ödemeyi Kapat',
  },
  'بڕی حیساب': {
    AppLanguage.badini: 'بڕی حیساب',
    AppLanguage.arabic: 'مبلغ الفاتورة',
    AppLanguage.persian: 'مبلغ صورتحساب',
    AppLanguage.english: 'Bill amount',
    AppLanguage.turkish: 'Hesap tutarı',
  },
  'بڕی پارەی وەرگیراو': {
    AppLanguage.badini: 'بڕی پارەی وەرگیراو',
    AppLanguage.arabic: 'المبلغ النقدي المستلم',
    AppLanguage.persian: 'مبلغ نقدی دریافت‌شده',
    AppLanguage.english: 'Cash received',
    AppLanguage.turkish: 'Alınan nakit',
  },
  'بڕی پارەی پێدراو': {
    AppLanguage.badini: 'بڕی پارەی پێدراو',
    AppLanguage.arabic: 'المبلغ النقدي المدفوع',
    AppLanguage.persian: 'مبلغ نقدی پرداخت‌شده',
    AppLanguage.english: 'Cash given',
    AppLanguage.turkish: 'Verilen nakit',
  },
  'بڕی باقی': {
    AppLanguage.badini: 'بڕی باقی',
    AppLanguage.arabic: 'الباقي',
    AppLanguage.persian: 'باقی‌مانده',
    AppLanguage.english: 'Change',
    AppLanguage.turkish: 'Para üstü',
  },
  'بڕی حیساب ڕێکە': {
    AppLanguage.badini: 'بڕی حیساب ڕێکە',
    AppLanguage.arabic: 'مبلغ الفاتورة مطابق تماماً',
    AppLanguage.persian: 'مبلغ صورتحساب دقیقاً برابر است',
    AppLanguage.english: 'Exact bill amount',
    AppLanguage.turkish: 'Hesap tutarı tam',
  },
  'بڕی پارەکە کەمترە لە حیساب': {
    AppLanguage.badini: 'بڕی پارەی کێمترە ژ حیسابێ',
    AppLanguage.arabic: 'المبلغ النقدي أقل من الفاتورة',
    AppLanguage.persian: 'مبلغ نقدی کمتر از صورتحساب است',
    AppLanguage.english: 'Cash is less than the bill',
    AppLanguage.turkish: 'Nakit, hesaptan az',
  },
  'بڕی پێویستە بگەڕێتەوە بۆ موشتەری': {
    AppLanguage.badini: 'بڕی پێویستە بگەڕێتەوە بۆ موشتەری',
    AppLanguage.arabic: 'المبلغ الواجب إرجاعه للعميل',
    AppLanguage.persian: 'مبلغی که باید به مشتری برگردانده شود',
    AppLanguage.english: 'Amount to return to the customer',
    AppLanguage.turkish: 'Müşteriye iade edilecek tutar',
  },
  'بڕی پارە تەواو نیە': {
    AppLanguage.badini: 'بڕی پارە تەواو نیە',
    AppLanguage.arabic: 'المبلغ النقدي غير مكتمل',
    AppLanguage.persian: 'مبلغ نقدی کامل نیست',
    AppLanguage.english: 'Cash amount is incomplete',
    AppLanguage.turkish: 'Nakit tutarı eksik',
  },

  // ===== Payment =====
  'وردەکاری پارەدان': {
    AppLanguage.badini: 'وردەکاری پارەدان',
    AppLanguage.arabic: 'تفاصيل الدفع',
    AppLanguage.persian: 'جزئیات پرداخت',
    AppLanguage.english: 'Payment Details',
    AppLanguage.turkish: 'Ödeme Detayları',
  },

  // ===== Admin =====
  'وشەی نهێنی': {
    AppLanguage.badini: 'وشەی نهێنی',
    AppLanguage.arabic: 'كلمة المرور',
    AppLanguage.persian: 'رمز عبور',
    AppLanguage.english: 'Password',
    AppLanguage.turkish: 'Şifre',
  },
  'وشەی نهێنی (٤ ژمارە)': {
    AppLanguage.badini: 'وشەی نهێنی (٤ ژمارە)',
    AppLanguage.arabic: 'كلمة المرور (4 أرقام)',
    AppLanguage.persian: 'رمز عبور (4 رقمی)',
    AppLanguage.english: 'PIN code (4 digits)',
    AppLanguage.turkish: 'Şifre (4 haneli)',
  },
  'وشەی نهێنی نوێ بۆ {name}': {
    AppLanguage.badini: 'وشەی نهێنی نوێ بۆ {name}',
    AppLanguage.arabic: 'كلمة مرور جديدة لـ {name}',
    AppLanguage.persian: 'رمز عبور جدید برای {name}',
    AppLanguage.english: 'New password for {name}',
    AppLanguage.turkish: '{name} için yeni şifre',
  },
  'وشەی نهێنی هەڵەیە': {
    AppLanguage.badini: 'وشەی نهێنی هەڵەیە',
    AppLanguage.arabic: 'كلمة المرور خاطئة',
    AppLanguage.persian: 'رمز عبور اشتباه است',
    AppLanguage.english: 'Wrong password',
    AppLanguage.turkish: 'Yanlış şifre',
  },

  // ===== App =====
  'وێنە/ئایکۆن': {
    AppLanguage.badini: 'وێنە/ئایکۆن',
    AppLanguage.arabic: 'صورة/أيقونة',
    AppLanguage.persian: 'تصویر/آیکون',
    AppLanguage.english: 'Image/Icon',
    AppLanguage.turkish: 'Resim/Simge',
  },
  'وەسڵ (نەقد)': {
    AppLanguage.badini: 'وەسڵ (نەقد)',
    AppLanguage.arabic: 'إيصال (نقدي)',
    AppLanguage.persian: 'رسید (نقد)',
    AppLanguage.english: 'Receipt (Cash)',
    AppLanguage.turkish: 'Fiş (Nakit)',
  },

  // ===== Admin =====
  'وەیتەر': {
    AppLanguage.badini: 'وەیتەر',
    AppLanguage.arabic: 'نادل',
    AppLanguage.persian: 'پیشخدمت',
    AppLanguage.english: 'Waiter',
    AppLanguage.turkish: 'Garson',
  },
  'کاپتن': {
    AppLanguage.badini: 'کاپتن',
    AppLanguage.arabic: 'كابتن',
    AppLanguage.persian: 'کاپیتان',
    AppLanguage.english: 'Captain',
    AppLanguage.turkish: 'Kaptan',
  },
  // ===== One captain to a table =====
  'مێز بەسەردەستە': {
    AppLanguage.badini: 'مێز بەسەردەستە',
    AppLanguage.arabic: 'طاولة مشغولة',
    AppLanguage.persian: 'میز اشغال‌شده',
    AppLanguage.english: 'Table in use',
    AppLanguage.turkish: 'Meşgul masa',
  },
  'مێزی {name} لەلایەن کاپتنەوە گرتەیەتەوە': {
    AppLanguage.badini: 'مێزی {name} لەلایەن کاپتنەوە گرتەیەتەوە',
    AppLanguage.arabic: 'الطاولة {name} محجوزة من قبل الكابتن',
    AppLanguage.persian: 'میز {name} توسط کاپیتان اشغال شده است',
    AppLanguage.english: 'Table {name} is taken by a captain',
    AppLanguage.turkish: '{name} numarası masa kaptan tarafından alınmış',
  },
  'بۆ ئەوەی بچیتە ناو مێزەکە، پێویستە کاپتنەکە لە مێزەکە دەربکەیت': {
    AppLanguage.badini:
        'بۆ ئەوەی بچیتە ناو مێزەکە، پێویستە کاپتنەکە لە مێزەکە دەربکەیت',
    AppLanguage.arabic: 'للدخول إلى الطاولة، عليك إخراج الكابتن منها',
    AppLanguage.persian: 'برای ورود به میز، باید کاپیتان را از میز خارج کنید',
    AppLanguage.english: 'To enter the table, the captain must leave it first',
    AppLanguage.turkish:
        'Masanın girilmesi için kaptanın masadan çıkması gerekir',
  },
  'کاپتنی مێزەکە': {
    AppLanguage.badini: 'کاپتنی مێزەکە',
    AppLanguage.arabic: 'كابتن الطاولة',
    AppLanguage.persian: 'کاپیتان میز',
    AppLanguage.english: 'Table captain',
    AppLanguage.turkish: 'Masa kaptanı',
  },
  'ناسەرەوە': {
    AppLanguage.badini: 'ناسەرەوە',
    AppLanguage.arabic: 'بدون اسم',
    AppLanguage.persian: 'بدون نام',
    AppLanguage.english: 'Unnamed',
    AppLanguage.turkish: 'İsimsiz',
  },
  'لە {time}ەوە': {
    AppLanguage.badini: 'لە {time}ەوە',
    AppLanguage.arabic: 'منذ {time}',
    AppLanguage.persian: 'از {time}',
    AppLanguage.english: 'since {time}',
    AppLanguage.turkish: '{time} beri',
  },
  '{h} کاتژمێر': {
    AppLanguage.badini: '{h} کاتژمێر',
    AppLanguage.arabic: '{h} ساعة',
    AppLanguage.persian: '{h} ساعت',
    AppLanguage.english: '{h} h',
    AppLanguage.turkish: '{h} saat',
  },
  '{m} خولەک': {
    AppLanguage.badini: '{m} خولەک',
    AppLanguage.arabic: '{m} دقيقة',
    AppLanguage.persian: '{m} دقیقه',
    AppLanguage.english: '{m} min',
    AppLanguage.turkish: '{m} dakika',
  },
  'چەند چرکەیەک': {
    AppLanguage.badini: 'چەند چرکەیەک',
    AppLanguage.arabic: 'بضع ثوانٍ',
    AppLanguage.persian: 'چند ثانیه',
    AppLanguage.english: 'a few seconds',
    AppLanguage.turkish: 'birkaç saniye',
  },
  'دەرکردنی {name} لە مێزەکە': {
    AppLanguage.badini: 'دەرکردنی {name} لە مێزەکە',
    AppLanguage.arabic: 'إخراج {name} من الطاولة',
    AppLanguage.persian: 'خارج کردن {name} از میز',
    AppLanguage.english: 'Remove {name} from the table',
    AppLanguage.turkish: '{name} kişiyi masadan çıkar',
  },
  'دەرکردن...': {
    AppLanguage.badini: 'دەرکردن...',
    AppLanguage.arabic: 'جارٍ الإخراج...',
    AppLanguage.persian: 'در حال خارج کردن...',
    AppLanguage.english: 'Removing...',
    AppLanguage.turkish: 'Çıkarılıyor...',
  },
  'گەڕانەوە بۆ مێزەکان': {
    AppLanguage.badini: 'گەڕانەوە بۆ مێزەکان',
    AppLanguage.arabic: 'العودة إلى الطاولات',
    AppLanguage.persian: 'بازگشت به میزها',
    AppLanguage.english: 'Back to tables',
    AppLanguage.turkish: 'Masalara dön',
  },
  '{name} لە مێزی {table} دەرکرایتەوە': {
    AppLanguage.badini: '{name} لە مێزی {table} دەرکرایتەوە',
    AppLanguage.arabic: 'تم إخراج {name} من الطاولة {table}',
    AppLanguage.persian: '{name} از میز {table} خارج شد',
    AppLanguage.english: '{name} was removed from table {table}',
    AppLanguage.turkish: '{name}, {table} masasından çıkarıldı',
  },
  'دەرکردن سەرکەوتوو نەبوو، دووبارە هەوڵ بدەوە': {
    AppLanguage.badini: 'دەرکردن سەرکەوتوو نەبوو، دووبارە هەوڵ بدەوە',
    AppLanguage.arabic: 'فشل الإخراج، حاول مرة أخرى',
    AppLanguage.persian: 'خارج کردن انجام نشد، دوباره تلاش کنید',
    AppLanguage.english: 'Could not remove them, please try again',
    AppLanguage.turkish: 'Çıkarılamadı, lütfen tekrar deneyin',
  },
  'لە مێزەکە دەرکرایتەوە': {
    AppLanguage.badini: 'لە مێزەکە دەرکرایتەوە',
    AppLanguage.arabic: 'تم إخراجك من الطاولة',
    AppLanguage.persian: 'از میز خارج شدید',
    AppLanguage.english: 'You were removed from the table',
    AppLanguage.turkish: 'Masadan çıkarıldınız',
  },
  'کاپتنی دیکە {name} مێزەکەی لە دەستت دا، بۆیە ئیتر ناتوانیت لەسەر کار بکەیت.': {
    AppLanguage.badini:
        'کاپتنی دیکە {name} مێزەکەی لە دەستت دا، بۆیە ئیتر ناتوانیت لەسەر کار بکەیت.',
    AppLanguage.arabic:
        'الكابتن {name} أخذ الطاولة منك، لم تعد قادراً على العمل عليها',
    AppLanguage.persian:
        'کاپیتان {name} میز را از شما گرفت، دیگر نمی‌توانید روی آن کار کنید',
    AppLanguage.english:
        'Captain {name} has taken over this table, so you can no longer work on it',
    AppLanguage.turkish:
        'Kaptan {name} masayı devraldı, artık bu masa üzerinde çalışamazsınız',
  },
  'ئەم مێزە لای کاپتن یان لای کاشێر کراوەیە': {
    AppLanguage.badini: 'ئەم مێزە لای کاپتن یان لای کاشێر کراوەیە',
    AppLanguage.arabic: 'هذه الطاولة مع كابتن أو كاشير',
    AppLanguage.persian: 'این میز با کاپیتان یا کاشیر است',
    AppLanguage.english: 'This table is with a captain or a cashier',
    AppLanguage.turkish: 'Bu masa bir kaptanda veya kasiyerde',
  },
  'ببورە {role} {name} لەناو مێزەکەدایە، کاتێکیتر هەوڵ بدەوە': {
    AppLanguage.badini:
        'ببورە {role} {name} لەناو مێزەکەدایە، کاتێکیتر هەوڵ بدەوە',
    AppLanguage.arabic:
        'عذراً، {role} {name} داخل هذه الطاولة، حاول مرة أخرى لاحقاً',
    AppLanguage.persian:
        'ببخشید، {role} {name} در این میز است، بعداً دوباره تلاش کنید',
    AppLanguage.english:
        'Sorry, {role} {name} is in this table, please try again later',
    AppLanguage.turkish:
        'Üzgünüz, {role} {name} bu masada, lütfen daha sonra tekrar deneyin',
  },
  'باشە، تێدەگەم': {
    AppLanguage.badini: 'باشە، تێدەگەم',
    AppLanguage.arabic: 'حسناً، فهمت',
    AppLanguage.persian: 'باشه، متوجه شدم',
    AppLanguage.english: 'OK, I understand',
    AppLanguage.turkish: 'Tamam, anladım',
  },

  // ===== Dollar rate (set by the admin, read by every cashier) =====
  'نرخی دۆلار': {
    AppLanguage.badini: 'نرخی دۆلار',
    AppLanguage.arabic: 'سعر الدولار',
    AppLanguage.persian: 'نرخ دلار',
    AppLanguage.english: 'Dollar rate',
    AppLanguage.turkish: 'Dolar kuru',
  },
  'ئادمێن نرخی دۆلاری داناوە': {
    AppLanguage.badini: 'ئادمێن نرخی دۆلاری داناوە',
    AppLanguage.arabic: 'قام المدير بتحديد سعر الدولار',
    AppLanguage.persian: 'مدیر نرخ دلار را تعیین کرده است',
    AppLanguage.english: 'The manager has set the dollar rate',
    AppLanguage.turkish: 'Müdür dolar kurunu belirledi',
  },
  '{dollars}\$ بەرامبەر بە دیناری عیراقی {iqd}': {
    AppLanguage.badini: '{dollars}\$ بەرامبەر بە دیناری عیراقی {iqd}',
    AppLanguage.arabic: '{dollars}\$ مقابل {iqd} دينار عراقي',
    AppLanguage.persian: '{dollars}\$ در برابر {iqd} دینار عراقی',
    AppLanguage.english: '{dollars}\$ equals {iqd} Iraqi dinars',
    AppLanguage.turkish: '{dollars}\$ karşılığında {iqd} Irak dinarı',
  },
  'چەند دۆلار': {
    AppLanguage.badini: 'چەند دۆلار',
    AppLanguage.arabic: 'كم دولاراً',
    AppLanguage.persian: 'چند دلار',
    AppLanguage.english: 'How many dollars',
    AppLanguage.turkish: 'Kaç dolar',
  },
  'چەند دیناری عیراقی': {
    AppLanguage.badini: 'چەند دیناری عیراقی',
    AppLanguage.arabic: 'كم ديناراً عراقياً',
    AppLanguage.persian: 'چند دینار عراقی',
    AppLanguage.english: 'How many Iraqi dinars',
    AppLanguage.turkish: 'Kaç Irak dinarı',
  },
  'نرخەکە بنووسە بەو شێوەیە کە دەتەوێت پیشان بدرێت - هەموو کاشێرەکان ئەم ژمارەیە دەبینن': {
    AppLanguage.badini:
        'نرخەکە بنووسە بەو شێوەیە کە دەتەوێت پیشان بدرێت - هەموو کاشێرەکان ئەم ژمارەیە دەبینن',
    AppLanguage.arabic:
        'اكتب السعر بالشكل الذي تريد عرضه - جميع الكاشيرين سيرون هذا الرقم',
    AppLanguage.persian:
        'نرخ را همان‌طور که می‌خواهید نمایش داده شود بنویسید - همه صندوق‌داران این عدد را می‌بینند',
    AppLanguage.english:
        'Type the rate exactly as you want it shown - every cashier will see this number',
    AppLanguage.turkish:
        'Kuru tam olarak görünmesini istediğiniz gibi yazın - tüm kasiyerler bu sayıyı görecek',
  },
  'ئەوەی دەبینرێت': {
    AppLanguage.badini: 'ئەوەی دەبینرێت',
    AppLanguage.arabic: 'ما سيظهر',
    AppLanguage.persian: 'آنچه نمایش داده می‌شود',
    AppLanguage.english: 'What will be shown',
    AppLanguage.turkish: 'Görünecek olan',
  },
  'ژمارەکان بنووسە تا پێشبینی دەربکەوێت': {
    AppLanguage.badini: 'ژمارەکان بنووسە تا پێشبینی دەربکەوێت',
    AppLanguage.arabic: 'اكتب الأرقام لمعاينة النتيجة',
    AppLanguage.persian: 'برای دیدن نتیجه اعداد را بنویسید',
    AppLanguage.english: 'Type the numbers to see a preview',
    AppLanguage.turkish: 'Önizleme için sayıları yazın',
  },
  'ژمارەیەکی دروست بنووسە (بۆ نموونە 100)': {
    AppLanguage.badini: 'ژمارەیەکی دروست بنووسە (بۆ نموونە 100)',
    AppLanguage.arabic: 'أدخل رقماً صحيحاً (مثال: 100)',
    AppLanguage.persian: 'یک عدد درست وارد کنید (مثال: 100)',
    AppLanguage.english: 'Enter a valid number (for example 100)',
    AppLanguage.turkish: 'Geçerli bir sayı girin (örneğin 100)',
  },
  'ژمارەیەکی دروست بنووسە (بۆ نموونە 150,000)': {
    AppLanguage.badini: 'ژمارەیەکی دروست بنووسە (بۆ نموونە 150,000)',
    AppLanguage.arabic: 'أدخل رقماً صحيحاً (مثال: 150,000)',
    AppLanguage.persian: 'یک عدد درست وارد کنید (مثال: 150,000)',
    AppLanguage.english: 'Enter a valid number (for example 150,000)',
    AppLanguage.turkish: 'Geçerli bir sayı girin (örneğin 150,000)',
  },
  'پاشەکەوتکرا': {
    AppLanguage.badini: 'پاشەکەوتکرا',
    AppLanguage.arabic: 'تم الحفظ',
    AppLanguage.persian: 'ذخیره شد',
    AppLanguage.english: 'Saved',
    AppLanguage.turkish: 'Kaydedildi',
  },
  'باشە': {
    AppLanguage.badini: 'باشە',
    AppLanguage.arabic: 'حسناً',
    AppLanguage.persian: 'باشه',
    AppLanguage.english: 'OK',
    AppLanguage.turkish: 'Tamam',
  },
  'گەڕانەوە': {
    AppLanguage.badini: 'گەڕانەوە',
    AppLanguage.arabic: 'رجوع',
    AppLanguage.persian: 'بازگشت',
    AppLanguage.english: 'Back',
    AppLanguage.turkish: 'Geri',
  },
  'میوان': {
    AppLanguage.badini: 'میوان',
    AppLanguage.arabic: 'عدد الضيوف',
    AppLanguage.persian: 'مهمان',
    AppLanguage.english: 'Guests',
    AppLanguage.turkish: 'Misafir',
  },
  'وەیتەرەکان': {
    AppLanguage.badini: 'وەیتەرەکان',
    AppLanguage.arabic: 'النُدُل',
    AppLanguage.persian: 'پیشخدمت‌ها',
    AppLanguage.english: 'Waiters',
    AppLanguage.turkish: 'Garsonlar',
  },

  // ===== Payment =====
  'پارە (کاش)': {
    AppLanguage.badini: 'پارە (کاش)',
    AppLanguage.arabic: 'نقداً',
    AppLanguage.persian: 'نقد',
    AppLanguage.english: 'Cash',
    AppLanguage.turkish: 'Nakit',
  },

  'کاش (نەقد) + قەرز': {
    AppLanguage.badini: 'کاش (نەقد) + قەرز',
    AppLanguage.arabic: 'نقد + دين',
    AppLanguage.persian: 'نقد + بدهی',
    AppLanguage.english: 'Cash + Debts',
    AppLanguage.turkish: 'Nakit + Borçlar',
  },

  // ===== App =====
  'پاشەکەوت': {
    AppLanguage.badini: 'پاشەکەوت',
    AppLanguage.arabic: 'حفظ',
    AppLanguage.persian: 'ذخیره',
    AppLanguage.english: 'Save',
    AppLanguage.turkish: 'Kaydet',
  },

  // ===== Printers =====
  'پرینتەر': {
    AppLanguage.badini: 'پرینتەر',
    AppLanguage.arabic: 'طابعة',
    AppLanguage.persian: 'پرینتر',
    AppLanguage.english: 'Printer',
    AppLanguage.turkish: 'Yazıcı',
  },

  // ===== App =====
  'پشتڕاستکردنەوە': {
    AppLanguage.badini: 'پشتڕاستکرن',
    AppLanguage.arabic: 'تأكيد',
    AppLanguage.persian: 'تأیید',
    AppLanguage.english: 'Confirm',
    AppLanguage.turkish: 'Onayla',
  },

  // ===== Debt =====
  'پوختەی قەرز': {
    AppLanguage.badini: 'پوختەی قەرز',
    AppLanguage.arabic: 'ملخص الديون',
    AppLanguage.persian: 'خلاصه بدهی‌ها',
    AppLanguage.english: 'Debt Summary',
    AppLanguage.turkish: 'Borç Özeti',
  },

  // ===== Printers =====
  'پێشبینینی چاپ': {
    AppLanguage.badini: 'پێشبینینی چاپ',
    AppLanguage.arabic: 'معاينة الطباعة',
    AppLanguage.persian: 'پیش‌نمایش چاپ',
    AppLanguage.english: 'Print Preview',
    AppLanguage.turkish: 'Baskı Önizleme',
  },
  'پێشبینینی چاپی حیساب': {
    AppLanguage.badini: 'پێشبینینی چاپی حیساب',
    AppLanguage.arabic: 'معاينة طباعة الفاتورة',
    AppLanguage.persian: 'پیش‌نمایش چاپ صورتحساب',
    AppLanguage.english: 'Bill Print Preview',
    AppLanguage.turkish: 'Hesap Baskı Önizleme',
  },

  // ===== App =====
  'چالاکە': {
    AppLanguage.badini: 'چالاکە',
    AppLanguage.arabic: 'نشط',
    AppLanguage.persian: 'فعال',
    AppLanguage.english: 'Active',
    AppLanguage.turkish: 'Aktif',
  },

  // ===== Payment =====
  'چاوەڕێی پارە': {
    AppLanguage.badini: 'چاوەڕێی پارە',
    AppLanguage.arabic: 'بانتظار الدفع',
    AppLanguage.persian: 'منتظر پرداخت',
    AppLanguage.english: 'Awaiting payment',
    AppLanguage.turkish: 'Ödeme bekliyor',
  },

  // ===== Printers =====
  'چاپ': {
    AppLanguage.badini: 'چاپ',
    AppLanguage.arabic: 'طباعة',
    AppLanguage.persian: 'چاپ',
    AppLanguage.english: 'Print',
    AppLanguage.turkish: 'Yazdır',
  },
  'چاپکردن': {
    AppLanguage.badini: 'چاپکرن',
    AppLanguage.arabic: 'طباعة',
    AppLanguage.persian: 'چاپ کردن',
    AppLanguage.english: 'Printing',
    AppLanguage.turkish: 'Yazdırma',
  },
  'چاپکردنەوەی حیساب': {
    AppLanguage.badini: 'چاپکردنەوەی حیساب',
    AppLanguage.arabic: 'إعادة طباعة الفاتورة',
    AppLanguage.persian: 'چاپ مجدد صورتحساب',
    AppLanguage.english: 'Re-print Bill',
    AppLanguage.turkish: 'Hesabı Tekrar Yazdır',
  },
  'چاپکەر': {
    AppLanguage.badini: 'چاپکەر',
    AppLanguage.arabic: 'طابعة',
    AppLanguage.persian: 'چاپگر',
    AppLanguage.english: 'Printer',
    AppLanguage.turkish: 'Yazıcı',
  },
  'چاپکەر دۆزراوەتەوە': {
    AppLanguage.badini: 'چاپکەر دۆزراوەتەوە',
    AppLanguage.arabic: 'تم العثور على الطابعة',
    AppLanguage.persian: 'چاپگر پیدا شد',
    AppLanguage.english: 'Printer found',
    AppLanguage.turkish: 'Yazıcı bulundu',
  },
  'چاپکەری {printer} بکە بە {type}؟': {
    AppLanguage.badini: 'چاپکەری {printer} بکە بە {type}؟',
    AppLanguage.arabic: 'هل تزيد تعيين الطابعة {printer} كـ {type}؟',
    AppLanguage.persian: 'آیا چاپگر {printer} را به عنوان {type} تنظیم کنید؟',
    AppLanguage.english: 'Set printer {printer} as {type}?',
    AppLanguage.turkish: 'Yazıcı {printer} {type} olarak ayarlansın mı?',
  },
  'چاپکەری بار': {
    AppLanguage.badini: 'چاپکەری بار',
    AppLanguage.arabic: 'طابعة البار',
    AppLanguage.persian: 'چاپگر بار',
    AppLanguage.english: 'Bar Printer',
    AppLanguage.turkish: 'Bar Yazıcısı',
  },
  'چاپکەری قەلیان': {
    AppLanguage.badini: 'چاپکەری قەلیان',
    AppLanguage.arabic: 'طابعة القليان',
    AppLanguage.persian: 'چاپگر قلیان',
    AppLanguage.english: 'Hookah Printer',
    AppLanguage.turkish: 'Nargile Yazıcısı',
  },
  'چاپکەری چێشتخانە': {
    AppLanguage.badini: 'چاپکەری چێشتخانە',
    AppLanguage.arabic: 'طابعة المطبخ',
    AppLanguage.persian: 'چاپگر آشپزخانه',
    AppLanguage.english: 'Kitchen Printer',
    AppLanguage.turkish: 'Mutfak Yazıcısı',
  },
  'چاپکەری کاشێر': {
    AppLanguage.badini: 'چاپکەری کاشێر',
    AppLanguage.arabic: 'طابعة الكاشير',
    AppLanguage.persian: 'چاپگر صندوقدار',
    AppLanguage.english: 'Cashier Printer',
    AppLanguage.turkish: 'Kasiyer Yazıcısı',
  },
  'چاپکەرەکان دەستنیشان بکە': {
    AppLanguage.badini: 'چاپکەرەکان دەستنیشان بکە',
    AppLanguage.arabic: 'تحديد الطابعات',
    AppLanguage.persian: 'چاپگرها را شناسایی کنید',
    AppLanguage.english: 'Identify printers',
    AppLanguage.turkish: 'Yazıcıları belirleyin',
  },
  'چاپی خواردن': {
    AppLanguage.badini: 'چاپی خوارن',
    AppLanguage.arabic: 'طباعة الطعام',
    AppLanguage.persian: 'چاپ غذا',
    AppLanguage.english: 'Print Food',
    AppLanguage.turkish: 'Yiyecek Yazdır',
  },
  'چاپی ڕەسید': {
    AppLanguage.badini: 'چاپی ڕەسید',
    AppLanguage.arabic: 'طباعة الإيصال',
    AppLanguage.persian: 'چاپ رسید',
    AppLanguage.english: 'Print Receipt',
    AppLanguage.turkish: 'Fiş Yazdır',
  },

  // ===== App =====
  'چوون': {
    AppLanguage.badini: 'چوون',
    AppLanguage.arabic: 'ذهاب',
    AppLanguage.persian: 'رفتن',
    AppLanguage.english: 'Go',
    AppLanguage.turkish: 'Git',
  },
  'چوونە دەرەوە': {
    AppLanguage.badini: 'دەرکەڤتن',
    AppLanguage.arabic: 'خروج',
    AppLanguage.persian: 'خروج',
    AppLanguage.english: 'Exit',
    AppLanguage.turkish: 'Çıkış',
  },

  // ===== Waiter Home =====
  'چەند کەسن؟': {
    AppLanguage.badini: 'چەند کەس هەنە؟',
    AppLanguage.arabic: 'كم شخصاً؟',
    AppLanguage.persian: 'چند نفر؟',
    AppLanguage.english: 'How many guests?',
    AppLanguage.turkish: 'Kaç kişi?',
  },

  // ===== Cashier =====
  'ڕاپۆرتی شەفت': {
    AppLanguage.badini: 'ڕاپۆرتی شەفت',
    AppLanguage.arabic: 'تقرير الشيفت',
    AppLanguage.persian: 'گزارش شیفت',
    AppLanguage.english: 'Shift Report',
    AppLanguage.turkish: 'Vardiya Raporu',
  },

  // ===== Printers =====
  'ڕێکخستنی چاپکەر': {
    AppLanguage.badini: 'ڕێکخستنی چاپکەر',
    AppLanguage.arabic: 'إعدادات الطابعة',
    AppLanguage.persian: 'تنظیمات چاپگر',
    AppLanguage.english: 'Printer Settings',
    AppLanguage.turkish: 'Yazıcı Ayarları',
  },
  'ڕێکخستنی چاپکەرەکان': {
    AppLanguage.badini: 'ڕێکخستنی چاپکەرەکان',
    AppLanguage.arabic: 'إعدادات الطابعات',
    AppLanguage.persian: 'تنظیمات چاپگرها',
    AppLanguage.english: 'Printer Configurations',
    AppLanguage.turkish: 'Yazıcı Yapılandırmaları',
  },

  // ===== Payment =====
  'ڕێگاکانی وەرگرتنی پارە': {
    AppLanguage.badini: 'ڕێگاکانی وەرگرتنی پارە',
    AppLanguage.arabic: 'طرق تحصيل الأموال',
    AppLanguage.persian: 'روش‌های دریافت پول',
    AppLanguage.english: 'Money Collection Methods',
    AppLanguage.turkish: 'Para Tahsil Yöntemleri',
  },
  'کاش (نەقد)': {
    AppLanguage.badini: 'کاش (نەقد)',
    AppLanguage.arabic: 'نقداً',
    AppLanguage.persian: 'نقد',
    AppLanguage.english: 'Cash',
    AppLanguage.turkish: 'Nakit',
  },
  'ئەلیکترۆنی': {
    AppLanguage.badini: 'ئەلیکترۆنی',
    AppLanguage.arabic: 'إلكتروني',
    AppLanguage.persian: 'الکترونیکی',
    AppLanguage.english: 'Electronic',
    AppLanguage.turkish: 'Elektronik',
  },
  'کۆی دراوی ئەلیکترۆنی': {
    AppLanguage.badini: 'کۆی دراوی ئەلیکترۆنی',
    AppLanguage.arabic: 'إجمالي النقود الإلكترونية',
    AppLanguage.persian: 'مجموع پول الکترونیکی',
    AppLanguage.english: 'Electronic Money Total',
    AppLanguage.turkish: 'Elektronik Para Toplamı',
  },
  'پارەی ئەلیکترۆنی': {
    AppLanguage.badini: 'پارەی ئەلیکترۆنی',
    AppLanguage.arabic: 'النقود الإلكترونية',
    AppLanguage.persian: 'پول الکترونیکی',
    AppLanguage.english: 'Electronic Money',
    AppLanguage.turkish: 'Elektronik Para',
  },
  'کاش + ئەلیکترۆنی': {
    AppLanguage.badini: 'کاش + ئەلیکترۆنی',
    AppLanguage.arabic: 'نقد + إلكتروني',
    AppLanguage.persian: 'نقد + الکترونیکی',
    AppLanguage.english: 'Cash + Electronic',
    AppLanguage.turkish: 'Nakit + Elektronik',
  },
  'کۆی گشتی پارەکان': {
    AppLanguage.badini: 'کۆی گشتی پارەکان',
    AppLanguage.arabic: 'إجمالي الأموال',
    AppLanguage.persian: 'مجموع کل پول‌ها',
    AppLanguage.english: 'Total Money',
    AppLanguage.turkish: 'Toplam Para',
  },
  'لە دەخیلە': {
    AppLanguage.badini: 'لە دەخیلە',
    AppLanguage.arabic: 'الوارد',
    AppLanguage.persian: 'وارد شده',
    AppLanguage.english: 'Income',
    AppLanguage.turkish: 'Gelir',
  },
  'ڕاکێشراوە': {
    AppLanguage.badini: 'ڕاکێشراوە',
    AppLanguage.arabic: 'المصروف',
    AppLanguage.persian: 'برداشته شده',
    AppLanguage.english: 'Expenses Out',
    AppLanguage.turkish: 'Giderler',
  },
  'گەڕاوەتەوە': {
    AppLanguage.badini: 'گەڕاوەتەوە',
    AppLanguage.arabic: 'المُعاد',
    AppLanguage.persian: 'بازگشتی',
    AppLanguage.english: 'Returned',
    AppLanguage.turkish: 'İade',
  },
  'مانگانە': {
    AppLanguage.badini: 'مانگانە',
    AppLanguage.arabic: 'شهرياً',
    AppLanguage.persian: 'ماهانه',
    AppLanguage.english: 'Monthly',
    AppLanguage.turkish: 'Aylık',
  },
  'ڕۆژانە': {
    AppLanguage.badini: 'ڕۆژانە',
    AppLanguage.arabic: 'يومياً',
    AppLanguage.persian: 'روزانه',
    AppLanguage.english: 'Daily',
    AppLanguage.turkish: 'Günlük',
  },
  'پێری': {
    AppLanguage.badini: 'پێڕی',
    AppLanguage.arabic: 'أول أمس',
    AppLanguage.persian: 'پریروز',
    AppLanguage.english: 'Day before yesterday',
    AppLanguage.turkish: 'Evvelsi gün',
  },
  'هیچ خەرجێک نییە': {
    AppLanguage.badini: 'هیچ خەرجێک نییە',
    AppLanguage.arabic: 'لا توجد مصروفات',
    AppLanguage.persian: 'هیچ خرجی نییە',
    AppLanguage.english: 'No expenses yet',
    AppLanguage.turkish: 'Harcama yok',
  },
  'هیچ ڕەتکراوەیەک تۆمارنەکراوە': {
    AppLanguage.badini: 'هیچ ڕەتکراوەیەک تۆمارنەکراوە',
    AppLanguage.arabic: 'لم تُسجَّل أي إرجاعات',
    AppLanguage.persian: 'هیچ بازگشتی ثبت نشده',
    AppLanguage.english: 'No returns recorded',
    AppLanguage.turkish: 'İade kaydı yok',
  },

  // ===== App =====
  'بەڵێ': {
    AppLanguage.badini: 'بەلێ',
    AppLanguage.arabic: 'نعم',
    AppLanguage.persian: 'بله',
    AppLanguage.english: 'Yes',
    AppLanguage.turkish: 'Evet',
  },
  'ڕەتکردنەوە': {
    AppLanguage.badini: 'ڕەتکرن',
    AppLanguage.arabic: 'إلغاء',
    AppLanguage.persian: 'لغو',
    AppLanguage.english: 'Cancel',
    AppLanguage.turkish: 'İptal',
  },
  'هیچ مێزێک نییە بۆ گواستنەوە': {
    AppLanguage.badini: 'هیچ ماسەیەک نیە بۆ ڤەگواستن',
    AppLanguage.arabic: 'لا توجد طاولة للنقل',
    AppLanguage.persian: 'میز برای انتقال وجود ندارد',
    AppLanguage.english: 'No table to move to',
    AppLanguage.turkish: 'Taşımak için masa yok',
  },

  // ===== Orders =====
  'ڕەفزکراوە': {
    AppLanguage.badini: 'ڕەفزکراوە',
    AppLanguage.arabic: 'مرفوض',
    AppLanguage.persian: 'رد شده',
    AppLanguage.english: 'Rejected',
    AppLanguage.turkish: 'Reddedildi',
  },
  'ڕەفزکراوەکان': {
    AppLanguage.badini: 'ڕەفزکراوەکان',
    AppLanguage.arabic: 'المرفوضات',
    AppLanguage.persian: 'رد شده‌ها',
    AppLanguage.english: 'Rejected Items',
    AppLanguage.turkish: 'Reddedilenler',
  },
  'ڕەفزەکان': {
    AppLanguage.badini: 'ڕەفزەکان',
    AppLanguage.arabic: 'الرفض',
    AppLanguage.persian: 'ردها',
    AppLanguage.english: 'Rejections',
    AppLanguage.turkish: 'Reddetmeler',
  },
  'ژ. داواکاری': {
    AppLanguage.badini: 'ژ. داواکاری',
    AppLanguage.arabic: 'رقم الطلب',
    AppLanguage.persian: 'شماره سفارش',
    AppLanguage.english: 'Order No.',
    AppLanguage.turkish: 'Sipariş No.',
  },

  // ===== Tables =====
  'ژمارە یان ناوی مێز': {
    AppLanguage.badini: 'هژمار یان ناڤی ماسە',
    AppLanguage.arabic: 'رقم أو اسم الطاولة',
    AppLanguage.persian: 'شماره یا نام میز',
    AppLanguage.english: 'Table number or name',
    AppLanguage.turkish: 'Masa numarası veya adı',
  },

  // ===== Waiter Home =====
  'ژمارەی کەسەکان بنووسە': {
    AppLanguage.badini: 'هژمارا کەسان بنڤیسە',
    AppLanguage.arabic: 'اكتب عدد الأشخاص',
    AppLanguage.persian: 'تعداد افراد را بنویسید',
    AppLanguage.english: 'Enter number of guests',
    AppLanguage.turkish: 'Kişi sayısını girin',
  },

  // ===== App =====
  'کات': {
    AppLanguage.badini: 'کات',
    AppLanguage.arabic: 'الوقت',
    AppLanguage.persian: 'زمان',
    AppLanguage.english: 'Time',
    AppLanguage.turkish: 'Zaman',
  },
  'کاتی دانیشتن': {
    AppLanguage.badini: 'کاتی دانیشتن',
    AppLanguage.arabic: 'وقت الجلوس',
    AppLanguage.persian: 'زمان نشستن',
    AppLanguage.english: 'Seating time',
    AppLanguage.turkish: 'Oturma zamanı',
  },
  'پ.ن': {
    AppLanguage.badini: 'پ.ن',
    AppLanguage.arabic: 'ص',
    AppLanguage.persian: 'ق.ظ',
    AppLanguage.english: 'AM',
    AppLanguage.turkish: 'ÖÖ',
  },
  'د.ن': {
    AppLanguage.badini: 'د.ن',
    AppLanguage.arabic: 'م',
    AppLanguage.persian: 'ب.ظ',
    AppLanguage.english: 'PM',
    AppLanguage.turkish: 'ÖS',
  },

  // ===== Payment =====
  'کارت': {
    AppLanguage.badini: 'کارت',
    AppLanguage.arabic: 'بطاقة',
    AppLanguage.persian: 'کارت',
    AppLanguage.english: 'Card',
    AppLanguage.turkish: 'Kart',
  },

  // ===== Cashier =====
  'کاشێر': {
    AppLanguage.badini: 'کاشێر',
    AppLanguage.arabic: 'الكاشير',
    AppLanguage.persian: 'صندوقدار',
    AppLanguage.english: 'Cashier',
    AppLanguage.turkish: 'Kasiyer',
  },
  'کاشێرەکان': {
    AppLanguage.badini: 'کاشێرەکان',
    AppLanguage.arabic: 'الكاشيرات',
    AppLanguage.persian: 'صندوقدارها',
    AppLanguage.english: 'Cashiers',
    AppLanguage.turkish: 'Kasiyerler',
  },

  // ===== Backup =====
  'کرتە لە دوگمەی بەکاپ بکە بۆ دروستکردنی یەکەم بەکاپ': {
    AppLanguage.badini: 'کرتە لە دوگمەی بەکاپ بکە بۆ دروستکردنی یەکەم بەکاپ',
    AppLanguage.arabic: 'اضغط على زر النسخ الاحتياطي لإنشاء أول نسخة',
    AppLanguage.persian: 'برای ایجاد اولین پشتیبان، دکمه پشتیبان را فشار دهید',
    AppLanguage.english: 'Tap the backup button to create your first backup',
    AppLanguage.turkish:
        'İlk yedeğinizi oluşturmak için yedekleme düğmesine dokunun',
  },

  // ===== App =====
  'کردنەوە بە تەواوی': {
    AppLanguage.badini: 'کردنەوە بە تەواوی',
    AppLanguage.arabic: 'فتح بالكامل',
    AppLanguage.persian: 'باز کردن کامل',
    AppLanguage.english: 'Open Fully',
    AppLanguage.turkish: 'Tam Aç',
  },

  // ===== Cashier =====
  'کڕینی ئەشیاکان': {
    AppLanguage.badini: 'کڕینی ئەشیاکان',
    AppLanguage.arabic: 'شراء المستلزمات',
    AppLanguage.persian: 'خرید لوازم',
    AppLanguage.english: 'Supply Purchases',
    AppLanguage.turkish: 'Malzeme Alımları',
  },

  // ===== App =====
  'کۆتایی': {
    AppLanguage.badini: 'کۆتایی',
    AppLanguage.arabic: 'النهاية',
    AppLanguage.persian: 'پایان',
    AppLanguage.english: 'End',
    AppLanguage.turkish: 'Son',
  },
  'کۆکردنەوە': {
    AppLanguage.badini: 'کۆمکرن',
    AppLanguage.arabic: 'تحصيل',
    AppLanguage.persian: 'جمع‌آوری',
    AppLanguage.english: 'Collection',
    AppLanguage.turkish: 'Tahsilat',
  },

  // ===== Debt =====
  'کۆکردنەوەی قەرز': {
    AppLanguage.badini: 'کۆکردنەوەی قەرز',
    AppLanguage.arabic: 'تحصيل الديون',
    AppLanguage.persian: 'جمع‌آوری بدهی',
    AppLanguage.english: 'Debt Collection',
    AppLanguage.turkish: 'Borç Tahsilatı',
  },

  // ===== Admin =====
  'کۆی خەرجیەکان': {
    AppLanguage.badini: 'کۆی خەرجیەکان',
    AppLanguage.arabic: 'إجمالي المصروفات',
    AppLanguage.persian: 'مجموع هزینه‌ها',
    AppLanguage.english: 'Total expenses',
    AppLanguage.turkish: 'Toplam giderler',
  },
  'خەرجییە دەرکراوەکان': {
    AppLanguage.badini: 'خەرجییە دەرکراوەکان',
    AppLanguage.arabic: 'المصروفات المسحوبة',
    AppLanguage.persian: 'هزینه‌های برداشت‌شده',
    AppLanguage.english: 'Expenses taken out',
    AppLanguage.turkish: 'Çıkarılan giderler',
  },

  // ===== Cashier =====
  'کۆی پارەی کۆکراوە (د.ع)': {
    AppLanguage.badini: 'کۆی پارەی کۆکراوە (د.ع)',
    AppLanguage.arabic: 'إجمالي المبلغ المحصل (د.ع)',
    AppLanguage.persian: 'مجموع مبلغ جمع‌آوری شده (د.ع)',
    AppLanguage.english: 'Total collected amount (IQD)',
    AppLanguage.turkish: 'Toplanan toplam tutar (IQD)',
  },
  'کۆی پاش داشکاندن': {
    AppLanguage.badini: 'کۆی پاش داشکاندن',
    AppLanguage.arabic: 'المجموع بعد الخصم',
    AppLanguage.persian: 'مجموع پس از تخفیف',
    AppLanguage.english: 'Total After Discount',
    AppLanguage.turkish: 'İndirim Sonrası Toplam',
  },

  // ===== App =====
  'کۆی گشتی': {
    AppLanguage.badini: 'تێکرا',
    AppLanguage.arabic: 'المجموع الكلي',
    AppLanguage.persian: 'مجموع کل',
    AppLanguage.english: 'Grand Total',
    AppLanguage.turkish: 'Genel Toplam',
  },

  // ===== Orders =====
  'کۆی گشتی ڕەفزکراوەکان': {
    AppLanguage.badini: 'کۆی گشتی ڕەفزکراوەکان',
    AppLanguage.arabic: 'إجمالي المرفوضات',
    AppLanguage.persian: 'مجموع رد شده‌ها',
    AppLanguage.english: 'Total Rejected',
    AppLanguage.turkish: 'Toplam Reddedilen',
  },

  // ===== App =====
  'کۆی یەکەم': {
    AppLanguage.badini: 'کۆی یەکەم',
    AppLanguage.arabic: 'المجموع الأولي',
    AppLanguage.persian: 'مجموع اولیه',
    AppLanguage.english: 'Initial Total',
    AppLanguage.turkish: 'İlk Toplam',
  },

  // ===== Waiter Home =====
  'کەس': {
    AppLanguage.badini: 'کەس',
    AppLanguage.arabic: 'شخص',
    AppLanguage.persian: 'نفر',
    AppLanguage.english: 'person',
    AppLanguage.turkish: 'kişi',
  },

  // ===== Waiter Home =====
  'دەستی پەیوەندی: {status}': {
    AppLanguage.badini: 'دەستی پەیوەندی: {status}',
    AppLanguage.arabic: 'زر الاتصال: {status}',
    AppLanguage.persian: 'دسته اتصال: {status}',
    AppLanguage.english: 'Sync status: {status}',
    AppLanguage.turkish: 'Bağlantı düğmesi: {status}',
  },
  'بۆ ڕاگرتنی پەیوەندی دووبارە بکەرەوە': {
    AppLanguage.badini: 'بۆ ڕاگرتنی پەیوەندی دووبارە بکەرەوە',
    AppLanguage.arabic: 'اضغط مرتين لقطع الاتصال',
    AppLanguage.persian: 'برای قطع اتصال دوبار ضربه بزنید',
    AppLanguage.english: 'Tap twice to disconnect',
    AppLanguage.turkish: 'Bağlantıyı kesmek için iki kez dokunun',
  },
  'بۆ پەیوەندی دووبارە بکەرەوە': {
    AppLanguage.badini: 'بۆ پەیوەندی دووبارە بکەرەوە',
    AppLanguage.arabic: 'اضغط مرتين للاتصال',
    AppLanguage.persian: 'برای اتصال دوبار ضربه بزنید',
    AppLanguage.english: 'Tap twice to connect',
    AppLanguage.turkish: 'Bağlanmak için iki kez dokunun',
  },
  'ڕاگرتنی پەیوەندی': {
    AppLanguage.badini: 'ڕاگرتنی پەیوەندی',
    AppLanguage.arabic: 'قطع الاتصال',
    AppLanguage.persian: 'قطع اتصال',
    AppLanguage.english: 'Disconnect',
    AppLanguage.turkish: 'Bağlantıyı Kes',
  },
  'بەڵێ، ڕابگرە': {
    AppLanguage.badini: 'بەڵێ، ڕابگرە',
    AppLanguage.arabic: 'نعم، اقطع',
    AppLanguage.persian: 'بله، قطع کن',
    AppLanguage.english: 'Yes, disconnect',
    AppLanguage.turkish: 'Evet, Kes',
  },
  'تاکە پەیوەندیکە دادەخەیت. داواکاریە نوێەکان لەسەر ئامێرەکەت دەمێننەوە و کاتێک پەیوەندی دەگەڕێتەوە خۆکار دەنێردرێنن. ئایا دڵنیایت؟': {
    AppLanguage.badini:
        'تاکە پەیوەندیکە دادەخەیت. داواکاریە نوێەکان لەسەر ئامێرەکەت دەمێننەوە و کاتێک پەیوەندی دەگەڕێتەوە خۆکار دەنێردرێنن. ئایا دڵنیایت؟',
    AppLanguage.arabic:
        'سيتم قطع الاتصال. تبقى الطلبات الجديدة على جهازك وترسل تلقائياً عند عودة الاتصال. هل أنت متأكد؟',
    AppLanguage.persian:
        'اتصال قطع می‌شود. سفارش‌های جدید روی دستگاه شما می‌مانند و با بازگشت اتصال به‌صورت خودکار ارسال می‌شوند. مطمئن هستید؟',
    AppLanguage.english:
        'The sync link will drop. New orders stay on this device and are sent automatically once the link returns. Are you sure?',
    AppLanguage.turkish:
        'Bağlantı kesilecek. Yeni siparişler bu cihazda kalır ve bağlantı geri geldiğinde otomatik gönderilir. Emin misiniz?',
  },

  // ===== App =====
  'کەمترە': {
    AppLanguage.badini: 'کەمترە',
    AppLanguage.arabic: 'أقل',
    AppLanguage.persian: 'کمتر',
    AppLanguage.english: 'Less',
    AppLanguage.turkish: 'Daha az',
  },

  // ===== Tables =====
  'گوازرایەوە بۆ {name}': {
    AppLanguage.badini: 'ڤەگوازرایەوە بۆ {name}',
    AppLanguage.arabic: 'تم النقل إلى {name}',
    AppLanguage.persian: 'به {name} منتقل شد',
    AppLanguage.english: 'Moved to {name}',
    AppLanguage.turkish: '{name} konumuna taşındı',
  },

  // ===== Debt =====
  'گوازرایەوە بۆ قەرزەکان': {
    AppLanguage.badini: 'ڤەگوازرایەوە بۆ قەرزەکان',
    AppLanguage.arabic: 'تم النقل إلى الديون',
    AppLanguage.persian: 'به بدهی‌ها منتقل شد',
    AppLanguage.english: 'Moved to debts',
    AppLanguage.turkish: 'Borçlara taşındı',
  },

  // ===== Tables =====
  'گواستنەوە': {
    AppLanguage.badini: 'ڤەگواستن',
    AppLanguage.arabic: 'نقل',
    AppLanguage.persian: 'انتقال',
    AppLanguage.english: 'Transfer',
    AppLanguage.turkish: 'Taşı',
  },
  'گواستنەوەی {itemName}': {
    AppLanguage.badini: 'گواستنەوەی {itemName}',
    AppLanguage.arabic: 'نقل {itemName}',
    AppLanguage.persian: 'انتقال {itemName}',
    AppLanguage.english: 'Transfer {itemName}',
    AppLanguage.turkish: '{itemName} Taşı',
  },
  'گواستنەوەی خواردنەکان': {
    AppLanguage.badini: 'ڤەگواستنی خوارنەکان',
    AppLanguage.arabic: 'نقل الأطعمة',
    AppLanguage.persian: 'انتقال غذاها',
    AppLanguage.english: 'Transfer Items',
    AppLanguage.turkish: 'Yiyecekleri Taşı',
  },
  'گواستنەوەی مێز': {
    AppLanguage.badini: 'ڤەگواستنی ماسە',
    AppLanguage.arabic: 'نقل الطاولة',
    AppLanguage.persian: 'انتقال میز',
    AppLanguage.english: 'Transfer Table',
    AppLanguage.turkish: 'Masa Taşı',
  },
  'تەنها دەتوانیت بۆ مێزی بەتاڵ بگوازیتەوە': {
    AppLanguage.badini: 'تەنها دەتوانیت بۆ ماسی ڤالا بگوازیتەوە',
    AppLanguage.arabic: 'يمكنك النقل إلى طاولة فارغة فقط',
    AppLanguage.persian: 'فقط می‌توانید به میز خالی منتقل کنید',
    AppLanguage.english: 'You can only transfer to an empty table',
    AppLanguage.turkish: 'Yalnızca boş bir masaya aktarabilirsiniz',
  },
  'ناتوانیت بۆ مێزێکی گیراو بگوازیتەوە؛ تەنها کاشێر دەتوانێت': {
    AppLanguage.badini: 'ناتوانیت بۆ ماسی داگیرکراوی بگوازیتەوە؛ تەنها کاشێر دەتوانێت',
    AppLanguage.arabic: 'لا يمكنك النقل إلى طاولة مشغولة؛ الكاشير فقط',
    AppLanguage.persian: 'نمی‌توانید به میز اشغال منتقل کنید؛ فقط صندوقدار',
    AppLanguage.english: 'Cannot transfer to an occupied table; only the cashier can',
    AppLanguage.turkish: 'Dolu bir masaya aktarılamaz; yalnızca kasiyer yapabilir',
  },
  'گواستنەوەی هەموو': {
    AppLanguage.badini: 'ڤەگواستنی هەمی',
    AppLanguage.arabic: 'نقل الكل',
    AppLanguage.persian: 'انتقال همه',
    AppLanguage.english: 'Transfer All',
    AppLanguage.turkish: 'Tümünü Taşı',
  },

  // ===== App =====
  'گۆڕین': {
    AppLanguage.badini: 'گوهرین',
    AppLanguage.arabic: 'تغيير',
    AppLanguage.persian: 'تغییر',
    AppLanguage.english: 'Change',
    AppLanguage.turkish: 'Değiştir',
  },

  // ===== Menu / Food =====
  'گۆڕینی بەش': {
    AppLanguage.badini: 'گۆڕینی بەش',
    AppLanguage.arabic: 'تغيير القسم',
    AppLanguage.persian: 'تغییر بخش',
    AppLanguage.english: 'Change Section',
    AppLanguage.turkish: 'Bölüm Değiştir',
  },
  'گۆڕینی خواردن': {
    AppLanguage.badini: 'گۆڕینی خواردن',
    AppLanguage.arabic: 'تغيير الطعام',
    AppLanguage.persian: 'تغییر غذا',
    AppLanguage.english: 'Change Food',
    AppLanguage.turkish: 'Yiyecek Değiştir',
  },

  // ===== Tables =====
  'گۆڕینی ناوی مێز': {
    AppLanguage.badini: 'گۆڕینی ناوی مێز',
    AppLanguage.arabic: 'تغيير اسم الطاولة',
    AppLanguage.persian: 'تغییر نام میز',
    AppLanguage.english: 'Change Table Name',
    AppLanguage.turkish: 'Masa Adını Değiştir',
  },

  // ===== Admin =====
  'گۆڕینی وشەی نهێنی': {
    AppLanguage.badini: 'گۆڕینی وشەی نهێنی',
    AppLanguage.arabic: 'تغيير كلمة المرور',
    AppLanguage.persian: 'تغییر رمز عبور',
    AppLanguage.english: 'Change Password',
    AppLanguage.turkish: 'Şifre Değiştir',
  },

  // ===== Payment =====
  'گۆڕینەوەی نرخ': {
    AppLanguage.badini: 'گۆڕینەوەی نرخ',
    AppLanguage.arabic: 'تحويل العملة',
    AppLanguage.persian: 'تبدیل ارز',
    AppLanguage.english: 'Currency Exchange',
    AppLanguage.turkish: 'Döviz Çevirici',
  },

  // ===== App =====
  'گیراوەکان': {
    AppLanguage.badini: 'گیراوەکان',
    AppLanguage.arabic: 'المشغولة',
    AppLanguage.persian: 'مشغول‌ها',
    AppLanguage.english: 'Occupied Tables',
    AppLanguage.turkish: 'Dolu Masalar',
  },
  'گیراوەکان:': {
    AppLanguage.badini: 'گیراوەکان:',
    AppLanguage.arabic: 'المشغولة:',
    AppLanguage.persian: 'مشغول:',
    AppLanguage.english: 'Occupied:',
    AppLanguage.turkish: 'Dolu:',
  },

  // ===== Search =====
  'گەڕان': {
    AppLanguage.badini: 'گەڕان',
    AppLanguage.arabic: 'بحث',
    AppLanguage.persian: 'جستجو',
    AppLanguage.english: 'Search',
    AppLanguage.turkish: 'Ara',
  },

  // ===== Tables =====
  'گەڕان بە ناوی مێز یان کاشێر': {
    AppLanguage.badini: 'گەڕان بە ناوی مێز یان کاشێر',
    AppLanguage.arabic: 'ابحث باسم الطاولة أو الكاشير',
    AppLanguage.persian: 'جستجو با نام میز یا صندوقدار',
    AppLanguage.english: 'Search by table name or cashier',
    AppLanguage.turkish: 'Masa adı veya kasiyer ile ara',
  },

  // ===== Backup =====
  'گەڕاندنەوە': {
    AppLanguage.badini: 'گەڕاندنەوە',
    AppLanguage.arabic: 'استعادة',
    AppLanguage.persian: 'بازیابی',
    AppLanguage.english: 'Restore',
    AppLanguage.turkish: 'Geri Yükle',
  },
  'گەڕاندنەوەی بەکاپ': {
    AppLanguage.badini: 'گەڕاندنەوەی بەکاپ',
    AppLanguage.arabic: 'استعادة النسخة الاحتياطية',
    AppLanguage.persian: 'بازیابی پشتیبان',
    AppLanguage.english: 'Restore Backup',
    AppLanguage.turkish: 'Yedeği Geri Yükle',
  },

  // ===== App =====
  'یەکسانە': {
    AppLanguage.badini: 'یەکسانە',
    AppLanguage.arabic: 'متساوٍ',
    AppLanguage.persian: 'مساوی',
    AppLanguage.english: 'Equal',
    AppLanguage.turkish: 'Eşit',
  },

  // ===== Printer assignment =====
  'تازەکردنەوە': {
    AppLanguage.badini: 'تازەکردنەوە',
    AppLanguage.arabic: 'تحديث',
    AppLanguage.persian: 'به‌روزرسانی',
    AppLanguage.english: 'Refresh',
    AppLanguage.turkish: 'Yenile',
  },
  'فلتەری خواردن بەپێی چاپکەر': {
    AppLanguage.badini: 'فلتەری خوارن بەپێی چاپکەر',
    AppLanguage.arabic: 'تصفية الطعام حسب الطابعة',
    AppLanguage.persian: 'فیلتر غذا بر اساس چاپگر',
    AppLanguage.english: 'Filter Food by Printer',
    AppLanguage.turkish: 'Yazıcıya Göre Yiyecek Filtrele',
  },
  'بە هیچ پرێنتێک پەیوەست نەبێت بۆ مەتبەخ دەچێت': {
    AppLanguage.badini: 'بە هیچ پرێنتێک پەیوەست نەبێت بۆ مەتبەخ دەچێت',
    AppLanguage.arabic: 'إذا لم يكن متصلاً بأي طابعة، يذهب للمطبخ',
    AppLanguage.persian: 'اگر به هیچ چاپگری متصل نباشد، به آشپزخانه می‌رود',
    AppLanguage.english: 'If not connected to any printer, goes to kitchen',
    AppLanguage.turkish: 'Hiçbir yazıcıya bağlı değilse mutfağa gider',
  },
  'کلیک بکە بۆ شوێنی چاپ': {
    AppLanguage.badini: 'کلیک بکە بۆ شوێنی چاپ',
    AppLanguage.arabic: 'اضغط لاختيار مكان الطباعة',
    AppLanguage.persian: 'برای انتخاب محل چاپ کلیک کنید',
    AppLanguage.english: 'Click for print location',
    AppLanguage.turkish: 'Yazdırma konumu için tıklayın',
  },
  'هیچ پرێنتێک': {
    AppLanguage.badini: 'هیچ پرێنتێک',
    AppLanguage.arabic: 'لا توجد طابعة',
    AppLanguage.persian: 'هیچ چاپگری',
    AppLanguage.english: 'No printer',
    AppLanguage.turkish: 'Yazıcı yok',
  },
  'مەتبەخ': {
    AppLanguage.badini: 'مەتبەخ',
    AppLanguage.arabic: 'مطبخ',
    AppLanguage.persian: 'آشپزخانه',
    AppLanguage.english: 'Kitchen',
    AppLanguage.turkish: 'Mutfak',
  },
  'باڕ': {
    AppLanguage.badini: 'باڕ',
    AppLanguage.arabic: 'بار',
    AppLanguage.persian: 'بار',
    AppLanguage.english: 'Bar',
    AppLanguage.turkish: 'Bar',
  },
  'نێرگیلە': {
    AppLanguage.badini: 'نێرگیلە',
    AppLanguage.arabic: 'ارجيلة',
    AppLanguage.persian: 'قلیان',
    AppLanguage.english: 'Hookah',
    AppLanguage.turkish: 'Nargile',
  },
  'چاپکەر هەڵبژێرە': {
    AppLanguage.badini: 'چاپکەر هەڵبژێرە',
    AppLanguage.arabic: 'اختر طابعة',
    AppLanguage.persian: 'چاپگر را انتخاب کنید',
    AppLanguage.english: 'Select printer',
    AppLanguage.turkish: 'Yazıcı seç',
  },
  'بەپێی پۆل': {
    AppLanguage.badini: 'بەپێی پۆل',
    AppLanguage.arabic: 'حسب الفئة',
    AppLanguage.persian: 'بر اساس دسته',
    AppLanguage.english: 'By category',
    AppLanguage.turkish: 'Kategoriye göre',
  },

  // ===== IP Settings (ڕێخستنی IP) =====
  'ڕێخستنی IP': {
    AppLanguage.badini: 'ڕێخستنی IP',
    AppLanguage.arabic: 'إعدادات IP',
    AppLanguage.persian: 'تنظیمات IP',
    AppLanguage.english: 'IP Settings',
    AppLanguage.turkish: 'IP Ayarları',
  },
  'نیشانەی IP': {
    AppLanguage.badini: 'نیشانەی IP',
    AppLanguage.arabic: 'عنوان IP',
    AppLanguage.persian: 'آدرس IP',
    AppLanguage.english: 'IP Address',
    AppLanguage.turkish: 'IP Adresi',
  },
  'ئای-پی سێرڤەر': {
    AppLanguage.badini: 'ئای-پی سێرڤەر',
    AppLanguage.arabic: 'IP الخادم',
    AppLanguage.persian: 'IP سرور',
    AppLanguage.english: 'Server IP',
    AppLanguage.turkish: 'Sunucu IP',
  },
  'بۆ ئەوەی هەموو ئامێرەکان یەکتری بناسنەوە و پەیوەندییان پێکەوە هەبێت، ناونیشانی IPـی ئەو ئامێرەی کە سێرڤەرەکەی لەسەرە لێرە دابنێ و پاشەکەوت بکە.': {
    AppLanguage.badini:
        'بۆ ئەوەی هەموو ئامێرەکان یەکتری بناسنەوە و پەیوەندییان پێکەوە هەبێت، ناونیشانی IPـی ئەو ئامێرەی کە سێرڤەرەکەی لەسەرە لێرە دابنێ و پاشەکەوت بکە.',
    AppLanguage.arabic:
        'لكي تتعرف جميع الأجهزة على بعضها وتتصل معاً، أدخل هنا عنوان IP الخاص بالجهاز الذي يعمل عليه الخادم واحفظه.',
    AppLanguage.persian:
        'برای اینکه همه دستگاه‌ها یکدیگر را بشناسند و به هم متصل شوند، آدرس IP دستگاهی که سرور روی آن است را اینجا وارد کنید و ذخیره کنید.',
    AppLanguage.english:
        'So all devices can recognize each other and stay connected, enter the IP of the device that hosts the server here and save it.',
    AppLanguage.turkish:
        'Tüm cihazların birbirini tanıması ve bağlı kalması için sunucunun üzerinde çalıştığı cihazın IP adresini buraya girin ve kaydedin.',
  },
  'نیشانەی IP هەڵەیە - دڵنیابە شێوەکەی وەک (مثال: 192.168.1.10) بێت': {
    AppLanguage.badini:
        'نیشانەی IP هەڵەیە - دڵنیابە شێوەکەی وەک (مثال: 192.168.1.10) بێت',
    AppLanguage.arabic:
        'عنوان IP غير صالح - تأكد أن الصيغة مثل (مثال: 192.168.1.10)',
    AppLanguage.persian:
        'آدرس IP نامعتبر است - مطمئن شوید فرمت مانند (مثال: 192.168.1.10) باشد',
    AppLanguage.english:
        'Invalid IP address - make sure the format is like (e.g. 192.168.1.10)',
    AppLanguage.turkish:
        'Geçersiz IP adresi - biçimin (örn. 192.168.1.10) gibi olduğundan emin olun',
  },
  'پاشەکەوت کرا - بەستەرەکە بە ئای-پی نوێیەوە دەبەسترێتەوە': {
    AppLanguage.badini:
        'پاشەکەوت کرا - بەستەرەکە بە ئای-پی نوێیەوە دەبەسترێتەوە',
    AppLanguage.arabic: 'تم الحفظ - سيتم الاتصال بعنوان IP الجديد',
    AppLanguage.persian: 'ذخیره شد - اتصال با IP جدید برقرار می‌شود',
    AppLanguage.english: 'Saved - will reconnect using the new IP',
    AppLanguage.turkish: 'Kaydedildi - yeni IP ile yeniden bağlanılacak',
  },
  'ئای-پی ئەم ئامێرە': {
    AppLanguage.badini: 'ئای-پی ئەم ئامێرە',
    AppLanguage.arabic: 'IP هذا الجهاز',
    AppLanguage.persian: 'IP این دستگاه',
    AppLanguage.english: 'This device IP',
    AppLanguage.turkish: 'Bu cihazın IP',
  },

  // ===== Connected devices (Wi-Fi icon on the cashier bar) =====
  'ئامێرە بەستراوەکان': {
    AppLanguage.badini: 'ئامێرێن گرێدای',
    AppLanguage.arabic: 'الأجهزة المتصلة',
    AppLanguage.persian: 'دستگاه‌های متصل',
    AppLanguage.english: 'Connected Devices',
    AppLanguage.turkish: 'Bağlı Cihazlar',
  },
  'هیچ ئامێرێک بەستراو نییە': {
    AppLanguage.badini: 'چو ئامێرێن گرێدای نینن',
    AppLanguage.arabic: 'لا توجد أجهزة متصلة',
    AppLanguage.persian: 'هیچ دستگاهی متصل نیست',
    AppLanguage.english: 'No connected devices',
    AppLanguage.turkish: 'Bağlı cihaz yok',
  },
  '{count} ئامێر بەستراوە': {
    AppLanguage.badini: '{count} ئامێرێن گرێدای',
    AppLanguage.arabic: '{count} جهاز متصل',
    AppLanguage.persian: '{count} دستگاه متصل',
    AppLanguage.english: '{count} devices connected',
    AppLanguage.turkish: '{count} cihaz bağlı',
  },
  'بەستراوی لە': {
    AppLanguage.badini: 'گرێدای لە',
    AppLanguage.arabic: 'متصل في',
    AppLanguage.persian: 'متصل در',
    AppLanguage.english: 'Connected at',
    AppLanguage.turkish: 'Bağlandı',
  },
  'ئەم ئامێرە سێرڤەر نییە': {
    AppLanguage.badini: 'ئەڤ ئامێر سێرڤەر نینە',
    AppLanguage.arabic: 'هذا الجهاز ليس الخادم',
    AppLanguage.persian: 'این دستگاه سرور نیست',
    AppLanguage.english: 'This device is not the server',
    AppLanguage.turkish: 'Bu cihaz sunucu değil',
  },
  'بەستنەوە بە IP': {
    AppLanguage.badini: 'بەستنەوە بە IP',
    AppLanguage.arabic: 'الاتصال عبر IP',
    AppLanguage.persian: 'اتصال با IP',
    AppLanguage.english: 'Connect with IP',
    AppLanguage.turkish: 'IP ile Bağlan',
  },
  'کۆنێکت': {
    AppLanguage.badini: 'کۆنێکت',
    AppLanguage.arabic: 'اتصال',
    AppLanguage.persian: 'اتصال',
    AppLanguage.english: 'Connect',
    AppLanguage.turkish: 'Bağlan',
  },
  'کۆنێکت کرا': {
    AppLanguage.badini: 'کۆنێکت کرا',
    AppLanguage.arabic: 'تم الاتصال',
    AppLanguage.persian: 'متصل شد',
    AppLanguage.english: 'Connected',
    AppLanguage.turkish: 'Bağlandı',
  },
  'هەڵەیە': {
    AppLanguage.badini: 'هەڵەیە',
    AppLanguage.arabic: 'خطأ',
    AppLanguage.persian: 'اشتباه است',
    AppLanguage.english: 'Wrong',
    AppLanguage.turkish: 'Yanlış',
  },
  'تکایە کۆنێکت لاپتۆپی بکە': {
    AppLanguage.badini: 'تکایە کۆنێکت لاپتۆپی بکە',
    AppLanguage.arabic: 'يرجى الاتصال باللابتوب',
    AppLanguage.persian: 'لطفاً به لپ‌تاپ متصل شوید',
    AppLanguage.english: 'Please connect to the laptop',
    AppLanguage.turkish: 'Lütfen dizüstü bilgisayara bağlanın',
  },
  'IPـی هەژمارەکەت': {
    AppLanguage.badini: 'IPـی هەژمارەکەت',
    AppLanguage.arabic: 'IP حسابك',
    AppLanguage.persian: 'IP حساب شما',
    AppLanguage.english: 'Your account IP',
    AppLanguage.turkish: 'Hesabınızın IP',
  },
  'ئەو IPـەی کە خاوەن سیستەم بۆ هەژمارەکەت دروستی کردووە لێرە بنووسە و کۆنێکت بکە، پاشان بە PINـە 5 ژمارەییەکەت چوونە ژوورەوە بکە. هەتا ئەم IPـە داخل نەکرێت، هیچ هەژمارەیەک لەم ئامێرەدا نابێت بێجگە لە خاوەن سیستەم.': {
    AppLanguage.badini:
        'ئەو IPـەی کە خاوەن سیستەم بۆ هەژمارەکەت دروستی کردووە لێرە بنووسە و کۆنێکت بکە، پاشان بە PINـە 5 ژمارەییەکەت چوونە ژوورەوە بکە. هەتا ئەم IPـە داخل نەکرێت، هیچ هەژمارەیەک لەم ئامێرەدا نابێت بێجگە لە خاوەن سیستەم.',
    AppLanguage.arabic:
        'أدخل هنا عنوان IP الذي أنشأه صاحب النظام لحسابك واضغط اتصال، ثم سجّل الدخول برمز PIN المكوّن من 5 أرقام. حتى يتم إدخال عنوان IP هذا، لا يوجد أي حساب على هذا الجهاز سوى صاحب النظام.',
    AppLanguage.persian:
        'آدرس IP که مالک سیستم برای حساب شما ساخته است را اینجا وارد کرده و اتصال بزنید، سپس با PIN پنج رقمی خود وارد شوید. تا وارد نشدن این IP، هیچ حسابی روی این دستگاه به جز مالک سیستم وجود ندارد.',
    AppLanguage.english:
        'Enter the IP the owner created for your account here and press Connect, then log in with your 5-digit PIN. Until this IP is entered, no account exists on this device except the owner.',
    AppLanguage.turkish:
        'Sahibin hesabınız için oluşturduğu IP adresini buraya girin ve Bağlan\'a basın, ardından 5 haneli PIN\'inizle giriş yapın. Bu IP girilene kadar bu cihazda sahip dışında hiçbir hesap yoktur.',
  },
  'سێرڤەر:': {
    AppLanguage.badini: 'سێرڤەر:',
    AppLanguage.arabic: 'الخادم:',
    AppLanguage.persian: 'سرور:',
    AppLanguage.english: 'Server:',
    AppLanguage.turkish: 'Sunucu:',
  },
  'چاوەڕوانی بەستنەوە...': {
    AppLanguage.badini: 'چاوەڕوانی بەستنەوە...',
    AppLanguage.arabic: 'جارٍ الاتصال...',
    AppLanguage.persian: 'در حال اتصال...',
    AppLanguage.english: 'Connecting...',
    AppLanguage.turkish: 'Bağlanıyor...',
  },
  'بەسترایتەوە - ئێستا بە PINـی خۆت چوونە ژوورەوە بکە': {
    AppLanguage.badini: 'بەسترایتەوە - ئێستا بە PINـی خۆت چوونە ژوورەوە بکە',
    AppLanguage.arabic: 'تم الاتصال - سجّل الدخول الآن برمز PIN الخاص بك',
    AppLanguage.persian: 'اتصال برقرار شد - اکنون با PIN خود وارد شوید',
    AppLanguage.english: 'Connected - now log in with your PIN',
    AppLanguage.turkish: 'Bağlandı - şimdi PIN\'inizle giriş yapın',
  },
  'پەیوەندی سەرکەوتوو نەبوو - دڵنیابە IPـەکەت ڕاستە و ئامێری سێرڤەرەکە لەسەر هەمان وای-فایە': {
    AppLanguage.badini:
        'پەیوەندی سەرکەوتوو نەبوو - دڵنیابە IPـەکەت ڕاستە و ئامێری سێرڤەرەکە لەسەر هەمان وای-فایە',
    AppLanguage.arabic:
        'فشل الاتصال - تأكد أن عنوان IP صحيح وأن جهاز الخادم على نفس شبكة Wi-Fi',
    AppLanguage.persian:
        'اتصال ناموفق بود - مطمئن شوید IP صحیح است و دستگاه سرور روی همان وای‌فای است',
    AppLanguage.english:
        'Connection failed - make sure the IP is correct and the server device is on the same Wi-Fi',
    AppLanguage.turkish:
        'Bağlantı başarısız - IP\'nin doğru olduğundan ve sunucu cihazının aynı Wi-Fi\'de olduğundan emin olun',
  },
  'وایفای پەیوەست نییە - ناتوانیت ببەسترێیتەوە': {
    AppLanguage.badini: 'وایفای پەیوەست نییە - ناتوانیت ببەسترێیتەوە',
    AppLanguage.arabic: 'لا يوجد اتصال Wi-Fi - لا يمكن الاتصال',
    AppLanguage.persian: 'اتصال وای‌فای وجود ندارد - امکان اتصال نیست',
    AppLanguage.english: 'No Wi-Fi connection - cannot connect',
    AppLanguage.turkish: 'Wi-Fi bağlantısı yok - bağlanılamıyor',
  },
  'ئەم PINـە لەم ئامێرەدا نەدۆزرایەوە - دڵنیابە IPـەکە ڕاستە و ئامێرەکە لەسەر هەمان وای-فایە': {
    AppLanguage.badini:
        'ئەم PINـە لەم ئامێرەدا نەدۆزرایەوە - دڵنیابە IPـەکە ڕاستە و ئامێرەکە لەسەر هەمان وای-فایە',
    AppLanguage.arabic:
        'لم يتم العثور على هذا الرمز PIN على هذا الجهاز - تأكد من صحة IP وأن الجهاز على نفس شبكة Wi-Fi',
    AppLanguage.persian:
        'این PIN روی این دستگاه یافت نشد - مطمئن شوید IP صحیح است و دستگاه روی همان وای‌فای است',
    AppLanguage.english:
        'This PIN was not found on this device - make sure the IP is correct and the device is on the same Wi-Fi',
    AppLanguage.turkish:
        'Bu PIN bu cihazda bulunamadı - IP\'nin doğru olduğundan ve cihazın aynı Wi-Fi\'de olduğundan emin olun',
  },
  'چوونە ژوورەوە ناکرێت هەتا ئەو IPـەی بۆ هەژمارەکەت دراوە داخل نەکرێت - لە دوگمەی (!) بەستنەوە بکە': {
    AppLanguage.badini:
        'چوونە ژوورەوە ناکرێت هەتا ئەو IPـەی بۆ هەژمارەکەت دراوە داخل نەکرێت - لە دوگمەی (!) بەستنەوە بکە',
    AppLanguage.arabic:
        'لا يمكن تسجيل الدخول حتى يتم إدخال عنوان IP المخصص لحسابك - اتصل عبر زر (!)',
    AppLanguage.persian:
        'وارد شدن ممکن نیست تا زمانی که IP اختصاص‌داده‌شده به حساب شما وارد نشود - از طریق دکمه (!) متصل شوید',
    AppLanguage.english:
        'Cannot log in until the IP assigned to your account is entered - connect via the (!) button',
    AppLanguage.turkish:
        'Hesabınıza atanan IP girilene kadar giriş yapılamaz - (!) düğmesiyle bağlanın',
  },
  'گەڕانەوە بۆ چوونە ژوورەوە': {
    AppLanguage.badini: 'ڤەگەڕان بۆ تێکەڤتن',
    AppLanguage.arabic: 'العودة إلى تسجيل الدخول',
    AppLanguage.persian: 'بازگشت به ورود',
    AppLanguage.english: 'Back to login',
    AppLanguage.turkish: 'Girişe dön',
  },

  // ===== Network Lockdown (Wi-Fi lost -> whole system locks) =====
  'قوفڵکرا - وایفای نەما': {
    AppLanguage.badini: 'قوفڵکرا - وایفای نەما',
    AppLanguage.arabic: 'مقفل - انقطع الواي فاي',
    AppLanguage.persian: 'قفل شد - وای‌فای قطع شد',
    AppLanguage.english: 'Locked - Wi-Fi Lost',
    AppLanguage.turkish: 'Kilitli - Wi-Fi Kayboldu',
  },
  'قوفڵکرا - تۆڕەکە نەناسراوە': {
    AppLanguage.badini: 'قوفڵکرا - تۆڕەکە نەناسراوە',
    AppLanguage.arabic: 'مقفل - الشبكة غير معروفة',
    AppLanguage.persian: 'قفل شد - شبکه ناشناخته',
    AppLanguage.english: 'Locked - Unknown Network',
    AppLanguage.turkish: 'Kilitli - Bilinmeyen Ağ',
  },
  'سیستەم ڕاوەستاوە بۆ پاراستنی داتاکان. کاتێک وایفای گەڕایەوە، بە خۆکاری دەکرێتەوە.': {
    AppLanguage.badini:
        'سیستەم ڕاوەستایە بۆ پاراستنا داتایان. دەمێ وایفای زڤڕیت، ب خۆکاری ڤەدبیتەڤە.',
    AppLanguage.arabic:
        'النظام متوقف لحماية البيانات. عند عودة الواي فاي، سيعمل تلقائياً.',
    AppLanguage.persian:
        'سیستم برای محافظت از داده‌ها متوقف شده است. با بازگشت وای‌فای، به‌طور خودکار باز می‌شود.',
    AppLanguage.english:
        'The system is stopped to protect your data. When Wi-Fi returns, it will reopen automatically.',
    AppLanguage.turkish:
        'Verilerinizi korumak için sistem durduruldu. Wi-Fi geri geldiğinde otomatik olarak açılır.',
  },
  'لە تۆڕی ڕێستۆرانت نیت. بگەڕێوە بۆ وایفای ڕێستۆرانتەکە و سیستەمەکە بە خۆکاری دەکرێتەوە.': {
    AppLanguage.badini:
        'ل تۆڕا ڕێستۆرانتێ نین. ڤەگەڕە وایفایا ڕێستۆرانتێ و سیستەم ب خۆکاری ڤەدبیتەڤە.',
    AppLanguage.arabic:
        'أنت لست على شبكة المطعم. عد إلى واي فاي المطعم وسيعمل النظام تلقائياً.',
    AppLanguage.persian:
        'شما در شبکه رستوران نیستید. به وای‌فای رستوران برگردید، سیستم به‌طور خودکار باز می‌شود.',
    AppLanguage.english:
        'You are not on the restaurant network. Connect to the restaurant Wi-Fi and the system will reopen automatically.',
    AppLanguage.turkish:
        'Restoran ağında değilsiniz. Restoran Wi-Fi\'ye bağlanın, sistem otomatik olarak açılır.',
  },
  'چاوەڕوانی وایفای...': {
    AppLanguage.badini: 'چاوەڕوانی وایفای...',
    AppLanguage.arabic: 'بانتظار الواي فاي...',
    AppLanguage.persian: 'در انتظار وای‌فای...',
    AppLanguage.english: 'Waiting for Wi-Fi...',
    AppLanguage.turkish: 'Wi-Fi bekleniyor...',
  },

  // ===== Completeness pass: every text used by tr()/trp() speaks all six =====
  'USD \$': {
    AppLanguage.badini: 'USD \$',
    AppLanguage.arabic: 'دولار أمريكي',
    AppLanguage.persian: 'دلار آمریکا',
    AppLanguage.english: 'USD \$',
    AppLanguage.turkish: 'ABD Doları',
  },
  '{count} خواردنی ڕەتکراو': {
    AppLanguage.badini: '{count} خوارنی ڕەتکراو',
    AppLanguage.arabic: '{count} طبق مرفوض',
    AppLanguage.persian: '{count} غذای رد شده',
    AppLanguage.english: '{count} rejected items',
    AppLanguage.turkish: '{count} reddedilen yiyecek',
  },
  '{count} داواکاری نوێ هەڵگیرا، کۆمپانیا سڕ نەکرا': {
    AppLanguage.badini: '{count} داواکاری نوێ هات، کۆمپانیا نەسڕا',
    AppLanguage.arabic: 'تم استلام {count} طلب جديد، لم يتم حذف الشركة',
    AppLanguage.persian: '{count} درخواست جدید دریافت شد، شرکت حذف نشد',
    AppLanguage.english: '{count} new request(s) received; company not deleted',
    AppLanguage.turkish: '{count} yeni istek alındı, şirket silinmedi',
  },
  '{count} داواکاری چاوەڕێی پەیوەندین': {
    AppLanguage.badini: '{count} داواکاری چاوەڕێی پەیوەندییە',
    AppLanguage.arabic: '{count} طلب بانتظار الاتصال',
    AppLanguage.persian: '{count} درخواست در انتظار اتصال',
    AppLanguage.english: '{count} requests waiting to connect',
    AppLanguage.turkish: '{count} istek bağlantı bekliyor',
  },
  '{label} ({count})': {
    AppLanguage.badini: '{label} ({count})',
    AppLanguage.arabic: '{label} ({count})',
    AppLanguage.persian: '{label} ({count})',
    AppLanguage.english: '{label} ({count})',
    AppLanguage.turkish: '{label} ({count})',
  },
  '{name} بە سەرکەوتوویی زیاد کرا (IP: {code})': {
    AppLanguage.badini: '{name} به‌سه‌رکه‌وتوو زیاد کرا (IP: {code})',
    AppLanguage.arabic: 'تمت إضافة {name} بنجاح (IP: {code})',
    AppLanguage.persian: '{name} با موفقیت اضافه شد (IP: {code})',
    AppLanguage.english: '{name} added successfully (IP: {code})',
    AppLanguage.turkish: '{name} başarıyla eklendi (IP: {code})',
  },
  'ئادمێن بزانێت...': {
    AppLanguage.badini: 'ئادمێن بزانێت...',
    AppLanguage.arabic: 'ليعلم الأدمن...',
    AppLanguage.persian: 'تا ادمین بداند...',
    AppLanguage.english: 'Let admin know...',
    AppLanguage.turkish: 'Admin bilsin...',
  },
  'ئاگەدارکردنەوە': {
    AppLanguage.badini: 'ئاگەهداریکردن',
    AppLanguage.arabic: 'إشعار',
    AppLanguage.persian: 'اعلان',
    AppLanguage.english: 'Notify',
    AppLanguage.turkish: 'Bildirim',
  },
  'ئەم ناوە پێشتر زیاد کراوە': {
    AppLanguage.badini: 'ئەم ناوە پێشتر زیاد کرا',
    AppLanguage.arabic: 'تمت إضافة هذا الاسم مسبقاً',
    AppLanguage.persian: 'این نام قبلاً اضافه شده است',
    AppLanguage.english: 'This name was already added',
    AppLanguage.turkish: 'Bu isim daha önce eklendi',
  },
  'بڕایەکی دروست بنووسە (ژمارە تەنیا)': {
    AppLanguage.badini: 'بڕەکێکی دروست بنووسە (تەنها ژمارە)',
    AppLanguage.arabic: 'أدخل مبلغاً صحيحاً (أرقام فقط)',
    AppLanguage.persian: 'مبلغ معتبر وارد کنید (فقط عدد)',
    AppLanguage.english: 'Enter a valid amount (numbers only)',
    AppLanguage.turkish: 'Geçerli bir tutar girin (sadece sayı)',
  },
  'بۆ': {
    AppLanguage.badini: 'بۆ',
    AppLanguage.arabic: 'إلى',
    AppLanguage.persian: 'تا',
    AppLanguage.english: 'to',
    AppLanguage.turkish: 'kadar',
  },
  'بۆ سڕینەوە، یەکێک لەمانە بکە:': {
    AppLanguage.badini: 'بۆ سڕینەوە، یەکێک لەمانە بکە:',
    AppLanguage.arabic: 'للحذف، قم بأحد الخيارات:',
    AppLanguage.persian: 'برای حذف، یکی از این کارها را انجام دهید:',
    AppLanguage.english: 'To delete, do one of these:',
    AppLanguage.turkish: 'Silmek için şunlardan birini yapın:',
  },
  'بۆ مێزی': {
    AppLanguage.badini: 'بۆ مێزی',
    AppLanguage.arabic: 'إلى مائدة',
    AppLanguage.persian: 'به میز',
    AppLanguage.english: 'to table',
    AppLanguage.turkish: 'masaya',
  },
  'بۆ کاشێر/ئادمێن بنوسە...': {
    AppLanguage.badini: 'بۆ کاشێر/ئادمێن بنووسە...',
    AppLanguage.arabic: 'اكتب للكاشير/الأدمن...',
    AppLanguage.persian: 'برای کاشیر/ادمین بنویسید...',
    AppLanguage.english: 'Write to cashier/admin...',
    AppLanguage.turkish: 'Kasiyer/admin için yazın...',
  },
  'بینینی': {
    AppLanguage.badini: 'دیتن',
    AppLanguage.arabic: 'عرض',
    AppLanguage.persian: 'نمایش',
    AppLanguage.english: 'View',
    AppLanguage.turkish: 'Görüntüle',
  },
  'بەروار': {
    AppLanguage.badini: 'بەروار',
    AppLanguage.arabic: 'التاريخ',
    AppLanguage.persian: 'تاریخ',
    AppLanguage.english: 'Date',
    AppLanguage.turkish: 'Tarih',
  },
  'بەکارهێنەرەکە ئەم نیشانەیە لە سیاتینگەکانی خۆیدا دادەنێت؛ بۆ سینککردن پێویستە دروست بێت.': {
    AppLanguage.badini:
        'بەکارهێنەرەکە ئەم نیشانەیە لە سیاتینگەکانی خۆیدا دادەنێت؛ بۆ سینککردن پێویستە دروست بێت.',
    AppLanguage.arabic:
        'يضع المستخدم هذا الرمز في إعداداته الخاصة؛ يجب أن يكون صحيحاً للمزامنة.',
    AppLanguage.persian:
        'کاربر این کد را در تنظیمات خودش قرار می‌دهد؛ برای همگام‌سازی باید درست باشد.',
    AppLanguage.english:
        'The user sets this code in their own settings; it must be correct to sync.',
    AppLanguage.turkish:
        'Kullanıcı bu kodu kendi ayarlarına yazar; senkronizasyon için doğru olması gerekir.',
  },
  'تۆڕ لە دەست چوو': {
    AppLanguage.badini: 'تۆڕ لە دەست چوو',
    AppLanguage.arabic: 'فقد الاتصال بالشبكة',
    AppLanguage.persian: 'اتصال شبکه قطع شد',
    AppLanguage.english: 'Network lost',
    AppLanguage.turkish: 'Ağ bağlantısı kesildi',
  },
  'تێبینی': {
    AppLanguage.badini: 'تێبینی',
    AppLanguage.arabic: 'ملاحظة',
    AppLanguage.persian: 'یادداشت',
    AppLanguage.english: 'Note',
    AppLanguage.turkish: 'Not',
  },
  'تێبینی بۆ ئادمێن': {
    AppLanguage.badini: 'تێبینی بۆ ئادمێن',
    AppLanguage.arabic: 'ملاحظة للأدمن',
    AppLanguage.persian: 'یادداشت برای ادمین',
    AppLanguage.english: 'Note for admin',
    AppLanguage.turkish: 'Admin için not',
  },
  'تێبینی بۆ مێز': {
    AppLanguage.badini: 'تێبینی بۆ مێز',
    AppLanguage.arabic: 'ملاحظة للمائدة',
    AppLanguage.persian: 'یادداشت برای میز',
    AppLanguage.english: 'Note for table',
    AppLanguage.turkish: 'Masa için not',
  },
  'تێبینیی مێزەکان': {
    AppLanguage.badini: 'تێبینیی مێزەکان',
    AppLanguage.arabic: 'ملاحظات الموائد',
    AppLanguage.persian: 'یادداشت‌های میزها',
    AppLanguage.english: 'Table notes',
    AppLanguage.turkish: 'Masa notları',
  },
  'تێبینیی کاپتن': {
    AppLanguage.badini: 'تێبینیی کاپتن',
    AppLanguage.arabic: 'ملاحظة الكابتن',
    AppLanguage.persian: 'یادداشت کاپیتان',
    AppLanguage.english: "Captain's note",
    AppLanguage.turkish: 'Kaptan notu',
  },
  'تێبینی کاشێر': {
    AppLanguage.badini: 'تێبینی کاشێر',
    AppLanguage.arabic: 'ملاحظة الكاشير',
    AppLanguage.persian: 'یادداشت صندوق‌دار',
    AppLanguage.english: "Cashier's note",
    AppLanguage.turkish: 'Kasiyer notu',
  },
  'چاپکردنەوەی وەسڵ': {
    AppLanguage.badini: 'چاپکرنا وەسلی',
    AppLanguage.arabic: 'إعادة طباعة الإيصال',
    AppLanguage.persian: 'چاپ مجدد رسید',
    AppLanguage.english: 'Reprint receipt',
    AppLanguage.turkish: 'Fişi yeniden yazdır',
  },
  'نەتوانرا چاپ بکرێت': {
    AppLanguage.badini: 'نەشیا چاپ بکرت',
    AppLanguage.arabic: 'تعذرت الطباعة',
    AppLanguage.persian: 'چاپ نشد',
    AppLanguage.english: 'Could not print',
    AppLanguage.turkish: 'Yazdırılamadı',
  },
  'هیچ پرێنتەرێکی کاشێر ڕێک نەخراوە': {
    AppLanguage.badini: 'چ پرێنتەرێ کاشێری ڕێک نەخستیە',
    AppLanguage.arabic: 'لا يوجد طابعة كاشير مهيأة',
    AppLanguage.persian: 'هیچ چاپگر صندوق‌داری تنظیم نشده است',
    AppLanguage.english: 'No cashier printer is set up',
    AppLanguage.turkish: 'Kasiyer yazıcısı ayarlanmamış',
  },
  'دیزاینی پرێنت': {
    AppLanguage.badini: 'دیزاینا چاپێ',
    AppLanguage.arabic: 'تصميم الطباعة',
    AppLanguage.persian: 'طراحی چاپ',
    AppLanguage.english: 'Print design',
    AppLanguage.turkish: 'Yazdırma tasarımı',
  },
  'پیشبینین': {
    AppLanguage.badini: 'پێشبینین',
    AppLanguage.arabic: 'معاينة',
    AppLanguage.persian: 'پیش‌نمایش',
    AppLanguage.english: 'Preview',
    AppLanguage.turkish: 'Önizleme',
  },
  'تایبەتمەندییەکان': {
    AppLanguage.badini: 'تایبەتمەندی',
    AppLanguage.arabic: 'التخصيص',
    AppLanguage.persian: 'شخصی‌سازی',
    AppLanguage.english: 'Customization',
    AppLanguage.turkish: 'Özelleştirme',
  },
  'ناوی دوکان': {
    AppLanguage.badini: 'ناڤێ دوکانێ',
    AppLanguage.arabic: 'اسم المتجر',
    AppLanguage.persian: 'نام فروشگاه',
    AppLanguage.english: 'Shop name',
    AppLanguage.turkish: 'Dükkan adı',
  },
  'پیشاندانی ناوی دوکان': {
    AppLanguage.badini: 'نیشاندانا ناڤێ دوکانێ',
    AppLanguage.arabic: 'إظهار اسم المتجر',
    AppLanguage.persian: 'نمایش نام فروشگاه',
    AppLanguage.english: 'Show shop name',
    AppLanguage.turkish: 'Dükkan adını göster',
  },
  'ناونیشانی وەسڵ': {
    AppLanguage.badini: 'ناڤونیشانێ وەسڵی',
    AppLanguage.arabic: 'عنوان الإيصال',
    AppLanguage.persian: 'عنوان رسید',
    AppLanguage.english: 'Receipt title',
    AppLanguage.turkish: 'Fiş başlığı',
  },
  'پیشاندانی ناونیشان': {
    AppLanguage.badini: 'نیشاندانا ناڤونیشانێ',
    AppLanguage.arabic: 'إظهار العنوان',
    AppLanguage.persian: 'نمایش عنوان',
    AppLanguage.english: 'Show title',
    AppLanguage.turkish: 'Başlığı göster',
  },
  'زانیاری': {
    AppLanguage.badini: 'زانیاری',
    AppLanguage.arabic: 'معلومات',
    AppLanguage.persian: 'اطلاعات',
    AppLanguage.english: 'Information',
    AppLanguage.turkish: 'Bilgi',
  },
  'ژمارەی میوان': {
    AppLanguage.badini: 'ژمارا میوانان',
    AppLanguage.arabic: 'عدد الضيوف',
    AppLanguage.persian: 'تعداد مهمان',
    AppLanguage.english: 'Guest count',
    AppLanguage.turkish: 'Misafir sayısı',
  },
  'خواردن و پارە': {
    AppLanguage.badini: 'خوارن و پارە',
    AppLanguage.arabic: 'الطعام والمال',
    AppLanguage.persian: 'غذا و پول',
    AppLanguage.english: 'Food and money',
    AppLanguage.turkish: 'Yemek ve para',
  },
  'کۆی گشتی گەورە': {
    AppLanguage.badini: 'کۆما گشتی یا مەزن',
    AppLanguage.arabic: 'المجموع الكلي بخط كبير',
    AppLanguage.persian: 'جمع کل بزرگ',
    AppLanguage.english: 'Large grand total',
    AppLanguage.turkish: 'Büyük genel toplam',
  },
  'ڕێکخستن': {
    AppLanguage.badini: 'ڕێکخستن',
    AppLanguage.arabic: 'التنسيق',
    AppLanguage.persian: 'چیدمان',
    AppLanguage.english: 'Layout',
    AppLanguage.turkish: 'Düzen',
  },
  'جۆری هێڵ': {
    AppLanguage.badini: 'جۆرێ هێلێ',
    AppLanguage.arabic: 'نوع الخط الفاصل',
    AppLanguage.persian: 'نوع خط جداکننده',
    AppLanguage.english: 'Separator style',
    AppLanguage.turkish: 'Ayırıcı stili',
  },
  'هێڵی داشە': {
    AppLanguage.badini: 'هێلین داشێ',
    AppLanguage.arabic: 'خط متقطع',
    AppLanguage.persian: 'خط تیره',
    AppLanguage.english: 'Dashed',
    AppLanguage.turkish: 'Kesikli',
  },
  'هێڵی دووانە': {
    AppLanguage.badini: 'هێلین دووجار',
    AppLanguage.arabic: 'خط مزدوج',
    AppLanguage.persian: 'خط دوتایی',
    AppLanguage.english: 'Double',
    AppLanguage.turkish: 'Çift',
  },
  'خاڵ': {
    AppLanguage.badini: 'خاڵ',
    AppLanguage.arabic: 'نقاط',
    AppLanguage.persian: 'نقطه',
    AppLanguage.english: 'Dots',
    AppLanguage.turkish: 'Nokta',
  },
  'پانی کاغەز': {
    AppLanguage.badini: 'پانیێ کاغەزێ',
    AppLanguage.arabic: 'عرض الورق',
    AppLanguage.persian: 'عرض کاغذ',
    AppLanguage.english: 'Paper width',
    AppLanguage.turkish: 'Kağıt genişliği',
  },
  'هێڵی سپی پێش بڕین': {
    AppLanguage.badini: 'هێلێن سپی بەری برینێ',
    AppLanguage.arabic: 'أسطر فارغة قبل القطع',
    AppLanguage.persian: 'خط خالی قبل از برش',
    AppLanguage.english: 'Blank lines before cut',
    AppLanguage.turkish: 'Kesimden önce boş satırlar',
  },
  'دەقی خوارەوە': {
    AppLanguage.badini: 'نڤیسا بنی',
    AppLanguage.arabic: 'نص التذييل',
    AppLanguage.persian: 'متن پایین',
    AppLanguage.english: 'Footer text',
    AppLanguage.turkish: 'Alt bilgi metni',
  },
  'پیشاندانی دەقی خوارەوە': {
    AppLanguage.badini: 'نیشاندانا نڤیسا بنی',
    AppLanguage.arabic: 'إظهار نص التذييل',
    AppLanguage.persian: 'نمایش متن پایین',
    AppLanguage.english: 'Show footer',
    AppLanguage.turkish: 'Alt bilgiyi göster',
  },
  'چاپی تاقیکردنەوە': {
    AppLanguage.badini: 'چاپێ تاقیکرنێ',
    AppLanguage.arabic: 'طباعة تجريبية',
    AppLanguage.persian: 'چاپ آزمایشی',
    AppLanguage.english: 'Test print',
    AppLanguage.turkish: 'Deneme yazdırması',
  },
  'گەڕاندنەوە بۆ ڕەسەن': {
    AppLanguage.badini: 'زڤڕاندن بۆ ڕەسەن',
    AppLanguage.arabic: 'إعادة إلى الافتراضي',
    AppLanguage.persian: 'بازگشت به پیش‌فرض',
    AppLanguage.english: 'Reset to default',
    AppLanguage.turkish: 'Varsayılana sıfırla',
  },
  'دیزاینەکە پاشەکەوت کرا': {
    AppLanguage.badini: 'دیزاین هاتە پاشەکەوتکرن',
    AppLanguage.arabic: 'تم حفظ التصميم',
    AppLanguage.persian: 'طراحی ذخیره شد',
    AppLanguage.english: 'Design saved',
    AppLanguage.turkish: 'Tasarım kaydedildi',
  },
  'چاپکرا': {
    AppLanguage.badini: 'هاتە چاپکرن',
    AppLanguage.arabic: 'تمت الطباعة',
    AppLanguage.persian: 'چاپ شد',
    AppLanguage.english: 'Printed',
    AppLanguage.turkish: 'Yazdırıldı',
  },
  'تەنها بینین؛ گواستنەوە بۆ مێز تەنها کاشێر دەکات': {
    AppLanguage.badini: 'تەنها دیتن؛ گواستنەوە بۆ مێز تەنها کاشێر دەکات',
    AppLanguage.arabic: 'عرض فقط؛ نقل المائدة لا يتم إلا بواسطة الكاشير',
    AppLanguage.persian: 'فقط نمایش؛ انتقال به میز فقط توسط کاشیر',
    AppLanguage.english: 'View only; only the cashier can move it to a table',
    AppLanguage.turkish: 'Sadece görüntüleme; masaya taşımayı yalnızca kasiyer yapabilir',
  },
  'خاوەن سیستەم': {
    AppLanguage.badini: 'خاوەنی سیستەم',
    AppLanguage.arabic: 'مالك النظام',
    AppLanguage.persian: 'صاحب سیستم',
    AppLanguage.english: 'System owner',
    AppLanguage.turkish: 'Sistem sahibi',
  },
  'د.ع {amount}': {
    AppLanguage.badini: 'د.ع {amount}',
    AppLanguage.arabic: 'د.ع {amount}',
    AppLanguage.persian: 'د.ع {amount}',
    AppLanguage.english: 'IQD {amount}',
    AppLanguage.turkish: 'IQD {amount}',
  },
  'داخراوە': {
    AppLanguage.badini: 'داخر',
    AppLanguage.arabic: 'مغلق',
    AppLanguage.persian: 'بسته',
    AppLanguage.english: 'Closed',
    AppLanguage.turkish: 'Kapalı',
  },
  'دانە': {
    AppLanguage.badini: 'دانە',
    AppLanguage.arabic: 'قطعة',
    AppLanguage.persian: 'عدد',
    AppLanguage.english: 'pcs',
    AppLanguage.turkish: 'adet',
  },
  'داواکاری خواردن': {
    AppLanguage.badini: 'داواکاری خوارن',
    AppLanguage.arabic: 'طلبات الطعام',
    AppLanguage.persian: 'درخواست غذا',
    AppLanguage.english: 'Food requests',
    AppLanguage.turkish: 'Yiyecek talepleri',
  },
  'داواکاری دوبارە نێردرا': {
    AppLanguage.badini: 'داواکاری دوبارە نێردرا',
    AppLanguage.arabic: 'تم إرسال الطلب مرة أخرى',
    AppLanguage.persian: 'درخواست دوباره ارسال شد',
    AppLanguage.english: 'Request sent again',
    AppLanguage.turkish: 'İstek yeniden gönderildi',
  },
  'داواکراوی حیساب': {
    AppLanguage.badini: 'داواکراوی حیساب',
    AppLanguage.arabic: 'طلب الحساب',
    AppLanguage.persian: 'حساب درخواست شد',
    AppLanguage.english: 'Bill requested',
    AppLanguage.turkish: 'Hesap istendi',
  },
  'دروستکردنی نوێ': {
    AppLanguage.badini: 'دروستکردنی نوێ',
    AppLanguage.arabic: 'إنشاء جديد',
    AppLanguage.persian: 'ایجاد جدید',
    AppLanguage.english: 'Create new',
    AppLanguage.turkish: 'Yeni oluştur',
  },
  'دوبارە ناردن': {
    AppLanguage.badini: 'دوبارە ناردن',
    AppLanguage.arabic: 'إعادة الإرسال',
    AppLanguage.persian: 'ارسال دوباره',
    AppLanguage.english: 'Send again',
    AppLanguage.turkish: 'Yeniden gönder',
  },
  'دوبارە پرێنت': {
    AppLanguage.badini: 'دوبارە پرێنت',
    AppLanguage.arabic: 'إعادة الطباعة',
    AppLanguage.persian: 'چاپ دوباره',
    AppLanguage.english: 'Print again',
    AppLanguage.turkish: 'Yeniden yazdır',
  },
  'دوبارە پرێنت کردن': {
    AppLanguage.badini: 'دوبارە پرێنت کردن',
    AppLanguage.arabic: 'إعادة الطباعة',
    AppLanguage.persian: 'چاپ مجدد',
    AppLanguage.english: 'Reprint',
    AppLanguage.turkish: 'Yeniden yazdırma',
  },
  'دڵنیایت دەتەوێت دەربچیت؟': {
    AppLanguage.badini: 'دڵنیایت دەتەوێت دەربچیت؟',
    AppLanguage.arabic: 'هل أنت متأكد من تسجيل الخروج؟',
    AppLanguage.persian: 'آیا مطمئن هستید که می‌خواهید خارج شوید؟',
    AppLanguage.english: 'Are you sure you want to log out?',
    AppLanguage.turkish: 'Çıkış yapmak istediğinize emin misiniz?',
  },
  'دڵنیایت دەتەوێت هەموو داتاکان بسڕیتەوە؟ هەموو حیسابەکان، قەرزەکان، ئۆردەرەکان و مێزەکان دەسڕدرێنەوە و بۆ دۆخە سەرەتاییەکە دەگەڕێتەوە. ئەم کارە ناتوانرێت بگەڕێتەوە.': {
    AppLanguage.badini:
        'دڵنیایت دەتەوێت هەموو داتاکان بسڕیتەوە؟ هەموو حیسابەکان، قەرزەکان، ئۆردەرەکان و مێزەکان دەسڕدرێنەوە و بۆ دۆخە سەرەتاییەکە دەگەڕێتەوە. ئەم کارە ناتوانرێت بگەڕێتەوە.',
    AppLanguage.arabic:
        'هل أنت متأكد من حذف جميع البيانات؟ سيتم حذف جميع الحسابات والديون والطلبات والموائد والعودة إلى الحالة الأولية. لا يمكن التراجع عن هذه العملية.',
    AppLanguage.persian:
        'آیا مطمئن هستید که می‌خواهید همه داده‌ها را حذف کنید؟ تمام حساب‌ها، بدهی‌ها، سفارش‌ها و میزها حذف می‌شوند و به حالت اولیه برمی‌گردد. این کار قابل بازگشت نیست.',
    AppLanguage.english:
        'Are you sure you want to delete all data? All accounts, debts, orders and tables will be deleted and the system returns to its initial state. This cannot be undone.',
    AppLanguage.turkish:
        'Tüm verileri silmek istediğinize emin misiniz? Tüm hesaplar, borçlar, siparişler ve masalar silinir ve sistem ilk durumuna döner. Bu işlem geri alınamaz.',
  },
  'دۆخی ئێستای مێز': {
    AppLanguage.badini: 'دۆخی ئێستای مێز',
    AppLanguage.arabic: 'الحالة الحالية للمائدة',
    AppLanguage.persian: 'وضعیت فعلی میز',
    AppLanguage.english: 'Current table status',
    AppLanguage.turkish: 'Masanın mevcut durumu',
  },
  'دۆخی ناردنی داواکاری': {
    AppLanguage.badini: 'دۆخی ناردنی داواکاری',
    AppLanguage.arabic: 'حالة إرسال الطلب',
    AppLanguage.persian: 'وضعیت ارسال درخواست',
    AppLanguage.english: 'Request sending status',
    AppLanguage.turkish: 'İstek gönderme durumu',
  },
  'دۆخی ئۆردەر': {
    AppLanguage.badini: 'دۆخی ئۆردەر',
    AppLanguage.arabic: 'حالة الطلب',
    AppLanguage.persian: 'وضعیت سفارش',
    AppLanguage.english: 'Order status',
    AppLanguage.turkish: 'Sipariş durumu',
  },
  'دیاریکردنی مێز': {
    AppLanguage.badini: 'دیاریکردنی مێز',
    AppLanguage.arabic: 'اختيار المائدة',
    AppLanguage.persian: 'انتخاب میز',
    AppLanguage.english: 'Select table',
    AppLanguage.turkish: 'Masa seçimi',
  },
  'دیاریکردنی مێز بۆ {name}': {
    AppLanguage.badini: 'دیاریکردنی مێز بۆ {name}',
    AppLanguage.arabic: 'اختيار المائدة لـ {name}',
    AppLanguage.persian: 'انتخاب میز برای {name}',
    AppLanguage.english: 'Select table for {name}',
    AppLanguage.turkish: '{name} için masa seçimi',
  },
  'دیاریکردنی مەودای مێز': {
    AppLanguage.badini: 'دیاریکردنی مەودای مێز',
    AppLanguage.arabic: 'اختيار نطاق الموائد',
    AppLanguage.persian: 'انتخاب محدوده میز',
    AppLanguage.english: 'Select table range',
    AppLanguage.turkish: 'Masa aralığı seçimi',
  },
  'دیاریکردنی مەودای مێز بۆ {name}': {
    AppLanguage.badini: 'دیاریکردنی مەودای مێز بۆ {name}',
    AppLanguage.arabic: 'اختيار نطاق الموائد لـ {name}',
    AppLanguage.persian: 'انتخاب محدوده میز برای {name}',
    AppLanguage.english: 'Select table range for {name}',
    AppLanguage.turkish: '{name} için masa aralığı seçimi',
  },
  'گەڕاندنەوە بۆ ئاسایی': {
    AppLanguage.badini: 'گەڕاندنەوە بۆ ئاسایی',
    AppLanguage.arabic: 'إعادة التعيين إلى الحالة الطبيعية',
    AppLanguage.persian: 'بازگشت به حالت عادی',
    AppLanguage.english: 'Reset to normal',
    AppLanguage.turkish: 'Normale sıfırla',
  },
  'زانیاری مێزی {tableNumber}': {
    AppLanguage.badini: 'زانیاری مێزی {tableNumber}',
    AppLanguage.arabic: 'معلومات المائدة {tableNumber}',
    AppLanguage.persian: 'اطلاعات میز {tableNumber}',
    AppLanguage.english: 'Table {tableNumber} info',
    AppLanguage.turkish: '{tableNumber} numaralı masa bilgisi',
  },
  'زمان': {
    AppLanguage.badini: 'زمان',
    AppLanguage.arabic: 'اللغة',
    AppLanguage.persian: 'زبان',
    AppLanguage.english: 'Language',
    AppLanguage.turkish: 'Dil',
  },
  'زیرەکی کاپتن': {
    AppLanguage.badini: 'زیرەکی کاپتن',
    AppLanguage.arabic: 'ذكاء الكابتن',
    AppLanguage.persian: 'هوش کاپیتان',
    AppLanguage.english: 'Captain intelligence',
    AppLanguage.turkish: 'Kaptan zekâsı',
  },
  'وردەکاری زیاتر': {
    AppLanguage.badini: 'وردەکاری زیاتر',
    AppLanguage.arabic: 'تفاصيل أكثر',
    AppLanguage.persian: 'جزئیات بیشتر',
    AppLanguage.english: 'More details',
    AppLanguage.turkish: 'Daha fazla detay',
  },
  'سڕینەوە نەکرا - خواردنی تێدایە': {
    AppLanguage.badini: 'سڕینەوە نەکرا - خوارنی تێدایە',
    AppLanguage.arabic: 'لم يتم الحذف - يحتوي على طعام',
    AppLanguage.persian: 'حذف نشد - غذا دارد',
    AppLanguage.english: 'Not deleted - it contains items',
    AppLanguage.turkish: 'Silinmedi - içinde yiyecek var',
  },
  'سڕینەوەی هەموو داتاکان': {
    AppLanguage.badini: 'سڕینەوەی هەموو داتاکان',
    AppLanguage.arabic: 'حذف جميع البيانات',
    AppLanguage.persian: 'حذف همه داده‌ها',
    AppLanguage.english: 'Delete all data',
    AppLanguage.turkish: 'Tüm verileri sil',
  },
  'سینک چالاکە': {
    AppLanguage.badini: 'سینک چالاکە',
    AppLanguage.arabic: 'المزامنة نشطة',
    AppLanguage.persian: 'همگام‌سازی فعال است',
    AppLanguage.english: 'Sync active',
    AppLanguage.turkish: 'Senkronizasyon aktif',
  },
  'فلتەری خواردن': {
    AppLanguage.badini: 'فلتەری خوارن',
    AppLanguage.arabic: 'فلتر الطعام',
    AppLanguage.persian: 'فیلتر غذا',
    AppLanguage.english: 'Food filter',
    AppLanguage.turkish: 'Yiyecek filtresi',
  },
  'لە مێزی': {
    AppLanguage.badini: 'لە مێزی',
    AppLanguage.arabic: 'من مائدة',
    AppLanguage.persian: 'از میز',
    AppLanguage.english: 'from table',
    AppLanguage.turkish: 'masadan',
  },
  'لە نێوان {min} و {max} دەبێت بێت': {
    AppLanguage.badini: 'لە نێوان {min} و {max} دەبێت بێت',
    AppLanguage.arabic: 'يجب أن يكون بين {min} و {max}',
    AppLanguage.persian: 'باید بین {min} و {max} باشد',
    AppLanguage.english: 'It must be between {min} and {max}',
    AppLanguage.turkish: '{min} ile {max} arasında olmalıdır',
  },
  'مێزی {name}': {
    AppLanguage.badini: 'مێزی {name}',
    AppLanguage.arabic: 'مائدة {name}',
    AppLanguage.persian: 'میز {name}',
    AppLanguage.english: 'Table {name}',
    AppLanguage.turkish: 'Masa {name}',
  },
  'مێزە دیاریکراوەکان': {
    AppLanguage.badini: 'مێزە دیاریکراوەکان',
    AppLanguage.arabic: 'الموائد المختارة',
    AppLanguage.persian: 'میزهای انتخاب‌شده',
    AppLanguage.english: 'Selected tables',
    AppLanguage.turkish: 'Seçili masalar',
  },
  'مێزەکە لە لایان کێ کرایەوە': {
    AppLanguage.badini: 'مێزەکە لە لایان کێ کرایەوە',
    AppLanguage.arabic: 'تم سحب المائدة منهم',
    AppLanguage.persian: 'میز از آن‌ها گرفته شد',
    AppLanguage.english: 'The table was taken from them',
    AppLanguage.turkish: 'Masa onlardan alındı',
  },
  'مەودا': {
    AppLanguage.badini: 'مەودا',
    AppLanguage.arabic: 'النطاق',
    AppLanguage.persian: 'محدوده',
    AppLanguage.english: 'Range',
    AppLanguage.turkish: 'Aralık',
  },
  'ناردنی ئاگەدارکردنەوە بۆ کاشێر': {
    AppLanguage.badini: 'ناردنی ئاگەهداری بۆ کاشێر',
    AppLanguage.arabic: 'إرسال إشعار إلى الكاشير',
    AppLanguage.persian: 'ارسال اعلان به کاشیر',
    AppLanguage.english: 'Notify the cashier',
    AppLanguage.turkish: 'Kasiyere bildirim gönder',
  },
  'ناو پێویستە': {
    AppLanguage.badini: 'ناو پێویستە',
    AppLanguage.arabic: 'الاسم مطلوب',
    AppLanguage.persian: 'نام الزامی است',
    AppLanguage.english: 'Name is required',
    AppLanguage.turkish: 'İsim gereklidir',
  },
  'نوێکردنەوە': {
    AppLanguage.badini: 'نوێکردنەوە',
    AppLanguage.arabic: 'تحديث',
    AppLanguage.persian: 'به‌روزرسانی',
    AppLanguage.english: 'Refresh',
    AppLanguage.turkish: 'Yenile',
  },
  'نیشانەی IP بۆ {name}': {
    AppLanguage.badini: 'نیشانەی IP بۆ {name}',
    AppLanguage.arabic: 'رمز IP لـ {name}',
    AppLanguage.persian: 'کد IP برای {name}',
    AppLanguage.english: 'IP code for {name}',
    AppLanguage.turkish: '{name} için IP kodu',
  },
  'نێردراوە': {
    AppLanguage.badini: 'نێردراوە',
    AppLanguage.arabic: 'تم الإرسال',
    AppLanguage.persian: 'ارسال شد',
    AppLanguage.english: 'Sent',
    AppLanguage.turkish: 'Gönderildi',
  },
  'نەتوانرێت سڕبدرێتەوە': {
    AppLanguage.badini: 'نەتوانرێت سڕبدرێتەوە',
    AppLanguage.arabic: 'لا يمكن حذفه',
    AppLanguage.persian: 'قابل حذف نیست',
    AppLanguage.english: 'Cannot be deleted',
    AppLanguage.turkish: 'Silinemez',
  },
  'نەگەیشت': {
    AppLanguage.badini: 'نەگەیشت',
    AppLanguage.arabic: 'لم يصل',
    AppLanguage.persian: 'نرسید',
    AppLanguage.english: 'Not received',
    AppLanguage.turkish: 'Ulaşmadı',
  },
  'هیچ تێبینییەک نییە': {
    AppLanguage.badini: 'هیچ تێبینییەک نییە',
    AppLanguage.arabic: 'لا توجد ملاحظات',
    AppLanguage.persian: 'یادداشتی وجود ندارد',
    AppLanguage.english: 'No notes',
    AppLanguage.turkish: 'Not yok',
  },
  'هیچ خواردنێک نەفرۆشراوە لەم ماوەیە': {
    AppLanguage.badini: 'هیچ خوارنێک نەفرۆشراوە لەم ماوەیە',
    AppLanguage.arabic: 'لم يتم بيع أي طعام في هذه الفترة',
    AppLanguage.persian: 'در این مدت هیچ غذایی فروخته نشده است',
    AppLanguage.english: 'No food sold in this period',
    AppLanguage.turkish: 'Bu dönemde satılan yiyecek yok',
  },
  'هیچ خواردنێکی ڕەتکراو نییە': {
    AppLanguage.badini: 'هیچ خوارنێکی ڕەتکراو نییە',
    AppLanguage.arabic: 'لا توجد أطعمة مرفوضة',
    AppLanguage.persian: 'غذای رد شده‌ای وجود ندارد',
    AppLanguage.english: 'No rejected items',
    AppLanguage.turkish: 'Reddedilen yiyecek yok',
  },
  'هیچ زانیاریەک نییە': {
    AppLanguage.badini: 'هیچ زانیاریەک نییە',
    AppLanguage.arabic: 'لا توجد بيانات',
    AppLanguage.persian: 'داده‌ای وجود ندارد',
    AppLanguage.english: 'No data',
    AppLanguage.turkish: 'Veri yok',
  },
  'هیچ مێزێک نییە': {
    AppLanguage.badini: 'هیچ مێزێک نییە',
    AppLanguage.arabic: 'لا توجد موائد',
    AppLanguage.persian: 'میزی وجود ندارد',
    AppLanguage.english: 'No tables',
    AppLanguage.turkish: 'Masa yok',
  },
  'هەر بەکارهێنەرێکی نوێ دەستبەجێ بۆ هەموو ئامێرەکانی تۆڕەکە دەنێردرێت': {
    AppLanguage.badini:
        'هەر بەکارهێنەرێکی نوێ دەستبەجێ بۆ هەموو ئامێرەکانی تۆڕەکە دەنێردرێت',
    AppLanguage.arabic: 'يتم إرسال كل مستخدم جديد فوراً إلى جميع أجهزة الشبكة',
    AppLanguage.persian: 'هر کاربر جدید بلافاصله به همه دستگاه‌های شبکه ارسال می‌شود',
    AppLanguage.english: 'Every new user is sent to all devices on the network immediately',
    AppLanguage.turkish: 'Her yeni kullanıcı anında ağdaki tüm cihazlara gönderilir',
  },
  'هەموو حیساب و ئۆردەر و قەرزەکان دەسڕێتەوە': {
    AppLanguage.badini: 'هەموو حیساب و ئۆردەر و قەرزەکان دەسڕێتەوە',
    AppLanguage.arabic: 'سيحذف جميع الحسابات والطلبات والديون',
    AppLanguage.persian: 'همه حساب‌ها، سفارش‌ها و بدهی‌ها حذف می‌شوند',
    AppLanguage.english: 'Deletes all bills, orders and debts',
    AppLanguage.turkish: 'Tüm hesapları, siparişleri ve borçları siler',
  },
  'هەموو داتاکان سڕانەوە و بۆ دۆخە سەرەتاییەکە گەڕایەوە': {
    AppLanguage.badini: 'هەموو داتاکان سڕانەوە و بۆ دۆخە سەرەتاییەکە گەڕایەوە',
    AppLanguage.arabic: 'تم حذف جميع البيانات والعودة إلى الحالة الأولية',
    AppLanguage.persian: 'همه داده‌ها حذف شد و به حالت اولیه بازگشت',
    AppLanguage.english: 'All data deleted and the system returned to its initial state',
    AppLanguage.turkish: 'Tüm veriler silindi ve sistem ilk durumuna döndü',
  },
  'هەڵوەشاندنەوە': {
    AppLanguage.badini: 'هەڵوەشاندنەوە',
    AppLanguage.arabic: 'إلغاء',
    AppLanguage.persian: 'انصراف',
    AppLanguage.english: 'Cancel',
    AppLanguage.turkish: 'İptal',
  },
  'هەڵەیەک ڕوویدا لە زیادکردندا': {
    AppLanguage.badini: 'هەڵەیەک ڕوویدا لە زیادکردندا',
    AppLanguage.arabic: 'حدث خطأ أثناء الإضافة',
    AppLanguage.persian: 'هنگام افزودن خطایی رخ داد',
    AppLanguage.english: 'An error occurred while adding',
    AppLanguage.turkish: 'Eklerken bir hata oluştu',
  },
  'هەڵەیەک ڕوویدا لە خوێندنەوە': {
    AppLanguage.badini: 'خەلەتییەک ڕوویدا د خواندنێ دا',
    AppLanguage.arabic: 'حدث خطأ أثناء القراءة',
    AppLanguage.persian: 'هنگام خواندن خطایی رخ داد',
    AppLanguage.english: 'Could not load the data',
    AppLanguage.turkish: 'Veriler yüklenemedi',
  },
  'گوازدنەوە سەرکەوتوو نەبوو': {
    AppLanguage.badini: 'گوهۆڕین سەرکەفتی نەبوو',
    AppLanguage.arabic: 'تعذّر النقل',
    AppLanguage.persian: 'انتقال انجام نشد',
    AppLanguage.english: 'Could not move the order',
    AppLanguage.turkish: 'Taşıma yapılamadı',
  },
  'پەیوەندی پچڕاوە': {
    AppLanguage.badini: 'گرهک پچرییە',
    AppLanguage.arabic: 'الاتصال مقطوع',
    AppLanguage.persian: 'اتصال قطع است',
    AppLanguage.english: 'Disconnected',
    AppLanguage.turkish: 'Bağlantı kesildi',
  },
  'سێرڤەر: {ip} | {count} ئامێر': {
    AppLanguage.badini: 'سێرڤەر: {ip} | {count} ئامێر',
    AppLanguage.arabic: 'الخادم: {ip} | {count} جهاز',
    AppLanguage.persian: 'سرور: {ip} | {count} دستگاه',
    AppLanguage.english: 'Server: {ip} | {count} device(s)',
    AppLanguage.turkish: 'Sunucu: {ip} | {count} cihaz',
  },
  'وەرگرتنی قەرز': {
    AppLanguage.badini: 'وەرگرتنا قەرزێ',
    AppLanguage.arabic: 'تحصيل الدين',
    AppLanguage.persian: 'دریافت بدهی',
    AppLanguage.english: 'Collect the debt',
    AppLanguage.turkish: 'Borcu tahsil et',
  },
  'فاست فوود': {
    AppLanguage.badini: 'فاست فوود',
    AppLanguage.arabic: 'وجبات سريعة',
    AppLanguage.persian: 'فست‌فود',
    AppLanguage.english: 'Fast food',
    AppLanguage.turkish: 'Fast food',
  },
  'برژاو': {
    AppLanguage.badini: 'برژای',
    AppLanguage.arabic: 'مشاوي',
    AppLanguage.persian: 'کباب',
    AppLanguage.english: 'Grill',
    AppLanguage.turkish: 'Izgara',
  },
  'برنج': {
    AppLanguage.badini: 'برنج',
    AppLanguage.arabic: 'أرز',
    AppLanguage.persian: 'برنج',
    AppLanguage.english: 'Rice',
    AppLanguage.turkish: 'Pilav',
  },
  'خواردنەوە': {
    AppLanguage.badini: 'ڤەخوارن',
    AppLanguage.arabic: 'مشروب',
    AppLanguage.persian: 'نوشیدنی',
    AppLanguage.english: 'Drink',
    AppLanguage.turkish: 'İçecek',
  },
  'شۆربە': {
    AppLanguage.badini: 'شۆربە',
    AppLanguage.arabic: 'شوربة',
    AppLanguage.persian: 'سوپ',
    AppLanguage.english: 'Soup',
    AppLanguage.turkish: 'Çorba',
  },
  'ئایسکریم': {
    AppLanguage.badini: 'ئایسکریم',
    AppLanguage.arabic: 'مثلجات',
    AppLanguage.persian: 'بستنی',
    AppLanguage.english: 'Ice cream',
    AppLanguage.turkish: 'Dondurma',
  },
  'قاوە': {
    AppLanguage.badini: 'قەهوە',
    AppLanguage.arabic: 'قهوة',
    AppLanguage.persian: 'قهوه',
    AppLanguage.english: 'Coffee',
    AppLanguage.turkish: 'Kahve',
  },
  'هێلکە': {
    AppLanguage.badini: 'هێک',
    AppLanguage.arabic: 'بيض',
    AppLanguage.persian: 'تخم‌مرغ',
    AppLanguage.english: 'Egg',
    AppLanguage.turkish: 'Yumurta',
  },
  'سەوزە': {
    AppLanguage.badini: 'سەوزە',
    AppLanguage.arabic: 'خضار',
    AppLanguage.persian: 'سبزیجات',
    AppLanguage.english: 'Vegetables',
    AppLanguage.turkish: 'Sebze',
  },
  '{count} مێزی {name} خواردنی تێدایە. پێش سڕینەوە دەبێت هەریەکە ڕادەخرێت یان دەنرێتەوە.': {
    AppLanguage.badini:
        '{count} ماسەیێن {name} خوارن تێدا یە. بەری ژێبرنێ دڤێت هەر یەک واسڵ ببیت یان ڤەگەڕێت.',
    AppLanguage.arabic:
        'يوجد {count} طاولة من {name} تحتوي على طعام. قبل الحذف يجب تسوية كل واحدة أو إرجاعها.',
    AppLanguage.persian:
        '{count} میز از {name} غذا دارند. پیش از حذف باید هر کدام تسویه شود یا برگردانده شود.',
    AppLanguage.english:
        '{count} tables of {name} have food. Before deleting, each must be settled or returned.',
    AppLanguage.turkish:
        '{name} için {count} masada yemek var. Silmeden önce her birinin hesabı kapatılmalı veya iade edilmelidir.',
  },
  'و {count} مێزی تر...': {
    AppLanguage.badini: 'و {count} مێزی تر...',
    AppLanguage.arabic: 'و {count} موائد أخرى...',
    AppLanguage.persian: 'و {count} میز دیگر...',
    AppLanguage.english: 'and {count} more tables...',
    AppLanguage.turkish: 've {count} masa daha...',
  },
  'وشەی نهێنی (٥ ژمارە)': {
    AppLanguage.badini: 'وشەی نهێنی (٥ ژمارە)',
    AppLanguage.arabic: 'كلمة السر (5 أرقام)',
    AppLanguage.persian: 'رمز عبور (۵ رقم)',
    AppLanguage.english: 'PIN (5 digits)',
    AppLanguage.turkish: 'Şifre (5 hane)',
  },
  'وشەی نهێنی دەبێت ٥ ژمارە بێت': {
    AppLanguage.badini: 'وشەی نهێنی دەبێت ٥ ژمارە بێت',
    AppLanguage.arabic: 'يجب أن تكون كلمة السر 5 أرقام',
    AppLanguage.persian: 'رمز عبور باید ۵ رقم باشد',
    AppLanguage.english: 'PIN must be 5 digits',
    AppLanguage.turkish: 'Şifre 5 hane olmalıdır',
  },
  'وەیتەرەکە تەنها ئەو مێزانە دەبینێت کە لە نێوان مەوداکەدان (لە {start} بۆ {end})': {
    AppLanguage.badini:
        'وەیتەرەکە تەنها ئەو مێزانە دەبینێت کە لە نێوان مەوداکەدان (لە {start} بۆ {end})',
    AppLanguage.arabic:
        'يرى النادل فقط الموائد الواقعة ضمن النطاق (من {start} إلى {end})',
    AppLanguage.persian:
        'گارسون فقط میزهای داخل محدوده را می‌بیند (از {start} تا {end})',
    AppLanguage.english:
        'The waiter only sees tables within the range (from {start} to {end})',
    AppLanguage.turkish:
        'Garson yalnızca aralıktaki masaları görür ({start} ile {end} arası)',
  },
  'پاشەکەوت کرا - بەستەرەکە نوێ کرایەوە': {
    AppLanguage.badini: 'پاشەکەوت کرا - بەستەرەکە نوێ کرایەوە',
    AppLanguage.arabic: 'تم الحفظ - تم تجديد الرابط',
    AppLanguage.persian: 'ذخیره شد - اتصال به‌روزرسانی شد',
    AppLanguage.english: 'Saved - the link was renewed',
    AppLanguage.turkish: 'Kaydedildi - bağlantı yenilendi',
  },
  'پاشەکەوتکردن': {
    AppLanguage.badini: 'پاشەکەوتکردن',
    AppLanguage.arabic: 'حفظ',
    AppLanguage.persian: 'ذخیره',
    AppLanguage.english: 'Save',
    AppLanguage.turkish: 'Kaydet',
  },
  'پرێنت': {
    AppLanguage.badini: 'پرێنت',
    AppLanguage.arabic: 'طباعة',
    AppLanguage.persian: 'چاپ',
    AppLanguage.english: 'Print',
    AppLanguage.turkish: 'Yazdır',
  },
  'پوختەی دارایی': {
    AppLanguage.badini: 'پوختەی دارایی',
    AppLanguage.arabic: 'الملخص المالي',
    AppLanguage.persian: 'خلاصه مالی',
    AppLanguage.english: 'Financial summary',
    AppLanguage.turkish: 'Mali özet',
  },
  'چەند میوان دانیشتووە': {
    AppLanguage.badini: 'چەند میوان دانیشتووە',
    AppLanguage.arabic: 'كم عدد الضيوف الجالسين',
    AppLanguage.persian: 'چند مهمان نشسته است',
    AppLanguage.english: 'How many guests are seated',
    AppLanguage.turkish: 'Kaç misafir oturuyor',
  },
  'ڕێخستن': {
    AppLanguage.badini: 'ڕێخستن',
    AppLanguage.arabic: 'الإعدادات',
    AppLanguage.persian: 'تنظیمات',
    AppLanguage.english: 'Settings',
    AppLanguage.turkish: 'Ayarlar',
  },
  'ڕەتکراوەکان': {
    AppLanguage.badini: 'ڕەتکراوەکان',
    AppLanguage.arabic: 'المرفوضة',
    AppLanguage.persian: 'رد شده‌ها',
    AppLanguage.english: 'Rejected',
    AppLanguage.turkish: 'Reddedilenler',
  },
  'ڕەتکردنەوەی داواکاری': {
    AppLanguage.badini: 'ڕەتکردنەوەی داواکاری',
    AppLanguage.arabic: 'رفض الطلب',
    AppLanguage.persian: 'رد درخواست',
    AppLanguage.english: 'Reject request',
    AppLanguage.turkish: 'İsteği reddet',
  },
  'کاتی داواکردن': {
    AppLanguage.badini: 'کاتی داواکرن',
    AppLanguage.arabic: 'وقت الطلب',
    AppLanguage.persian: 'زمان سفارش',
    AppLanguage.english: 'Ordered at',
    AppLanguage.turkish: 'Sipariş zamanı',
  },
  'کاتی ڕەتکردنەوە': {
    AppLanguage.badini: 'کاتی ڕەتکرنەوە',
    AppLanguage.arabic: 'وقت الرفض',
    AppLanguage.persian: 'زمان رد',
    AppLanguage.english: 'Rejected at',
    AppLanguage.turkish: 'Reddedilme zamanı',
  },
  'داواکەر': {
    AppLanguage.badini: 'داواکەر',
    AppLanguage.arabic: 'الطالب',
    AppLanguage.persian: 'سفارشدهنده',
    AppLanguage.english: 'Ordered by',
    AppLanguage.turkish: 'Sipariş veren',
  },
  'ڕەتکەر': {
    AppLanguage.badini: 'ڕەتکەر',
    AppLanguage.arabic: 'الرافض',
    AppLanguage.persian: 'ردکننده',
    AppLanguage.english: 'Rejected by',
    AppLanguage.turkish: 'Reddeden',
  },
  'چاوەڕوانە': {
    AppLanguage.badini: 'چاوەڕوانە',
    AppLanguage.arabic: 'قيد الانتظار',
    AppLanguage.persian: 'در انتظار',
    AppLanguage.english: 'Pending',
    AppLanguage.turkish: 'Beklemede',
  },
  'گەڕێنراوەتەوە': {
    AppLanguage.badini: 'گەڕێنراوەتەوە',
    AppLanguage.arabic: 'مُعاد',
    AppLanguage.persian: 'برگردانده شد',
    AppLanguage.english: 'Returned',
    AppLanguage.turkish: 'İade edildi',
  },
  'ڕەفز': {
    AppLanguage.badini: 'ڕەفز',
    AppLanguage.arabic: 'مرفوض',
    AppLanguage.persian: 'رد شد',
    AppLanguage.english: 'Rejected',
    AppLanguage.turkish: 'Reddedildi',
  },
  'ڕەفز و خەرجی': {
    AppLanguage.badini: 'ڕەفز و خەرجی',
    AppLanguage.arabic: 'المرفوضات والمصروفات',
    AppLanguage.persian: 'رد شده‌ها و هزینه‌ها',
    AppLanguage.english: 'Rejects and expenses',
    AppLanguage.turkish: 'Reddedilenler ve giderler',
  },
  'ژمارەکە بۆ {count} گۆڕدرا': {
    AppLanguage.badini: 'ژمارەکە بۆ {count} گۆڕدرا',
    AppLanguage.arabic: 'تم تغيير الرقم إلى {count}',
    AppLanguage.persian: 'شماره به {count} تغییر کرد',
    AppLanguage.english: 'The number was changed to {count}',
    AppLanguage.turkish: 'Sayı {count} olarak değiştirildi',
  },
  'ژمارەی مێز': {
    AppLanguage.badini: 'ژمارەی مێز',
    AppLanguage.arabic: 'رقم المائدة',
    AppLanguage.persian: 'شماره میز',
    AppLanguage.english: 'Table number',
    AppLanguage.turkish: 'Masa numarası',
  },
  'ژمارەی مێزەکان': {
    AppLanguage.badini: 'ژمارەی مێزەکان',
    AppLanguage.arabic: 'أرقام الموائد',
    AppLanguage.persian: 'شماره میزها',
    AppLanguage.english: 'Table numbers',
    AppLanguage.turkish: 'Masa numaraları',
  },
  'ژمارەی مێزەکانی {name}': {
    AppLanguage.badini: 'ژمارەی مێزەکانی {name}',
    AppLanguage.arabic: 'أرقام موائد {name}',
    AppLanguage.persian: 'شماره میزهای {name}',
    AppLanguage.english: "{name}'s table numbers",
    AppLanguage.turkish: '{name} masalarının numaraları',
  },
  'کاتی داواکردنی حیساب': {
    AppLanguage.badini: 'کاتی داواکردنی حیساب',
    AppLanguage.arabic: 'وقت طلب الحساب',
    AppLanguage.persian: 'زمان درخواست حساب',
    AppLanguage.english: 'Bill request time',
    AppLanguage.turkish: 'Hesap isteme zamanı',
  },
  'کاتی ڕۆیشتن': {
    AppLanguage.badini: 'کاتی ڕۆیشتن',
    AppLanguage.arabic: 'وقت المغادرة',
    AppLanguage.persian: 'زمان خروج',
    AppLanguage.english: 'Departure time',
    AppLanguage.turkish: 'Çıkış zamanı',
  },
  'کرا: خواردنەکە گوێزرایەوە': {
    AppLanguage.badini: 'کرا: خوارنەکە گوێزرایەوە',
    AppLanguage.arabic: 'تم: نقل الطعام',
    AppLanguage.persian: 'انجام شد: غذا منتقل شد',
    AppLanguage.english: 'Done: the item was moved',
    AppLanguage.turkish: 'Tamam: yiyecek taşındı',
  },
  'کوردی': {
    AppLanguage.badini: 'کوردی',
    AppLanguage.arabic: 'الكردية',
    AppLanguage.persian: 'کردی',
    AppLanguage.english: 'Kurdish',
    AppLanguage.turkish: 'Kürtçe',
  },
  'کۆپی': {
    AppLanguage.badini: 'کۆپی',
    AppLanguage.arabic: 'نسخ',
    AppLanguage.persian: 'کپی',
    AppLanguage.english: 'Copy',
    AppLanguage.turkish: 'Kopyala',
  },
  'کۆپی کرا': {
    AppLanguage.badini: 'کۆپی کرا',
    AppLanguage.arabic: 'تم النسخ',
    AppLanguage.persian: 'کپی شد',
    AppLanguage.english: 'Copied',
    AppLanguage.turkish: 'Kopyalandı',
  },
  'کۆی بڕ': {
    AppLanguage.badini: 'کۆی بڕ',
    AppLanguage.arabic: 'المبلغ الإجمالي',
    AppLanguage.persian: 'مبلغ کل',
    AppLanguage.english: 'Total amount',
    AppLanguage.turkish: 'Toplam tutar',
  },
  'کێ خواردنی داوا کردووە': {
    AppLanguage.badini: 'کێ خوارنی داوا کردووە',
    AppLanguage.arabic: 'من طلب الطعام',
    AppLanguage.persian: 'چه کسی غذا را درخواست کرد',
    AppLanguage.english: 'Who requested the items',
    AppLanguage.turkish: 'Yiyeceği kim istedi',
  },
  'گواستنەوە بۆ مێز': {
    AppLanguage.badini: 'گواستنەوە بۆ مێز',
    AppLanguage.arabic: 'نقل إلى مائدة',
    AppLanguage.persian: 'انتقال به میز',
    AppLanguage.english: 'Move to table',
    AppLanguage.turkish: 'Masaya taşı',
  },
  'گواستنەوەی {itemName} بۆ مێز': {
    AppLanguage.badini: 'گواستنەوەی {itemName} بۆ مێز',
    AppLanguage.arabic: 'نقل {itemName} إلى مائدة',
    AppLanguage.persian: 'انتقال {itemName} به میز',
    AppLanguage.english: 'Move {itemName} to table',
    AppLanguage.turkish: '{itemName} masaya taşı',
  },
  'پەککەوتوو': {
    AppLanguage.badini: 'پەککەوتوو',
    AppLanguage.arabic: 'منقطع',
    AppLanguage.persian: 'قطع شده',
    AppLanguage.english: 'Disconnected',
    AppLanguage.turkish: 'Bağlantı kesildi',
  },
  'هەڵە': {
    AppLanguage.badini: 'هەڵە',
    AppLanguage.arabic: 'خطأ',
    AppLanguage.persian: 'خطا',
    AppLanguage.english: 'Error',
    AppLanguage.turkish: 'Hata',
  },
  'چاپ کرا': {
    AppLanguage.badini: 'چاپ کرا',
    AppLanguage.arabic: 'تمت الطباعة',
    AppLanguage.persian: 'چاپ شد',
    AppLanguage.english: 'Printed',
    AppLanguage.turkish: 'Yazdırıldı',
  },
  'نێردرا': {
    AppLanguage.badini: 'نێردرا',
    AppLanguage.arabic: 'أُرسل',
    AppLanguage.persian: 'ارسال شد',
    AppLanguage.english: 'Sent',
    AppLanguage.turkish: 'Gönderildi',
  },
  'بەستراوی': {
    AppLanguage.badini: 'بەستراوی',
    AppLanguage.arabic: 'متصل',
    AppLanguage.persian: 'متصل',
    AppLanguage.english: 'Connected',
    AppLanguage.turkish: 'Bağlı',
  },
  'ناوی کۆمپانیاکەت بنووسە ڕامیار': {
    AppLanguage.badini: 'ناوی کۆمپانیاکەت بنووسە ڕامیار',
    AppLanguage.arabic: 'اكتب اسم شركتك: راميار',
    AppLanguage.persian: 'نام شرکت خود را بنویسید: رامیار',
    AppLanguage.english: 'Write your company name: Ramyar',
    AppLanguage.turkish: 'Şirket adınızı yazın: Ramyar',
  },
  'گەرمی': {
    AppLanguage.badini: 'گەرم',
    AppLanguage.arabic: 'حار',
    AppLanguage.persian: 'گرم',
    AppLanguage.english: 'Hot',
    AppLanguage.turkish: 'Sıcak',
  },
  'ساردی': {
    AppLanguage.badini: 'سارد',
    AppLanguage.arabic: 'بارد',
    AppLanguage.persian: 'سرد',
    AppLanguage.english: 'Cold',
    AppLanguage.turkish: 'Soğuk',
  },
  'شیرینی': {
    AppLanguage.badini: 'شیرینی',
    AppLanguage.arabic: 'حلويات',
    AppLanguage.persian: 'شیرینی',
    AppLanguage.english: 'Dessert',
    AppLanguage.turkish: 'Tatlı',
  },
  'کێک': {
    AppLanguage.badini: 'کێک',
    AppLanguage.arabic: 'كيك',
    AppLanguage.persian: 'کیک',
    AppLanguage.english: 'Cake',
    AppLanguage.turkish: 'Kek',
  },
  // ===== Order delivery (item-level) =====
  'چێشتخانە': {
    AppLanguage.badini: 'چێشتخانە',
    AppLanguage.arabic: 'المطبخ',
    AppLanguage.persian: 'آشپزخانه',
    AppLanguage.english: 'Kitchen',
    AppLanguage.turkish: 'Mutfak',
  },
  'پرێنتی کاشێر': {
    AppLanguage.badini: 'پرێنتی کاشێری',
    AppLanguage.arabic: 'طابعة الكاشير',
    AppLanguage.persian: 'چاپگر صندوق',
    AppLanguage.english: 'Cashier printer',
    AppLanguage.turkish: 'Kasa yazıcısı',
  },
  'ژووری نێرگیلە': {
    AppLanguage.badini: 'ژوورا نێرگیلەیێ',
    AppLanguage.arabic: 'غرفة الأركيلة',
    AppLanguage.persian: 'اتاق قلیان',
    AppLanguage.english: 'Hookah room',
    AppLanguage.turkish: 'Nargile odası',
  },
  'پرێنت نەکراوە': {
    AppLanguage.badini: 'پرێنت نەکریە',
    AppLanguage.arabic: 'لم يُطبع',
    AppLanguage.persian: 'چاپ نشده',
    AppLanguage.english: 'Not printed',
    AppLanguage.turkish: 'Yazdırılmadı',
  },
  'هیچ ئایتیمێک نەدۆزرایەوە': {
    AppLanguage.badini: 'چ ئایتیم نەهاتنە دیتن',
    AppLanguage.arabic: 'لم يتم العثور على أي عنصر',
    AppLanguage.persian: 'هیچ آیتمی یافت نشد',
    AppLanguage.english: 'No items found',
    AppLanguage.turkish: 'Hiç öğe bulunamadı',
  },
  'هەڵە لە دووبارە ناردن': {
    AppLanguage.badini: 'خەلەتی د دووبارە هنارتنێ دا',
    AppLanguage.arabic: 'خطأ في إعادة الإرسال',
    AppLanguage.persian: 'خطا در ارسال مجدد',
    AppLanguage.english: 'Error resending',
    AppLanguage.turkish: 'Yeniden gönderme hatası',
  },
  'هەڵە لە پرێنت': {
    AppLanguage.badini: 'خەلەتی د پرێنتکرنێ دا',
    AppLanguage.arabic: 'خطأ في الطباعة',
    AppLanguage.persian: 'خطا در چاپ',
    AppLanguage.english: 'Error printing',
    AppLanguage.turkish: 'Yazdırma hatası',
  },
};

/// Every translatable UI string, keyed by the Kurdish (Sorani) source text.
///
/// Exposed so tests (and future tooling) can verify that every app language -
/// including Badini - covers every UI string in the system.
Map<String, Map<AppLanguage, String>> get allTranslations => _allTranslations;
