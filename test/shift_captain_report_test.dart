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
import 'package:ramyar_pos/page/admin/shift_captain_report_page.dart';

/// «زیرەکی کاپتن»: who sold what during a shift.
///
/// The admin wanted two things here. First, every captain is named - even one
/// who sold nothing - so the ranking shows who worked and who did not. Second,
/// the count is of *dishes sold* and a cashier who adds food to a table counts
/// as a salesperson, because in this shop they are selling too. That is why a
/// sale is credited to the person who rang the line in (`waiterName` /
/// `waiterRole`), not to the table's waiter.
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

  /// A settled order with one dish line, written straight into the tables:
  /// `addSettledOrder` also queues a sync mutation whose retry timer would
  /// still be pending when the widget test tears down.
  Future<void> seedLine({
    required int orderId,
    required String waiterName,
    required int waiterRole,
    required String itemName,
    required double price,
    required int quantity,
  }) async {
    await db.db.insert('settled_orders', {
      'id': orderId,
      'tableId': orderId,
      'tableName': 'مێز $orderId',
      'totalAmount': price * quantity,
      'settledAt': DateTime.now().toIso8601String(),
      'settledBy': 1,
      'shiftId': shiftId,
      'paymentMethod': 'cash',
    });
    await db.db.insert('settled_order_items', {
      'settledOrderId': orderId,
      'itemName': itemName,
      'itemPrice': price,
      'quantity': quantity,
      'category': 'خواردن',
      'waiterName': waiterName,
      'waiterRole': waiterRole,
    });
  }

  SettledOrder order(int id) => SettledOrder(
        id: id,
        tableId: id,
        tableName: 'مێز $id',
        totalAmount: 0,
        settledAt: DateTime.now().toIso8601String(),
        settledBy: 1,
        shiftId: shiftId,
      );

  Future<void> pump(WidgetTester tester, List<SettledOrder> orders) async {
    tester.view.physicalSize = const Size(1200, 2400);
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
                child: ShiftCaptainReportView(orders: orders),
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

  testWidgets('a cashier who adds food counts as a salesperson', (tester) async {
    await db.addUser('کاپتن ئاراس', '10001', UserRole.waiter);
    await db.addUser('کاشێر شیلان', '10002', UserRole.cashier);

    await seedLine(
      orderId: 1,
      waiterName: 'کاپتن ئاراس',
      waiterRole: 0,
      itemName: 'شیرینی',
      price: 5000,
      quantity: 2,
    );
    await seedLine(
      orderId: 2,
      waiterName: 'کاشێر شیلان',
      waiterRole: 1,
      itemName: 'چای',
      price: 1000,
      quantity: 3,
    );

    await pump(tester, [order(1), order(2)]);

    // Both show up, each with the dishes they rang in.
    expect(find.text('کاپتن ئاراس'), findsOneWidget);
    expect(find.text('کاشێر شیلان'), findsOneWidget);
    expect(find.textContaining('کاشێر  •  خواردنەکان: 3'), findsOneWidget);
    expect(find.textContaining('کاپتن  •  خواردنەکان: 2'), findsOneWidget);
    // The money is the value of each person's own dishes.
    expect(find.text('د.ع ${money(10000)}'), findsOneWidget);
    expect(find.text('د.ع ${money(3000)}'), findsOneWidget);
  });

  testWidgets('every captain is listed, even with nothing sold', (tester) async {
    await db.addUser('کاپتن بێ کار', '10003', UserRole.waiter);

    await pump(tester, const []);

    expect(find.text('کاپتن بێ کار'), findsOneWidget);
    expect(find.text('کاپتن  •  خواردنەکان: 0'), findsOneWidget);
    // A cashier with no sales is not worth a row, so the list stays short.
    expect(find.textContaining('کاشێر'), findsNothing);
  });

  testWidgets('a sale with no known seller is still counted', (tester) async {
    // A legacy line: settled before the adder was recorded.
    await seedLine(
      orderId: 1,
      waiterName: '',
      waiterRole: -1,
      itemName: 'چای',
      price: 1000,
      quantity: 4,
    );

    await pump(tester, [order(1)]);

    // The unknown-seller row is the bare dish count (no role label).
    expect(find.text('خواردنەکان: 4'), findsOneWidget);
    expect(find.text('د.ع ${money(4000)}'), findsOneWidget);
  });
}
