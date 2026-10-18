export 'single_instance_none.dart'
    if (dart.library.io) 'single_instance_io.dart';

/// Duplicate-launch policy for desktop installs.
///
/// A second copy of the same install is treated as a request to focus the
/// already-running app, not as a reason to kill the active process. This keeps
/// the software open until the user intentionally exits it and avoids the
/// destructive `exit(0)` path.
bool shouldExitDuplicateInstance() => false;
