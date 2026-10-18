import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/order_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/admin/admin_home_page.dart';
import 'package:ramyar_pos/page/admin/admin_shift_detail_page.dart';
import 'package:ramyar_pos/page/admin/admin_shifts_page.dart';
import 'package:ramyar_pos/page/admin/shift_payment_method_page.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// The admin's own walk through a shift report, driven on the REAL device with
/// the REAL widgets and the REAL screen geometry - the same code path a human
/// touches: log in with the admin PIN, tap «شەفتی کاشێر», open the shift,
/// then press every collection-method button and step through all the report
/// tabs, including «ڕەتکراوەکان» and «زیرەکی کاپتن» that now live in the bar.
///
/// The database is an isolated in-memory one, so a real user's data is never
/// touched while the shipping pages, the shipping SQLite queries and the
/// shipping navigation are exercised end to end.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
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
    await db.resetForTesting();
  });

  // The laptop that is also the cashier/hub, and the phone the floor runs on.
  const laptop = Size(1280, 800);
  const phone = Size(413, 896);

  testWidgets('admin walks the shift report on the laptop (1280x800)',
      (tester) async {
    await walkShiftReport(tester, db, laptop);
  });

  testWidgets('admin walks the shift report on the phone (413x896)',
      (tester) async {
    await walkShiftReport(tester, db, phone);
  });
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
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
  final detail = err is FlutterError
      ? '\n${err.diagnostics.map((d) => d.toStringDeep()).join('\n')}'
      : '';
  expect(err, isNull, reason: '$what threw: $err$detail');
}

Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 25; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pump(const Duration(milliseconds: 120));
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 120));
  }
  fail('could not bring $finder on screen to tap it');
}

Future<void> goBack(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pump(const Duration(milliseconds: 500));
}

/// One closed shift that carries every collection method, a debt, and a
/// rejected dish with the full story, so every button and tab has something to
/// show.
Future<void> seedReportData(
  LocalDatabase db,
  UserModel cashier,
  UserModel captain,
) async {
  const methods = [
    'cash',
    'fib',
    'fastpay',
    'superqi',
    'zincash',
    'nass',
    'switch',
  ];
  final base = DateTime.now();
  final shiftId = await db.startShift(
    CashierShift(
      cashierId: cashier.id,
      cashierName: cashier.name,
      startedAt: base.subtract(const Duration(hours: 4)).toIso8601String(),
    ),
  );

  var tableId = 1;
  for (final method in methods) {
    final orderId = await db.addSettledOrder(
      SettledOrder(
        // `SettledOrder.toMap()` always writes the `id` column, so seeded rows
        // need distinct ids or the second insert trips the primary key.
        id: tableId,
        tableId: tableId,
        tableName: 'مێز $tableId',
        totalAmount: 10000,
        settledAt: base.subtract(Duration(minutes: tableId)).toIso8601String(),
        settledBy: cashier.id,
        shiftId: shiftId,
        paymentMethod: method,
        waiterId: captain.id.toString(),
      ),
    );
    await db.addSettledOrderItems(orderId, [
      OrderItem(
        id: 'it-$tableId',
        name: 'شیرینی بەرگەری',
        price: 5000,
        quantity: 2,
        category: 'خواردن',
        // The captain rang this dish in, so «زیرەکی کاپتن» credits it to them.
        waiterName: captain.name,
        waiterRole: UserRole.waiter.index,
      ),
    ]);
    tableId++;
  }

  // A debt so «قەرزەکان» is not empty either.
  final debtOrderId = await db.addSettledOrder(
    SettledOrder(
      id: 8,
      tableId: 8,
      tableName: 'مێز 8',
      totalAmount: 7000,
      settledAt: base.toIso8601String(),
      settledBy: cashier.id,
      shiftId: shiftId,
      paymentMethod: 'debt',
      waiterId: captain.id.toString(),
    ),
  );
  await db.addSettledOrderItems(debtOrderId, [
    OrderItem(
      id: 'it-8',
      name: 'چای',
      price: 1000,
      quantity: 7,
      category: 'خواردنەوە',
      waiterName: captain.name,
      waiterRole: UserRole.waiter.index,
    ),
  ]);

  // The rejected dish, with the four facts the admin asked for: which table,
  // who ordered it, which captain got it wrong, and who rejected it.
  await db.recordCancelledItem(
    tableId: 9,
    tableName: 'مێز 9',
    itemName: 'شیرینی تایبەت',
    price: 4000,
    quantity: 1,
    category: 'خواردن',
    cancelledBy: cashier.id,
    cancelledByName: cashier.name,
    requestedByName: captain.name,
    requestedAt: base.subtract(const Duration(minutes: 40)).toIso8601String(),
  );
}

/// The report's own vertical list. The tab bar is a second, horizontal
/// `Scrollable` deeper in the tree, so the first one is the page scroller.
Finder detailScrollable() => find
    .descendant(
      of: find.byType(AdminShiftDetailPage),
      matching: find.byType(Scrollable),
    )
    .first;

/// Drags the report down until [target] has actually been built. A `ListView`
/// only builds what is near the viewport, so a button below the fold is
/// invisible to `find.text` until the page is scrolled to it - exactly what a
/// human does with a thumb on a phone.
Future<void> scrollToDetail(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 40; i++) {
    if (target.evaluate().isNotEmpty) return;
    await tester.drag(detailScrollable(), const Offset(0, -260),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> walkShiftReport(
  WidgetTester tester,
  LocalDatabase db,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  debugPrint('LIVE shift-report @ $size : app start');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localDbProvider.overrideWithValue(db)],
      child: const RamyarPosApp(),
    ),
  );
  await pumpUntil(tester, find.byType(LoginPage));

  // Seed after the app is at the PIN pad: the isolated DB is empty during
  // auto-login, so the operator stays at the keypad instead of being signed in
  // as a user id that happens to match the real device's stored session.
  await db.seedDefaultStaff();
  final cashier = (await db.getUsersByRole(UserRole.cashier)).first;
  final captain = (await db.getUsersByRole(UserRole.waiter)).first;
  await seedReportData(db, cashier, captain);

  // ---- ADMIN ----
  await enterPin(tester, '33441');
  await pumpUntil(tester, find.byType(AdminHomePage));
  checkNoError(tester, 'admin home');

  await tapWhenReady(tester, find.text('شەفتی کاشێر'));
  await pumpUntil(tester, find.byType(AdminShiftsPage));
  checkNoError(tester, 'shifts list');

  await pumpUntil(tester, find.text(cashier.name));
  await tapWhenReady(tester, find.text(cashier.name));
  await pumpUntil(tester, find.byType(AdminShiftDetailPage));
  checkNoError(tester, 'shift detail');
  debugPrint('LIVE shift-report @ $size : detail open');

  // The header and the money summary sit at the top and must be there.
  expect(find.text('ڕاپۆرتی شەفت'), findsOneWidget);
  expect(find.text('پوختەی دارایی'), findsOneWidget);

  // The collection-method rows live under the summary; the report is a lazy
  // ListView, so scroll to them the way a human does instead of assuming they
  // were built at the top.
  await scrollToDetail(tester, find.text('ڕێگاکانی وەرگرتنی پارە'));
  checkNoError(tester, 'collection methods');

  // ---- EVERY COLLECTION METHOD IS A BUTTON ----
  // One method (FIB) is opened and its food read while it is already fresh and
  // on screen, the way a human opens FIB and taps the table to see the dishes.
  for (final method in const [
    'FIB',
    'FastPay',
    'Super QI',
    'ZinCash',
    'NassPay',
    'Switch',
  ]) {
    await scrollToDetail(tester, find.text(method));
    await tapWhenReady(tester, find.text(method));
    await pumpUntil(tester, find.byType(ShiftPaymentMethodPage));
    checkNoError(tester, 'payment page $method');
    // A one-order method must list that order, not the empty state.
    expect(find.textContaining('کۆی گشتی'), findsOneWidget);
    if (method == 'FIB') {
      expect(find.text('مێز 2'), findsOneWidget);
      await tapWhenReady(tester, find.text('مێز 2'));
      await pumpUntil(tester, find.text('شیرینی بەرگەری'));
      checkNoError(tester, 'payment page expanded food');
    }
    await goBack(tester);
    await pumpUntil(tester, find.byType(AdminShiftDetailPage));
  }
  debugPrint('LIVE shift-report @ $size : all payment methods open');

  // ---- ڕەتکراوەکان : the full rejected story, now a tab of the report ----
  await tapWhenReady(tester, find.text('ڕەتکراوەکان'));
  await pumpUntil(tester, find.text('شیرینی تایبەت'));
  checkNoError(tester, 'rejected tab');
  expect(find.byType(AdminShiftDetailPage), findsOneWidget);
  expect(find.textContaining('ڕەتکەر:'), findsOneWidget);
  expect(find.textContaining('داواکەر:'), findsOneWidget);
  expect(find.textContaining('مێز 9'), findsWidgets);
  debugPrint('LIVE shift-report @ $size : rejected tab open');

  // ---- زیرەکی کاپتن : the top seller, also a tab ----
  await tapWhenReady(tester, find.text('زیرەکی کاپتن'));
  await pumpUntil(tester, find.text(captain.name));
  checkNoError(tester, 'captain tab');
  expect(find.byType(AdminShiftDetailPage), findsOneWidget);
  debugPrint('LIVE shift-report @ $size : captain tab open');

  // ---- EVERY REPORT TAB ----
  // The bar now carries the data tabs and the four shift reports the admin used
  // to open as separate pages; each one draws its content right here.
  // «مێزەکان» is gone: the bar now carries only the «وردەکاری زیاتر» reports.
  expect(find.text('مێزەکان'), findsNothing);
  expect(find.text('کڕینی ئەشیاکان'), findsNothing);
  for (final tab in const [
    'ئۆردەرەکان',
    'قەرزەکان',
    'داواکاری خواردن',
    'ڕەتکراوەکان',
    'خەرجیەکان',
    'گەڕانەوەی خەرجی',
    'زیرەکی کاپتن',
  ]) {
    await tapWhenReady(tester, find.text(tab));
    await tester.pump(const Duration(milliseconds: 300));
    checkNoError(tester, 'tab $tab');
    expect(find.byType(AdminShiftDetailPage), findsOneWidget);
  }
  expect(find.text('وردەکاری زیاتر'), findsOneWidget);

  debugPrint('LIVE shift-report @ $size : done, all reports and tabs clean');

  // Integration runs use REAL time (`isRunningUnderTest` is false on a device),
  // so the pages' periodic timers are live. Unmount the app and stop the hub
  // before tearDown closes the database, or a late tick would touch a closed
  // DB and be reported as a phantom failure.
  disconnectSync();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 800));
}
