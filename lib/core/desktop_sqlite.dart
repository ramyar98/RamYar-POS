import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'env.dart';

/// Whether the desktop build has to select the FFI SQLite implementation
/// itself.
///
/// `sqflite` ships a platform channel implementation for Android, iOS and macOS
/// only. Everywhere else the global database factory is never set, and the
/// first call to `openDatabase` throws
/// `Bad state: databaseFactory not initialized` - which, at startup, means the
/// program opens a window that never fills in. Windows, Linux and a macOS build
/// from source therefore have to install the FFI implementation before the first
/// database is opened.
///
/// Android is deliberately excluded: the platform channel is the correct and
/// fastest implementation there.
bool get needsDesktopDatabaseFactory {
  if (kIsWeb) return false;
  try {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  } catch (_) {
    // No dart:io (web): there is no desktop factory to pick either.
    return false;
  }
}

/// Installs the desktop SQLite implementation, if this platform needs one.
///
/// Two separate steps, and both are needed:
///  - `sqfliteFfiInit()` loads the SQLite library. On Windows that is a DLL
///    which has to be located and opened by hand, and it has to happen before
///    the first query.
///  - assigning `databaseFactory` is what actually points the global
///    `openDatabase` at the FFI implementation. `sqfliteFfiInit()` on its own
///    does NOT do this, which is what made a release build open a window and
///    then stop dead.
///
/// Safe to call more than once and from anywhere before the database is opened.
/// Returns whether a working factory is in place afterwards.
bool ensureDesktopDatabaseFactory() {
  if (!needsDesktopDatabaseFactory) return isDesktopDatabaseFactoryReady;
  sqfliteFfiInit();
  // The default FFI factory runs its queries in a background isolate, which is
  // the right thing for a program: a slow query cannot freeze the UI. A
  // `flutter test` process is different - a spawned isolate outlives the test
  // that made it and the binding fails the test as "pending timer", so tests
  // get the no-isolate factory instead. The queries here are local SQLite on a
  // local disk, so the two behave the same.
  databaseFactory =
      isRunningUnderTest ? databaseFactoryFfiNoIsolate : databaseFactoryFfi;
  return isDesktopDatabaseFactoryReady;
}

/// Whether an FFI implementation is the active database factory.
///
/// Read through the public `databaseFactory` getter, which deliberately throws
/// when nothing has been installed yet - that is the state being diagnosed, and
/// a caller asking "is a working factory in place?" has to be able to ask it
/// before there is one. Checked by identity against the two FFI factories,
/// since the package exposes no public type to test for.
bool get isDesktopDatabaseFactoryReady {
  try {
    return identical(databaseFactory, databaseFactoryFfi) ||
        identical(databaseFactory, databaseFactoryFfiNoIsolate);
  } catch (_) {
    // "databaseFactory not initialized" - nothing is installed yet.
    return false;
  }
}
