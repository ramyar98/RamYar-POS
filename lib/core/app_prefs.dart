import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'env.dart';

/// The app's own settings store - language-agnostic key/value settings such as
/// the signed-in user, this device's id, the bound account IPs, the saved server
/// IP, and whether this device hosts the cashier server.
///
/// ## Why not `SharedPreferences` directly on Windows
///
/// `shared_preferences_windows` derives its folder from the executable's version
/// resource, which is `%APPDATA%\com.kalakchi\RAMYAR POS\shared_preferences.json`
/// for every copy of this app on the machine. That has two consequences, and
/// both were real failures:
///
///  * The settings live outside the app's own folder, so a shop that keeps the
///    program in one folder and clears the rest loses the account IPs the
///    workers are bound to. Losing those means *nobody can log in*: the login
///    check refuses any staff PIN whose IP is not in that list, including the
///    owner of the shop.
///  * Every instance on the machine shares one file, and the package reads it
///    with a bare `json.decode` and rewrites it with a truncating write. Two
///    windows open at once can make one of them read a half-written file and
///    throw on startup - which looks exactly like "the app does not work".
///
/// So on Windows this service keeps one file per install, next to the
/// executable, and treats it carefully:
///
///  * **atomic** - writes go to a temporary file and are renamed into place, so
///    a reader never sees a half-written file;
///  * **tolerant** - a damaged file falls back to the previous good copy, and
///    then to no settings, instead of throwing and taking the app down;
///  * **merged** - every write re-reads the file first, so an instance only
///    changes the keys it actually set and cannot wipe another instance's;
///  * **non-destructive** - the old `%APPDATA%` file is imported once so nothing
///    already saved is lost.
///
/// Phones keep using `SharedPreferences`, which is per-app storage there and
/// already behaves. Tests keep using it too, so `setMockInitialValues` still
/// works.
class AppPrefs {
  AppPrefs._();

  static AppPrefs? _instance;
  static AppPrefs get instance => _instance ??= AppPrefs._();

  /// File name used next to the executable. Deliberately not
  /// `shared_preferences.json`, so it can never be confused with - or clash
  /// with - the platform file.
  static const String fileName = 'ramyar_pos_settings.json';

  /// Must match the CompanyName / ProductName in `windows/runner/Runner.rc`,
  /// which is where the platform file lives.
  static const String _vendorFolder = 'com.kalakchi';
  static const String _productFolder = 'RAMYAR POS';

  /// Values held in memory. Only used by the own-file store; the platform
  /// store keeps its own cache.
  final Map<String, Object> _values = <String, Object>{};

  File? _file;
  bool _loaded = false;

  /// Serialises writes so two of them in the same process cannot interleave
  /// their read-merge-write and lose one of the two changes.
  Future<void> _writeTail = Future<void>.value();

  /// True when this device keeps its settings in its own file rather than in the
  /// platform's shared preferences.
  bool get usesOwnStore =>
      debugFilePath != null ||
      (!kIsWeb && Platform.isWindows && !isRunningUnderTest);

  /// Points the own-file store at a specific file, for tests. `null` in a real
  /// build; setting it also forces the own-file store on, so the desktop
  /// behaviour can be exercised anywhere.
  @visibleForTesting
  static String? debugFilePath;

  /// Drops the cached instance so the next call re-reads from disk - which is
  /// what a second copy of the app on the same machine would see.
  @visibleForTesting
  static void debugReload() {
    _instance?.disposeForTesting();
    _instance = null;
  }

  void disposeForTesting() {
    _values.clear();
    _file = null;
    _loaded = false;
  }

  // ---------------------------------------------------------------- reading

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    if (!usesOwnStore) return;
    final target = _resolveFile();
    _file = target;
    _values
      ..clear()
      ..addAll(_readFile(target));
    _importPlatformFileOnce(target);
  }

  /// Prefers the app's own folder, so the settings travel with the program and
  /// two copies of the app never share one file. Falls back to the per-user app
  /// data folder when the program sits somewhere it may not write to, e.g.
  /// `C:\Program Files`.
  File _resolveFile() {
    final override = debugFilePath;
    if (override != null) return File(override);
    var directory = '';
    try {
      directory = p.dirname(Platform.resolvedExecutable);
    } catch (_) {
      // Fall through to the per-user location.
    }
    if (directory.isNotEmpty && _canWriteIn(directory)) {
      return File(p.join(directory, fileName));
    }
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isNotEmpty) {
      return File(p.join(appData, _vendorFolder, _productFolder, fileName));
    }
    return File(fileName);
  }

  static bool _canWriteIn(String directory) {
    try {
      Directory(directory).createSync(recursive: true);
      final probe = File(p.join(directory, '.$fileName.probe'));
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads the current copy, falling back to the previous good one. A settings
  /// file that cannot be read is a nuisance; it must never be the reason the
  /// shop cannot open the till.
  static Map<String, Object> _readFile(File target) {
    for (final candidate in <File>[target, File('${target.path}.bak')]) {
      if (!candidate.existsSync()) continue;
      try {
        final text = candidate.readAsStringSync();
        if (text.trim().isEmpty) continue;
        final decoded = jsonDecode(text);
        if (decoded is Map) return _stripPrefix(decoded.cast<String, Object>());
      } catch (_) {
        // Damaged - try the backup.
      }
    }
    return <String, Object>{};
  }

  /// `shared_preferences` stores everything with a `flutter.` prefix. Only
  /// matters while importing the old platform file.
  static Map<String, Object> _stripPrefix(Map<String, Object> raw) {
    final out = <String, Object>{};
    raw.forEach((key, value) {
      out[_keyWithoutPrefix(key)] = value;
    });
    return out;
  }

  static String _keyWithoutPrefix(String key) =>
      key.startsWith('flutter.') ? key.substring(8) : key;

  /// Settings the app used to keep and no longer reads or writes.
  ///
  /// `ramyar_last_login_role` was the "remember which button you last pressed"
  /// role on the login screen. That control is gone from the screen, so nothing
  /// reads the key any more - but importing it anyway would leave every migrated
  /// install carrying a stale role on disk forever: never read, never updated,
  /// never removed, and impossible for anyone reading the file to explain. It is
  /// dropped at the one moment it would otherwise come back to life.
  ///
  /// Only genuinely dead keys belong here. Anything still in use has to keep
  /// coming across, or a shop would silently lose its IP bindings on upgrade.
  static const Set<String> _retiredKeys = <String>{'ramyar_last_login_role'};

  /// Brings the settings across from the platform file the app used before, the
  /// first time it runs. Runs only when there is no settings file yet, so it can
  /// never overwrite something the shop has since changed.
  void _importPlatformFileOnce(File target) {
    if (target.existsSync()) return;
    final legacy = _platformFile();
    if (legacy == null || !legacy.existsSync()) return;
    try {
      final decoded = jsonDecode(legacy.readAsStringSync());
      if (decoded is! Map) return;
      _values.addAll(
        _stripPrefix(decoded.cast<String, Object>())
          ..removeWhere((key, _) => _retiredKeys.contains(key)),
      );
      _writeNow();
      appLog(
        '[Prefs] Imported existing settings from the previous '
        '${legacy.path} (bound account IPs and server address preserved).',
      );
    } catch (_) {
      // Nothing to import, or the file is damaged. Either way the app starts.
    }
  }

  /// The `shared_preferences` file the app used before it kept its own.
  static File? _platformFile() {
    final override = debugPlatformFilePath;
    if (override != null) return File(override);
    // A test that only redirects the settings file must not pull in whatever
    // happens to be in the real user profile.
    if (debugFilePath != null) return null;
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isEmpty) return null;
    return File(
      p.join(appData, _vendorFolder, _productFolder, 'shared_preferences.json'),
    );
  }

  @visibleForTesting
  static String? debugPlatformFilePath;

  // ---------------------------------------------------------------- writing

  void _writeNow() {
    final target = _file;
    if (target == null) return;
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    try {
      temp.writeAsStringSync(jsonEncode(_values), flush: true);
      if (backup.existsSync()) backup.deleteSync();
      if (target.existsSync()) target.renameSync(backup.path);
      temp.renameSync(target.path);
    } catch (_) {
      // A settings write that fails is worth no more than a log line - the next
      // write tries again, and the previous good copy is still on disk.
      appLog('[Prefs] Could not write ${target.path}');
    }
  }

  /// Re-reads before writing so only the keys this instance actually changed are
  /// applied. Without the re-read, instance A saving its device id would delete
  /// the server flag instance B had just written - the exact failure that made
  /// two copies of this app on one machine fight.
  void _queueWrite() {
    _writeTail = _writeTail
        .then((_) {
          final target = _file;
          if (target == null) return;
          final onDisk = _readFile(target);
          final merged = <String, Object>{...onDisk, ..._values};
          _values
            ..clear()
            ..addAll(merged);
          _writeNow();
        })
        .catchError((Object error) {
          appLog('[Prefs] Settings write skipped: $error');
        });
  }

  // ------------------------------------------------------------------- API

  Future<String?> getString(String key) async {
    if (!usesOwnStore) {
      return (await SharedPreferences.getInstance()).getString(key);
    }
    _ensureLoaded();
    final value = _values[key];
    return value is String ? value : null;
  }

  Future<int?> getInt(String key) async {
    if (!usesOwnStore) {
      return (await SharedPreferences.getInstance()).getInt(key);
    }
    _ensureLoaded();
    final value = _values[key];
    return value is int ? value : null;
  }

  Future<bool?> getBool(String key) async {
    if (!usesOwnStore) {
      return (await SharedPreferences.getInstance()).getBool(key);
    }
    _ensureLoaded();
    final value = _values[key];
    return value is bool ? value : null;
  }

  Future<void> setString(String key, String value) async {
    if (!usesOwnStore) {
      await (await SharedPreferences.getInstance()).setString(key, value);
      return;
    }
    _ensureLoaded();
    _values[key] = value;
    _queueWrite();
  }

  Future<void> setInt(String key, int value) async {
    if (!usesOwnStore) {
      await (await SharedPreferences.getInstance()).setInt(key, value);
      return;
    }
    _ensureLoaded();
    _values[key] = value;
    _queueWrite();
  }

  Future<void> setBool(String key, bool value) async {
    if (!usesOwnStore) {
      await (await SharedPreferences.getInstance()).setBool(key, value);
      return;
    }
    _ensureLoaded();
    _values[key] = value;
    _queueWrite();
  }

  Future<void> remove(String key) async {
    if (!usesOwnStore) {
      await (await SharedPreferences.getInstance()).remove(key);
      return;
    }
    _ensureLoaded();
    _values.remove(key);
    _queueWrite();
  }

  /// Clears the full persisted app state, leaving the application code intact.
  /// On Android/iOS this wipes the platform preferences store; on Windows it
  /// deletes the app's own settings file so the next run behaves like a fresh
  /// install without removing any Flutter code or resources.
  Future<void> clearAll() async {
    if (!usesOwnStore) {
      await (await SharedPreferences.getInstance()).clear();
      return;
    }

    _ensureLoaded();
    _values.clear();

    final target = _file ?? _resolveFile();
    if (target.existsSync()) {
      try {
        target.deleteSync();
      } catch (_) {}
    }
    final backup = File('${target.path}.bak');
    if (backup.existsSync()) {
      try {
        backup.deleteSync();
      } catch (_) {}
    }
    final temp = File('${target.path}.tmp');
    if (temp.existsSync()) {
      try {
        temp.deleteSync();
      } catch (_) {}
    }
  }
}
