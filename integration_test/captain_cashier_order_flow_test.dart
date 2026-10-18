import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

/// The same end-to-end story as
/// `test/captain_order_cashier_settle_e2e_test.dart`, but running ON THE REAL
/// DEVICE (`flutter test integration_test/... -d <device>`) using the device's
/// own sqflite plugin and its real screen geometry.
///
/// On the laptop (`-d windows`) it exercises the desktop layout; on the phone
/// (`-d <android serial>`) it exercises the landscape/tablet layout the shop
/// actually runs. The database is an isolated in-memory one, so a real user's
/// data is never touched while still driving the shipping widgets and the
/// shipping sync/print code paths.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    // NOTE: staff are seeded inside the test, not here. On a real device the
    // app's own SharedPreferences may still hold a session, and `tryAutoLogin`
    // looks that session up in THIS (empty) in-memory database - finding
    // nothing, it leaves the operator at the PIN pad instead of auto-signing in
    // as a user id that happens to match. The user's real prefs are untouched.
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 40),
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

  void checkNoError(WidgetTester tester, String what) {
    final err = tester.takeException();
    // `FlutterError.toString()` is just the headline ("A RenderFlex overflowed
    // by 31 pixels"). The offending widget, its parent chain and the exact
    // constraints only live in the diagnostics dump, which is the difference
    // between a five-minute fix and a guessing game.
    final detail = err is FlutterError
        ? '\n${err.diagnostics.map((d) => d.toStringDeep()).join('\n')}'
        : '';
    expect(err, isNull, reason: '$what threw: $err$detail');
  }

  /// Scrolls [finder] into view and taps it, re-resolving it between steps.
///
/// The captain menu and the cashier bill tab are lazy lists: while they scroll,
/// the row being aimed at can be disposed and rebuilt, so a finder captured
/// once goes stale and `tap` then throws "No element". Real time on a phone
/// makes that window easy to hit. Re-checking after every step and retrying
/// turns a flaky device test into a deterministic one.
  Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 25; i++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.ensureVisible(finder.first);
        await tester.pump(const Duration(milliseconds: 120));
        if (finder.evaluate().isNotEmpty) {
          await tester.tap(finder.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 120));
          return;
        }
      }
      await tester.pump(const Duration(milliseconds: 120));
    }
    fail('could not bring $finder on screen to tap it');
  }

  Future<void> backToLogin(WidgetTester tester, String what) async {
    final ctx = tester.element(find.byType(Navigator).first);
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 600));
    checkNoError(tester, '$what back-to-login');
  }

  testWidgets('captain orders on the device and the cashier settles it',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const RamyarPosApp(),
      ),
    );
    await pumpUntil(tester, find.byType(LoginPage));

    // Now that the app is sitting at the PIN pad (no auto-login), create the
    // default staff accounts in the isolated database.
    await db.seedDefaultStaff();

    // ---- CAPTAIN ----
    await enterPin(tester, '11221');
    await pumpUntil(tester, find.byType(WaiterHomePage));
    checkNoError(tester, 'captain home');

    // The table grid arrives a frame or two after the page itself (the list is
    // loaded asynchronously), so wait for a card rather than tapping into an
    // empty grid - on the phone that raced and blew up on `No element`.
    await pumpUntil(tester, find.byType(TableCard).first);
    await tester.tap(find.byType(TableCard).first, warnIfMissed: false);
    await tester.pump();
    await pumpUntil(tester, find.text('چەند کەسن؟'));
    await tester.tap(find.text('2'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(TablePage));
    checkNoError(tester, 'captain table');

    // The menu grid is LAZY. On a short landscape phone (832x411) only the
    // first few dish rows are ever built, so the seeded dish this test orders
    // is simply not in the tree - `find.text(...)` matches nothing at all.
    // Scrolling the grid is what makes the tile exist, so scroll until it
    // shows before looking for it. Without this the test only passes on
    // viewports tall/wide enough for that dish to land in the first screenful.
    const dishName = 'بەرگەری گۆشتی';
    final menuGrid = find.descendant(
        of: find.byType(TablePage), matching: find.byType(GridView));
    // The page body swaps in a progress indicator while the order loads, so
    // `TablePage` being on screen does NOT mean the menu is built yet. On the
    // phone that raced and the scroll below had nothing to drag. Wait for the
    // grid itself (the narrow layout scrolls the menu as one sliver list
    // instead, hence the fallback).
    for (var i = 0; i < 200 && menuGrid.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final menuScroll = menuGrid.evaluate().isNotEmpty
        ? menuGrid
        : find.descendant(
            of: find.byType(TablePage), matching: find.byType(Scrollable));
    expect(menuScroll, findsWidgets,
        reason: 'the captain menu must render its dish grid');
    for (var i = 0;
        i < 30 && find.text(dishName).evaluate().isEmpty;
        i++) {
      await tester.drag(menuScroll.first, const Offset(0, -400),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Tap the whole tile: on a short landscape viewport the dish label near the
    // bottom of the (tall) tile can be below the fold even when the tile shows.
    expect(find.text(dishName), findsWidgets,
        reason: 'the captain menu must offer the seeded dish $dishName');
    final dish = find.text(dishName).first;
    final dishTile =
        find.ancestor(of: dish, matching: find.byType(InkWell));
    await tapWhenReady(tester, dishTile);
    await tester.pump(const Duration(milliseconds: 300));

    // On the phone's tall menu the cart sits below the fold; drag to it.
    final tableScroll = find.descendant(
        of: find.byType(TablePage), matching: find.byType(Scrollable));
    for (var i = 0;
        i < 80 && find.text('ناردن').evaluate().isEmpty;
        i++) {
      await tester.drag(tableScroll.first, const Offset(0, -500),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
    }

    final send = find.text('ناردن');
    expect(send, findsOneWidget,
        reason: 'the captain send button must be present once a dish is chosen');
    await tapWhenReady(tester, send);
    await tester.pump(const Duration(milliseconds: 600));
    checkNoError(tester, 'captain send');

    final captainItems = await db.getOrderItems(1);
    expect(captainItems, hasLength(1));
    expect(captainItems.single.name, 'بەرگەری گۆشتی');
    final afterOrder = await db.getTable(1);
    expect(afterOrder!.status, isNot(TableStatus.empty));
    expect(afterOrder.totalAmount, 5000);
    final total = afterOrder.totalAmount;

    // ---- CASHIER ----
    await backToLogin(tester, 'captain');
    await enterPin(tester, '22334');
    await pumpUntil(tester, find.byType(CashierWelcomePage));
    checkNoError(tester, 'cashier welcome');

    await tester.ensureVisible(find.text('دەستپێکردنی شەفت'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('دەستپێکردنی شەفت'), warnIfMissed: false);
    await pumpUntil(tester, find.byType(CashierHomePage));
    checkNoError(tester, 'cashier home');

    await tester.tap(find.widgetWithText(TableCard, 'مێز 1').first,
        warnIfMissed: false);
    await tester.pump();
    await pumpUntil(tester, find.byType(CashierUnifiedTablePage));
    checkNoError(tester, 'cashier unified table');

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
    await tapWhenReady(tester, openSettle);
    await pumpUntil(tester, find.text('واسڵ کردنی پارە'));
    checkNoError(tester, 'cash calculator');

    final expectedPaid = total;
    final dialog = find.byType(Dialog);
    final cashField =
        find.descendant(of: dialog, matching: find.byType(TextField));
    await tester.enterText(cashField.last, expectedPaid.toInt().toString());
    await tester.pump(const Duration(milliseconds: 300));
    final confirm =
        find.descendant(of: dialog, matching: find.text('واسڵ کردن'));
    expect(confirm, findsOneWidget);
    // The dialog body scrolls: on a 411-tall landscape phone the confirm button
    // starts below the fold, and `tap` on an off-screen widget is a silent
    // no-op - the settle never ran and the assertions below failed on an empty
    // settled-orders list. Bring it on screen first.
    await tapWhenReady(tester, confirm);
    await tester.pump(const Duration(milliseconds: 900));
    // The dialog closing is the settle's own acknowledgement; wait for it rather
    // than betting on a fixed delay.
    await pumpUntil(tester, find.byType(Dialog), negate: true);
    checkNoError(tester, 'cash settle');

    final settled = await db.getAllSettledOrders();
    final mine = settled.where((o) => o.tableId == 1).toList();
    expect(mine, hasLength(1));
    expect(mine.single.totalAmount, expectedPaid);
    final afterSettle = await db.getTable(1);
    expect(afterSettle!.status, TableStatus.empty);
    expect(await db.getOrderItems(1), isEmpty);

    // Integration runs use REAL time (`isRunningUnderTest` is false on a device),
    // so the pages' periodic timers are live. Unmount the app and stop the hub
    // before tearDown closes the database, or a late tick would touch a closed
    // DB and be reported as a phantom failure.
    disconnectSync();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 800));
  });
}
