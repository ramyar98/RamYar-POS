// Covers the P0/P1 production-hardening guarantees:
//  * durable schema v34 (a print ledger + the indexes the sync paths need);
//  * at-most-once kitchen printing through a (batch, printer) ledger;
//  * atomic order totals and idempotent item inserts;
//  * an ordered, per-table pending flush.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for condition');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  group('schema v34', () {
    test('a fresh database carries the print ledger and sync indexes', () async {
      final tables = await db.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='print_jobs'");
      expect(tables, isNotEmpty, reason: 'print_jobs must exist');

      final indexes = (await db.db
              .rawQuery("SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => r['name'])
          .toSet();
      expect(indexes, contains('idx_pending_status'));
      expect(indexes, contains('idx_items_table'));
      expect(indexes, contains('idx_pending_batch'));
      // Warm-path indexes: the floor poll every screen runs once a second, and
      // the per-shift/report reads that grow with the shop's history.
      expect(indexes, contains('idx_tables_status'));
      expect(indexes, contains('idx_settled_shift'));
      expect(indexes, contains('idx_settled_items_order'));
      expect(indexes, contains('idx_cancelled_shift'));

      final pendingColumns =
          (await db.db.rawQuery('PRAGMA table_info(pending_sync)'))
              .map((r) => r['name'])
              .toSet();
      expect(pendingColumns,
          containsAll(<String>['batchId', 'retryCount', 'lastError']));
    });

    test('opening a v33 database migrates it to v34', () async {
      final dir = Directory.systemTemp.createTempSync('ramyar_pos_v34');
      final path = '${dir.path}${Platform.pathSeparator}old.db';

      // A database still on v33: no print_jobs table, no batchId column.
      final raw = await databaseFactory.openDatabase(path);
      await raw.execute(
          'CREATE TABLE tables (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
          'status INTEGER NOT NULL DEFAULT 0, seatedTime TEXT DEFAULT "", '
          'waiterId TEXT DEFAULT "", totalAmount REAL DEFAULT 0.0, '
          'guestCount INTEGER DEFAULT 0, sentToCashier INTEGER DEFAULT 0, '
          'printedAt TEXT DEFAULT "", note TEXT DEFAULT "", createdBy INTEGER DEFAULT 0)');
      await raw.execute(
          'CREATE TABLE order_items (id TEXT NOT NULL, tableId INTEGER NOT NULL, '
          'name TEXT NOT NULL, price REAL NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, '
          'category TEXT DEFAULT "", createdAt TEXT NOT NULL, waiterName TEXT DEFAULT "", '
          'PRIMARY KEY (id, tableId))');
      await raw.execute(
          'CREATE TABLE pending_sync (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'action TEXT NOT NULL, data TEXT NOT NULL, createdAt TEXT NOT NULL, status INTEGER DEFAULT 0)');
      await raw.execute('PRAGMA user_version = 33');
      await raw.close();

      final migrated = LocalDatabase();
      await migrated.init(path: path);
      try {
        final jobs = await migrated.db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='print_jobs'");
        expect(jobs, isNotEmpty, reason: 'v34 migration must add print_jobs');

        final columns =
            (await migrated.db.rawQuery('PRAGMA table_info(pending_sync)'))
                .map((r) => r['name'])
                .toSet();
        expect(columns,
            containsAll(<String>['batchId', 'retryCount', 'lastError']));
      } finally {
        await migrated.resetForTesting();
      }
    });
  });

  group('print ledger is at-most-once', () {
    test('the first claim prints, a concurrent or later claim does not',
        () async {
      expect(
        await db.claimPrintJob(
            batchId: 'b1', printerType: 0, tableId: 3, payload: '{}'),
        isTrue,
      );
      expect(
        await db.claimPrintJob(
            batchId: 'b1', printerType: 0, tableId: 3, payload: '{}'),
        isFalse,
        reason: 'a second claim while the first is printing must not print again',
      );
      await db.completePrintJob('b1', 0, success: true);
      expect(
        await db.claimPrintJob(
            batchId: 'b1', printerType: 0, tableId: 3, payload: '{}'),
        isFalse,
        reason: 'a printed ticket is never printed again',
      );
    });

    test('a failed ticket can be retried; a printed one cannot', () async {
      expect(
        await db.claimPrintJob(
            batchId: 'b2', printerType: 1, tableId: 4, payload: '{}'),
        isTrue,
      );
      await db.completePrintJob('b2', 1, success: false, error: 'printer offline');
      expect((await db.getPendingPrintJobs()).map((r) => r['batchId']),
          contains('b2'));

      expect(
        await db.claimPrintJob(
            batchId: 'b2', printerType: 1, tableId: 4, payload: '{}'),
        isTrue,
      );
      await db.completePrintJob('b2', 1, success: true);
      expect(await db.getPendingPrintJobs(), isEmpty);
    });

    test('each printer type of a batch is its own ticket', () async {
      expect(
        await db.claimPrintJob(
            batchId: 'b3', printerType: 0, tableId: 5, payload: '{}'),
        isTrue,
      );
      expect(
        await db.claimPrintJob(
            batchId: 'b3', printerType: 1, tableId: 5, payload: '{}'),
        isTrue,
      );
    });

    test('a ticket the printer will never take stops asking', () async {
      // A printer that is switched off for the evening, or a station with no
      // printer configured at all, fails the same way every single time. The
      // retry timer runs every 30 seconds for as long as the shop is open, so
      // an uncapped retry is a dispatch and a wire message every half minute
      // until closing, for a job that has already proven it cannot be done.
      const cap = LocalDatabase.printJobMaxAttempts;
      for (var attempt = 1; attempt <= cap; attempt++) {
        expect(
          await db.claimPrintJob(
              batchId: 'stuck', printerType: 0, tableId: 7, payload: '{}'),
          isTrue,
          reason: 'attempt $attempt must still be allowed to try',
        );
        await db.completePrintJob('stuck', 0,
            success: false, error: 'no printer configured for type kitchen');
      }

      expect(await db.getPendingPrintJobs(), isEmpty,
          reason: 'the automatic loop must stop here, not keep trying forever');
      final stalled = await db.stalledPrintJobs();
      expect(stalled.map((r) => r['batchId']), contains('stuck'),
          reason: 'but the ticket and its reason stay in the ledger - the '
              'machine must not quietly forget it');
      expect((stalled.first['attempts'] as int), cap);
      expect(stalled.first['lastError'], contains('no printer configured'));

      // The record is kept exactly as it was: giving up is not a state the
      // data loses, so an operator can still see and settle it.
      final row = await db.db.query('print_jobs',
          where: 'batchId = ?', whereArgs: ['stuck']);
      expect(row.single['status'], LocalDatabase.printJobFailed);
    });

    test('a ticket that recovers is not punished for the earlier failures',
        () async {
      for (var attempt = 1;
          attempt < LocalDatabase.printJobMaxAttempts;
          attempt++) {
        await db.claimPrintJob(
            batchId: 'flaky', printerType: 0, tableId: 8, payload: '{}');
        await db.completePrintJob('flaky', 0, success: false, error: 'offline');
      }
      expect((await db.getPendingPrintJobs()).map((r) => r['batchId']),
          contains('flaky'),
          reason: 'still inside the allowance, so it keeps its chance');
      expect(await db.claimPrintJob(
          batchId: 'flaky', printerType: 0, tableId: 8, payload: '{}'), isTrue);
      await db.completePrintJob('flaky', 0, success: true);
      expect(await db.getPendingPrintJobs(), isEmpty);
      expect(await db.stalledPrintJobs(), isEmpty);
    });
  });

  group('atomic totals and idempotent items', () {
    test('batchSendAndOccupy writes the total with its items', () async {
      await db.batchSendAndOccupy(1, [
        OrderItem(id: 'i1', name: 'Tea', price: 2.5, quantity: 2),
        OrderItem(id: 'i2', name: 'Rice', price: 10, quantity: 1),
      ]);
      expect((await db.getTable(1))!.totalAmount, 15.0);
      expect(await db.getOrderItems(1), hasLength(2));
    });

    test('the same item id twice is stored once and counted once', () async {
      final items = [OrderItem(id: 'dup', name: 'Tea', price: 2.5, quantity: 2)];
      await db.batchSendAndOccupy(1, items);
      await db.batchSendAndOccupy(1, items); // an exact resend
      expect(await db.getOrderItems(1), hasLength(1));
      expect((await db.getTable(1))!.totalAmount, 5.0);
    });

    test('changing and removing items keeps the total in step', () async {
      await db.batchSendAndOccupy(1, [
        OrderItem(id: 'a', name: 'A', price: 3, quantity: 1),
        OrderItem(id: 'b', name: 'B', price: 4, quantity: 1),
      ]);
      await db.updateOrderItemQuantity(1, 'a', 4);
      expect((await db.getTable(1))!.totalAmount, 16.0);
      await db.removeOrderItem(1, 'b');
      expect((await db.getTable(1))!.totalAmount, 12.0);
    });
  });

  group('pending queue', () {
    test('batchSendAndOccupyPending mints a stable batchId', () async {
      // No onMutation handler: this is the pure-offline path.
      await db.batchSendAndOccupyPending(7, [
        OrderItem(id: 'p1', name: 'Kebab', price: 9, quantity: 1),
      ]);
      final pending = await db.getPendingSyncAll();
      expect(pending, hasLength(1));
      final data = pending.single['data'] as Map<String, dynamic>;
      final batchId = data['batchId'];
      expect(batchId, isA<String>());
      expect((batchId as String).isNotEmpty, isTrue);

      // Stored in its own column too, so the unique backstop index sees it.
      final rows = await db.db.query('pending_sync', columns: ['batchId']);
      expect(rows.single['batchId'], batchId);
    });

    test('recordPendingFailure keeps the row queued and records the error',
        () async {
      await db.batchSendAndOccupyPending(7, [
        OrderItem(id: 'p2', name: 'Kebab', price: 9, quantity: 1),
      ]);
      final localId = (await db.getPendingSyncAll()).single['localId'] as int;
      await db.recordPendingFailure(localId, 'hub rejected');
      final row = (await db.db
              .query('pending_sync', where: 'id = ?', whereArgs: [localId]))
          .single;
      expect(row['status'], 0,
          reason: 'a rejected order must stay queued for a retry');
      expect(row['retryCount'], 1);
      expect(row['lastError'], 'hub rejected');
    });
  });

  group('ordered per-table flush', () {
    test("one table's queued changes are applied oldest-first", () async {
      final dir = Directory.systemTemp.createTempSync('ramyar_pos_ordered');
      final serverDb = LocalDatabase();
      await serverDb.init(path: '${dir.path}${Platform.pathSeparator}server.db');
      final clientDb = LocalDatabase();
      await clientDb.init(path: '${dir.path}${Platform.pathSeparator}client.db');

      final item = OrderItem(id: 'ord-1', name: 'Kebab', price: 9, quantity: 1);
      // The server already holds table 3 seated with the item.
      await serverDb.batchSendAndOccupy(3, [item]);

      // On the client, the freeTable has a LATER timestamp but is inserted
      // FIRST, so raw row order is the wrong way round. Only the createdAt
      // ordering can save the item.
      await clientDb.db.insert('pending_sync', {
        'action': 'freeTable',
        'data': jsonEncode({'tableId': 3}),
        'createdAt': '2020-01-02T00:00:00.000',
        'status': 0,
      });
      await clientDb.db.insert('pending_sync', {
        'action': 'addOrderItem',
        'data': jsonEncode({'tableId': 3, 'item': item.toMap()}),
        'createdAt': '2020-01-01T00:00:00.000',
        'status': 0,
      });

      final serverState = SyncStateNotifier();
      final ip = await startSyncServer(serverDb, 4, 'cashier', serverState,
          port: 9895);
      expect(ip, isNotNull);
      final clientState = SyncStateNotifier();
      final ok =
          await connectToServer(clientDb, ip!, 2, 'waiter', clientState, port: 9895);
      expect(ok, isTrue);

      await waitUntil(() async => (await clientDb.getPendingSyncAll()).isEmpty);

      // addOrderItem (oldest) landed before freeTable, so the table is freed and
      // empty. The wrong order would leave the item behind.
      expect(await serverDb.getOrderItems(3), isEmpty);
      expect((await serverDb.getTable(3))!.status, TableStatus.empty);

      disconnectSync(clientDb);
      disconnectSync(serverDb);
      await serverDb.resetForTesting();
      await clientDb.resetForTesting();
    });
  });
}
