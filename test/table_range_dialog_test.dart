import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/widgets/role_users_tab.dart';

/// Covers the owner ▸ کاپتن ▸ «دیاریکردنی مەودای مێز» (numeric table range) flow.
///
/// The button used to look like pure decoration: the dialog opened and the
/// numbers could be typed, but saving showed nothing. The range WAS written to
/// SQLite - the defect was on the way out. The dialog created its
/// `TextEditingController`s in the caller and disposed them the instant
/// `showDialog` resolved, while the route was still animating out and its two
/// `TextField`s still referenced them. That threw
/// "A TextEditingController was used after being disposed" and aborted the frame
/// that repaints the owner's list, so the new مەودا never appeared on screen.
///
/// These tests pin the whole path down: the dialog opens, typing updates the
/// live description, saving closes it, the range reaches SQLite, and the list
/// row shows the range immediately afterwards - the same "result right away"
/// the pick-tables dialog gives.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  /// The app is used on a phone in landscape (~914x411) and on a laptop, so the
  /// tests run at a roomy laptop size where the whole dialog is on screen.
  Future<void> pumpTab(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: AppState(
          currentLanguage: AppLanguage.kurdish,
          onLanguageChanged: (_) {},
          child: const MaterialApp(
            home: Scaffold(body: RoleUsersTab(role: UserRole.waiter)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> openRangeDialog(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.filter_alt_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder startField() => find.widgetWithText(TextField, 'لە مێزی');
  Finder endField() => find.widgetWithText(TextField, 'بۆ مێزی');
  Finder saveButton() => find.widgetWithText(FilledButton, 'پاشەکەوتکردن');

  testWidgets('the range dialog opens and can be typed into', (tester) async {
    expect(await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);

    await openRangeDialog(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(startField(), findsOneWidget);
    expect(endField(), findsOneWidget);
    // Nothing entered yet: the description shows the placeholders.
    expect(find.textContaining('لە ؟ بۆ ؟'), findsOneWidget);
  });

  testWidgets('typing updates the description live', (tester) async {
    expect(await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);
    await openRangeDialog(tester);

    await tester.enterText(startField(), '1');
    await tester.pump();
    await tester.enterText(endField(), '10');
    await tester.pump();

    expect(find.textContaining('لە 1 بۆ 10'), findsOneWidget);
  });

  testWidgets('saving writes the range and the list row shows it right away',
      (tester) async {
    expect(await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);
    await openRangeDialog(tester);

    await tester.enterText(startField(), '1');
    await tester.pump();
    await tester.enterText(endField(), '10');
    await tester.pump();

    await tester.tap(saveButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    expect(user.rangeStart, 1);
    expect(user.rangeEnd, 10);
    expect(user.hasRange, isTrue);

    expect(find.byType(AlertDialog), findsNothing, reason: 'the dialog closes');
    // The whole point: the result is visible without reopening anything.
    expect(find.textContaining('مەودا: 1-10'), findsOneWidget);
  });

  testWidgets('an invalid range (start after end) cannot be saved',
      (tester) async {
    expect(await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);
    await openRangeDialog(tester);

    await tester.enterText(startField(), '10');
    await tester.pump();
    await tester.enterText(endField(), '1');
    await tester.pump();

    final FilledButton button = tester.widget(saveButton());
    expect(button.onPressed, isNull, reason: 'start > end is not a range');
  });

  testWidgets('reopening pre-fills the saved range', (tester) async {
    final ok = await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter);
    expect(ok, isTrue);
    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    await db.updateUserRange(user.id, 3, 7);

    await pumpTab(tester);
    await openRangeDialog(tester);

    final startWidget = tester.widget<TextField>(startField());
    final endWidget = tester.widget<TextField>(endField());
    expect(startWidget.controller!.text, '3');
    expect(endWidget.controller!.text, '7');
    expect(find.textContaining('لە 3 بۆ 7'), findsOneWidget);
  });

  testWidgets('reset from the range dialog clears the range', (tester) async {
    final ok = await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter);
    expect(ok, isTrue);
    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    await db.updateUserRange(user.id, 1, 10);

    await pumpTab(tester);
    await openRangeDialog(tester);

    await tester.tap(find.text('گەڕاندنەوە بۆ ئاسایی'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final after = await db.getUserById(user.id);
    expect(after!.rangeStart, isNull);
    expect(after.rangeEnd, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('مەودا:'), findsNothing);
  });
}
