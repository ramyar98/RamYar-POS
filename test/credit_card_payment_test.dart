import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_unified_table_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_welcome_page.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/waiter/table_page.dart';
import 'package:ramyar_pos/page/waiter/waiter_home_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

/// The card payment dialog the owner asked for:
///
///  * clicking کارت on the cashier's bill tab opens the جۆری کارت picker,
///  * next to the title there is a چاپکردنی وەسڵ (print receipt) toggle — on
///    at settlement or off, the cashier's choice,
///  * the picker lists exactly: FIB, FastPay, Super QI, ZinCash, NassPay,
///    Switch,
///  * settling through FastPay records `fastpay` as the payment method and
///    frees the table.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugSyncServerPort = 39877;
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    debugSyncServerPort = 9876;
    await db.resetForTesting();
  });

  const landscapeHandheld = Size(896, 414);

  Future<void> prepare(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
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

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.ensureVisible(find.text(digit));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text(digit), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  void checkNoError(WidgetTester tester, String what) {
    final err = tester.takeException();
    expect(err, isNull, reason: '$what threw: $err');
  }

  Future<void> backToLogin(WidgetTester tester, String what) async {
    final ctx = tester.element(find.byType(Navigator).first);
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 600));
    checkNoError(tester, '$what back-to-login');
  }

  testWidgets('cashier settles table 1 with FastPay via the card picker',
      (tester) async {
    await prepare(tester, landscapeHandheld);

    // CAPTAIN: open table 1 and order one real seeded dish.
    await enterPin(tester, '11221'); // وەیتەر 1
    await pumpUntil(tester, find.byType(WaiterHomePage));
    await tester.tap(find.byType(TableCard).first, warnIfMissed: false);
    await tester.pump();
    await pumpUntil(tester, find.text('چەند کەسن؟'));
    await tester.tap(find.text('2'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(TablePage));

    final dish = find.text('بەرگەری گۆشتی').first;
    final dishTile =
        find.ancestor(of: dish, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(dishTile);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(dishTile, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    final tableScroll = find.descendant(
        of: find.byType(TablePage), matching: find.byType(CustomScrollView));
    for (var i = 0;
        i < 60 && find.text('ناردن').evaluate().isEmpty;
        i++) {
      await tester.drag(tableScroll.first, const Offset(0, -500),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
    }
    final send = find.text('ناردن');
    expect(send, findsOneWidget);
    await tester.ensureVisible(send.first);
    await tester.tap(send.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    checkNoError(tester, 'captain send');

    final captainItems = await db.getOrderItems(1);
    expect(captainItems, hasLength(1));
    final afterOrder = await db.getTable(1);
    expect(afterOrder!.status, isNot(TableStatus.empty));
    final total = afterOrder.totalAmount;

    // CASHIER: open a shift, open the same table, settle by card.
    await backToLogin(tester, 'captain');
    await enterPin(tester, '22334'); // کاشێر 1
    await pumpUntil(tester, find.byType(CashierWelcomePage));

    await tester.ensureVisible(find.text('دەستپێکردنی شەفت'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('دەستپێکردنی شەفت'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(CashierHomePage));

    await tester.tap(find.widgetWithText(TableCard, 'مێز 1').first,
        warnIfMissed: false);
    await tester.pump();
    await pumpUntil(tester, find.byType(CashierUnifiedTablePage));
    checkNoError(tester, 'cashier unified table');

    // The payment row can sit below the fold on a short landscape screen.
    final pageScroll = find.descendant(
        of: find.byType(CashierUnifiedTablePage),
        matching: find.byType(Scrollable));
    for (var i = 0;
        i < 40 && find.text('کارت').evaluate().isEmpty;
        i++) {
      await tester.drag(pageScroll.first, const Offset(0, -400),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
    }
    final cardButton = find.text('کارت');
    expect(cardButton, findsOneWidget,
        reason: 'the card settle button must be on the bill tab');
    await tester.ensureVisible(cardButton.first);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(cardButton.first, warnIfMissed: false);
    await pumpUntil(tester, find.text('جۆری کارت'));
    checkNoError(tester, 'card dialog');

    // Every brand the owner listed must be offered, in that order.
    final dialog = find.byType(AlertDialog);
    for (final brand in [
      'FIB',
      'FastPay',
      'Super QI',
      'ZinCash',
      'NassPay',
      'Switch',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(brand)),
        findsOneWidget,
        reason: 'the picker must offer $brand',
      );
    }

    // The print-receipt toggle sits next to the جۆری کارت title and defaults
    // to ON; the cashier can switch it off for a paperless settlement.
    final receiptToggle =
        find.descendant(of: dialog, matching: find.text('چاپکردنی وەسڵ'));
    expect(receiptToggle, findsOneWidget,
        reason: 'the print-receipt toggle must sit in the card picker');
    final toggleSwitch =
        find.descendant(of: dialog, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggleSwitch).value, isTrue,
        reason: 'printing the receipt must default to ON');
    await tester.tap(receiptToggle.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Switch>(toggleSwitch).value, isFalse,
        reason: 'tapping the toggle must switch receipt printing off');

    // Pick FastPay and confirm.
    await tester.tap(find.text('FastPay'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await pumpUntil(tester, find.text('واسڵکردن'));
    expect(
      find.text('دڵنیایت دەتەوێت مێزی 1 بە FastPay واسڵ بکەیت؟'),
      findsOneWidget,
      reason: 'the confirm message must name the picked brand',
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'واسڵکردن'),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 900));
    checkNoError(tester, 'card settle');

    // The till: one settled bill, paid by fastpay, table freed.
    final settled = await db.getAllSettledOrders();
    final mine = settled.where((o) => o.tableId == 1).toList();
    expect(mine, hasLength(1),
        reason: 'the card settlement must be recorded exactly once');
    expect(mine.single.paymentMethod, 'fastpay',
        reason: 'FastPay must be stored as its payment method');
    expect(mine.single.totalAmount, total,
        reason: 'the settled total must be the bill');
    final afterSettle = await db.getTable(1);
    expect(afterSettle!.status, TableStatus.empty,
        reason: 'settling the bill must free the table');

    // Tear the real sync server down before its heartbeat outlives the tree.
    await backToLogin(tester, 'cashier');
    disconnectSync();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(seconds: 11));
    checkNoError(tester, 'finish');
  });
}