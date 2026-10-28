import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/printer_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_order_delivery_page.dart';

/// The cashier's «دۆخی ئۆردەر» screen.
///
/// It exists because the cashier may add food to a table before the captain has
/// started their shift, and they need to see whether those dishes reached the
/// till and whether their tickets printed. The till has no `order_delivery`
/// rows, so this page reads the tables and their dishes instead - these tests
/// pin that contract:
///
///  * only seated tables WITH dishes are listed;
///  * the three filters are the captain's three buckets (no «گەیشت»/«پرێنت»
///    filters), and their counts are per dish;
///  * delivery slots never appear;
///  * a table with no dishes is not work to check.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  OrderItem line(String id, String name, {int qty = 1, String category = 'خواردن'}) =>
      OrderItem(
        id: id,
        name: name,
        price: 1000,
        quantity: qty,
        category: category,
      );

  Future<void> seat(int tableId, List<OrderItem> items) => db.batchSendAndOccupy(
        tableId,
        items,
        guestCount: 2,
        waiterId: '2',
      );

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(414, 896),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CashierOrderDeliveryPage()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Disposes the page so its refresh timer never outlives the test.
  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('empty state when no table has an order', (tester) async {
    await pumpPage(tester);

    expect(find.text('دۆخی ناردنی داواکاری'), findsOneWidget);
    expect(find.text('هیچ داواکارییەک نەنێردراوە'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposePage(tester);
  });

  testWidgets('shows the tables the till is holding and counts each dish',
      (tester) async {
    await seat(1, [line('a', 'کەباب'), line('b', 'چای', category: 'چا')]);
    // Only the first dish has reached the till so far.
    await db.markOrderItemsArrived(1, ['a']);

    await pumpPage(tester);

    expect(find.text('مێز 1'), findsOneWidget);
    expect(find.text('کەباب ×1'), findsOneWidget);
    expect(find.text('چای ×1'), findsOneWidget);

    // Counted per dish, exactly like the captain's screen.
    expect(find.text('هەموو (2)'), findsOneWidget);
    expect(find.text('نەگەیشت (1)'), findsOneWidget);
    expect(find.text('دوبارە پرێنت (2)'), findsOneWidget);

    // The two status filters that only describe a card are not filters here.
    expect(find.text('گەیشت (1)'), findsNothing);
    expect(find.text('پرێنت (0)'), findsNothing);

    expect(tester.takeException(), isNull);
    await disposePage(tester);
  });

  testWidgets('a printed dish drops out of «دوبارە پرێنت»', (tester) async {
    await seat(1, [line('a', 'کەباب'), line('b', 'چای', category: 'چا')]);
    await db.markOrderItemsArrived(1, ['a', 'b']);
    await db.stampItemPrintResult(
      1,
      ['a'],
      PrinterType.kitchen.index,
      success: true,
    );

    await pumpPage(tester);

    expect(find.text('هەموو (2)'), findsOneWidget);
    expect(find.text('نەگەیشت (0)'), findsOneWidget);
    expect(find.text('دوبارە پرێنت (1)'), findsOneWidget);

    await tester.tap(find.text('دوبارە پرێنت (1)'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('چای ×1'), findsOneWidget);
    expect(find.text('کەباب ×1'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposePage(tester);
  });

  testWidgets('an open table with no dishes is not listed', (tester) async {
    await seat(1, [line('a', 'کەباب')]);
    // Table 2 is occupied but nothing has been ordered yet.
    await db.db.update(
      'tables',
      {'status': 1},
      where: 'id = ?',
      whereArgs: [2],
    );

    await pumpPage(tester);

    expect(find.text('مێز 1'), findsOneWidget);
    expect(find.text('مێز 2'), findsNothing);
    expect(find.text('هەموو (1)'), findsOneWidget);

    await disposePage(tester);
  });

  testWidgets('delivery slots never appear', (tester) async {
    await seat(1, [line('a', 'کەباب')]);
    await db.db.insert('tables', {
      'id': LocalDatabase.deliverySlotBase + 3,
      'name': 'دلیڤەری تەلەبات 3',
      'status': 1,
      'isDelivery': 1,
      'deliveryCompanyId': 1,
      'deliverySlot': 3,
      'seatedTime': DateTime.now().toIso8601String(),
      'totalAmount': 5000.0,
      'guestCount': 1,
    });
    await db.batchAddOrderItems(
      LocalDatabase.deliverySlotBase + 3,
      [line('d', 'پیتزا')],
    );

    await pumpPage(tester);

    expect(find.text('مێز 1'), findsOneWidget);
    expect(find.textContaining('تەلەبات 3'), findsNothing);
    expect(find.text('هەموو (1)'), findsOneWidget);

    await disposePage(tester);
  });

  testWidgets('the desktop grid renders the same table cards', (tester) async {
    await seat(1, [line('a', 'کەباب'), line('b', 'چای', category: 'چا')]);
    await db.markOrderItemsArrived(1, ['a', 'b']);

    await pumpPage(tester, size: const Size(1200, 900));

    expect(find.text('مێز 1'), findsOneWidget);
    expect(find.text('کەباب ×1'), findsOneWidget);
    expect(find.text('چای ×1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposePage(tester);
  });
}
