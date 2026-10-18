import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/admin/admin_home_page.dart';
import 'package:ramyar_pos/page/owner/owner_home_page.dart';
import 'package:ramyar_pos/page/waiter/waiter_home_page.dart';
import 'package:ramyar_pos/page/cashier/cashier_welcome_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

import 'owner_test_login.dart';

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
    // The owner (خاوەن سیستەم) creates every staff account with an automatic
    // unique IP. Replace the seeded placeholders with provisioned accounts so
    // staff logins only unlock once THIS device is bound to the account IP.
    final seeded = await db.getAllUsers();
    for (final u in seeded) {
      await db.deleteUser(u.id);
    }
    await db.addUser('Admin', '33441', UserRole.admin, accessCode: '192.168.10.7');
    await db.addUser('کاپتن', '11221', UserRole.waiter, accessCode: '192.168.10.8');
    await db.addUser('کاشێر', '22334', UserRole.cashier, accessCode: '192.168.10.9');
    // Every user write above fires a fire-and-forget addPendingSync insert (and
    // an unawaited pending-count query after it). Those futures all share the
    // sqflite connection lock and were created in the real-async setUp zone,
    // so they must be drained HERE - before the FakeAsync test body runs -
    // otherwise the first DB call inside the body queues behind them and hangs.
    // Each awaited query sits behind everything already queued, so two barriers
    // flush both the insert chain and the follow-up count queries.
    await db.getPendingCount();
    await db.getPendingCount();
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDbProvider.overrideWithValue(db),
        ],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
  }

  Future<void> expectPage(WidgetTester tester, Type pageType, String pin) async {
    // The login gate resolves the account IP check against prefs/DB asynchronously
    // before navigating, so wait (with pumps) for the target page instead of
    // failing on the very first frame.
    var found = false;
    for (var i = 0; i < 30 && !found; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(pageType).evaluate().isNotEmpty) found = true;
    }
    if (!found) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .toList();
      fail('After PIN $pin, $pageType never appeared. Visible texts:\n$texts');
    }
  }

  Future<void> backToLogin(WidgetTester tester) async {
    final ctx = tester.element(find.byType(Navigator).first);
    Navigator.of(ctx).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    var found = false;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isNotEmpty) {
        found = true;
        break;
      }
    }
    if (!found) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .toList();
      fail('LoginPage never appeared. Visible texts: $texts');
    }
  }

  testWidgets('staff accounts open their home pages after the account IP is entered and PIN login',
      (tester) async {
    await pumpApp(tester);
    expect(find.byType(LoginPage), findsOneWidget);

    // Until the account IP is entered on this device, ONLY the owner exists:
    // staff PINs are refused even for real accounts.
    await enterPin(tester, '33441');
    expect(find.byType(LoginPage), findsOneWidget);

    // The owner enters the admin's IP on this device, then the admin logs in.
    await saveDeviceAccessCode('192.168.10.7');
    await enterPin(tester, '33441');
    await expectPage(tester, AdminHomePage, '33441');
    await backToLogin(tester);

    // Rebinding changes whose account is allowed on this device.
    await saveDeviceAccessCode('192.168.10.8');
    await enterPin(tester, '11221');
    await expectPage(tester, WaiterHomePage, '11221');
    await backToLogin(tester);

    await saveDeviceAccessCode('192.168.10.9');
    await enterPin(tester, '22334');
    await expectPage(tester, CashierWelcomePage, '22334');
    await backToLogin(tester);

    disconnectSync();
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('brand new system: invalid PINs fail, only the owner PIN opens the owner page',
      (tester) async {
    // Simulate a freshly wiped system: no accounts have been created yet.
    final all = await db.getAllUsers();
    for (final u in all) {
      await db.deleteUser(u.id);
    }
    await pumpApp(tester);
    expect(find.byType(LoginPage), findsOneWidget);

    await enterPin(tester, '54321');
    expect(find.byType(LoginPage), findsOneWidget);

    await enterPin(tester, '33411');
    expect(find.byType(LoginPage), findsOneWidget);

    // The owner PIN is not in the repository in any form, so the suite installs
    // a throwaway one - see owner_test_login.dart.
    await enterPin(tester, testOwnerPin);
    await expectPage(tester, OwnerHomePage, testOwnerPin);
    await backToLogin(tester);

    disconnectSync();
    await tester.pump(const Duration(seconds: 11));
  });
}