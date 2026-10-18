import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';

/// The admin's shift report - and the captain's copy of «ڕەتکراوەکان» - must show
/// the same rejections the till recorded, on every device.
///
/// The report used to scope by the bare `shiftId`, a per-device
/// auto-increment number. On the till that number names the shift; on the admin's
/// device it names an unrelated row (or nothing), so the report read an empty
/// list while the very same rejections sat in the database. The device's own
/// shifts drifting away from the till's counter is the normal state, not an edge
/// case, so this has to hold with diverged ids.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late Directory dir;

  /// A device with its own real database FILE. Two `init(inMemory: true)`
  /// instances share one in-memory database under the FFI factory, which would
  /// quietly make "two devices" one device and hide exactly this bug.
  Future<LocalDatabase> device(String name) async {
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(path: '${dir.path}${Platform.pathSeparator}$name.db');
    addTearDown(db.resetForTesting);
    db.onMutation = null;
    return db;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('ramyar_shift_report');
  });

  tearDown(() async {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the admin sees a shift\'s rejections even when its local id differs',
      () async {
    final till = await device('till');
    final admin = await device('admin');

    // The admin's device has run its own shifts first, so its auto-increment
    // counter is already ahead of the till's - the ids cannot line up.
    for (var i = 0; i < 4; i++) {
      await admin.startShift(
        CashierShift(
          cashierId: 99,
          cashierName: 'Other',
          startedAt: '2026-10-0${i + 1}T00:00:00.000',
        ),
      );
    }

    final tillShiftId = await till.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'Cashier 1',
        startedAt: '2026-10-12T08:00:00.000',
      ),
    );
    await till.batchAddOrderItems(1, [
      OrderItem(id: 'o1', name: 'Burger', price: 8500, quantity: 1),
    ]);
    await till.removeOrderItem(
      1,
      'o1',
      cancelledBy: 5,
      cancelledByName: 'Cashier 1',
    );

    // The shift and the rejection arrive at the admin over sync.
    await admin.applyRemoteShift(
      Map<String, dynamic>.from((await till.db.query('cashier_shifts')).first),
    );
    await admin.addCancelledItem(
      Map<String, dynamic>.from(
        (await till.db.query('cancelled_items')).first,
      ),
    );

    final adminShift =
        (await admin.getAllShifts()).firstWhere((s) => s.cashierId == 5);

    expect(
      adminShift.id,
      isNot(tillShiftId),
      reason: 'the fixture must actually diverge the two devices\' shift ids, '
          'or it proves nothing',
    );
    expect(
      await admin.getCancelledItemsByShift(adminShift.id),
      hasLength(1),
      reason: 'the shift report must find the rejection by the shift\'s '
          'device-independent key, not by the till\'s local id',
    );
  });

  test('closing a shift empties the live queue but keeps the shift report',
      () async {
    final till = await device('till');
    final captain = await device('captain');

    final tillShiftId = await till.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'Cashier 1',
        startedAt: '2026-10-12T08:00:00.000',
      ),
    );
    await till.batchAddOrderItems(1, [
      OrderItem(id: 'o1', name: 'Burger', price: 8500, quantity: 1),
    ]);
    await till.removeOrderItem(
      1,
      'o1',
      cancelledBy: 5,
      cancelledByName: 'Cashier 1',
    );

    await captain.applyRemoteShift(
      Map<String, dynamic>.from((await till.db.query('cashier_shifts')).first),
    );
    await captain.addCancelledItem(
      Map<String, dynamic>.from(
        (await till.db.query('cancelled_items')).first,
      ),
    );

    expect(
      await captain.getPendingCancelledItems(),
      hasLength(1),
      reason: 'the captain sees the rejection while the shift is open',
    );

    // The till closes the shift; the captain hears the end.
    await till.endShift(tillShiftId, '2026-10-12T10:00:00.000', 0);
    await captain.applyRemoteShift(
      Map<String, dynamic>.from((await till.db.query('cashier_shifts')).first),
    );

    expect(
      await captain.getPendingCancelledItems(),
      isEmpty,
      reason: 'a closed shift hands nothing to the next one on any device',
    );
    final captainShift =
        (await captain.getAllShifts()).firstWhere((s) => s.cashierId == 5);
    expect(
      await captain.getCancelledItemsByShift(captainShift.id),
      hasLength(1),
      reason: 'the closed shift keeps its own record on the captain\'s device',
    );
  });

  test('a new shift starts with an empty rejected queue', () async {
    final db = await device('cashier');
    final first = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'Cashier 5',
        startedAt: '2026-10-12T08:00:00.000',
      ),
    );
    await db.recordCancelledItem(
      tableId: 1,
      tableName: 'مێز 1',
      itemName: 'Burger',
      price: 8500,
      quantity: 1,
      category: 'food',
      cancelledBy: 5,
      cancelledByName: 'Cashier 5',
    );
    expect(await db.getPendingCancelledItems(), hasLength(1));

    await db.endShift(first, '2026-10-12T09:00:00.000', 0);

    // Same cashier, same account, brand new shift.
    final second = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'Cashier 5',
        startedAt: '2026-10-12T09:05:00.000',
      ),
    );
    expect(
      await db.getPendingCancelledItems(),
      isEmpty,
      reason: 'even the same cashier starts a new shift with nothing carried '
          'over from the closed one',
    );
    expect(
      await db.getCancelledItemsByShift(first),
      hasLength(1),
      reason: 'the closed shift still owns its record',
    );
    expect(await db.getCancelledItemsByShift(second), isEmpty);
  });
}
