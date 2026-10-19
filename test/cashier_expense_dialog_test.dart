import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/fmt.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/cashier/cashier_expenses_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_welcome_page.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// Drives the cashier's «خەرجیەکان» ledger through the REAL page.
///
/// Two things are under test here. First, the dialogs own their controllers via
/// a `DialogControllerOwner`, so the post-dialog read of `controller.text` still
/// works (an early dispose used to cover the whole app with a red error screen
/// while the route animated out). Second, the ledger itself: an expense is
/// recorded as money out, and the replay button on a row puts the same amount
/// straight back - the "enter 20,000, return 20,000" path the cashier asked for.
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
    // test runs test files concurrently), and off the other reserved ports
    // (39876 is captain_order_cashier_settle_e2e_test's, 39877 is
    // credit_card_payment_test's, 39878 is discount_amount_mode_test's) so two
    // files never race for the same bind.
    debugSyncServerPort = 39879;
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    debugSyncServerPort = 9876;
    await db.resetForTesting();
  });

  // The laptop that is also the cashier/hub, and the shape the shop floor runs.
  const laptop = Size(1280, 800);
  const landscapeHandheld = Size(896, 414);

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
    bool negate = false,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      final present = finder.evaluate().isNotEmpty;
      if (negate ? !present : present) return;
    }
    fail('Timed out waiting for ${negate ? 'the absence of ' : ''}$finder');
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

  /// Signs in as the cashier, opens a shift and stops on the cashier home.
  /// Returns the row id of the shift that was opened.
  Future<int> openCashierHome(WidgetTester tester, Size size) async {
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

    await enterPin(tester, '22334'); // کاشێر 1
    await pumpUntil(tester, find.byType(CashierWelcomePage));
    await tester.ensureVisible(find.text('دەستپێکردنی شەفت'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('دەستپێکردنی شەفت'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(CashierHomePage));

    final shift = await db.getActiveShift(4);
    expect(shift, isNotNull, reason: 'the shift must be open');
    return shift!.id;
  }

  /// Taps «خەرجیەکان» in the app bar and waits for the ledger page.
  ///
  /// A widget enters the tree the moment a route starts sliding in, and a tap
  /// on a widget that is still moving is silently swallowed - so each step
  /// pumps past the route animation before it taps. (`pumpAndSettle` is avoided:
  /// the cashier screen owns periodic timers, so it would never settle.)
  Future<void> openExpensesPage(WidgetTester tester) async {
    await tester.ensureVisible(find.text('خەرجیەکان'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('خەرجیەکان'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(CashierExpensesPage));
    await tester.pump(const Duration(milliseconds: 600)); // page slide-in
  }

  /// Opens the add-expense or return-expense dialog from the ledger page.
  ///
  /// The returns section is switched to first (the FAB and the dialog follow the
  /// selected section); the FAB is matched by type since the page owns exactly
  /// one.
  Future<void> openLedgerDialog(
    WidgetTester tester, {
    required bool returns,
  }) async {
    if (returns) {
      final tab = find.text('گەڕانەوەی خەرجی');
      await tester.ensureVisible(tab.first);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(tab.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600)); // tab settle
    }
    await tester.tap(find.byType(FloatingActionButton), warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog));
    await tester.pump(const Duration(milliseconds: 500)); // dialog fade-in
  }

  /// A finder for a widget inside the open dialog, so stray matches elsewhere on
  /// the page (a tab label, the FAB) cannot make a tap ambiguous.
  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

  Future<void> waitForTotal(WidgetTester tester, int shiftId, int expected) async {
    for (var i = 0; i < 40; i++) {
      if (await db.getShiftExpensesTotal(shiftId) == expected.toDouble()) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('shift expense total never reached $expected');
  }

  /// Settles the hub before the test body ends.
  ///
  /// The cashier home is the hub, so its `initState` kicks off the real sync
  /// server. Two things must be allowed to happen while the tree is still
  /// ALIVE: (a) that async start - bind plus a 3s local-IP probe - must finish,
  /// or its completion calls `setError` on an already-disposed notifier; (b)
  /// after `disconnectSync()`, the heartbeat/health-check timers must burn out,
  /// or the framework reports "A Timer is still pending even after the widget
  /// tree was disposed". This mirrors `captain_order_cashier_settle_e2e_test`.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    disconnectSync();
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('cashier saves an expense - the controllers survive the dialog',
      (tester) async {
    final shiftId = await openCashierHome(tester, laptop);

    await openExpensesPage(tester);
    await openLedgerDialog(tester, returns: false);
    expect(inDialog(find.text('تۆمارکردنی خەرجی')), findsOneWidget);

    final fields = inDialog(find.byType(TextField));
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, 'کارەبا');
    await tester.enterText(fields.last, '5000');
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(inDialog(find.text('تۆمارکردن')).first,
        warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog), negate: true);
    expect(tester.takeException(), isNull);

    // The dialog read `nameCtrl.text`/`priceCtrl.text` after it closed and then
    // wrote the row. If the owner had disposed the controllers early, that read
    // would have thrown and nothing would have been recorded.
    await waitForTotal(tester, shiftId, parseAmount('5000'));

    await finish(tester);
  });

  testWidgets('cashier returns 20,000 with the replay button', (tester) async {
    final shiftId = await openCashierHome(tester, laptop);

    // 1. Enter a 20,000 set and save it.
    await openExpensesPage(tester);
    await openLedgerDialog(tester, returns: false);
    var fields = inDialog(find.byType(TextField));
    await tester.enterText(fields.first, 'کارەبا');
    await tester.enterText(fields.last, '20000');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(inDialog(find.text('تۆمارکردن')).first,
        warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog), negate: true);
    await waitForTotal(tester, shiftId, 20000);

    // 2. The row now offers the replay button; it opens the return form already
    //    filled with the same name and amount, so the money goes straight back.
    await tester.tap(find.byTooltip('گەڕاندنەوەی ئەم خەرجییە').first);
    await pumpUntil(tester, find.byType(AlertDialog));
    await tester.pump(const Duration(milliseconds: 400));
    fields = inDialog(find.byType(TextField));
    expect(
      tester.widget<TextField>(fields.first).controller!.text,
      'کارەبا',
      reason: 'the return form carries the expense name',
    );
    expect(
      tester.widget<TextField>(fields.last).controller!.text,
      money(20000),
      reason: 'the return form carries the amount, ready to put back',
    );

    // 3. Confirm: the return is written as a negative price, so the shift total
    //    nets back to zero.
    await tester.tap(inDialog(find.text('گەڕاندنەوەی خەرجی')).first,
        warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog), negate: true);
    await waitForTotal(tester, shiftId, 0);

    final rows = await db.getShiftExpenses(shiftId);
    expect(rows.length, 2);
    expect(rows.where((r) => (r['price'] as num) > 0).length, 1);
    expect(rows.where((r) => (r['price'] as num) < 0).length, 1);

    await finish(tester);
  });

  testWidgets('cashier cancels the add and return-expense dialogs cleanly',
      (tester) async {
    final shiftId = await openCashierHome(tester, landscapeHandheld);

    // --- add-expense dialog, cancelled while a field holds focus ---
    await openExpensesPage(tester);
    await openLedgerDialog(tester, returns: false);
    expect(inDialog(find.text('تۆمارکردنی خەرجی')), findsOneWidget);
    await tester.enterText(inDialog(find.byType(TextField)).first, 'کارەبا');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(inDialog(find.text('ڕەتکردنەوە')).first, warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog), negate: true);
    expect(tester.takeException(), isNull);

    // --- return-expense dialog, cancelled ---
    await openLedgerDialog(tester, returns: true);
    expect(inDialog(find.text('گەڕانەوەی خەرجی')), findsOneWidget);
    await tester.enterText(inDialog(find.byType(TextField)).first, 'کارەبا');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(inDialog(find.text('ڕەتکردنەوە')).first, warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog), negate: true);
    expect(tester.takeException(), isNull);

    // Nothing was recorded by either cancelled dialog.
    expect(await db.getShiftExpensesTotal(shiftId), 0);

    await finish(tester);
  });
}
