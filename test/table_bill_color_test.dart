import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  group('کاشێر - ڕەنگی مێزەکان', () {
    test('مێزە دانیشتووەکان سەوزن و requestBill تەنها مێزی داواکراو دەکاتە شین', () async {
      await db.occupyTable(1, '101', guestCount: 2);
      await db.occupyTable(2, '101', guestCount: 2);
      await db.occupyTable(3, '101', guestCount: 2);

      expect((await db.getTable(1))!.status, TableStatus.occupied);
      expect((await db.getTable(2))!.status, TableStatus.occupied);
      expect((await db.getTable(3))!.status, TableStatus.occupied);

      await db.requestBill(1);

      expect((await db.getTable(1))!.status, TableStatus.billRequested);
      expect((await db.getTable(1))!.printedAt, isNotEmpty);
      expect((await db.getTable(2))!.status, TableStatus.occupied);
      expect((await db.getTable(3))!.status, TableStatus.occupied);
    });

    test('مێزە دانیشتووەکان هەرگیز نابنە سور - تەنها مێزی حیسابی نەواسڵکراو دوای 10 خولەک', () async {
      await db.occupyTable(1, '101', guestCount: 2);
      await db.occupyTable(2, '101', guestCount: 2);
      await db.requestBill(1);

      final past = DateTime.now().subtract(const Duration(minutes: 11)).toIso8601String();
      await db.db.update('tables', {'printedAt': past}, where: 'id = ?', whereArgs: [1]);

      await db.checkOverdueTables();

      expect((await db.getTable(1))!.status, TableStatus.overdue);
      expect((await db.getTable(2))!.status, TableStatus.occupied,
          reason: 'a seated table with no bill is never swept');
    });

    test('داوای حیسابێکی نوێ هەر نەبیوەتە سور (کەمتر لە 10 خولەک)', () async {
      await db.occupyTable(1, '101');
      await db.requestBill(1);
      await db.checkOverdueTables();
      expect((await db.getTable(1))!.status, TableStatus.billRequested,
          reason: 'a bill printed this second is still blue');
    });

    test('مێزی نوێ کە خواردنی بۆ داواکراوە دەبێتە سەوز', () async {
      await db.occupyTable(4, '101', guestCount: 3);
      expect((await db.getTable(4))!.status, TableStatus.occupied);
    });

    test('markAsPrinted ڕاستەوخۆ مێزەکە دەکاتە شین', () async {
      await db.occupyTable(1, '101');
      await db.markAsPrinted(1);
      final table = await db.getTable(1);
      expect(table!.status, TableStatus.billRequested);
      expect(table.printedAt, isNotEmpty);
    });
  });

  group('گواستنەوەی مێز - پاراستنی دۆخەکەی مێز', () {
    OrderItem item(String id) => OrderItem(id: id, name: 'بیرە', price: 3000, quantity: 2, createdAt: DateTime.now().toIso8601String());

    test('مێزی سەوزی خواردنی لەسەرە بگوازرێتەوە بە هەمان سەوزی - نابێت شین', () async {
      await db.batchSendAndOccupy(1, [item('a-1'), item('a-2')], waiterId: '101');

      expect((await db.getTable(1))!.status, TableStatus.occupied);

      await db.transferItems(1, 6);

      final source = await db.getTable(1);
      final target = await db.getTable(6);
      expect(source!.status, TableStatus.empty);
      expect(target!.status, TableStatus.occupied, reason: 'گواستنەوە دۆخی سەوز دەپارێزێت');
      expect(target.printedAt, isEmpty);
      expect(target.sentToCashier, isTrue, reason: 'ئاگاداری داواکاریەکە نامێنێتەوە');
      expect(await db.getOrderItems(6), hasLength(2));
    });

    test('مێزی شینی حیساب داواکراو بگوازرێتەوە بە هەمان شینی و کاتی چاپەکەی دەپارێزێت', () async {
      await db.batchSendAndOccupy(1, [item('c-1')], waiterId: '101');
      await db.requestBill(1);
      final printed = (await db.getTable(1))!.printedAt;

      await db.transferItems(1, 6);

      final target = await db.getTable(6);
      expect(target!.status, TableStatus.billRequested);
      expect(target.printedAt, printed);
    });

    test('گۆڕینی مێزێکی سەوز بۆ ئامانجی خاڵی دۆخی سەوز دەپارێزێت', () async {
      await db.batchSendAndOccupy(1, [item('b-1')], waiterId: '101');
      expect((await db.getTable(1))!.status, TableStatus.occupied);

      await db.transferSingleItem(1, 6, 'b-1');

      expect((await db.getTable(6))!.status, TableStatus.occupied,
          reason: 'گۆڕینی تاک بەند دۆخی سەوز دەپارێزێت');
      expect((await db.getTable(6))!.printedAt, isEmpty);
    });

    test('تێکەڵکردنی مێزی سەوز لەنێو مێزی خاڵی نابێتە شین', () async {
      OrderItem makeItem(String id) => OrderItem(id: id, name: 'کەباب', price: 700, quantity: 1, createdAt: DateTime.now().toIso8601String());
      await db.batchSendAndOccupy(2, [makeItem('m-1')], waiterId: '101');
      await db.batchSendAndOccupy(3, [makeItem('m-2')], waiterId: '101');
      await db.mergeTables(2, 3);
      final merged = await db.getTable(3);
      expect(merged!.status, TableStatus.occupied, reason: 'تێکەڵکردن دۆخی سەوز دەپارێزێت');
      expect(merged.printedAt, isEmpty);
      expect((await db.getTable(2))!.status, TableStatus.empty);
    });
  });
}