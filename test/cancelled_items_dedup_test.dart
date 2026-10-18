import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/cancelled_item_model.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// The «ڕەتکراوەکان» duplicate reported from the captain's device: every dish
/// appeared 3-4 times under the captain's login while the admin's and the
/// cashier's copies stayed clean. The queued list reads the local database, so
/// several identical rows in `cancelled_items` on the captain's device render
/// as several identical cards.
///
/// Why there would be several rows: a rejection is broadcast by the till and
/// can reach a captain's device over more than one path - direct and relayed
/// copies of the same mutation, or again on a reconnect flush - and
/// `addCancelledItem` used to insert unconditionally, so every copy wrote its
/// own row.
///
/// The fix is a natural key for one rejection event (the till's exact ISO
/// second + table + dish + cashier + quantity). `addCancelledItem` is
/// idempotent on it, the queue collapses duplicates it already holds, and
/// "served" finds the record by the same key instead of by a row id that only
/// exists on the till.
Map<String, dynamic> _rejectionMap({
  String at = '2026-10-12T08:00:00.000',
  int tableId = 1,
  String name = 'قەیمە',
  double price = 8500,
  int by = 5,
  int qty = 2,
}) => {
  'shiftId': 0,
  'tableId': tableId,
  'tableName': 'مێز $tableId',
  'itemName': name,
  'itemPrice': price,
  'quantity': qty,
  'category': 'خواردن',
  'cancelledAt': at,
  'cancelledBy': by,
  'cancelledByName': 'کاشێر 1',
  'requestedByName': 'کاپتن 1',
  'requestedAt': at,
  'requestedByRole': 0,
  'status': 'pending',
  'servedAt': '',
};

/// The map the till would broadcast for a record - every field the receiving
/// device needs to place the row and to match it again on "served".
Map<String, dynamic> _fromItem(CancelledItem i) => {
  'shiftId': i.shiftId,
  'tableId': i.tableId,
  'tableName': i.tableName,
  'itemName': i.itemName,
  'itemPrice': i.itemPrice,
  'quantity': i.quantity,
  'category': i.category,
  'cancelledAt': i.cancelledAt,
  'cancelledBy': i.cancelledBy,
  'cancelledByName': i.cancelledByName,
  'requestedByName': i.requestedByName,
  'requestedAt': i.requestedAt,
  'requestedByRole': i.requestedByRole,
  'status': i.status,
  'servedAt': i.servedAt,
};

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // No-isolate factory: a database in a real isolate never hands its results
    // back inside the test's FakeAsync zone.
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

  tearDown(() async {
    await db.resetForTesting();
  });

  test('the same rejection delivered twice arrives as one record', () async {
    final map = _rejectionMap();
    await db.addCancelledItem(map);
    // Second delivery of the same mutation - the relayed copy.
    await db.addCancelledItem(map);

    final pending = await db.getPendingCancelledItems();
    expect(pending.length, 1,
        reason: 'each dish must appear once, not one card per delivery');
    expect(pending.first.itemName, 'قەیمە');
  });

  test('different dishes or tables in the same second stay separate', () async {
    await db.addCancelledItem(_rejectionMap(name: 'چای', price: 500));
    await db.addCancelledItem(_rejectionMap(name: 'قەیمە'));
    await db.addCancelledItem(_rejectionMap(tableId: 2));

    final pending = await db.getPendingCancelledItems();
    expect(pending.length, 3,
        reason: 'three real rejections must still be three rows');
  });

  test('a queue that already holds copies collapses to one row', () async {
    // A device corrupted by the pre-fix build. Make a real database file, let
    // LocalDatabase build the schema, then write the same rejection straight
    // into the table three times through a raw connection - exactly the state
    // the old sync left. (The public insert is idempotent now, so this is the
    // only faithful way to create the damage.)
    final dir = await Directory.systemTemp.createTemp('ramyar_dedup_heal');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}captain_dup.db';

    final dbFile = LocalDatabase();
    await dbFile.resetForTesting();
    await dbFile.init(path: path);
    addTearDown(() => dbFile.resetForTesting());

    final raw = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: LocalDatabase.schemaVersion),
    );
    await raw.insert('cancelled_items', _rejectionMap(name: 'چای', price: 500));
    final real = _rejectionMap();
    await raw.insert('cancelled_items', real);
    await raw.insert('cancelled_items', _rejectionMap());
    await raw.insert('cancelled_items', _rejectionMap());

    final pending = await dbFile.getPendingCancelledItems();
    expect(pending.length, 2,
        reason: 'the corrupted queue must collapse: «چای» + one «قەیمە»');
    expect(pending.where((i) => i.itemName == 'قەیمە').length, 1,
        reason: 'exactly one «قەیمە» card, not three');

    // And the strays are really gone from the file, not just hidden from the
    // list: a second read stays clean and the table holds the two rows only.
    final again = await dbFile.getPendingCancelledItems();
    expect(again.length, 2);
    final count = await raw.rawQuery(
      "SELECT COUNT(*) AS c FROM cancelled_items WHERE itemName = 'قەیمە'",
    );
    expect((count.first['c'] as num).toInt(), 1,
        reason: 'the duplicate rows themselves must be deleted');
    await raw.close();
  });

  test('served reaches the same rejection on a foreign device by its fields',
      () async {
    // Two devices. The till cancels first - its row id is 1, which this
    // captain's device has already spent on a *different* dish, so matching by
    // row id alone could never find the right row here.
    final till = LocalDatabase();
    await till.resetForTesting();
    await till.init(inMemory: true);
    addTearDown(till.resetForTesting);

    final captain = LocalDatabase();
    await captain.resetForTesting();
    await captain.init(inMemory: true);
    addTearDown(captain.resetForTesting);

    await till.recordCancelledItem(
      tableId: 1,
      tableName: 'Table 1',
      itemName: 'Burger',
      price: 8500,
      quantity: 2,
      category: 'food',
      cancelledBy: 5,
      cancelledByName: 'Cashier 1',
      requestedByName: 'Captain 1',
    );
    // The row exactly as the till stamped it - this is what the mutation
    // carries to every device.
    final tillItem = (await till.getPendingCancelledItems()).single;
    final real = _fromItem(tillItem);

    // The captain's device gets a different dish first, so its row id 1 is not
    // the till's row id 1.
    await captain.addCancelledItem(_rejectionMap(name: 'چای', price: 500));
    await captain.addCancelledItem(real);

    // The till moves the dish back and marks it served; the mutation carries
    // the till's row id *and* the record's own fields. Arriving here, the
    // fields - not the foreign row id - must be what finds the record.
    await captain.markCancelledItemServed(
      1, // the till's row id, which on this device is the "چای" row
      cancelledAt: tillItem.cancelledAt,
      tableId: tillItem.tableId,
      itemName: tillItem.itemName,
      itemPrice: tillItem.itemPrice,
      cancelledBy: tillItem.cancelledBy,
      quantity: tillItem.quantity,
    );

    final pending = await captain.getPendingCancelledItems();
    expect(pending.length, 1,
        reason: 'the rejected dish left the queue, only «چای» is still pending');
    expect(pending.first.itemName, 'چای',
        reason: 'the wrong row (id 1, «چای») must not have been served');
  });

  test('a buffered re-delivery cannot resurrect an already served rejection',
      () async {
    final map = _rejectionMap();
    await db.addCancelledItem(map);
    await db.markCancelledItemServed(
      1,
      cancelledAt: map['cancelledAt'] as String,
      tableId: map['tableId'] as int,
      itemName: map['itemName'] as String,
      itemPrice: map['itemPrice'] as double,
      cancelledBy: map['cancelledBy'] as int,
      quantity: map['quantity'] as int,
    );
    expect(await db.getPendingCancelledItems(), isEmpty);

    // The original mutation, delayed in a peer's buffer, finally arrives.
    await db.addCancelledItem(map);

    expect(await db.getPendingCancelledItems(), isEmpty,
        reason: 'a replay of the same rejection must not re-seat it in the '
            'queue after the cashier already moved it back');
  });

  test('a rejected dish reaches the captain exactly once, not twice', () async {
    // The reported bug: the cashier's own «ڕەتکراوەکان» was correct, but the
    // captain's copy listed every thrown-out dish twice. A local
    // `removeOrderItem` writes ONE cancelled record and then broadcasts TWO
    // mutations - `cancelledOrderItem` (the record, emitted first) and
    // `removeOrderItem` (the line removal). On the captain's device the second
    // handler used to run `removeOrderItem` again, which re-audited the dish
    // with this device's own clock; the two rows shared no dedup key, so both
    // survived and rendered as two cards for one rejection.
    final till = LocalDatabase();
    await till.resetForTesting();
    await till.init(inMemory: true);
    addTearDown(till.resetForTesting);

    final captain = LocalDatabase();
    await captain.resetForTesting();
    await captain.init(inMemory: true);
    addTearDown(captain.resetForTesting);

    // Both devices hold the same order line - the captain has to see the dish
    // to be able to re-audit it, which is what made the bug reproducible.
    final dish = OrderItem(
      id: 'o1',
      name: 'Burger',
      price: 8500,
      quantity: 2,
      category: 'food',
      createdAt: '2026-10-12T08:00:00.000',
      waiterName: 'Captain 1',
    );
    for (final device in [till, captain]) {
      device.onMutation = (_, _) {};
      await device.batchAddOrderItems(1, [dish]);
    }

    // The till rejects the dish and we capture exactly what it broadcasts.
    final sent = <MapEntry<String, Map<String, dynamic>>>[];
    till.onMutation = (action, data) => sent.add(MapEntry(action, data));
    await till.removeOrderItem(
      1,
      'o1',
      cancelledBy: 5,
      cancelledByName: 'Cashier 1',
    );
    expect(
      sent.map((e) => e.key),
      containsAllInOrder(['cancelledOrderItem', 'removeOrderItem']),
      reason: 'the record must travel before the line removal it belongs to',
    );

    // Every mutation lands on the captain's device through the real handler.
    captain.onMutation = null;
    for (final mutation in sent) {
      await debugApplyRemoteMutation(captain, mutation.key, mutation.value);
    }

    final pending = await captain.getPendingCancelledItems();
    expect(pending, hasLength(1),
        reason: 'one rejection is one card on the captain, not two');
    expect(pending.single.itemName, 'Burger');
    expect(pending.single.quantity, 2);
    expect(await captain.getOrderItems(1), isEmpty,
        reason: 'the line still has to leave the table');
  });

  test('a queue doubled by the old remote removal heals to one card', () async {
    // What the pre-fix build left on a captain's device: the till's real record
    // (a named cashier, stamped at 08:00:00) and the phantom its own
    // `removeOrderItem` re-audited (no user, stamped a second later). Both were
    // cut from the SAME order line, so they share `requestedAt`/`requestedByName`
    // but not `cancelledAt`/`cancelledBy` - the exact-key dedup keeps both.
    await db.addCancelledItem(_rejectionMap(by: 5, at: '2026-10-12T08:00:00.000'));
    // The phantom shares the real record's source line (`requestedAt`), which is
    // what ties them together, but carries its own later `cancelledAt` and no
    // user - so the exact-key dedup cannot see they are one event.
    final phantom = _rejectionMap(by: 0, at: '2026-10-12T08:00:01.000');
    phantom['requestedAt'] = '2026-10-12T08:00:00.000';
    await db.addCancelledItem(phantom);

    final pending = await db.getPendingCancelledItems();
    expect(pending, hasLength(1),
        reason: 'one rejected dish is one card, however many times it was '
            'written');
    expect(pending.single.cancelledBy, 5,
        reason: 'the named record is the real one; the anonymous copy goes');
  });

  test('two genuinely different rejections of one dish both stay', () async {
    // Same dish and table, but two different order lines (look at the requester
    // timestamp): that is two real rejections, not one written twice.
    await db.addCancelledItem(_rejectionMap(at: '2026-10-12T08:00:00.000'));
    await db.addCancelledItem(_rejectionMap(at: '2026-10-12T09:30:00.000'));

    final pending = await db.getPendingCancelledItems();
    expect(pending, hasLength(2),
        reason: 'a heal that eats real rejections is worse than the duplicate');
  });

  test('a phantom that disagrees on the order time still heals to one card',
      () async {
    // The live damage: the old build stamped the cart line's `createdAt`
    // separately on each device (the cart left it empty and both ends filled in
    // their own clock), so the till's real record and the captain's phantom did
    // NOT share `requestedAt` - and a heal keyed on it kept both. The dish,
    // table, quantity and requester still match, so they are one rejection.
    final real = _rejectionMap(by: 5, at: '2026-10-12T16:26:07.000');
    real['requestedAt'] = '2026-10-12T16:25:40.748';
    await db.addCancelledItem(real);

    final phantom = _rejectionMap(by: 0, at: '2026-10-12T16:26:01.000');
    phantom['requestedAt'] = '2026-10-12T16:25:35.272';
    await db.addCancelledItem(phantom);

    final pending = await db.getPendingCancelledItems();
    expect(pending, hasLength(1),
        reason: 'one rejected dish is one card, even when the two copies '
            'disagree on the order time');
    expect(pending.single.cancelledBy, 5,
        reason: 'the named record is the real one; the anonymous copy goes');
  });

  test('the order time is carried, not re-stamped, on the receiving device',
      () async {
    // The fix behind the heal: an order line is stored and broadcast with the
    // SAME `createdAt`, so a rejection cut from it on either device keys the
    // same and cannot leave a phantom. A cart line arrives with no time; both
    // the stored row and the emitted mutation must carry the one this device
    // stamps.
    final sent = <MapEntry<String, Map<String, dynamic>>>[];
    db.onMutation = (action, data) => sent.add(MapEntry(action, data));

    await db.batchSendAndOccupy(1, [
      OrderItem(id: 'o1', name: 'Burger', price: 8500, category: 'food'),
    ]);

    final stored = (await db.getOrderItems(1)).single;
    expect(stored.createdAt, isNotEmpty);
    final escaped = sent.singleWhere((e) => e.key == 'batchSendAndOccupy');
    final items = escaped.value['items'] as List;
    final broadcastAt = (items.single as Map)['createdAt'] as String;
    expect(broadcastAt, stored.createdAt,
        reason: 'the broadcast line must carry the time this device stored, '
            'not an empty string the receiver replaces with its own clock');
  });

  test('closing a shift clears its pending rejections; a new shift is fresh',
      () async {
    // A rejection belongs to the shift that was open when it happened. When
    // that shift closes, its leftovers leave the «ڕەتکراوەکان» queue - the next
    // shift starts empty, and the shift report still has the history.
    final shiftId = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'کاشێر 1',
        startedAt: DateTime.now().toIso8601String(),
      ),
    );
    await db.recordCancelledItem(
      tableId: 3,
      tableName: 'مێز 3',
      itemName: 'قەیمە',
      price: 8500,
      quantity: 1,
      category: 'خواردن',
      cancelledBy: 5,
      cancelledByName: 'کاشێر 1',
    );
    final stamped = (await db.getPendingCancelledItems()).single;
    expect(stamped.shiftId, shiftId,
        reason: 'a rejection is audited against the open shift');

    await db.endShift(shiftId, DateTime.now().toIso8601String(), 0);

    expect(await db.getPendingCancelledItems(), isEmpty,
        reason: 'closing the shift ends its rejected list');
    expect(await db.getCancelledItemsByShift(shiftId), hasLength(1),
        reason: 'the shift report still holds the rejection');
  });

  test('a rejection whose shift is unknown here is still shown', () async {
    // The receiving device may see the rejection before the shift row (a
    // captain that joined mid-shift), or the row may carry no shift at all.
    // Hiding a real rejection would be worse than showing a stale one, so only
    // a shift KNOWN to be closed removes it.
    await db.addCancelledItem(_rejectionMap());
    final orphan = _rejectionMap(name: 'چای', price: 500);
    orphan['shiftId'] = 999; // No such shift on this device.
    await db.addCancelledItem(orphan);

    expect(await db.getPendingCancelledItems(), hasLength(2));
  });

  test('a closed shift does not hide a different open shift\'s rejections',
      () async {
    final oldShift = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'کاشێر 1',
        startedAt: '2026-10-12T08:00:00.000',
      ),
    );
    await db.recordCancelledItem(
      tableId: 1,
      tableName: 'مێز 1',
      itemName: 'چای',
      price: 500,
      quantity: 1,
      category: 'خواردنەوە',
      cancelledBy: 5,
      cancelledByName: 'کاشێر 1',
    );
    await db.endShift(oldShift, '2026-10-12T09:00:00.000', 0);

    final newShift = await db.startShift(
      CashierShift(
        cashierId: 5,
        cashierName: 'کاشێر 1',
        startedAt: '2026-10-12T09:05:00.000',
      ),
    );
    await db.recordCancelledItem(
      tableId: 2,
      tableName: 'مێز 2',
      itemName: 'قەیمە',
      price: 8500,
      quantity: 1,
      category: 'خواردن',
      cancelledBy: 5,
      cancelledByName: 'کاشێر 1',
    );

    final pending = await db.getPendingCancelledItems();
    expect(pending, hasLength(1),
        reason: 'only the open shift\'s rejection is still pending');
    expect(pending.single.itemName, 'قەیمە');
    expect(pending.single.shiftId, newShift);
  });
}