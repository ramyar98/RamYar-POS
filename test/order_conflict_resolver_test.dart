import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/services/order_conflict_resolver.dart';

/// A captain ringing food in on one device, and the hub deciding what to do
/// with the batch when it lands.
///
/// The case that matters most is the second round of the same dish. It used to be
/// thrown away, because "is this a duplicate?" was answered by comparing the
/// dish's name, price and quantity - which cannot tell a second round from a
/// repeated message. The captain's screen showed the kebab; the cashier's never
/// did, and the table came to short by one dish.
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

  OrderItem item(String id, String name, double price, String createdAt,
          {int quantity = 1, String waiterName = ''}) =>
      OrderItem(
        id: id,
        name: name,
        price: price,
        quantity: quantity,
        createdAt: createdAt,
        waiterName: waiterName,
      );

  Future<void> seedOrder(List<OrderItem> items) =>
      db.batchSendAndOccupy(5, items, guestCount: 1, waiterId: '101');

  test('applies when table has no existing items', () async {
    final outcome = await resolveOrderConflict(
        db, 5, [item('a', 'کەباب', 10000, '2026-01-01T10:00:00')]);
    expect(outcome, OrderConflictOutcome.apply);
  });

  test('a second round of the same dish is a new order, not a duplicate',
      () async {
    await seedOrder([item('a', 'کەباب', 10000, '2026-01-01T10:00:00')]);
    // Same dish, same price, same quantity, ten minutes later - a different
    // item, because it was rung in separately and got its own id.
    final outcome = await resolveOrderConflict(
        db, 5, [item('b', 'کەباب', 10000, '2026-01-01T10:05:00')]);
    expect(outcome, OrderConflictOutcome.apply);

    // And it really does land: two kebabs on the table, not one.
    await db.batchSendAndOccupy(5, [item('b', 'کەباب', 10000, '')],
        guestCount: 1, waiterId: '101');
    expect((await db.getOrderItems(5)).length, 2);
    expect((await db.getTable(5))!.totalAmount, 20000);
  });

  test('the same batch arriving twice is not added twice', () async {
    final batch = [item('a', 'کەباب', 10000, '2026-01-01T10:00:00')];
    await seedOrder(batch);
    // A reconnect flush re-sends the very same item, id and all.
    final outcome = await resolveOrderConflict(db, 5, batch);
    expect(outcome, OrderConflictOutcome.alreadyApplied);
  });

  test('a batch that partly overlaps adds only what is missing', () async {
    await seedOrder([item('a1', 'کەباب', 10000, '2026-01-01T10:05:00')]);
    final outcome = await resolveOrderConflict(db, 5, [
      item('a1', 'کەباب', 10000, '2026-01-01T10:05:00'),
      item('a2', 'پیتزا', 5000, '2026-01-01T10:06:00'),
    ]);
    expect(outcome, OrderConflictOutcome.apply);
  });

  test('duplicate with different quantity is not a duplicate', () async {
    await seedOrder([item('a', 'کەباب', 10000, '2026-01-01T10:00:00', quantity: 1)]);
    final outcome = await resolveOrderConflict(
        db, 5, [item('b', 'کەباب', 10000, '2026-01-01T10:05:00', quantity: 2)]);
    expect(outcome, OrderConflictOutcome.apply);
  });

  test('an earlier timestamp never deletes what is already on the table',
      () async {
    // Two captains ordered while the hub was briefly unreachable. The second
    // device's clock is behind, so its batch looks older. It must be added, not
    // substituted - the first captain's order is real money on the table.
    await seedOrder([item('a', 'کەباب', 10000, '2026-01-01T10:05:00')]);
    final outcome = await resolveOrderConflict(
        db, 5, [item('b', 'پیتزا', 5000, '2026-01-01T10:00:00')]);
    expect(outcome, OrderConflictOutcome.apply);
  });

  test('later-created different order appends', () async {
    await seedOrder([item('a', 'کەباب', 10000, '2026-01-01T10:00:00')]);
    final outcome = await resolveOrderConflict(
        db, 5, [item('b', 'پیتزا', 5000, '2026-01-01T10:05:00')]);
    expect(outcome, OrderConflictOutcome.apply);
  });

  test('existing items without parseable createdAt still apply', () async {
    await seedOrder([item('a', 'کەباب', 10000, 'not-a-date')]);
    final outcome = await resolveOrderConflict(
        db, 5, [item('b', 'پیتزا', 5000, '2026-01-01T10:00:00')]);
    expect(outcome, OrderConflictOutcome.apply);
  });

  test('multi-item batch: a repeat is ignored, a new one is added', () async {
    final original = [
      item('a1', 'کەباب', 10000, '2026-01-01T10:05:00'),
      item('a2', 'پیتزا', 5000, '2026-01-01T10:06:00'),
    ];
    await seedOrder(original);

    // Same two ids again: nothing to do.
    expect(await resolveOrderConflict(db, 5, original),
        OrderConflictOutcome.alreadyApplied);

    // Two fresh ids: applied, and the table keeps what it had.
    final second = await resolveOrderConflict(db, 5, [
      item('c1', 'سالاد', 3000, '2026-01-01T10:03:00'),
      item('c2', 'چای', 1000, '2026-01-01T10:04:00'),
    ]);
    expect(second, OrderConflictOutcome.apply);
  });

  test('an empty batch is applied rather than treated as already there',
      () async {
    await seedOrder([item('a', 'کەباب', 10000, '2026-01-01T10:00:00')]);
    expect(await resolveOrderConflict(db, 5, []), OrderConflictOutcome.apply);
  });

  test('a batch with no ids at all is applied, never guessed away', () async {
    await seedOrder([item('a', 'کەباب', 10000, '2026-01-01T10:00:00')]);
    expect(
      await resolveOrderConflict(
          db, 5, [item('', 'پیتزا', 5000, '2026-01-01T10:05:00')]),
      OrderConflictOutcome.apply,
    );
  });
}
