import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/colors.dart';
import 'package:ramyar_pos/core/table_status_visuals.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';

/// The whole rule, end to end, through the exact calls the screens make.
///
/// The floor's rule in one scenario: a customer sits down and the table is
/// green; the captain asks for the bill and it turns blue; ten minutes later,
/// with the bill unpaid, it turns red; settling frees it. Each step is asserted
/// on both the state the database holds and the colour the floor will draw, so
/// the state and the picture cannot come apart.
///
/// The blue spell is ten MINUTES and the constant is written in SECONDS (600).
/// That combination is deliberate: the window began as `billOverdueMinutes = 10`
/// compared with `inMinutes` - which truncates - so the red could arrive anywhere
/// from ten to eleven minutes after the print.
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

  /// Rewinds the print stamp, standing in for the wait between the print and
  /// the sweep. The sweep is driven by the wall clock, so the only honest way to
  /// test the passage of the window is to move the recorded time.
  Future<void> rewindPrint(int tableId, Duration age) async {
    final past =
        DateTime.now().subtract(age).toIso8601String();
    await db.db
        .update('tables', {'printedAt': past}, where: 'id = ?', whereArgs: [tableId]);
  }

  test('the floor rule, from a customer sitting down to the bill going red',
      () async {
    // 1. A customer sits down. Green, and the table carries no bill yet.
    await db.occupyTable(1, '10001', guestCount: 4);
    var table = await db.getTable(1);
    expect(table!.status, TableStatus.occupied);
    expect(TableStatusVisuals.color(table.status), AppColors.success,
        reason: 'a seated customer is green');
    expect(table.printedAt, isEmpty,
        reason: 'the bill clock does not start until the bill is printed');

    // The sweep must leave a merely seated table alone, however long it sits.
    await db.db.update('tables', {
      'seatedTime': DateTime.now()
          .subtract(const Duration(hours: 4))
          .toIso8601String(),
    }, where: 'id = ?', whereArgs: [1]);
    await db.checkOverdueTables();
    expect((await db.getTable(1))!.status, TableStatus.occupied,
        reason: 'only a printed bill carries the clock');

    // 2. The captain asks for the bill. Blue, at once.
    await db.requestBill(1);
    table = await db.getTable(1);
    expect(table!.status, TableStatus.billRequested);
    expect(TableStatusVisuals.color(table.status), AppColors.blue,
        reason: 'the bill was issued for this table, so it is blue');
    expect(table.sentToCashier, isTrue,
        reason: 'the request has to reach the cashier');

    // Inside the window it stays blue - a bill handed over a few minutes ago is
    // not a problem yet.
    await rewindPrint(1, const Duration(minutes: 5));
    await db.checkOverdueTables();
    expect((await db.getTable(1))!.status, TableStatus.billRequested,
        reason: 'five minutes in is still inside the ten minute window');

    // 3. The bill is printed by the cashier. Blue still - the print is what
    // starts the clock, so it restarts it.
    await db.markAsPrinted(1);
    await rewindPrint(1, const Duration(minutes: 5));
    await db.checkOverdueTables();
    expect((await db.getTable(1))!.status, TableStatus.billRequested,
        reason: 'a fresh print restarts the window and goes back to blue');

    // 4. Ten minutes pass with no settle. Red.
    await rewindPrint(1, const Duration(minutes: 11));
    await db.checkOverdueTables();
    table = await db.getTable(1);
    expect(table!.status, TableStatus.overdue,
        reason: 'eleven minutes is past a ten minute window');
    expect(TableStatusVisuals.color(table.status), AppColors.danger,
        reason: 'the customer has not come back, so the table is red');

    // 5. The customer pays. The table is free again and the red is gone.
    await db.settleTable(1, 25000, 0, 0, 2);
    table = await db.getTable(1);
    expect(table!.status, TableStatus.empty,
        reason: 'settling frees the table whatever colour it was');
    expect(table.printedAt, isEmpty,
        reason: 'a freed table must not carry a stale print time forward');
  });

  test('the red is a flag on the state, not a thing the UI invents', () {
    // The reason every role sees the same colour: the colour is a pure function
    // of a state stored in the database that all roles read, so there is no
    // per-screen copy of the decision to fall out of step.
    expect(TableStatusVisuals.color(TableStatus.occupied),
        isNot(TableStatusVisuals.color(TableStatus.overdue)));
    expect(TableStatusVisuals.color(TableStatus.billRequested),
        isNot(TableStatusVisuals.color(TableStatus.overdue)));
  });

  test('reprinting a red table clears the red and starts the window again',
      () async {
    await db.occupyTable(1, '10001');
    await db.markAsPrinted(1);
    await rewindPrint(1, const Duration(minutes: 11));
    await db.checkOverdueTables();
    expect((await db.getTable(1))!.status, TableStatus.overdue);

    // The cashier prints again for this table: it is blue again, and the window
    // runs again rather than the table being stuck red.
    await db.markAsPrinted(1);
    expect((await db.getTable(1))!.status, TableStatus.billRequested,
        reason: 'a reprint clears the overdue flag');

    await db.checkOverdueTables();
    expect((await db.getTable(1))!.status, TableStatus.billRequested,
        reason: 'the fresh print is inside its own new window');
  });

  test('the sweep only touches tables whose bill was actually printed', () async {
    // Three tables: one printed long ago (red), one printed long ago as well
    // (red), and one asked about but never printed (untouched).
    await db.occupyTable(1, '10001');
    await db.markAsPrinted(1);
    await rewindPrint(1, const Duration(minutes: 11));

    await db.occupyTable(2, '10001');
    await db.markAsPrinted(2);
    await rewindPrint(2, const Duration(minutes: 11));

    await db.occupyTable(3, '10001');
    await db.requestBill(3);
    // Undo the stamp the request set, standing in for a request whose bill the
    // cashier has not printed yet.
    await db.db.update('tables', {'printedAt': ''}, where: 'id = ?', whereArgs: [3]);

    await db.checkOverdueTables();

    expect((await db.getTable(1))!.status, TableStatus.overdue);
    expect((await db.getTable(2))!.status, TableStatus.overdue);
    expect((await db.getTable(3))!.status, TableStatus.billRequested,
        reason: 'a request with no print has no clock to run out');
  });
}
