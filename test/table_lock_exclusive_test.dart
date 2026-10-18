import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_lock_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/services/table_lock_controller.dart';

/// One captain to a table, and the cashier's right to take a table off him.
///
/// The rule these tests defend is the one the shop actually runs on: a table has
/// one captain at a time, everybody else is told whose table it is and stays
/// out, and when the cashier needs the table the captain is removed without the
/// order being touched. The old code looked like it did this and did not - the
/// lock expired on a timer nobody refreshed, so a captain holding a table lost it
/// after seconds and the next one walked in.
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

  TableLock captainLock(int tableId, {int userId = 2, String name = 'کاپتن 1'}) =>
      TableLock(
        tableId: tableId,
        deviceId: 'dev-$userId',
        userId: userId,
        userName: name,
        role: 'waiter',
        lockedAt: DateTime.now(),
        heartbeat: DateTime.now(),
      );

  group('the lock outlives the page that took it', () {
    test('a held lock is still held well past the old 15 second cutoff', () async {
      await db.lockTable(captainLock(5));
      // What the old timer did: pretend 20 seconds went by with no heartbeat.
      await db.db.update(
        'table_locks',
        {'heartbeat': DateTime.now().subtract(const Duration(seconds: 20)).toIso8601String()},
        where: 'tableId = ?',
        whereArgs: [5],
      );
      expect(await db.getTableLockById(5), isNotNull,
          reason: 'a captain working a table must not be treated as gone');
    });

    test('the holder is told the moment somebody else takes the table', () async {
      // The lock being replaced is the other half of the eject: a cashier
      // taking the table over shows up on the captain's device as a new owner,
      // and the captain has to be pulled off it.
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      TableLockLoss? reason;
      final page = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (r) => reason = r,
      );
      await page.acquire();

      // Someone else overwrites the row, exactly as a taking-over device does.
      await db.lockTable(TableLock(
        tableId: 5,
        deviceId: 'cashier-device',
        userId: 9,
        userName: 'کاشێر',
        role: 'cashier',
      ));
      final lock = await db.getTableLockById(5);
      expect(lock!.userId, 9);

      // The page notices on its next check and stands down.
      await page.acquire();
      await Future<void>.delayed(Duration.zero);
      expect(reason, isNotNull,
          reason: 'a captain must not keep serving a table somebody else took');
      await page.release();
    });

    test('a lock is only released once it is genuinely past its timeout', () async {
      await db.lockTable(captainLock(5));
      await db.db.update(
        'table_locks',
        {'heartbeat': DateTime.now().subtract(kTableLockTimeout + const Duration(seconds: 5)).toIso8601String()},
        where: 'tableId = ?',
        whereArgs: [5],
      );
      expect(await db.getTableLockById(5), isNull,
          reason: 'a device that died must not lock the table out forever');
    });

    test('a heartbeat keeps a lock alive indefinitely', () async {
      await db.lockTable(captainLock(5));
      for (var i = 0; i < 5; i++) {
        await db.db.update(
          'table_locks',
          {'heartbeat': DateTime.now().subtract(Duration(seconds: i * 20)).toIso8601String()},
          where: 'tableId = ?',
          whereArgs: [5],
        );
        await db.updateLockHeartbeat(5, 'dev-2');
        expect(await db.getTableLockById(5), isNotNull);
      }
    });
  });

  group('one captain to a table', () {
    test('a captain waiting on an empty table is refused just as firmly', () async {
      // The gap that let two captains share a table: the check used to run only
      // for tables that already had guests, so the empty ones - the majority on
      // a fresh floor - were a way straight past it.
      await db.lockTable(captainLock(9, userId: 2, name: 'کاپتن 1'));
      expect((await db.getTable(9))!.status, TableStatus.empty,
          reason: 'precondition: the table is free of guests');

      final other = TableLockController(
        db: db,
        tableId: 9,
        userId: 3,
        userName: 'کاپتن 2',
        role: 'waiter',
        onLost: (_) {},
      );
      expect(await other.acquire(), isFalse,
          reason: 'a free table is not a table without an owner');
      await other.release();
    });

    test('a second captain is refused the table', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      final other = TableLockController(
        db: db,
        tableId: 5,
        userId: 3,
        userName: 'کاپتن 2',
        role: 'waiter',
        onLost: (_) {},
      );
      expect(await other.acquire(), isFalse,
          reason: 'کاپتن 2 must not be able to sit at a table کاپتن 1 is on');
      final lock = await db.getTableLockById(5);
      expect(lock!.userId, 2, reason: 'the refusal must not disturb کاپتن 1');
      expect(lock.userName, 'کاپتن 1');
      await other.release();
    });

    test('a refused captain is told, and the holder is not', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      TableLockLoss? reason;
      final other = TableLockController(
        db: db,
        tableId: 5,
        userId: 3,
        userName: 'کاپتن 2',
        role: 'waiter',
        onLost: (r) => reason = r,
      );
      await other.acquire();
      other.loseImmediately(TableLockLoss.heldByAnotherUser);
      expect(reason, TableLockLoss.heldByAnotherUser);
      await other.release();
    });

    test('the same captain may re-enter their own table', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      final mine = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (_) {},
      );
      expect(await mine.acquire(), isTrue,
          reason: 'coming back to your own table is not a collision');
      await mine.release();
    });

    test('a free table is open to anyone', () async {
      final c = TableLockController(
        db: db,
        tableId: 7,
        userId: 3,
        userName: 'کاپتن 2',
        role: 'waiter',
        onLost: (_) {},
      );
      expect(await c.acquire(), isTrue);
      expect((await db.getTableLockById(7))!.userId, 3);
      await c.release();
    });

    test('a cashier is never locked out of a table', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      final cashier = TableLockController(
        db: db,
        tableId: 5,
        userId: 9,
        userName: 'کاشێر',
        role: 'cashier',
        onLost: (_) {},
      );
      expect(await cashier.acquire(force: true), isTrue);
      expect((await db.getTableLockById(5))!.role, 'cashier');
      await cashier.release();
    });
  });

  group('the cashier takes the table off the captain', () {
    test('ejecting drops the claim and clears the serving captain', () async {
      await db.occupyTable(5, '2', guestCount: 3);
      expect((await db.getTable(5))!.waiterId, '2');
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));

      await db.ejectCaptainFromTable(5);

      expect(await db.getTableLockById(5), isNull, reason: 'the claim is gone');
      expect((await db.getTable(5))!.waiterId, isEmpty, reason: 'no captain is serving it');
    });

    test('ejecting keeps the whole order so the cashier can settle it', () async {
      await db.batchSendAndOccupy(5, [
        OrderItem(
            id: 'a', name: 'خواردن', price: 3000, quantity: 1, createdAt: DateTime.now().toIso8601String()),
        OrderItem(
            id: 'b', name: 'خواردن', price: 2000, quantity: 1, createdAt: DateTime.now().toIso8601String()),
      ], waiterId: '2');
      final before = await db.getTable(5);
      expect(before!.totalAmount, 5000);

      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      await db.ejectCaptainFromTable(5);

      final after = await db.getTable(5);
      expect(after!.totalAmount, 5000, reason: 'the bill must survive the eject');
      expect(after.status, before.status, reason: 'the table is still occupied');
      expect(after.guestCount, before.guestCount);
      expect(await db.getOrderItems(5), hasLength(2), reason: 'no item is lost');
    });

    test('ejecting tells the device showing that table', () async {
      final seen = <int>[];
      final sub = db.tableEjections.listen(seen.add);
      await db.ejectCaptainFromTable(5);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [5]);
    });

    test('ejecting a free table is harmless', () async {
      await db.ejectCaptainFromTable(5);
      expect(await db.getTableLockById(5), isNull);
      expect((await db.getTable(5))!.waiterId, isEmpty);
    });

    test('a captain may take the table once the previous one is off it', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      await db.ejectCaptainFromTable(5);

      final next = TableLockController(
        db: db,
        tableId: 5,
        userId: 3,
        userName: 'کاپتن 2',
        role: 'waiter',
        onLost: (_) {},
      );
      expect(await next.acquire(), isTrue);
      expect((await db.getTableLockById(5))!.userId, 3);
      await next.release();
    });
  });

  group('a claim is never left behind', () {
    test('a page closed before its write lands leaves no lock', () async {
      // Opening a table and backing straight out is ordinary use, and it can
      // happen before the write reaches the database. The row that survived
      // that looked to every other captain exactly like a table somebody was
      // working, so the floor lost the table for as long as the row lasted.
      final page = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (_) {},
      );
      final opening = page.acquire();
      await page.release();
      expect(await opening, isFalse, reason: 'the page was gone before it opened');
      expect(await db.getTableLockById(5), isNull,
          reason: 'a table nobody is working must not stay shut');
    });

    test('a closed page frees the table for the next captain', () async {
      final first = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (_) {},
      );
      final opening = first.acquire();
      await first.release();
      await opening;

      final next = TableLockController(
        db: db,
        tableId: 5,
        userId: 3,
        userName: 'کاپتن 2',
        role: 'waiter',
        onLost: (_) {},
      );
      expect(await next.acquire(), isTrue,
          reason: 'the table is free the moment the first page closed');
      await next.release();
    });

    test('a released claim stays released even if a beat was in flight', () async {
      final page = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (_) {},
      );
      expect(await page.acquire(), isTrue);
      await page.release();
      // Let anything the controller had queued finish.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await db.getTableLockById(5), isNull,
          reason: 'a heartbeat must not resurrect a claim that was given up');
    });
  });

  group('a captain learns the moment the table is taken off them', () {
    test('the page is told when its table is ejected', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      TableLockLoss? reason;
      final page = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (r) => reason = r,
      );
      await page.acquire();
      expect(reason, isNull, reason: 'nothing has happened yet');

      await db.ejectCaptainFromTable(5);
      await Future<void>.delayed(Duration.zero);

      expect(reason, TableLockLoss.takenAway,
          reason: 'the captain must not be left standing at a table that is not his');
      await page.release();
    });

    test('ejecting another table does not disturb this one', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      TableLockLoss? reason;
      final page = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (r) => reason = r,
      );
      await page.acquire();

      await db.ejectCaptainFromTable(9);
      await Future<void>.delayed(Duration.zero);

      expect(reason, isNull);
      expect(await db.getTableLockById(5), isNotNull);
      await page.release();
    });

    test('a released lock notifies only once, not on every check', () async {
      await db.lockTable(captainLock(5, userId: 2, name: 'کاپتن 1'));
      var calls = 0;
      final page = TableLockController(
        db: db,
        tableId: 5,
        userId: 2,
        userName: 'کاپتن 1',
        role: 'waiter',
        onLost: (_) => calls++,
      );
      await page.acquire();
      await db.ejectCaptainFromTable(5);
      await Future<void>.delayed(Duration.zero);
      await db.ejectCaptainFromTable(5);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: 'one message per captain, not one per event');
      await page.release();
    });
  });
}
