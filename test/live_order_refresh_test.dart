import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';

/// The complaint this covers: a captain rang food in on their device and the
/// cashier's screen never showed it.
///
/// The rows did arrive and the table total was right - the cashier just kept
/// looking at the list they had built the first time the page opened, because
/// nothing told the screen to look again when the change came from *another*
/// device. Every write here therefore ends on the remote path, exactly as it
/// does when the hub applies a mutation that arrived over the socket.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The isolating factory hangs widget tests; the non-isolate one does not.
    databaseFactory = databaseFactoryFfiNoIsolate;
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

  Widget wrap(Widget child) => ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: MaterialApp(home: child),
      );

  /// The item lines the screen is currently showing, as the screen itself
  /// rendered them. Read off the widget rather than off the database: the whole
  /// point is what the person can see, and a test that queried the database
  /// would pass with the refresh broken.
  List<String> visibleItems(WidgetTester tester) {
    final text = tester.widget<Text>(find.byKey(const ValueKey('items-5')));
    if (text.data == null || text.data!.trim().isEmpty) return const [];
    return text.data!.split(' | ').toList();
  }

  /// The table's total, as the screen is currently showing it.
  String visibleTotal(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('total-5'))).data!;

  TableStatus visibleStatus(WidgetTester tester) {
    final text = tester.widget<Text>(find.byKey(const ValueKey('status-5')));
    return TableStatus.values[int.parse(text.data!.split('=')[1])];
  }

  /// Pumps twice: once to run the provider's own future, once to let the frame
  /// that future completed in be laid out.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('an order from another device shows up on the cashier\'s table '
      'without anyone re-entering the page', (tester) async {
    await tester.pumpWidget(wrap(const _CashierTableProbe()));
    await settle(tester);

    expect(visibleItems(tester), isEmpty);
    expect(visibleTotal(tester), 'total=0.0');

    // A captain on another device rings in two kebabs. This is the same call the
    // hub makes when the mutation arrives, inside a remote-apply window so it
    // cannot echo back out.
    db.remoteMutationDepth++;
    try {
      await db.batchSendAndOccupy(5, [
        OrderItem(
          id: 'captain-1',
          name: 'کەباب',
          price: 10000,
          quantity: 2,
          category: 'گەرم',
          waiterName: 'کاپتن 1',
        ),
      ], guestCount: 4, waiterId: '101');
    } finally {
      db.remoteMutationDepth--;
    }
    await settle(tester);

    expect(visibleItems(tester), ['کەباب x2']);
    expect(visibleTotal(tester), 'total=20000.0');
  });

  testWidgets('a second round of the same dish shows as a second line',
      (tester) async {
    await tester.pumpWidget(wrap(const _CashierTableProbe()));
    await settle(tester);

    db.remoteMutationDepth++;
    try {
      await db.batchSendAndOccupy(5, [
        OrderItem(
          id: 'round-1',
          name: 'کەباب',
          price: 10000,
          category: 'گەرم',
          waiterName: 'کاپتن 1',
        ),
      ], guestCount: 2, waiterId: '101');
      await db.batchSendAndOccupy(5, [
        OrderItem(
          id: 'round-2',
          name: 'کەباب',
          price: 10000,
          category: 'گەرم',
          waiterName: 'کاپتن 1',
        ),
      ], guestCount: 2, waiterId: '101');
    } finally {
      db.remoteMutationDepth--;
    }
    await settle(tester);

    // Both rounds are on the table and the total counts both. This is the case
    // that used to lose the second round on its way to the cashier.
    expect(visibleItems(tester), ['کەباب x1', 'کەباب x1']);
    expect(visibleTotal(tester), 'total=20000.0');
  });

  testWidgets('a bill requested on another device reaches the table list',
      (tester) async {
    await tester.pumpWidget(wrap(const _CashierTableProbe()));
    await settle(tester);
    expect(visibleStatus(tester), TableStatus.empty);

    db.remoteMutationDepth++;
    try {
      await db.occupyTable(5, '101', guestCount: 3);
      await db.requestBill(5);
    } finally {
      db.remoteMutationDepth--;
    }
    await settle(tester);

    expect(
      visibleStatus(tester),
      TableStatus.billRequested,
      reason: 'the captain pressed the bell on their own device',
    );
  });

  testWidgets('freeing a table on another device clears it here too',
      (tester) async {
    await tester.pumpWidget(wrap(const _CashierTableProbe()));
    await settle(tester);
    await db.occupyTable(5, '101', guestCount: 2);
    await settle(tester);

    db.remoteMutationDepth++;
    try {
      await db.freeTable(5);
    } finally {
      db.remoteMutationDepth--;
    }
    await settle(tester);

    expect(visibleItems(tester), isEmpty);
    expect(visibleStatus(tester), TableStatus.empty);
  });

  test('the notifier fires for a local change and for a remote one alike',
      () async {
    var bumps = 0;
    void listener() => bumps++;
    db.orderRevision.addListener(listener);
    addTearDown(() => db.orderRevision.removeListener(listener));

    await db.addOrderItem(5, OrderItem(
      id: 'x1',
      name: 'چای',
      price: 1000,
      category: 'گەرم',
    ));
    final afterLocal = bumps;
    expect(afterLocal, greaterThan(0), reason: 'a local add must notify');

    db.remoteMutationDepth++;
    try {
      await db.addOrderItem(5, OrderItem(
        id: 'x2',
        name: 'چای',
        price: 1000,
        category: 'گەرم',
      ));
    } finally {
      db.remoteMutationDepth--;
    }
    expect(bumps, greaterThan(afterLocal),
        reason: 'an order arriving from another device must notify just the same');
  });

  test('the notifier fires for every path that changes what a table shows',
      () async {
    final paths = <String, Future<void> Function()>{
      'addOrderItem': () => db.addOrderItem(
          5, OrderItem(id: 'p1', name: 'چای', price: 1000, category: 'گەرم')),
      'batchAddOrderItems': () => db.batchAddOrderItems(5, [
        OrderItem(id: 'p2', name: 'چای', price: 1000, category: 'گەرم'),
      ]),
      'batchSendAndOccupy': () => db.batchSendAndOccupy(
        5,
        [OrderItem(id: 'p3', name: 'چای', price: 1000, category: 'گەرم')],
        guestCount: 1,
        waiterId: '101',
      ),
      'occupyTable': () => db.occupyTable(5, '101', guestCount: 1),
      'requestBill': () => db.requestBill(5),
      'removeOrderItem': () async {
        await db.batchAddOrderItems(5, [
          OrderItem(id: 'p4', name: 'چای', price: 1000, category: 'گەرم'),
        ]);
        await db.removeOrderItem(5, 'p4');
      },
      'transferSingleItem': () async {
        await db.batchAddOrderItems(5, [
          OrderItem(id: 'p5', name: 'چای', price: 1000, category: 'گەرم'),
        ]);
        await db.transferSingleItem(5, 6, 'p5');
      },
      'freeTable': () => db.freeTable(5),
      'deleteTable': () => db.deleteTable(5),
      'clearAllTables': () => db.clearAllTables(),
      'resetTablesToRange': () => db.resetTablesToRange(5),
    };

    for (final entry in paths.entries) {
      var bumps = 0;
      void listener() => bumps++;
      db.orderRevision.addListener(listener);
      await entry.value();
      db.orderRevision.removeListener(listener);
      expect(bumps, greaterThan(0),
          reason: '${entry.key} changes the screen and must say so');
    }
  });
}

/// Watches the same providers the open table screens watch, and prints what it
/// sees. Standing in for the real page keeps this test about the wiring rather
/// than about any one screen's layout.
class _CashierTableProbe extends ConsumerWidget {
  const _CashierTableProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(orderRevisionProvider);
    final orders = ref.watch(tableOrdersProvider(5));
    final table = ref.watch(tableDetailProvider(5));
    return Scaffold(
      body: Column(
        children: [
          orders.when(
            loading: () => const Text('loading', key: ValueKey('items-5')),
            error: (Object e, StackTrace s) =>
                Text('error: $e', key: const ValueKey('items-5')),
            data: (List<OrderItem> items) => Text(
              items.map((OrderItem e) => '${e.name} x${e.quantity}').join(' | '),
              key: const ValueKey('items-5'),
            ),
          ),
          table.when(
            loading: () => const Text('status=loading',
                key: ValueKey('status-5')),
            error: (Object e, StackTrace s) =>
                Text('error: $e', key: const ValueKey('status-5')),
            data: (TableModel? t) => Column(
              children: [
                Text('status=${t?.status.index}',
                    key: const ValueKey('status-5')),
                Text('total=${t?.totalAmount}', key: const ValueKey('total-5')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
