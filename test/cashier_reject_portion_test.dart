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

/// Rejecting ONE portion of a dish that was ordered in quantity.
///
/// The complaint: a captain rang up a dish x3 and the cashier's reject button on
/// the bill tab - the tab an occupied table opens on - threw all three away in a
/// single tap. The floor wants it to step down: x3, then x2, then x1, and only
/// the last tap clears the line. The food tab's cart already took that step; the
/// bill tab is the one that skipped it.
///
/// No Kurdish literals: the dish is an ASCII test name and the assertions read
/// the database and the rendered "xN" badge.
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

  const dish = 'Fish';

  /// Opens table 1 straight on the bill tab (`initialTab: 0`), the way the
  /// cashier's grid does for a table that already has food on it.
  Future<void> openBill(WidgetTester tester) async {
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
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('x3').evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// The reject button living in the dish's own bill row, found by walking up
  /// from the name so the food tab (were it built) could never be hit instead.
  Finder rejectButton() => find.descendant(
    of: find
        .ancestor(of: find.text(dish), matching: find.byType(Container))
        .first,
    matching: find.byIcon(Icons.delete_outline_rounded),
  );

  Future<void> tapReject(WidgetTester tester) async {
    final button = rejectButton();
    expect(
      button,
      findsOneWidget,
      reason: 'the bill row must offer exactly one reject button',
    );
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('one reject steps the dish down by a portion, not the line',
      (tester) async {
    await db.addOrderItem(
      1,
      OrderItem(id: 'line-1', name: dish, price: 1000, quantity: 3),
    );

    await openBill(tester);
    expect(find.text('x3'), findsOneWidget);

    // First tap: x3 -> x2.
    await tapReject(tester);
    expect((await db.getOrderItems(1)).single.quantity, 2,
        reason: 'the first reject takes one portion, leaving two');
    expect(find.text('x2'), findsOneWidget);
    expect(find.text('x3'), findsNothing);

    // Second tap: x2 -> x1.
    await tapReject(tester);
    expect((await db.getOrderItems(1)).single.quantity, 1,
        reason: 'the second reject takes another portion, leaving one');
    expect(find.text('x1'), findsOneWidget);

    // Third tap: the last portion, so the line goes - and only now.
    await tapReject(tester);
    expect(await db.getOrderItems(1), isEmpty,
        reason: 'only the final portion clears the line');

    // A rejection is audited per order line, so the queue gets exactly one
    // record - of the one portion that was still there when it was thrown out.
    final cancelled = await db.getPendingCancelledItems();
    expect(cancelled, hasLength(1));
    expect(cancelled.single.itemName, dish);
    expect(cancelled.single.quantity, 1);
  });

  testWidgets('dropping the whole line still works when there is one portion',
      (tester) async {
    await db.addOrderItem(
      1,
      OrderItem(id: 'line-1', name: dish, price: 1000, quantity: 1),
    );

    await openBill(tester);
    expect(find.text('x1'), findsOneWidget);

    await tapReject(tester);
    expect(await db.getOrderItems(1), isEmpty,
        reason: 'a single-portion line still clears on one tap');
    expect(find.text(dish), findsNothing);

    final cancelled = await db.getPendingCancelledItems();
    expect(cancelled, hasLength(1));
    expect(cancelled.single.quantity, 1);
  });
}
