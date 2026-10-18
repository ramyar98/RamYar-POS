import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/services/pos_socket_client.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/services/sync_types.dart';

import 'support/port_guard.dart';
/// The original complaint, end to end over a real socket: a captain rings food
/// in on their own device and the cashier's till never shows it.
///
/// Each test here covers a way that actually happened.
///
///  * the order was thrown away for looking like a repeat of one already there -
///    the second round of the same dish, which is an ordinary thing to order;
///  * it went out in the moment between the socket opening and the cashier's
///    device being authorised, and the hub discarded it without a word;
///  * two changes to the same table were answered against each other's result,
///    so a change that failed came back as a success;
///  * a change nobody had a handler for was reported as saved.
void main() {
  /// This file's own hub port. It used to be the app's default 9876, which it
  /// shared with two other hub test files: all three probed the port at
  /// startup, all three saw it free, and the loser of the bind race failed with
  /// errno 10048. sync_integration_test keeps 9876 (and proves the shipping
  /// default works); everyone else gets a port of their own.
  const hubPort = 9890;

  // Set once, before anything binds. See support/port_guard.dart for why the
  // timing matters and why this is a skip rather than a failure.
  String? heldPort;
  bool portIsHeld() => heldPort != null;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    heldPort = await describeHeldPort(hubPort);
  });

  /// Every test in this file stands up a real hub, so every test in this file
  /// is subject to the same environmental conflict.
  void hubTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (portIsHeld()) {
        markTestSkipped(heldPort!);
        return;
      }
      await body();
    });
  }

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for the condition');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  late LocalDatabase till;
  late SyncStateNotifier hubState;
  String? hubIp;
  final acks = <AckMessage>[];

  /// A captain's device, already through the handshake.
  Future<PosSocketClient> signedInCaptain() async {
    final captain = PosSocketClient(userId: 2, role: 'waiter')
      ..onMessage = (msg) {
        if (msg.type == 'ack') acks.add(AckMessage.fromSyncMessage(msg));
      };
    addTearDown(captain.dispose);
    expect(await captain.connect(hubIp!, port: hubPort), isTrue);
    await waitUntil(() async => captain.isAuthorized);
    return captain;
  }

  setUp(() async {
    // Nothing to set up when the port is gone: the hub is what every test here
    // needs, and standing it up is the thing that would fail.
    if (portIsHeld()) return;
    acks.clear();
    till = LocalDatabase();
    await till.resetForTesting();
    await till.init(inMemory: true);
    hubState = SyncStateNotifier();
    hubIp = await startSyncServer(till, 4, 'cashier', hubState, port: hubPort);
    expect(hubIp, isNotNull,
        reason: 'the hub must be up for a captain to reach it, and port '
            '$hubPort was free when the file started');
  });

  tearDown(() async {
    if (portIsHeld()) return;
    disconnectSync();
    await till.resetForTesting();
  });

  OrderItem kebab(String id, String at) => OrderItem(
        id: id,
        name: 'کەباب',
        price: 10000,
        quantity: 1,
        category: 'گەرمی',
        createdAt: at,
        waiterName: 'کاپتن 1',
      );

  void sendOrder(PosSocketClient captain, int tableId, List<OrderItem> items) {
    captain.sendMutation({
      'tableId': tableId,
      'items': items.map((e) => e.toMap()).toList(),
      'guestCount': 2,
      'waiterId': '2',
    }, action: 'batchSendAndOccupy');
  }

  hubTest('an order sent the instant the link opens still reaches the till',
      () async {
    final captain = PosSocketClient(userId: 2, role: 'waiter');
    addTearDown(captain.dispose);
    expect(await captain.connect(hubIp!, port: hubPort), isTrue);

    // Straight away, before the hub has had any chance to answer. This is the
    // window that used to swallow the first order of a session: the socket was
    // open, the captain pressed send, and the hub dropped the change because it
    // had not finished checking the device.
    sendOrder(captain, 5, [kebab('impatient-1', '2026-01-01T10:00:00')]);

    await waitUntil(() async => captain.isAuthorized);
    expect(captain.isAuthorized, isTrue,
        reason: 'the hub has to confirm the device, not merely accept the socket');

    await waitUntil(() async => (await till.getOrderItems(5)).isNotEmpty);
    final items = await till.getOrderItems(5);
    expect(items, hasLength(1),
        reason: 'an order held during the handshake must go out, not evaporate');
    expect(items.single.id, 'impatient-1');
    expect((await till.getTable(5))!.totalAmount, 10000);
  });

  hubTest('a captain ordering the same dish twice gets both on the till',
      () async {
    final captain = await signedInCaptain();

    sendOrder(captain, 9, [kebab('round-1', '2026-01-01T10:00:00')]);
    await waitUntil(() async => (await till.getOrderItems(9)).length == 1);

    // The same dish again, ten minutes later: same name, same price, same
    // quantity, and a completely separate order. This is the one that used to
    // be quietly dropped - the hub called it a repeat of what was already there.
    sendOrder(captain, 9, [kebab('round-2', '2026-01-01T10:10:00')]);
    await waitUntil(() async => (await till.getOrderItems(9)).length == 2);

    final items = await till.getOrderItems(9);
    expect(items.map((e) => e.id), containsAll(<String>['round-1', 'round-2']));
    expect((await till.getTable(9))!.totalAmount, 20000,
        reason: 'the total has to count both rounds');
  });

  hubTest('the same batch delivered twice is on the till once', () async {
    final captain = await signedInCaptain();
    final batch = [kebab('repeat-1', '2026-01-01T10:00:00')];

    sendOrder(captain, 11, batch);
    await waitUntil(() async => (await till.getOrderItems(11)).isNotEmpty);

    // A reconnect flush re-sends the very same items, ids and all. That is not
    // a new order and must not become a second one - but it is not a failure
    // either, so the captain is not sent chasing a problem that does not exist.
    acks.clear();
    sendOrder(captain, 11, batch);
    await waitUntil(() async => acks.isNotEmpty);
    expect(acks.first.success, isTrue);
    expect(acks.first.rejected, isFalse);
    expect(await till.getOrderItems(11), hasLength(1));
  });

  hubTest('two changes to the same table are each answered for themselves',
      () async {
    final captain = await signedInCaptain();

    // Seat the table, then immediately send food to it. Both name table 5, and
    // they used to share one key: the second overwrote the first, so one of them
    // was acked with no result at all and came back as a success it never had.
    captain.sendMutation({'tableId': 5, 'waiterId': '2', 'guestCount': 2},
        action: 'occupyTable');
    sendOrder(captain, 5, [kebab('same-table-1', '2026-01-01T10:00:00')]);

    await waitUntil(() async => acks.length >= 2);
    final byAction = <String, AckMessage>{
      for (final ack in acks) ack.originalAction: ack,
    };
    expect(byAction.keys,
        containsAll(<String>['occupyTable', 'batchSendAndOccupy']),
        reason: 'each change needs its own answer');
    for (final ack in byAction.values) {
      expect(ack.success, isTrue, reason: '${ack.originalAction} should be saved');
      expect(ack.rejected, isFalse);
    }
    expect((await till.getOrderItems(5)).single.id, 'same-table-1');
    expect((await till.getTable(5))!.status.index, isNot(0));
  });

  hubTest('a change the hub has no handler for is not reported as saved',
      () async {
    final captain = await signedInCaptain();

    captain.sendMutation({'tableId': 5}, action: 'SOMETHING_NOBODY_HANDLES');
    await waitUntil(() async => acks.isNotEmpty);

    // Acknowledged, but as a failure. The switch used to fall out the bottom
    // silently, so this came back "success" for a change nobody had performed -
    // a printed ticket for an order that was never in the database.
    expect(acks.first.success, isFalse);
    expect(acks.first.rejected, isTrue);
  });
}
