import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/app_prefs.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_welcome_page.dart';
import 'package:ramyar_pos/page/login/connect_ip_page.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/page/login/pin_login_page.dart';
import 'package:ramyar_pos/services/network_guard_service.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The owner-facing onboarding flow and the Wi-Fi blocking of the login /
/// Connect screens:
///  - a cashier account created elsewhere signs in on THIS device only after
///    its IP is entered and connected on the Connect "!" page, then the PIN;
///  - the login keypad locks instantly the moment Wi-Fi is gone;
///  - the Connect page boxes turn black + locked while offline.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    NetworkGuardService.instance.status.value = RestaurantNetworkStatus.secure;
    await db.resetForTesting();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 900);
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
    expect(
      find.byType(LoginPage),
      findsOneWidget,
      reason: 'login not shown at boot',
    );
  }

  Future<void> tapPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  /// Taps the Connect (کۆنێکت) button, scrolling it into view first.
  Future<void> tapConnect(WidgetTester tester) async {
    final connect = find.text('کۆنێکت');
    await tester.ensureVisible(connect);
    await tester.pumpAndSettle();
    await tester.tap(connect);
    await tester.pump();
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxTries = 45,
  }) async {
    var found = false;
    for (var i = 0; i < maxTries && !found; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) found = true;
    }
    expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
  }

  testWidgets(
    'cashier created elsewhere signs in on the laptop: Connect-page IP then PIN',
    (tester) async {
      // The laptop already received the account the owner created on the phone
      // (registry synced) - the member still must bind the IP on this device.
      await db.addUser(
        'کاشێر',
        '22334',
        UserRole.cashier,
        accessCode: '192.168.8.50',
      );
      await pumpApp(tester);

      // Open the Connect page from the "!" icon next to the language selector.
      await tester.tap(find.text('!'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(ConnectIpPage),
        findsOneWidget,
        reason: 'the "!" button must open the Connect page',
      );

      await tester.enterText(find.byType(TextField).first, '192.168.8.50');
      await tester.pump(const Duration(milliseconds: 100));
      await tapConnect(tester);

      // Synced account on this device -> instant bind + success snack.
      await pumpUntilFound(tester, find.textContaining('بەسترایتەوە'));
      expect(find.textContaining('بەسترایتەوە'), findsOneWidget);

      // The Connect page pops back to the login after a short delay.
      await pumpUntilFound(tester, find.byType(LoginPage));
      expect(
        find.byType(LoginPage),
        findsOneWidget,
        reason: 'Connect page should return to login after a successful bind',
      );

      // Now the cashier PIN unlocks this laptop.
      await tapPin(tester, '22334');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(
        find.byType(CashierWelcomePage),
        findsOneWidget,
        reason: 'IP-bound cashier PIN must sign in on the laptop',
      );
      final codes = await getDeviceAccessCodes();
      expect(
        codes,
        contains('192.168.8.50'),
        reason: 'the typed IP must be bound on this device',
      );
    },
  );

  testWidgets('unknown PIN after binding shows the PIN-not-found guidance', (
    tester,
  ) async {
    await db.addUser(
      'کاشێر',
      '22334',
      UserRole.cashier,
      accessCode: '192.168.8.50',
    );
    // Device already bound from a previous Connect-page visit.
    await saveDeviceAccessCode('192.168.8.50');
    await pumpApp(tester);

    await tapPin(tester, '99999');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(LoginPage),
      findsOneWidget,
      reason: 'unknown PIN must not log in',
    );
    expect(
      find.text(
        'ئەم PINـە لەم ئامێرەدا نەدۆزرایەوە - دڵنیابە IPـەکە ڕاستە و ئامێرەکە لەسەر هەمان وای-فایە',
      ),
      findsOneWidget,
      reason: 'a bound device must explain that this PIN matches no account',
    );
  });

  testWidgets('plain wrong PIN on a fresh device shows the wrong-PIN message', (
    tester,
  ) async {
    // Brand new device: no accounts, nothing bound - the generic message.
    await pumpApp(tester);

    await tapPin(tester, '99999');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      find.text('وشەی نهێنی هەڵەیە'),
      findsOneWidget,
      reason: 'nothing bound -> honest wrong-password message',
    );
  });

  testWidgets('login screen hides the dollar admin controls', (tester) async {
    await pumpApp(tester);

    expect(
      find.text('!'),
      findsOneWidget,
      reason: 'the IP connect button must stay visible',
    );
    expect(
      find.text('\$'),
      findsNothing,
      reason: 'the dollar icon must be removed from the login screen',
    );
    expect(
      find.textContaining('نرخی دۆلار'),
      findsNothing,
      reason: 'the dollar-rate hint must not appear on the login screen',
    );
  });

  testWidgets('a staff session is not restored once the device is unbound', (
    tester,
  ) async {
    // A member is signed in on this device while it is bound to their IP...
    await db.addUser(
      'کاشێر',
      '22334',
      UserRole.cashier,
      accessCode: '192.168.8.50',
    );
    final member = (await db.getUserByPin('22334'))!;
    await saveDeviceAccessCode('192.168.8.50');
    await AppPrefs.instance.setInt('loggedUserId', member.id);

    tester.view.physicalSize = const Size(800, 900);
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
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(CashierWelcomePage),
      findsOneWidget,
      reason: 'a bound device restores its own signed-in member',
    );

    // ...and the owner then takes the tablet away and unbinds its IP. Coming
    // back up must not put that member back in: the saved session used to be
    // restored unconditionally, so unbinding only took effect on a manual
    // logout - long after it should have.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await saveDeviceAccessCodes([]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byType(CashierWelcomePage),
      findsNothing,
      reason: 'the member must not be let back in by the saved session',
    );
    expect(
      find.byType(LoginPage),
      findsOneWidget,
      reason: 'an unbound device comes back up on the login screen',
    );
    expect(
      await AppPrefs.instance.getInt('loggedUserId'),
      isNull,
      reason: 'the stale session is dropped so the screen starts from the owner',
    );
  });

  testWidgets(
    'blank Connect-page fields stay harmless until an IP is entered',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localDbProvider.overrideWithValue(db)],
          child: const MaterialApp(home: ConnectIpPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final connect = find.text('کۆنێکت');
      await tester.ensureVisible(connect);
      await tester.pumpAndSettle();
      await tester.tap(connect);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('لانی کەم یەک IP'),
        findsNothing,
        reason: 'blank boxes should not trigger a connect error',
      );
      expect(
        find.textContaining('بەسترایتەوە'),
        findsNothing,
        reason: 'blank boxes must not count as a successful bind',
      );
    },
  );

  testWidgets('Connect page: boxes turn black + locked when Wi-Fi is gone', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDbProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ConnectIpPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Simulate losing the restaurant network (widget tests never reach the
    // real platform channels, so drive the guard's notifier directly).
    final guard = NetworkGuardService.instance;
    guard.status.value = RestaurantNetworkStatus.offline;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('وایفای پەیوەست نییە - ناتوانیت ببەسترێیتەوە'),
      findsOneWidget,
      reason: 'offline banner must appear on the Connect page',
    );
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, isNotEmpty);
    for (final field in fields) {
      expect(field.enabled, isFalse, reason: 'IP boxes must be locked offline');
      final deco = field.decoration as InputDecoration;
      expect(
        deco.fillColor,
        Colors.black,
        reason: 'IP boxes must be black offline',
      );
    }
    final connectBtn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      connectBtn.onPressed,
      isNull,
      reason: 'Connect must be disabled offline',
    );
    // Restore for the next test.
    guard.status.value = RestaurantNetworkStatus.secure;
    await tester.pump();
  });

  testWidgets('login screen immediately blocks the keypad when Wi-Fi is gone', (
    tester,
  ) async {
    await pumpApp(tester);

    final guard = NetworkGuardService.instance;
    guard.status.value = RestaurantNetworkStatus.offline;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final keypad = tester.widget<PinKeypad>(find.byType(PinKeypad));
    expect(
      keypad.enabled,
      isFalse,
      reason: 'keypad must be locked as soon as the network is lost',
    );
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'the login card has no IP box anymore (Connect page only)',
    );
    expect(
      find.text(NetworkGuardService.wifiLostBanner),
      findsOneWidget,
      reason: 'the Wi-Fi blocking banner must show',
    );
    guard.status.value = RestaurantNetworkStatus.secure;
    await tester.pump();
  });
}
