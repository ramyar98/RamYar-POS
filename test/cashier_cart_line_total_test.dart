import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_unified_table_page.dart';

/// The food tab's «داواکاری» cart has to add up.
///
/// The complaint: stepping into a table, picking food and reading the total at
/// the foot of the cart gave a number that did not match the lines above it. The
/// cart rows printed the *unit* price («د.ع 1,000» beside «x2»), while «کۆی
/// گشتی» summed price x quantity - so a dish rung up twice looked like a total
/// that had been doubled by mistake. Each row now carries its own line total, so
/// what the cashier reads reconciles with the footer.
///
/// No Kurdish literals in assertions beyond the money strings the UI owns: the
/// dishes are ASCII test names.
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

  const alpha = 'Alpha';
  const beta = 'Beta';

  /// Opens table 1 straight on the food tab, the way the cashier reaches it to
  /// add more dishes.
  Future<void> openFoodTab(WidgetTester tester, Size size) async {
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
            home: CashierUnifiedTablePage(tableNumber: 1, initialTab: 1),
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> seed(WidgetTester tester) async {
    // Drop the starter menu so only the test dishes are on the grid.
    for (final it in await db.getFoodItems()) {
      await db.deleteFoodItem(it['id'] as int);
    }
    await db.addFoodCategory('Grill', 'restaurant');
    await db.addFoodItem(alpha, 1000, 'Grill');
    await db.addFoodItem(beta, 250, 'Grill');
    // A dish the captain already sent: 1000 x 2.
    await db.addOrderItem(
      1,
      OrderItem(id: 'line-1', name: alpha, price: 1000, quantity: 2),
    );
  }

  testWidgets('each cart line carries its own total, so the footer adds up',
      (tester) async {
    await seed(tester);
    await openFoodTab(tester, const Size(1200, 900));

    // Put one 250 dish on the pending side.
    await tester.tap(
      find.descendant(of: find.byType(GridView), matching: find.text(beta)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // The sent line shows its own 2,000 (it used to show only the unit 1,000)...
    expect(
      find.text('د.ع 2,000'),
      findsOneWidget,
      reason: 'the x2 line must print its own total, not the unit price',
    );
    // ...and the footer is that 2,000 plus the 250 dish just picked.
    expect(
      find.text('د.ع 2,250'),
      findsOneWidget,
      reason: 'the footer sums the line totals the rows display',
    );
  });

  testWidgets('the cart renders without overflow on a tablet-width sidebar',
      (tester) async {
    await seed(tester);
    // 700pt is under the 740 desktop breakpoint, so the cart sidebar is 220px -
    // the tightest the row total column ever has to fit.
    await openFoodTab(tester, const Size(700, 800));

    await tester.tap(
      find.descendant(of: find.byType(GridView), matching: find.text(beta)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('د.ع 2,250'), findsOneWidget);
  });
}
