import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app.dart';
import 'core/desktop_sqlite.dart';
import 'core/qa_harness.dart';
import 'core/single_instance.dart';
import 'core/startup_failure.dart';
import 'database/local_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything else, so even a failure during startup is captured. A no-op
  // unless the build was launched with `--dart-define=RAMYAR_QA=true`.
  installQaHarnessIfEnabled();
  // Landscape only: the floor, the bill and the tables are laid out for a wide
  // screen, so the device is pinned to landscape and never turns back to
  // portrait. The Android manifest's `sensorLandscape` is the authoritative
  // lock (it applies before Flutter starts); this keeps it true at runtime too.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await _initialiseAndRun();
}

/// Everything that has to succeed before the first frame, in one place.
///
/// The desktop SQLite implementation is selected before the database is
/// opened because `sqflite` only ships a platform channel implementation
/// for Android, iOS and macOS: on a desktop build its default factory is
/// still the plugin one, so the very first `openDatabase()` raises
/// `MissingPluginException` and the program never gets as far as its first
/// frame. See `core/desktop_sqlite.dart`.
///
/// That step has to be inside the try, and it is the step that fails when
/// a build's native assets are missing: it loads `sqlite3.dll` through FFI,
/// and that throws before anything at all is on screen - which left a
/// release build looking like it simply never started, with no window and
/// no error to read. With it inside, the same failure is reported on the
/// startup error screen instead.
///
/// Retrying just runs the whole thing again, so a database that could not
/// be opened the first time is re-resolved from scratch rather than
/// against a half-initialised factory.
Future<void> _initialiseAndRun() async {
  // A second desktop copy must not boot: two instances race for port 9876
  // and each opens its own SQLite file, so whichever loses the port leaves
  // the winner half-initialised. The lock is a loopback bind the OS releases
  // on process death, so it can never go stale.
  if (!await ensureSingleInstance()) {
    focusRunningInstance();
    return;
  }
  try {
    ensureDesktopDatabaseFactory();
    final localDb = LocalDatabase();
    await localDb.init();
    _startApp(localDb);
  } catch (error) {
    // Without the database there is no app, and a build that throws before
    // its first frame shows the user nothing at all. Say what went wrong and
    // offer to try again.
    runApp(
      StartupFailureApp(
        message: describeStartupFailure(error),
        onRetry: _initialiseAndRun,
      ),
    );
  }
}

void _startApp(LocalDatabase localDb) {
  runApp(
    ProviderScope(
      overrides: [
        // Override the localDbProvider with the initialized database instance
        localDbProvider.overrideWithValue(localDb),
      ],
      child: const RamyarPosAppWrapper(),
    ),
  );
}
