import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/settlement_model.dart';

/// Verifies the cashier shift data flow: a shift started on a cashier device
/// (even fully offline) reaches the admin device when network returns, and all
/// shift-linked data (expenses, refunds, settled orders) is attached to the
/// SAME shift on every device via the device-independent (cashierId, startedAt)
/// key.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ramyar_pos_shift_sync');
    db = LocalDatabase();
    // A per-test temp FILE keeps every device in this suite on its own store
    // (:memory: with sqflite ffi is a single shared store per process).
    await db.init(path: '${tmp.path}${Platform.pathSeparator}admin.db');
  });

  tearDown(() async {
    await db.resetForTesting();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A second device with its own private store.
  Future<LocalDatabase> newDevice(String name, String fn) async {
    final device = LocalDatabase();
    await device.init(path: '${tmp.path}${Platform.pathSeparator}$name.db');
    return device;
  }

  test('starting and ending a shift emits SHIFT_STARTED / SHIFT_ENDED', () async {
    final emitted = <String, List<Map<String, dynamic>>>{};
    db.onMutation = (action, data) {
      emitted[action] = [...(emitted[action] ?? []), data];
    };

    const startedAt = '2026-09-25T10:00:00.000';
    final id = await db.startShift(
      const CashierShift(cashierId: 2, cashierName: 'کاشێر 1', startedAt: startedAt),
    );
    expect(id, greaterThan(0));

    final started = emitted['SHIFT_STARTED']!.single['shift'] as Map<String, dynamic>;
    expect(started['id'], id);
    expect(started['cashierId'], 2);
    expect(started['startedAt'], startedAt);
    expect(started['endedAt'], '');

    await db.endShift(id, '2026-09-25T14:00:00.000', 250000);
    final ended = emitted['SHIFT_ENDED']!.single['shift'] as Map<String, dynamic>;
    expect(ended['endedAt'], '2026-09-25T14:00:00.000');
    expect(ended['totalCollected'], 250000);
  });

  test('an offline shift start is queued and survives until reconnect', () async {
    const startedAt = '2026-09-25T10:00:00.000';
    await db.startShift(
      const CashierShift(cashierId: 2, cashierName: 'کاشێر 1', startedAt: startedAt),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final pending = await db.getPendingSyncAll();
    final actions = pending.map((p) => p['action']).toList();
    expect(actions, contains('SHIFT_STARTED'));
    // The shift is also stored locally so work can continue while offline.
    expect((await db.getActiveShift(2))?.startedAt, startedAt);
  });

  test('a shift started on the cashier device appears on the admin device with its expenses', () async {
    // Admin device (this db) starts empty - the shift must arrive remotely.
    const startedAt = '2026-09-25T10:00:00.000';
    final cashier = await newDevice('cashier', (() {}).toString());
    try {
      final emitted = <String, Map<String, dynamic>>{};
      cashier.onMutation = (action, data) => emitted[action] = data;

      final shiftId = await cashier.startShift(
        const CashierShift(cashierId: 2, cashierName: 'کاشێر 1', startedAt: startedAt),
      );

      // Apply the relayed SHIFT_STARTED mutation on the admin device.
      final shiftMut = emitted['SHIFT_STARTED']!;
      await db.applyRemoteShift(Map<String, dynamic>.from(shiftMut['shift'] as Map));

      final allShifts = await db.getAllShifts();
      expect(allShifts, hasLength(1));
      expect(allShifts.single.cashierName, 'کاشێر 1');

      final adminShiftId = await db.resolveShiftIdByKey(
        {'cashierId': 2, 'startedAt': startedAt},
      );
      expect(adminShiftId, isNotNull);

      // The cashier records an expense; the admin device must attach it to the
      // SAME shift even though the auto-increment ids differ per device.
      await cashier.addCashierExpense(shiftId, 'خەرجی سەودا', 5000);
      final expMut = emitted['CASHIER_EXPENSE_CREATED']!;
      await db.applyRemoteExpense(
        Map<String, dynamic>.from(expMut['expense'] as Map),
        shiftKey: expMut['shiftKey'] is Map
            ? Map<String, dynamic>.from(expMut['shiftKey'] as Map)
            : null,
      );

      final expenses = await db.getShiftExpenses(adminShiftId!);
      expect(expenses, hasLength(1));
      expect(expenses.single['itemName'], 'خەرجی سەودا');
    } finally {
      await cashier.resetForTesting();
    }
  });

  test('a settlement on the cashier device reaches the admin shift detail', () async {
    // Cashier device starts today's shift and settles a table.
    const startedAt = '2026-09-25T10:00:00.000';
    final cashier = await newDevice('cashier2', (() {}).toString());
    try {
      final emitted = <String, Map<String, dynamic>>{};
      cashier.onMutation = (action, data) => emitted[action] = data;

      final shiftId = await cashier.startShift(
        const CashierShift(cashierId: 2, cashierName: 'کاشێر 1', startedAt: startedAt),
      );
      // Define a clean table set (raw inserts - no mutations) so table 5 exists.
      await cashier.resetTablesToRange(10);
      await cashier.db.insert('order_items', {
        'id': 'c1-1',
        'tableId': 5,
        'name': 'کەباب',
        'price': 10000.0,
        'quantity': 1,
        'category': 'کەباب',
        'createdAt': DateTime.now().toIso8601String(),
        'waiterName': 'کاپتن 1',
      });
      await cashier.settleTable(5, 10000, 0, 0, 1, shiftId: shiftId);

      final settleMut = emitted['settleTable']!;
      final order = settleMut['order'] as Map<String, dynamic>;
      final items = (settleMut['items'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final shiftKey = settleMut['shiftKey'] is Map
          ? Map<String, dynamic>.from(settleMut['shiftKey'] as Map)
          : null;

      // Admin device: shift arrives first, then the settlement.
      await db.applyRemoteShift(
        Map<String, dynamic>.from(emitted['SHIFT_STARTED']!['shift'] as Map),
      );
      await db.applyRemoteSettledOrder(
        Map<String, dynamic>.from(order),
        items: items,
        shiftKey: shiftKey,
      );

      final adminShiftId = await db.resolveShiftIdByKey(
        {'cashierId': 2, 'startedAt': startedAt},
      );
      expect(adminShiftId, isNotNull);

      final settled = await db.getSettledOrdersByShiftId(adminShiftId!);
      expect(settled, hasLength(1));
      expect(settled.single.tableId, 5);
      expect(settled.single.totalAmount, 10000);

      final orderItems = await db.getSettledOrderItems(settled.single.id);
      expect(orderItems, hasLength(1));
      expect(orderItems.single.itemName, 'کەباب');

      // The shift-wide batch query the report's demand tab uses must return the
      // same line without walking order by order.
      final shiftItems = await db.getSettledOrderItemsByShiftId(adminShiftId);
      expect(shiftItems, hasLength(1));
      expect(shiftItems.single.itemName, 'کەباب');
    } finally {
      await cashier.resetForTesting();
    }
  });

  test('cashier shifts travel inside the snapshot', () async {
    const startedAt = '2026-09-25T10:00:00.000';
    await db.startShift(
      const CashierShift(cashierId: 2, cashierName: 'کاشێر 1', startedAt: startedAt),
    );

    final snap = await db.buildSnapshot();
    expect(snap['cashier_shifts'], isA<List<dynamic>>());
    expect((snap['cashier_shifts'] as List), hasLength(1));

    final admin = await newDevice('admin2', (() {}).toString());
    try {
      await admin.applySnapshot(snap);
      final shifts = await admin.getAllShifts();
      expect(shifts, hasLength(1));
      expect(shifts.single.cashierName, 'کاشێر 1');
    } finally {
      await admin.resetForTesting();
    }
  });
}