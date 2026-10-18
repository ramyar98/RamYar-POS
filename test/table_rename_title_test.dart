import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/cashier/cashier_unified_table_page.dart';
import 'package:ramyar_pos/page/waiter/table_page.dart';

/// The complaint this file exists for, in the cashier's own words: renaming a
/// table in the appbar succeeded and the new name showed *in the dialog*, but
/// after closing the table the name still read "مێزی 1".
///
/// The rename was never the problem - it always wrote the row. The problem was
/// that every heading on the table page was built from the table's NUMBER rather
/// than from its NAME, so the page kept announcing the old number after the
/// label had moved, while the grid card one screen away (fed from the same row)
/// showed the new name. The rename looked like it had not saved.
///
/// So these tests do not call `renameTable` and check the database - the
/// database was right all along. They rename the table and then read the text
/// actually rendered in the appbar, on both the cashier's page and the
/// captain's, because that is where the lie was.
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

  /// Puts [page] on screen and leaves it there once the row has loaded.
  ///
  /// The database goes in through `localDbProvider` - exactly how `main` does it,
  /// and the only reason that provider exists. These pages have to read the SAME
  /// row the rename just wrote; a page fed some other database would build a
  /// title and prove nothing about the real one.
  Future<void> openTablePage(
    WidgetTester tester,
    Widget page,
    LocalDatabase database,
  ) async {
      // `AppState` is the app's language scope, which every string on both pages
    // reads through `context.tr`. It has to be here or the pages throw before
    // they build a title. Language is irrelevant to what is being asserted, so
    // it is pinned to Kurdish - which is also the language the reported bug was
    // reported in, and where `tr` returns the key itself, so the expected strings
    // below are read literally.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(database)],
        child: AppState(
          currentLanguage: AppLanguage.kurdish,
          onLanguageChanged: (_) {},
          child: MaterialApp(home: Builder(builder: (_) => page)),
        ),
      ),
    );
    // The title comes from the row, so the page has to be pumped until the
    // provider has actually read it - the same wait a real screen does.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(AppBar).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

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

  testWidgets('the cashier page announces the renamed table, not its number',
      (tester) async {
    await db.renameTable(1, 'VIP 1');

    await openTablePage(tester, const CashierUnifiedTablePage(tableNumber: 1, initialTab: 0), db);

    expect(appBarTitle(tester), 'VIP 1',
        reason: 'this is the whole complaint: the page must show the label the '
            'shop set, not the number it happens to sit at');
  });

  testWidgets('the captain page announces the renamed table too', (tester) async {
    await db.renameTable(1, 'VIP 1');

    await openTablePage(tester, const TablePage(tableNumber: 1), db);

    expect(appBarTitle(tester), 'VIP 1',
        reason: 'the same table, the same rename, on the other role\'s screen - '
            'the two floors must not disagree about what a table is called');
  });

  testWidgets('a table nobody renamed still falls back to its number',
      (tester) async {
    // The fallback is not dead code: a row that has not loaded yet, or one with
    // no usable label, must still say something useful rather than a blank bar.
    await db.renameTable(1, '   ');

    await openTablePage(tester, const CashierUnifiedTablePage(tableNumber: 1, initialTab: 0), db);

    expect(appBarTitle(tester), contains('1'),
        reason: 'a blank name must fall back to the number, not to nothing');
  });

  testWidgets('a renamed table is still reachable as a plain table as well',
      (tester) async {
    // The second half of the request: renaming table 1 away from its standard
    // label hands that label back to the floor as its own empty row, so the
    // grid can still seat a party at a table called "table 1".
    await db.renameTable(1, 'VIP 1');

    final spare = await db.getTable(LocalDatabase.standardLabelRowId(1));
    expect(spare, isNotNull);
    expect(spare!.name, LocalDatabase.standardTableName(1));
    expect(spare.status.index, 0, reason: 'it waits empty, nobody is seated');

    // And that spare opens on its own page, under the label it carries.
    await openTablePage(tester, CashierUnifiedTablePage(tableNumber: spare.id, initialTab: 0), db);
    expect(appBarTitle(tester), LocalDatabase.standardTableName(1));
  });
}
