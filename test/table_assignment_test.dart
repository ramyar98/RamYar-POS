import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/role_users_tab.dart';

/// Covers the owner → کاپتن (captain) → table-assignment flow.
///
/// The button used to be a no-op: `AlertDialog` sizes its content with
/// `IntrinsicWidth`, and the grid inside used a `LayoutBuilder`, which throws
/// "LayoutBuilder does not support returning intrinsic dimensions". The dialog's
/// layout collapsed, no table was ever painted, and the tap looked like it had
/// done nothing. These tests pin the whole path down: the dialog opens, a table
/// can be selected, and saving reaches `waiter_tables`.
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

  Future<void> pumpTab(
    WidgetTester tester, {
    // The app is used on a phone in landscape (2400x1080 @2.625 -> 914x411
    // logical) and on a laptop, so both are exercised.
    Size size = const Size(914, 411),
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

  Future<void> openAssignDialog(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.table_restaurant_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('tapping table assignment opens a dialog that actually paints',
      (tester) async {
    expect(await db.addUser('کاپتن ١', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);

    await openAssignDialog(tester);

    expect(find.byType(Dialog), findsOneWidget);
    // The grid is there and laid out: 100 seeded tables, the visible ones are
    // painted (and hit-testable) rather than a collapsed box.
    expect(find.text('مێزە دیاریکراوەکان'), findsOneWidget);
    expect(find.text('0/100'), findsOneWidget);
    expect(find.text('مێز 1'), findsOneWidget);
  });

  testWidgets('a table can be selected and the count follows',
      (tester) async {
    expect(await db.addUser('کاپتن ١', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);
    await openAssignDialog(tester);

    expect(find.text('0/100'), findsOneWidget);
    await tester.tap(find.text('مێز 1'));
    await tester.pump();
    expect(find.text('1/100'), findsOneWidget);

    // Tapping again deselects.
    await tester.tap(find.text('مێز 1'));
    await tester.pump();
    expect(find.text('0/100'), findsOneWidget);
  });

  testWidgets('saving writes the assignment to waiter_tables', (tester) async {
    expect(await db.addUser('کاپتن ١', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);
    await openAssignDialog(tester);

    await tester.tap(find.text('مێز 3'));
    await tester.pump();
    await tester.tap(find.text('مێز 4'));
    await tester.pump();
    expect(find.text('2/100'), findsOneWidget);

    await tester.tap(find.text('پاشەکەوتکردن'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final waiter = (await db.getUsersByRole(UserRole.waiter)).single;
    expect(await db.getWaiterTableIds(waiter.id), containsAll([3, 4]));
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('an existing assignment is pre-selected when reopening',
      (tester) async {
    final waiterId = await db.addUser('کاپتن ١', '10001', UserRole.waiter);
    expect(waiterId, isTrue);
    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    await db.assignTablesToWaiter(user.id, [1, 2, 3]);

    await pumpTab(tester);
    await openAssignDialog(tester);

    expect(find.text('3/100'), findsOneWidget);
  });

  testWidgets('the dialog works on a laptop-sized screen too', (tester) async {
    expect(await db.addUser('کاپتن ١', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester, size: const Size(1440, 900));

    await openAssignDialog(tester);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('0/100'), findsOneWidget);
    await tester.tap(find.text('مێز 1'));
    await tester.pump();
    expect(find.text('1/100'), findsOneWidget);
  });

  testWidgets('cancelling leaves the assignment untouched', (tester) async {
    expect(await db.addUser('کاپتن ١', '10001', UserRole.waiter), isTrue);
    await pumpTab(tester);
    await openAssignDialog(tester);

    await tester.tap(find.text('مێز 7'));
    await tester.pump();
    await tester.tap(find.text('ڕەتکردنەوە'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    expect(await db.getWaiterTableIds(user.id), isEmpty);
  });

  testWidgets('reset from the pick-tables dialog clears the range too',
      (tester) async {
    expect(await db.addUser('کاپتن ١', '10001', UserRole.waiter), isTrue);
    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    // Both halves of the scope, as an admin would leave them.
    await db.updateUserRange(user.id, 1, 5);
    await db.assignTablesToWaiter(user.id, [3, 4]);

    await pumpTab(tester);
    await openAssignDialog(tester);
    expect(find.text('2/100'), findsOneWidget);

    await tester.tap(find.text('گەڕاندنەوە بۆ ئاسایی'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final after = await db.getUserById(user.id);
    expect(after!.rangeStart, isNull,
        reason: 'one press is one action: the range has to go too');
    expect(after.rangeEnd, isNull);
    expect(await db.getWaiterTableIds(user.id), isEmpty,
        reason: 'the whole point of a reset is to hand back a normal account');
    expect(
      (await db.getAllTables()).where((t) => t.createdBy == user.id),
      isEmpty,
    );
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('reset from the range dialog clears the picked tables too',
      (tester) async {
    expect(await db.addUser('کاپتن ١', '10001', UserRole.waiter), isTrue);
    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    // Both halves of the same scope: a numeric range and picked tables.
    await db.updateUserRange(user.id, 1, 5);
    await db.assignTablesToWaiter(user.id, [3, 4]);
    final locked = (await db.getAllTables())
        .where((t) => t.createdBy == user.id)
        .map((t) => t.id)
        .toSet();
    expect(locked, containsAll([1, 2, 3, 4, 5]),
        reason: 'the range locks its tables to the captain');

    await pumpTab(tester);
    await tester.tap(find.byIcon(Icons.filter_alt_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('گەڕاندنەوە بۆ ئاسایی'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final after = await db.getUserById(user.id);
    expect(after!.rangeStart, isNull);
    expect(after.rangeEnd, isNull);
    expect(await db.getWaiterTableIds(user.id), isEmpty,
        reason: 'the picked tables are the other half of the same scope');
    final tables = await db.getAllTables();
    expect(tables.where((t) => t.createdBy == user.id), isEmpty,
        reason: 'the room must be shared again, not left carved up for them');
  });

  test('an assignment made on another device reaches this one through sync',
      () async {
    final other = LocalDatabase();
    await other.resetForTesting();
    await other.init(inMemory: true);
    addTearDown(other.resetForTesting);

    final sent = <MapEntry<String, Map<String, dynamic>>>[];
    db.onMutation = (action, data) => sent.add(MapEntry(action, data));
    await db.assignTablesToWaiter(7, [1, 2, 3]);
    db.onMutation = null;

    final assign = sent.singleWhere((e) => e.key == 'WAITER_TABLES_UPDATED');
    await debugApplyRemoteMutation(other, assign.key, assign.value);
    expect(await other.getWaiterTableIds(7), containsAll([1, 2, 3]),
        reason: 'the captain device has to learn which tables are theirs');

    // The empty list is the reset and must land as such, not be treated as a
    // no-op - that was the whole reason to broadcast assignments at all.
    final resetSent = <MapEntry<String, Map<String, dynamic>>>[];
    db.onMutation = (action, data) => resetSent.add(MapEntry(action, data));
    await db.assignTablesToWaiter(7, const []);
    db.onMutation = null;

    final reset = resetSent.singleWhere((e) => e.key == 'WAITER_TABLES_UPDATED');
    await debugApplyRemoteMutation(other, reset.key, reset.value);
    expect(await other.getWaiterTableIds(7), isEmpty);
  });

  test('a مەودا changed on another device re-locks the captain device\'s floor',
      () async {
    // A FILE-backed second device: sqflite's `:memory:` is one shared store per
    // process, which would make a two-device test pass for the wrong reason.
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_range_sync');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final captain = LocalDatabase();
    await captain.init(path: '${tmp.path}${Platform.pathSeparator}captain.db');
    addTearDown(captain.resetForTesting);

    final messages = <MapEntry<String, Map<String, dynamic>>>[];
    db.onMutation = (action, data) => messages.add(MapEntry(action, data));

    await db.addUser('کاپتن', '10001', UserRole.waiter);
    final user = (await db.getUsersByRole(UserRole.waiter)).single;

    // The captain device learns the fresh account - but creating one carries no
    // table lock, so nothing may be glued to it yet on either side.
    final created = messages.singleWhere((e) => e.key == 'USER_CREATED');
    await debugApplyRemoteMutation(captain, created.key, created.value);
    expect(
      (await captain.getAllTables()).where((t) => t.createdBy == user.id),
      isEmpty,
    );

    // The owner sets the range: the captain device must pick up the same lock.
    messages.clear();
    await db.updateUserRange(user.id, 1, 8);
    final first = messages.singleWhere((e) => e.key == 'USER_UPDATED');
    await debugApplyRemoteMutation(captain, first.key, first.value);
    expect(
      (await captain.getAllTables())
          .where((t) => t.createdBy == user.id)
          .map((t) => t.id)
          .toSet(),
      containsAll([1, 2, 3, 4, 5, 6, 7, 8]),
      reason: 'the captain device has to mirror the width the owner opened',
    );

    // The owner narrows it to 3-7. Without re-deriving the lock, the captain
    // device would keep 1-8 and its floor - and the cashier's ownership column -
    // would still show the window the owner just moved away from.
    messages.clear();
    await db.updateUserRange(user.id, 3, 7);
    final second = messages.singleWhere((e) => e.key == 'USER_UPDATED');
    await debugApplyRemoteMutation(captain, second.key, second.value);

    expect((await captain.getUserById(user.id))!.rangeStart, 3);
    expect((await captain.getUserById(user.id))!.rangeEnd, 7);
    expect(
      (await captain.getAllTables())
          .where((t) => t.createdBy == user.id)
          .map((t) => t.id)
          .toSet(),
      {3, 4, 5, 6, 7},
      reason: 'release the old مەودا, keep only the new one',
    );
    db.onMutation = null;
  });

  test('a reset from another device releases the captain device\'s lock',
      () async {
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_range_reset');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final captain = LocalDatabase();
    await captain.init(path: '${tmp.path}${Platform.pathSeparator}captain.db');
    addTearDown(captain.resetForTesting);

    final messages = <MapEntry<String, Map<String, dynamic>>>[];
    db.onMutation = (action, data) => messages.add(MapEntry(action, data));
    await db.addUser('کاپتن', '10001', UserRole.waiter);
    final user = (await db.getUsersByRole(UserRole.waiter)).single;
    await debugApplyRemoteMutation(
      captain,
      messages.singleWhere((e) => e.key == 'USER_CREATED').key,
      messages.singleWhere((e) => e.key == 'USER_CREATED').value,
    );

    messages.clear();
    await db.updateUserRange(user.id, 1, 5);
    final set = messages.singleWhere((e) => e.key == 'USER_UPDATED');
    await debugApplyRemoteMutation(captain, set.key, set.value);
    expect(
      (await captain.getAllTables()).where((t) => t.createdBy == user.id).length,
      5,
    );

    messages.clear();
    await db.resetWaiterScope(user.id);
    final reset = messages.singleWhere((e) => e.key == 'USER_UPDATED');
    await debugApplyRemoteMutation(captain, reset.key, reset.value);
    expect((await captain.getUserById(user.id))!.rangeStart, isNull);
    expect(
      (await captain.getAllTables()).where((t) => t.createdBy == user.id),
      isEmpty,
      reason: 'a normal account hands the whole floor back',
    );
    db.onMutation = null;
  });
}
