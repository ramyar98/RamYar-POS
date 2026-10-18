import 'dart:async';
import 'dart:io';

/// Loopback port this *install* claims as its "already running" marker.
///
/// The port is derived from the install's own executable directory, not a
/// single machine-wide constant. That is what makes the three-shop test harness
/// in `tools/instances` possible: `inst1`, `inst2` and `inst3` live in
/// different folders, so each derives a different lock and all three can run at
/// once. Two launches of the *same* install still derive the same port and
/// still collide, which is exactly the case the lock exists to stop - a
/// double-clicked exe, or a bat file run twice.
///
/// It is deliberately kept out of the way of the sync (9876) and UDP discovery
/// (9877) ports: the derived range is 49152-53247, inside the private/dynamic
/// range.
const int _lockPortBase = 49152;
const int _lockPortSpan = 4096;

/// The lock port a given executable path would claim. Pure and stable: the
/// same path always maps to the same port, and different paths only collide by
/// chance (1 in 4096).
int instanceLockPortFor(String executablePath) {
  // FNV-1a over the lower-cased directory. Lower-cased because Windows paths
  // are case-insensitive: `C:\Shop` and `c:\shop` are the same install and
  // must map to the same lock.
  final dir = File(executablePath).parent.path.toLowerCase();
  var hash = 0x811c9dc5;
  for (final unit in dir.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return _lockPortBase + (hash % _lockPortSpan);
}

/// The lock port for *this* running copy of the program.
int get instanceLockPort => instanceLockPortFor(Platform.resolvedExecutable);

ServerSocket? _held;

/// Returns `true` when this install is the only copy of itself on this machine.
///
/// A second copy of the same install (double-clicked exe, or a bat file run
/// twice) must not boot: the two instances fight over the sync port, each opens
/// its own SQLite file and whichever loses leaves the other half-initialised.
/// Instead the loser brings the winner's window up front where possible and
/// exits. A *different* install - a second shop, or one of the test instances -
/// gets its own lock and boots normally.
Future<bool> ensureSingleInstance() async {
  try {
    _held = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      instanceLockPort,
    );
    return true;
  } on SocketException {
    return false;
  }
}

/// Best-effort: ask the running copy to show itself. The winner listens on the
/// lock port and treats one received byte as a "raise your window" nudge.
///
/// Duplicate launches are never allowed to terminate the already-running app.
/// Instead, the second copy exits its own startup path after trying to raise the
/// original window, leaving the user in control of when the app closes.
void focusRunningInstance() {
  Socket.connect(
        InternetAddress.loopbackIPv4,
        instanceLockPort,
        timeout: const Duration(seconds: 2),
      )
      .then((socket) {
        socket.add([1]);
        socket.flush();
        socket.destroy();
      })
      .catchError((_) {});
}

bool shouldExitDuplicateInstance() => false;

/// Starts listening for "another copy tried to start" nudges. Returns the
/// callback wired to fire at most once per nudge; wire it to whatever raises
/// the window on the platform.
Stream<void> watchSecondInstanceLaunches() async* {
  final server = _held;
  if (server == null) return;
  yield* server.map((_) {});
}

/// Drops the lock. The OS would do this on process death anyway; explicit
/// just keeps the exit path tidy.
Future<void> releaseInstanceLock() async {
  await _held?.close();
  _held = null;
}
