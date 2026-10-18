import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/digits.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/login/pin_login_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// Returns the first localized (non-Latin) digit found in [s], or null when
/// the string only contains Latin digits and regular text.
String? _firstLocalizedDigit(String s) {
  for (final c in s.codeUnits) {
    final arabicIndic = c >= 0x0660 && c <= 0x0669;
    final persian = c >= 0x06F0 && c <= 0x06F9;
    final fullwidth = c >= 0xFF10 && c <= 0xFF19;
    if (arabicIndic || persian || fullwidth) return String.fromCharCode(c);
  }
  return null;
}

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
    // The menu item (overlay) is the last matching text after the button's.
    await tester.tap(
        find.text(LanguageHelper.getLanguageName(lang)).last,
        warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
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
    expect(tester.takeException(), isNull, reason: 'finish error');
  }

  group('login page digits are Latin in every language', () {
    for (final lang in AppLanguage.values) {
      testWidgets('keypad digits remain 0-9 in ${lang.name}',
          (tester) async {
        await pumpLogin(tester);
        await selectLanguage(tester, lang);
        final label = 'login(${lang.name})';

        // 1) Every Latin digit 0-9 must be visible on the keypad.
        for (final d in '0123456789'.split('')) {
          expect(find.text(d), findsWidgets,
              reason: '$label: keypad is missing Latin digit "$d"');
        }

        // 2) No localized (Arabic-Indic / Persian / fullwidth) digit may exist
        // in ANY text on screen.
        final offenders = <String>[];
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          final data = t.data ?? t.textSpan?.toPlainText() ?? '';
          final bad = _firstLocalizedDigit(data);
          if (bad != null) offenders.add('"$bad" inside "$data"');
        }
        expect(offenders, isEmpty,
            reason: '$label: localized digits found on screen: $offenders');

        // 2b) The keypad must always be a standard (English dialer) layout:
        //    1-2-3 on the top row from the LEFT, and 7-8-9 below them - in
        //    every language (never mirrored by RTL).
        final ones = tester.getRect(find.text('1'));
        final twos = tester.getRect(find.text('2'));
        final threes = tester.getRect(find.text('3'));
        final sevens = tester.getRect(find.text('7'));
        final eights = tester.getRect(find.text('8'));
        final nines = tester.getRect(find.text('9'));
        expect(ones.top.round() == twos.top.round() &&
                twos.top.round() == threes.top.round(),
            isTrue,
            reason: '$label: 1-2-3 are not on one row');
        expect(ones.left < twos.left && twos.left < threes.left, isTrue,
            reason: '$label: top row is not 1-2-3 left to right '
                '(1@${ones.left.round()}, 2@${twos.left.round()}, '
                '3@${threes.left.round()})');
        expect(sevens.left < eights.left && eights.left < nines.left, isTrue,
            reason: '$label: bottom digit row is not 7-8-9 left to right');
        expect(sevens.top > threes.top, isTrue,
            reason: '$label: 7-8-9 should be BELOW 1-2-3');

        // 3) Tapping a key registers the Latin digit into the PIN.
        await tester.tap(find.text('5'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        final state =
            tester.state<PinKeypadState>(find.byType(PinKeypad));
        expect(state.pin, '5',
            reason: '$label: tap on digit 5 did not register Latin "5"');

        await finish(tester);
      });
    }
  });

  group('toLatinDigits', () {
    test('maps Arabic-Indic ٠-٩ to 0-9', () {
      expect(toLatinDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    });
    test('maps Persian ۰-۹ to 0-9', () {
      expect(toLatinDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    });
    test('maps fullwidth ０-９ to 0-9', () {
      expect(toLatinDigits('０１２３４５６７８９'), '0123456789');
    });
    test('passes ASCII digits and text through', () {
      expect(toLatinDigits('PIN 123'), 'PIN 123');
    });
    test('normalizes mixed text', () {
      expect(toLatinDigits('٩-X-۹'), '9-X-9');
      expect(toLatinDigits('١92.١٦٨.1.10'), '192.168.1.10');
    });
  });
}