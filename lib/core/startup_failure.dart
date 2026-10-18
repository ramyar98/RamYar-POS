import 'package:flutter/material.dart';

/// Turns a startup exception into something a person can act on.
///
/// Most startup failures are the error text itself and are shown as they came.
/// The one worth rewriting is a missing `sqlite3.dll`: the exception it raises
/// is an FFI loader message that names a file and says nothing about what to do
/// about it, and — because it happens while the database implementation is
/// being selected, before there is a widget tree — it used to leave the program
/// showing no window at all, so there was not even anywhere to show a message.
///
/// The library is produced by the Dart build hooks, so this failure means the
/// build is incomplete rather than the machine being broken, and that is worth
/// saying in the message.
///
/// Recognised by the file name appearing in the error text rather than by the
/// exception's type, because that type is not something this can rely on:
/// `dart:ffi` has raised `ArgumentError` and `FileSystemException` for the same
/// failure across versions, and `package:ffi` adds its own. Matching the text is
/// the only check that keeps working across all of them. It is deliberately
/// loose — a message that merely mentions `sqlite3.dll` as part of a longer path
/// would be rewritten too — which is the right trade here: the original text is
/// always included underneath, so a rewrite that turns out to be wrong costs a
/// line of noise, whereas a failure left unrecognised costs a dead app.
String describeStartupFailure(Object error) {
  final detail = error.toString();
  if (detail.contains('sqlite3.dll')) {
    return 'sqlite3.dll could not be loaded.\n\n'
        'The database library is missing from this build, so the app cannot '
        'start. Reinstall it, or build it again from the project root - '
        '`flutter clean` followed by a fresh build repairs a build that was '
        'left half finished.\n\n'
        '($detail)';
  }
  return detail;
}

/// Shown when the app could not get as far as opening its database.
///
/// Kept deliberately plain and dependency-free: it has to render when the
/// database layer is exactly the thing that is broken, so it must not ask that
/// layer for anything — not translations, not settings, not the network.
///
/// [onRetry] is run again by the button. Whatever went wrong is usually a
/// transient condition (the data directory locked by a backup, the network
/// share not mounted yet), so being able to try once more without restarting
/// is the useful thing to offer; the original [message] stays on screen
/// throughout so the reason is never lost.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 56),
                const SizedBox(height: 18),
                const Text(
                  'نەتوانرا داتابەیسەکە بکرێتەوە',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'ئەم پڕۆگرامە بێ داتابەیس ناتوانێت کار بکات. تکایە پەردەی پەیوەندی (ئینتەرنێت) بپشکنە و دووبارە هەوڵ بدەوە.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await onRetry();
                    } catch (_) {
                      // The failure screen stays up; the message above still
                      // describes the original problem.
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('دووبارە هەوڵ بدەوە'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
