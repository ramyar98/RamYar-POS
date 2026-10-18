import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One shared answer to a question a few test files keep asking: *can this
/// machine give me the port this test's hub needs?*
///
/// ## Why it is asked at all
///
/// The hub tests used to all bind **9876** - the same port the app itself
/// uses, deliberately, because the point of them is that the shipping default
/// works. Three files doing that at once is a bind race: each probes the port
/// in `setUpAll`, each sees it free, and whichever process binds second fails
/// with errno 10048. That race is why the files were split onto ports of their
/// own (`captain_to_cashier_test` 9890, `cross_device_login_test` 9891, and so
/// on); only `sync_integration_test` still holds 9876, so exactly one file in
/// the suite proves the shipping default and no two files can fight over it.
///
/// What is left here is the conflict this suite cannot schedule away - a
/// holder from *outside* the test process:
///
///  * a RAMYAR POS window left open by `tools\instances\start_all.bat`;
///  * another `flutter test` or `flutter run` of this project;
///  * a hub from a previous test file that has not finished exiting.
///
/// `startSyncServer` answers a taken port by returning `null`, and the test then
/// fails on `expect(ip, isNotNull, reason: 'the hub must be up ...')`. That
/// message blames the sync layer for something the environment did, and the real
/// cause - errno 10048, printed by a server in a different process - is several
/// lines further up the log. A busy port is not a defect in this code.
///
/// A test whose port was taken is **skipped**, not failed, and it says why.
///
/// ## When to ask
///
/// In `setUpAll`, before anything binds - and that timing is the whole trick. A
/// check placed in the test body is useless here, because the file's own `setUp`
/// has already stood the hub up by then and the port is busy with *this test's
/// own socket*: the guard reports a conflict against itself, skips, and takes
/// the database down underneath the next test. The first version did exactly
/// that, and it turned one busy port into a cascade of `database_closed`
/// failures across the file.
///
/// `markTestSkipped` also does not unwind anything - it records the skip and
/// lets the caller carry on. So the `return` after it is load-bearing, and the
/// `setUp` that binds has to check the answer as well as the test body.
Future<String?> describeHeldPort(int port) async {
  try {
    final probe = await ServerSocket.bind(InternetAddress.anyIPv4, port,
        shared: false);
    await probe.close();
    return null;
  } on SocketException {
    return 'Port $port is already in use, so this test cannot stand up its hub. '
        'Something outside the test is holding it - a RAMYAR POS window from '
        'tools\\instances\\start_all.bat, another flutter run of this project, or '
        'a hub from the previous test file that has not finished exiting. Close '
        'it and run again. On Windows, to see who: '
        'Get-NetTCPConnection -LocalPort $port -State Listen';
  }
}

/// Waits (bounded) until [port] can be bound again.
///
/// A hub's `HttpServer.close()` hands the port back asynchronously, so a hub
/// test that tears one server down and stands the next up immediately can race
/// its own previous socket and read errno 10048 for a port nothing outside
/// wants. Polling the bind until it succeeds (or the timeout expires) lets a
/// file that owns a hub port run its consecutive tests deterministically.
Future<void> waitForPortFree(
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final probe =
          await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: false);
      await probe.close();
      return;
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  throw StateError('Port $port never became free within $timeout');
}
