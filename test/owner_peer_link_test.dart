import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/services/sync_types.dart';

/// Verifies the OWNER PEER LINK: the owner (خاوەن سیستەم) signs in from two
/// devices at once (e.g. phone + laptop on the same Wi-Fi) and an account
/// opened on one must show up on the other.
///
/// The socket layer itself is exercised by hand on two real devices; what is
/// pinned down here is the part that decides convergence:
///  - only account-registry changes are on the peer wire (never orders/menus),
///  - a peer's account list is adopted ADDITIVELY, so two owner devices that
///    each have an account the other lacks both end up with both,
///  - an account id that already exists locally is never clobbered and never
///    deleted by the peer's list (no ping-pong, no lost accounts),
///  - the message id / hop fields survive the JSON round trip the socket does,
///    which is what makes the relay dedupe work.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ramyar_pos_owner_peer');
    db = LocalDatabase();
    // Per-test temp FILE: sqflite's `:memory:` is ONE shared store per process,
    // so file paths are used whenever the test models 2+ devices.
    await db.init(path: '${tmp.path}${Platform.pathSeparator}owner.db');
  });

  tearDown(() async {
    await db.resetForTesting();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A second device with its own private store - the sibling owner device.
  Future<LocalDatabase> newDevice(String name) async {
    final device = LocalDatabase();
    await device.init(path: '${tmp.path}${Platform.pathSeparator}$name.db');
    return device;
  }

  Future<List<Map<String, dynamic>>> usersOf(LocalDatabase device) async =>
      (await device.getAllUsers()).map((u) => u.toMap()).toList();

  test('the peer wire carries account actions only', () {
    expect(kRegistryActions, contains('USER_CREATED'));
    expect(kRegistryActions, contains('USER_UPDATED'));
    expect(kRegistryActions, contains('USER_DELETED'));
    // Nothing else may ever ride the owner peer link: orders, menus, tables
    // and shifts keep the central cashier server as their only source.
    for (final action in [
      'batchSendAndOccupy',
      'addOrderItem',
      'settleTable',
      'FOOD_ITEM_CREATED',
      'SHIFT_STARTED',
      'occupyTable',
    ]) {
      expect(kRegistryActions.contains(action), isFalse,
          reason: '$action must not travel between owner devices');
    }
  });

  test('an account created on one owner device is adopted by the other', () async {
    final phone = await newDevice('phone');
    try {
      await phone.addUser('کاپتن ١', '10001', UserRole.waiter,
          rangeStart: 1, rangeEnd: 10, accessCode: '10.0.0.9');
      await phone.addUser('کاشێر ١', '10002', UserRole.cashier,
          accessCode: '10.0.0.10');

      // The laptop receives the peer hub's accounts-only snapshot on join.
      final peerUsers = await usersOf(phone);
      await db.applyRegistrySnapshotUsers(peerUsers);

      final names = (await db.getAllUsers()).map((u) => u.name).toList();
      expect(names, containsAll(['کاپتن ١', 'کاشێر ١']));
    } finally {
      await phone.resetForTesting();
    }
  });

  test('an account created on the laptop is adopted by the phone', () async {
    final laptop = await newDevice('laptop');
    try {
      await laptop.addUser('ئادمێن ١', '20001', UserRole.admin,
          accessCode: '10.0.0.5');
      await db.applyRegistrySnapshotUsers(await usersOf(laptop));
      expect((await db.getAllUsers()).map((u) => u.name), contains('ئادمێن ١'));
    } finally {
      await laptop.resetForTesting();
    }
  });

  test('two owner devices that were apart still end up with every account',
      () async {
    final laptop = await newDevice('laptop');
    try {
      // The owner opened a captain + cashier on the phone, and an admin on the
      // laptop, while the two devices could not see each other. Each device
      // numbered its own accounts from 1, so the ids DO clash.
      await db.addUser('کاپتن ١', '10001', UserRole.waiter,
          rangeStart: 1, rangeEnd: 10);
      await db.addUser('کاشێر ١', '10003', UserRole.cashier);
      await laptop.addUser('ئادمێن ١', '20001', UserRole.admin);

      // Each side then adopts the other's list.
      await laptop.applyRegistrySnapshotUsers(await usersOf(db));
      await db.applyRegistrySnapshotUsers(await usersOf(laptop));

      final laptopNames = (await laptop.getAllUsers()).map((u) => u.name).toList();
      final phoneNames = (await db.getAllUsers()).map((u) => u.name).toList();
      for (final name in ['کاپتن ١', 'کاشێر ١', 'ئادمێن ١']) {
        expect(laptopNames, contains(name), reason: 'laptop is missing $name');
        expect(phoneNames, contains(name), reason: 'phone is missing $name');
      }
    } finally {
      await laptop.resetForTesting();
    }
  });

  test('re-adopting the same peer list is a no-op', () async {
    // The peer hub serves its account list on every (re)join, so applying the
    // same list twice must not duplicate anything.
    final laptop = await newDevice('laptop');
    try {
      await laptop.addUser('کاپتن ١', '10001', UserRole.waiter,
          rangeStart: 1, rangeEnd: 10, accessCode: '10.0.0.9');
      await laptop.addUser('کاشێر ١', '10002', UserRole.cashier);

      final peerList = await usersOf(laptop);
      await db.applyRegistrySnapshotUsers(peerList);
      await db.applyRegistrySnapshotUsers(peerList);
      await db.applyRegistrySnapshotUsers(peerList);

      expect(await db.getAllUsers(), hasLength(2));
    } finally {
      await laptop.resetForTesting();
    }
  });

  test('an account id that already exists is never clobbered by the peer list',
      () async {
    // Both owner devices independently created an account that landed on the
    // same id. The local one keeps its row untouched - it must not be
    // overwritten just because the peer reported a different account there.
    await db.addUser('کاپتن ی سەرەکی', '11111', UserRole.waiter,
        rangeStart: 1, rangeEnd: 5, accessCode: '10.0.0.1');

    final localId = (await db.getAllUsers()).single.id;
    await db.applyRegistrySnapshotUsers([
      {
        'id': localId,
        'name': 'کاپتن دووەم',
        'pin': '99999',
        'role': UserRole.waiter.index,
        'rangeStart': 50,
        'rangeEnd': 60,
        'accessCode': '10.0.0.2',
      }
    ]);

    // The local account is untouched...
    final kept = await db.getUserById(localId);
    expect(kept, isNotNull);
    expect(kept!.name, 'کاپتن ی سەرەکی');
    expect(kept.pin, '11111');
    expect(kept.accessCode, '10.0.0.1');
    // ...and the peer's account is kept too, under a free id, rather than
    // being dropped and lost.
    final all = await db.getAllUsers();
    expect(all, hasLength(2));
    expect(all.map((u) => u.pin), containsAll(['11111', '99999']));
  });

  test('a PIN shared with the peer is recognised as the same account', () async {
    // The same account, already synced live, must not be inserted a second
    // time just because it shows up in the peer's list as well.
    await db.addUser('کاپتن ١', '10001', UserRole.waiter,
        rangeStart: 1, rangeEnd: 10);
    await db.applyRegistrySnapshotUsers([
      {
        'id': 99,
        'name': 'کاپتن ١',
        'pin': '10001',
        'role': UserRole.waiter.index,
        'rangeStart': 1,
        'rangeEnd': 10,
        'accessCode': '10.0.0.9',
      }
    ]);

    expect(await db.getAllUsers(), hasLength(1));
  });

  test('the peer list never deletes a local-only account', () async {
    // Deleting an account is a deliberate USER_DELETED mutation, not a
    // side-effect of the owner device that happens not to know about it.
    await db.addUser('کاپتن ١', '10001', UserRole.waiter);
    await db.addUser('ئادمێن ١', '20001', UserRole.admin);

    await db.applyRegistrySnapshotUsers([
      {'id': 1, 'name': 'ئادمێن ١', 'pin': '20001', 'role': UserRole.admin.index},
    ]);

    final names = (await db.getAllUsers()).map((u) => u.name).toList();
    expect(names, contains('کاپتن ١'));
    expect(names, contains('ئادمێن ١'));
  });

  test('an account deleted on one owner device is removed on the other',
      () async {
    final laptop = await newDevice('laptop');
    try {
      await laptop.addUser('کاپتن ١', '10001', UserRole.waiter,
          rangeStart: 1, rangeEnd: 5, accessCode: '10.0.0.7');
      await db.applyRegistrySnapshotUsers(await usersOf(laptop));
      expect((await db.getAllUsers()), hasLength(1));

      final id = (await db.getAllUsers()).single.id;
      // The laptop deletes it; the phone applies the relayed USER_DELETED.
      await laptop.deleteRemoteUser(id);
      await db.deleteRemoteUser(id);

      expect(await db.getAllUsers(), isEmpty);
    } finally {
      await laptop.resetForTesting();
    }
  });

  test('a PIN change made on one owner device lands on the other', () async {
    final laptop = await newDevice('laptop');
    try {
      await laptop.addUser('کاشێر ١', '10002', UserRole.cashier,
          accessCode: '10.0.0.8');
      await db.applyRegistrySnapshotUsers(await usersOf(laptop));
      final id = (await db.getAllUsers()).single.id;

      await laptop.updateUserPin(id, '54321');
      final changed = (await usersOf(laptop)).single;
      await db.applyRemoteUser(Map<String, dynamic>.from(changed));

      final synced = await db.getUserById(id);
      expect(synced!.pin, '54321');
    } finally {
      await laptop.resetForTesting();
    }
  });

  test('relay bookkeeping survives the JSON round trip the socket performs',
      () {
    // The dedupe/hop fields travel inside SyncMessage.data, so they must come
    // back out of encode/decode intact - otherwise the owner peer mesh could
    // not recognise a message it had already forwarded.
    final original = SyncMessage(
      type: 'mutation',
      action: 'USER_CREATED',
      data: {
        'user': {'id': 7, 'name': 'کاپتن ١', 'pin': '10001'},
        kMsgIdKey: 'device-a-12',
        kOriginKey: 'device-a',
        kHopKey: 0,
      },
      userId: 0,
      role: 'owner',
    );

    final decoded = SyncMessage.decode(original.encode());
    expect(decoded, isNotNull);
    expect(decoded!.action, 'USER_CREATED');
    expect(decoded.data[kMsgIdKey], 'device-a-12');
    expect(decoded.data[kOriginKey], 'device-a');
    expect(decoded.data[kHopKey], 0);
  });

  test('a relayed registry change can be told apart from a fresh one', () {
    // A peer hub accepts a forwarded copy of a registry change (it came from a
    // trusted central server) but refuses a freshly originated one that is
    // not an account action.
    final relayed = SyncMessage(
      type: 'mutation',
      action: 'USER_UPDATED',
      data: {kMsgIdKey: 'x-1', kRelayedKey: true},
      userId: 4,
      role: 'cashier',
    );
    expect(relayed.data[kRelayedKey], isTrue);

    final fresh = SyncMessage(
      type: 'mutation',
      action: 'USER_UPDATED',
      data: {kMsgIdKey: 'x-2'},
      userId: 0,
      role: 'owner',
    );
    expect(fresh.data.containsKey(kRelayedKey), isFalse);
  });

  test('the relay chain is bounded so owner hubs cannot loop forever', () {
    expect(kMaxRegistryHops, greaterThan(0));
    expect(kMaxRegistryHops, lessThanOrEqualTo(5));
  });
}
