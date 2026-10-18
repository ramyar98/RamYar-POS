import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';

/// The cashier's «ئاگەدارکردنەوەی مێز» queue is driven by exactly one thing:
/// a captain pressing the 🔔 «ئاگەدارکردنەوە» button on that table.
///
/// It used to fill up on its own - seating a guest, merging tables and
/// transferring items all pushed the table onto the cashier's screen, so the
/// cashier's "queue" was really "every occupied table" and the button meant
/// nothing. These tests pin the explicit-only rule down, including the case
/// that motivated it: a cleared table must not come back on its own.
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

  OrderItem item(String id, {double price = 1000, int qty = 1}) => OrderItem(
        id: id,
        name: 'خواردن $id',
        price: price,
        quantity: qty,
        createdAt: DateTime.now().toIso8601String(),
      );

  Future<List<int>> queued() async =>
      (await db.getTableNotifications()).map((n) => n.tableId).toList()..sort();

  group('nothing enters the queue on its own', () {
    test('seating a guest does not notify the cashier', () async {
      await db.occupyTable(1, '2', guestCount: 4);
      expect(await queued(), isEmpty);
    });

    test('sending items to a table does not notify the cashier', () async {
      await db.batchSendAndOccupy(1, [item('a'), item('b')], waiterId: '2');
      expect(await queued(), isEmpty);
    });

    test('requesting the bill does not notify the cashier', () async {
      // «ناردن بۆ کاشێر» belongs to the separate داواکاری tab, not this queue.
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.requestBill(1);
      expect(await queued(), isEmpty);
      expect((await db.getTable(1))!.sentToCashier, isTrue,
          reason: 'the داواکاری tab is driven by its own flag');
    });

    test('merging tables does not notify the cashier', () async {
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.mergeTables(1, 2);
      expect(await queued(), isEmpty,
          reason: 'the target table is occupied now, but nobody pressed 🔔');
    });

    test('transferring items does not notify the cashier', () async {
      await db.batchSendAndOccupy(1, [item('a'), item('b')], waiterId: '2');
      await db.transferItems(1, 2);
      expect(await queued(), isEmpty);
    });

    test('transferring a single item does not notify the cashier', () async {
      await db.batchSendAndOccupy(1, [item('a'), item('b')], waiterId: '2');
      await db.transferSingleItem(1, 2, 'a');
      expect(await queued(), isEmpty);
    });
  });

  group('the bell is what puts a table in the queue', () {
    test('notifying adds the table, and the cashier sees it', () async {
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.notifyTable(1);
      expect(await queued(), [1]);
    });

    test('notifying several tables queues each of them once', () async {
      for (final t in [1, 2, 3]) {
        await db.batchSendAndOccupy(t, [item('i$t')], waiterId: '2');
      }
      for (final t in [1, 2, 3]) {
        await db.notifyTable(t);
      }
      expect(await queued(), [1, 2, 3]);

      // Pressing 🔔 again must not duplicate the entry.
      await db.notifyTable(2);
      expect(await queued(), [1, 2, 3]);
    });

    test('the queue shows the table name and amount the cashier needs',
        () async {
      await db.batchSendAndOccupy(4, [item('a', price: 2500, qty: 2)],
          waiterId: '2');
      await db.notifyTable(4);
      final notif = (await db.getTableNotifications()).single;
      expect(notif.tableId, 4);
      expect(notif.tableName, 'مێز 4');
      expect(notif.totalAmount, 5000);
    });

    test('a bell on an empty table is not queued (no guests to serve)', () async {
      await db.notifyTable(7);
      expect(await queued(), isEmpty,
          reason: 'the queue only lists tables that are actually occupied');
    });

    test('the captain is notified live, without polling', () async {
      var notified = 0;
      db.onTableNotification = () => notified++;
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      expect(notified, 0, reason: 'seating must stay silent');
      await db.notifyTable(1);
      expect(notified, greaterThan(0));
      db.onTableNotification = null;
    });
  });

  group('leaving the queue', () {
    test('the cashier tapping the entry removes it', () async {
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.notifyTable(1);
      expect(await queued(), [1]);
      await db.clearTableNotifications(1);
      expect(await queued(), isEmpty);
    });

    test('settling the table removes it for good', () async {
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.notifyTable(1);
      await db.settleTable(1, 1000, 0, 0, 0);
      expect(await queued(), isEmpty);
    });

    test('freeing the table removes it for good', () async {
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.notifyTable(1);
      await db.freeTable(1);
      expect(await queued(), isEmpty);
    });

    test('a cleared table does NOT reappear when guests sit again', () async {
      // The stale-row trap: the notification row outlives the seating, so a
      // re-occupied table would slide back onto the cashier's screen with no
      // bell press at all.
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.notifyTable(1);
      await db.freeTable(1);

      await db.batchSendAndOccupy(1, [item('b')], waiterId: '3');
      expect(await queued(), isEmpty,
          reason: 'seating a new party is not a request');

      // ...and the captain can still ring for this new party.
      await db.notifyTable(1);
      expect(await queued(), [1]);
    });

    test('merging a notified table away drops it from the queue', () async {
      await db.batchSendAndOccupy(1, [item('a')], waiterId: '2');
      await db.batchSendAndOccupy(2, [item('b')], waiterId: '2');
      await db.notifyTable(1);
      expect(await queued(), [1]);
      await db.mergeTables(1, 2);
      expect(await queued(), isEmpty,
          reason: 'the source table no longer exists for the cashier');
    });
  });
}
