import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_delivery_model.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/printer_model.dart';

/// Guards the move from "did the TABLE arrive / print?" to per-dish truth:
/// did THIS dish reach the till, and did THIS dish's ticket come out of every
/// one of ITS printers? Those two answers drive the captain's delivery screen.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;

  setUp(() async {
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

  group('per-dish arrival', () {
    test('markOrderItemsArrived stamps only the echoed ids', () async {
      await db.recordOrderSent(3);
      await db.batchAddOrderItems(3, [line('a', 'کەباب'), line('b', 'چای')]);

      await db.markOrderItemsArrived(3, ['a']);

      final items = await db.getOrderItems(3);
      final a = items.firstWhere((i) => i.id == 'a');
      final b = items.firstWhere((i) => i.id == 'b');
      expect(a.arrived, isTrue, reason: 'the echoed dish reached the till');
      expect(a.syncedAt, isNotEmpty);
      expect(b.arrived, isFalse, reason: 'a dish nobody echoed is still travelling');
      expect(b.syncedAt, isEmpty);
    });

    test('markOrderItemsArrived with no ids backfills every unarrived line',
        () async {
      await db.recordOrderSent(4);
      await db.batchAddOrderItems(4, [line('a', 'کەباب'), line('b', 'چای')]);

      // A legacy ack carries no itemIds; the whole table is acknowledged.
      await db.markOrderItemsArrived(4, null);

      final items = await db.getOrderItems(4);
      expect(items.every((i) => i.arrived), isTrue);
    });

    test('markOrderItemsArrived is idempotent on already-arrived lines',
        () async {
      await db.recordOrderSent(7);
      await db.batchAddOrderItems(7, [line('a', 'کەباب')]);
      await db.markOrderItemsArrived(7, ['a']);
      final first = (await db.getOrderItems(7)).first.syncedAt;

      await db.markOrderItemsArrived(7, ['a']);

      final second = (await db.getOrderItems(7)).first.syncedAt;
      expect(second, first, reason: 'the first arrival stamp is kept');
    });
  });

  group('per-dish printing', () {
    test('a dish routed to two printers prints only when BOTH succeed',
        () async {
      await db.recordOrderSent(5);
      await db.batchAddOrderItems(5, [line('a', 'پیتزا')]);

      // Kitchen printed first - the dish is not done, bar is still owed.
      await db.stampItemPrintResult(
        5,
        ['a'],
        PrinterType.kitchen.index,
        success: true,
      );
      var it = (await db.getOrderItems(5)).first;
      expect(it.printedAt, isNotEmpty);
      expect(it.printed, isTrue, reason: 'bar was never recorded as failed yet');

      // The bar printer then fails its ticket.
      await db.stampItemPrintResult(
        5,
        ['a'],
        PrinterType.bar.index,
        success: false,
      );
      it = (await db.getOrderItems(5)).first;
      expect(it.failedPrinterTypes, [PrinterType.bar.index]);
      expect(it.needsPrint, isTrue, reason: 'one printer still owes a ticket');
      expect(it.printed, isFalse);

      // Bar catches up - now every assigned printer has done its part.
      await db.stampItemPrintResult(
        5,
        ['a'],
        PrinterType.bar.index,
        success: true,
      );
      it = (await db.getOrderItems(5)).first;
      expect(it.failedPrinterTypes, isEmpty);
      expect(it.printed, isTrue);
    });

    test('a second failure on the same printer is not duplicated', () async {
      await db.recordOrderSent(8);
      await db.batchAddOrderItems(8, [line('a', 'پیتزا')]);

      await db.stampItemPrintResult(
        8,
        ['a'],
        PrinterType.bar.index,
        success: false,
      );
      await db.stampItemPrintResult(
        8,
        ['a'],
        PrinterType.bar.index,
        success: false,
      );

      final it = (await db.getOrderItems(8)).first;
      expect(it.failedPrinterTypes, [PrinterType.bar.index]);
    });

    test('print success on one dish never touches its neighbour', () async {
      await db.recordOrderSent(9);
      await db.batchAddOrderItems(9, [line('a', 'کەباب'), line('b', 'چای')]);

      await db.stampItemPrintResult(
        9,
        ['a'],
        PrinterType.kitchen.index,
        success: true,
      );

      final items = await db.getOrderItems(9);
      expect(items.firstWhere((i) => i.id == 'a').printed, isTrue);
      expect(items.firstWhere((i) => i.id == 'b').printed, isFalse);
    });
  });

  group('delivery view joins per-dish state', () {
    test('getOrderDeliveries attaches items and derives the count getters',
        () async {
      await db.recordOrderSent(6);
      await db.batchAddOrderItems(6, [line('a', 'کەباب'), line('b', 'چای')]);
      await db.markOrderItemsArrived(6, ['a', 'b']);
      await db.stampItemPrintResult(
        6,
        ['a'],
        PrinterType.kitchen.index,
        success: true,
      );

      final d = (await db.getOrderDeliveries())
          .firstWhere((x) => x.tableId == 6);
      expect(d.items, hasLength(2));
      expect(d.hasItemState, isTrue);
      expect(d.itemTotal, 2);
      expect(d.arrivedItemCount, 2);
      expect(d.printedItemCount, 1);
      expect(d.allItemsArrived, isTrue);
      expect(d.allItemsPrinted, isFalse);
      expect(d.unprintedItems.map((i) => i.id), ['b']);
      expect(d.pendingItems, isEmpty);
      expect(d.itemStatusLabel, 'arrived');
    });

    test('a dish with a failed printer drives the reprint list', () async {
      await db.recordOrderSent(10);
      await db.batchAddOrderItems(10, [line('a', 'کەباب'), line('b', 'چای')]);
      await db.markOrderItemsArrived(10, ['a', 'b']);
      await db.stampItemPrintResult(
        10,
        ['a'],
        PrinterType.kitchen.index,
        success: true,
      );
      await db.stampItemPrintResult(
        10,
        ['b'],
        PrinterType.bar.index,
        success: false,
      );

      final d = (await db.getOrderDeliveries())
          .firstWhere((x) => x.tableId == 10);
      expect(d.anyItemPrintFailed, isTrue);
      expect(d.unprintedItems.map((i) => i.id), ['b']);
      expect(d.itemStatusLabel, 'print_failed');
      expect(d.allItemsArrived, isTrue);
    });

    test('dishes still travelling keep the card in the waiting bucket',
        () async {
      await db.recordOrderSent(11);
      await db.batchAddOrderItems(11, [line('a', 'کەباب'), line('b', 'چای')]);
      await db.markOrderItemsArrived(11, ['a']);

      final d = (await db.getOrderDeliveries())
          .firstWhere((x) => x.tableId == 11);
      expect(d.pendingItems.map((i) => i.id), ['b']);
      expect(d.allItemsArrived, isFalse);
      expect(d.itemStatusLabel, 'not_arrived');
    });

    test('an order with no items reads as legacy (no item state)', () async {
      await db.recordOrderSent(12);
      await db.markOrderArrived(12);

      final d = (await db.getOrderDeliveries())
          .firstWhere((x) => x.tableId == 12);
      expect(d.hasItemState, isFalse);
      expect(d.items, isEmpty);
      expect(d.itemStatusLabel, d.statusLabel);
      expect(d.itemStatusLabel, 'arrived');
    });

    test('a rejected order labels as rejected regardless of dishes', () async {
      await db.recordOrderSent(13);
      await db.batchAddOrderItems(13, [line('a', 'کەباب')]);
      await db.markOrderArrived(13, rejected: true);

      final d = (await db.getOrderDeliveries())
          .firstWhere((x) => x.tableId == 13);
      expect(d.rejected, isTrue);
      expect(d.itemStatusLabel, 'rejected');
    });
  });

  group('DeliveryItemStatus model', () {
    test('printed requires a stamp and no owed printer', () {
      const done = DeliveryItemStatus(id: 'a', name: 'x', printedAt: 't');
      const owed = DeliveryItemStatus(
        id: 'a',
        name: 'x',
        printedAt: 't',
        failedPrinters: '1',
      );
      const none = DeliveryItemStatus(id: 'a', name: 'x');
      expect(done.printed, isTrue);
      expect(done.needsPrint, isFalse);
      expect(owed.printed, isFalse);
      expect(owed.needsPrint, isTrue);
      expect(none.needsPrint, isTrue);
    });

    test('failedPrinterTypes parses a CSV of printer indexes', () {
      const it = DeliveryItemStatus(
        id: 'a',
        name: 'x',
        failedPrinters: '1,2',
      );
      expect(it.failedPrinterTypes, [1, 2]);
      expect(it.printFailed, isTrue);
    });
  });
}
