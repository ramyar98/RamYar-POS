import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/fmt.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/page/admin/admin_shift_detail_page.dart';

/// The money summary of the admin's shift report.
///
/// The admin asked for a fourth figure: how much physical cash the till took
/// («کاش (نەقد)») next to the cashier's declared count («کاشێر»), so the report
/// finally answers "is the cashier short or over?" - «حسابی سیستەم». «کاش (نەقد)»
/// means physical cash: a bill on credit and an electronic receipt never reach
/// the drawer, so neither lands there even though both are sales. «کاش (نەقد) +
/// قەرز» adds the credit back: both the debts already collected and the ones
/// still sitting in the till's «قەرزەکان» list, and the «قەرز» card on its own
/// is that credit half, so the admin can read the split without arithmetic.
///
/// The «حسابی سیستەم» card is the size of the discrepancy between the two,
/// coloured by its direction: «کەمترە» red, «زیاترە» amber, «یەکسانە» green.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;
  const shiftId = 3;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  /// A settled order written straight into the table: `addSettledOrder` also
  /// queues an offline-sync mutation whose retry timer would still be pending
  /// when the widget test tears down.
  Future<void> seedOrder(String method, double amount) => db.db.insert(
        'settled_orders',
        {
          'tableId': 1,
          'tableName': 'مێز 1',
          'totalAmount': amount,
          'settledAt': DateTime.now().toIso8601String(),
          'settledBy': 4,
          'shiftId': shiftId,
          'paymentMethod': method,
        },
      );

  Future<void> openReport(
    WidgetTester tester, {
    required double collected,
    Size size = const Size(1400, 2000),
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
          child: MaterialApp(
            home: AdminShiftDetailPage(
              shift: CashierShift(
                id: shiftId,
                cashierId: 4,
                cashierName: 'Test cashier',
                startedAt: DateTime.now().toIso8601String(),
                endedAt: DateTime.now().toIso8601String(),
                totalCollected: collected,
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

  /// The money cards the admin reads. Scoped to the summary itself: «قەرز» is
  /// also the payment label on a debt order in the list below, so an unscoped
  /// text finder would count both.
  final summary = find.byKey(const Key('shift-financial-summary'));

  Finder card(String label) =>
      find.descendant(of: summary, matching: find.text(label));

  Future<void> expectCards(WidgetTester tester) async {
    expect(card('کاش (نەقد) + قەرز'), findsOneWidget);
    expect(card('قەرز'), findsOneWidget);
    expect(card('کاش (نەقد)'), findsOneWidget);
    expect(card('کاشێر'), findsOneWidget);
    expect(card('حسابی سیستەم'), findsOneWidget);
  }

  testWidgets('cash-only excludes debt and electronic receipts', (tester) async {
    await seedOrder('cash', 100000);
    await seedOrder('cash', 50000);
    await seedOrder('debt', 30000); // owed, not in the drawer
    await seedOrder('fib', 20000); // electronic, never in the drawer

    await openReport(tester, collected: 150000);

    await expectCards(tester);
    // «کاش (نەقد) + قەرز» = 100,000 + 50,000 + 30,000; «کاش (نەقد)» = 150,000 only.
    expect(find.textContaining(money(180000)), findsOneWidget);
    expect(find.textContaining(money(150000)), findsWidgets);
    expect(find.text('یەکسانە'), findsOneWidget,
        reason: 'the declared 150,000 matches the physical cash take exactly');
  });

  testWidgets('the «قەرز» card counts the credit alone', (tester) async {
    await seedOrder('cash', 100000);
    await seedOrder('cash', 50000);
    await seedOrder('debt', 30000); // collected on credit, during this shift
    await seedOrder('fib', 20000); // electronic, neither cash nor credit

    await openReport(tester, collected: 150000);

    await expectCards(tester);
    // «قەرز» is the credit on its own: 30,000. The electronic receipt is in
    // neither half of the split. Scoped to the summary because the same number
    // is also the amount of the debt order listed below it.
    expect(
      find.descendant(
        of: summary,
        matching: find.text('د.ع ${money(30000)}'),
      ),
      findsOneWidget,
    );
    // «کاش (نەقد) + قەرز» is the two halves added: 150,000 cash + 30,000 credit.
    expect(
      find.descendant(
        of: summary,
        matching: find.text('د.ع ${money(180000)}'),
      ),
      findsOneWidget,
    );
    // The electronic receipt is in neither figure. Scoped to the summary: the
    // order itself is still listed below with its 20,000 total.
    expect(
      find.descendant(
        of: summary,
        matching: find.text('د.ع ${money(20000)}'),
      ),
      findsNothing,
    );
  });

  testWidgets('a bill moved to «قەرزەکان» lands in the «قەرز» card',
      (tester) async {
    await seedOrder('cash', 10000);
    // The cashier hit «قەرز» on a 40,000 bill: the table was moved to the till's
    // debts list, so the money is owed rather than settled.
    await db.db.insert('debts', {
      'tableId': 2,
      'tableName': 'مێز 2',
      'amount': 40000.0,
      'reason': 'قەرز',
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': 4,
      'shiftId': shiftId,
    });

    await openReport(tester, collected: 10000);

    await expectCards(tester);
    // The debt is still owed, so it belongs to «قەرز» and not to «کاش (نەقد)».
    expect(find.text('د.ع ${money(40000)}'), findsOneWidget);
    expect(find.text('د.ع ${money(50000)}'), findsOneWidget);
  });

  testWidgets('«قەرز» sits between the whole book and the cash half',
      (tester) async {
    await seedOrder('cash', 10000);
    await seedOrder('debt', 40000);

    // Phone width: the cards wrap, so the test reads their declaration order in
    // the widget tree - which is the order the admin reads them on screen,
    // right-to-left per row in Kurdish.
    await openReport(tester, collected: 10000, size: const Size(420, 2400));

    await expectCards(tester);
    final labels = tester
        .widgetList<Text>(
          find.descendant(of: summary, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final totalIndex = labels.indexOf('کاش (نەقد) + قەرز');
    final debtIndex = labels.indexOf('قەرز');
    final cashIndex = labels.indexOf('کاش (نەقد)');
    expect(totalIndex, isNonNegative);
    expect(debtIndex, greaterThan(totalIndex),
        reason: '«قەرز» must come after «کاش (نەقد) + قەرز»');
    expect(cashIndex, greaterThan(debtIndex),
        reason: '«قەرز» must come before «کاش (نەقد)»');
  });

  testWidgets('a short till reads «کەمترە»', (tester) async {
    await seedOrder('cash', 200000);
    await openReport(tester, collected: 150000);

    await expectCards(tester);
    expect(find.text('کەمترە'), findsOneWidget);
    // The shortfall is the fourth card's amount: 200,000 - 150,000 = 50,000.
    expect(find.text('د.ع ${money(50000)}'), findsOneWidget);
  });

  testWidgets('an over till reads «زیاترە»', (tester) async {
    await seedOrder('cash', 100000);
    await openReport(tester, collected: 130000);

    await expectCards(tester);
    expect(find.text('زیاترە'), findsOneWidget);
    // The 30,000 overage is the fourth card's amount: 130,000 - 100,000.
    expect(find.text('د.ع ${money(30000)}'), findsOneWidget);
  });

  testWidgets('the gap is measured against cash only, not cash + debt',
      (tester) async {
    await seedOrder('cash', 10000);
    await seedOrder('debt', 40000); // owed, not in the drawer
    await openReport(tester, collected: 5000);

    await expectCards(tester);
    // «کاش (نەقد) + قەرز» is 50,000 and «کەمترە» flags the shortfall, but the fourth
    // card's gap is |5,000 - 10,000| = 5,000: had it wrongly compared against
    // cash + debt we would see 45,000 instead.
    expect(find.text('د.ع ${money(50000)}'), findsWidgets);
    expect(find.text('کەمترە'), findsOneWidget);
    expect(find.text('د.ع ${money(45000)}'), findsNothing);
  });

  testWidgets('a bill moved to «قەرزەکان» still counts in cash + debt',
      (tester) async {
    await seedOrder('cash', 10000);
    // The cashier hit «قەرز» on a 40,000 bill: the table was moved to the till's
    // debts list. That writes a debt row and no settled order, so the money
    // would be invisible to the report without the debt lookup.
    await db.db.insert('debts', {
      'tableId': 2,
      'tableName': 'مێز 2',
      'amount': 40000.0,
      'reason': 'قەرز',
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': 4,
      'shiftId': shiftId,
    });

    await openReport(tester, collected: 10000);

    await expectCards(tester);
    // «کاش (نەقد) + قەرز» = 10,000 cash + 40,000 owed = 50,000, while
    // «کاش (نەقد)» stays 10,000 so the till still reconciles.
    expect(find.text('د.ع ${money(50000)}'), findsWidgets);
    expect(find.text('یەکسانە'), findsOneWidget);
  });

  testWidgets('the «قەرزەکان» tab lists the tables still on credit',
      (tester) async {
    await db.db.insert('debts', {
      'tableId': 2,
      'tableName': 'مێز 2',
      'amount': 40000.0,
      'reason': 'قەرز',
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': 4,
      'shiftId': shiftId,
    });

    await openReport(tester, collected: 0);

    await tester.tap(find.text('قەرزەکان').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The tab names the credit group and shows the table that owes the money,
    // not just the debts that happened to be collected.
    expect(find.text('مێزەکانی قەرز (1)'), findsOneWidget);
    expect(find.text('مێز 2'), findsOneWidget);
    expect(find.text('د.ع ${money(40000)}'), findsWidgets);
  });

  testWidgets('tapping a credit table shows the dishes it ordered',
      (tester) async {
    // Moving a table to «قەرزەکان» clears its order, so the debt carries a
    // snapshot of the dishes. Opening the row must surface them.
    await db.db.insert('debts', {
      'tableId': 2,
      'tableName': 'مێز 2',
      'amount': 40000.0,
      'reason': 'قەرز',
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': 4,
      'shiftId': shiftId,
      'itemsJson': '[{"name":"شیرینی بەرگەری","price":5000.0,"quantity":2},'
          '{"name":"چای","price":1000.0,"quantity":1}]',
    });

    await openReport(tester, collected: 0);
    await tester.tap(find.text('قەرزەکان').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The row counts the dishes...
    expect(find.textContaining('خواردنەکان: 2'), findsOneWidget);

    // ...and tapping it opens them with their quantities.
    await tester.tap(find.text('مێز 2'));
    await tester.pumpAndSettle();
    expect(find.text('شیرینی بەرگەری'), findsOneWidget);
    expect(find.text('چای'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
  });
}
