import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/login/connect_ip_page.dart';
import 'package:ramyar_pos/page/login/dollar_rate_page.dart';
import 'package:ramyar_pos/page/login/hama_page.dart';
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
import 'package:ramyar_pos/page/cashier/cashier_cancelled_items_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_expenses_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_previous_orders_page.dart';
import 'package:ramyar_pos/page/cashier/transfer_page.dart';
import 'package:ramyar_pos/page/cashier/merge_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_table_hold_page.dart';
import 'package:ramyar_pos/page/cashier/delivery_page.dart';
import 'package:ramyar_pos/page/admin/admin_table_notes_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/table_card.dart';
import 'package:ramyar_pos/widgets/cash_calculator_dialog.dart';
import 'package:ramyar_pos/widgets/table_note_dialog.dart';
import 'package:ramyar_pos/widgets/print_preview_dialog.dart';
import 'package:ramyar_pos/widgets/close_shift_dialog.dart';
import 'package:ramyar_pos/models/printer_model.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/models/table_lock_model.dart';

import 'owner_test_login.dart';

const _sizes = <String, Size>{
  'tiny-phone': Size(320, 480),
  'small-phone': Size(360, 740),
  'phone': Size(414, 896),
  'small-phone-se': Size(320, 568),
  'narrow-fold': Size(280, 653),
  'tablet': Size(768, 1024),
  'tablet-landscape': Size(1024, 768),
  'phone-landscape': Size(667, 375),
  'tiny-landscape': Size(568, 320),
  // The real target handset: a Galaxy A52s locked to landscape. Its logical
  // width (2400 - 88px cutout) / 2.625 lands in the DESKTOP tier, but the height
  // is only 411 - so this is the one size that pairs a desktop layout with a
  // phone-short screen, the exact combination a human would hit in the field.
  'device-landscape': Size(833, 411),
  'laptop': Size(1280, 800),
  'desktop': Size(1440, 900),
  'wide-desktop': Size(1920, 1080),
};

Future<void> _pumpUntil(
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

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.ensureVisible(find.text(digit));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text(digit), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

void _checkNoError(WidgetTester tester, String what) {
  final err = tester.takeException();
  expect(err, isNull, reason: '$what thrown exception: $err');
}

/// Shows a single dialog/modal widget on top of the running app, checks that it
/// laid out without overflowing at the current size, dismisses it and checks the
/// teardown too. Used to cover the dialogs and sheets that a page visit alone
/// never opens (note editor, cash calculator, ...), which are exactly where a
/// fixed-width box breaks on a narrow phone.
Future<void> _visitDialog(WidgetTester tester, Widget dialog) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  final ctx = nav.context;
  final pending = showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (_) => dialog,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  _checkNoError(tester, 'dialog ${dialog.runtimeType}');
  Navigator.of(ctx).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  _checkNoError(tester, 'dismiss ${dialog.runtimeType}');
  await pending;
}

/// Drives the receipt/print preview dialog (the same private widget behind
/// both the kitchen ticket and the cashier receipt) against a running app: it
/// is far taller than a landscape phone and carries a couple of non-flexible
/// rows (item-count chip, printer line), so it is exactly where a short screen
/// would overflow.
Future<void> _visitPrintPreview(
  WidgetTester tester,
  Future<bool> Function(BuildContext) show,
) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  final ctx = nav.context;
  final pending = show(ctx);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  _checkNoError(tester, 'print preview');
  Navigator.of(ctx).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  _checkNoError(tester, 'dismiss print preview');
  await pending;
}

/// Like [_visitDialog], but types [text] into the dialog's first on-stage text
/// field first - the close-shift dialog only reveals its "net" row once an
/// amount is entered, and that row is exactly the one that can overflow.
Future<void> _visitTypedDialog(
  WidgetTester tester,
  Widget dialog,
  String text,
) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  final ctx = nav.context;
  final pending = showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (_) => dialog,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  _checkNoError(tester, 'typed dialog ${dialog.runtimeType}');
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump(const Duration(milliseconds: 200));
  _checkNoError(tester, 'filled dialog ${dialog.runtimeType}');
  Navigator.of(ctx).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  _checkNoError(tester, 'dismiss ${dialog.runtimeType}');
  await pending;
}

Future<void> _visit(WidgetTester tester, Widget page) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute(builder: (_) => page));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  // Checked while the page is still on screen, so an overflow names the page
  // that produced it instead of surfacing later as an unattributed error at
  // the end of the test.
  _checkNoError(tester, 'visit ${page.runtimeType}');
  nav.pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  _checkNoError(tester, 'return from ${page.runtimeType}');
}

Future<void> _seedTable1Occupied(LocalDatabase db) async {
  await db.occupyTable(1, '2', guestCount: 2);
  await db.addOrderItem(1, OrderItem(id: 'it1', name: 'قەیمە بە ماس و بەیانیی تەماتە', price: 8500.0, quantity: 2, waiterName: 'وەیتەر گەشتیار'));
  await db.addOrderItem(1, OrderItem(id: 'it2', name: 'شای فەڕمی هەڵاتوو بە قەلایە قورچکدار', price: 12500.0, quantity: 3, waiterName: 'وەیتەر گەشتیار'));
  await db.addOrderItem(1, OrderItem(id: 'it3', name: 'چای کلکگشتی کەلە لەسەر سەکەمەزاری گەرم', price: 500.0, quantity: 1, waiterName: ''));
}

/// Seeds one pending cancelled item so the cashier "ڕەتکراوەکان" page renders a
/// real item card (name, chips, total row + "گواستنەوە بۆ مێز" button) instead
/// of the empty state.
Future<void> _seedCancelledItem(LocalDatabase db) async {
  await db.recordCancelledItem(
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

Future<void> _finish(WidgetTester tester) async {
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
  _checkNoError(tester, 'finish');
}

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

  Future<void> prepare(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDbProvider.overrideWithValue(db),
        ],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    if (find.byType(LoginPage).evaluate().isEmpty) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .toList();
      fail('No LoginPage at $size. Visible texts:\n$texts');
    }
    expect(find.byType(LoginPage), findsOneWidget, reason: 'login at $size');
    _checkNoError(tester, 'login boot');
  }

  for (final entry in _sizes.entries) {
    final size = entry.value;
    final label = entry.key;

    testWidgets('login with keyboard open at $label', (tester) async {
      await prepare(tester, size);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'login keyboard open');
      await _finish(tester);
    });

    testWidgets('connect page at $label', (tester) async {
      await prepare(tester, size);
      await tester.tap(find.text('!'), warnIfMissed: false);
      await _pumpUntil(tester, find.byType(ConnectIpPage));
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'connect page');
      await _finish(tester);
    });

    testWidgets('admin at $label', (tester) async {
      await prepare(tester, size);
      await _enterPin(tester, '33441');
      await _pumpUntil(tester, find.byType(AdminHomePage));
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'admin home');
      await _finish(tester);
    });

    testWidgets('admin all pages at $label', (tester) async {
      // An occupied table with a real note so the notes page renders a card,
      // not just its empty state.
      await _seedTable1Occupied(db);
      await db.updateTableNote(1, 'ئەم مێزە بۆ کۆمپانیایە');
      await prepare(tester, size);
      await _enterPin(tester, '33441');
      await _pumpUntil(tester, find.byType(AdminHomePage));
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'admin home');
      await _visit(tester, const AdminAccountsPage());
      await _visit(tester, const AdminMenuPage());
      await _visit(tester, const AdminUsersPage());
      await _visit(tester, const AdminUserManagementPage());
      await _visit(tester, const AdminOrdersPage());
      await _visit(tester, const AdminShiftsPage());
      await _visit(tester, AdminShiftDetailPage(
        shift: CashierShift(cashierId: 4, cashierName: 'کاشێر', startedAt: DateTime.now().toIso8601String(), totalCollected: 125000000),
      ));
      await _visit(tester, const ShiftPaymentMethodPage(method: 'fib', orders: []));
      await _visit(tester, const ShiftRejectedItemsPage(shiftId: 0));
      await _visit(tester, const ShiftExpensesPage(shiftId: 0));
      await _visit(
        tester,
        const ShiftExpensesPage(shiftId: 0, returnsOnly: true),
      );
      await _visit(tester, const ShiftCaptainReportPage(orders: []));
      await _visit(tester, const AdminPurchasesPage());
      await _visit(tester, const AdminDebtsPage());
      await _visit(tester, const AdminRefundsPage());
      await _visit(tester, const AdminPrinterScreen());
      await _visit(tester, const AdminFoodFilterPage());
      await _visit(tester, const AdminCaptainIntelligencePage());
      await _visit(tester, const AdminFoodDemandPage());
      await _visit(tester, const AdminBackupPage());
      await _visit(tester, const AdminTableNotesPage());
      await _visit(tester, const DollarRatePage());
      await _finish(tester);
    });

    testWidgets('cashier at $label', (tester) async {
      await prepare(tester, size);
      await _enterPin(tester, '22334');
      await _pumpUntil(tester, find.byType(CashierWelcomePage));
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'cashier welcome');
      await tester.ensureVisible(find.text('دەستپێکردنی شەفت'));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('دەستپێکردنی شەفت'), warnIfMissed: false);
      await _pumpUntil(tester, find.byType(CashierHomePage));
      await tester.pump(const Duration(milliseconds: 400));
      _checkNoError(tester, 'cashier home');
      await _finish(tester);
    });

    testWidgets('cashier all pages at $label', (tester) async {
      await _seedTable1Occupied(db);
      await _seedCancelledItem(db);
      await prepare(tester, size);
      await _enterPin(tester, '22334');
      await _pumpUntil(tester, find.byType(CashierWelcomePage));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('دەستپێکردنی شەفت'));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('دەستپێکردنی شەفت'), warnIfMissed: false);
      await _pumpUntil(tester, find.byType(CashierHomePage));
      await tester.pump(const Duration(milliseconds: 400));
      _checkNoError(tester, 'cashier home');
      await _visit(tester, const CashierUnifiedTablePage(tableNumber: 1, initialTab: 0));
      await _visit(tester, const CashierUnifiedTablePage(tableNumber: 1, initialTab: 1));
      await _visit(tester, const TransferPage(sourceTableId: 1));
      await _visit(tester, const MergePage(sourceTableId: 1));
      await _visit(tester, const CashierCancelledItemsPage());
      await _visit(tester, const CashierExpensesPage(shiftId: 0));
      await _visit(tester, const CashierPreviousOrdersPage(shiftId: 0));
      await _visit(
        tester,
        const CashierTableHistoryPage(
          tableId: 1,
          tableName: 'مێز 1',
          shiftId: 0,
        ),
      );
      await _visit(tester, const DeliveryPage());
      // A lock held by a captain: the cashier is shown the "table is taken"
      // stand with the name, the held time and the running bill.
      await _visit(tester, CashierTableHoldPage(
        table: const TableModel(
          id: 1,
          name: 'مێز 1',
          status: TableStatus.occupied,
          guestCount: 2,
          totalAmount: 37000,
        ),
        lock: TableLock(
          tableId: 1,
          deviceId: 'test-device',
          userId: 2,
          userName: 'وەیتەر 1',
          role: 'waiter',
        ),
      ));
      await _finish(tester);
    });

    testWidgets('waiter at $label', (tester) async {
      await _seedTable1Occupied(db);
      await prepare(tester, size);
      await _enterPin(tester, '11221');
      await _pumpUntil(tester, find.byType(WaiterHomePage));
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'waiter home');
      tester.widget<TableCard>(find.byType(TableCard).first).onTap();
      await tester.pump();
      await _pumpUntil(tester, find.byType(TablePage));
      await tester.pump(const Duration(milliseconds: 400));
      _checkNoError(tester, 'waiter table page');
      await _finish(tester);
    });

    testWidgets('waiter all pages at $label', (tester) async {
      await _seedTable1Occupied(db);
      await prepare(tester, size);
      await _enterPin(tester, '11221');
      await _pumpUntil(tester, find.byType(WaiterHomePage));
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'waiter home');
      await _visit(tester, const TablePage(tableNumber: 1, initialGuestCount: 2));
      await _visit(tester, const OrderPage(tableNumber: 1));
      await _visit(tester, const TransferPage(sourceTableId: 1));
      await _visit(tester, const OrderDeliveryPage());
      await _visit(tester, const WaiterSettingsPage());
      await _finish(tester);
    });

    testWidgets('hidden hama page at $label', (tester) async {
      await prepare(tester, size);
      // Autofocuses its text box - keep the keyboard closed by focusing first.
      await _visit(tester, const HamaPage());
      await _finish(tester);
    });

    testWidgets('dialogs and sheets at $label', (tester) async {
      await prepare(tester, size);
      // The note editor (captain + cashier variants) and the cash calculator,
      // the two dialogs with real content at every width.
      await _visitDialog(
        tester,
        const TableNoteDialog(title: 'تێبینی', showAdminField: true),
      );
      await _visitDialog(
        tester,
        const TableNoteDialog(title: 'تێبینی بۆ مێز', showAdminField: false),
      );
      await _visitDialog(
        tester,
        const CashCalculatorDialog(totalDue: 125000, tableName: 'مێز 1'),
      );
      await _visitDialog(
        tester,
        const CashCalculatorDialog(totalDue: 9800000, tableName: 'تەلەبات 100104'),
      );
      // The print/receipt preview: a tall scrollable dialog with fixed header
      // and footer rows plus non-flexible item-count and printer lines.
      await _visitPrintPreview(
        tester,
        (ctx) => PrintPreview.showKitchenPreview(
          ctx,
          const PrintJob(
            items: [
              PrintJobItem(
                name: 'قەیمە بە ماس و بەیانیی تەماتە',
                quantity: 2,
                category: 'خواردن',
                waiterName: 'وەیتەر گەشتیار',
                tableNumber: 1,
              ),
              PrintJobItem(
                name: 'شای فەڕمی هەڵاتوو بە قەلایە قورچکدار',
                quantity: 3,
                category: 'خواردن',
                waiterName: 'وەیتەر گەشتیار',
                tableNumber: 1,
              ),
            ],
            printerType: PrinterType.kitchen,
            printerName: 'چاپکەری چێشتخانەی سەرەکی یەکەم',
            printerPort: 'USB001',
          ),
        ),
      );
      await _visitPrintPreview(
        tester,
        (ctx) => PrintPreview.showReceiptPreview(
          ctx,
          tableNumber: 1,
          guestCount: 2,
          items: [
            OrderItem(
              id: 'it1',
              name: 'قەیمە بە ماس و بەیانیی تەماتە',
              price: 8500,
              quantity: 2,
              waiterName: 'وەیتەر گەشتیار',
            ),
          ],
          subtotal: 17000,
          discountPercent: 0,
          discountAmount: 0,
          total: 17000,
          waiterName: 'وەیتەر گەشتیار',
          cashierName: 'کاشێر 1',
          printerName: 'چاپکەری کاشێر',
          seatedAt: DateTime.now().toIso8601String(),
        ),
      );
      // The cashier's close-shift dialog: a label row next to a FittedBox
      // amount, plus a "net" row that only appears once an amount is typed.
      // The split figures are supplied so the "taken out" and "returned" rows
      // are both laid out here too - they must not overflow at this size.
      await _visitTypedDialog(
        tester,
        CloseShiftDialog(
          startedAt: DateTime.now().toIso8601String(),
          shiftExpenses: 0,
          expensesOut: 25000,
          expensesBack: 25000,
        ),
        '500000',
      );
      await _finish(tester);
    });

    testWidgets('owner at $label', (tester) async {
      await prepare(tester, size);
      await _enterPin(tester, testOwnerPin);
      await _pumpUntil(tester, find.byType(OwnerHomePage));
      await tester.pump(const Duration(milliseconds: 300));
      _checkNoError(tester, 'owner home');
      await _visit(tester, const IpSettingsPage());
      await _finish(tester);
    });
  }
}