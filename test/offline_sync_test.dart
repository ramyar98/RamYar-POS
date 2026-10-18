import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/services/pos_socket_client.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/services/sync_types.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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

  test('offline waiter order is delivered on reconnect and ack updates delivery', () async {
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_offline');
    // ===== Phase 1: waiter is OFFLINE, order is queued as pending sync =====
    final waiterDb = LocalDatabase();
    await waiterDb.init(path: '${tmp.path}${Platform.pathSeparator}waiter.db');
    final items = [
      OrderItem(
        id: 'w1-1', name: 'کەباب', price: 10000, quantity: 1,
        category: 'گەرمی', createdAt: '2026-01-01T10:00:00', waiterName: 'وەیتەر 1',
      ),
    ];
    await waiterDb.batchSendAndOccupyPending(5, items, guestCount: 2, waiterId: '2');
    await waiterDb.recordOrderSent(5);
    expect(await waiterDb.getPendingSyncAll(), hasLength(1));
    expect(await waiterDb.getOrderItems(5), hasLength(1));
    expect(await waiterDb.getOrderDeliveries(), hasLength(1));

    // ===== Phase 2: cashier server comes online =====
    final cashierDb = LocalDatabase();
    await cashierDb.init(path: '${tmp.path}${Platform.pathSeparator}cashier.db');
    final serverState = SyncStateNotifier();
    final ip = await startSyncServer(cashierDb, 4, 'cashier', serverState, port: 9877);
    expect(ip, isNotNull);

    // ===== Phase 3: waiter reconnects -> pending flushes -> ack =====
    final clientState = SyncStateNotifier();
    final ok = await connectToServer(waiterDb, ip!, 2, 'waiter', clientState, port: 9877);
    expect(ok, isTrue);

    await waitUntil(() async {
      final deliveries = await waiterDb.getOrderDeliveries();
      final pending = await waiterDb.getPendingSyncAll();
      return deliveries.isNotEmpty && deliveries.first.hasArrived && pending.isEmpty;
    });

    final itemsOnServer = await cashierDb.getOrderItems(5);
    expect(itemsOnServer, hasLength(1));
    expect(itemsOnServer.single.waiterName, 'وەیتەر 1');

    final deliveries = await waiterDb.getOrderDeliveries();
    expect(deliveries, hasLength(1));
    expect(deliveries.single.tableId, 5);
    expect(deliveries.single.hasArrived, isTrue);
    expect(deliveries.single.hasPrinted, isFalse);
    expect(deliveries.single.rejected, isFalse);

    // ===== Phase 4: the same batch re-delivered is not added twice =====
    // This is what a reconnect flush or a retry looks like from the hub's side:
    // the identical item, id and all. It must not be inserted again, and it must
    // not be reported as a failure - the order really is on the table.
    final waiter2 = PosSocketClient(userId: 3, role: 'waiter');
    final acks2 = <AckMessage>[];
    waiter2.onMessage = (msg) {
      if (msg.type == 'ack') acks2.add(AckMessage.fromSyncMessage(msg));
    };
    expect(await waiter2.connect(ip, port: 9877), isTrue);

    waiter2.sendMutation({
      'tableId': 5,
      'items': items.map((e) => e.toMap()).toList(),
      'guestCount': 2,
      'waiterId': '2',
    }, action: 'batchSendAndOccupy');
    await waitUntil(() async => acks2.isNotEmpty);
    expect(acks2.first.rejected, isFalse);
    expect(acks2.first.success, isTrue);

    final itemsAfter = await cashierDb.getOrderItems(5);
    expect(itemsAfter, hasLength(1), reason: 'the repeat was not inserted again');
    expect(itemsAfter.single.id, 'w1-1');
    final waiterItemsAfter = await waiterDb.getOrderItems(5);
    expect(waiterItemsAfter.single.id, 'w1-1');
    final deliveriesAfter = await waiterDb.getOrderDeliveries();
    expect(deliveriesAfter.single.rejected, isFalse);

    // ===== Phase 5: a captain ordering the same dish again IS a new order =====
    // The other half of the pair, and the one that used to be lost: same dish,
    // same price, rung in separately, so it carries its own id.
    final waiter3 = PosSocketClient(userId: 3, role: 'waiter');
    final acks3 = <AckMessage>[];
    waiter3.onMessage = (msg) {
      if (msg.type == 'ack') acks3.add(AckMessage.fromSyncMessage(msg));
    };
    expect(await waiter3.connect(ip, port: 9877), isTrue);

    final secondRound = [
      OrderItem(
        id: 'w3-1', name: 'کەباب', price: 10000, quantity: 1,
        category: 'گەرمی', createdAt: '2026-01-01T10:05:00', waiterName: 'وەیتەر 2',
      ),
    ];
    waiter3.sendMutation({
      'tableId': 5,
      'items': secondRound.map((e) => e.toMap()).toList(),
      'guestCount': 2,
      'waiterId': '3',
    }, action: 'batchSendAndOccupy');
    await waitUntil(() async => acks3.isNotEmpty);
    expect(acks3.first.success, isTrue);
    expect(acks3.first.rejected, isFalse);

    final finalItems = await cashierDb.getOrderItems(5);
    expect(finalItems, hasLength(2), reason: 'the second round is a real order');
    expect((await cashierDb.getTable(5))!.totalAmount, 20000);
    waiter3.dispose();

    waiter2.dispose();
    disconnectSync();
    await waiterDb.resetForTesting();
    await cashierDb.resetForTesting();
    tmp.deleteSync(recursive: true);
  });
}
