import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/services/app_localizations.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/language_flag.dart';

/// Six-language gate:
/// 1. Every UI string in the system has a non-empty value in all 6 languages
///    (Kurdish Sorani, Kurdish Badini, Arabic, Persian, English, Turkish).
/// 2. Every language keeps the {placeholder} tokens of its source string.
/// 3. The language definitions (names + RTL/LTR) are correct.
/// 4. The login language selector shows a real flag + correct text direction
///    for every language.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  group('all 6 languages cover every UI string', () {
    test('every key has a non-empty value in all 6 languages', () {
      expect(allTranslations.length, greaterThanOrEqualTo(300),
          reason: 'translation map looks too small (${allTranslations.length})');
      for (final entry in allTranslations.entries) {
        // Kurdish (Sorani) IS the map key itself - no map value needed.
        expect(entry.key.trim(), isNotEmpty,
            reason: 'an empty Kurdish source key exists');
        for (final lang in AppLanguage.values) {
          if (lang == AppLanguage.kurdish) continue;
          final value = entry.value[lang];
          expect(value, isNotNull,
              reason: '"${entry.key}" has no ${lang.name} translation');
          expect(value!.trim(), isNotEmpty,
              reason: '"${entry.key}" has an empty ${lang.name} translation');
        }
      }
    });

    test('placeholders {...} are preserved in every language', () {
      for (final entry in allTranslations.entries) {
        final tokens = RegExp(r'\{[^}]+\}')
            .allMatches(entry.key)
            .map((m) => m.group(0)!)
            .toSet();
        if (tokens.isEmpty) continue;
        for (final lang in AppLanguage.values) {
          final value =
              lang == AppLanguage.kurdish ? entry.key : entry.value[lang]!;
          final valueTokens = RegExp(r'\{[^}]+\}')
              .allMatches(value)
              .map((m) => m.group(0)!)
              .toSet();
          expect(valueTokens, containsAll(tokens),
              reason: '"${entry.key}" / ${lang.name} lost placeholder tokens');
        }
      }
    });
  });

  group('language definitions', () {
    test('names for all 6 languages', () {
      expect(LanguageHelper.getLanguageName(AppLanguage.kurdish), 'کوردی (سۆرانی)');
      expect(LanguageHelper.getLanguageName(AppLanguage.badini), 'کوردی (بادینی)');
      expect(LanguageHelper.getLanguageName(AppLanguage.arabic), 'العربية');
      expect(LanguageHelper.getLanguageName(AppLanguage.persian), 'فارسی');
      expect(LanguageHelper.getLanguageName(AppLanguage.english), 'English');
      expect(LanguageHelper.getLanguageName(AppLanguage.turkish), 'Türkçe');
    });

    test('directions: kurdish/badini/arabic/persian are RTL, english/turkish LTR', () {
      for (final lang in [
        AppLanguage.kurdish,
        AppLanguage.badini,
        AppLanguage.arabic,
        AppLanguage.persian,
      ]) {
        expect(LanguageHelper.isRtl(lang), isTrue,
            reason: '${lang.name} should be RTL');
      }
      for (final lang in [AppLanguage.english, AppLanguage.turkish]) {
        expect(LanguageHelper.isRtl(lang), isFalse,
            reason: '${lang.name} should be LTR');
      }
    });
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginPage), findsOneWidget);
  }

  Future<void> selectLanguage(WidgetTester tester, AppLanguage lang) async {
    await tester.tap(find.byType(DropdownButton<AppLanguage>),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(
        find.text(LanguageHelper.getLanguageName(lang)).last,
        warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester, String what) async {
    final ctx = tester.element(find.byType(Navigator).first);
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
    disconnectSync();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull, reason: '$what finish error');
  }

  group('login language selector shows a flag + correct direction', () {
    for (final lang in AppLanguage.values) {
      testWidgets('${lang.name}: flag row, direction, all 6 entries',
          (tester) async {
        await pumpLogin(tester);
        await selectLanguage(tester, lang);
        final label = 'login(${lang.name})';

        // The currently selected language is shown next to its flag.
        expect(
            find.byWidgetPredicate(
                (w) => w is FlagIcon && w.language == lang),
            findsWidgets,
            reason: '$label: no ${lang.name} flag on screen');

        // Text direction follows the language (Badini must be RTL).
        final ctx = tester
            .element(find.text(LanguageHelper.getLanguageName(lang)).first);
        expect(Directionality.of(ctx), LanguageHelper.getTextDirection(lang),
            reason: '$label: wrong text direction');

        // The dropdown lists all 6 languages, each with a flag.
        await tester.tap(find.byType(DropdownButton<AppLanguage>),
            warnIfMissed: false);
        await tester.pumpAndSettle();
        for (final l in AppLanguage.values) {
          expect(find.text(LanguageHelper.getLanguageName(l)), findsWidgets,
              reason: '$label: dropdown missing ${l.name}');
        }
        final flagsInMenu =
            tester.widgetList<FlagIcon>(find.byType(FlagIcon)).map((f) => f.language).toSet();
        expect(flagsInMenu.length, 6,
            reason: '$label: dropdown should show 6 flag icons, got '
                '${flagsInMenu.map((f) => f.name).join(',')}');
        await finish(tester, label);
      });
    }
  });
}