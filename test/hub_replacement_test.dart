import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app_prefs.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/services/network_discovery_service.dart';
import 'package:ramyar_pos/services/pos_socket_server.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

import 'support/port_guard.dart';

/// Replacing the hub must not leave the device serving nothing.
///
/// The server device is started twice in a normal session: once at launch, so
/// captains' orders have somewhere to arrive while the app is still on the login
/// or welcome screen, and again by the cashier's home page once there is a shift
/// to serve. The second call replaces the first.
///
/// The failure this pins is the reason that replacement has to wait: the old
/// `HttpServer` releases its port asynchronously, so a rebind issued immediately
/// loses the race, the bind throws, and - because the old server was already torn
/// down - the device is left with **no** hub at all. On the restaurant's central
/// server that means every captain's order is silently dropped, and the only
/// clue is a bind error about a "shared flag", which reads like a deliberate
/// two-hub configuration rather than the race it is.
void main() {
  // A port of its own, so this test cannot be blocked by, or block, the tests
  // that exercise the real default.
  const port = 9893;

  // Set once, before anything binds.
  String? heldPort;
  bool portIsHeld() => heldPort != null;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    heldPort = await describeHeldPort(port);
  });

  late LocalDatabase db;
  late Directory prefsDir;

  setUp(() async {
    if (portIsHeld()) return;
    prefsDir = Directory.systemTemp.createTempSync('ramyar_hub_');
    AppPrefs.debugPlatformFilePath = null;
    AppPrefs.debugFilePath = p.join(prefsDir.path, AppPrefs.fileName);
    AppPrefs.debugReload();
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    if (portIsHeld()) return;
    disconnectSync();
    await db.resetForTesting();
    AppPrefs.debugFilePath = null;
    AppPrefs.debugPlatformFilePath = null;
    AppPrefs.debugReload();
    if (prefsDir.existsSync()) prefsDir.deleteSync(recursive: true);
  });

  /// A test in this file needs a port of its own, so it is skipped when
  /// something else has already taken it. Checked once, before anything binds -
  /// see support/port_guard.dart.
  void hubTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (portIsHeld()) {
        markTestSkipped(heldPort!);
        return;
      }
      await body();
    });
  }

  hubTest(
    'a second hub replaces the first and keeps the port',
    () async {
      final first = await startSyncServer(db, 4, 'cashier', SyncStateNotifier(),
          port: port);
      expect(first, isNotNull, reason: 'the hub must be up to begin with');

      // The exact call the cashier's home page makes, with nothing in between
      // to let the old socket finish closing.
      final second = await startSyncServer(db, 4, 'cashier', SyncStateNotifier(),
          port: port);
      expect(second, isNotNull,
          reason: 'the replacement hub must bind - losing this race to the old '
              "socket's asynchronous close is the bug being pinned");

      // The one that matters: still listening afterwards. A null from the second
      // call plus a dead port is the shape of the original failure, and it is
      // what the captains would have found.
      final listening = await _isListening(port);
      expect(listening, isTrue,
          reason: 'after replacing the hub the port must still be served - a '
              'device that is the restaurant\'s only hub cannot go quiet');
    },
  );

  hubTest(
    'the port is free again once the sync layer is torn down',
    () async {
      final ip = await startSyncServer(db, 4, 'cashier', SyncStateNotifier(),
          port: port);
      expect(ip, isNotNull);
      disconnectSync();

      // A leftover hub here would make the next start fail the same way, so the
      // teardown has to release the port rather than just drop the reference.
      //
      // `disconnectSync` tears the server down with a fire-and-forget `stop()`
      // (`HttpServer.close()` finishes asynchronously), so a single immediate
      // probe races the close and flaked on the macOS CI runner. The guarantee
      // being pinned is that the port *is* released, not that it is released
      // within one microtask - so poll briefly before failing.
      var released = false;
      for (var i = 0; i < 40 && !released; i++) {
        released = await _isListening(port) == false;
        if (!released) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      expect(released, isTrue,
          reason: 'tearing the sync layer down must release the port');
    },
  );

  hubTest('a captain login tears the central server down and leaves a client',
      () async {
    // A phone that once ran the cashier is flagged to host. When a captain signs
    // in, that device must become a pure client: the old central server goes and
    // its port is released, so the captain follows the cashier instead of
    // answering as a second restaurant server.
    await markServerDevice();
    final syncState = SyncStateNotifier();
    final ip = await startSyncServer(db, 4, 'cashier', syncState, port: port);
    expect(ip, isNotNull,
        reason: 'the hub must be up before the captain logs in');
    expect(await _isListening(port), isTrue);
    expect(syncState.state.connected, isTrue,
        reason: 'a running hub reports itself connected');

    await clearServerDevice(syncState);

    expect(await isServerDevice(), isFalse,
        reason: 'the server flag must not survive a captain login');
    expect(await _isListening(port), isFalse,
        reason: 'a captain device must stop answering as the restaurant server');
    expect(syncState.state.connected, isFalse,
        reason: 'the state must not keep saying online, or the captain skips '
            'dialling the cashier');
    // The port is cleanly free, so the client link (and any later cashier
    // session) can bind it again.
    final probe = await ServerSocket.bind(InternetAddress.anyIPv4, port,
        shared: false);
    await probe.close();
  });

  hubTest('a teardown does not report itself finished before the port is free',
      () async {
    // The property the fix rests on, checked where it is actually decided.
    // [PosSocketServer.stop] asks the old socket to close and moves on;
    // `HttpServer.close()` releases the port asynchronously, so a caller that
    // binds straight away can still lose. [PosSocketServer.stopAndReleasePort]
    // is the version that waits, and it is what the replace-a-hub path uses.
    //
    // The bind below is issued with nothing between it and the end of the
    // teardown, on purpose: the guarantee is about the state at the moment the
    // teardown's future completed, not a moment later when the event loop has
    // had time to finish the close anyway.
    final server = PosSocketServer(userId: 4, role: 'cashier');
    expect(await server.start(port: port), isNotNull,
        reason: 'the hub must be up to tear down');

    await server.stopAndReleasePort();

    final probe = await ServerSocket.bind(InternetAddress.anyIPv4, port,
        shared: false);
    await probe.close();
  });

  test('tearing the discovery service down twice is not a crash', () async {
    // Not the same bug, but found next to it while pinning the one above: the
    // notifiers were written after they had been disposed, which throws out of a
    // path whose only job is to clean up. A second teardown is reachable
    // whenever a hub is replaced and then the sync layer is torn down.
    final discovery = NetworkDiscoveryService();
    discovery.dispose();
    expect(discovery.dispose, returnsNormally,
        reason: 'teardown has to be safe to repeat');
  });
}

/// Whether a hub is actually answering on [port].
///
/// A bind probe, not a connect: the question is whether the port is served, and
/// a connect would also succeed against a socket that is on its way out.
Future<bool> _isListening(int port) async {
  try {
    final probe = await ServerSocket.bind(InternetAddress.anyIPv4, port,
        shared: false);
    await probe.close();
    return false;
  } on SocketException {
    return true;
  }
}
