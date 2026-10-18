import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_unified_table_page.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';

/// What happens when the cashier renames table 1 and presses save.
///
/// The rule, in the shop's own terms: the room is a hundred PLACES, ids 1..100,
/// and a name is only a label stuck on a place. So typing "hama" (or "150") over
/// table 1 does not turn table 1 into a different table and it does not make
/// table 1 disappear - the place keeps its id, its guests and its bill, and only
/// the label moves. What the floor then lacks is a plain table 1 to seat, so the
/// system hands that label straight back as its own empty spare row, and the
/// grid grows by one card rather than by one lost table.
///
/// The rule the floor depends on underneath all of it: ids 1..100 are always
/// there. Whatever happens - a rename, a delete, an old database carried across -
/// the missing place is re-created empty before anything is drawn, so a cashier
/// can never end up with a hole in the room.
///
/// Why this file drives the dialog instead of calling `renameTable`: the rename
/// was never the broken part. The original complaint was that saving the dialog
/// looked like it worked and the table page then announced the old number
/// anyway, and the only way that hides is to skip the dialog and assert on the
/// database - which is exactly what the older tests did. Everything here goes
/// through the pencil, the text field and the save button, then reads what is
/// actually rendered.
///
/// No Kurdish literals: assertions are on the ids, the ASCII names and the ASCII
/// number the cashier types.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The no-isolate factory: a widget test runs inside `FakeAsync`, and a
    // database in a real isolate would never hand its results back.
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

  Future<void> openTableOne(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: AppState(
          currentLanguage: AppLanguage.kurdish,
          onLanguageChanged: (_) {},
          child: const MaterialApp(
            home: CashierUnifiedTablePage(tableNumber: 1, initialTab: 0),
          ),
        ),
      ),
    );
    // The title is built from the row, so wait for the page to have read it -
    // the same wait a real screen does.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(AppBar).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The pencil, the field, the save button - the path a cashier actually walks.
  Future<void> renameThroughDialog(WidgetTester tester, String newName) async {
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    // Scoped to the dialog: the food tab underneath has a search field of its
    // own, and an unscoped finder matches two and throws.
    final dialog = find.byType(AlertDialog);
    final field = find.descendant(of: dialog, matching: find.byType(TextField));
    expect(field, findsOneWidget, reason: 'the dialog offers one name field');
    await tester.enterText(field, newName);
    await tester.pump();
    // The save button sits in the dialog's own actions, so it is found inside it
    // rather than by label.
    final save = find.descendant(of: dialog, matching: find.byType(FilledButton));
    expect(save, findsOneWidget, reason: 'the dialog must offer exactly one save');
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The label the app bar is actually printing right now.
  String appBarTitle(WidgetTester tester) {
    final titles = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(titles, isNotEmpty, reason: 'the appbar must carry a title');
    return titles.first;
  }

  Future<List<TableModel>> allTables() => db.getAllTables();

  testWidgets('renaming table 1 to a word: the place keeps its id, the floor '
      'gets a spare table 1', (tester) async {
    await openTableOne(tester);

    await renameThroughDialog(tester, 'hama');

    // What the cashier sees on the table they are standing at.
    expect(appBarTitle(tester), 'hama');

    // Table 1 is still table 1 - a place does not move because its label did.
    final renamed = await db.getTable(1);
    expect(renamed, isNotNull,
        reason: 'table 1 is a place in the room; it cannot go anywhere');
    expect(renamed!.name, 'hama');

    // ...and the plain table 1 the shop expects to always be there is handed
    // back to the floor as its own empty row.
    final spare = await db.getTable(LocalDatabase.standardLabelRowId(1));
    expect(spare, isNotNull,
        reason: 'the room lost its table 1 label, so a spare row takes it back');
    expect(spare!.name, LocalDatabase.standardTableName(1));
    expect(spare.status.index, TableStatus.empty.index,
        reason: 'it waits empty - nobody is seated at a table that was just '
            'invented');
    expect(spare.totalAmount, 0);

    // One card more on the floor, never one card fewer.
    expect((await allTables()).length, kStandardTableCount + 1);
  });

  testWidgets('renaming table 1 to a number: the same thing, numbers included',
      (tester) async {
    await openTableOne(tester);

    await renameThroughDialog(tester, '150');

    expect(appBarTitle(tester), '150',
        reason: 'a number is just another label - the page must not fall back '
            'to the number it happens to sit at');
    final renamed = await db.getTable(1);
    expect(renamed, isNotNull);
    expect(renamed!.name, '150');

    final spare = await db.getTable(LocalDatabase.standardLabelRowId(1));
    expect(spare, isNotNull);
    expect(spare!.name, LocalDatabase.standardTableName(1));
    expect((await allTables()).length, kStandardTableCount + 1);

    // Nothing else was disturbed: the other 99 places are all still there, and
    // none of them gained or lost a row.
    final ids = (await allTables()).map((t) => t.id).toSet();
    for (var i = 1; i <= kStandardTableCount; i++) {
      expect(ids.contains(i), isTrue, reason: 'place $i must never go missing');
    }
  });

  testWidgets('renaming the spare away and back does not pile up cards',
      (tester) async {
    await openTableOne(tester);
    await renameThroughDialog(tester, 'hama');
    expect((await allTables()).length, kStandardTableCount + 1);

    // Typing the standard label back onto place 1 is how a cashier says "never
    // mind, call it a table again" - and two cards reading the same would be a
    // duplicate to seat somebody at by mistake.
    await renameThroughDialog(tester, LocalDatabase.standardTableName(1));

    expect(appBarTitle(tester), LocalDatabase.standardTableName(1));
    expect(await db.getTable(LocalDatabase.standardLabelRowId(1)), isNull);
    expect((await allTables()).length, kStandardTableCount);
  });

  testWidgets('a blank name is refused instead of wiping the label',
      (tester) async {
    await openTableOne(tester);

    await renameThroughDialog(tester, '   ');

    // The dialog's own guard: an empty field would leave a card with no way to
    // tell it apart, so nothing is written at all.
    final t1 = await db.getTable(1);
    expect(t1!.name, LocalDatabase.standardTableName(1),
        reason: 'a blank rename must not blank the card');
    expect(await db.getTable(LocalDatabase.standardLabelRowId(1)), isNull,
        reason: 'and must not hand out a spare for a rename that never happened');
  });

  testWidgets('the floor is always 1..100, whatever happened to the rows',
      (tester) async {
    // The rule the whole scheme leans on, checked at the boundary the cashier
    // would notice: rename, delete and raw holes, then one repair pass.
    await db.renameTable(1, 'hama');
    await db.deleteTable(2);
    await db.db.delete('tables', where: 'id IN (3, 99)');
    expect(await db.getTable(3), isNull);

    await db.ensureStandardTables();

    expect((await db.getTable(3))!.name, LocalDatabase.standardTableName(3));
    expect((await db.getTable(99))!.name, LocalDatabase.standardTableName(99));
    // The custom label survived the repair - the place was never the label.
    expect((await db.getTable(1))!.name, 'hama');
    expect((await allTables()).length, kStandardTableCount + 1,
        reason: 'the restored places come back, and the spare stays a spare');
  });

  testWidgets('the grid the cashier returns to shows both cards',
      (tester) async {
    // The last link: the table page is not where the cashier counts tables. Go
    // back to the floor and read the list the grid is built from - two cards,
    // one place renamed and one spare, not one table lost.
    final container =
        ProviderContainer(overrides: [localDbProvider.overrideWithValue(db)]);
    // Riverpod refreshes a provider on a zero-duration timer, so the container
    // needs a tree above it for the test's clock to drive that timer.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const SizedBox.shrink(),
    ));

    await db.renameTable(1, 'hama');
    await container.read(waiterProvider.notifier).refreshSilent();
    await _pumpUntilTables(tester, container);

    final names =
        (container.read(waiterProvider).asData?.value ?? []).map((t) => t.name).toList();
    expect(names, contains('hama'));
    expect(names, contains(LocalDatabase.standardTableName(1)),
        reason: 'the floor must still be able to seat a party at a table 1');
    expect(names.length, kStandardTableCount + 1);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });
}

/// Waits for the floor's table list to have finished loading, so "the grid shows
/// both cards" is waited for rather than sampled once and hoped over.
Future<void> _pumpUntilTables(
  WidgetTester tester,
  ProviderContainer container, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (container.read(waiterProvider).hasValue) return;
  }
  fail('Timed out waiting for the floor list');
}
