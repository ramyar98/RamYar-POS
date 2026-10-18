import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramyar_pos/core/startup_failure.dart';

/// The button is located by its icon rather than by its label on purpose.
///
/// The label is Kurdish, and a test that repeats a translated string pins the
/// wording and fails for a reason that has nothing to do with the behaviour
/// under test. Icons are not translated, so this stays true when the text
/// changes.
Finder get retryButton => find.widgetWithIcon(FilledButton, Icons.refresh);

void main() {
  group('describeStartupFailure', () {
    test('explains a missing sqlite3.dll as a broken build', () {
      // The shape of the failure the Dart build hooks cause. dart:ffi reports
      // it as an ArgumentError naming the file and says nothing about what to
      // do about it, and it is thrown before the first frame - so this message
      // is the only place the user can be told what happened.
      final message = describeStartupFailure(
        ArgumentError('Failed to load dynamic library sqlite3.dll'),
      );

      expect(message, contains('sqlite3.dll could not be loaded'));
      // Actionable: says what is wrong with the build and what to do about it.
      expect(message, contains('flutter clean'));
      // The original detail is never thrown away - it is what identifies the
      // exact loader error when the library is present but unusable.
      expect(message, contains('Failed to load dynamic library sqlite3.dll'));
    });

    test('passes every other failure through unchanged', () {
      const error = 'Bad state: databaseFactory not initialized';
      expect(describeStartupFailure(error), error);
    });

    test('passes an exception through unchanged when it has no text', () {
      // toString() of a bare object is still shown, rather than swallowed.
      final message = describeStartupFailure(_Silent());
      expect(message, contains('_Silent'));
      expect(message, isNot(contains('sqlite3.dll')));
    });
  });

  group('StartupFailureApp', () {
    testWidgets('shows the message and the retry button', (tester) async {
      await tester.pumpWidget(StartupFailureApp(
        message: 'the database could not be opened',
        onRetry: () async {},
      ));

      expect(find.text('the database could not be opened'), findsOneWidget);
      expect(retryButton, findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('retry runs the callback', (tester) async {
      var retried = 0;
      await tester.pumpWidget(StartupFailureApp(
        message: 'boom',
        onRetry: () async => retried++,
      ));

      await tester.tap(retryButton);
      await tester.pump();

      expect(retried, 1);
    });

    testWidgets('a retry that fails again leaves the screen up', (tester) async {
      // Retrying is offered because most of these are transient, but a retry
      // that throws must not take the screen down with it - that would lose the
      // only description of the original problem. The exception is swallowed
      // deliberately; the message stays.
      await tester.pumpWidget(StartupFailureApp(
        message: 'the original problem',
        onRetry: () async => throw StateError('still broken'),
      ));

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('the original problem'), findsOneWidget);
    });

    testWidgets('a long message scrolls instead of overflowing', (tester) async {
      // The missing-library message is much longer than the others, and this is
      // the one place the text is shown, so it has to fit a small window.
      final longMessage = describeStartupFailure(
        ArgumentError('Failed to load dynamic library sqlite3.dll: '
            '${'detail ' * 200}'),
      );
      expect(longMessage.length, greaterThan(1500));

      await tester.pumpWidget(StartupFailureApp(
        message: longMessage,
        onRetry: () async {},
      ));

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}

/// An exception whose `toString` carries no message of its own.
class _Silent implements Exception {
  @override
  String toString() => '_Silent';
}
