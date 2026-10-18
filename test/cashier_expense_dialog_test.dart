import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/fmt.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_welcome_page.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// Drives the cashier's «خەرجیەکان» flow through the REAL page. This is the
/// code path that used to leave the whole app on a red error screen: the dialog
/// disposed its `TextEditingController`s in the caller the moment `showDialog`
/// returned, while the route was still animating out with the soft keyboard
/// closing, and the framework tripped `assert(_dependents.isEmpty)`.
///
/// The controllers are now owned by a `DialogControllerOwner` that wraps the
/// dialog, so they live exactly as long as the route does. The save test proves
/// the post-dialog read of `controller.text` still works (an early dispose
/// would have thrown there instead of recording the expense); the cancel test
/// opens and dismisses both dialogs and asserts the tree stays healthy.
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

  /// Opens the cashier's expense sheet from the app bar and picks [option].
  ///
  /// A widget enters the tree the moment a route starts sliding in, and a tap
  /// on a widget that is still moving is silently swallowed - so each step
  /// pumps past the route animation before it taps. (`pumpAndSettle` is avoided:
  /// the cashier screen owns periodic timers, so it would never settle.)
  Future<void> openExpenseDialog(WidgetTester tester, String option) async {
    await tester.ensureVisible(find.text('خەرجیەکان'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('خەرجیەکان'), warnIfMissed: false);
    await pumpUntil(tester, find.text(option));
    await tester.pump(const Duration(milliseconds: 500)); // sheet slide-in
    await tester.tap(find.text(option), warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog));
    await tester.pump(const Duration(milliseconds: 500)); // dialog fade-in
  }

  /// A finder for a widget inside the open dialog, so stray matches elsewhere on
  /// the page cannot make a tap ambiguous.
  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(AlertDialog), matching: finder);

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

    await openExpenseDialog(tester, 'خەرجی');
    expect(find.text('تۆمارکردنی خەرجی'), findsOneWidget);

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
    final expected = parseAmount('5000').toDouble();
    var total = await db.getShiftExpensesTotal(shiftId);
    for (var i = 0; i < 30 && total != expected; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      total = await db.getShiftExpensesTotal(shiftId);
    }
    expect(total, expected);

    await finish(tester);
  });

  testWidgets('cashier cancels the add and return-expense dialogs cleanly',
      (tester) async {
    final shiftId = await openCashierHome(tester, landscapeHandheld);

    // --- add-expense dialog, cancelled while a field holds focus ---
    await openExpenseDialog(tester, 'خەرجی');
    expect(find.text('تۆمارکردنی خەرجی'), findsOneWidget);
    await tester.enterText(inDialog(find.byType(TextField)).first, 'کارەبا');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(inDialog(find.text('ڕەتکردنەوە')).first, warnIfMissed: false);
    await pumpUntil(tester, find.byType(AlertDialog), negate: true);
    expect(tester.takeException(), isNull);

    // --- return-expense dialog, cancelled ---
    await openExpenseDialog(tester, 'گەڕانەوەی خەرجی');
    expect(find.text('گەڕانەوەی خەرجی'), findsOneWidget);
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
