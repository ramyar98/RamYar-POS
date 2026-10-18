import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/printer_model.dart';
import 'package:ramyar_pos/models/receipt_design_model.dart';
import 'package:ramyar_pos/page/admin/admin_print_design_page.dart';
import 'package:ramyar_pos/services/esc_pos_builder.dart';

/// «دیزاینی پرێنت» - the receipt the admin designs.
///
/// The design is one JSON row in `shop_settings`; the builder turns it into the
/// slip. These tests cover both halves: the switches really add and drop lines
/// from the printed bytes, and the design survives a save/read round-trip (and a
/// stale sync message cannot undo a newer save).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  const items = [
    PrintJobItem(name: 'برگر', quantity: 2, category: 'بەرگەر', price: 5000),
  ];

  List<String> layoutText(ReceiptDesign design) => EscPosBuilder.receiptLayout(
    tableNumber: 1,
    guestCount: 2,
    items: items,
    subtotal: 10000,
    discountPercent: 0,
    discountAmount: 0,
    total: 10000,
    waiterName: 'Ali',
    cashierName: 'Sara',
    seatedAt: '2026-01-01T10:00:00.000',
    tableLabel: 'مێز 1',
    design: design,
  ).map((l) => l.text).toList();

  test('the standard design keeps every section of the old receipt', () {
    final lines = layoutText(ReceiptDesign.standard).join('\n');
    expect(lines.contains('B I A B L O'), isTrue);
    expect(lines.contains('وەسڵی کاشێر'), isTrue);
    expect(lines.contains('مێز 1'), isTrue);
    expect(lines.contains('کاپتن: Ali'), isTrue);
    expect(lines.contains('کاشێر: Sara'), isTrue);
    expect(lines.contains('خواردنەکان'), isTrue);
    expect(lines.contains('کۆی یەکەم'), isTrue);
    expect(lines.contains('کۆی گشتی'), isTrue);
    expect(lines.contains('سوپاس بۆ بەکارهێنانی'), isTrue);
  });

  test('turning a section off drops it from the slip', () {
    final lines = layoutText(
      const ReceiptDesign(
        showShopName: false,
        showHeaderTitle: false,
        showItems: false,
        showSubtotal: false,
        showTotal: false,
        showFooter: false,
        showWaiter: false,
        showCashier: false,
      ),
    ).join('\n');
    expect(lines.contains('B I A B L O'), isFalse);
    expect(lines.contains('وەسڵی کاشێر'), isFalse);
    expect(lines.contains('خواردنەکان'), isFalse);
    expect(lines.contains('کۆی یەکەم'), isFalse);
    expect(lines.contains('کۆی گشتی'), isFalse);
    expect(lines.contains('سوپاس بۆ بەکارهێنانی'), isFalse);
    expect(lines.contains('کاپتن'), isFalse);
    expect(lines.contains('کاشێر'), isFalse);
    // The title the admin typed replaces the built-in one.
    final custom = layoutText(
      const ReceiptDesign(headerTitle: 'قاوەخانەی ئازادی'),
    ).join('\n');
    expect(custom.contains('قاوەخانەی ئازادی'), isTrue);
    expect(custom.contains('وەسڵی کاشێر'), isFalse);
  });

  test('the printed bytes honour the design too', () {
    // A hidden dish list must not appear on paper: the bytes are what the
    // printer actually receives, so they are the real contract.
    final bytes = EscPosBuilder.buildCashierReceipt(
      tableNumber: 1,
      guestCount: 2,
      items: items,
      subtotal: 10000,
      discountPercent: 0,
      discountAmount: 0,
      total: 10000,
      tableLabel: 'مێز 1',
      design: const ReceiptDesign(showItems: false, shopName: 'قاوەخانە'),
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    expect(text.contains('قاوەخانە'), isTrue);
    expect(text.contains('برگر'), isFalse);
  });

  group('storage', () {
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

    test('a saved design is read back unchanged', () async {
      const design = ReceiptDesign(
        shopName: 'قاوەخانەی ئازادی',
        headerTitle: 'وەسڵ',
        separatorStyle: 'dots',
        showItems: false,
        paperWidth: 32,
        feedBeforeCut: 6,
        footerText: 'سوپاس',
      );
      // An untouched device prints the stock receipt...
      expect(await db.getReceiptDesign(), ReceiptDesign.standard);

      await db.setReceiptDesign(design);
      expect(await db.getReceiptDesign(), design);
    });

    test('the revision bumps so open screens re-read the design', () async {
      final before = db.receiptDesignRevision.value;
      await db.setReceiptDesign(const ReceiptDesign(shopName: 'X'));
      expect(db.receiptDesignRevision.value, greaterThan(before));
    });

    test('an older synced design does not overwrite a newer one', () async {
      await db.applyReceiptDesign(
        const ReceiptDesign(shopName: 'New'),
        updatedAt: '2026-02-02T10:00:00.000',
      );
      await db.applyReceiptDesign(
        const ReceiptDesign(shopName: 'Old'),
        updatedAt: '2026-01-01T10:00:00.000',
      );
      expect((await db.getReceiptDesign()).shopName, 'New');
    });
  });

  testWidgets('the design screen previews the switches live', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() async => db.resetForTesting());

    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: AppState(
          currentLanguage: AppLanguage.kurdish,
          onLanguageChanged: (_) {},
          child: const MaterialApp(home: AdminPrintDesignPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('دیزاینی پرێنت'), findsOneWidget);
    expect(find.textContaining('B I A B L O'), findsWidgets);
    expect(find.textContaining('مێز 1'), findsOneWidget);

    // Turning the table row off takes it out of the preview at once.
    await tester.tap(find.text('مێز'));
    await tester.pumpAndSettle();
    expect(find.textContaining('مێز 1'), findsNothing);

    // And the save button stores what the switches now say.
    await tester.tap(find.text('پاشەکەوتکردن'));
    await tester.pumpAndSettle();
    expect((await db.getReceiptDesign()).showTable, isFalse);
  });
}
