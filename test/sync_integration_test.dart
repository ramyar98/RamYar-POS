import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/services/pos_socket_client.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/services/sync_types.dart';

import 'support/port_guard.dart';

void main() {
  // Set once, before anything binds. See support/port_guard.dart for why the
  // timing matters and why this is a skip rather than a failure.
  String? heldPort;
  bool portIsHeld() => heldPort != null;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    heldPort = await describeHeldPort(9876);
  });

  /// Every test in this file stands up a real hub on the app's own port, so
  /// every test in this file is subject to the same environmental conflict.
  void hubTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (portIsHeld()) {
        markTestSkipped(heldPort!);
        return;
      }
      await body();
    });
  }

  late LocalDatabase serverDb;
  late PosSocketClient waiter1;
  late PosSocketClient waiter2;
  final acks1 = <AckMessage>[];
  final acks2 = <AckMessage>[];
  String? serverIp;

  setUp(() async {
    // Nothing to set up when the port is gone: the hub and the two waiters that
    // depend on it are the whole point of this file.
    if (portIsHeld()) return;
    acks1.clear();
    acks2.clear();
    serverDb = LocalDatabase();
    await serverDb.resetForTesting();
    await serverDb.init(inMemory: true);
    final state = SyncStateNotifier();
    // This file exists to prove the SHIPPING default works, so it binds 9876
    // explicitly (the under-test fallback in startSyncServer keeps other
    // widget tests off the port, not this one).
    serverIp = await startSyncServer(serverDb, 4, 'cashier', state,
        port: 9876);
    expect(serverIp, isNotNull,
        reason: 'Server failed to bind port 9876, and the port was free when '
            'this file started');

    waiter1 = PosSocketClient(userId: 2, role: 'waiter');
    waiter2 = PosSocketClient(userId: 3, role: 'waiter');
    waiter1.onMessage = (msg) {
      if (msg.type == 'ack') acks1.add(AckMessage.fromSyncMessage(msg));
    };
    waiter2.onMessage = (msg) {
      if (msg.type == 'ack') acks2.add(AckMessage.fromSyncMessage(msg));
    };
    expect(await waiter1.connect(serverIp!), isTrue);
    expect(await waiter2.connect(serverIp!), isTrue);
  });

  tearDown(() async {
    // Nothing was built when the port was gone, so nothing of this file's is
    // left to dispose.
    if (portIsHeld()) return;
    waiter1.dispose();
    waiter2.dispose();
    disconnectSync();
    await serverDb.resetForTesting();
    // stop()'s HttpServer.close() releases the port asynchronously; a fresh
    // bind in the next test's setUp can still lose the race and report 10048
    // against this file's own previous hub. Wait it out so a hub exists within
    // this file whenever the environment gave us the port at all.
    await waitForPortFree(9876);
  });

  Map<String, dynamic> orderItem(String id, String name, String createdAt,
          {double price = 10000, int quantity = 1, String waiterName = ''}) =>
      {
        'id': id,
        'name': name,
        'price': price,
        'quantity': quantity,
        'category': 'گەرمی',
        'createdAt': createdAt,
        'waiterName': waiterName,
      };

  void sendOrder(PosSocketClient waiter, int tableId, List<Map<String, dynamic>> items) {
    waiter.sendMutation({
      'tableId': tableId,
      'items': items,
      'guestCount': 1,
      'waiterId': waiter == waiter1 ? '2' : '3',
    }, action: 'batchSendAndOccupy');
  }

  Future<void> waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for condition');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  hubTest('the same batch arriving twice on the wire is not added twice', () async {
    // Two items, sent twice, from two devices. A reconnect flush and a retry
    // both look like this from the hub's side.
    final w1Items = [orderItem('w1-1', 'کەباب', '2026-01-01T10:00:00', waiterName: 'وەیتەر 1')];
    sendOrder(waiter1, 5, w1Items);
    await waitUntil(() => acks1.isNotEmpty);
    expect(acks1.first.rejected, isFalse);
    expect(acks1.first.success, isTrue);
    expect(acks1.first.tableId, 5);

    // The identical batch, same ids, arriving from another device.
    sendOrder(waiter2, 5, [orderItem('w1-1', 'کەباب', '2026-01-01T10:00:00', waiterName: 'وەیتەر 1')]);
    await waitUntil(() => acks2.isNotEmpty);
    // It is not an error: the order genuinely is on the table, so the hub says
    // so rather than reporting a rejection the captain would then chase.
    expect(acks2.first.rejected, isFalse);
    expect(acks2.first.success, isTrue);

    final items = await serverDb.getOrderItems(5);
    expect(items, hasLength(1));
    expect(items.single.id, 'w1-1');
  });

  hubTest('two captains ordering the same dish both get it counted', () async {
    // The case that was being lost: the same dish, the same price, ordered
    // separately by two people at two tables' worth of moments apart. These are
    // two real orders, not a repeated message.
    sendOrder(waiter1, 7, [orderItem('r1', 'کەباب', '2026-01-01T10:00:00', waiterName: 'وەیتەر 1')]);
    await waitUntil(() => acks1.isNotEmpty);
    expect(acks1.first.success, isTrue);

    sendOrder(waiter2, 7, [orderItem('r2', 'کەباب', '2026-01-01T10:05:00', waiterName: 'وەیتەر 2')]);
    await waitUntil(() => acks2.isNotEmpty);
    expect(acks2.first.success, isTrue);
    expect(acks2.first.rejected, isFalse);

    final items = await serverDb.getOrderItems(7);
    expect(items, hasLength(2), reason: 'the second round is a real order too');
    expect((await serverDb.getTable(7))!.totalAmount, 20000);
  });

  hubTest('an earlier timestamp from a slow device never deletes a real order',
      () async {
    // A device whose clock is behind sends a batch that looks older than what is
    // already there. The hub used to treat that as "the other one is stale" and
    // wipe the table. On a till that is money leaving the screen.
    final laterItems = [orderItem('late-1', 'کەباب', '2026-01-01T10:05:00', waiterName: 'وەیتەر 2')];
    sendOrder(waiter2, 6, laterItems);
    await waitUntil(() => acks2.isNotEmpty);
    expect(acks2.first.rejected, isFalse);
    expect(acks2.first.success, isTrue);

    final earlierItems = [orderItem('early-1', 'پیتزا', '2026-01-01T10:00:00', waiterName: 'وەیتەر 1')];
    sendOrder(waiter1, 6, earlierItems);
    await waitUntil(() => acks1.isNotEmpty);
    expect(acks1.first.success, isTrue);
    expect(acks1.first.rejected, isFalse);

    final items = await serverDb.getOrderItems(6);
    expect(items, hasLength(2), reason: 'both orders stand');
    expect(
      items.map((e) => e.id),
      containsAll(<String>['late-1', 'early-1']),
    );
    expect((await serverDb.getTable(6))!.totalAmount, 20000);
  });

  hubTest('later different order appends to existing items', () async {
    final firstItems = [orderItem('a-1', 'کەباب', '2026-01-01T10:00:00', waiterName: 'وەیتەر 1')];
    sendOrder(waiter1, 8, firstItems);
    await waitUntil(() => acks1.isNotEmpty);
    expect(acks1.first.rejected, isFalse);

    final secondItems = [orderItem('b-1', 'پیتزا', '2026-01-01T10:05:00', price: 5000, waiterName: 'وەیتەر 2')];
    sendOrder(waiter2, 8, secondItems);
    await waitUntil(() => acks2.isNotEmpty);
    expect(acks2.first.rejected, isFalse);
    expect(acks2.first.success, isTrue);

    final items = await serverDb.getOrderItems(8);
    expect(items, hasLength(2));
    expect(items.any((i) => i.waiterName == 'وەیتەر 1'), isTrue);
    expect(items.any((i) => i.waiterName == 'وەیتەر 2'), isTrue);
  });

  hubTest('a freshly connecting waiter device receives the current table states as a snapshot', () async {
    // Prepare authoritative states on the cashier/server side first.
    final now = DateTime.now().toIso8601String();
    sendOrder(waiter1, 3, [orderItem('snap-1', 'کەباب', now, waiterName: 'وەیتەر 1')]);
    await waitUntil(() => acks1.isNotEmpty);
    await serverDb.requestBill(3);
    final past = DateTime.now().subtract(const Duration(minutes: 11)).toIso8601String();
    await serverDb.db.update('tables', {'printedAt': past}, where: 'id = ?', whereArgs: [3]);
    await serverDb.checkOverdueTables();
    sendOrder(waiter1, 5, [orderItem('snap-2', 'بیرە', now, waiterName: 'وەیتەر 1')]);
    await waitUntil(() => acks1.length >= 2);

    // Fresh device joins the LAN and connects to the cashier server.
    final freshDb = LocalDatabase();
    await freshDb.resetForTesting();
    await freshDb.init(inMemory: true);
    final state = SyncStateNotifier();
    final ok = await connectToServer(freshDb, serverIp!, 9, 'waiter', state);
    expect(ok, isTrue);

    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (true) {
      final t3 = await freshDb.getTable(3);
      final t5 = await freshDb.getTable(5);
      if (t3 != null && t3.status == TableStatus.overdue &&
          t5 != null && t5.status == TableStatus.occupied) {
        break;
      }
      if (DateTime.now().isAfter(deadline)) fail('Snapshot was not applied on the fresh device');
      await Future.delayed(const Duration(milliseconds: 50));
    }

    expect((await freshDb.getTable(3))!.status, TableStatus.overdue);
    expect((await freshDb.getTable(3))!.sentToCashier, isTrue);
    expect((await freshDb.getTable(5))!.status, TableStatus.occupied);
    expect(await freshDb.getOrderItems(5), hasLength(1));
    expect((await freshDb.getTable(1))!.status, TableStatus.empty);

    disconnectSync();
    await freshDb.resetForTesting();
  });
}
