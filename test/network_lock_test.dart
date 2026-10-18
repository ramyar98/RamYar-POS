import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/cashier/cashier_welcome_page.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/providers/network_lockdown_provider.dart';
import 'package:ramyar_pos/widgets/network_lock_screen.dart';

/// Verifies the "Wi-Fi lost -> the WHOLE system locks; Wi-Fi back -> it
/// unlocks automatically without re-entering the PIN" behaviour:
///  - the lockdown provider transitions offline/wrongNetwork -> locked and
///    back to unlocked,
///  - the full-screen overlay renders over EVERY route and cannot be popped,
///  - when booted with a live session, the overlay covers the home page and
///    an unlock removes it while the session's page stays alive underneath.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // NoIsolate keeps sqflite on the calling isolate so DB futures resolve
    // inside testWidgets' fake-async zone - exactly like the other page tests.
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
    await db.resetForTesting();
  });

  group('network lock provider', () {
    test('starts unlocked', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(networkLockProvider).locked, isFalse);
      expect(container.read(networkLockProvider).reason, isNull);
    });

    test('locks for offline and for unknown network, then unlocks', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(networkLockProvider.notifier);

      notifier.lock(NetworkLockReason.offline, localIp: '192.168.1.5');
      var state = container.read(networkLockProvider);
      expect(state.locked, isTrue);
      expect(state.reason, NetworkLockReason.offline);
      expect(state.localIp, '192.168.1.5');

      notifier.lock(NetworkLockReason.wrongNetwork);
      state = container.read(networkLockProvider);
      expect(state.locked, isTrue);
      expect(state.reason, NetworkLockReason.wrongNetwork);

      notifier.unlock();
      state = container.read(networkLockProvider);
      expect(state.locked, isFalse);
      expect(state.reason, isNull);
      expect(state.localIp, isNull);
    });
  });

  group('NetworkLockScreen', () {
    Future<void> pumpLock(WidgetTester tester, NetworkLockReason reason) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: NetworkLockScreen(reason: reason),
            ),
          ),
        ),
      );
    }

    testWidgets('offline variant shows the Wi-Fi lost title and hint',
        (tester) async {
      await pumpLock(tester, NetworkLockReason.offline);
      expect(find.text('قوفڵکرا - وایفای نەما'), findsOneWidget);
      expect(
        find.text(
            'سیستەم ڕاوەستاوە بۆ پاراستنی داتاکان. کاتێک وایفای گەڕایەوە، بە خۆکاری دەکرێتەوە.'),
        findsOneWidget,
      );
      expect(find.text('چاوەڕوانی وایفای...'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('untrusted-network variant explains the wrong network',
        (tester) async {
      await pumpLock(tester, NetworkLockReason.wrongNetwork);
      expect(find.text('قوفڵکرا - تۆڕەکە نەناسراوە'), findsOneWidget);
      expect(
        find.text(
            'لە تۆڕی ڕێستۆرانت نیت. بگەڕێوە بۆ وایفای ڕێستۆرانتەکە و سیستەمەکە بە خۆکاری دەکرێتەوە.'),
        findsOneWidget,
      );
    });

    testWidgets('the overlay cannot be popped away by the user',
        (tester) async {
      await pumpLock(tester, NetworkLockReason.offline);
      final scope = tester.widget<PopScope>(find.byType(PopScope));
      expect(scope.canPop, isFalse);
    });
  });

  group('full app lockdown', () {
    testWidgets(
        'a lost network while a cashier is signed in locks the whole app and '
        'unlock resumes the same session (no PIN re-entry)', (tester) async {
      // Save a cashier session so the app boots straight into the home page.
      await db.seedDefaultStaff();
      SharedPreferences.setMockInitialValues({'loggedUserId': 4});

      final lockNotifier = NetworkLockNotifier()
        ..lock(NetworkLockReason.offline, localIp: '192.168.1.5');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDbProvider.overrideWithValue(db),
            networkLockProvider.overrideWith((ref) => lockNotifier),
          ],
          child: const RamyarPosApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The cashier session is live, but the full-screen blocker covers it.
      expect(find.byType(NetworkLockScreen), findsOneWidget);
      expect(find.text('قوفڵکرا - وایفای نەما'), findsOneWidget);

      // Network comes back: the guard calls unlock() and the overlay lifts,
      // while the page underneath (the cashier session) stays alive.
      lockNotifier.unlock();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(NetworkLockScreen), findsNothing);
      expect(find.byType(CashierWelcomePage), findsOneWidget,
          reason: 'a cashier without an open shift lands on the welcome page');
      expect(find.byType(LoginPage), findsNothing,
          reason: 'the session is preserved - no PIN re-entry');

      // Unmount the app so the welcome page's clock timer is cancelled before
      // the test framework checks for pending timers.
      await tester.pumpWidget(const SizedBox());
    });
  });
}