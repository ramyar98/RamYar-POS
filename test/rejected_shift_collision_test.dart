import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/settlement_model.dart';

/// «ڕەتکراوەکان» must not be scoped by a per-device `shiftId`.
///
/// `cancelled_items.shiftId` is an auto-increment number that only means
/// anything on the device that wrote it. A till's id for today's shift can be
/// the same number this device gave to an unrelated, already-closed shift, and
/// the old queue hid any rejection whose id matched ANY closed shift here - so a
/// live rejection vanished from the captain's list, and the shift report matched
/// the wrong shift. A rejection with no device-independent key is placed by the
/// time window it was written in instead.
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

  tearDown(() async => db.resetForTesting());

  test('a rejection survives a colliding id from a closed shift', () async {
    // An earlier, closed shift on this device - it will own the id the till's
    // own counter happens to give today's shift.
    final closed = await db.startShift(CashierShift(
      cashierId: 5,
      cashierName: 'Cashier 1',
      startedAt: '2026-10-01T08:00:00.000',
    ));
    await db.endShift(closed, '2026-10-01T16:00:00.000', 0);

    // Today's shift, open.
    final open = await db.startShift(CashierShift(
      cashierId: 5,
      cashierName: 'Cashier 1',
      startedAt: '2026-10-14T08:00:00.000',
    ));

    // A rejection broadcast by a till whose own local id for today's shift
    // happened to be `closed` (the id counters diverge across devices). It
    // carries no device-independent key - the pre-v41 shape.
    await db.addCancelledItem({
      'shiftId': closed,
      'tableId': 1,
      'tableName': 'مێز 1',
      'itemName': 'کەباب',
      'itemPrice': 10000.0,
      'quantity': 1,
      'category': 'گەرمی',
      'cancelledAt': '2026-10-14T09:00:00.000',
      'cancelledBy': 5,
      'cancelledByName': 'Cashier 1',
      'requestedByName': 'کاپتن 1',
      'requestedAt': '2026-10-14T08:30:00.000',
      'requestedByRole': 0,
      'status': 'pending',
      'servedAt': '',
    });

    expect(
      await db.getPendingCancelledItems(),
      hasLength(1),
      reason: 'the shift running now is open on this device, so the rejection '
          'must be in the queue - its stored id names an unrelated closed shift',
    );
    expect(
      await db.getCancelledItemsByShift(open),
      hasLength(1),
      reason: 'the rejection happened during the open shift and belongs in its '
          'report',
    );
    expect(
      await db.getCancelledItemsByShift(closed),
      isEmpty,
      reason: 'the closed shift must not steal the rejection by its id',
    );
  });
}
