import 'dart:convert';

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

/// The «مێزەکانی ماون» tab is the admin's window onto the tables a cashier left
/// sitting with an open bill when the shift closed. It is informational only -
/// nothing is settled or counted - so these tests pin the two things the admin
/// does with it: read the list, and tap a row to see what that table had.
///
/// The rows are written straight into `shift_remaining_tables` rather than
/// through `endShift()`: the DB-level capture is covered by
/// `shift_remaining_tables_test.dart`, and going through the mutation path would
/// leave an offline-sync retry timer pending at teardown.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
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
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  Future<void> seedRemainingTable({
    required int tableId,
    required String tableName,
    int guestCount = 2,
    String waiterName = 'وەیتەر 1',
    String note = '',
    double total = 20000,
    String itemsJson = '',
  }) => db.db.insert('shift_remaining_tables', {
    'shiftId': shiftId,
    'shiftCashierId': 4,
    'shiftStartedAt': DateTime.now().toIso8601String(),
    'tableId': tableId,
    'tableName': tableName,
    'guestCount': guestCount,
    'seatedAt': DateTime.now().toIso8601String(),
    'waiterId': '2',
    'waiterName': waiterName,
    'note': note,
    'totalAmount': total,
    'itemsJson': itemsJson,
    'createdAt': DateTime.now().toIso8601String(),
  });

  String kebabJson() => jsonEncode([
    {
      'name': 'کەباب',
      'price': 10000,
      'quantity': 2,
      'category': 'کەباب',
      'waiterName': 'وەیتەر 1',
      'waiterRole': 0,
    },
  ]);

  Future<void> openReport(WidgetTester tester) async {
    // A tall viewport so the whole report - including the tab bar and the
    // content under it - is laid out at once: `ListView(children:)` does not
    // build children that are below the fold.
    tester.view.physicalSize = const Size(1400, 2400);
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
                totalCollected: 0,
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

  testWidgets('the tab lists the tables left un-settled', (tester) async {
    await seedRemainingTable(
      tableId: 1,
      tableName: 'مێز 1',
      itemsJson: kebabJson(),
    );
    await openReport(tester);
    await tapTab(tester, 'مێزەکانی ماون');

    expect(find.text('مێز 1'), findsOneWidget);
    // The summary header counts what the shift left behind.
    expect(find.text('مێزەکانی ماون: 1'), findsOneWidget);
  });

  testWidgets('tapping a remaining table opens its full contents', (
    tester,
  ) async {
    await seedRemainingTable(
      tableId: 1,
      tableName: 'مێز 1',
      itemsJson: kebabJson(),
    );
    await openReport(tester);
    await tapTab(tester, 'مێزەکانی ماون');

    await tester.tap(find.text('مێز 1'), warnIfMissed: false);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The bottom sheet shows the dishes the table still owed for.
    expect(find.text('کەباب'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
  });

  testWidgets('an empty snapshot shows the empty message', (tester) async {
    await openReport(tester);
    await tapTab(tester, 'مێزەکانی ماون');

    expect(find.text('هیچ مێزێکی ماوە نییە'), findsOneWidget);
    expect(find.text('مێز 1'), findsNothing);
  });
}
