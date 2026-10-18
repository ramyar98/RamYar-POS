import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/debt_model.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_lock_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/models/user_model.dart';

void main() {
  setUpAll(() {
    // resetAllData clears AppPrefs too, and under test that store is the
    // SharedPreferences fallback (AppPrefs.usesOwnStore is false outside a
    // real Windows build), which needs the test binding and an in-memory mock
    // before any method channel is touched.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  group('order_delivery', () {
    test('recordOrderSent creates a waiting delivery', () async {
      await db.recordOrderSent(5);
      final deliveries = await db.getOrderDeliveries();
      expect(deliveries, hasLength(1));
      final d = deliveries.first;
      expect(d.tableId, 5);
      expect(d.hasArrived, isFalse);
      expect(d.hasPrinted, isFalse);
      expect(d.rejected, isFalse);
      expect(DateTime.tryParse(d.sentAt), isNotNull);
    });

    test('markOrderArrived and markOrderPrinted transition status', () async {
      await db.recordOrderSent(5);
      await db.markOrderArrived(5);
      var deliveries = await db.getOrderDeliveries();
      expect(deliveries.first.hasArrived, isTrue);
      expect(deliveries.first.hasPrinted, isFalse);
      expect(deliveries.first.rejected, isFalse);

      await db.markOrderPrinted(5);
      deliveries = await db.getOrderDeliveries();
      expect(deliveries.first.hasPrinted, isTrue);
      expect(deliveries.first.rejected, isFalse);
    });

    test('rejected delivery keeps printed false', () async {
      await db.recordOrderSent(5);
      await db.markOrderArrived(5, rejected: true);
      final deliveries = await db.getOrderDeliveries();
      expect(deliveries.first.rejected, isTrue);
      expect(deliveries.first.hasPrinted, isFalse);
    });

    test('clearOrderDelivery removes the row', () async {
      await db.recordOrderSent(5);
      await db.clearOrderDelivery(5);
      expect(await db.getOrderDeliveries(), isEmpty);
    });

    test('freeTable clears order delivery', () async {
      await db.recordOrderSent(5);
      await db.freeTable(5);
      expect(await db.getOrderDeliveries(), isEmpty);
    });

    test('settleTable clears items and delivery and empties the table', () async {
      await db.batchSendAndOccupy(5, [
        OrderItem(
          id: 's1', name: 'کەباب', price: 10000, quantity: 2,
          category: 'گەرمی', createdAt: '2026-01-01T10:00:00', waiterName: 'وەیتەر 1',
        ),
      ], guestCount: 2, waiterId: '101');
      await db.recordOrderSent(5);

      await db.settleTable(5, 20000, 0, 0, 4);

      expect(await db.getOrderItems(5), isEmpty);
      expect(await db.getOrderDeliveries(), isEmpty);
      final table = await db.getTable(5);
      expect(table!.status, TableStatus.empty);
      expect(table.waiterId, '');
      expect(table.guestCount, 0);
      expect(table.sentToCashier, isFalse);
    });

    test('deleteTable clears order delivery and restores the standard table', () async {
      await db.recordOrderSent(5);
      await db.deleteTable(5);
      expect(await db.getOrderDeliveries(), isEmpty);
      // The dining room is fixed at 1..100: the deleted table comes straight
      // back as a fresh, empty "مێز 5" rather than leaving a hole in the grid.
      final restored = await db.getTable(5);
      expect(restored, isNotNull);
      expect(restored!.name, 'مێز 5');
      expect(restored.status, TableStatus.empty);
    });
  });

  group('order conflict building blocks', () {
    OrderItem item(String id, String name, double price, String createdAt,
            {String waiterName = ''}) =>
        OrderItem(
          id: id,
          name: name,
          price: price,
          quantity: 2,
          category: 'گەرمی',
          createdAt: createdAt,
          waiterName: waiterName,
        );

    test('batchSendAndOccupy occupies empty table and marks sent', () async {
      await db.batchSendAndOccupy(5, [item('a', 'کەباب', 10000, '2026-01-01T10:00:00')],
          guestCount: 3, waiterId: '101');
      final table = await db.getTable(5);
      expect(table!.status, TableStatus.occupied);
      expect(table.guestCount, 3);
      expect(table.sentToCashier, isTrue);
      expect(table.totalAmount, 20000);
    });

    test('replaceTableItems replaces items and recalculates total', () async {
      await db.batchSendAndOccupy(5, [item('a', 'کەباب', 10000, '2026-01-01T10:00:00')]);
      await db.replaceTableItems(5, [item('b', 'پیتزا', 5000, '2026-01-01T09:00:00')],
          waiterId: '102');
      final items = await db.getOrderItems(5);
      expect(items, hasLength(1));
      expect(items.first.name, 'پیتزا');
      final table = await db.getTable(5);
      expect(table!.sentToCashier, isTrue);
      expect(table.totalAmount, 10000);
    });

    test('deleteTable also clears waiter assignments', () async {
      await db.assignTablesToWaiter(2, [5, 6]);
      await db.deleteTable(5);
      final assigned = await db.getWaiterTableIds(2);
      expect(assigned, isNot(contains(5)));
      expect(assigned, contains(6));
    });
  });

  group('first-wins offline duplicate scenario', () {
    test('earlier-created order replaces later one when arriving second', () async {
      final w2Order = OrderItem(
        id: 'w2',
        name: 'کەباب',
        price: 10000,
        quantity: 1,
        createdAt: '2026-01-01T10:05:00',
        waiterName: 'وەیتەر 2',
      );
      final w1Order = OrderItem(
        id: 'w1',
        name: 'کەباب',
        price: 10000,
        quantity: 1,
        createdAt: '2026-01-01T10:00:00',
        waiterName: 'وەیتەر 1',
      );

      await db.batchSendAndOccupy(5, [w2Order], guestCount: 1, waiterId: '102');
      expect((await db.getOrderItems(5)).single.waiterName, 'وەیتەر 2');

      await db.replaceTableItems(5, [w1Order], waiterId: '101');
      final items = await db.getOrderItems(5);
      expect(items.single.waiterName, 'وەیتەر 1');
    });
  });

  group('waiter ranges', () {
    test('updateUserRange re-owns unassigned tables inside the range', () async {
      await db.addUser('وەیتەر 3', '11224', UserRole.waiter, rangeStart: 150, rangeEnd: 250);
      final user = (await db.getUserById(5))!;
      expect(user.rangeStart, 150);
      expect(user.rangeEnd, 250);

      await db.addTable(const TableModel(id: 149, name: 'مێز 149', createdBy: 0));
      await db.addTable(const TableModel(id: 150, name: 'مێز 150', createdBy: 0));
      await db.addTable(const TableModel(id: 250, name: 'مێز 250', createdBy: 0));
      await db.addTable(const TableModel(id: 260, name: 'مێز 260', createdBy: 0));

      await db.updateUserRange(5, 150, 250);
      final tables = await db.getAllTables();
      expect(tables.firstWhere((t) => t.id == 149).createdBy, 0);
      expect(tables.firstWhere((t) => t.id == 150).createdBy, 5);
      expect(tables.firstWhere((t) => t.id == 250).createdBy, 5);
      expect(tables.firstWhere((t) => t.id == 260).createdBy, 0);
      expect(tables.firstWhere((t) => t.id == 25).createdBy, 2);
      expect(tables.firstWhere((t) => t.id == 55).createdBy, 3);
    });

    test('updateUserRange clears the range when null', () async {
      await db.updateUserRange(2, null, null);
      final user = await db.getUserById(2);
      expect(user!.rangeStart, isNull);
      expect(user.rangeEnd, isNull);
    });
  });

  group('resetAllData', () {
    test('clears all operational data and re-seeds tables by ranges', () async {
      await db.batchSendAndOccupy(5, [OrderItem(
        id: 'a1', name: 'کەباب', price: 10000, quantity: 1,
        category: 'گەرمی', createdAt: '2026-01-01T10:00:00', waiterName: 'وەیتەر 1',
      )], guestCount: 2, waiterId: '101');
      await db.recordOrderSent(5);
      await db.addPendingSync('occupyTable', {'tableId': 9});
      await db.addDebt(const DebtModel(
        id: 0, tableId: 5, tableName: 'مێز 5', amount: 10000, reason: 'قەرز',
        createdAt: '2026-01-01T10:00:00', createdBy: 4,
      ));
      await db.settleTable(5, 20000, 0, 0, 4);

      await db.resetAllData();

      expect(await db.getOrderItems(5), isEmpty);
      expect(await db.getOrderDeliveries(), isEmpty);
      expect(await db.getPendingSyncAll(), isEmpty);
      final tables = await db.getAllTables();
      expect(tables, hasLength(100));
      expect(tables.firstWhere((t) => t.id == 10).createdBy, 2);
      expect(tables.firstWhere((t) => t.id == 60).createdBy, 3);
      expect(tables.firstWhere((t) => t.id == 10).status, TableStatus.empty);
      final w2 = await db.getWaiterTableIds(2);
      expect(w2, containsAll([1, 50]));
      final w3 = await db.getWaiterTableIds(3);
      expect(w3, containsAll([51, 100]));
    });

    test('reset with no range waiters leaves tables unassigned', () async {
      await db.updateUserRange(2, null, null);
      await db.updateUserRange(3, null, null);
      await db.resetAllData();
      final tables = await db.getAllTables();
      expect(tables.every((t) => t.createdBy == 0), isTrue);
      expect(await db.getWaiterTableIds(2), isEmpty);
      expect(await db.getWaiterTableIds(3), isEmpty);
    });
  });

  group('table locks', () {
    test('lock, heartbeat and unlock work on a fresh database', () async {
      await db.lockTable(TableLock(
        tableId: 5, deviceId: 'dev1', userId: 2, userName: 'وەیتەر 1',
        role: 'waiter', lockedAt: DateTime.now(), heartbeat: DateTime.now(),
      ));
      expect(await db.getTableLockById(5), isNotNull);

      await db.updateLockHeartbeat(5, 'dev1');
      final lock = await db.getTableLockById(5);
      expect(lock, isNotNull);
      expect(lock!.deviceId, 'dev1');

      await db.unlockTable(5, 'dev1');
      expect(await db.getTableLockById(5), isNull);
    });

    test('unlock by device releases all locks of that device', () async {
      await db.lockTable(TableLock(
        tableId: 5, deviceId: 'dev1', userId: 2, userName: 'وەیتەر 1',
        role: 'waiter', lockedAt: DateTime.now(), heartbeat: DateTime.now(),
      ));
      await db.lockTable(TableLock(
        tableId: 6, deviceId: 'dev1', userId: 2, userName: 'وەیتەر 1',
        role: 'waiter', lockedAt: DateTime.now(), heartbeat: DateTime.now(),
      ));
      expect(await db.getAllTableLocks(), hasLength(2));
      await db.unlockAllByDevice('dev1');
      expect(await db.getAllTableLocks(), isEmpty);
    });

    test('resetAllData clears table locks', () async {
      await db.lockTable(TableLock(
        tableId: 5, deviceId: 'dev1', userId: 2, userName: 'وەیتەر 1',
        role: 'waiter', lockedAt: DateTime.now(), heartbeat: DateTime.now(),
      ));
      await db.resetAllData();
      expect(await db.getAllTableLocks(), isEmpty);
    });
  });

  group('table notifications', () {
    test('captain notifyTable upserts the cashier notification', () async {
      await db.occupyTable(1, '2', guestCount: 2);
      var notified = 0;
      db.onTableNotification = () => notified++;
      await db.notifyTable(1);
      final notifs = await db.getTableNotifications();
      expect(notifs, hasLength(1));
      expect(notifs.single.tableId, 1);
      expect(notified, greaterThan(0));
      await db.notifyTable(1);
      expect(await db.getTableNotifications(), hasLength(1));
      db.onTableNotification = null;
    });

    test('opening the table clears its notification', () async {
      await db.occupyTable(2, '2', guestCount: 2);
      await db.notifyTable(2);
      expect(await db.getTableNotifications(), hasLength(1));
      await db.clearTableNotifications(2);
      expect(await db.getTableNotifications(), isEmpty);
    });

    test('freeTable removes the notification (table no longer notified)', () async {
      await db.occupyTable(3, '2', guestCount: 2);
      await db.notifyTable(3);
      await db.freeTable(3);
      expect(await db.getTableNotifications(), isEmpty);
    });
  });

  group('snapshot sync', () {
    test('buildSnapshot captures states and applySnapshot restores them on a fresh device db', () async {
      await db.batchSendAndOccupy(
        3,
        [OrderItem(id: 's1', name: 'بیرە', price: 1000, quantity: 1, createdAt: DateTime.now().toIso8601String())],
        waiterId: '101',
      );
      await db.requestBill(3);
      final past = DateTime.now().subtract(const Duration(minutes: 11)).toIso8601String();
      await db.db.update('tables', {'printedAt': past}, where: 'id = ?', whereArgs: [3]);
      await db.checkOverdueTables();
      await db.batchSendAndOccupy(
        5,
        [OrderItem(id: 's2', name: 'کەباب', price: 500, quantity: 2, createdAt: DateTime.now().toIso8601String())],
        waiterId: '101',
      );

      final snap = await db.buildSnapshot();

      final db2 = LocalDatabase();
      await db2.resetForTesting();
      await db2.init(inMemory: true);
      await db2.applySnapshot(snap);

      expect((await db2.getTable(3))!.status, TableStatus.overdue,
          reason: 'مێزی سوور لەسەر ئامێری نوێ هەمان دۆخی پیشان دەدات');
      expect((await db2.getTable(3))!.sentToCashier, isTrue);
      expect((await db2.getTable(5))!.status, TableStatus.occupied,
          reason: 'مێزی سەوز لەسەر ئامێری نوێ سەوز دەمێنێتەوە');
      expect((await db2.getTable(1))!.status, TableStatus.empty);
      expect(await db2.getOrderItems(5), hasLength(1));
      expect((await db2.getTable(5))!.totalAmount, 1000);
    });

    test('applySnapshot keeps local offline items that are not in the snapshot', () async {
      await db.occupyTable(1, '101');
      await db.addOrderItem(
        1,
        OrderItem(id: 'local-1', name: 'شای', price: 250, quantity: 1, createdAt: DateTime.now().toIso8601String()),
      );

      await db.applySnapshot(const {'tables': <Object>[], 'items': <Object, Object>{'1': <Object>[]}});

      expect(await db.getOrderItems(1), hasLength(1), reason: 'خواردنی ئۆفلاین لە ناوخۆیی نامێنێتەوە');
    });
  });

  group('user registry sync (owner opens accounts on the phone)', () {
    test('getAllUsers returns real accounts only (the virtual owner is id 0)', () async {
      // Seed staff are created in setUp; add one more account on top.
      await db.addUser('ئادمێن ب', '98765', UserRole.admin);
      final users = await db.getAllUsers();
      expect(users, isNotEmpty);
      expect(users.every((u) => u.id > 0), isTrue,
          reason: 'خاوەن سیستەم (id 0) هەرگیز لە تابلەی users نابێت');
      expect(users.map((u) => u.name), contains('ئادمێن ب'));
    });

    test('snapshot carries the user registry; applying it converges the device '
        'without deleting local-only accounts', () async {
      // A second, fully isolated database plays the server (the laptop).
      // In-memory databases are shared by sqflite, so use a temp file instead.
      final tmp = await Directory.systemTemp.createTemp('ramyar_pos_server_test');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final serverPath = '${tmp.path}${Platform.pathSeparator}server.db';
      final server = LocalDatabase();
      await server.init(path: serverPath);
      await server.addUser('ئادمێنی سێرڤەر', '44444', UserRole.admin);

      // The phone (this `db`) created an account while it was offline, so the
      // server does not know it yet.
      await db.addUser('ئادمێنی مۆبایل', '55555', UserRole.admin);
      final phoneAdminId = (await db.getAllUsers())
          .firstWhere((u) => u.name == 'ئادمێنی مۆبایل')
          .id;

      final snap = await server.buildSnapshot();
      final snapshotIds = ((snap['users'] as List?) ?? const [])
          .map((e) => (e as Map)['id'] as int)
          .toSet();
      expect(snapshotIds, isNotEmpty, reason: 'سناپشۆت دەبێت ڕیجستەری بەکارهێنەران هەڵگرێت');
      expect(snapshotIds, isNot(contains(phoneAdminId)),
          reason: 'ئادمێنی مۆبایل هێشتا لە سێرڤەردا نییە');

      // The phone applies the server snapshot: gets the server admin, keeps
      // its own offline-created admin (never deleted by a snapshot).
      await db.applySnapshot(snap);
      final localNames = (await db.getAllUsers()).map((u) => u.name).toSet();
      expect(localNames, contains('ئادمێنی سێرڤەر'));
      expect(localNames, contains('ئادمێنی مۆبایل'),
          reason: 'سناپشۆت بەکارهێنەری ناوخۆیی - کە سێرڤەر نایناسی - ناسڕێتەوە');

      // And the reverse direction: every local id the snapshot lacked is what
      // `_uploadMissingUsers` pushes back so the laptop learns the phone admin.
      final localIds = (await db.getAllUsers()).map((u) => u.id).toSet();
      final toUpload = localIds.difference(snapshotIds);
      expect(toUpload, contains(phoneAdminId));
      expect((await db.getUserById(phoneAdminId))!.name, 'ئادمێنی مۆبایل');

      await server.resetForTesting();
    });
  });
}
