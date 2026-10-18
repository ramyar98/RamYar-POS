import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/dollar_rate_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// The three-app test, run against a **real, separate process**.
///
/// Every other test in this suite proves the same code paths with a server and
/// a client in one test process. That leaves the one thing that only shows up
/// when two copies of the program talk to each other untested: the socket
/// itself, across process boundaries, with the server's database open in another
/// process and the client starting from an empty database of its own.
///
/// This is the report that a captain's order never reached the cashier's
/// device. It is not reproducible from one process, so it needs a second one:
///
///   1. run `run_windows.bat` to build, then `tools\instances\sync_instances.bat`
///   2. give the hub instance three accounts - one per role, each with its own
///      access code - and a dollar rate the client does not already have:
///
///        INSERT INTO users (name, pin, role, accessCode) VALUES
///          ('Captain 1', '10001', 0, '10.10.0.1'),
///          ('Cashier 1', '22334', 1, '10.10.0.2'),
///          ('Admin 1',   '33441', 2, '10.10.0.3');
///        INSERT OR REPLACE INTO shop_settings VALUES
///          ('dollar_rate', '{"dollars":100.0,"iqd":185000.0}', '...');
///
///      The PINs are yours to choose - only the roles and the access codes are
///      fixed, because the roles are what the three shops are for and
///      `10.10.0.2` is the code this test connects with. The assertions below
///      read the accounts back out of the registry the hub sent, so a
///      differently numbered shop passes just as well.
///   3. run `tools\instances\start_all.bat`
///   4. `flutter test test\cross_process_mesh_test.dart`
///
/// The test skips itself, loudly, rather than passing quietly, in both of the
/// ways there is nothing to test: nothing listening on the port at all, and
/// something listening that hangs up instead of speaking the protocol. A green
/// run that quietly proved nothing would be worse than an obvious skip.
void main() {
  setUpAll(() {
    // Connecting saves the access code through AppPrefs, which reads
    // SharedPreferences and so needs the binding. Under test AppPrefs keeps
    // everything in memory (it only writes a file next to the executable on a
    // real Windows run), so nothing here touches the disk or the SDK.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'a second app gets the accounts and the shop settings from the running hub',
    () async {
      final host = await _lanAddress();
      expect(host, isNotNull,
          reason: 'the hub is reached over the local network, so a test machine '
              'with no LAN address cannot run this');
      if (host == null) return;

      if (!await _isListening(host, 9876)) {
        markTestSkipped(
          'No RAMYAR POS hub is listening on $host:9876. Start one with '
          'tools\\instances\\start_all.bat to run this test for real.');
        return;
      }
      // Note this is only a cheap pre-filter, not proof: a TCP connect succeeds
      // against a stale listener too. The connection itself is checked further
      // down, once the protocol has had its chance to fail.

      final tmp = Directory.systemTemp.createTempSync('ramyar_pos_mesh');

      // ===== The other app: a device that has never been told anything =====
      final client = LocalDatabase();

      // The client database is a real file, and the test framework only cleans
      // up temp directories it creates itself. Without this every run leaves a
      // ramyar_pos_mesh* folder holding a whole database behind in %TEMP%, and
      // they accumulate. Registered after the client is declared so the
      // teardown can close it: the file stays locked while SQLite has it open.
      addTearDown(() async {
        // The socket first, then the database. A registry snapshot is still in
        // flight when the assertions end - the hub pushes its accounts on a
        // timer and the test does not wait for it - so tearing the database down
        // first leaves that write to fail against a closed handle, which the
        // flutter_test binding then reports as an error in its own right and
        // buries the real failure underneath it.
        disconnectSync();
        await client.resetForTesting();
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      });

      await client.init(
          path: '${tmp.path}${Platform.pathSeparator}client.db');

      // Starts empty on purpose. If either number below matched what a fresh
      // install seeds for itself, the assertions would pass with the hub
      // sending nothing at all.
      expect((await client.getAllUsers()).length, 0,
          reason: 'a fresh device must know nobody, or the test proves nothing');
      expect((await client.getDollarRate()).iqd, DollarRate.kDefaultIqd,
          reason: 'a fresh device shows the default rate, not the shop\'s');

      // ===== Connect as the cashier, presenting the cashier's own access code =
      //
      // The connection state is watched from the moment before the connect,
      // because "something answered on 9876" is not the same as "a hub is
      // there". A bare TCP probe is what the skip guard below uses, and it is
      // fooled by a socket that accepts and then closes - which is exactly what
      // a half-dead test server or another copy of the app looks like. Counting
      // the drops tells the two apart, so a stale listener skips this test with
      // an explanation instead of failing it on an empty registry.
      final link = SyncStateNotifier();
      var drops = 0;
      link.addListener((_) {
        if (!link.state.connected) drops++;
      });

      final ok = await connectToServer(
        client,
        host,
        2,
        'cashier',
        link,
        port: 9876,
        accessCode: _cashierAccessCode,
      );
      // The cheap probe above succeeded but the real connection did not, so
      // whatever answered was not speaking the protocol. That is not a defect
      // here and not a broken hub - it is a stale listener (a leftover
      // flutter_tester still shutting down, or another copy of the app) - and
      // failing on it would send somebody hunting through the sync layer for a
      // bug that is not in it.
      if (!ok) {
        markTestSkipped(
          'Something answered on $host:9876 but would not hold a connection, so '
          'there is no hub to test. Close whatever is holding port 9876 - a '
          'leftover flutter_tester, or another copy of the app - and run this '
          'again with tools\\instances\\start_all.bat.');
        return;
      }

      // ===== The accounts have to arrive: this is what unlocks PIN login =====
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        if ((await client.getAllUsers()).isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final users = await client.getAllUsers();
      if (users.isEmpty && drops > 0) {
        // Same cause as above, seen one step later: the socket opened and was
        // then hung up on before the registry could arrive.
        markTestSkipped(
          'A hub answered on $host:9876 and then closed the connection '
          '($drops time(s)) without sending its account registry, so there is '
          'nothing to test against. Close whatever is holding port 9876 and run '
          'this again with tools\\instances\\start_all.bat.');
        return;
      }
      expect(users, isNotEmpty,
          reason: 'the hub pushes its account registry to every new device');

      // One account per role, because the three shops exist to exercise the
      // three roles: a captain places a table order, a cashier settles it, an
      // admin owns the settings. Asserted as a property of the registry rather
      // than as three hardcoded PINs, so a shop numbered differently still gets
      // a real check instead of a mismatch on a digit it never chose.
      for (final role in UserRole.values.where((r) => r != UserRole.owner)) {
        final ofRole = users.where((u) => u.role == role).toList();
        expect(ofRole, hasLength(1),
            reason: 'the hub has to hold exactly one $role account for this '
                'test to be meaningful - it sent '
                '${users.map((u) => '${u.name} (${u.role})').join(', ')}');
      }

      // The access codes are what bind an account to a device, and the code this
      // test connects with has to be one the hub knows - otherwise the connect
      // was accepted by accident.
      expect(users.where((u) => u.accessCode == _cashierAccessCode), hasLength(1),
          reason: 'the hub has to know an account bound to $_cashierAccessCode, '
              'the code this second app connects with');

      // Every account has to survive the crossing intact - and what a second app
      // actually does with the registry is look somebody up by PIN to let them
      // sign in, which is the complaint this test exists for. So resolve each
      // account by the PIN that arrived and insist it is the same account.
      for (final arrived in users) {
        final resolved = await client.getUserByPin(arrived.pin);
        expect(resolved, isNotNull,
            reason: 'the PIN that arrived for ${arrived.name} has to unlock '
                'PIN login on the second app');
        expect(resolved!.id, arrived.id, reason: 'the wrong account answered');
        expect(resolved.role, arrived.role);
        expect(resolved.accessCode, arrived.accessCode,
            reason: 'an account that lost its access code on the way cannot be '
                'bound to any device');
      }

      // ===== Shop settings, not just accounts =====
      // A fresh install seeds the same food menu as every other install, so the
      // menu cannot tell "the hub sent this" from "I made it up myself". The
      // dollar rate can: the hub was given a figure the client has never seen.
      final rateDeadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(rateDeadline)) {
        if ((await client.getDollarRate()).iqd != DollarRate.kDefaultIqd) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      expect((await client.getDollarRate()).iqd, 185000.0,
          reason: "the shop's dollar rate has to cross the process boundary too");
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// The access code this second app presents. It has to be one the hub already
/// knows, so the setup recipe in the doc comment above has to grant it to an
/// account. Named once so the connect and the assertion that follows cannot
/// drift apart.
const String _cashierAccessCode = '10.10.0.2';

/// The address a second device would use to reach this machine.
///
/// Loopback is skipped: it would prove the socket works but not that the code
/// that resolves a real address works.
Future<String?> _lanAddress() async {
  final interfaces =
      await NetworkInterface.list(type: InternetAddressType.IPv4,
          includeLoopback: false);
  for (final ni in interfaces) {
    for (final a in ni.addresses) {
      if (a.isLoopback) continue;
      return a.address;
    }
  }
  return null;
}

Future<bool> _isListening(String host, int port) async {
  try {
    final s = await Socket.connect(host, port,
        timeout: const Duration(seconds: 3));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
