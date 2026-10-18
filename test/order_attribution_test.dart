import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/services/app_localizations.dart';

/// Guards the two facts the shop asked for on the floor:
///
///  * every order line remembers whether the CAPTAIN or the CASHIER rang it in,
///    so a dish the till added is never read as the captain's; and
///  * every table remembers the person who FIRST seated it - distinct from
///    `createdBy`, which is the captain whose مەودا owns the row.
void main() {
  setUpAll(() {
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

  OrderItem line(
    String id, {
    int role = OrderItem.unknownRole,
    String waiter = '',
  }) => OrderItem(
    id: id,
    name: 'کەباب',
    price: 1000,
    quantity: 1,
    category: 'خواردن',
    createdAt: '2026-01-01T10:00:00',
    waiterName: waiter,
    waiterRole: role,
  );

  group('who added each order line', () {
    test('the adder\'s role survives the store and a reload', () async {
      await db.batchSendAndOccupy(
        1,
        [line('a', role: 1, waiter: 'کاشێر 1')],
        waiterId: '4',
      );
      final stored = (await db.getOrderItems(1)).single;
      expect(stored.waiterRole, 1, reason: 'cashier role must persist');
      expect(stored.waiterName, 'کاشێر 1');
    });

    test('captain and cashier lines keep separate roles', () async {
      await db.batchSendAndOccupy(
        1,
        [line('a', role: 0, waiter: 'کاپتن 1')],
        waiterId: '2',
      );
      await db.batchSendAndOccupy(
        1,
        [line('b', role: 1, waiter: 'کاشێر 1')],
        waiterId: '4',
      );
      final byId = {
        for (final i in await db.getOrderItems(1)) i.id: i.waiterRole,
      };
      expect(byId['a'], 0);
      expect(byId['b'], 1);
    });

    test('a line with no recorded role reads as unknown, never captain', () {
      // What a row written before the column existed reads back as.
      final row = {
        'id': 'old',
        'name': 'چا',
        'price': 500.0,
        'quantity': 1,
        'category': '',
        'createdAt': '2026-01-01T09:00:00',
        'waiterName': 'کاشێر کۆن',
      };
      expect(OrderItem.fromMap(row).waiterRole, OrderItem.unknownRole);
      expect(OrderItem.unknownRole, -1);
    });
  });

  group('who first opened the table', () {
    test('the first send records its sender as the opener', () async {
      await db.batchSendAndOccupy(1, [line('a')], waiterId: '2');
      expect((await db.getTable(1))!.openedBy, 2);
    });

    test('a later send does not steal the opener', () async {
      await db.batchSendAndOccupy(1, [line('a')], waiterId: '2');
      await db.batchSendAndOccupy(1, [line('b')], waiterId: '4');
      expect((await db.getTable(1))!.openedBy, 2);
    });

    test('seating first, then sending, keeps the seater', () async {
      await db.occupyTable(1, '4', guestCount: 2);
      await db.batchSendAndOccupy(1, [line('a')], waiterId: '2');
      expect((await db.getTable(1))!.openedBy, 4);
    });

    test('freeing the table clears the opener for the next sitting', () async {
      await db.batchSendAndOccupy(1, [line('a')], waiterId: '2');
      await db.freeTable(1);
      expect((await db.getTable(1))!.openedBy, 0);
    });
  });

  group('migration from the previous schema', () {
    test('v38 opens with the role and opener columns, old rows unknown', () async {
      final dir = Directory.systemTemp.createTempSync('ramyar_pos_v39');
      final path = '${dir.path}${Platform.pathSeparator}old.db';

      // A database still on v38: neither new column exists.
      final raw = await databaseFactory.openDatabase(path);
      await raw.execute(
        'CREATE TABLE tables (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
        'status INTEGER NOT NULL DEFAULT 0, seatedTime TEXT DEFAULT "", '
        'waiterId TEXT DEFAULT "", totalAmount REAL DEFAULT 0.0, '
        'guestCount INTEGER DEFAULT 0, sentToCashier INTEGER DEFAULT 0, '
        'printedAt TEXT DEFAULT "", note TEXT DEFAULT "", '
        'createdBy INTEGER DEFAULT 0)',
      );
      await raw.execute(
        'CREATE TABLE order_items (id TEXT NOT NULL, tableId INTEGER NOT NULL, '
        'name TEXT NOT NULL, price REAL NOT NULL, '
        'quantity INTEGER NOT NULL DEFAULT 1, category TEXT DEFAULT "", '
        'createdAt TEXT NOT NULL, waiterName TEXT DEFAULT "", '
        'PRIMARY KEY (id, tableId))',
      );
      await raw.execute(
        "INSERT INTO order_items VALUES "
        "('old', 1, 'چا', 500, 1, '', '2026-01-01T09:00:00', 'کاشێر کۆن')",
      );
      // init() builds its sync indexes on open; those index statements touch
      // pending_sync directly, so the fixture has to carry it.
      await raw.execute(
        'CREATE TABLE pending_sync (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'action TEXT NOT NULL, data TEXT NOT NULL, createdAt TEXT NOT NULL, '
        'status INTEGER DEFAULT 0, batchId TEXT, retryCount INTEGER DEFAULT 0, '
        'lastError TEXT DEFAULT "")',
      );
      await raw.execute('PRAGMA user_version = 38');
      await raw.close();

      final migrated = LocalDatabase();
      await migrated.init(path: path);
      try {
        final itemColumns =
            (await migrated.db.rawQuery('PRAGMA table_info(order_items)'))
                .map((r) => r['name'])
                .toSet();
        expect(itemColumns, contains('waiterRole'));

        final tableColumns =
            (await migrated.db.rawQuery('PRAGMA table_info(tables)'))
                .map((r) => r['name'])
                .toSet();
        expect(tableColumns, contains('openedBy'));

        // The dish written before the column existed is unknown, not captain.
        final old = (await migrated.getOrderItems(1)).single;
        expect(old.waiterName, 'کاشێر کۆن');
        expect(old.waiterRole, OrderItem.unknownRole);
      } finally {
        await migrated.resetForTesting();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('the label a dish carries on screen', () {
    testWidgets('is prefixed with the role, and bare when unknown', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(staffLabel(ctx, 0, 'ئاراس'), 'کاپتن ئاراس');
      expect(staffLabel(ctx, 1, 'شیلان'), 'کاشێر شیلان');
      expect(staffLabel(ctx, OrderItem.unknownRole, 'نەناسراو'), 'نەناسراو');
      expect(staffLabel(ctx, 0, ''), '');
    });
  });
}
