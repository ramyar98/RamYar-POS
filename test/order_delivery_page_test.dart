import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/printer_model.dart';
import 'package:ramyar_pos/page/waiter/order_delivery_page.dart';

/// Renders the captain's delivery screen against a real (in-memory) database
/// and asserts the item-level contract the UI promises:
///
///  * the five filters exist and their counts are counted per DISH, not per
///    table (one order with three arrived dishes cannot read «گەیشت (1)»);
///  * every dish is listed on its own row with its printer and its two status
///    icons - arrival (till) and print (every assigned printer);
///  * selecting «دوبارە پرێنت» hides the dishes that printed and keeps exactly
///    the ones a printer still owes.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    // In-process factory: widget tests run inside a fake-async zone, so an
    // isolate round-trip would never complete.
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

  OrderItem line(String id, String name, {int qty = 1}) => OrderItem(
        id: id,
        name: name,
        price: 1000,
        quantity: qty,
        category: 'خواردن',
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
        child: const MaterialApp(home: OrderDeliveryPage()),
      ),
    );
    // Let the async providers (delivery list, pending count, printers) settle.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Disposes the page so its 5-second refresh timer never outlives the test,
  /// then lets any sqflite lock timeout drain.
  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('empty state when nothing has been sent yet', (tester) async {
    await pumpPage(tester);

    expect(find.text('هیچ داواکارییەک نەنێردراوە'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposePage(tester);
  });

  testWidgets('filters count dishes and «دوبارە پرێنت» keeps only owed dishes',
      (tester) async {
    // One table, two dishes: the first reached the till AND printed, the second
    // is still travelling and has printed nowhere.
    await db.recordOrderSent(1);
    await db.batchAddOrderItems(1, [line('a', 'کەباب'), line('b', 'چای')]);
    await db.markOrderItemsArrived(1, ['a']);
    await db.stampItemPrintResult(
      1,
      ['a'],
      PrinterType.kitchen.index,
      success: true,
    );

    await pumpPage(tester);

    // Counts are per dish: 2 total, 1 arrived, 1 still travelling, 1 printed,
    // 1 still owed a ticket.
    expect(find.text('هەموو (2)'), findsOneWidget);
    expect(find.text('گەیشت (1)'), findsOneWidget);
    expect(find.text('نەگەیشت (1)'), findsOneWidget);
    expect(find.text('پرێنت (1)'), findsOneWidget);
    expect(find.text('دوبارە پرێنت (1)'), findsOneWidget);

    // Both dishes render, each with its resolved printer (kitchen by default).
    expect(find.text('کەباب ×1'), findsOneWidget);
    expect(find.text('چای ×1'), findsOneWidget);
    expect(find.text('چێشتخانە'), findsNWidgets(2));

    // Selecting the reprint filter drops the printed dish and keeps the owed one.
    await tester.tap(find.text('دوبارە پرێنت (1)'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('چای ×1'), findsOneWidget);
    expect(find.text('کەباب ×1'), findsNothing);

    expect(tester.takeException(), isNull);
    await disposePage(tester);
  });

  testWidgets('a dish owed by two printers names both on its row',
      (tester) async {
    await db.recordOrderSent(2);
    await db.batchAddOrderItems(2, [line('a', 'پیتزا', qty: 2)]);
    // Kitchen and bar both failed their ticket for this dish.
    await db.stampItemPrintResult(
      2,
      ['a'],
      PrinterType.kitchen.index,
      success: false,
    );
    await db.stampItemPrintResult(
      2,
      ['a'],
      PrinterType.bar.index,
      success: false,
    );

    await pumpPage(tester);

    // The row lists exactly the printers still owing a ticket, joined with '·'.
    expect(find.text('پیتزا ×2'), findsOneWidget);
    expect(find.text('چێشتخانە · باڕ'), findsOneWidget);

    // The whole dish is in the reprint bucket.
    expect(find.text('دوبارە پرێنت (1)'), findsOneWidget);
    expect(find.text('پرێنت (0)'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await disposePage(tester);
  });

  testWidgets('the desktop grid renders the same item rows', (tester) async {
    await db.recordOrderSent(9);
    await db.batchAddOrderItems(9, [line('a', 'کەباب'), line('b', 'چای')]);
    await db.markOrderItemsArrived(9, ['a', 'b']);
    await db.stampItemPrintResult(
      9,
      ['a'],
      PrinterType.kitchen.index,
      success: true,
    );

    await pumpPage(tester, size: const Size(1200, 900));

    expect(find.text('کەباب ×1'), findsOneWidget);
    expect(find.text('چای ×1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposePage(tester);
  });
}
