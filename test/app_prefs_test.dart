import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ramyar_pos/core/app_prefs.dart';

/// These tests cover the settings store that replaced `SharedPreferences` on
/// Windows.
///
/// The two failures they exist for were both real and both looked like "the
/// app stopped working":
///
///  * the settings lived in `%APPDATA%`, outside the program, so clearing
///    everything else lost the account IPs staff are bound to - and with those
///    gone the login check refuses every PIN, including the owner's;
///  * every copy of the app on the machine shared that one file, and the package
///    read it with a bare `json.decode` while rewriting it with a truncating
///    write, so two windows open together could make one of them throw on
///    startup.
void main() {
  late Directory temp;
  late String settingsPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ramyar_prefs_');
    settingsPath = p.join(temp.path, AppPrefs.fileName);
    AppPrefs.debugPlatformFilePath = null;
    AppPrefs.debugFilePath = settingsPath;
    AppPrefs.debugReload();
  });

  tearDown(() {
    AppPrefs.debugFilePath = null;
    AppPrefs.debugPlatformFilePath = null;
    AppPrefs.debugReload();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('a value written is read back', () async {
    await AppPrefs.instance.setString('ramyar_pos_server_ip', '192.168.8.97');
    expect(
      await AppPrefs.instance.getString('ramyar_pos_server_ip'),
      '192.168.8.97',
    );
  });

  test(
    'settings land in the app\'s own folder, not the user profile',
    () async {
      await AppPrefs.instance.setBool('ramyar_pos_is_server_device', true);
      expect(File(settingsPath).existsSync(), isTrue);
      // Nothing was written next to the executable's platform prefs.
      expect(
        AppPrefs.instance.usesOwnStore,
        isTrue,
        reason: 'a Windows install must keep its own file',
      );
    },
  );

  test('a damaged settings file does not stop the app - it falls back to the '
      'previous good copy', () async {
    await AppPrefs.instance.setString(
      'device_access_codes',
      '["192.168.8.31"]',
    );
    await AppPrefs.instance.setString('ramyar_pos_server_ip', '192.168.8.97');
    // Give the queued write a chance to land, then truncate the live file the
    // way a half-finished write would.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    File(settingsPath).writeAsStringSync('{"ramyar_pos_server_ip": "192.16');

    // A second copy of the app opens on the same folder.
    AppPrefs.debugReload();
    expect(
      await AppPrefs.instance.getString('device_access_codes'),
      '["192.168.8.31"]',
      reason: 'the backup copy carries the last good values',
    );
  });

  test(
    'a settings file that is damaged beyond recovery yields defaults instead '
    'of throwing',
    () async {
      File(settingsPath).writeAsStringSync('not json at all');
      AppPrefs.debugReload();
      expect(await AppPrefs.instance.getString('anything'), isNull);
      // And it can still be written to, so the shop is not stuck.
      await AppPrefs.instance.setString('ramyar_pos_server_ip', '192.168.8.97');
      expect(
        await AppPrefs.instance.getString('ramyar_pos_server_ip'),
        '192.168.8.97',
      );
    },
  );

  test('two copies of the app do not wipe each other\'s settings', () async {
    // Copy 1 - the hub - marks itself as the server device.
    await AppPrefs.instance.setBool('ramyar_pos_is_server_device', true);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // Copy 2, same folder, starts later and saves its own device id without
    // having seen copy 1's flag.
    AppPrefs.debugReload();
    await AppPrefs.instance.setString('ramyar_pos_device_id', 'copy-two');
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // Copy 1 looks again: its flag is still there, and copy 2's id arrived.
    AppPrefs.debugReload();
    expect(
      await AppPrefs.instance.getBool('ramyar_pos_is_server_device'),
      isTrue,
      reason: 'copy 2 must not have deleted copy 1\'s server flag',
    );
    expect(
      await AppPrefs.instance.getString('ramyar_pos_device_id'),
      'copy-two',
    );

    // The real fix for the collision: each copy now has its own folder, so each
    // keeps its own device id - which is what tells their registry messages
    // apart on the wire.
    final other = Directory.systemTemp.createTempSync('ramyar_prefs2_');
    addTearDown(() => other.deleteSync(recursive: true));
    AppPrefs.debugFilePath = p.join(other.path, AppPrefs.fileName);
    AppPrefs.debugReload();
    await AppPrefs.instance.setString('ramyar_pos_device_id', 'copy-one');
    expect(
      await AppPrefs.instance.getString('ramyar_pos_device_id'),
      'copy-one',
    );
    expect(
      File(settingsPath).existsSync(),
      isTrue,
      reason: 'copy 1 keeps its own folder untouched',
    );
  });

  test('the settings the app used before are carried across once', () async {
    // The shop's existing file, in the format `shared_preferences` wrote.
    final legacy = File(p.join(temp.path, 'shared_preferences.json'))
      ..writeAsStringSync(
        jsonEncode({
          'flutter.device_access_code': '192.168.153.218',
          'flutter.device_access_codes': '["192.168.153.218"]',
          'flutter.ramyar_pos_is_server_device': true,
          'flutter.ramyar_pos_device_id': 'hmmxd7015f-ftrmco',
          'flutter.loggedUserId': 8,
        }),
      );
    AppPrefs.debugPlatformFilePath = legacy.path;
    AppPrefs.debugReload();

    expect(
      await AppPrefs.instance.getString('device_access_code'),
      '192.168.153.218',
      reason: 'the `flutter.` prefix has to come off',
    );
    expect(
      await AppPrefs.instance.getBool('ramyar_pos_is_server_device'),
      isTrue,
    );
    expect(await AppPrefs.instance.getInt('loggedUserId'), 8);

    // Once written into the app's own file, a change there is never undone by
    // the old one.
    await AppPrefs.instance.setString('device_access_code', '192.168.8.31');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    AppPrefs.debugReload();
    expect(
      await AppPrefs.instance.getString('device_access_code'),
      '192.168.8.31',
    );
  });

  test('a setting the app no longer uses is not brought across', () async {
    // `ramyar_last_login_role` was the role button the login screen used to
    // remember. The button is gone, so nothing reads the key - but the old file
    // still has one on it, and importing it verbatim would leave every migrated
    // install carrying a role that nothing will ever read, update or clear.
    final legacy = File(p.join(temp.path, 'shared_preferences.json'))
      ..writeAsStringSync(
        jsonEncode({
          'flutter.device_access_code': '192.168.153.218',
          'flutter.ramyar_last_login_role': 'waiter',
        }),
      );
    AppPrefs.debugPlatformFilePath = legacy.path;
    AppPrefs.debugReload();

    expect(
      await AppPrefs.instance.getString('device_access_code'),
      '192.168.153.218',
      reason: 'a setting still in use has to survive the migration',
    );
    expect(
      await AppPrefs.instance.getString('ramyar_last_login_role'),
      isNull,
      reason: 'a retired setting must not come back to life on disk',
    );
  });

  test('a removed key stays removed across a restart', () async {
    await AppPrefs.instance.setString('loggedUserId', '8');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await AppPrefs.instance.remove('loggedUserId');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    AppPrefs.debugReload();
    expect(await AppPrefs.instance.getInt('loggedUserId'), isNull);
  });

  test('clearAll removes every persisted setting from the app store', () async {
    await AppPrefs.instance.setString('ramyar_pos_server_ip', '192.168.8.97');
    await AppPrefs.instance.setString(
      'device_access_codes',
      '["192.168.8.31"]',
    );
    await AppPrefs.instance.setInt('loggedUserId', 8);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    await AppPrefs.instance.clearAll();

    expect(await AppPrefs.instance.getString('ramyar_pos_server_ip'), isNull);
    expect(await AppPrefs.instance.getString('device_access_codes'), isNull);
    expect(await AppPrefs.instance.getInt('loggedUserId'), isNull);
    expect(
      File(settingsPath).existsSync(),
      isFalse,
      reason: 'the app settings file itself must be wiped for a clean start',
    );
  });

  test('a write never leaves a half-written file behind', () async {
    await AppPrefs.instance.setString('ramyar_pos_server_ip', '192.168.8.97');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // Whatever is on disk must be complete, parseable JSON.
    final text = File(settingsPath).readAsStringSync();
    expect(jsonDecode(text), isA<Map<String, dynamic>>());
    // And the temporary file used for the swap is not left on disk.
    expect(File('$settingsPath.tmp').existsSync(), isFalse);
  });
}
