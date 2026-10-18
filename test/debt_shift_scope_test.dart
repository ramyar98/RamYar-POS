import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/debt_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';

/// «قەرز» belongs to the shift that rang it up. The shop's rule: once a shift is
/// closed, a new shift - a new cashier or the same one back on - must start with
/// an empty debt list, because the debt was the old shift's business. The record
/// itself is not destroyed; it stays on the admin's «قەرزەکان» page.
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

  Future<int> startShift(int cashierId) => db.startShift(
    CashierShift(
      cashierId: cashierId,
      cashierName: 'کاشێر $cashierId',
      startedAt: DateTime.now().toIso8601String(),
    ),
  );

  DebtModel debt({int shiftId = 0, int table = 1, double amount = 10000}) =>
      DebtModel(
        id: 0,
        tableId: table,
        tableName: 'مێز $table',
        amount: amount,
        reason: 'قەرز',
        createdAt: DateTime.now().toIso8601String(),
        createdBy: 5,
        shiftId: shiftId,
      );

  group('a debt is scoped to its shift', () {
    test('a debt opened under a shift shows for that shift only', () async {
      final shiftA = await startShift(5);
      await db.addDebt(debt(shiftId: shiftA));

      expect(await db.getDebtsByShift(shiftA), hasLength(1),
          reason: 'the shift that opened it still sees its debt');

      final shiftB = await startShift(5);
      expect(await db.getDebtsByShift(shiftB), isEmpty,
          reason: 'a new shift starts with an empty debt list');
    });

    test('closing a shift still leaves its debt off the till', () async {
      final shiftA = await startShift(5);
      await db.addDebt(debt(shiftId: shiftA));
      await db.endShift(shiftA, DateTime.now().toIso8601String(), 0);

      final shiftB = await startShift(5);
      expect(await db.getDebtsByShift(shiftB), isEmpty,
          reason: 'the closed shift did not hand its debt to the next one');
    });

    test('the admin view (getDebts) still holds every debt', () async {
      final shiftA = await startShift(5);
      await db.addDebt(debt(shiftId: shiftA));
      await db.addDebt(debt(shiftId: 0, table: 2));

      expect(await db.getDebts(), hasLength(2),
          reason: 'the record survives even after the till stops showing it');
    });

    test('the shift id survives the store and a reload', () async {
      final shiftA = await startShift(5);
      await db.addDebt(debt(shiftId: shiftA));
      final stored = (await db.getDebtsByShift(shiftA)).single;
      expect(stored.shiftId, shiftA);
    });
  });

  group('migration from the previous schema', () {
    test('v39 opens with the shiftId column, old debts belong to no shift',
        () async {
      final dir = Directory.systemTemp.createTempSync('ramyar_pos_v40');
      final path = '${dir.path}${Platform.pathSeparator}old.db';

      // A database still on v39: `debts` has no `shiftId`.
      final raw = await databaseFactory.openDatabase(path);
      await raw.execute(
        'CREATE TABLE tables (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
        'status INTEGER NOT NULL DEFAULT 0, seatedTime TEXT DEFAULT "", '
        'waiterId TEXT DEFAULT "", totalAmount REAL DEFAULT 0.0, '
        'guestCount INTEGER DEFAULT 0, sentToCashier INTEGER DEFAULT 0, '
        'printedAt TEXT DEFAULT "", note TEXT DEFAULT "", '
        'createdBy INTEGER DEFAULT 0, openedBy INTEGER DEFAULT 0)',
      );
      await raw.execute(
        'CREATE TABLE debts (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'tableId INTEGER NOT NULL, tableName TEXT NOT NULL, '
        'amount REAL NOT NULL, reason TEXT DEFAULT "", '
        'createdAt TEXT NOT NULL, createdBy INTEGER NOT NULL)',
      );
      await raw.execute(
        "INSERT INTO debts (tableId, tableName, amount, reason, createdAt, createdBy) "
        "VALUES (1, 'مێز 1', 10000, 'قەرز', '2026-01-01T10:00:00', 5)",
      );
      // init() builds its sync indexes on open; those touch order_items and
      // pending_sync directly, so the fixture has to carry both.
      await raw.execute(
        'CREATE TABLE order_items (id TEXT NOT NULL, tableId INTEGER NOT NULL, '
        'name TEXT NOT NULL, price REAL NOT NULL, '
        'quantity INTEGER NOT NULL DEFAULT 1, category TEXT DEFAULT "", '
        'createdAt TEXT NOT NULL, waiterName TEXT DEFAULT "", '
        'PRIMARY KEY (id, tableId))',
      );
      await raw.execute(
        'CREATE TABLE pending_sync (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'action TEXT NOT NULL, data TEXT NOT NULL, createdAt TEXT NOT NULL, '
        'status INTEGER DEFAULT 0, batchId TEXT, retryCount INTEGER DEFAULT 0, '
        'lastError TEXT DEFAULT "")',
      );
      await raw.execute('PRAGMA user_version = 39');
      await raw.close();

      final migrated = LocalDatabase();
      await migrated.init(path: path);
      try {
        final columns =
            (await migrated.db.rawQuery('PRAGMA table_info(debts)'))
                .map((r) => r['name'])
                .toSet();
        expect(columns, contains('shiftId'));

        // The debt written before the column existed belongs to no shift, so a
        // cashier whose shift has a real id does not see it.
        expect(await migrated.getDebtsByShift(7), isEmpty);
        final all = await migrated.getDebts();
        expect(all.single.shiftId, 0,
            reason: 'an old debt carries the "no shift" default');
      } finally {
        await migrated.resetForTesting();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
