import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/remaining_table_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/models/table_model.dart';

/// When a cashier locks up while tables are still sitting with an open bill, the
/// shift report keeps an informational snapshot of those tables. It answers the
/// admin's question - *which tables were left un-settled?* - and never touches
/// the tables or the shift's money.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('ramyar_pos_remaining');
    db = LocalDatabase();
    await db.resetForTesting();
    // A per-test temp FILE keeps each device in this suite on its own store.
    await db.init(path: '${tmp.path}${Platform.pathSeparator}device.db');
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    await db.resetForTesting();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<LocalDatabase> newDevice(String name) async {
    final device = LocalDatabase();
    await device.resetForTesting();
    await device.init(
      path: '${tmp.path}${Platform.pathSeparator}$name.db',
    );
    await device.seedDefaultStaff();
    return device;
  }

  Future<int> startShift(int cashierId) => db.startShift(
    CashierShift(
      cashierId: cashierId,
      cashierName: 'کاشێر $cashierId',
      startedAt: DateTime.now().toIso8601String(),
    ),
  );

  Future<void> seatTable(int tableId, {int guestCount = 2}) async {
    await db.batchSendAndOccupy(
      tableId,
      [
        OrderItem(
          id: 'i$tableId',
          name: 'کەباب',
          price: 10000,
          quantity: 2,
          category: 'کەباب',
          waiterName: 'وەیتەر 1',
          waiterRole: 0,
        ),
      ],
      guestCount: guestCount,
      waiterId: '2',
    );
  }

  test('closing a shift records the tables still seated', () async {
    final shiftId = await startShift(4);
    await seatTable(1, guestCount: 3);
    await seatTable(2, guestCount: 5);
    await db.updateTableNote(1, 'کاپتن: بێ شەکر');

    await db.endShift(shiftId, DateTime.now().toIso8601String(), 0);

    final remaining = await db.getRemainingTablesByShift(shiftId);
    expect(remaining, hasLength(2));
    expect(remaining.map((t) => t.tableName), containsAll(['مێز 1', 'مێز 2']));

    final t1 = remaining.firstWhere((t) => t.tableId == 1);
    expect(t1.guestCount, 3);
    expect(t1.totalAmount, 20000);
    expect(t1.waiterName, 'وەیتەر 1');
    expect(t1.note, contains('بێ شەکر'));
    final items = decodeRemainingTableItems(t1.itemsJson);
    expect(items, hasLength(1));
    expect(items.single.name, 'کەباب');
    expect(items.single.subtotal, 20000);
  });

  test('an empty floor records nothing', () async {
    final shiftId = await startShift(4);
    await db.endShift(shiftId, DateTime.now().toIso8601String(), 0);
    expect(await db.getRemainingTablesByShift(shiftId), isEmpty);
  });

  test('closing twice never duplicates the snapshot', () async {
    final shiftId = await startShift(4);
    await seatTable(1);
    await db.endShift(shiftId, DateTime.now().toIso8601String(), 0);
    await db.endShift(shiftId, DateTime.now().toIso8601String(), 0);
    expect(await db.getRemainingTablesByShift(shiftId), hasLength(1));
  });

  test('the snapshot carries the shift key for another device', () async {
    final emitted = <String, Map<String, dynamic>>{};
    db.onMutation = (action, data) => emitted[action] = data;

    const startedAt = '2026-10-17T10:00:00.000';
    final shiftId = await db.startShift(
      const CashierShift(
        cashierId: 4,
        cashierName: 'کاشێر 1',
        startedAt: startedAt,
      ),
    );
    await seatTable(1);
    await db.endShift(shiftId, '2026-10-17T14:00:00.000', 0);

    final mutation = emitted['SHIFT_REMAINING_TABLES'];
    expect(mutation, isNotNull);
    expect(mutation!['shiftKey'], {'cashierId': 4, 'startedAt': startedAt});

    // A second device hears the shift, then the snapshot, and links them.
    final other = await newDevice('other');
    try {
      await other.applyRemoteShift({
        'cashierId': 4,
        'cashierName': 'کاشێر 1',
        'startedAt': startedAt,
        'endedAt': '2026-10-17T14:00:00.000',
        'totalCollected': 0,
      });
      final localShiftId = (await other.resolveShiftIdByKey({
        'cashierId': 4,
        'startedAt': startedAt,
      }))!;
      await other.applyRemoteRemainingTables(
        (mutation['tables'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        shiftKey: Map<String, dynamic>.from(mutation['shiftKey'] as Map),
      );

      final mirrored = await other.getRemainingTablesByShift(localShiftId);
      expect(mirrored, hasLength(1));
      expect(mirrored.single.tableName, 'مێز 1');
      expect(decodeRemainingTableItems(mirrored.single.itemsJson), hasLength(1));
    } finally {
      await other.resetForTesting();
    }
  });

  test('delivery slots are not counted as remaining tables', () async {
    final shiftId = await startShift(4);
    await seatTable(1);
    // A delivery slot lives in `tables` but is not a table in the room.
    await db.db.insert('tables', {
      'id': LocalDatabase.deliverySlotBase + 1,
      'name': 'دلیڤەری تەلەبات 1',
      'status': 1,
      'isDelivery': 1,
      'deliveryCompanyId': 1,
      'deliverySlot': 1,
      'seatedTime': DateTime.now().toIso8601String(),
      'totalAmount': 5000.0,
      'guestCount': 1,
    });

    await db.endShift(shiftId, DateTime.now().toIso8601String(), 0);

    final remaining = await db.getRemainingTablesByShift(shiftId);
    expect(remaining, hasLength(1));
    expect(remaining.single.tableId, 1);
  });

  // ==================== Shift handover ====================
  //
  // A shift does not start on an empty floor. Whatever the previous cashier
  // left sitting is inherited by the cashier who opens next - possibly days
  // later - and the settlement must land in THAT shift's money.

  test('a new shift inherits the tables the previous shift left', () async {
    final first = await startShift(4);
    await seatTable(1, guestCount: 3);
    await seatTable(2, guestCount: 5);
    await db.endShift(first, DateTime.now().toIso8601String(), 0);

    final second = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'کاشێر 5',
        startedAt: DateTime.now().toIso8601String(),
      ),
    );

    final inherited = await db.getRemainingTablesByShift(second);
    expect(inherited, hasLength(2));
    expect(inherited.map((t) => t.tableId), containsAll([1, 2]));
    for (final t in inherited) {
      expect(t.isCarriedIn, isTrue);
      expect(t.isOutstanding, isTrue);
      expect(t.carriedFromShiftId, first);
      expect(t.settledAt, isEmpty);
      expect(t.guestCount, greaterThan(0));
      expect(decodeRemainingTableItems(t.itemsJson), hasLength(1));
    }
    // The previous shift keeps its own record untouched: its report must still
    // say what it left behind.
    expect(await db.getRemainingTablesByShift(first), hasLength(2));
    // And the tables themselves were never freed.
    expect((await db.getTable(1))!.status, isNot(TableStatus.empty));
  });

  test('settling an inherited table closes it under the new shift', () async {
    final first = await startShift(4);
    await seatTable(1);
    await seatTable(2);
    await db.endShift(first, DateTime.now().toIso8601String(), 0);

    final second = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'کاشێر 5',
        startedAt: DateTime.now().toIso8601String(),
      ),
    );

    // The new cashier settles one of the two inherited tables during their own
    // shift - the money belongs to shift 2, which settleTable already stamps.
    await db.settleTable(1, 20000, 0, 0, 5, shiftId: second);

    final inherited = await db.getRemainingTablesByShift(second);
    final settled = inherited.firstWhere((t) => t.tableId == 1);
    final open = inherited.firstWhere((t) => t.tableId == 2);
    expect(settled.settledAt, isNotEmpty);
    expect(settled.settledShiftId, second);
    expect(settled.isOutstanding, isFalse);
    expect(open.settledAt, isEmpty);
    expect(open.isOutstanding, isTrue);

    // The settlement is filed under the shift that did the work.
    final settlement = (await db.getSettledOrdersByShiftId(second)).single;
    expect(settlement.tableId, 1);
    expect(settlement.totalAmount, 20000);
    expect(await db.getSettledOrdersByShiftId(first), isEmpty);
  });

  test('closing the new shift keeps one record per inherited table', () async {
    final first = await startShift(4);
    await seatTable(1);
    await seatTable(2);
    await db.endShift(first, DateTime.now().toIso8601String(), 0);

    final second = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'کاشێر 5',
        startedAt: DateTime.now().toIso8601String(),
      ),
    );
    // Something new is ordered on a table that is still open from yesterday.
    await db.addOrderItem(
      1,
      OrderItem(
        id: 'extra',
        name: 'چا',
        price: 2000,
        quantity: 1,
        category: 'چا',
        waiterName: 'وەیتەر 2',
        waiterRole: 0,
      ),
    );
    await seatTable(3);
    await db.endShift(second, DateTime.now().toIso8601String(), 0);

    final rows = await db.getRemainingTablesByShift(second);
    expect(rows, hasLength(3));
    expect(rows.map((t) => t.tableId).toSet(), {1, 2, 3});
    final table1 = rows.firstWhere((t) => t.tableId == 1);
    // Still the same inherited record, its snapshot refreshed at close.
    expect(table1.isCarriedIn, isTrue);
    expect(table1.carriedFromShiftId, first);
    expect(table1.totalAmount, 22000);
    expect(decodeRemainingTableItems(table1.itemsJson), hasLength(2));
    // The new table was simply left at close, not inherited.
    final table3 = rows.firstWhere((t) => t.tableId == 3);
    expect(table3.isCarriedIn, isFalse);
    expect(table3.totalAmount, 20000);
  });

  test('adoption is broadcast with the new shift key', () async {
    final first = await startShift(4);
    await seatTable(1);
    await db.endShift(first, DateTime.now().toIso8601String(), 0);

    final emitted = <Map<String, dynamic>>[];
    db.onMutation = (action, data) {
      if (action == 'SHIFT_REMAINING_TABLES') emitted.add(data);
    };
    const startedAt = '2026-10-20T09:00:00.000';
    await db.startShift(
      const CashierShift(
        cashierId: 5,
        cashierName: 'کاشێر 5',
        startedAt: startedAt,
      ),
    );

    expect(emitted, hasLength(1));
    expect(emitted.single['shiftKey'], {'cashierId': 5, 'startedAt': startedAt});
    final rows = (emitted.single['tables'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    expect(rows, hasLength(1));
    expect(rows.single['tableId'], 1);
    expect(rows.single['carriedAt'], isNotEmpty);
    expect(rows.single['carriedFromShiftId'], first);
  });

  test('a carried record is not resurrected after it is settled', () async {
    final first = await startShift(4);
    await seatTable(1);
    await db.endShift(first, DateTime.now().toIso8601String(), 0);
    final second = await startShift(4);
    await db.settleTable(1, 20000, 0, 0, 4, shiftId: second);

    final local = (await db.getRemainingTablesByShift(second)).single;
    expect(local.settledAt, isNotEmpty);

    // A stale payload from another device still says "open". It must not undo
    // the settlement the report already shows.
    final stale = Map<String, dynamic>.from(local.toMap())
      ..remove('id')
      ..['settledAt'] = ''
      ..['settledShiftId'] = 0;
    await db.applyRemoteRemainingTables(
      [stale],
      shiftKey: {
        'cashierId': 4,
        'startedAt': local.shiftStartedAt,
      },
    );
    expect(local.shiftStartedAt, isNotEmpty);
    expect((await db.getRemainingTablesByShift(local.shiftId)).single.settledAt,
        isNotEmpty);
  });
}
