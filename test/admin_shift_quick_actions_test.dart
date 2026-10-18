import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/page/admin/admin_shift_detail_page.dart';
import 'package:ramyar_pos/page/admin/shift_expenses_page.dart';

/// The four shift reports «ڕەتکراوەکان ، خەرجیەکان ، گەڕانەوەی خەرجی ، زیرەکی
/// کاپتن» used to be a row of tiles that pushed a page each. The admin asked to
/// fold them into the report's own tab bar and show their content directly
/// underneath, without ever leaving the shift report.
///
/// So this test proves two things: the four labels are now tabs (not tiles), and
/// selecting one draws this shift's rows inline - same page, no pushed route.
///
/// Expenses and their returns share the `cashier_expenses` table, split by the
/// sign of the price, so the fixture writes one of each plus a decoy on a second
/// shift to prove the scope.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The no-isolate factory: a widget test runs inside `FakeAsync`, and a
    // database in a real isolate would never hand its results back.
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;
  const shiftId = 7;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    // Written straight into the table rather than through `addCashierExpense`:
    // that method also queues an offline-sync mutation, whose retry timer would
    // still be pending when the widget test tears down.
    Future<void> seedExpense(int shift, String name, double price) => db.db
        .insert('cashier_expenses', {
          'shiftId': shift,
          'itemName': name,
          'price': price,
          'createdAt': DateTime.now().toIso8601String(),
        });
    await seedExpense(shiftId, 'Generator fuel', 20000);
    await seedExpense(shiftId, 'Returned fuel', -5000);
    // Belongs to a different shift and must never leak into either tab.
    await seedExpense(shiftId + 1, 'Other shift expense', 999);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  Future<void> openReport(
    WidgetTester tester, {
    Size size = const Size(1400, 2400),
  }) async {
    // A tall viewport so the whole report - including the tab bar and the
    // content under it - is laid out at once: `ListView(children:)` does not
    // build children that are below the fold.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: AppState(
          currentLanguage: AppLanguage.kurdish,
          onLanguageChanged: (_) {},
          child: MaterialApp(
            home: AdminShiftDetailPage(
              shift: CashierShift(
                id: shiftId,
                cashierId: 4,
                cashierName: 'Test cashier',
                startedAt: DateTime.now().toIso8601String(),
                totalCollected: 125000,
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(finder.first, warnIfMissed: false);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the four reports live in the tab bar, not as tiles', (
    tester,
  ) async {
    await openReport(tester);
    expect(find.byType(TabBar), findsOneWidget);
    // Four data tabs - «مێزەکانی ماون» (the informational snapshot of tables
    // still seated when the shift closed) joined the other three - plus the four
    // reports the admin moved down here.
    // «مێزەکان» and «کڕینی ئەشیاکان» were dropped from the box.
    expect(find.byType(Tab), findsNWidgets(8));
    expect(find.text('مێزەکان'), findsNothing);
    expect(find.text('کڕینی ئەشیاکان'), findsNothing);
    expect(find.text('ئۆردەرەکان'), findsOneWidget);
    expect(find.text('مێزەکانی ماون'), findsOneWidget);
    expect(find.text('ڕەتکراوەکان'), findsOneWidget);
    expect(find.text('خەرجیەکان'), findsOneWidget);
    expect(find.text('گەڕانەوەی خەرجی'), findsOneWidget);
    expect(find.text('زیرەکی کاپتن'), findsOneWidget);
    expect(find.text('ڕەفز و خەرجی'), findsNothing);
  });

  testWidgets('the bar stays clean on a narrow phone', (tester) async {
    // Tall enough that the tabs are actually laid out, but only 300px wide so
    // the long «گەڕانەوەی خەرجی» label can only sit on a scrollable bar.
    await openReport(tester, size: const Size(300, 2200));
    expect(tester.takeException(), isNull);
    expect(find.text('گەڕانەوەی خەرجی'), findsOneWidget);
  });

  testWidgets('«خەرجیەکان» shows this shift\'s expenses inline', (
    tester,
  ) async {
    await openReport(tester);
    await tapTab(tester, 'خەرجیەکان');
    // Same page: no route was pushed.
    expect(find.byType(AdminShiftDetailPage), findsOneWidget);
    expect(find.byType(ShiftExpensesPage), findsNothing);
    expect(find.text('Generator fuel'), findsOneWidget);
    expect(find.text('Returned fuel'), findsNothing);
    expect(find.text('Other shift expense'), findsNothing);
  });

  testWidgets('«گەڕانەوەی خەرجی» shows this shift\'s returns inline', (
    tester,
  ) async {
    await openReport(tester);
    await tapTab(tester, 'گەڕانەوەی خەرجی');
    expect(find.byType(AdminShiftDetailPage), findsOneWidget);
    expect(find.byType(ShiftExpensesPage), findsNothing);
    expect(find.text('Returned fuel'), findsOneWidget);
    expect(find.text('Generator fuel'), findsNothing);
    expect(find.text('Other shift expense'), findsNothing);
  });
}
