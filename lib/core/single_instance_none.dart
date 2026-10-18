/// Web stub for `single_instance_io.dart` (swapped in by the conditional
/// export when `dart:io` is unavailable). A browser tab cannot open a second
/// copy of the local database the way a double-launched desktop exe can, so
/// there is nothing to guard here.
library;

/// Web stub for the per-install lock port. A browser tab cannot open a second
/// copy of the local database, so nothing is keyed off this.
int instanceLockPortFor(String executablePath) => 0;

int get instanceLockPort => 0;

Future<bool> ensureSingleInstance() async => true;

bool shouldExitDuplicateInstance() => false;

void focusRunningInstance() {}

Stream<void> watchSecondInstanceLaunches() async* {}

Future<void> releaseInstanceLock() async {}
