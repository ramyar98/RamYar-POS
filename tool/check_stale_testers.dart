// Detects (and optionally kills) the leftover processes that keep this
// project's build folder locked and make the next `flutter test` or
// `flutter run` crash with:
//
//   PathAccessException: Deletion failed, path = '...sqlite3.dll.moved'
//   (OS Error: Access is denied, errno = 5)
//
// Two kinds of process can hold the lock:
//
//  * a leftover `flutter_tester` - an orphan whose test suite already ended
//    (most often because a test left a sync server / UDP isolate alive);
//    one alive longer than [maxAge] cannot belong to a running suite (a whole
//    `flutter test` here finishes in ~2 minutes);
//  * the running POS app itself (`ramyar_pos.exe`) - it has the built
//    sqlite3.dll loaded, so the tool cannot rebuild that folder until it
//    exits. A DEBUG app is assumed disposable and killed; a --release app
//    belongs to the shop and is only reported.
//
// Usage:
//   dart tool/check_stale_testers.dart                        # report only
//   dart tool/check_stale_testers.dart --kill                 # kill orphans
//   dart tool/check_stale_testers.dart --kill --max-age=120   # age in seconds
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final shouldKill = args.contains('--kill');
  final ageArg = args.firstWhere(
    (a) => a.startsWith('--max-age='),
    orElse: () => '--max-age=600',
  );
  final maxAge = Duration(seconds: int.parse(ageArg.split('=').last));

  final json = _runPowerShell(
    'Get-Process -Name flutter_tester,ramyar_pos -ErrorAction SilentlyContinue '
    '| Select-Object Id, Name, StartTime, Path | ConvertTo-Json -Compress',
  );
  final stale = <int>[];
  final blockers = <String>[];
  for (final p in _decodeList(json)) {
    final pid = (p['Id'] as num?)?.toInt() ?? 0;
    final name = '${p['Name']}';
    if (pid <= 0) continue;
    if (name == 'ramyar_pos') {
      // The live restaurant app: a release build stays open on purpose, a
      // debug one is a leftover from a dev session and blocks every build.
      final path = '${p['Path']}';
      final isRelease = path.toLowerCase().contains('release');
      if (isRelease) {
        blockers.add('ramyar_pos.exe (pid $pid, RELEASE - close it by hand)');
      } else {
        blockers.add('ramyar_pos.exe (pid $pid, debug)');
        if (shouldKill) stale.add(pid);
      }
      continue;
    }
    final created = DateTime.tryParse('${p['StartTime']}');
    if (created == null) continue;
    final age = DateTime.now().difference(created.toLocal());
    if (age > maxAge) {
      blockers.add('flutter_tester.exe (pid $pid, age ${age.inMinutes} min)');
      stale.add(pid);
    }
  }

  if (blockers.isEmpty) {
    stdout.writeln('OK: nothing is holding build/ - tests and builds can run.');
    exitCode = 0;
    return;
  }
  stdout.writeln('Processes locking build/:');
  for (final b in blockers) {
    stdout.writeln('  - $b');
  }
  if (!shouldKill) {
    stdout.writeln('Run again with --kill to terminate the killable ones.');
    exitCode = 1;
    return;
  }
  if (stale.isEmpty) {
    stdout.writeln('Nothing killable - close the listed app(s) by hand.');
    exitCode = 1;
    return;
  }
  var failed = false;
  for (final pid in stale) {
    final res = Process.runSync('taskkill', ['/F', '/PID', '$pid']);
    final out = (res.stdout as String).trim();
    final err = (res.stderr as String).trim();
    stdout.writeln(out.isEmpty ? err : out);
    if (res.exitCode != 0) failed = true;
  }
  // Windows keeps the file lock for a moment after the handle is released.
  sleep(const Duration(milliseconds: 500));
  exitCode = failed ? 1 : 0;
}

String _runPowerShell(String script) {
  final res = Process.runSync(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-Command', script],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return res.stdout as String;
}

List<Map<String, dynamic>> _decodeList(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text == 'null') return const [];
  final decoded = jsonDecode(text);
  if (decoded is Map<String, dynamic>) return [decoded];
  return (decoded as List).cast<Map<String, dynamic>>();
}
