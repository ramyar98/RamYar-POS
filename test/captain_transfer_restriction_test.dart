import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/cashier/transfer_page.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// Who may merge two tables' food.
///
/// The complaint behind this: a captain could move a table whose food was
/// sitting on top of an occupied one, and two parties' food quietly became a
/// single order. That decision belongs to the till - a captain may only move a
/// load onto an EMPTY table, so their hand can never mix two tables.
///
/// `TransferPage` is shared, so the same widget has to behave differently for
/// the two roles: on a captain's copy the occupied tiles turn inert (dimmer,
/// with a small block badge) once a source is picked, and on the cashier's copy
/// the full merge still works.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);

  void seed(UserModel? user) => state = user;
}

const _waiter = UserModel(
  id: 2,
  name: 'کاپتن 1',
  pin: '1234',
  role: UserRole.waiter,
);

const _cashier = UserModel(
  id: 5,
  name: 'کاشێر 1',
  pin: '5678',
  role: UserRole.cashier,
);

/// Seed two occupied tables - 1 is the source, 2 an occupied target - and leave
/// only a few empty ones. The floor is trimmed because the page lists the empty
/// tables above the occupied ones: with the full hundred, the occupied grid
/// (the thing this test is about) is pushed off-screen and never built.
Future<void> _seedTables(LocalDatabase db) async {
  await db.db.delete('tables', where: 'id > 5');
  await db.occupyTable(1, '5', guestCount: 2);
  await db.addOrderItem(
    1,
    OrderItem(
      id: 'a1',
      name: 'قەیمە',
      price: 8500,
      quantity: 1,
      waiterName: 'کاپتن 1',
    ),
  );
  await db.occupyTable(2, '5', guestCount: 2);
  await db.addOrderItem(
    2,
    OrderItem(
      id: 'b1',
      name: 'چای',
      price: 500,
      quantity: 1,
      waiterName: 'کاپتن 1',
    ),
  );
}

Future<void> _openTransfer(
  WidgetTester tester,
  LocalDatabase db,
  UserModel user,
) async {
  // The real viewport, not just a MediaQuery override: the grid and the app bar
  // need the room the app really runs in.
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth =
      _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier())
        ..seed(user);

  await tester.pumpWidget(_wrap(ProviderScope(
    overrides: [
      localDbProvider.overrideWithValue(db),
      authProvider.overrideWith((ref) => auth),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TransferPage(sourceTableId: 1),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  )));
  await tester.tap(find.text('open'));
  // Let the pushed route build before reaching for its element.
  await _pumpUntil(tester, find.byType(TransferPage));
  // Reading the floor provider starts it empty - the home page is what loads
  // it in the app - so the page under test needs the same kick the floor gives
  // it: build the table list before expecting tiles. Like the floor, this is
  // fired and left to the pump: awaiting a database read directly inside a
  // widget test's fake clock is what stalls it.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TransferPage)),
  );
  unawaited(container.read(waiterProvider.notifier).syncTableScope());
  // The page loads its tables asynchronously from the database.
  await _pumpUntil(tester, find.text('مێز 3'));
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
    // The seeding writes would otherwise fire-and-forget a `pending_sync` insert
    // per change. This setup runs in the real async zone, but the test body runs
    // in the widget tester's fake clock - the queued writes would be orphaned
    // the moment that clock takes over and hold sqflite's lock, so every read
    // the page makes would wait behind them. A sink that drops them keeps the
    // seed local, which is all this test needs.
    db.onMutation = (action, data) {};
    await _seedTables(db);
  });

  tearDown(() async {
    disconnectSync(db);
    await db.resetForTesting();
  });

  testWidgets('a captain can only move a table onto an empty one',
      (tester) async {
    await _openTransfer(tester, db, _waiter);

    // The captain is told up front: empty destination only.
    expect(find.text('تەنها دەتوانیت بۆ مێزی بەتاڵ بگوازیتەوە'), findsOneWidget,
        reason: 'the captain needs to know the merge is not theirs to make');

    // The occupied tile carries the block badge - it reads as a no-go, not as
    // a button that does nothing.
    expect(find.byIcon(Icons.block_rounded), findsWidgets,
        reason: 'every occupied destination is visibly off-limits');

    // Tapping the occupied table does nothing: no merge, page stays open.
    await tester.tap(find.text('مێز 2'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TransferPage), findsOneWidget,
        reason: 'a blocked tap must not navigate away');
    expect((await db.getOrderItems(1)).length, 1);
    expect((await db.getOrderItems(2)).length, 1,
        reason: "two parties must never become one order by a captain's tap");

    // Moving to the empty table 3 works normally and frees table 1.
    await tester.tap(find.text('مێز 3'), warnIfMissed: false);
    // Settle the pop: waiting for 'open' alone would fire mid-transition, with
    // the page still animating out.
    await tester.pumpAndSettle();
    expect(find.byType(TransferPage), findsNothing,
        reason: 'a successful transfer closes the shared page');
    expect(await db.getOrderItems(3), isNotEmpty,
        reason: 'the load moved onto the empty table');
    expect(await db.getOrderItems(1), isEmpty,
        reason: 'the source table was freed');
  });

  testWidgets('the cashier can still merge two occupied tables',
      (tester) async {
    await _openTransfer(tester, db, _cashier);

    expect(find.text('تەنها دەتوانیت بۆ مێزی بەتاڵ بگوازیتەوە'), findsNothing,
        reason: "the empty-only rule is a captain rule, not the till's");
    expect(find.byIcon(Icons.block_rounded), findsNothing,
        reason: 'occupied tables stay fully tappable at the till');

    await tester.tap(find.text('مێز 2'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect((await db.getOrderItems(2)).length, 2,
        reason: "the cashier merge joins the two tables' food");
    expect(await db.getOrderItems(1), isEmpty,
        reason: 'and frees the source table');
    expect(
      (await db.getAllTables()).firstWhere((t) => t.id == 2).status,
      TableStatus.occupied,
      reason: 'the merged table stays seated',
    );
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
