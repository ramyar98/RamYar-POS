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
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/admin/shift_rejected_items_page.dart';
/// The shape of a «ڕەتکراوەکان» card.
///
/// The admin asked for the facts first, on one line - which table, when it was
/// ordered, when it was rejected, who asked for it and what it is worth - and
/// for the dish name and its price to sit below that row. This pins that order
/// so a later tidy-up cannot quietly put the dish back on top.
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

  testWidgets('the facts share the top row and the dish sits below',
      (tester) async {
    await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter);
    // The rejection is scoped to the shift that rang it up, so open one first.
    final shiftId = await db.startShift(
      CashierShift(
        cashierId: 4,
        cashierName: 'کاشێر شیلان',
        startedAt: '2026-10-12T08:00:00.000',
      ),
    );
    await db.recordCancelledItem(
      tableId: 11,
      tableName: 'مێز 11',
      itemName: 'شیرینی تایبەت',
      price: 4000,
      quantity: 1,
      category: 'خواردن',
      cancelledBy: 4,
      cancelledByName: 'کاشێر شیلان',
      requestedByName: 'کاپتن ئاراس',
      requestedAt: '2026-10-12T08:15:00.000',
    );

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
            home: Scaffold(
              body: SingleChildScrollView(
                child: ShiftRejectedItemsView(shiftId: shiftId),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The facts row carries every fact the admin named.
    expect(find.textContaining('مێز 11'), findsOneWidget);
    expect(find.textContaining('کاتی داواکردن:'), findsOneWidget);
    expect(find.textContaining('کاتی ڕەتکردنەوە:'), findsOneWidget);
    expect(find.textContaining('داواکەر:'), findsOneWidget);
    expect(find.textContaining('کۆی گشتی:'), findsOneWidget);

    // The dish and its price are still on the card.
    expect(find.text('شیرینی تایبەت'), findsOneWidget);
    expect(find.text('1 × د.ع ${money(4000)}'), findsOneWidget);

    // The facts sit above the dish: the row's first fact is painted higher on
    // the screen than the dish's name.
    final factsRow = find.textContaining('کاتی داواکردن:');
    final dish = find.text('شیرینی تایبەت');
    expect(
      tester.getTopLeft(factsRow).dy,
      lessThan(tester.getTopLeft(dish).dy),
      reason: 'the facts row must come before the dish name',
    );
  });

  testWidgets('the five facts fold instead of overflowing on a phone',
      (tester) async {
    await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter);
    final shiftId = await db.startShift(
      CashierShift(
        cashierId: 4,
        cashierName: 'کاشێر شیلان',
        startedAt: '2026-10-12T08:00:00.000',
      ),
    );
    await db.recordCancelledItem(
      tableId: 11,
      tableName: 'مێز 11',
      itemName: 'شیرینی تایبەت',
      price: 4000,
      quantity: 1,
      category: 'خواردن',
      cancelledBy: 4,
      cancelledByName: 'کاشێر شیلان',
      requestedByName: 'کاپتن ئاراس',
      requestedAt: '2026-10-12T08:15:00.000',
    );

    // A narrow phone: five facts cannot fit on one line, so the Wrap has to
    // fold them rather than trip a RenderFlex overflow.
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: AppState(
          currentLanguage: AppLanguage.kurdish,
          onLanguageChanged: (_) {},
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ShiftRejectedItemsView(shiftId: shiftId),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('شیرینی تایبەت'), findsOneWidget);
  });
}
