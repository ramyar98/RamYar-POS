import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/main.dart' as app;
import 'package:ramyar_pos/page/login/login_page.dart';

Future<void> pumpUntil(WidgetTester tester, Finder f,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  fail('timeout waiting for $f');
}

Future<void> pumpUntilAny(WidgetTester tester, List<Finder> finders,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finders.any((f) => f.evaluate().isNotEmpty)) return;
  }
  fail('timeout waiting for any marker');
}

Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.text(d), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cashier close shift WITHOUT typing amount (real Windows)',
      (tester) async {
    // SAFETY GATE. This test drives the REAL app against the REAL shop database
    // and really closes the active shift: it taps «داخستن و چوونە دەرەوە» ->
    // «داخستن» and then opens `ramyar_pos.db` directly (below). A plain
    // `flutter test integration_test` sweep would therefore mutate/close a real
    // shift, so it is skipped unless the operator opts in on purpose:
    //
    //   $env:RAMYAR_REAL_DB_TEST='1'
    //   flutter test integration_test/close_shift_test.dart -d windows
    if (Platform.environment['RAMYAR_REAL_DB_TEST'] != '1') {
      markTestSkipped('real-database shift-close test - set RAMYAR_REAL_DB_TEST=1 '
          'to run it (it really closes the active shift)');
      return;
    }
    app.main();
    await tester.pump(const Duration(milliseconds: 3000));

    final startBtn = find.text('دەستپێکردنی شەفت');
    final exitPill = find.text('داخستن و چوونە دەرەوە');
    final welcomeOut = find.text('چوونە دەرەوە');
    final closeShiftHome = find.text('داخستنی شەفت');

    await pumpUntilAny(tester,
        [find.byType(LoginPage), startBtn, exitPill, welcomeOut, closeShiftHome],
        timeout: const Duration(seconds: 40));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .toList();
    debugPrint('LIVE-STEP visible-texts: $texts');

    if (find.byType(LoginPage).evaluate().isNotEmpty) {
      await enterPin(tester, '2233');
      await pumpUntilAny(tester, [startBtn, exitPill, welcomeOut]);
      debugPrint('LIVE-STEP after-login');
    }
    if (exitPill.evaluate().isEmpty && welcomeOut.evaluate().isEmpty) {
      if (startBtn.evaluate().isNotEmpty) {
        await tester.tap(startBtn, warnIfMissed: false);
        await pumpUntil(tester, exitPill);
        debugPrint('LIVE-STEP started-shift, at home');
      }
    }

    await tester.pump(const Duration(milliseconds: 600));

    // میحوەرەکی ئێمە: داخستن بەبێ نوسینی هیچ بڕە پارەیەک
    if (exitPill.evaluate().isNotEmpty) {
      await tester.tap(exitPill, warnIfMissed: false);
    } else {
      final closeShift = find.text('داخستنی شەفت');
      await tester.ensureVisible(closeShift);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(closeShift, warnIfMissed: false);
    }
    await tester.pump(const Duration(milliseconds: 600));
    final closeBtn = find.widgetWithText(FilledButton, 'داخستن');
    debugPrint('LIVE-STEP dialog-open=${find.text('داخستنی شەفت').evaluate().isNotEmpty}');
    debugPrint('LIVE-STEP close-btn-present=${closeBtn.evaluate().isNotEmpty}');
    final err1 = tester.takeException();
    debugPrint('LIVE-STEP exception-before-tap=$err1');
    if (closeBtn.evaluate().isNotEmpty) {
      final r = tester.getRect(closeBtn);
      debugPrint('LIVE-STEP btn-rect=${r.toString()}');
      await tester.tap(closeBtn, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      debugPrint('LIVE-STEP close-btn-still-visible=${closeBtn.evaluate().isNotEmpty}');
    }
    await tester.pump(const Duration(seconds: 2));

    // پشکنینی داتیڕاستەقینە لە داتابەیسەکەدا
    final dir = await getDatabasesPath();
    final db = await openDatabase('$dir${Platform.pathSeparator}ramyar_pos.db');
    final shifts = await db.query('cashier_shifts', orderBy: 'id DESC');
    debugPrint('LIVE-STEP db-shift-rows=${shifts.length}');
    for (final s in shifts) {
      debugPrint('LIVE-STEP db-shift id=${s['id']} ended=${s['endedAt']} collected=${s['totalCollected']}');
    }
    final anyOpen = shifts.any((s) => s['endedAt'] == '');
    final lastEnded = shifts.isNotEmpty && shifts.first['endedAt'] != '' && shifts.first['totalCollected'] == 0;
    await db.close();

    final err2 = tester.takeException();
    debugPrint('LIVE-STEP final-exception=$err2');
    expect(lastEnded, isTrue,
        reason: 'newest shift must be ended with totalCollected = 0 when closing WITHOUT typing');
    expect(anyOpen, isFalse, reason: 'no shift may remain open');
  }, timeout: const Timeout(Duration(minutes: 3)));
}