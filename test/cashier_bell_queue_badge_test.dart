import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_previous_orders_page.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/currency_converter.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

/// What a number on the cashier's «داواکاری» tab is allowed to mean.
///
/// The complaint was a number appearing on that tab by itself: walk into the
/// cashier home and the tab already showed a figure nobody had asked for. The
/// figure was the count of tables that had sent their bill, which is the bill
/// doing its job, not a captain standing at a table asking for the cashier.
///
/// So the tab now carries exactly one number, the bell queue: a table is in it
/// only after a captain pressed 🔔 «ئاگەدارکردنەوە» on that table. Everything
/// that used to light the tab up on its own - seating, ringing food in, sending
/// the bill, registering a new table - must leave it bare. And the panel's own
/// counter follows the same rule, because a permanent "0" chip is the same
/// problem in smaller type: a number where nobody is waiting.
///
/// Deliberately no Kurdish literals: every assertion below is on a widget type,
/// an icon, a key or an ASCII number, so this file cannot rot when a translation
/// changes.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);

  void seed(UserModel? user) => state = user;
}

const _cashierId = 5;
const _cashierName = 'Cashier 1';

/// The badge the tab grows once somebody rings. Nothing else in the bar is ever
/// a [Badge], so its absence/presence is the whole assertion.
Finder get _tabBadge =>
    find.descendant(of: find.byType(BottomNavigationBar), matching: find.byType(Badge));

/// The «0 ئاگەدارکردنەوە» chip in the panel header, which now exists only when
/// there is something to count.
Finder get _panelCounter => find.byKey(const ValueKey('notificationCount'));

/// The «ڕەتکراوەکان» button's icon and the number on top of it.
///
/// The button is found by its block icon (the only one on the page) and the
/// badge by being that icon's ancestor, because the badge wraps the icon and
/// exists only once the count is above zero - so its presence is itself an
/// assertion, the same way [_tabBadge]'s is.
Finder get _rejectedIcon => find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.block_rounded),
    );
Finder get _rejectedBadge =>
    find.ancestor(of: _rejectedIcon, matching: find.byType(Badge));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The no-isolate factory: a widget test runs inside `FakeAsync`, and a
    // database in a real isolate would never hand its results back.
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    disconnectSync(db);
    await db.resetForTesting();
  });

  OrderItem item(String id) => OrderItem(
        id: id,
        name: 'item $id',
        price: 1000,
        quantity: 1,
        createdAt: DateTime.now().toIso8601String(),
      );

  /// Signs a cashier in, opens their shift and lands on the home page.
  ///
  /// A cashier with no shift open is bounced to the welcome gate, so the shift
  /// is the only way to see the tab at all. The page also auto-hosts the POS
  /// socket server with a local-IP timeout, so the tree is pumped past that
  /// timeout and the server disconnected - otherwise the test ends with a
  /// pending timer and the failure lands in whichever test runs next.
  Future<void> openCashierHome(WidgetTester tester) async {
    // The real viewport, not just a MediaQuery override: the cashier's appbar
    // carries a full row of buttons and only fits the tablet the app runs on.
    // Without this the bar overflows and the test fails on a layout error that
    // has nothing to do with the number it is here to check.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth =
        _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());
    auth.seed(const UserModel(
      id: _cashierId,
      name: _cashierName,
      pin: '2233',
      role: UserRole.cashier,
    ));
    await db.startShift(CashierShift(
      cashierId: _cashierId,
      cashierName: _cashierName,
      startedAt: DateTime.now().toIso8601String(),
    ));

    await tester.pumpWidget(_wrap(ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(db),
        authProvider.overrideWith((ref) => auth),
      ],
      child: const MaterialApp(home: CashierHomePage()),
    )));
    await _pumpUntil(tester, find.byType(BottomNavigationBar));
    // The grid is loaded before the number on the tab can be called stable.
    await _pumpUntil(tester, find.byType(TableCard));

    await tester.pump(const Duration(seconds: 4));
    disconnectSync(db);
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(CashierHomePage)));

  /// Switches to the orders tab, the way the cashier does.
  Future<void> openOrdersTab(WidgetTester tester) async {
    await tester.tap(find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.byIcon(Icons.receipt_long_rounded),
    ));
    await _pumpUntil(tester, find.byType(CurrencyConverter));
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Pumps until the badge is gone, so "the number came back off" is waited for
  /// rather than sampled once and hoped over.
  Future<void> pumpUntilTabBadgeGone(WidgetTester tester) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (_tabBadge.evaluate().isEmpty) return;
    }
    fail('The tab badge never went away');
  }

  /// The status the grid is drawing for the first table.
  ///
  /// Used as proof that the page really did re-read the database, so a
  /// "nothing is on the tab" assertion cannot pass simply because the page never
  /// noticed the change.
  String gridStatusText(WidgetTester tester) =>
      tester.widget<TableCard>(find.byType(TableCard).first).statusText;

  // NOTE ON TEST COUNT.
  // Every page opened here binds a server for real, because that is what the
  // app does. `flutter test` runs files in parallel, so a file that opens the
  // page many times widens the window in which it can collide with another
  // file's socket test. The assertions are therefore grouped into a handful of
  // tests - one page each - rather than one test per rule. Coverage is the same;
  // the number of real page-opens is five instead of a dozen.

  testWidgets('nothing at all on the tab until a captain rings',
      (tester) async {
    await openCashierHome(tester);
    expect(_tabBadge, findsNothing,
        reason: 'walking in must not put a number on the tab');

    // Seating a guest and ringing food in. The old number came from exactly
    // here: `batchSendAndOccupy` sets `sentToCashier`, so every order a captain
    // ever rang lit the cashier's tab up with no bell press in the story.
    final before = gridStatusText(tester);
    await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
    await _pumpUntil(tester,
        find.byWidgetPredicate((w) => w is TableCard && w.statusText != before));
    expect(_tabBadge, findsNothing,
        reason: 'the grid really did change, so the page really did re-read');

    // And the bill. This was the other automatic source.
    final seated = gridStatusText(tester);
    await db.requestBill(1);
    expect((await db.getTable(1))!.sentToCashier, isTrue,
        reason: 'the bill really did reach the till');
    await _pumpUntil(tester,
        find.byWidgetPredicate((w) => w is TableCard && w.statusText != seated));
    expect(_tabBadge, findsNothing,
        reason: 'a printed bill is the bill doing its job, not a request');

    // And registering a new table. The grid is lazy, so the new card cannot be
    // counted on screen at 1200x900 - the room growing is proved from the data
    // the grid draws from.
    final container = containerOf(tester);
    // Above the standard 1..100, so this is a table the room did not have.
    expect(await container.read(waiterProvider.notifier).addTableWithInput('151'),
        isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    final tables = container.read(waiterProvider).asData?.value ?? [];
    expect(tables.any((t) => t.id == 151), isTrue);
    expect(await db.getTableNotifications(), isEmpty,
        reason: 'registering a table must not create a notification row');
    expect(_tabBadge, findsNothing,
        reason: 'a new table in the room is not somebody asking for the cashier');
  });

  testWidgets('the bell is the only thing that puts a number on the tab',
      (tester) async {
    await openCashierHome(tester);
    await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
    await db.batchSendAndOccupy(2, [item('b')], waiterId: '2');
    await db.notifyTable(1);
    await _pumpUntil(tester, _tabBadge);
    expect(
      tester
          .widget<Text>(find.descendant(of: _tabBadge, matching: find.byType(Text)))
          .data,
      '1',
    );

    await db.notifyTable(2);
    await _pumpUntil(tester, find.descendant(
      of: _tabBadge,
      matching: find.text('2'),
    ));
    expect(
      tester
          .widget<Text>(find.descendant(of: _tabBadge, matching: find.byType(Text)))
          .data,
      '2',
    );

    // The cashier walks over and answers it: the number comes back off.
    await db.clearTableNotifications(1);
    await _pumpUntil(tester, find.descendant(
      of: _tabBadge,
      matching: find.text('1'),
    ));
    expect(
      tester
          .widget<Text>(find.descendant(of: _tabBadge, matching: find.byType(Text)))
          .data,
      '1',
    );

    await db.clearTableNotifications(2);
    await pumpUntilTabBadgeGone(tester);
    expect(_tabBadge, findsNothing);
  });

  testWidgets("the panel's own counter follows the same rule", (tester) async {
    await openCashierHome(tester);
    await openOrdersTab(tester);
    expect(_panelCounter, findsNothing,
        reason: 'a permanent "0" chip is still a number nobody asked for');

    await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
    await db.requestBill(1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_panelCounter, findsNothing,
        reason: 'a printed bill is not a request either');

    await db.notifyTable(1);
    await _pumpUntil(tester, _panelCounter);
    final text = tester
        .widget<Text>(find.descendant(of: _panelCounter, matching: find.byType(Text)))
        .data!;
    expect(text.startsWith('1 '), isTrue,
        reason: 'the chip is the count followed by its label: "$text"');
  });

  testWidgets('the bell button is gone from the cashier appbar', (tester) async {
    await openCashierHome(tester);
    // Not "the appbar is empty" - the rest of the bar has to survive, or this
    // would pass just as well on a page that lost its buttons.
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_box_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_rounded), findsNothing,
        reason: 'the bell lives on the tab now and nowhere else');
  });

  testWidgets('the rejected button counts the dishes still waiting',
      (tester) async {
    await openCashierHome(tester);
    expect(_rejectedIcon, findsOneWidget,
        reason: 'the button itself must be on the bar');
    expect(_rejectedBadge, findsNothing,
        reason: 'nothing thrown out yet, so no number');

    // One dish thrown out by the cashier: the button reads «1».
    await db.recordCancelledItem(
      tableId: 1,
      tableName: 'مێز 1',
      itemName: 'dish A',
      price: 1000,
      quantity: 1,
      category: 'خواردن',
      cancelledBy: _cashierId,
      cancelledByName: _cashierName,
    );
    await _pumpUntil(tester, _rejectedBadge);
    expect(
      tester
          .widget<Text>(
              find.descendant(of: _rejectedBadge, matching: find.byType(Text)))
          .data,
      '1',
    );

    // A second, different dish (a different row, not a re-delivery): «2».
    await db.recordCancelledItem(
      tableId: 2,
      tableName: 'مێز 2',
      itemName: 'dish B',
      price: 2000,
      quantity: 1,
      category: 'خواردن',
      cancelledBy: _cashierId,
      cancelledByName: _cashierName,
    );
    await _pumpUntil(tester,
        find.descendant(of: _rejectedBadge, matching: find.text('2')));
    expect(
      tester
          .widget<Text>(
              find.descendant(of: _rejectedBadge, matching: find.byType(Text)))
          .data,
      '2',
    );

    // The cashier puts one back onto a table: the number drops, live.
    final first = (await db.getPendingCancelledItems()).first;
    await db.markCancelledItemServed(first.id);
    await _pumpUntil(tester,
        find.descendant(of: _rejectedBadge, matching: find.text('1')));
    expect(
      tester
          .widget<Text>(
              find.descendant(of: _rejectedBadge, matching: find.byType(Text)))
          .data,
      '1',
    );

    // And the queue empties: the badge comes off entirely rather than reading 0.
    final last = (await db.getPendingCancelledItems()).first;
    await db.markCancelledItemServed(last.id);
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end) &&
        _rejectedBadge.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_rejectedBadge, findsNothing);
  });

  testWidgets('the previous-orders button opens the shift dishes on a page',
      (tester) async {
    await openCashierHome(tester);
    final shift = (await db.getActiveShift(_cashierId))!;
    final table = (await db.getTable(1))!;
    final other = (await db.getTable(2))!;

    // The table this cashier served in the running shift, closed with two
    // dishes the guest will ask about next time.
    await db.batchSendAndOccupy(1, [
      OrderItem(
        id: 'p1',
        name: 'dish kebab',
        price: 5000,
        quantity: 2,
        createdAt: DateTime.now().toIso8601String(),
      ),
      OrderItem(
        id: 'p2',
        name: 'dish tea',
        price: 1000,
        quantity: 1,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ], waiterId: '2');
    await db.settleTable(1, 11000, 0, 0, _cashierId, shiftId: shift.id);
    // A settlement that belongs to another shift's book: shift-scoping means it
    // must not leak into this cashier's list.
    await db.settleTable(2, 3000, 0, 0, _cashierId, shiftId: 0);

    // The button opens a page now, not the old bottom sheet of settlements.
    final previousButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.receipt_rounded),
    );
    expect(previousButton, findsOneWidget,
        reason: 'the previous-orders button must be on the bar');
    await tester.tap(previousButton);
    await _pumpUntil(tester, find.byType(CashierPreviousOrdersPage));

    // Only the shift's own table is listed ...
    final row = find.descendant(
      of: find.byType(CashierPreviousOrdersPage),
      matching: find.text(table.name),
    );
    await _pumpUntil(tester, row);
    expect(
      find.descendant(
        of: find.byType(CashierPreviousOrdersPage),
        matching: find.text(other.name),
      ),
      findsNothing,
      reason: "another shift's settlement must not appear here",
    );

    // ... and tapping it shows the dishes that visit actually had.
    await tester.tap(row.first);
    await _pumpUntil(tester, find.byType(CashierTableHistoryPage));
    Finder dish(String name) => find.descendant(
          of: find.byType(CashierTableHistoryPage),
          matching: find.text(name),
        );
    await _pumpUntil(tester, dish('dish kebab'));
    expect(dish('dish kebab'), findsOneWidget);
    expect(dish('dish tea'), findsOneWidget);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Wraps a page the way the app actually builds one: RTL, a tablet-sized
/// viewport, and [AppState] because every visible string goes through
/// `context.tr`, which reads the language from there.
Widget _wrap(Widget child) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(1200, 900)),
      child: AppState(
        currentLanguage: AppLanguage.kurdish,
        onLanguageChanged: (_) {},
        child: child,
      ),
    ),
  );
}
