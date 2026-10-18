import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

import 'support/port_guard.dart';

/// End-to-end reproduction of the owner's onboarding flow over real sockets
/// (one Wi-Fi / one router, no internet required):
///  1. the phone (owner client) creates the cashier account with its own IP,
///  2. that account must land in the laptop (server) database,
///  3. the laptop binds the account IP (Connect-page wording) and the
///     cashier's PIN unlocks the login on the laptop.
void main() {
  /// This file's own hub port. It used to be the app's default 9876, which it
  /// shared with two other hub test files: all three probed the port at
  /// startup, all three saw it free, and the loser of the bind race failed
  /// with errno 10048. sync_integration_test keeps 9876 (and proves the
  /// shipping default works); everyone else gets a port of their own.
  const hubPort = 9891;

  // Set once, before anything binds. See support/port_guard.dart for why the
  // timing matters and why this is a skip rather than a failure.
  String? heldPort;
  bool portIsHeld() => heldPort != null;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
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

  late LocalDatabase laptopDb;
  late LocalDatabase phoneDb;
  String? serverIp;
  bool serverUp = false;

  setUp(() async {
    // Nothing to set up when the port is gone: the laptop hub is what these
    // tests are about, and standing it up is the thing that would fail.
    if (portIsHeld()) return;
    SharedPreferences.setMockInitialValues({});
    laptopDb = LocalDatabase();
    await laptopDb.resetForTesting();
    await laptopDb.init(inMemory: true);
    phoneDb = LocalDatabase();
    await phoneDb.resetForTesting();
    await phoneDb.init(inMemory: true);

    final state = SyncStateNotifier();
    serverIp = await startSyncServer(laptopDb, 0, 'owner', state, port: hubPort);
    expect(serverIp, isNotNull,
        reason: 'laptop (server) failed to start on port $hubPort, and the port '
            'was free when this file started');
    serverUp = true;
  });

  tearDown(() async {
    // Nothing was built when the port was gone, so nothing of this file's is
    // left to close.
    if (portIsHeld()) return;
    if (serverUp) disconnectSync();
    await phoneDb.resetForTesting();
    await laptopDb.resetForTesting();
    serverUp = false;
  });

  Future<void> waitUntil(Future<bool> Function() condition,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (await condition()) return;
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for condition');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  hubTest('cashier created on the phone is synced to the laptop and its '
      'IP + PIN login unlocks there', () async {
    // The phone is logged in as the owner (خاوەن سیستەم) and connects to the
    // laptop's server over the router.
    final state = SyncStateNotifier();
    final connected =
        await connectToServer(phoneDb, serverIp!, 0, 'owner', state,
            port: hubPort);
    expect(connected, isTrue,
        reason: 'the phone owner client must connect to the laptop server');

    // The owner creates the cashier account (with its automatic IP) on the
    // phone. USER_CREATED flows over the wire to the laptop.
    await phoneDb.addUser('کاشێر', '22334', UserRole.cashier,
        accessCode: '192.168.8.50');

    // The account must reach the laptop database within the LAN round-trip.
    await waitUntil(() async {
      final users = await laptopDb.getAllUsers();
      return users.any((u) => u.name == 'کاشێر');
    });
    final cashier = (await laptopDb.getAllUsers())
        .firstWhere((u) => u.name == 'کاشێر');
    expect(cashier.pin, '22334');
    expect(cashier.accessCode, '192.168.8.50');
    expect(cashier.role, UserRole.cashier);

    // The phone can now go away - the laptop owns its copy.
    disconnectSync();
    serverUp = false;

    // Laptop: the Connect page binds the cashier's IP. The account is already
    // in the local registry, so the fast path succeeds instantly.
    final state2 = SyncStateNotifier();
    final bound = await connectWithAccountIp(laptopDb, state2, ['192.168.8.50']);
    expect(bound, isTrue,
        reason: 'laptop must bind a code it already knows locally');
    final codes = await getDeviceAccessCodes();
    expect(codes, contains('192.168.8.50'));

    // Laptop: the cashier PIN now unlocks the login.
    final container = ProviderContainer(
      overrides: [localDbProvider.overrideWithValue(laptopDb)],
    );
    addTearDown(container.dispose);
    final auth = container.read(authProvider.notifier);
    final user = await auth.loginWithPin('22334');
    expect(user, isNotNull,
        reason: 'synced cashier with bound IP must log in on the laptop');
    expect(user!.role, UserRole.cashier);
    expect(container.read(loginNoticeProvider).state, isNull);
  });

  hubTest('an account still missing on the laptop stays locked until it is synced',
      () async {
    // Simulate the laptop that never received the account (phone was away when
    // the owner created it): enter the IP on the laptop's Connect page while
    // no server can provide the registry.
    if (serverUp) {
      disconnectSync();
      serverUp = false;
    }
    SharedPreferences.setMockInitialValues({});
    final state2 = SyncStateNotifier();
    final bound = await connectWithAccountIp(laptopDb, state2, ['192.168.8.50']);
    expect(bound, isFalse,
        reason: 'without the synced account the code cannot be unlocked');

    // And the PIN stays locked even though the code was typed.
    final container = ProviderContainer(
      overrides: [localDbProvider.overrideWithValue(laptopDb)],
    );
    addTearDown(container.dispose);
    final auth = container.read(authProvider.notifier);
    expect(await auth.loginWithPin('22334'), isNull,
        reason: 'missing account must never log in');
  });
}