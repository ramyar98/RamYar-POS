import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_cancelled_items_page.dart';
import 'package:ramyar_pos/page/waiter/waiter_home_page.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

/// What a captain is allowed to do with the cashier's «ڕەتکراوەکان».
///
/// The complaint behind this: the cashier throws a dish out and the captain who
/// rang it in never finds out. They find out by asking, which always sounds like
/// an accusation, so it has to be visible on the floor instead.
///
/// The line is drawn at who owns the table. A captain's copy of the list is a
/// window - the rejected dish, which table it came off, who rejected it and what
/// it was worth - because that is what they are asked about. Putting a rejected
/// dish back writes onto a live table order and seats a guest, so that button
/// stays the cashier's and is not merely disabled on the captain's device: it is
/// not built at all, so there is nothing to press and nothing to get wrong.
///
/// Deliberately no Kurdish literals: every assertion is on a widget type, an icon
/// or an ASCII number, so this file cannot rot when a translation changes.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);

  void seed(UserModel? user) => state = user;
}

const _cashierId = 5;

/// The «ڕەتکراوەکان» button on the captain's app bar. The rounded block icon is
/// the only `Icons.block_rounded` on the page, so the button is addressable
/// without typing its label.
Finder get _appBarButton =>
    find.ancestor(of: find.byIcon(Icons.block_rounded), matching: find.byType(IconButton));

/// The count itself. A [Badge] always builds itself and only hides its label, so
/// "is there a badge widget" proves nothing - the question is whether a number is
/// written, which is the label. While the queue is empty there must be no label
/// at all: a permanent "0" is the same mistake as a permanent "0" on the
/// cashier's tab.
Finder get _appBarBadge =>
    find.descendant(of: _appBarButton, matching: find.byType(Badge));

/// The one control that puts rejected food back on a table.
Finder get _moveBackButton => find.byIcon(Icons.drive_file_move_rounded);

/// The number the app bar is currently writing, or `null` when it is writing
/// none. The badge's own `isLabelVisible` flag is not the assertion - it hides
/// the label, and what the captain reads is the label.
String? appBarCountText(WidgetTester tester) {
  final label = find.descendant(of: _appBarBadge, matching: find.byType(Text));
  if (label.evaluate().isEmpty) return null;
  return tester.widget<Text>(label).data;
}

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

  /// The cashier throws a dish out. No shift is open, so this lands with
  /// `shiftId = 0` - which is exactly what the row looks like on a floor device
  /// that never opened the till, and is why the queue cannot be shift-scoped.
  Future<void> reject(
    int tableId,
    String item, {
    int quantity = 1,
    int by = _cashierId,
  }) async {
    await db.recordCancelledItem(
      tableId: tableId,
      tableName: 'Table $tableId',
      itemName: item,
      price: 1500,
      quantity: quantity,
      category: 'food',
      cancelledBy: by,
      cancelledByName: 'Cashier 1',
    );
  }

  /// The floor page as a captain gets it.
  ///
  /// Deliberately signed out. A signed-in captain's page dials the shop's till
  /// the moment it appears - discovery broadcast and all - and a test that did
  /// that would reach out to whatever POS server is live on this network and
  /// write into it. Nothing in this feature depends on the session: the app bar
  /// and the queue are the same for every role that lands on this page, and
  /// `delivery_features_test.dart` opens it the same way.
  Future<void> openWaiterHome(WidgetTester tester) async {
    // The real viewport, not just a MediaQuery override: the app bar carries
    // four controls and only fits the tablet the app runs on. Without this the
    // bar overflows and the test fails on a layout error that has nothing to do
    // with the count it is here to check.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());

    await tester.pumpWidget(_wrap(ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(db),
        authProvider.overrideWith((ref) => auth),
      ],
      child: const MaterialApp(home: WaiterHomePage()),
    )));
    await _pumpUntil(tester, find.byType(TableCard));
  }

  /// Tears the floor page down. The test body, not `addTearDown`: the framework
  /// checks for pending timers *before* teardown callbacks run, and the page
  /// polls every two seconds, so it has to be unmounted while the test is still
  /// in control.
  Future<void> closeFloor(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(WaiterHomePage)));

  testWidgets('the captain sees how much food was thrown out, live',
      (tester) async {
    await openWaiterHome(tester);

    expect(_appBarButton, findsOneWidget,
        reason: 'the captain needs a way in to the rejected list');
    expect(appBarCountText(tester), isNull,
        reason: 'nothing rejected yet, so no number at all');

    await reject(1, 'Burger');
    await _pumpUntil(tester, find.descendant(of: _appBarBadge, matching: find.text('1')));

    await reject(2, 'Pizza', quantity: 2);
    await _pumpUntil(tester, find.descendant(of: _appBarBadge, matching: find.text('2')));
    expect(appBarCountText(tester), '2');

    // The cashier puts one back on a table: the number drops without the captain
    // touching anything, because the row leaves the queue.
    final pending = await db.getPendingCancelledItems();
    await db.markCancelledItemServed(pending.last.id);
    await _pumpUntil(tester, find.descendant(of: _appBarBadge, matching: find.text('1')));
    expect(appBarCountText(tester), '1');

    // And the way a captain's device really hears about a rejection: the row
    // arriving from the till rather than being written by this device's own
    // database call. It is the same insert, so the number has to move too.
    await db.addCancelledItem({
      'shiftId': 0,
      'tableId': 3,
      'tableName': 'Table 3',
      'itemName': 'Salad',
      'itemPrice': 800.0,
      'quantity': 1,
      'category': 'food',
      'cancelledAt': DateTime.now().toIso8601String(),
      'cancelledBy': _cashierId,
      'cancelledByName': 'Cashier 1',
      'status': 'pending',
      'servedAt': '',
    });
    await _pumpUntil(tester, find.descendant(of: _appBarBadge, matching: find.text('2')));
    expect(
      (containerOf(tester).read(pendingCancelledItemsProvider).asData?.value ?? [])
          .length,
      2,
    );
    await closeFloor(tester);
  });

  testWidgets('the captain reads the list and cannot touch it', (tester) async {
    await openWaiterHome(tester);
    await reject(1, 'Burger');
    await _pumpUntil(tester, find.descendant(of: _appBarBadge, matching: find.text('1')));

    await tester.tap(_appBarButton);
    await _pumpUntil(tester, find.byType(CashierCancelledItemsPage));

    // The window: what was thrown out, where it came from and who threw it.
    expect(find.text('Burger'), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_rounded), findsOneWidget,
        reason: 'the count banner is the whole point of showing them the list');
    expect(find.byIcon(Icons.drive_file_move_rounded), findsNothing,
        reason: 'a captain must not be able to put rejected food back');
    // Not "the button is greyed out" - the page builds no button at all, so
    // there is nothing on it that can be pressed by mistake or by a stray tap.
    // Scoped to the page, because the floor page underneath has its own
    // "add table" button and a bare `findsNothing` would never be true.
    expect(
      find.descendant(of: find.byType(CashierCancelledItemsPage),
          matching: find.byType(FilledButton)),
      findsNothing,
    );
    expect(find.byIcon(Icons.visibility_rounded), findsOneWidget,
        reason: 'and it has to say why, or a captain just wonders');

    await closeFloor(tester);
  });

  testWidgets('the open page empties itself when the till serves the item',
      (tester) async {
    // The actual complaint: a captain opens «ڕەتکراوەکان», sits there looking
    // at it, the cashier moves the dish back onto a table at the till, and the
    // captain's screen kept showing the row as if it were still rejected. The
    // page loaded its list once and never listened again.
    await openWaiterHome(tester);
    await reject(1, 'Burger');
    await _pumpUntil(tester, find.descendant(of: _appBarBadge, matching: find.text('1')));

    await tester.tap(_appBarButton);
    await _pumpUntil(tester, find.byType(CashierCancelledItemsPage));
    expect(find.text('Burger'), findsOneWidget);

    // The dish goes back on a table - the way it really happens, as a database
    // write landing on this device from the till, not as something this page
    // asked for.
    final pending = await db.getPendingCancelledItems();
    await db.markCancelledItemServed(pending.last.id);

    // The row has to disappear from the still-open page on its own, with no
    // pull-to-refresh and no reopen: the till's write lands here, the revision
    // notifier fires, and the page watches it.
    final end = DateTime.now().add(const Duration(seconds: 5));
    var gone = false;
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      final onPage = find
          .descendant(
            of: find.byType(CashierCancelledItemsPage),
            matching: find.text('Burger'),
          )
          .evaluate()
          .isNotEmpty;
      if (!onPage) {
        gone = true;
        break;
      }
    }
    expect(gone, isTrue,
        reason: "the row was still on the captain's open page after the till "
            'served it - the page had to be closed and reopened to see it');
  });

  testWidgets("the cashier's copy still has the button", (tester) async {
    await reject(1, 'Burger');

    await tester.pumpWidget(_wrap(ProviderScope(
      overrides: [localDbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CashierCancelledItemsPage()),
    )));
    await _pumpUntil(tester, find.byType(FilledButton));

    expect(_moveBackButton, findsOneWidget,
        reason: 'the control is hidden from captains, not taken away from the till');
    expect(find.byIcon(Icons.visibility_rounded), findsNothing,
        reason: 'and the read-only line would be a lie on the cashier\'s device');
    expect(find.text('Burger'), findsOneWidget);
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
