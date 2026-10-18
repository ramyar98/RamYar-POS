import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_lock_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_table_hold_page.dart';
import 'package:ramyar_pos/models/order_model.dart';

/// The cashier standing in front of a table a captain is working.
///
/// The screen exists because the cashier has every table at their disposal and
/// used to simply walk in: the captain's claim was overwritten without anyone
/// being told, so two people ended up working one table and neither knew. These
/// tests pin down what the screen has to do - name the captain in full, offer
/// the one way through, and never destroy the order on the way.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
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
    await db.resetForTesting();
  });

  /// Stands a captain at table 1 with a live order on it.
  Future<void> seatCaptain({String name = 'ئاراس', int userId = 2}) async {
    await db.batchSendAndOccupy(1, [
      OrderItem(
        id: 'a',
        name: 'خواردن',
        price: 3000,
        quantity: 2,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ], waiterId: '$userId', guestCount: 4);
    await db.lockTable(TableLock(
      tableId: 1,
      deviceId: 'captain-device',
      userId: userId,
      userName: name,
      role: 'waiter',
    ));
  }

  Future<void> pumpHold(
    WidgetTester tester, {
    String captainName = 'ئاراس',
    int captainId = 2,
  }) async {
    final table = (await db.getTable(1))!;
    final lock = (await db.getTableLockById(1))!;
    expect(lock.userName, captainName);

    tester.view.physicalSize = const Size(914, 411);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Pushed on top of a placeholder rather than used as `home:`, because a
    // root route has nothing to pop back to and the leave path is half of what
    // this screen is being tested for.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: AppState(
          currentLanguage: AppLanguage.kurdish,
          onLanguageChanged: (_) {},
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('cashier grid')),
          ),
        ),
      ),
    );
    unawaited(navigator.currentState!.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CashierTableHoldPage(table: table, lock: lock),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the screen paints the captain holding the table', (tester) async {
    await seatCaptain(name: 'ئاراس');
    await pumpHold(tester, captainName: 'ئاراس');

    // The whole point: the cashier can see who it is before going in.
    expect(find.text('ئاراس'), findsWidgets);
    expect(find.text('کاپتنی مێزەکە'), findsOneWidget);
    // The table itself is named, so a cashier with several bells ringing knows
    // which one this is.
    expect(find.textContaining('مێزی مێز 1'), findsOneWidget);
  });

  testWidgets('the running bill is on screen', (tester) async {
    await seatCaptain();
    await pumpHold(tester);

    expect(find.text('6,000 IQD'), findsOneWidget);
    expect(find.text('میوان'), findsOneWidget);
  });

  testWidgets('the only way on is the eject button', (tester) async {
    await seatCaptain();
    await pumpHold(tester);

    expect(find.textContaining('دەرکردنی ئاراس لە مێزەکە'), findsOneWidget);
    expect(find.text('گەڕانەوە بۆ مێزەکان'), findsOneWidget);
  });

  testWidgets('ejecting takes the table off the captain and keeps the order',
      (tester) async {
    await seatCaptain();
    await pumpHold(tester);

    await tester.tap(find.textContaining('دەرکردنی ئاراس لە مێزەکە'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(await db.getTableLockById(1), isNull,
        reason: 'the captain no longer holds the table');
    final table = (await db.getTable(1))!;
    expect(table.waiterId, isEmpty, reason: 'and is not serving it');
    // The reason the cashier is here at all: this bill must still be settleable.
    expect(table.totalAmount, 6000);
    expect(await db.getOrderItems(1), hasLength(1));
  });

  testWidgets('going back changes nothing', (tester) async {
    await seatCaptain();
    await pumpHold(tester);

    await tester.tap(find.text('گەڕانەوە بۆ مێزەکان'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await db.getTableLockById(1), isNotNull,
        reason: 'the captain keeps his table - the cashier just did not come in');
    expect((await db.getTable(1))!.waiterId, '2');
  });

  testWidgets('the system back button does not slip past the screen',
      (tester) async {
    await seatCaptain();
    await pumpHold(tester);

    // PopScope(canPop: false) is what makes the hardware/gesture back leave the
    // screen instead of walking into the table behind it. Asserted on the
    // widget rather than by synthesising a gesture, because a synthetic
    // popRoute has no navigator behind it here and throws instead of testing
    // anything real.
    // Matched by predicate rather than `find.byType`: the generic argument is
    // reified at the use site, so the type literal does not reliably match.
    final scope = tester.widget<PopScope<dynamic>>(
      find.byWidgetPredicate((w) => w is PopScope<dynamic>),
    );
    expect(scope.canPop, isFalse,
        reason: 'back must not be a way into a table a captain is on');

    // And it must actually be wired to leave, not merely refuse: running the
    // handler it registered is the path a back press takes.
    scope.onPopInvokedWithResult!(false, null);
    await tester.pumpAndSettle();
    expect(find.byType(CashierTableHoldPage), findsNothing,
        reason: 'back leaves this screen');
    expect(await db.getTableLockById(1), isNotNull,
        reason: 'a back gesture must not be a way into an occupied table');
  });

  testWidgets('a cashier is told the difference between captain and cashier',
      (tester) async {
    // Cashiers work every table, so a cashier holding a table must not raise
    // this screen for another cashier at all - the gate checks the role. This
    // test pins the label logic on the other side of that.
    await seatCaptain(name: 'کاشێر ژیار');
    await pumpHold(tester, captainName: 'کاشێر ژیار');
    expect(find.text('کاشێر ژیار'), findsWidgets);
  });

  testWidgets('an unnamed captain still renders instead of crashing',
      (tester) async {
    await db.occupyTable(1, '2', guestCount: 2);
    await db.lockTable(TableLock(
      tableId: 1,
      deviceId: 'd',
      userId: 2,
      userName: '',
      role: 'waiter',
    ));
    await pumpHold(tester, captainName: '');
    expect(find.text('ناسەرەوە'), findsWidgets);
  });
}
