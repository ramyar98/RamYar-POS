import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/remaining_table_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';

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
}
