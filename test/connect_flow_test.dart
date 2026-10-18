import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/login/connect_ip_page.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
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
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  group('login gate: staff accounts need the account IP on this device', () {
    test('staff login is refused until the account IP is bound; owner always logs in', () async {
      await db.addUser('سەرپەرشتیار', '11111', UserRole.admin,
          accessCode: '192.168.10.5');
      final container = ProviderContainer(
        overrides: [localDbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final auth = container.read(authProvider.notifier);

      // No IP entered on this device yet -> only the owner exists.
      expect(await auth.loginWithPin('11111'), isNull);
      expect(container.read(loginNoticeProvider).state, isNotNull);

      // A different (wrong) IP is still locked.
      await saveDeviceAccessCode('192.168.10.6');
      expect(await auth.loginWithPin('11111'), isNull);

      // The account's own IP unlocks this device for that member.
      await saveDeviceAccessCode('192.168.10.5');
      final user = await auth.loginWithPin('11111');
      expect(user, isNotNull);
      expect(user!.role, UserRole.admin);
      expect(container.read(loginNoticeProvider).state, isNull);
    });

    test('owner PIN works even before any IP is entered (owner is always allowed)', () async {
      final container = ProviderContainer(
        overrides: [localDbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final auth = container.read(authProvider.notifier);
      final user = await auth.loginWithPin(testOwnerPin);
      expect(user, isNotNull);
      expect(user!.role, UserRole.owner);
    });

    test('a device bound to several account IPs unlocks every matching account (multi-IP)', () async {
      await db.addUser('سەرپەرشتیار', '11111', UserRole.admin,
          accessCode: '192.168.10.5');
      await db.addUser('کاپتن', '22222', UserRole.waiter,
          accessCode: '192.168.10.6');
      final container = ProviderContainer(
        overrides: [localDbProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final auth = container.read(authProvider.notifier);

      // Adding one IP must NOT wipe others: bind both account IPs on this device.
      await saveDeviceAccessCode('192.168.10.5');
      await saveDeviceAccessCode('192.168.10.6');
      final codes = await getDeviceAccessCodes();
      expect(codes, containsAll(['192.168.10.5', '192.168.10.6']));

      // After both IPs are bound, both staff accounts can log in on this device.
      final admin = await auth.loginWithPin('11111');
      expect(admin, isNotNull);
      expect(admin!.role, UserRole.admin);
      expect(container.read(loginNoticeProvider).state, isNull);

      final waiter = await auth.loginWithPin('22222');
      expect(waiter, isNotNull);
      expect(waiter!.role, UserRole.waiter);
      expect(container.read(loginNoticeProvider).state, isNull);

      // An unrelated account on a THIRD IP is still refused on this device.
      await db.addUser('کاشێر', '33333', UserRole.cashier,
          accessCode: '192.168.10.7');
      expect(await auth.loginWithPin('33333'), isNull);
      expect(container.read(loginNoticeProvider).state, isNotNull);
    });
  });

  group('ConnectIpPage (بەستنەوە بە IP)', () {
    Future<void> pumpConnectPage(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localDbProvider.overrideWithValue(db)],
          child: const MaterialApp(home: ConnectIpPage()),
        ),
      );
      await tester.pump();
    }

    /// The multi-IP page is taller than the 800x600 test viewport, so the
    /// Connect (کۆنێکت) button sits below the fold. Scroll it into view before
    /// tapping so the tap actually lands on the button.
    Future<void> tapConnect(WidgetTester tester) async {
      final connect = find.text('کۆنێکت');
      await tester.ensureVisible(connect);
      await tester.pumpAndSettle();
      await tester.tap(connect);
      await tester.pump();
    }

    testWidgets('invalid IP shows an error snackbar', (tester) async {
      await pumpConnectPage(tester);
      // The text field only allows digits and dots, so 'abc' would be filtered
      // to an empty string and silently treated as "nothing typed". Use an IP
      // that passes the character filter but fails IPv4 validation (999 > 255).
      await tester.enterText(find.byType(TextField), '999.1.1.1');
      await tapConnect(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('نیشانەی IP هەڵەیە'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('known account IP binds the device and reports success', (tester) async {
      await db.addUser('کاپتن', '33221', UserRole.waiter,
          accessCode: '192.168.10.5');
      await pumpConnectPage(tester);
      await tester.enterText(find.byType(TextField), '192.168.10.5');
      await tapConnect(tester);
      // The success snackbar (بەسترایتەوە) appears right after connect.
      var found = false;
      for (var i = 0; i < 45 && !found; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('بەسترایتەوە').evaluate().isNotEmpty) found = true;
      }
      expect(find.textContaining('بەسترایتەوە'), findsOneWidget);
      expect(await getDeviceAccessCode(), '192.168.10.5');
      // Let the success snackbar and the auto-return delay finish.
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('unknown account IP reports failure', (tester) async {
      await pumpConnectPage(tester);
      await tester.enterText(find.byType(TextField), '192.168.10.99');
      await tapConnect(tester);
      // The failure snackbar (پەیوەندی سەرکەوتوو نەبوو) appears right after
      // connect when no user on this device has that IP.
      var found = false;
      for (var i = 0; i < 45 && !found; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('پەیوەندی سەرکەوتوو نەبوو').evaluate().isNotEmpty) found = true;
      }
      expect(find.textContaining('پەیوەندی سەرکەوتوو نەبوو'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a small icon-only "+" button below the box adds another box', (tester) async {
      await pumpConnectPage(tester);
      expect(find.byType(TextField), findsOneWidget);

      // The "+" is an icon-only button (no text anywhere inside it), placed
      // BELOW the IP box.
      final addButton = find.byWidgetPredicate((w) =>
          w is IconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.add_rounded);
      expect(addButton, findsOneWidget);
      expect(find.descendant(of: addButton, matching: find.byType(Text)), findsNothing);
      final addY = tester.getCenter(addButton).dy;
      final boxY = tester.getCenter(find.byType(TextField).first).dy;
      expect(addY, greaterThan(boxY));

      // Clicking it makes a second box appear.
      await tester.tap(addButton);
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('boxes can be added up to 50; one more tap shows the limit snackbar', (tester) async {
      await pumpConnectPage(tester);
      final addButton = find.byWidgetPredicate((w) =>
          w is IconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.add_rounded);
      for (var i = 0; i < 49; i++) {
        await tester.ensureVisible(addButton);
        await tester.pump();
        await tester.tap(addButton);
        await tester.pump();
      }
      expect(find.byType(TextField), findsNWidgets(50));

      await tester.ensureVisible(addButton);
      await tester.pump();
      await tester.tap(addButton);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsNWidgets(50));
      expect(find.textContaining('گەیشتە 50 IP'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a box can be removed with its small "x"', (tester) async {
      await pumpConnectPage(tester);
      await tester.tap(find.byWidgetPredicate((w) =>
          w is IconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.add_rounded));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));

      // Remove the second box; one box remains.
      final removeButtons = find.byWidgetPredicate((w) =>
          w is IconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.cancel_rounded);
      expect(removeButtons, findsNWidgets(2));
      await tester.tap(removeButtons.at(1));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('all filled boxes are bound when connecting', (tester) async {
      await db.addUser('کاپتن', '33221', UserRole.waiter,
          accessCode: '192.168.10.5');
      await db.addUser('کاشێر', '33333', UserRole.cashier,
          accessCode: '192.168.10.7');
      await pumpConnectPage(tester);
      await tester.tap(find.byWidgetPredicate((w) =>
          w is IconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.add_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), '192.168.10.5');
      await tester.enterText(find.byType(TextField).at(1), '192.168.10.7');
      await tapConnect(tester);
      var found = false;
      for (var i = 0; i < 45 && !found; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('بەسترایتەوە').evaluate().isNotEmpty) found = true;
      }
      expect(find.textContaining('بەسترایتەوە'), findsOneWidget);
      final codes = await getDeviceAccessCodes();
      expect(codes.toSet(), {'192.168.10.5', '192.168.10.7'});
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('the "!" button on the login page opens the Connect page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LoginPage), findsOneWidget);

    await tester.tap(find.text('!'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConnectIpPage), findsOneWidget);

    disconnectSync();
    await tester.pump(const Duration(seconds: 11));
  });
}