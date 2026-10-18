import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/responsive.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/delivery_company_model.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_unified_table_page.dart';
import 'package:ramyar_pos/page/cashier/delivery_page.dart';

/// Request 4: the cashier's delivery section.
///
/// Under the app bar sits a second bar listing the delivery companies, in the
/// order the shop set, which can be dragged into a new order and added to.
/// Below it sit that company's own slots - fifty to begin with, raised or
/// lowered by the cashier; tapping one opens it as an order the cashier rings
/// food in on, with the «حساب» section underneath. A company holding food
/// cannot be deleted until that food is settled or thrown out.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The isolating factory hangs widget tests.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late LocalDatabase db;
  final mutations = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mutations.clear();
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    // After the reset, which clears the hook on purpose.
    db.onMutation = (action, _) => mutations.add(action);
    // Start from a clean registry so the shop's defaults are not in the way.
    for (final company in await db.getDeliveryCompanies()) {
      await db.deleteDeliveryCompany(company.id);
    }
    mutations.clear();
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  /// Takes the pages off the screen before the database is closed, the way
  /// leaving the app does - a live-update listener firing on a closed database
  /// is an error nothing can catch.
  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> openPage(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [localDbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: DeliveryPage()),
    ));
    // Registered so the pages come off the screen before the database closes,
    // even when the test itself fails part way through.
    addTearDown(() => closePage(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens a slot the way the cashier does: tap it, land on the order page.
  Future<void> openSlot(WidgetTester tester, int slotNumber) async {
    await tester.tap(find.byKey(Key('delivery-slot-$slotNumber')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('the company bar', () {
    testWidgets('lists the companies under the app bar', (tester) async {
      await db.addDeliveryCompany('ئەمازۆن');
      await db.addDeliveryCompany('پیتا');
      await openPage(tester);

      expect(find.byKey(const Key('delivery-company-bar')), findsOneWidget,
          reason: 'the bar sits between the app bar and the slots');
      expect(find.text('ئەمازۆن'), findsWidgets);
      expect(find.text('پیتا'), findsWidgets);
    });

    testWidgets('a company added now goes to the end of the bar',
        (tester) async {
      await db.addDeliveryCompany('یەکەم');
      await db.addDeliveryCompany('دووەم');
      await db.addDeliveryCompany('سێیەم');
      expect((await db.getDeliveryCompanies()).map((c) => c.name).last,
          'سێیەم');

      // Adding used to write sortOrder 0, so every company the cashier added
      // jumped to the front of the bar instead of after the ones already there.
      await openPage(tester);
      await tester.tap(find.byKey(const Key('add-delivery-company')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const Key('delivery-company-name')), 'چوارەم');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-delivery-company')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final order = (await db.getDeliveryCompanies()).map((c) => c.name).toList();
      expect(order, ['یەکەم', 'دووەم', 'سێیەم', 'چوارەم']);
    });

    testWidgets('the add button refuses a name already on the bar',
        (tester) async {
      await db.addDeliveryCompany('ئەمازۆن');
      await openPage(tester);
      await tester.tap(find.byKey(const Key('add-delivery-company')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const Key('delivery-company-name')), 'ئەمازۆن');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-delivery-company')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(await db.getDeliveryCompanies(), hasLength(1),
          reason: 'two chips with the same name are a mystery on the bar');
    });

    testWidgets('a chip can be dragged into another place', (tester) async {
      await db.addDeliveryCompany('یەکەم');
      await db.addDeliveryCompany('دووەم');
      await db.addDeliveryCompany('سێیەم');
      await openPage(tester);

      expect(find.byType(ReorderableListView), findsOneWidget);
      final chips = find.byType(ReorderableDragStartListener);
      expect(chips, findsNWidgets(3));

      // Drag the last chip to the far left, the way a hand would.
      final gesture =
          await tester.startGesture(tester.getCenter(chips.last));
      await tester.pump();
      await gesture.moveBy(const Offset(-600, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final order = (await db.getDeliveryCompanies()).map((c) => c.name).toList();
      expect(order, ['سێیەم', 'یەکەم', 'دووەم'],
          reason: 'the dragged chip keeps the place it was dropped in');
    });

    test('a reordering is sent to the other devices', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final b = await db.addDeliveryCompany('دووەم');
      mutations.clear();
      await db.reorderDeliveryCompanies([b, a]);
      expect(mutations, contains('DELIVERY_COMPANIES_REORDERED'),
          reason: 'a bar only one till has reordered is not the shop\'s bar');
      expect((await db.getDeliveryCompanies()).map((c) => c.id), [b, a]);
    });

    test('a reordering that changes nothing stays quiet', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final b = await db.addDeliveryCompany('دووەم');
      mutations.clear();
      await db.reorderDeliveryCompanies([a, b]);
      expect(mutations, isEmpty,
          reason: 'a drag that lands where it started should not make every '
              'other till redraw its bar');
    });
  });

  group('the delivery slots', () {
    test('a slot is a real table, kept out of the dining room', () async {
      final companyId = await db.addDeliveryCompany('تەلەبات');
      final table = await db.ensureDeliverySlot(companyId, 'تەلەبات', 4);

      expect(table.isDelivery, isTrue);
      expect(table.deliveryCompanyId, companyId);
      expect(table.deliverySlot, 4);
      expect(table.name, 'تەلەبات 4');

      // A delivery order is a real order, so it has to exist where orders live.
      final room = (await db.getAllTables()).where((t) => t.isDelivery);
      expect(room, isEmpty,
          reason: 'a delivery must never turn up in the table grid');
      expect(await db.getAllTables(includeDelivery: true),
          contains(predicate<TableModel>((t) => t.id == table.id)));

      // Opening the same slot twice must not create a second order.
      final again = await db.ensureDeliverySlot(companyId, 'تەلەبات', 4);
      expect(again.id, table.id);
      expect((await db.getDeliverySlots(companyId)), hasLength(1));
    });

    test('the slots of different companies never collide', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final b = await db.addDeliveryCompany('دووەم');
      final t1 = await db.ensureDeliverySlot(a, 'یەکەم', 1);
      final t2 = await db.ensureDeliverySlot(b, 'دووەم', 1);
      expect(t1.id, isNot(t2.id));
      // And neither can be mistaken for a dining table.
      expect(t1.id, greaterThan(LocalDatabase.deliverySlotBase));
      expect(t2.id, greaterThan(LocalDatabase.deliverySlotBase));
    });

    testWidgets('tapping a slot opens it as an order', (tester) async {
      final id = await db.addDeliveryCompany('تەلەبات');
      await openPage(tester);
      await openSlot(tester, 3);

      final tableId = LocalDatabase.deliverySlotTableId(id, 3);
      expect(await db.getTable(tableId), isNotNull,
          reason: 'the order behind the slot is made the first time it opens');
      expect(find.byType(CashierUnifiedTablePage), findsOneWidget,
          reason: 'a delivery is worked on the same page as a table');
      // The ticket, the note and clearing it all still make sense...
      expect(find.byTooltip('زانیاری مێز'), findsOneWidget);
      expect(find.byTooltip('تێبینی'), findsOneWidget);
      // ...but a slot has no name to change and is not moved to a table.
      expect(find.byTooltip('گۆڕینی ناوی مێز'), findsNothing);
      expect(find.byTooltip('گواستنەوەی مێز'), findsNothing);
    });

    testWidgets('the slot is named after its company, not its number',
        (tester) async {
      final id = await db.addDeliveryCompany('تەلەبات');
      await openPage(tester);
      await openSlot(tester, 4);

      // "مێزی 100104" tells the cashier nothing; the company's own name does.
      expect(find.text('تەلەبات 4'), findsOneWidget);
      expect(find.textContaining('${LocalDatabase.deliverySlotTableId(id, 4)}'),
          findsNothing);
    });

    testWidgets('the cashier can add food to a slot and bill it',
        (tester) async {
      final id = await db.addDeliveryCompany('تەلەبات');
      final tableId = LocalDatabase.deliverySlotTableId(id, 1);
      await openPage(tester);
      await openSlot(tester, 1);

      // The food tab, and the «حساب» tab, are the ordinary table ones.
      expect(find.text('خواردن'), findsOneWidget);
      expect(find.text('حیساب'), findsOneWidget);

      await tester.tap(find.text('خواردن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // A dish the shop's own menu ships, so the test does not depend on the
      // grid having been scrolled to find a freshly added one.
      await tester.tap(find.text('بەرگەری گۆشتی').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // On a delivery the cashier is taking the order down, so the button says
      // it is being recorded rather than promising to send it somewhere.
      await tester.tap(find.text('تۆمارکردن').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(await db.getOrderItems(tableId), hasLength(1));
      final table = await db.getTable(tableId);
      expect(table!.totalAmount, 5000);
      expect(table.status, TableStatus.occupied);
    });

    testWidgets('a slot in use shows what is on it', (tester) async {
      final id = await db.addDeliveryCompany('تەلەبات');
      final table = await db.ensureDeliverySlot(id, 'تەلەبات', 2);
      await db.addOrderItem(
        table.id,
        OrderItem(
          id: 'x1',
          name: 'چای',
          price: 1000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      await db.occupyTable(table.id, '1', guestCount: 2);

      await openPage(tester);

      // The same delivery rung in twice is the mistake this prevents.
      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
      expect(find.textContaining('1,000'), findsWidgets);
    });
  });

  group('how big a company is', () {
    testWidgets('the grid opens with fifty slots', (tester) async {
      await db.addDeliveryCompany('تەلەبات');
      await openPage(tester);

      final grid =
          tester.widget<ResponsiveGridView>(find.byType(ResponsiveGridView));
      expect(grid.itemCount, 50,
          reason: 'a branch needs room for its whole day of deliveries');
      expect(
        find.descendant(
          of: find.byKey(const Key('delivery-slot-count-badge')),
          matching: find.text('50'),
        ),
        findsOneWidget,
        reason: 'the header says how big this company is',
      );
    });

    testWidgets('the cashier raises a company from the panel', (tester) async {
      final id = await db.addDeliveryCompany('تەلەبات');
      await openPage(tester);

      await tester.tap(find.byKey(const Key('edit-delivery-slot-count')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('delivery-slot-count')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('delivery-slot-count')), '70');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-delivery-slot-count')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect((await db.getDeliveryCompany(id))!.slotCount, 70);
      expect(tester.widget<ResponsiveGridView>(find.byType(ResponsiveGridView))
          .itemCount, 70);
    });

    testWidgets('a number the panel cannot use is refused, not obeyed',
        (tester) async {
      final id = await db.addDeliveryCompany('تەلەبات');
      await openPage(tester);

      // Slot numbers are worked out per company, so 500 would run into the
      // next company. The dialog says the range rather than silently obeying.
      await tester.tap(find.byKey(const Key('edit-delivery-slot-count')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('99'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('delivery-slot-count')), '500');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-delivery-slot-count')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect((await db.getDeliveryCompany(id))!.slotCount, 99);
    });
  });

  group('a company holding food', () {
    /// A company with one delivery rung in on it - the case the delete has to
    /// refuse.
    Future<int> busyCompany() async {
      final id = await db.addDeliveryCompany('تەلەبات');
      final slot = await db.ensureDeliverySlot(id, 'تەلەبات', 1);
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'x1',
          name: 'چای',
          price: 1000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      return id;
    }

    Future<void> tapDelete(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('delete-delivery-company')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('deleting it is refused and says what is in the way',
        (tester) async {
      final id = await busyCompany();
      await openPage(tester);
      await tapDelete(tester);

      // Not the plain confirmation - the reason, and a way out.
      expect(find.byKey(const Key('void-delivery-request')), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      // The grid tile carries the same name, so look inside the dialog only.
      expect(find.descendant(of: dialog, matching: find.text('تەلەبات 1')),
          findsOneWidget,
          reason: 'the cashier is told which delivery is stuck');
      expect(find.descendant(of: dialog, matching: find.textContaining('د.ع')),
          findsOneWidget,
          reason: '...and how much is on it');
      expect(find.text('سڕینەوەی کۆمپانیا'), findsNothing,
          reason: 'nothing is deleted while the food is still out');

      await tester.tap(find.text('هەڵوەشاندنەوە'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(await db.getDeliveryCompany(id), isNotNull);
      expect(await db.getOccupiedDeliverySlots(id), hasLength(1),
          reason: 'backing out leaves the order exactly as it was');
    });

    testWidgets('the dialog can open the stuck order instead', (tester) async {
      final id = await busyCompany();
      await openPage(tester);
      await tapDelete(tester);

      await tester.tap(find.text('بینینی'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Straight to the order so it can be settled there.
      expect(find.byType(CashierUnifiedTablePage), findsOneWidget);
      expect(await db.getDeliveryCompany(id), isNotNull);
    });

    testWidgets('throwing the request out clears it and then asks to delete',
        (tester) async {
      final id = await busyCompany();
      await openPage(tester);
      await tapDelete(tester);

      await tester.tap(find.byKey(const Key('void-delivery-request')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      // The void frees the slots, but the company still does not vanish
      // silently: the ordinary confirmation runs first.
      expect(find.text('سڕینەوەی کۆمپانیا'), findsOneWidget);
      expect(await db.getDeliveryCompany(id), isNotNull);
      // The food is kept on the discarded-items page, not quietly erased.
      expect(await db.getPendingCancelledItems(), hasLength(1));

      await tester.tap(find.widgetWithText(FilledButton, 'سڕینەوە'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(await db.getDeliveryCompany(id), isNull);
    });
  });

  group('what a company removal takes with it', () {
    test('a company with food on it refuses to be deleted', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final slot = await db.ensureDeliverySlot(a, 'یەکەم', 1);
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'live',
          name: 'کەباب',
          price: 10000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      // Money rung in against the company must not vanish because someone
      // tidied the bar away. The cashier settles or voids first.
      expect(await db.deleteDeliveryCompany(a), isFalse);
      expect(await db.getTable(slot.id), isNotNull);
      expect(await db.getOrderItems(slot.id), hasLength(1));
      expect((await db.getDeliveryCompanies()).map((c) => c.id), contains(a));
    });

    test('an unused slot does not hold the company back', () async {
      // A slot that was opened but never ordered on holds nothing, so there is
      // nothing to lose and the company can go.
      final a = await db.addDeliveryCompany('یەکەم');
      final b = await db.addDeliveryCompany('دووەم');
      final keep = await db.ensureDeliverySlot(b, 'دووەم', 1);
      await db.ensureDeliverySlot(a, 'یەکەم', 1);

      expect(await db.deleteDeliveryCompany(a), isTrue);
      // Leaving the row behind would strand a slot that belongs to no company,
      // so it shows up nowhere.
      final dropId = LocalDatabase.deliverySlotTableId(a, 1);
      expect(await db.getTable(dropId), isNull);
      // The other company's order is none of its business.
      expect(await db.getTable(keep.id), isNotNull);
      expect((await db.getDeliveryCompanies()).map((c) => c.id), [b]);
    });

    test('voiding the request frees the company and audits every line',
        () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final slot = await db.ensureDeliverySlot(a, 'یەکەم', 1);
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'one',
          name: 'کەباب',
          price: 10000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'two',
          name: 'برنج',
          price: 5000,
          quantity: 2,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      expect(await db.getOccupiedDeliverySlots(a), hasLength(1));
      final voided = await db.voidTableOrder(slot.id, cancelledBy: 7,
          cancelledByName: 'کاشێر');
      expect(voided, 2);
      expect(await db.getOrderItems(slot.id), isEmpty);
      // The thrown-out food is kept on the discarded-items page rather than
      // quietly erased.
      expect(await db.getPendingCancelledItems(), hasLength(2));
      expect(
          (await db.getPendingCancelledItems()).first.cancelledByName, 'کاشێر');

      expect(await db.deleteDeliveryCompany(a), isTrue);
      expect((await db.getDeliveryCompanies()).map((c) => c.id), isNot(contains(a)));
    });

    test('a forced delete follows the device that already cleared the slots',
        () async {
      // The sync layer forces it: the delete was decided where the orders
      // were, so a till that has not caught up must not keep a company the
      // whole shop already removed.
      final a = await db.addDeliveryCompany('یەکەم');
      final slot = await db.ensureDeliverySlot(a, 'یەکەم', 1);
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'stale',
          name: 'کەباب',
          price: 10000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      expect(await db.deleteDeliveryCompany(a, force: true), isTrue);
      expect(await db.getTable(slot.id), isNull);
      expect((await db.getDeliveryCompanies()).map((c) => c.id), isNot(contains(a)));
    });
  });

  group('per-company slot counts', () {
    test('a new company starts with fifty slots', () async {
      final id = await db.addDeliveryCompany('تەلەبات');
      expect((await db.getDeliveryCompany(id))!.slotCount, 50);
    });

    test('the cashier can raise and lower a company on its own', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final b = await db.addDeliveryCompany('دووەم');

      expect(await db.setDeliveryCompanySlotCount(a, 80), 80);
      // Each company keeps its own number: the grid is not one shared size.
      expect((await db.getDeliveryCompany(a))!.slotCount, 80);
      expect((await db.getDeliveryCompany(b))!.slotCount, 50);

      expect(await db.setDeliveryCompanySlotCount(a, 30), 30);
      expect((await db.getDeliveryCompany(a))!.slotCount, 30);
      expect((await db.getDeliveryCompany(b))!.slotCount, 50);
    });

    test('a count can never hide a slot that already holds an order', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final slot = await db.ensureDeliverySlot(a, 'یەکەم', 40);
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'late',
          name: 'کەباب',
          price: 10000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      // Shrinking to 10 would take slot 40 off the grid while its food is
      // still out, so the floor is what is already in use.
      expect(await db.setDeliveryCompanySlotCount(a, 10), 40);
      expect((await db.getDeliveryCompany(a))!.slotCount, 40);
    });

    test('a count cannot run into the next company', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      expect(await db.setDeliveryCompanySlotCount(a, 5000), 99);
      // Slot numbering is base + companyId * 100 + slot, so 99 is the last
      // number that stays clear of the next company's first slot.
      expect(LocalDatabase.deliverySlotTableId(a, 99),
          lessThan(LocalDatabase.deliverySlotTableId(a + 1, 1)));
    });

    test('a slot outside the addressable range is refused', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      final b = await db.addDeliveryCompany('دووەم');
      // Slot 100 of one company IS slot 0 of the next: sharing a row would put
      // two companies' food on one bill.
      expect(() => db.ensureDeliverySlot(a, 'یەکەم', 100), throwsArgumentError);
      expect(() => db.ensureDeliverySlot(a, 'یەکەم', 0), throwsArgumentError);
      final slot = await db.ensureDeliverySlot(b, 'دووەم', 1);
      expect((await db.getTable(slot.id))!.deliveryCompanyId, b);
    });

    test('the count reaches another device through the mutation', () async {
      final a = await db.addDeliveryCompany('یەکەم');
      await db.setDeliveryCompanySlotCount(a, 70);
      final company = (await db.getDeliveryCompany(a))!;

      final other = LocalDatabase();
      await other.init(inMemory: true);
      // What the hub puts on the wire.
      await other.applyRemoteDeliveryCompany(
          DeliveryCompany.fromMap(company.toMap()));
      expect((await other.getDeliveryCompany(a))!.slotCount, 70);
      await other.resetForTesting();
    });

    test('a count sent by an older build falls back to the default', () async {
      // No slotCount key at all: the grid must not come back empty.
      final parsed = DeliveryCompany.fromMap({'id': 4, 'name': 'لیزۆ', 'sortOrder': 1});
      expect(parsed.slotCount, 50);
      // Nonsense from a hand-edited row is clamped, not obeyed.
      expect(DeliveryCompany.fromMap({'id': 5, 'name': 'x', 'slotCount': 0}).slotCount,
          50);
      expect(
          DeliveryCompany.fromMap({'id': 6, 'name': 'x', 'slotCount': 5000}).slotCount,
          99);
    });

    test('a device whose table lacks the column still takes the company',
        () async {
      // The shop's hub and its captain handsets are not always on the same
      // build. A hub that sends `slotCount` to a phone whose table has never
      // heard of it used to make SQLite reject the whole statement - so the
      // company neither appeared nor renamed, and a snapshot threw with it.
      final older = LocalDatabase();
      await older.init(inMemory: true);
      await older.db.execute(
          'ALTER TABLE delivery_companies DROP COLUMN slotCount');
      addTearDown(() => older.resetForTesting());
      // Without this the rest of the test would pass whether or not the column
      // really went, and prove nothing.
      final info = await older.db
          .rawQuery('PRAGMA table_info(delivery_companies)');
      expect(info.map((c) => c['name']).toList(), isNot(contains('slotCount')));

      await older.applyRemoteDeliveryCompany(
        const DeliveryCompany(id: 9, name: 'تەلەبات', sortOrder: 3, slotCount: 70),
      );

      final arrived = await older.getDeliveryCompany(9);
      expect(arrived, isNotNull, reason: 'the name still has to arrive');
      expect(arrived!.name, 'تەلەبات');
      expect(arrived.sortOrder, 3);

      // And a snapshot from that same newer hub must not roll itself back.
      await expectLater(
        older.applySnapshot({'delivery_companies': [
          {'id': 9, 'name': 'تەلەبات', 'sortOrder': 4, 'slotCount': 70}
        ]}),
        completes,
      );
      expect((await older.getDeliveryCompany(9))!.sortOrder, 4);
    });
  });

  group('clearing the room', () {
    test('does not throw away live delivery orders', () async {
      final id = await db.addDeliveryCompany('تەلەبات');
      final slot = await db.ensureDeliverySlot(id, 'تەلەبات', 1);
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'live',
          name: 'کەباب',
          price: 10000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      await db.occupyTable(slot.id, '1', guestCount: 2);

      await db.clearAllTables();

      // "Clear the floor" is not a decision to throw away food that is still
      // out for delivery and money that is owed on it.
      expect(await db.getOrderItems(slot.id), hasLength(1));
      expect((await db.getTable(slot.id))!.status, TableStatus.occupied);
    });

    test('resetting the table numbers keeps live delivery orders', () async {
      final id = await db.addDeliveryCompany('تەلەبات');
      final slot = await db.ensureDeliverySlot(id, 'تەلەبات', 1);
      await db.addOrderItem(
        slot.id,
        OrderItem(
          id: 'live',
          name: 'چای',
          price: 1000,
          quantity: 1,
          category: 'گەرمی',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      await db.resetTablesToRange(10);

      expect(await db.getOrderItems(slot.id), hasLength(1));
      expect((await db.getAllTables()).map((t) => t.id), List.generate(10, (i) => i + 1));
    });
  });
}
