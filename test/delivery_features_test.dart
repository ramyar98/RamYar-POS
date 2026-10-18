import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/delivery_company_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/page/admin/admin_user_management_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/cashier/delivery_page.dart';
import 'package:ramyar_pos/page/waiter/table_page.dart';
import 'package:ramyar_pos/page/waiter/waiter_home_page.dart';
import 'package:ramyar_pos/page/waiter/waiter_settings_page.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

/// Test-only auth state: [StateNotifier.state] is protected, so a tiny
/// subclass exposes a seed setter to fake a logged-in cashier session.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);

  void seed(UserModel? user) => state = user;
}

/// Widget-test harness: pumps [page] inside a ProviderScope with the real
/// (in-memory) database and an AppState so `context.tr(...)` resolves - the
/// same dependencies every role page needs. Pass [authUser] to fake a logged
/// in session (required by home pages that gate on the user's role).
Future<void> _pumpPage(WidgetTester tester, Widget page, LocalDatabase db,
    {Size size = const Size(800, 600), UserModel? authUser}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final notifier = _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());
  notifier.seed(authUser);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(db),
        authProvider.overrideWith((ref) => notifier),
      ],
      child: AppState(
        currentLanguage: AppLanguage.kurdish,
        onLanguageChanged: (_) {},
        child: MaterialApp(home: page),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  group('delivery companies database', () {
    test('default companies are seeded on a fresh install', () async {
      final companies = await db.getDeliveryCompanies();
      expect(
          companies.map((c) => c.name), containsAll(['تەلەبات', 'لیزۆ', 'وادێ']));
      expect(companies, hasLength(3));
    });

    test('add emits DELIVERY_COMPANY_CREATED and bumps the revision', () async {
      final mutations = <String>[];
      db.onMutation = (action, data) => mutations.add(action);
      expect(db.deliveryCompaniesRevision.value, 0);

      final id = await db.addDeliveryCompany('Toters');
      expect(id, greaterThan(0));
      expect(mutations, ['DELIVERY_COMPANY_CREATED']);
      expect(db.deliveryCompaniesRevision.value, 1);

      final companies = await db.getDeliveryCompanies();
      expect(companies.map((c) => c.name), contains('Toters'));
    });

    test('delete emits DELIVERY_COMPANY_DELETED and removes the row', () async {
      final id = await db.addDeliveryCompany('Toters');
      final mutations = <String>[];
      db.onMutation = (action, data) => mutations.add(action);

      await db.deleteDeliveryCompany(id);
      expect(mutations, ['DELIVERY_COMPANY_DELETED']);
      final companies = await db.getDeliveryCompanies();
      expect(companies.map((c) => c.name), isNot(contains('Toters')));
      expect(companies, hasLength(3));
    });

    test('remote upsert inserts when missing and updates when present',
        () async {
      final remote = DeliveryCompany(id: 101, name: 'Toters');
      await db.applyRemoteDeliveryCompany(remote);
      var companies = await db.getDeliveryCompanies();
      expect(companies.any((c) => c.id == 101 && c.name == 'Toters'), isTrue);

      await db.applyRemoteDeliveryCompany(
          DeliveryCompany(id: 101, name: 'Toters 2'));
      companies = await db.getDeliveryCompanies();
      expect(
          companies.any((c) => c.id == 101 && c.name == 'Toters 2'), isTrue);
      expect(companies.where((c) => c.id == 101), hasLength(1));
    });

    test('snapshot round-trips the delivery registry', () async {
      await db.addDeliveryCompany('Toters');
      final snapshot = await db.buildSnapshot();
      expect(snapshot['delivery_companies'], isA<List>());
      final companyNames =
          (snapshot['delivery_companies'] as List).map((e) => e['name']);
      expect(companyNames, containsAll(['تەلەبات', 'لیزۆ', 'وادێ', 'Toters']));

      final db2 = LocalDatabase();
      try {
        await db2.init(inMemory: true);
        await db2.applySnapshot(snapshot);
        final names =
            (await db2.getDeliveryCompanies()).map((c) => c.name).toList();
        expect(names, containsAll(['تەلەبات', 'لیزۆ', 'وادێ', 'Toters']));
      } finally {
        await db2.resetForTesting();
      }
    });

    test('applySnapshot upserts but never drops local-only companies', () async {
      // Local company not present on the server snapshot.
      await db.addDeliveryCompany('Toters');
      final serverDb = LocalDatabase();
      try {
        await serverDb.init(inMemory: true);
        await db.applySnapshot(await serverDb.buildSnapshot());
        final names =
            (await db.getDeliveryCompanies()).map((c) => c.name).toList();
        expect(names, contains('Toters'));
        expect(names, hasLength(4)); // 3 default + Toters preserved
      } finally {
        await serverDb.resetForTesting();
      }
    });
  });

  group('delivery page', () {
    testWidgets('renders the 3 default tabs each with 20 table slots',
        (tester) async {
      await _pumpPage(tester, const DeliveryPage(), db,
          size: const Size(414, 896));
      for (final name in ['تەلەبات', 'لیزۆ', 'وادێ']) {
        expect(find.text(name), findsWidgets,
            reason: 'company chip $name should be visible');
      }
      expect(find.byIcon(Icons.delivery_dining_rounded), findsWidgets);
      expect(find.text('تەلەبات 1'), findsOneWidget);
      // Slot 20 is off-screen until scrolled (the grid builds lazily).
      final gridScrollable = find
          .descendant(of: find.byType(DeliveryPage), matching: find.byType(Scrollable))
          .last;
      await tester.scrollUntilVisible(find.text('تەلەبات 20'), 200,
          scrollable: gridScrollable);
      expect(find.text('تەلەبات 20'), findsOneWidget);
    });

    testWidgets('icon-only "+" adds a custom company that persists',
        (tester) async {
      await _pumpPage(tester, const DeliveryPage(), db,
          size: const Size(414, 896));
      await tester.tap(find.byIcon(Icons.add_rounded), warnIfMissed: false);
      await _pumpUntil(tester, find.text('زیادکردنی کۆمپانیا'));
      await tester.enterText(find.byType(TextField), 'Toters');
      await tester.tap(find.text('زیادکردن'));
      // The slots are read separately from the companies, so waiting for the
      // chip on its own would check the bar before the grid has loaded.
      await _pumpUntil(tester, find.text('Toters 1'));

      expect((await db.getDeliveryCompanies()).map((c) => c.name),
          contains('Toters'));
      // The new company becomes the selected one, so its slots render.
      expect(find.text('Toters 1'), findsOneWidget);
    });

    testWidgets('a company can be deleted from the trash button',
        (tester) async {
      await _pumpPage(tester, const DeliveryPage(), db,
          size: const Size(414, 896));
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first,
          warnIfMissed: false);
      await _pumpUntil(tester, find.text('سڕینەوەی کۆمپانیا'));
      await tester.tap(find.text('سڕینەوە').last);
      await tester.pump(const Duration(milliseconds: 400));

      final names =
          (await db.getDeliveryCompanies()).map((c) => c.name).toList();
      expect(names, isNot(contains('تەلەبات')));
      expect(names, hasLength(2));
    });

    testWidgets('empty state shows when every company was deleted',
        (tester) async {
      for (final c in await db.getDeliveryCompanies()) {
        await db.deleteDeliveryCompany(c.id);
      }
      await _pumpPage(tester, const DeliveryPage(), db,
          size: const Size(414, 896));
      expect(find.text('هیچ کۆمپانیایەک نییە — زیاد بکە'), findsOneWidget);
    });

    testWidgets('stays overflow-free on a tiny phone and a desktop',
        (tester) async {
      await _pumpPage(tester, const DeliveryPage(), db,
          size: const Size(320, 480));
      expect(tester.takeException(), isNull);
      expect(find.text('تەلەبات 1'), findsOneWidget);

      await _pumpPage(tester, const DeliveryPage(), db,
          size: const Size(1280, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('تەلەبات 1'), findsOneWidget);
    });
  });

  group('cashier delivery entry point', () {
    testWidgets('the delivery segment sits beside the 3 filters and opens the page',
        (tester) async {
      // CashierHomePage screens the user by role and only stays on the tables
      // view while a shift is active, so seed a cashier session + shift.
      final cashier = (await db.getUsersByRole(UserRole.cashier)).first;
      await db.startShift(CashierShift(
        cashierId: cashier.id,
        cashierName: cashier.name,
        startedAt: DateTime.now().toIso8601String(),
      ));
      await _pumpPage(tester, const CashierHomePage(), db,
          size: const Size(600, 800), authUser: cashier);
      for (final label in [
        'هەموو مێزەکان',
        'مێزە گیراوەکان',
        'مێزە بەتاڵەکان',
        'دلیڤەری'
      ]) {
        expect(find.text(label), findsOneWidget,
            reason: 'filter segment $label should be visible');
      }
      // Tap the delivery segment itself (its text may be FittedBox-scaled).
      await tester.tap(
        find
            .ancestor(
                of: find.text('دلیڤەری'),
                matching: find.byType(GestureDetector))
            .first,
      );
      await _pumpUntil(tester, find.byType(DeliveryPage));
      expect(find.byType(DeliveryPage), findsOneWidget);

      // CashierHomePage auto-starts the POS socket server (real bind already
      // happened): let its 3s local-IP timeout timer fire, then dispose the
      // server so no timers stay pending when the widget tree is torn down.
      await tester.pump(const Duration(seconds: 4));
      disconnectSync(db);
      await tester.pump();
    });
  });

  group('guest-count "+" (captain)', () {
    testWidgets('typing a custom number opens the table with that guest count',
        (tester) async {
      await _pumpPage(tester, const WaiterHomePage(), db,
          size: const Size(900, 700));

      // Table 1 is empty by default: tapping its card opens the guest dialog.
      tester.widget<TableCard>(find.byType(TableCard).first).onTap();
      await tester.pump();
      await _pumpUntil(tester, find.text('چەند کەسن؟'));

      // The icon-only "+" tile opens the custom input dialog.
      await tester.tap(find.byIcon(Icons.add_rounded), warnIfMissed: false);
      await _pumpUntil(tester, find.text('ژمارەی موشتەرییەکان'));

      await tester.enterText(find.byType(TextField), '22');
      await tester.tap(find.text('زیادکردن'));
      await _pumpUntil(tester, find.byType(TablePage));

      final tablePage = tester.widget<TablePage>(find.byType(TablePage));
      expect(tablePage.initialGuestCount, 22);
    });

    testWidgets('an invalid custom number shows a validation snackbar',
        (tester) async {
      await _pumpPage(tester, const WaiterHomePage(), db,
          size: const Size(900, 700));

      tester.widget<TableCard>(find.byType(TableCard).first).onTap();
      await tester.pump();
      await _pumpUntil(tester, find.text('چەند کەسن؟'));
      await tester.tap(find.byIcon(Icons.add_rounded), warnIfMissed: false);
      await _pumpUntil(tester, find.text('ژمارەی موشتەرییەکان'));

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.tap(find.text('زیادکردن'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('ژمارەیەکی دروست بنووسە'), findsOneWidget);
      expect(find.byType(TablePage), findsNothing);
    });
  });

  group('admin add-user page', () {
    testWidgets('renames the captain tab and uses a language spinner',
        (tester) async {
      await _pumpPage(tester, const AdminUserManagementPage(), db);
      expect(find.text('کاپتن'), findsOneWidget);
      // A dropdown (spinner) replaces the item-by-item language list.
      expect(find.byType(DropdownButton<AppLanguage>), findsOneWidget);
    });
  });

  group('waiter settings page', () {
    testWidgets('renames the IP field to کۆدی تایبەت and drops the helper text',
        (tester) async {
      await _pumpPage(tester, const WaiterSettingsPage(), db,
          size: const Size(414, 896));
      expect(find.text('کۆدی تایبەت'), findsWidgets);
      expect(find.text('نیشانەی IP'), findsNothing);
      expect(find.textContaining('سەرڤەر دەتپەسەندێت'), findsNothing);
      expect(find.text('پاشەکەوتکردن'), findsOneWidget);
    });
  });
}