import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_model.dart';

/// The shop's rule for a bill that is already out:
///
///   * the cashier prints the bill     -> the table is blue;
///   * ten minutes pass with no settle -> the table is red;
///   * the customer orders ANOTHER dish and the captain sends it -> the table
///     goes back to the working green, because the account now carries more
///     food than the printed bill showed.
///
/// The change has to land in the database, because every role's floor reads the
/// same tables row, and it has to be immediate - the captain's send button is
/// what triggers it.
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

  OrderItem food(String id) => OrderItem(
        id: id,
        name: 'بیرە',
        price: 3000,
        quantity: 1,
        createdAt: DateTime.now().toIso8601String(),
      );

  Future<void> makeOverdue(int tableId) async {
    await db.markAsPrinted(tableId);
    final longAgo = DateTime.now()
        .subtract(const Duration(minutes: 11))
        .toIso8601String();
    await db.db.update('tables', {'printedAt': longAgo},
        where: 'id = ?', whereArgs: [tableId]);
    await db.checkOverdueTables();
    expect((await db.getTable(tableId))!.status, TableStatus.overdue,
        reason: 'setup: the bill is overdue and the table is red');
  }

  group('a blue table plus another dish goes green', () {
    test('the captain sending more food clears the printed bill', () async {
      await db.batchSendAndOccupy(1, [food('b-1')], waiterId: '101');
      await db.markAsPrinted(1);
      expect((await db.getTable(1))!.status, TableStatus.billRequested,
          reason: 'the print makes it blue');

      // The customer asks for one more dish; the captain sends it.
      await db.batchSendAndOccupy(1, [food('b-2')], waiterId: '101');

      final t = await db.getTable(1);
      expect(t!.status, TableStatus.occupied,
          reason: 'another dish re-opens the account - back to green');
      expect(t.printedAt, isEmpty,
          reason: 'the old print clock goes with the old bill');
      expect(await db.getOrderItems(1), hasLength(2),
          reason: 'the extra dish is on the same account');
    });

    test('the reopened table is not swept red by the old clock', () async {
      await db.batchSendAndOccupy(1, [food('b-1')], waiterId: '101');
      await db.markAsPrinted(1);
      // The bill sat for eleven minutes...
      final longAgo = DateTime.now()
          .subtract(const Duration(minutes: 11))
          .toIso8601String();
      await db.db.update('tables', {'printedAt': longAgo},
          where: 'id = ?', whereArgs: [1]);
      // ...then the customer ordered more and the captain sent it.
      await db.batchSendAndOccupy(1, [food('b-2')], waiterId: '101');

      await db.checkOverdueTables();
      expect((await db.getTable(1))!.status, TableStatus.occupied,
          reason: 'the fresh dish must not be born already overdue');
    });
  });

  group('a red table plus another dish goes green', () {
    test('an overdue table re-opens when more food arrives', () async {
      await db.batchSendAndOccupy(1, [food('r-1')], waiterId: '101');
      await makeOverdue(1);

      await db.batchSendAndOccupy(1, [food('r-2')], waiterId: '101');

      final t = await db.getTable(1);
      expect(t!.status, TableStatus.occupied,
          reason: 'red goes back to the working green');
      expect(t.printedAt, isEmpty);
    });

    test('the cashier moving a rejected dish back also re-opens it', () async {
      await db.batchSendAndOccupy(1, [food('r-1')], waiterId: '101');
      await makeOverdue(1);

      // What the cashier's «گەڕاندنەوە» on a rejected item does.
      await db.addOrderItem(1, food('r-2'));

      expect((await db.getTable(1))!.status, TableStatus.occupied,
          reason: 'food going back on the account re-opens it');
    });
  });

  group('nothing else changes colour', () {
    test('topping up a green table leaves it green', () async {
      await db.batchSendAndOccupy(1, [food('g-1')], waiterId: '101');
      await db.batchSendAndOccupy(1, [food('g-2')], waiterId: '101');
      expect((await db.getTable(1))!.status, TableStatus.occupied);
    });

    test('seating an empty table with its first food is still green', () async {
      await db.batchSendAndOccupy(9, [food('e-1')], waiterId: '101');
      final t = await db.getTable(9);
      expect(t!.status, TableStatus.occupied);
      expect(t.printedAt, isEmpty);
    });

    test('the cashier printing again after the re-open starts a fresh blue',
        () async {
      await db.batchSendAndOccupy(1, [food('f-1')], waiterId: '101');
      await makeOverdue(1);
      await db.batchSendAndOccupy(1, [food('f-2')], waiterId: '101');
      expect((await db.getTable(1))!.status, TableStatus.occupied);

      await db.markAsPrinted(1);
      expect((await db.getTable(1))!.status, TableStatus.billRequested,
          reason: 'the second print is blue again');

      await db.checkOverdueTables();
      expect((await db.getTable(1))!.status, TableStatus.billRequested,
          reason: 'the fresh clock is ten minutes, so it is nowhere near red');
    });
  });
}
