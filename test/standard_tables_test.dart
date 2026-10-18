import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_model.dart';

/// The dining room is fixed at tables 1..100.
///
/// The complaint that started this: a cashier opened table 1, renamed it to
/// whatever they liked ("مێزی حەمە", "مێزی 83999"), saved - and table 1 was
/// gone from the floor. The fix: the room is the 100 PLACES ids 1..100; a name
/// is only a label on a place. A rename keeps the place (the id) and its
/// label; a delete puts the place straight back, empty.
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

  test('a fresh database has all 100 standard tables', () async {
    final tables = await db.getAllTables();
    expect(tables.length, kStandardTableCount);
    expect(tables.map((t) => t.id), containsAll(<int>[1, 50, 100]));
  });

  test('the reported case: مێزی حەمە - table 1 stays, under its new name',
      () async {
    await db.renameTable(1, 'مێزی حەمە');

    // Table 1 did not vanish: it is still the same row, with the new label.
    final t1 = await db.getTable(1);
    expect(t1, isNotNull, reason: 'id 1 is a place in the room - it cannot go');
    expect(t1!.name, 'مێزی حەمە');
    // ...and the standard label the place used to carry is handed back to the
    // floor as a spare row, so there is still a plain "table 1" to seat.
    expect((await db.getAllTables()).length, kStandardTableCount + 1);
  });

  test('the reported case: renaming table 1 adds a plain مێز 1 back', () async {
    await db.renameTable(1, 'مێزی حەمە');

    final spare = await db.getTable(LocalDatabase.standardLabelRowId(1));
    expect(spare, isNotNull,
        reason: 'the room lost its table 1 label, so a spare row takes it back');
    expect(spare!.name, LocalDatabase.standardTableName(1));
    expect(spare.status.index, 0, reason: 'the spare is empty and waiting');
    expect(spare.totalAmount, 0);
  });

  test('the reported case: مێزی 83999 - numbers are just another label',
      () async {
    await db.renameTable(1, 'مێزی 83999');
    final t1 = await db.getTable(1);
    expect(t1, isNotNull);
    expect(t1!.name, 'مێزی 83999');
    expect((await db.getAllTables()).length, kStandardTableCount + 1);
  });

  test('the renamed place keeps its guests and its bill; the spare is empty',
      () async {
    await db.occupyTable(1, '2', guestCount: 4);
    await db.addOrderItem(
      1,
      OrderItem(
        id: 'kept-across-rename',
        name: 'کەباب',
        price: 10000,
        quantity: 2,
        category: 'گەرمی',
        createdAt: '2026-01-01T10:00:00',
        waiterName: 'کاپتن 1',
      ),
    );
    await db.renameTable(1, 'مێزی حەمە');

    final renamed = await db.getTable(1);
    expect(renamed!.name, 'مێزی حەمە');
    expect(renamed.guestCount, 4,
        reason: 'the rename moved a label, not a party of guests');
    expect(await db.getOrderItems(1), hasLength(1),
        reason: 'the bill stays with the table that was renamed');

    final spare = await db.getTable(LocalDatabase.standardLabelRowId(1));
    expect(spare!.guestCount, 0);
    expect(await db.getOrderItems(spare.id), isEmpty);
  });

  test('renaming back to the standard label takes the spare away again',
      () async {
    await db.renameTable(1, 'مێزی حەمە');
    expect(await db.getTable(LocalDatabase.standardLabelRowId(1)), isNotNull);

    await db.renameTable(1, LocalDatabase.standardTableName(1));

    expect(await db.getTable(LocalDatabase.standardLabelRowId(1)), isNull,
        reason: 'two cards reading the same would be a duplicate to seat by '
            'mistake');
    expect((await db.getAllTables()).length, kStandardTableCount);
  });

  test('renaming the same place twice does not stack two spares', () async {
    // This is the cross-device path: the same rename arrives again from another
    // till, and both devices run this same method. One spare, not two.
    await db.renameTable(1, 'مێزی حەمە');
    await db.renameTable(1, 'مێزی حەمە');
    await db.renameTable(1, 'خانۆی دیکە');

    expect((await db.getAllTables()).length, kStandardTableCount + 1,
        reason: 'the spare is keyed to the place, so it cannot accumulate');
  });

  test('each renamed place gets its own spare, at a different id', () async {
    for (final id in [1, 25, 77, 100]) {
      await db.renameTable(id, 'تاقیکردنەوە $id');
    }
    final tables = await db.getAllTables();
    expect(tables.length, kStandardTableCount + 4);
    expect(tables.map((t) => t.id), containsAll(<int>[1, 25, 77, 100]));
    for (final id in [1, 25, 77, 100]) {
      final spare = await db.getTable(LocalDatabase.standardLabelRowId(id));
      expect(spare, isNotNull);
      expect(spare!.name, LocalDatabase.standardTableName(id));
    }
  });

  test('deleting a renamed place does not leave its spare behind', () async {
    await db.renameTable(1, 'مێزی حەمە');
    await db.deleteTable(1);

    expect(await db.getTable(LocalDatabase.standardLabelRowId(1)), isNull,
        reason: 'a ghost card would be there for the cashier to click by '
            'mistake');
    final restored = await db.getTable(1);
    expect(restored, isNotNull);
    expect(restored!.name, LocalDatabase.standardTableName(1));
    expect((await db.getAllTables()).length, kStandardTableCount);
  });

  test('deleting a standard table puts it straight back as an empty مێز N',
      () async {
    await db.deleteTable(1);
    final restored = await db.getTable(1);
    expect(restored, isNotNull,
        reason: 'the room is always 1..100 - a delete cannot leave a hole');
    expect(restored!.name, 'مێز 1');
  });

  test('a table the restore brings back starts empty with no bill', () async {
    // Seat the table and give it an order first.
    await db.occupyTable(7, '2', guestCount: 3);
    await db.addOrderItem(
      7,
      OrderItem(
        id: 'pre-delete-item',
        name: 'کەباب',
        price: 10000,
        quantity: 1,
        category: 'گەرمی',
        createdAt: '2026-01-01T10:00:00',
        waiterName: 'کاپتن 1',
      ),
    );
    await db.deleteTable(7);

    final restored = await db.getTable(7);
    expect(restored, isNotNull);
    expect(restored!.status.index, 0, reason: 'the replacement starts empty');
    expect(restored.totalAmount, 0);
    expect(await db.getOrderItems(7), isEmpty,
        reason: 'a re-created table carries no ghost bill');
  });

  test('ensureStandardTables repairs a database with holes in the range',
      () async {
    // Simulate an old database that lost rows some other way: delete through
    // the model first (so the fixture is realistic), then punch holes again
    // with a raw database handle so ensureStandardTables has work to do.
    await db.deleteTable(3);
    await db.deleteTable(99);
    await db.db.delete('tables', where: 'id IN (3, 99)');
    expect(await db.getTable(3), isNull);

    await db.ensureStandardTables();

    expect((await db.getTable(3))!.name, 'مێز 3');
    expect((await db.getTable(99))!.name, 'مێز 99');
    expect((await db.getAllTables()).length, kStandardTableCount);
  });

  test('ensureStandardTables never overwrites a custom name', () async {
    await db.renameTable(5, 'خانۆی گەورە');
    await db.ensureStandardTables();
    expect((await db.getTable(5))!.name, 'خانۆی گەورە');
  });

  test('delivery slots are untouched by the standard-table restore', () async {
    await db.addTable(
      TableModel(id: 9001, name: 'ئەمازۆن 1', isDelivery: true),
    );
    await db.ensureStandardTables();

    final stillThere = await db.getTable(9001);
    expect(stillThere, isNotNull,
        reason: 'delivery slots are not part of the dining room range');
    expect((await db.getAllTables()).length, kStandardTableCount,
        reason: 'the dining-room count still reads exactly 100');
  });
}
