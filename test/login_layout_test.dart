import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/login/pin_login_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// Real-device sizes (not just the responsive grid) to guarantee the shared
/// cashier/admin/captain PIN login looks right and never overlaps on any of
/// them - tiny phones, big phones, iPads and Windows.
const _sizes = <String, Size>{
  'fold-280x653': Size(280, 653),
  'iphone-se-320x568': Size(320, 568),
  'small-android-360x640': Size(360, 640),
  'iphone-8-375x667': Size(375, 667),
  'iphone-13-390x844': Size(390, 844),
  'iphone-max-414x896': Size(414, 896),
  'big-phone-430x932': Size(430, 932),
  'landscape-568x320': Size(568, 320),
  'landscape-667x375': Size(667, 375),
  'landscape-844x390': Size(844, 390),
  'ipad-768x1024': Size(768, 1024),
  'ipad-land-1024x768': Size(1024, 768),
  'ipad-pro-1180x820': Size(1180, 820),
  'laptop-1280x800': Size(1280, 800),
  'desktop-1920x1080': Size(1920, 1080),
};

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

  Future<void> pumpLogin(WidgetTester tester, Size size,
      {double bottomInset = 0, double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (bottomInset > 0) {
      tester.view.viewInsets = FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.resetViewInsets);
    }
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'login not shown at $size');
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

  ({double gap, double cellW, double cellH, Size keypad}) layoutMetrics(
      WidgetTester tester) {
    final keypadRect = tester.getRect(find.byType(PinKeypad));
    final bangRect = tester.getRect(find.text('!'));
    final dropdownRect =
        tester.getRect(find.byType(DropdownButton<AppLanguage>).first);
    // RTL row: language selector on the right, "!" button to its left.
    final gap = dropdownRect.left - bangRect.right;
    final cellW = (keypadRect.width - 2 * 10) / 3;
    return (gap: gap, cellW: cellW, cellH: cellW / 1.5, keypad: keypadRect.size);
  }

  for (final entry in _sizes.entries) {
    final size = entry.value;
    final label = entry.key;

    testWidgets('login layout at $label', (tester) async {
      await pumpLogin(tester, size);
      final m = layoutMetrics(tester);
      expect(tester.takeException(), isNull, reason: '$label error');
      expect(m.gap >= 8, isTrue,
          reason: '$label: language selector overlaps ! button (gap ${m.gap}px)');
      expect(m.keypad.width <= size.width - 4, isTrue,
          reason: '$label: keypad wider than screen (${m.keypad.width}px)');
      expect(m.cellH >= 36, isTrue,
          reason: '$label: keys too short (${m.cellH.toStringAsFixed(1)}px)');
      expect(m.cellW >= 40, isTrue,
          reason: '$label: keys too narrow (${m.cellW.toStringAsFixed(1)}px)');
      expect(m.cellW <= 260, isTrue,
          reason: '$label: keys absurdly wide (${m.cellW.toStringAsFixed(1)}px)');
      debugPrint('LAYOUT $label keypad=${m.keypad.width.toInt()}x'
          '${m.keypad.height.toInt()} cell=${m.cellW.toStringAsFixed(1)}x'
          '${m.cellH.toStringAsFixed(1)} gap=${m.gap.toStringAsFixed(1)}');
      await finish(tester);
    });

    testWidgets('login layout keyboard at $label', (tester) async {
      await pumpLogin(tester, size, bottomInset: 300);
      final visibleH = (size.height - 300).clamp(0.0, double.infinity);
      // Scroll the keypad into the visible area, like a user would.
      await tester.ensureVisible(find.byType(PinKeypad));
      await tester.pump(const Duration(milliseconds: 200));
      final keypadRect = tester.getRect(find.byType(PinKeypad));
      expect(tester.takeException(), isNull, reason: '$label kb error');
      // Keypad must intersect the remaining visible area (reachable).
      expect(keypadRect.top <= visibleH && keypadRect.bottom >= 0, isTrue,
          reason: '$label kb: keypad not reachable (visible $visibleH, '
              'rect ${keypadRect.top.toInt()}-${keypadRect.bottom.toInt()})');
      if (visibleH >= 160) {
        await tester.ensureVisible(find.text('5'));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(find.text('5'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        final state = tester
            .state<PinKeypadState>(find.byType(PinKeypad));
        expect(state.pin, '5',
            reason: '$label kb: digit tap did not register');
      }
      await finish(tester);
    });

    if (size.width < 600) {
      testWidgets('login layout textScale1.3 at $label', (tester) async {
        await pumpLogin(tester, size, textScale: 1.3);
        final m = layoutMetrics(tester);
        expect(tester.takeException(), isNull, reason: '$label s1.3 error');
        expect(m.gap >= 4, isTrue,
            reason: '$label s1.3: overlap (gap ${m.gap.toStringAsFixed(1)}px)');
        expect(m.keypad.width <= size.width - 4, isTrue,
            reason: '$label s1.3: keypad wider than screen');
        expect(m.cellH >= 36, isTrue,
            reason: '$label s1.3: keys too short');
        await finish(tester);
      });
    }
  }
}