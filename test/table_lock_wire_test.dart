import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/services/pos_socket_client.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/services/table_lock_controller.dart';

/// The eject and the force-unlock, as they actually travel between two devices.
///
/// These two actions are the only lock messages that carry nothing but a table
/// id - there is no device to blame, because the point of both is that *somebody*
/// took the table away, not that a particular handset said so. The first version
/// of the receiver read the device id off every lock message before looking at
/// what the message was, so these two threw on arrival and were dropped: the
/// cashier's device dropped the captain, and the captain's own device carried on
/// serving the table until the lock timed out. Nothing in the local tests caught
/// it, because the local tests never go through a socket - only running it on two
/// real devices showed it.
///
/// Everything here is two real databases and a real WebSocket, driven through
/// the same `TableLockController` the table page uses, because that is the only
/// place the whole path exists: a test that wrote the lock row by hand would pass
/// whether or not anything was ever broadcast.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // A fresh install seeds 100 tables, so the test tables have to sit past them.
  const kEjectTable = 107;
  const kForceTable = 108;
  const kNamelessTable = 109;

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for condition');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// One captain's open table page: a controller, the reason it would be told it
  /// lost the table, and a record of every time it was.
  ({TableLockController page, List<TableLockLoss> lost}) openCaptainPage(
    LocalDatabase db,
    int tableId, {
    required int userId,
    required String name,
  }) {
    final lost = <TableLockLoss>[];
    return (
      page: TableLockController(
        db: db,
        tableId: tableId,
        userId: userId,
        userName: name,
        role: 'waiter',
        onLost: lost.add,
      ),
      lost: lost,
    );
  }

  test('a captain ejected by the cashier is pulled off the table on their own device', () async {
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_eject_wire');

    // ===== The shop: the cashier's device is the hub, a captain's handset is on it =====
    final cashier = LocalDatabase();
    await cashier.init(
        path: '${tmp.path}${Platform.pathSeparator}eject-cashier.db');
    final ip = await startSyncServer(cashier, 4, 'cashier', SyncStateNotifier(),
        port: 9881);
    expect(ip, isNotNull, reason: 'the cashier device has to open the hub');

    final captain = LocalDatabase();
    await captain.init(
        path: '${tmp.path}${Platform.pathSeparator}eject-captain.db');
    expect(
        await connectToServer(captain, ip!, 2, 'waiter', SyncStateNotifier(),
            port: 9881),
        isTrue,
        reason: 'the captain handset has to be on the link');

    // ===== The captain opens a table and puts an order on it =====
    final cap = openCaptainPage(captain, kEjectTable, userId: 2, name: 'کاپتن 1');
    expect(await cap.page.acquire(), isTrue);
    // The bill is already on both devices - the captain rang it in and the
    // cashier has it. That is the state the eject has to leave alone.
    for (final device in [captain, cashier]) {
      await device.db.insert('order_items', {
        'id': 'w-1',
        'tableId': kEjectTable,
        'name': 'کەباب',
        'price': 10000,
        'quantity': 2,
        'category': 'گەرمی',
        'createdAt': '2026-01-01T10:00:00',
        'waiterName': 'کاپتن 1',
      });
    }

    // The lock has to reach the cashier before the eject means anything: it is
    // only interesting once both sides agree the captain is serving that table.
    await waitUntil(() async => (await cashier.getTableLockById(kEjectTable)) != null);
    expect(cap.lost, isEmpty, reason: 'nobody has taken the table yet');

    // ===== The cashier presses eject on the hold screen =====
    await cashier.ejectCaptainFromTable(kEjectTable);

    // ===== The captain's own device has to be told, and told properly =====
    await waitUntil(() async => cap.lost.isNotEmpty);
    expect(cap.lost.single, TableLockLoss.takenAway,
        reason: 'the page must step out of a table that is no longer its own');
    expect(await captain.getTableLockById(kEjectTable), isNull);

    // The bill survives on both devices: the cashier is about to settle exactly
    // this order, and the captain's own copy must not be wiped either.
    for (final device in [captain, cashier]) {
      final items = await device.getOrderItems(kEjectTable);
      expect(items, hasLength(1), reason: 'the order on ${device.db.path}');
      expect(items.single.name, 'کەباب');
      expect(items.single.quantity, 2);
    }

    // And nothing was sent on again - the echo would bounce the eject between
    // the two devices for ever.
    expect(await captain.getPendingSyncAll(), isEmpty);

    await cap.page.release();
    disconnectSync();
    await cashier.resetForTesting();
    await captain.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('a captain whose table is force-unlocked loses it on their own device', () async {
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_force_wire');

    final cashier = LocalDatabase();
    await cashier.init(
        path: '${tmp.path}${Platform.pathSeparator}force-cashier.db');
    final ip = await startSyncServer(cashier, 4, 'cashier', SyncStateNotifier(),
        port: 9882);
    expect(ip, isNotNull);

    // A second captain on a second handset, so the one being freed is not the
    // one holding the link.
    final cap2 = LocalDatabase();
    await cap2.init(path: '${tmp.path}${Platform.pathSeparator}force-captain.db');
    expect(
        await connectToServer(cap2, ip!, 3, 'waiter', SyncStateNotifier(),
            port: 9882),
        isTrue);

    final cap = openCaptainPage(cap2, kForceTable, userId: 3, name: 'کاپتن 2');
    expect(await cap.page.acquire(), isTrue);
    await waitUntil(() async => (await cashier.getTableLockById(kForceTable)) != null);

    // A device that stopped heartbeating must not hold a table off the shop for
    // ever. The force-unlock is the other device-less action.
    await cashier.forceUnlockTable(kForceTable);

    await waitUntil(() async => cap.lost.isNotEmpty);
    expect(cap.lost.single, TableLockLoss.takenAway);
    expect(await cap2.getTableLockById(kForceTable), isNull);

    await cap.page.release();
    disconnectSync();
    await cashier.resetForTesting();
    await cap2.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('a release that names no device is refused rather than freeing a table', () async {
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_nodevice_wire');

    final cashier = LocalDatabase();
    await cashier.init(
        path: '${tmp.path}${Platform.pathSeparator}nodevice-cashier.db');
    final ip = await startSyncServer(cashier, 4, 'cashier', SyncStateNotifier(),
        port: 9883);
    expect(ip, isNotNull);

    final captain = LocalDatabase();
    await captain.init(
        path: '${tmp.path}${Platform.pathSeparator}nodevice-captain.db');
    expect(
        await connectToServer(captain, ip!, 2, 'waiter', SyncStateNotifier(),
            port: 9883),
        isTrue);

    final cap = openCaptainPage(captain, kNamelessTable, userId: 2, name: 'کاپتن 1');
    expect(await cap.page.acquire(), isTrue);
    await waitUntil(
        () async => (await cashier.getTableLockById(kNamelessTable)) != null);

    // A release that names nobody cannot be attributed to a holder, and dropping
    // the row on a guess would free a table somebody is working. It is dropped.
    // A third handset sends it, so the working captain's link is a bystander.
    final rude = PosSocketClient(userId: 5, role: 'waiter');
    expect(await rude.connect(ip, port: 9883), isTrue);
    rude.sendMutation({'tableId': kNamelessTable}, action: 'TABLE_LOCK_RELEASED');

    await Future.delayed(const Duration(seconds: 3));
    final still = await captain.getTableLockById(kNamelessTable);
    expect(still, isNotNull, reason: 'a table must not be freed by a nameless release');
    expect(still!.userName, 'کاپتن 1');
    expect(cap.lost, isEmpty,
        reason: 'a captain must never be dropped off a table he still holds');

    rude.dispose();
    await cap.page.release();
    disconnectSync();
    await cashier.resetForTesting();
    await captain.resetForTesting();
    tmp.deleteSync(recursive: true);
  });
}
