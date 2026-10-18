import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_cancelled_items_page.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

/// Deleting a table must never eat an order.
///
/// The rule, in both directions: a cashier cannot delete a table that still
/// has food on it (the main section and the delivery slot cleanup both say no),
/// and the database backs that up - if a delete ever does go through a table
/// with food on it, every dish lands in «ڕەتکراوەکان» with its full row
/// (name, price, quantity, category, table, the waiter who rang it, who removed
/// the table) instead of vanishing with the table.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);

  void seed(UserModel? user) => state = user;
}

const _cashierId = 5;
const _cashierName = 'Cashier 1';

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
    disconnectSync(db);
    await db.resetForTesting();
  });

  OrderItem dish(
    String id,
    String name,
    double price, {
    int qty = 2,
    String category = 'گەرمی',
    String waiter = 'سەرکاردە 1',
    String? created,
  }) => OrderItem(
    id: id,
    name: name,
    price: price,
    quantity: qty,
    category: category,
    createdAt: created ?? DateTime.now().toIso8601String(),
    waiterName: waiter,
  );

  group('the database backs the guard up', () {
    test(
      'deleteTable moves every dish still on the table into «ڕەتکراوەکان» with its full row',
      () async {
        // A captain rang the first dish in, a cashier rang the second - the
        // record has to keep both roles apart, so both staff exist as users.
        expect(
          await db.addUser('کاپتن ئاراس', '9091', UserRole.waiter),
          isTrue,
        );
        expect(
          await db.addUser('کاشێر شیلان', '9092', UserRole.cashier),
          isTrue,
        );
        final at1 = '2026-09-01T10:15:30.000';
        final at2 = '2026-09-01T10:20:00.000';
        await db.batchSendAndOccupy(5, [
          dish(
            'a',
            'کەباب',
            10000,
            qty: 2,
            category: 'گەرمی',
            waiter: 'کاپتن ئاراس',
            created: at1,
          ),
          dish(
            'b',
            'پیتزا',
            5000,
            qty: 1,
            category: 'ساردی',
            waiter: 'کاشێر شیلان',
            created: at2,
          ),
        ], waiterId: '101');

        await db.deleteTable(5, cancelledBy: 7, cancelledByName: 'کاشێر 1');

        // One complete cancelled record per dish, not a lump sum.
        final cancelled = await db.getPendingCancelledItems();
        expect(cancelled, hasLength(2));

        final kabab = cancelled.singleWhere((c) => c.itemName == 'کەباب');
        expect(kabab.tableId, 5);
        expect(kabab.tableName, 'مێز 5');
        expect(kabab.itemPrice, 10000);
        expect(kabab.quantity, 2);
        expect(kabab.category, 'گەرمی');
        expect(kabab.cancelledBy, 7);
        expect(kabab.cancelledByName, 'کاشێر 1');
        // Full order-handle: WHO rung it (name + the captain role), WHEN it was
        // rung, and when it was thrown out.
        expect(kabab.requestedByName, 'کاپتن ئاراس');
        expect(kabab.requestedByRole, UserRole.waiter.index);
        expect(kabab.requestedAt, at1);
        expect(kabab.cancelledAt, isNotEmpty);
        expect(
          kabab.status,
          'pending',
          reason: 'it has to sit in the queue for the cashier to confirm',
        );

        final pizza = cancelled.singleWhere((c) => c.itemName == 'پیتزا');
        expect(pizza.tableName, 'مێز 5');
        expect(pizza.itemPrice, 5000);
        expect(pizza.quantity, 1);
        expect(pizza.category, 'ساردی');
        expect(pizza.requestedByName, 'کاشێر شیلان');
        expect(
          pizza.requestedByRole,
          UserRole.cashier.index,
          reason: 'a cashier who rings a dish is not filed under captain',
        );
        expect(pizza.requestedAt, at2);

        // The room keeps its standard place, fresh and empty.
        final restored = await db.getTable(5);
        expect(restored, isNotNull);
        expect(restored!.name, 'مێز 5');
        expect(restored.status, TableStatus.empty);
        expect(await db.getOrderItems(5), isEmpty);
      },
    );

    test(
      'cancelling one line of the bill keeps its order time and requester role',
      () async {
        expect(
          await db.addUser('کاشێر شیلان', '9092', UserRole.cashier),
          isTrue,
        );
        final at = '2026-09-01T10:15:30.000';
        await db.batchSendAndOccupy(5, [
          dish(
            'a',
            'چای',
            1000,
            qty: 1,
            category: 'خواردنەوە',
            waiter: 'کاشێر شیلان',
            created: at,
          ),
        ]);

        await db.removeOrderItem(
          5,
          'a',
          cancelledBy: 7,
          cancelledByName: 'کاشێر 1',
        );

        final pending = await db.getPendingCancelledItems();
        expect(pending, hasLength(1));
        expect(
          pending.first.requestedAt,
          at,
          reason: 'the order moment of the dish, not the moment it was thrown',
        );
        expect(pending.first.requestedByName, 'کاشێر شیلان');
        expect(pending.first.requestedByRole, UserRole.cashier.index);
        expect(pending.first.cancelledByName, 'کاشێر 1');
        expect(await db.getOrderItems(5), isEmpty);
      },
    );

    test(
      'deleting an empty table records nothing into «ڕەتکراوەکان»',
      () async {
        await db.deleteTable(6, cancelledBy: 7, cancelledByName: 'کاشێر 1');

        expect(await db.getPendingCancelledItems(), isEmpty);
        final restored = await db.getTable(6);
        expect(restored, isNotNull);
        expect(restored!.status, TableStatus.empty);
      },
    );

    test(
      'a remote delete purges without writing the same cancelled records twice',
      () async {
        await db.batchSendAndOccupy(7, [dish('a', 'کەباب', 10000)]);

        // The deleting device already sent its cancelled records ahead of
        // this delete, so applying it here must not re-cancel the stale
        // local copies - that would double the cancelled orders for one shift.
        await db.applyRemoteTableDelete(7);

        expect(await db.getPendingCancelledItems(), isEmpty);
        expect(await db.getOrderItems(7), isEmpty);
        final restored = await db.getTable(7);
        expect(restored, isNotNull);
        expect(restored!.status, TableStatus.empty);
      },
    );
  });

  group('the cashier is stopped at the door', () {
    Future<void> openCashierHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final auth = _SeededAuthNotifier(
        db,
        LogoutReasonNotifier(),
        LoginNoticeNotifier(),
      );
      auth.seed(
        const UserModel(
          id: _cashierId,
          name: _cashierName,
          pin: '2233',
          role: UserRole.cashier,
        ),
      );
      await db.startShift(
        CashierShift(
          cashierId: _cashierId,
          cashierName: _cashierName,
          startedAt: DateTime.now().toIso8601String(),
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              localDbProvider.overrideWithValue(db),
              authProvider.overrideWith((ref) => auth),
            ],
            child: const MaterialApp(home: CashierHomePage()),
          ),
        ),
      );
      await _pumpUntil(tester, find.byType(BottomNavigationBar));
      await _pumpUntil(tester, find.byType(TableCard));

      await tester.pump(const Duration(seconds: 4));
      disconnectSync(db);
      await tester.pump();
    }

    testWidgets('a table with food on it cannot be deleted and nothing is lost', (
      tester,
    ) async {
      await openCashierHome(tester);

      // A captain rings two dishes into table 1 while the cashier watches.
      await db.batchSendAndOccupy(1, [
        dish('a', 'کەباب', 10000, qty: 2),
        dish('b', 'چای', 1000, qty: 1, category: 'خواردنەوە'),
      ], waiterId: '2');
      await tester.pump(const Duration(milliseconds: 400));

      // The cashier long-presses the table and asks to delete it.
      final card = tester.widget<TableCard>(
        find.byWidgetPredicate((w) => w is TableCard && w.table.id == 1),
      );
      card.onLongPress!();
      await tester.pump();
      await tester.tap(find.text('سڕینەوەی مێز'));
      await tester.pump();

      // Not a "are you sure" - a refusal. The food is still on the table.
      await _pumpUntil(
        tester,
        find.text(
          'ناتوانیت مێز بسڕیتەوە چونکە خواردن لەناو مێزەکەدایە. سەرەتا حیسابەکە واسڵ بکە یان خواردنەکە بۆ مێزێکی تر بگوازەوە.',
        ),
      );
      await tester.tap(find.text('باشە'));
      await tester.pump();
      await tester.pump();

      // The table is untouched: still there, still occupied, food intact, and
      // nothing was pushed into «ڕەتکراوەکان» behind the cashier's back.
      final table = await db.getTable(1);
      expect(table, isNotNull);
      expect(table!.status, TableStatus.occupied);
      final items = await db.getOrderItems(1);
      expect(items, hasLength(2));
      expect(items.map((i) => i.name), containsAll(['کەباب', 'چای']));
      expect(await db.getPendingCancelledItems(), isEmpty);
    });
  });

  group('the card tells the whole story of a rejection', () {
    testWidgets(
      'order time, cancel time and the requester come with name and role',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // The captain who rang the dish exists as a user, so the record can
        // pin the role as well as the name.
        expect(await db.addUser('ئاراس', '9091', UserRole.waiter), isTrue);
        await db.recordCancelledItem(
          tableId: 1,
          tableName: 'مێز 1',
          itemName: 'کەباب',
          price: 10000,
          quantity: 2,
          category: 'گەرمی',
          cancelledBy: 7,
          cancelledByName: 'کاشێر 1',
          requestedByName: 'ئاراس',
          requestedAt: '2026-09-01T10:15:30.000',
        );

        await tester.pumpWidget(
          _wrap(
            ProviderScope(
              overrides: [localDbProvider.overrideWithValue(db)],
              child: const MaterialApp(home: CashierCancelledItemsPage()),
            ),
          ),
        );
        await _pumpUntil(tester, find.text('کەباب'));

        // Every bit the record is asked to carry: name, price, when it was
        // ordered, when it was thrown out, who rang it (role + name) and who
        // threw it out.
        expect(find.text('کەباب'), findsOneWidget);
        expect(find.text('2 × د.ع 10,000'), findsOneWidget);
        expect(find.textContaining('کاتی داواکردن:'), findsOneWidget);
        expect(find.textContaining('کاتی ڕەتکردنەوە:'), findsOneWidget);
        expect(
          find.text('داواکەر: کاپتن ئاراس'),
          findsOneWidget,
          reason: 'the requester is shown with their role, not a bare name',
        );
        expect(find.text('ڕەتکەر: کاشێر 1'), findsOneWidget);
        expect(find.text('مێزی مێز 1'), findsOneWidget);
      },
    );
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Wraps a page the way the app actually builds one: RTL, a tablet-sized
/// viewport, and [AppState] because every visible string goes through
/// `context.tr`, which reads the language from there.
Widget _wrap(Widget child) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(1200, 900)),
      child: AppState(
        currentLanguage: AppLanguage.kurdish,
        onLanguageChanged: (_) {},
        child: child,
      ),
    ),
  );
}
