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

/// The discount box on the cashier's bill tab keeps its percent mode and gains
/// a small "% / د.ع" switch next to the title. Tapping د.ع turns the box into
/// a straight Iraqi-dinar discount: on a 25,000 د.ع bill a typed 5,000 د.ع
/// drops the total to 20,000 د.ع, and the settled order keeps that 5,000 د.ع
/// as its discount.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugSyncServerPort = 39878;
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

  testWidgets('discount box switches from percent to a straight د.ع amount', (
    tester,
  ) async {
    await prepare(tester, landscapeHandheld);

    // CAPTAIN: open table 1 and order five 5,000 د.ع portions of the same
    // dish, so the bill is exactly the 25,000 د.ع from the request.
    await enterPin(tester, '11221'); // وەیتەر 1
    await pumpUntil(tester, find.byType(WaiterHomePage));
    await tester.tap(find.byType(TableCard).first, warnIfMissed: false);
    await tester.pump();
    await pumpUntil(tester, find.text('چەند کەسن؟'));
    await tester.tap(find.text('2'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(TablePage));

    final dish = find.text('بەرگەری گۆشتی').first;
    final dishTile = find
        .ancestor(of: dish, matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(dishTile);
    await tester.pump(const Duration(milliseconds: 150));
    for (var i = 0; i < 5; i++) {
      await tester.tap(dishTile, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
    }

    final tableScroll = find.descendant(
      of: find.byType(TablePage),
      matching: find.byType(CustomScrollView),
    );
    for (var i = 0; i < 60 && find.text('ناردن').evaluate().isEmpty; i++) {
      await tester.drag(
        tableScroll.first,
        const Offset(0, -500),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    final send = find.text('ناردن');
    expect(send, findsOneWidget);
    await tester.ensureVisible(send.first);
    await tester.tap(send.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    checkNoError(tester, 'captain send');

    final total = (await db.getTable(1))!.totalAmount;
    expect(
      total,
      25000,
      reason: 'five 5,000 د.ع portions must total 25,000 د.ع',
    );

    // CASHIER: open a shift, open the same table, find the discount box.
    await backToLogin(tester, 'captain');
    await enterPin(tester, '22334'); // کاشێر 1
    await pumpUntil(tester, find.byType(CashierWelcomePage));
    await tester.ensureVisible(find.text('دەستپێکردنی شەفت'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('دەستپێکردنی شەفت'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(CashierHomePage));

    await tester.tap(
      find.widgetWithText(TableCard, 'مێز 1').first,
      warnIfMissed: false,
    );
    await tester.pump();
    await pumpUntil(tester, find.byType(CashierUnifiedTablePage));
    checkNoError(tester, 'cashier unified table');

    final pageScroll = find.descendant(
      of: find.byType(CashierUnifiedTablePage),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 40 && find.text('5%').evaluate().isEmpty; i++) {
      await tester.drag(
        pageScroll.first,
        const Offset(0, -400),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    checkNoError(tester, 'scroll to discount');

    final box = find
        .ancestor(of: find.byType(TextField), matching: find.byType(Column))
        .first;

    // Percent mode is the default: a percent title and the quick-chips.
    expect(
      find.descendant(of: box, matching: find.text('داشکاندن (%)')),
      findsOneWidget,
      reason: 'the box must start in percent mode',
    );
    expect(
      find.descendant(of: box, matching: find.text('5%')),
      findsOneWidget,
      reason: 'percent quick chips must show by default',
    );

    // The new button in the box header switches the box to Iraqi dinar.
    final dinarChip = find.descendant(of: box, matching: find.text('د.ع'));
    await tester.ensureVisible(dinarChip.first);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(dinarChip.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    checkNoError(tester, 'switch to د.ع mode');

    expect(
      find.descendant(of: box, matching: find.text('داشکاندن (د.ع)')),
      findsOneWidget,
      reason: 'the box title must follow the mode',
    );
    expect(
      find.descendant(of: box, matching: find.text('5%')),
      findsNothing,
      reason: 'percent quick chips make no sense in dinar mode',
    );

    // Type a straight 5,000 د.ع: 25,000 - 5,000 = 20,000 د.ع.
    final discountField = find.byType(TextField).first;
    await tester.enterText(discountField, '5000');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('داشکاندن (20%)'),
      findsOneWidget,
      reason: 'the summary strip must show the derived percent',
    );
    expect(
      find.text('-د.ع 5,000'),
      findsWidgets,
      reason: 'the exact 5,000 د.ع taken off must appear on the bill',
    );
    checkNoError(tester, 'discount math');

    // Settle by cash: the calculator must open on the 20,000 د.ع figure.
    for (var i = 0; i < 40 && find.text('واسڵ کردن').evaluate().isEmpty; i++) {
      await tester.drag(
        pageScroll.first,
        const Offset(0, -400),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    final openSettle = find.text('واسڵ کردن');
    await tester.ensureVisible(openSettle.first);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(openSettle.first, warnIfMissed: false);
    await pumpUntil(tester, find.text('واسڵ کردنی پارە'));
    checkNoError(tester, 'cash calculator');

    expect(
      find.text('20,000 IQD'),
      findsOneWidget,
      reason: 'the cash calculator must open on the discounted 20,000 د.ع',
    );
    final dialog = find.byType(Dialog);
    final cashField = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(cashField.last, '20000');
    await tester.pump(const Duration(milliseconds: 300));
    final confirm = find.descendant(
      of: dialog,
      matching: find.text('واسڵ کردن'),
    );
    expect(
      confirm,
      findsOneWidget,
      reason: 'the cash dialog confirm must enable once the bill is covered',
    );
    await tester.ensureVisible(confirm.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(confirm.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 900));
    checkNoError(tester, 'cash settle');

    // The till: settled at 20,000 with the fixed 5,000 د.ع carried over.
    final settled = await db.getAllSettledOrders();
    final mine = settled.where((o) => o.tableId == 1).toList();
    expect(
      mine,
      hasLength(1),
      reason: 'the settlement must be recorded exactly once',
    );
    expect(
      mine.single.totalAmount,
      20000,
      reason: 'the settled total must be the bill after the dinar discount',
    );
    expect(
      mine.single.discountAmount,
      5000,
      reason: 'the fixed dinar discount must be carried into the settled order',
    );
    final afterSettle = await db.getTable(1);
    expect(
      afterSettle!.status,
      TableStatus.empty,
      reason: 'settling the bill must free the table',
    );

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
