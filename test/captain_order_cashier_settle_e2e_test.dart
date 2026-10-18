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

/// The owner's own words, driven through the REAL widgets on one machine:
/// "a captain takes an order on his phone, and the cashier makes/settles the
/// order and prints on the laptop".
///
/// Nothing here is stubbed at the UI layer: the captain logs in through the
/// 5-digit keypad, taps a table, taps a real menu dish, presses the real
/// `ناردن` send button, and the cashier then logs in, opens a shift, opens the
/// same table and settles the bill through the real cash calculator. The
/// database assertions at the end are read back from SQLite, so a green run
/// means the order really crossed from the captain's screen into the till and
/// the bill really came out of it.
///
/// The SAME journey is walked at all three responsive breakpoints the app
/// ships against - a landscape handheld (which the app buckets as "tablet"),
/// a small landscape phone, and the laptop hub ("desktop") - because the floor,
/// the order cart and the bill are laid out differently in each and a
/// fix in one must not quietly break another.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The cashier screen starts a REAL sync server as a side effect. Keep it off
    // 9876 so this file never fights the hub tests running beside it (flutter
    // test runs test files concurrently).
    debugSyncServerPort = 39876;
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    debugSyncServerPort = 9876;
    await db.resetForTesting();
  });

  // A landscape handheld (1080x2400 @ ~2.7 dpr) is what the shop actually
  // runs; the app buckets its ~896 logical width as "tablet".
  const landscapeHandheld = Size(896, 414);
  // The narrow branch, for a small landscape phone.
  const smallLandscapePhone = Size(568, 320);
  // The laptop that is also the cashier/hub.
  const laptop = Size(1280, 800);

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
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'LoginPage not shown at $size');
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

  /// Drops the current role's routes back to the login page so the next role
  /// can sign in with its own PIN.
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

  Future<void> runOrderThenSettle(WidgetTester tester, Size size) async {
    await prepare(tester, size);

    // ============================================================
    // CAPTAIN: sign in, open table 1, order a real menu dish, send.
    // ============================================================
    await enterPin(tester, '11221'); // وەیتەر 1
    await pumpUntil(tester, find.byType(WaiterHomePage));
    checkNoError(tester, 'captain home');

    // Table 1 starts empty, so the captain is first asked how many guests.
    await tester.tap(find.byType(TableCard).first, warnIfMissed: false);
    await tester.pump();
    await pumpUntil(tester, find.text('چەند کەسن؟'));
    await tester.tap(find.text('2'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(TablePage));
    checkNoError(tester, 'captain table');

    // Add a real seeded dish (بەرگەری گۆشتی, 5000 IQD) and send it. Tap the
    // whole tile, the way a captain does: on a very short landscape screen the
    // tile is taller than the viewport, so the dish label near its bottom can
    // sit below the fold even though the tile itself is visible.
    final dish = find.text('بەرگەری گۆشتی').first;
    final dishTile =
        find.ancestor(of: dish, matching: find.byType(InkWell)).first;
    await tester.ensureVisible(dishTile);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(dishTile, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    // On a phone the cart sits BELOW the whole menu, so the send button is not
    // built until the captain scrolls down to it - exactly what a real captain
    // does after choosing a dish. On the wider layouts the cart is already
    // visible and this loop exits on its first check.
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
    expect(send, findsOneWidget,
        reason: 'the captain send button must be present once a dish is chosen');
    await tester.ensureVisible(send.first);
    await tester.tap(send.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    checkNoError(tester, 'captain send');

    // The order must be in SQLite, on table 1, occupied, with a live total.
    final captainItems = await db.getOrderItems(1);
    expect(captainItems, hasLength(1),
        reason: 'the captain order must be persisted exactly once');
    expect(captainItems.single.name, 'بەرگەری گۆشتی');
    final afterOrder = await db.getTable(1);
    expect(afterOrder!.status, isNot(TableStatus.empty),
        reason: 'sending an order must occupy the table');
    expect(afterOrder.totalAmount, 5000,
        reason: 'the total must equal the ordered dish');
    final total = afterOrder.totalAmount;

    // ============================================================
    // CASHIER: sign in, open a shift, open the same table, settle it.
    // ============================================================
    await backToLogin(tester, 'captain');
    await enterPin(tester, '22334'); // کاشێر 1
    await pumpUntil(tester, find.byType(CashierWelcomePage));
    checkNoError(tester, 'cashier welcome');

    await tester.ensureVisible(find.text('دەستپێکردنی شەفت'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('دەستپێکردنی شەفت'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(CashierHomePage));
    checkNoError(tester, 'cashier home');

    // Open the occupied table from the floor grid by its own label, so the
    // settled bill cannot accidentally be read off a different table.
    await tester.tap(find.widgetWithText(TableCard, 'مێز 1').first,
        warnIfMissed: false);
    await tester.pump();
    await pumpUntil(tester, find.byType(CashierUnifiedTablePage));
    checkNoError(tester, 'cashier unified table');

    // Take a 10% discount so the printed bill and the settled total agree.
    final discountChip = find.text('10%');
    if (discountChip.evaluate().isNotEmpty) {
      await tester.ensureVisible(discountChip.first);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(discountChip.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }

    // The bill tab's cash settle button opens the cash calculator. On the
    // narrow phone layout it can sit below the fold.
    final pageScroll = find.descendant(
        of: find.byType(CashierUnifiedTablePage),
        matching: find.byType(Scrollable));
    for (var i = 0;
        i < 40 && find.text('واسڵ کردن').evaluate().isEmpty;
        i++) {
      await tester.drag(pageScroll.first, const Offset(0, -400),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
    }
    final openSettle = find.text('واسڵ کردن');
    await tester.ensureVisible(openSettle.first);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(openSettle.first, warnIfMissed: false);
    await pumpUntil(tester, find.text('واسڵ کردنی پارە'));
    checkNoError(tester, 'cash calculator');

    // Hand over enough cash for the discounted bill.
    final expectedPaid = (total * 0.9).roundToDouble();
    final dialog = find.byType(Dialog);
    final cashField =
        find.descendant(of: dialog, matching: find.byType(TextField));
    await tester.enterText(cashField.last, expectedPaid.toInt().toString());
    await tester.pump(const Duration(milliseconds: 300));
    final confirm = find.descendant(
        of: dialog, matching: find.text('واسڵ کردن'));
    expect(confirm, findsOneWidget,
        reason: 'the cash dialog confirm must enable once the bill is covered');
    // In landscape the dialog is a scroll view and the confirm button can sit
    // just below the fold on a short screen - scroll it in before tapping.
    await tester.ensureVisible(confirm.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(confirm.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 900));
    checkNoError(tester, 'cash settle');

    // ============================================================
    // The till: table freed, bill recorded, shift total in step.
    // ============================================================
    final settled = await db.getAllSettledOrders();
    final mine = settled.where((o) => o.tableId == 1).toList();
    expect(mine, hasLength(1),
        reason: 'the settled bill must be recorded exactly once');
    expect(mine.single.totalAmount, expectedPaid,
        reason: 'the settled total must be the discounted bill');
    expect(mine.single.discountAmount, greaterThan(0),
        reason: 'the 10% discount must be carried into the settled order');

    final afterSettle = await db.getTable(1);
    expect(afterSettle!.status, TableStatus.empty,
        reason: 'settling the bill must free the table');
    expect(afterSettle.totalAmount, 0,
        reason: 'a freed table must carry no live total');
    expect(await db.getOrderItems(1), isEmpty,
        reason: 'the live order must be moved into the settled bill');

    // An open shift carries no frozen `totalCollected` (that is stamped only at
    // close); the live figure the till shows is the sum of the shift's settled
    // orders, and the bill must be linked to that very shift.
    final shift = await db.getActiveShift(4); // کاشێر 1
    expect(shift, isNotNull, reason: 'the cashier shift must still be open');
    expect(mine.single.shiftId, shift!.id,
        reason: 'the settled bill must be attached to the open shift');
    expect(
        await db.getSettledOrdersTotalByShiftId(shift.id), expectedPaid,
        reason: 'the shift must collect exactly the settled bill');
    expect(
        await db.getSettledCashLikeTotalByShiftId(shift.id), expectedPaid,
        reason: 'a cash settlement must count as cash in the shift');

    // The cashier's till is the hub, so its home screen started the real sync
    // server. Tear it down exactly as `six_language_sweep_test` does, otherwise
    // its heartbeat timers outlive the widget tree.
    await backToLogin(tester, 'cashier');
    disconnectSync();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(seconds: 11));
    checkNoError(tester, 'finish');
  }

  testWidgets('captain orders and cashier settles on a landscape handheld',
      (tester) => runOrderThenSettle(tester, landscapeHandheld));

  testWidgets('captain orders and cashier settles on a small landscape phone',
      (tester) => runOrderThenSettle(tester, smallLandscapePhone));

  testWidgets('captain orders and cashier settles on the laptop hub',
      (tester) => runOrderThenSettle(tester, laptop));
}
