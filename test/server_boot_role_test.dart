import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:ramyar_pos/core/app_prefs.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// The rule that decides whether this device brings the central cashier server
/// up when the app launches.
///
/// A captain's order is worthless if there is nowhere for it to arrive, so the
/// device that used to host the server has to be listening whatever the person
/// in front of it is doing - including nothing at all. The interesting half is
/// the signed-in half, and that is what these pin.
void main() {
  UserModel user(UserRole role) => UserModel(id: 1, name: 'u', pin: '0000', role: role);

  group('shouldStartServerAtBoot', () {
    test('is true with nobody signed in', () {
      // The login and lock screens. A shop does not stop taking orders because
      // the cashier walked away from the till.
      expect(shouldStartServerAtBoot(null), isTrue);
    });

    test('is true for the owner, a cashier and an admin', () {
      for (final role in [UserRole.owner, UserRole.cashier, UserRole.admin]) {
        expect(shouldStartServerAtBoot(user(role)), isTrue,
            reason: 'a $role can run this device as the cashier server');
      }
    });

    test('is false for a captain', () {
      // A captain is a pure client - the device dials the hub and takes orders
      // from tables. Answering as a hub as well would put a second cashier
      // server on the network under a captain's account, and the two would
      // disagree about orders, tables and shifts.
      expect(shouldStartServerAtBoot(user(UserRole.waiter)), isFalse);
    });

    test('is true for a cashier with a closed shift', () {
      // The regression this rule exists for. A restored cashier session with no
      // open shift lands on the welcome screen, which never reaches its own
      // `startSyncServer` because that call waits for a shift - so gating the
      // boot server on "nobody is signed in" left a device explicitly flagged
      // as the server answering on nothing, and every captain's order stopped
      // arriving with nothing in the log.
      //
      // The role is all the rule is given, deliberately: the shift is not known
      // at launch, and the answer must not depend on it.
      expect(shouldStartServerAtBoot(user(UserRole.cashier)), isTrue);
    });
  });

  group('clearServerDevice', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('ramyar_server_role_');
      AppPrefs.debugPlatformFilePath = null;
      AppPrefs.debugFilePath = p.join(temp.path, AppPrefs.fileName);
      AppPrefs.debugReload();
    });

    tearDown(() {
      AppPrefs.debugFilePath = null;
      AppPrefs.debugPlatformFilePath = null;
      AppPrefs.debugReload();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('a captain login clears the server flag a cashier session left behind',
        () async {
      // The phone in the shop was once signed in as the cashier, so it is
      // flagged to host. When a captain signs in on it, that flag must go: the
      // phone is a pure client and follows the cashier, and the boot path must
      // not bring a second restaurant server back up on the next launch.
      await markServerDevice();
      expect(await isServerDevice(), isTrue);

      await clearServerDevice();
      expect(await isServerDevice(), isFalse,
          reason: 'a captain device must not keep answering as the restaurant '
              'server');
    });

    test('clearing is harmless on a device that never hosted', () async {
      expect(await isServerDevice(), isFalse);
      await clearServerDevice();
      expect(await isServerDevice(), isFalse);
    });
  });
}
