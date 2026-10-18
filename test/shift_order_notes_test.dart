import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/fmt.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/printer_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/page/admin/admin_shift_detail_page.dart';
import 'package:ramyar_pos/services/esc_pos_builder.dart';

/// The notes a table carried, on the admin's shift report.
///
/// A captain and a cashier can each leave a line on a table. Once the table is
/// settled and freed the `tables.note` row is reused, so the shift report reads
/// the copy the settlement took (`settled_orders.note`): tapping a table in
/// «ئۆردەرەکان» shows «تێبینیی کاپتن» and «تێبینی کاشێر». The report is the
/// admin's - the notes are for the record and never reach a printed receipt.
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

  Future<void> openReport(WidgetTester tester, {required double collected}) async {
    tester.view.physicalSize = const Size(1400, 2000);
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

  testWidgets('a settled table shows its captain and cashier notes',
      (tester) async {
    final orderId = await db.db.insert('settled_orders', {
      'tableId': 7,
      'tableName': 'مێز 7',
      'totalAmount': 10000,
      'discountPercent': 0,
      'discountAmount': 0,
      'settledAt': DateTime.now().toIso8601String(),
      'settledBy': 4,
      'shiftId': shiftId,
      'paymentMethod': 'cash',
      'note': 'سەوزی بێ گۆشت\n__ADMIN_NOTE__\nوەسڵی جیا بکە',
    });
    await db.db.insert('settled_order_items', {
      'settledOrderId': orderId,
      'itemName': 'Alpha',
      'itemPrice': 10000,
      'quantity': 1,
      'category': '',
    });

    await openReport(tester, collected: 10000);

    // The card carries a reprint button next to the expand chevron...
    expect(find.byIcon(Icons.print_rounded), findsOneWidget);

    // ...and opening it surfaces both lines the table carried.
    await tester.tap(find.text('مێز 7'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تێبینیی کاپتن'), findsOneWidget);
    expect(find.text('سەوزی بێ گۆشت'), findsOneWidget);
    expect(find.textContaining('تێبینی کاشێر'), findsOneWidget);
    expect(find.text('وەسڵی جیا بکە'), findsOneWidget);
  });

  testWidgets('a settled table with no note shows no note line', (tester) async {
    await db.db.insert('settled_orders', {
      'tableId': 8,
      'tableName': 'مێز 8',
      'totalAmount': 5000,
      'discountPercent': 0,
      'discountAmount': 0,
      'settledAt': DateTime.now().toIso8601String(),
      'settledBy': 4,
      'shiftId': shiftId,
      'paymentMethod': 'cash',
    });

    await openReport(tester, collected: 5000);
    await tester.tap(find.text('مێز 8'));
    await tester.pumpAndSettle();

    expect(find.textContaining('تێبینیی کاپتن'), findsNothing);
    expect(find.textContaining('تێبینی کاشێر'), findsNothing);
  });

  test('settling a table copies its note onto the settled order', () async {
    // The note lives on `tables.note` and the table row is reused the moment the
    // bill is closed, so settlement has to take a copy.
    await db.updateTableNote(
      1,
      'سەوزی بێ گۆشت\n__ADMIN_NOTE__\nوەسڵی جیا بکە',
    );
    await db.addOrderItem(
      1,
      OrderItem(id: 'x1', name: 'Alpha', price: 10000, quantity: 1),
    );
    await db.settleTable(1, 10000, 0, 0, 4, shiftId: shiftId);

    final orders = await db.getSettledOrdersByShiftId(shiftId);
    expect(orders, hasLength(1));
    expect(orders.first.note, contains('سەوزی بێ گۆشت'));
    expect(orders.first.note, contains('__ADMIN_NOTE__'));
    expect(orders.first.note, contains('وەسڵی جیا بکە'));
  });

  test('the printed receipt never carries the table note', () {
    // The receipt builder is given dishes, money and staff names - never the
    // note - so the note cannot leak onto paper. This pins that contract.
    final bytes = EscPosBuilder.buildCashierReceipt(
      tableNumber: 7,
      guestCount: 0,
      items: const [
        PrintJobItem(name: 'Alpha', quantity: 1, category: '', price: 10000),
      ],
      subtotal: 10000,
      discountPercent: 0,
      discountAmount: 0,
      total: 10000,
      tableLabel: 'مێز 7',
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    expect(text.contains('__ADMIN_NOTE__'), isFalse);
    expect(text.contains('تێبینیی کاپتن'), isFalse);
    expect(text.contains('تێبینی کاشێر'), isFalse);
    expect(text.contains('سەوزی بێ گۆشت'), isFalse);
    // Sanity: the receipt did render the table and the money.
    expect(text.contains('مێز 7'), isTrue);
    expect(text.contains(money(10000)), isTrue);
  });
}
