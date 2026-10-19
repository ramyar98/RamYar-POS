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
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/login/pin_login_page.dart';
import 'package:ramyar_pos/page/admin/admin_home_page.dart';
import 'package:ramyar_pos/page/admin/admin_accounts_page.dart';
import 'package:ramyar_pos/page/admin/admin_backup_page.dart';
import 'package:ramyar_pos/page/admin/admin_captain_intelligence_page.dart';
import 'package:ramyar_pos/page/admin/admin_debts_page.dart';
import 'package:ramyar_pos/page/admin/admin_food_demand_page.dart';
import 'package:ramyar_pos/page/admin/admin_food_filter_page.dart';
import 'package:ramyar_pos/page/admin/admin_menu_page.dart';
import 'package:ramyar_pos/page/admin/admin_orders_page.dart';
import 'package:ramyar_pos/page/admin/admin_printer_screen.dart';
import 'package:ramyar_pos/page/admin/admin_purchases_page.dart';
import 'package:ramyar_pos/page/admin/admin_refunds_page.dart';
import 'package:ramyar_pos/page/admin/admin_shift_detail_page.dart';
import 'package:ramyar_pos/page/admin/admin_shifts_page.dart';
import 'package:ramyar_pos/page/admin/shift_captain_report_page.dart';
import 'package:ramyar_pos/page/admin/shift_expenses_page.dart';
import 'package:ramyar_pos/page/admin/shift_payment_method_page.dart';
import 'package:ramyar_pos/page/admin/shift_rejected_items_page.dart';
import 'package:ramyar_pos/page/admin/admin_users_page.dart';
import 'package:ramyar_pos/page/admin/admin_user_management_page.dart';
import 'package:ramyar_pos/page/owner/owner_home_page.dart';
import 'package:ramyar_pos/page/owner/ip_settings_page.dart';
import 'package:ramyar_pos/page/waiter/waiter_home_page.dart';
import 'package:ramyar_pos/page/waiter/waiter_settings_page.dart';
import 'package:ramyar_pos/page/waiter/order_delivery_page.dart';
import 'package:ramyar_pos/page/waiter/table_page.dart';
import 'package:ramyar_pos/page/waiter/order_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_welcome_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_unified_table_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_table_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_cancelled_items_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_expenses_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_previous_orders_page.dart';
import 'package:ramyar_pos/page/cashier/delivery_page.dart';
import 'package:ramyar_pos/page/cashier/transfer_page.dart';
import 'package:ramyar_pos/page/cashier/merge_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/services/app_localizations.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

import 'owner_test_login.dart';

/// "Review all the pages one by one in all 6 languages" gate.
///
/// For every language (kurdish, badini, arabic, persian, english, turkish) the
/// full role sweep is executed at phone size: admin pages, cashier pages,
/// waiter pages and owner pages are all rendered in that language and must not
/// throw. A compact tiny-phone pass makes sure the landing screens stay
/// overflow-free in every language too.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    installTestOwnerPin();
  });

  tearDownAll(uninstallTestOwnerPin);

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

  const phone = Size(413, 896);

  Future<void> prepare(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'LoginPage not shown at $size');
  }

  Future<void> selectLanguage(WidgetTester tester, AppLanguage lang) async {
    await tester.tap(
      find.byType(DropdownButton<AppLanguage>),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(LanguageHelper.getLanguageName(lang)).last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'selectLanguage(${lang.name}) threw');
  }

  /// Returns the rendered string for [key] in [lang] (kurdish == the key).
  String trKey(String key, AppLanguage lang) =>
      lang == AppLanguage.kurdish ? key : (allTranslations[key]?[lang] ?? key);

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.ensureVisible(find.text(digit));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text(digit), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  void checkNoError(WidgetTester tester, String what) {
    final err = tester.takeException();
    expect(err, isNull, reason: '$what threw: $err');
  }

  Future<void> visitPage(WidgetTester tester, Widget page, String what) async {
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    checkNoError(tester, what);
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> finishSweep(WidgetTester tester, String what) async {
    final ctx = tester.element(find.byType(Navigator).first);
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
    disconnectSync();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(seconds: 11));
    checkNoError(tester, '$what finish');
  }

  /// Drops the current role's routes back to the (curried) login page so the
  /// next role can log in with its own PIN. The keypad must be present again.
  Future<void> backToLogin(WidgetTester tester, String what) async {
    final ctx = tester.element(find.byType(Navigator).first);
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty &&
          find.byType(PinKeypad).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 600));
    checkNoError(tester, '$what back-to-login');
  }

  Future<void> seedData(LocalDatabase database) async {
    await database.occupyTable(1, '2', guestCount: 2);
    await database.addOrderItem(
      1,
      OrderItem(
          id: 'it1',
          name: 'قەیمە بە ماس و بەیانیی تەماتە',
          price: 8500.0,
          quantity: 2,
          waiterName: 'وەیتەر گەشتیار'),
    );
    await database.recordCancelledItem(
      tableId: 1,
      tableName: 'مێز 1',
      itemName: 'قەیمە بە ماس و بەیانیی تەماتە',
      price: 8500.0,
      quantity: 2,
      category: 'خواردن',
      cancelledBy: 4,
      cancelledByName: 'کاشێر 1',
    );
  }

  Future<void> loginAs(WidgetTester tester, String pin, Type page,
      String what) async {
    await enterPin(tester, pin);
    await pumpUntil(tester, find.byType(page));
    await tester.pump(const Duration(milliseconds: 400));
    checkNoError(tester, '$what home');
  }

  Future<void> sweepAllPages(WidgetTester tester, AppLanguage lang) async {
    final what = 'sweep(${lang.name})';

    // ---- Admin ----
    await loginAs(tester, '33441', AdminHomePage, what);
    await visitPage(tester, const AdminAccountsPage(), '$what accounts');
    await visitPage(tester, const AdminMenuPage(), '$what menu');
    await visitPage(tester, const AdminUsersPage(), '$what users');
    await visitPage(tester, const AdminUserManagementPage(), '$what user-mgmt');
    await visitPage(tester, const AdminOrdersPage(), '$what orders');
    await visitPage(tester, const AdminShiftsPage(), '$what shifts');
    await visitPage(
      tester,
      AdminShiftDetailPage(
        shift: CashierShift(
          cashierId: 4,
          cashierName: 'کاشێر',
          startedAt: DateTime.now().toIso8601String(),
          totalCollected: 125000,
        ),
      ),
      '$what shift-detail',
    );
    await visitPage(
        tester,
        const ShiftPaymentMethodPage(method: 'fib', orders: []),
        '$what shift-pay-method');
    await visitPage(
        tester,
        const ShiftRejectedItemsPage(shiftId: 0),
        '$what shift-rejected');
    await visitPage(
        tester,
        const ShiftExpensesPage(shiftId: 0),
        '$what shift-expenses');
    await visitPage(
        tester,
        const ShiftExpensesPage(shiftId: 0, returnsOnly: true),
        '$what shift-expense-returns');
    await visitPage(
        tester,
        const ShiftCaptainReportPage(orders: []),
        '$what shift-captain');
    await visitPage(tester, const AdminPurchasesPage(), '$what purchases');
    await visitPage(tester, const AdminDebtsPage(), '$what debts');
    await visitPage(tester, const AdminRefundsPage(), '$what refunds');
    await visitPage(tester, const AdminPrinterScreen(), '$what printer');
    await visitPage(tester, const AdminFoodFilterPage(), '$what food-filter');
    await visitPage(tester, const AdminCaptainIntelligencePage(), '$what captain');
    await visitPage(tester, const AdminFoodDemandPage(), '$what food-demand');
    await visitPage(tester, const AdminBackupPage(), '$what backup');
    await backToLogin(tester, what);

    // ---- Cashier ----
    await loginAs(tester, '22334', CashierWelcomePage, what);
    final startLabel = trKey('دەستپێکردنی شەفت', lang);
    await tester.ensureVisible(find.text(startLabel));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text(startLabel), warnIfMissed: false);
    await pumpUntil(tester, find.byType(CashierHomePage));
    await tester.pump(const Duration(milliseconds: 400));
    checkNoError(tester, '$what cashier home');
    await visitPage(
        tester,
        const CashierUnifiedTablePage(tableNumber: 1, initialTab: 0),
        '$what unified-0');
    await visitPage(
        tester,
        const CashierUnifiedTablePage(tableNumber: 1, initialTab: 1),
        '$what unified-1');
    await visitPage(tester, const TransferPage(sourceTableId: 1), '$what transfer');
    await visitPage(tester, const MergePage(sourceTableId: 1), '$what merge');
    await visitPage(tester, const CashierTablePage(tableNumber: 1), '$what table');
    await visitPage(
        tester, const CashierCancelledItemsPage(), '$what cancelled');
    await visitPage(
        tester, const CashierExpensesPage(shiftId: 0), '$what expenses');
    await visitPage(tester, const CashierPreviousOrdersPage(shiftId: 0),
        '$what previous-orders');
    await visitPage(
        tester,
        const CashierTableHistoryPage(
            tableId: 1, tableName: 'مێز 1', shiftId: 0),
        '$what previous-orders-table');
    await visitPage(tester, const DeliveryPage(), '$what delivery-page');
    await backToLogin(tester, what);

    // ---- Waiter ----
    await loginAs(tester, '11221', WaiterHomePage, what);
    tester.widget<TableCard>(find.byType(TableCard).first).onTap();
    await tester.pump();
    await pumpUntil(tester, find.byType(TablePage));
    await tester.pump(const Duration(milliseconds: 400));
    checkNoError(tester, '$what waiter table');
    await visitPage(
        tester,
        const TablePage(tableNumber: 1, initialGuestCount: 2),
        '$what table-page');
    await visitPage(tester, const OrderPage(tableNumber: 1), '$what order');
    await visitPage(
        tester, const TransferPage(sourceTableId: 1), '$what waiter-transfer');
    await visitPage(tester, const OrderDeliveryPage(), '$what delivery');
    await visitPage(tester, const WaiterSettingsPage(), '$what waiter-settings');
    await backToLogin(tester, what);

    // ---- Owner ----
    await loginAs(tester, testOwnerPin, OwnerHomePage, what);
    await visitPage(tester, const IpSettingsPage(), '$what ip-settings');

    await finishSweep(tester, what);
  }

  group('all pages render in every language (phone 413x896)', () {
    for (final lang in AppLanguage.values) {
      testWidgets('${lang.name} full sweep', (tester) async {
        await seedData(db);
        await prepare(tester, phone);
        await selectLanguage(tester, lang);
        await sweepAllPages(tester, lang);
      });
    }
  });

  group('landing screens at tiny phone 320x480', () {
    const tiny = Size(320, 480);
    for (final lang in AppLanguage.values) {
      testWidgets('${lang.name} tiny landing screens', (tester) async {
        await prepare(tester, tiny);
        await selectLanguage(tester, lang);
        final what = 'tiny(${lang.name})';

        // Admin home fits with no overflow.
        await loginAs(tester, '33441', AdminHomePage, what);
        checkNoError(tester, '$what admin-home');
        await backToLogin(tester, what);

        // Cashier welcome + home (start shift).
        await loginAs(tester, '22334', CashierWelcomePage, what);
        final startLabel = trKey('دەستپێکردنی شەفت', lang);
        await tester.ensureVisible(find.text(startLabel));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(find.text(startLabel), warnIfMissed: false);
        await pumpUntil(tester, find.byType(CashierHomePage));
        await tester.pump(const Duration(milliseconds: 400));
        checkNoError(tester, '$what cashier-home');
        await backToLogin(tester, what);

        // Waiter home.
        await loginAs(tester, '11221', WaiterHomePage, what);
        checkNoError(tester, '$what waiter-home');

        await finishSweep(tester, what);
      });
    }
  });
}