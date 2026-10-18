import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/dollar_rate_model.dart';
import 'package:ramyar_pos/models/settlement_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_home_page.dart';
import 'package:ramyar_pos/page/login/dollar_rate_page.dart';
import 'package:ramyar_pos/page/login/pin_login_page.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/providers/dollar_rate_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/dollar_rate_banner.dart';

import 'owner_test_login.dart';

/// The admin's dollar rate: one number for the shop, set on the admin's device
/// and read by every cashier.
///
/// The rate is stored in the database rather than in preferences on purpose,
/// because a preference would leave every cashier quoting yesterday's figure -
/// the whole point of the box is that the cashiers and the admin are looking at
/// the SAME number. That makes it a synced value, so these tests cover all three
/// hops it has to survive: the local write, the wire, and the snapshot a device
/// that was switched off catches up on.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);

  void seed(UserModel? user) => state = user;
}

/// Pins the viewport to the tablet the app really runs on. Without this a
/// widget test inherits the 800x600 test default, which is neither the phone
/// nor the tablet size, and a layout that only works at neither would go
/// unnoticed.
void _useTabletViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The no-isolate factory, not the default one: a widget test runs inside
    // `FakeAsync`, and a database living in a real isolate would never hand its
    // results back, so every `await` on it would hang the test rather than fail
    // it. The socket test at the bottom opens its own databases and is the one
    // place a real isolate is used.
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    // The owner signs in with a real PIN through the keypad below, so the
    // stand-in PIN has to be the accepted one for this file.
    installTestOwnerPin();
  });

  tearDownAll(uninstallTestOwnerPin);

  group('the stored rate', () {
    late LocalDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = LocalDatabase();
      await db.resetForTesting();
      await db.init(inMemory: true);
    });

    tearDown(() async => db.resetForTesting());

    test('a device that has never been told a rate still says something sane', () async {
      // Not a crash and not a blank screen: a fresh cashier device has to render
      // a sentence, and the pair it falls back to is the one the admin's own
      // example uses, so the first number anybody reads is not a wrong one.
      final rate = await db.getDollarRate();
      expect(rate, DollarRate.fallback);
      expect(rate.isSet, isTrue);
      expect(rate.dollars, 100);
      expect(rate.iqd, 150000);
      expect(rate.iqdLabel, '150,000');
    });

    test('saving stores the pair, bumps the revision and broadcasts it', () async {
      final revisions = <int>[];
      db.dollarRateRevision.addListener(() => revisions.add(db.dollarRateRevision.value));
      final sent = <MapEntry<String, Map<String, dynamic>>>[];
      db.onMutation = (action, data) => sent.add(MapEntry(action, data));

      await db.setDollarRate(const DollarRate(dollars: 100, iqd: 150000));

      expect((await db.getDollarRate()).iqd, 150000);
      expect(revisions, [1], reason: 'an open screen has to refresh the moment it is saved');

      // The broadcast is what carries the rate to the cashiers, so it has to be
      // sent - and it has to carry the same stamp the row was written with, or
      // the "newest wins" comparison on the receiving side cannot be reasoned
      // about.
      final change = sent.singleWhere((e) => e.key == 'DOLLAR_RATE_CHANGED').value;
      expect(change['dollars'], 100);
      expect(change['iqd'], 150000);
      final stamp = change['updatedAt'] as String;
      expect(stamp, isNotEmpty);
      final row = (await db.db.query('shop_settings', where: 'key = ?',
          whereArgs: ['dollar_rate'])).single;
      expect(row['updatedAt'], stamp);
    });

    test('the admin can change the rate as often as they like', () async {
      for (final iqd in [150000.0, 200000.0, 148500.0, 150000.0]) {
        await db.setDollarRate(DollarRate(dollars: 100, iqd: iqd));
        expect((await db.getDollarRate()).iqd, iqd);
      }
      // A single row, replaced - not one row per save, which would leave the
      // shop reading whichever row it happened to find first.
      expect((await db.db.query('shop_settings')).length, 1);
    });

    test('a corrupt stored value falls back instead of taking the screen down', () async {
      // The rate is read on the cashier's home screen during a shift, so one bad
      // row must not be able to make that screen throw.
      await db.db.insert('shop_settings', {'key': 'dollar_rate', 'value': 'not json'});
      expect((await db.getDollarRate()).iqd, 150000);

      await db.db.update('shop_settings', {'value': '[1,2,3]'});
      expect((await db.getDollarRate()).iqd, 150000);

      await db.db.update('shop_settings', {'value': '{"dollars":"lots","iqd":null}'});
      expect((await db.getDollarRate()).iqd, 150000);
    });

    test('a zero or negative rate reads as unset rather than as a wrong price', () async {
      const zero = DollarRate(dollars: 100, iqd: 0);
      expect(zero.isSet, isFalse);
      expect(zero.iqdPerDollar, isNull, reason: 'no division by a price nobody set');
      const negative = DollarRate(dollars: -5, iqd: 150000);
      expect(negative.isSet, isFalse);
    });

    test('dinar figures are grouped and rounded, and dollars keep real cents', () {
      expect(const DollarRate(dollars: 100, iqd: 150000).iqdLabel, '150,000');
      expect(const DollarRate(dollars: 100, iqd: 1234567).iqdLabel, '1,234,567');
      expect(const DollarRate(dollars: 100, iqd: 1500.6).iqdLabel, '1,501',
          reason: 'the shop does not trade in half dinars');
      expect(const DollarRate(dollars: 100, iqd: 150000).dollarsLabel, '100');
      expect(const DollarRate(dollars: 100.5, iqd: 150000).dollarsLabel, '100.50');
    });

    group('a rate that arrives from another device', () {
      test('is applied, and is not sent on again', () async {
        final sent = <String>[];
        db.onMutation = (action, _) => sent.add(action);
        final revisions = <int>[];
        db.dollarRateRevision.addListener(() => revisions.add(db.dollarRateRevision.value));

        await db.applyDollarRate(
          const DollarRate(dollars: 100, iqd: 200000),
          updatedAt: '2026-01-01T10:00:00.000Z',
        );

        expect((await db.getDollarRate()).iqd, 200000);
        expect(revisions, [1]);
        // The echo is the bug this guards: the hub applies what the admin's
        // device sent and re-broadcasts it, and the admin's device applies that
        // and re-broadcasts it, and the two devices never stop talking.
        expect(sent, isEmpty);
      });

      test('loses to a newer rate, so a late message cannot undo a fresh one', () async {
        await db.setDollarRate(const DollarRate(dollars: 100, iqd: 150000));
        final savedStamp = (await db.db.query('shop_settings')).single['updatedAt'] as String;

        // An older rate, held up on a link - the cashier's screen must keep
        // showing the rate the admin last saved.
        await db.applyDollarRate(
          const DollarRate(dollars: 100, iqd: 999000),
          updatedAt: '2020-01-01T00:00:00.000Z',
        );
        expect((await db.getDollarRate()).iqd, 150000);

        // The same rate again (a relay) is harmless.
        await db.applyDollarRate(
          const DollarRate(dollars: 100, iqd: 150000),
          updatedAt: savedStamp,
        );
        expect((await db.getDollarRate()).iqd, 150000);
      });

      test('beats an older stored rate', () async {
        await db.setDollarRate(const DollarRate(dollars: 100, iqd: 150000));
        final stored = (await db.db.query('shop_settings')).single['updatedAt'] as String;
        await db.applyDollarRate(
          const DollarRate(dollars: 100, iqd: 220000),
          updatedAt: _bumpStamp(stored),
        );
        expect((await db.getDollarRate()).iqd, 220000);
      });
    });

    test('the rate rides in the snapshot, and applying it echoes nothing', () async {
      await db.setDollarRate(const DollarRate(dollars: 100, iqd: 175000));
      final snapshot = await db.buildSnapshot();
      expect((snapshot['dollar_rate'] as Map)['iqd'], 175000);

      final other = LocalDatabase();
      await other.resetForTesting();
      await other.init(inMemory: true);
      addTearDown(() => other.resetForTesting());
      final sent = <String>[];
      other.onMutation = (action, _) => sent.add(action);

      await other.applySnapshot(snapshot);

      expect((await other.getDollarRate()).iqd, 175000);
      expect(sent, isEmpty,
          reason: 'a snapshot is the server speaking; it has nothing to tell the server');
    });
  });

  testWidgets('the admin editor saves the number they typed, comma and all', (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());

    await tester.pumpWidget(_wrap(ProviderScope(
      overrides: [localDbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: DollarRatePage()),
    )));
    await tester.pumpAndSettle();

    // The admin reads "100$ equals 150,000" off a screen and types it back.
    // The comma is how the figure is written everywhere in the app, so accepting
    // it is the whole point of the field.
    await tester.enterText(find.widgetWithText(TextFormField, '100'), '100');
    await tester.enterText(find.widgetWithText(TextFormField, '150,000'), '150,000');
    await tester.pumpAndSettle();

    // The live preview has to be the sentence the cashiers will read, so it is
    // checked before saving rather than after: a preview that disagrees with
    // what eventually gets stored is worse than no preview.
    expect(find.text('100\$ بەرامبەر بە دیناری عیراقی 150,000'), findsOneWidget);

    await tester.tap(find.text('پاشەکەوتکردن'));
    await tester.pumpAndSettle();

    expect((await db.getDollarRate()).dollars, 100);
    expect((await db.getDollarRate()).iqd, 150000,
        reason: '"150,000" is 150000, not a rejected or a zero rate');
    expect(find.text('پاشەکەوتکرا'), findsOneWidget);
  });

  testWidgets('a rate the admin types as nonsense is refused, not silently zeroed',
      (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());
    await db.setDollarRate(const DollarRate(dollars: 100, iqd: 150000));

    await tester.pumpWidget(_wrap(ProviderScope(
      overrides: [localDbProvider.overrideWithValue(db)],
      child: const MaterialApp(home: DollarRatePage()),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, '150,000'), '0');
    await tester.pumpAndSettle();
    await tester.tap(find.text('پاشەکەوتکردن'));
    await tester.pumpAndSettle();

    // A "0$ equals 0" sentence on every cashier's screen is worse than no edit
    // at all, so the save is refused and the previous rate stands.
    expect((await db.getDollarRate()).iqd, 150000);
  });

  testWidgets('the cashier is shown the sentence the admin saved', (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());
    await db.setDollarRate(const DollarRate(dollars: 100, iqd: 150000));

    // The one test that drives the whole cashier home page, because the question
    // it answers is a question about the page: is the box actually on the
    // cashier's orders tab, and does it sit above the converter rather than
    // buried under it? The box's own behaviour is covered below on its own, so
    // this real socket bind happens once for the whole file.
    await _openCashierOrdersTab(tester, db);

    expect(find.text('ئادمێن نرخی دۆلاری داناوە'), findsOneWidget);
    expect(find.text('100\$ بەرامبەر بە دیناری عیراقی 150,000'), findsOneWidget);
    // Above the converter, as asked for: the admin's figure is the first thing
    // read, and the ad-hoc converter stays exactly where it was.
    expect(
      tester.getTopLeft(find.byType(DollarRateBanner)).dy,
      lessThan(tester.getTopLeft(find.text('گۆڕینەوەی نرخ')).dy),
    );
  });

  testWidgets('the rate box offers no way to edit the rate', (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());
    await db.setDollarRate(const DollarRate(dollars: 100, iqd: 150000));
    await _pumpBanner(tester, db);

    // A cashier who can move the number every other cashier reads is a cashier
    // who can lie about the rate, so the box is a sentence and nothing more -
    // not a field, not a save button, and not even something to tap.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('پاشەکەوتکردن'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('the rate box follows a rate the admin changes while they watch',
      (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());
    await db.setDollarRate(const DollarRate(dollars: 100, iqd: 150000));
    await _pumpBanner(tester, db);
    expect(find.text('100\$ بەرامبەر بە دیناری عیراقی 150,000'), findsOneWidget);

    // The rate moves on the admin's device and lands here. A box that needed the
    // cashier to leave the screen and come back would be a box they read stale
    // while quoting it to a customer.
    await db.applyDollarRate(
      const DollarRate(dollars: 100, iqd: 200000),
      updatedAt: '2099-01-01T00:00:00.000Z',
    );
    await _pumpUntil(tester, find.text('100\$ بەرامبەر بە دیناری عیراقی 200,000'));

    expect(find.text('100\$ بەرامبەر بە دیناری عیراقی 150,000'), findsNothing);
  });

  testWidgets('a device with no rate saved yet still says something', (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());
    await _pumpBanner(tester, db);

    // Better a plausible figure the admin recognises on sight than a blank gap
    // the cashier has to interrupt someone to ask about on their first shift.
    expect(find.text('100\$ بەرامبەر بە دیناری عیراقی 150,000'), findsOneWidget);
  });

  testWidgets('the rate box says nothing at all until it has an answer', (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());

    // The provider is overridden with a read that never finishes, which is the
    // state a cashier's screen really is in for the moment between opening the
    // tab and the database answering. A gap there is honest; a placeholder rate
    // is a number somebody could quote to a customer.
    await _pumpBannerOn(tester, db, Completer<DollarRate>().future);
    expect(find.textContaining('\$'), findsNothing);
    expect(find.textContaining('دیناری عیراقی'), findsNothing);
  });

  testWidgets('the rate box says nothing at all if the read fails', (tester) async {
    _useTabletViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    addTearDown(() => db.resetForTesting());

    // A read that throws is the same argument from the other end: a cashier must
    // not be handed a number nobody set just because the disk misbehaved.
    final read = Completer<DollarRate>();
    await _pumpBannerOn(tester, db, read.future);
    read.completeError(StateError('disk is having a day'));
    await tester.pump();
    // The failure is reported to the test's zone as well as to the provider.
    // Taken out of the queue so the assertions below are about the box and not
    // about the deliberately broken read.
    while (tester.takeException() != null) {}

    expect(find.textContaining('دیناری عیراقی'), findsNothing);
    expect(find.textContaining('\$'), findsNothing);
  });

  group('the login screen', () {
    /// Builds a fresh login screen. The widget is torn down first because
    /// `pumpWidget` reuses an existing `State` when the widget type and position
    /// are unchanged - so a second call would silently keep the flag the first
    /// call had drawn, and the test would prove nothing.
    Future<void> pumpLogin(
      WidgetTester tester,
      LocalDatabase db,
      _SeededAuthNotifier auth,
    ) async {
      _useTabletViewport(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap(ProviderScope(
        overrides: [
          localDbProvider.overrideWithValue(db),
          authProvider.overrideWith((ref) => auth),
        ],
        child: const MaterialApp(home: PinLoginPage()),
      )));
      await tester.pumpAndSettle();
    }

    /// Types [pin] on the real keypad, the way the person at the till does, and
    /// waits for the login to finish. Five digits is the keypad's length, so the
    /// last one submits by itself.
    ///
    /// Pumped frame by frame rather than with `pumpAndSettle`: a successful
    /// login swaps in a whole home screen, and some of those keep an animation
    /// running forever, so "settle" would never come back. What matters here is
    /// that the submit had time to run and the role had time to be written.
    Future<void> signInWith(
      WidgetTester tester,
      LocalDatabase db,
      _SeededAuthNotifier auth,
      String pin,
    ) async {
      await pumpLogin(tester, db, auth);
      for (final digit in pin.split('')) {
        await tester.tap(find.text(digit).first);
        await tester.pump();
      }
      // The page waits 300ms on purpose before authenticating, then the
      // navigation lands. Two long pumps cover both without racing them.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    // The rate used to be set from a dollar button on this page. It was removed
    // on request: the login screen is the first thing anyone sees and a stray
    // "settings" affordance there is a trap waiting for whoever is standing at
    // the till. These tests hold that closed for every role, so it cannot drift
    // back in - the button has to be gone for the owner and the admin too, not
    // only for the cashier.

    testWidgets('the login screen carries no rate control at all', (tester) async {
      _useTabletViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final db = LocalDatabase();
      await db.resetForTesting();
      await db.init(inMemory: true);
      addTearDown(() => db.resetForTesting());
      final auth = _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());

      await pumpLogin(tester, db, auth);
      expect(find.text('\$'), findsNothing);
      expect(find.byIcon(Icons.attach_money), findsNothing);
      expect(find.byTooltip('نرخی دۆلار'), findsNothing);
    });

    testWidgets('no role gets the rate button back on the login screen',
        (tester) async {
      _useTabletViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final db = LocalDatabase();
      await db.resetForTesting();
      await db.init(inMemory: true);
      addTearDown(() => db.resetForTesting());
      expect(await db.addUser('ئادمێن', '12345', UserRole.admin), isTrue);
      expect(await db.addUser('کاشێر 1', '54321', UserRole.cashier), isTrue);
      expect(await db.addUser('کاپتن 1', '11111', UserRole.waiter), isTrue);

      // Each role signs in and lands back on the login screen, and the button is
      // still absent - including for the owner, who is the one person who
      // genuinely needs to be able to change the rate.
      for (final pin in <String>[testOwnerPin, '12345', '54321', '11111']) {
        final auth =
            _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());
        await signInWith(tester, db, auth, pin);
        await pumpLogin(tester, db, auth);
        expect(find.text('\$'), findsNothing,
            reason: 'the rate button must not come back for PIN $pin');
      }
    });

    testWidgets('the login screen no longer records who signed in last',
        (tester) async {
      // The remembered role existed only to decide whose device was allowed to
      // show the button. With the button gone the key is dead weight, and dead
      // keys are what let a stale flag decide behaviour years later - so it is
      // gone from the login page entirely.
      _useTabletViewport(tester);
      SharedPreferences.setMockInitialValues({});
      final db = LocalDatabase();
      await db.resetForTesting();
      await db.init(inMemory: true);
      addTearDown(() => db.resetForTesting());
      expect(await db.addUser('ئادمێن', '12345', UserRole.admin), isTrue);
      final auth = _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());

      await signInWith(tester, db, auth, '12345');
      expect(
        (await SharedPreferences.getInstance()).getString('ramyar_last_login_role'),
        isNull,
      );
    });
  });

  test('the rate reaches the cashier device over the wire', () async {
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_rate_wire');

    // A real socket, a real handshake and two real files: the only thing that
    // proves the rate travels is a test where the second database is genuinely
    // somewhere else. The isolating factory is safe to use here precisely
    // because this is not a widget test and the isolate's answers do come back.
    databaseFactory = databaseFactoryFfi;
    final admin = LocalDatabase();
    await admin.init(path: '${tmp.path}${Platform.pathSeparator}rate-admin.db');
    final ip = await startSyncServer(admin, 1, 'admin', SyncStateNotifier(), port: 9884);
    expect(ip, isNotNull);

    final cashier = LocalDatabase();
    await cashier.init(path: '${tmp.path}${Platform.pathSeparator}rate-cashier.db');

    // A device that has just dialled in is handed a full snapshot, and that
    // snapshot carries the rate. So the opening snapshot has to be waited out
    // BEFORE the admin saves anything - otherwise the rate arrives that way and
    // the test passes whether or not the live mutation works at all, which is
    // the entire thing being tested. An earlier version of this test did exactly
    // that and passed with the receive code commented out.
    final opened = Completer<void>();
    onSyncDataApplied = () {
      if (!opened.isCompleted) opened.complete();
    };
    try {
      expect(
        await connectToServer(cashier, ip!, 5, 'cashier', SyncStateNotifier(), port: 9884),
        isTrue,
      );
      await opened.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => fail('the cashier device never received the opening snapshot'),
      );
    } finally {
      onSyncDataApplied = null;
    }

    // The admin opens the editor, types the figure, saves. The cashier - who is
    // not even logged in, just sitting on the login screen - has to end up
    // reading the same number without anyone re-saving it on their device, and
    // without their screen being reopened.
    await admin.setDollarRate(const DollarRate(dollars: 100, iqd: 195000));

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while ((await cashier.getDollarRate()).iqd != 195000) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the rate never reached the cashier device');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect((await cashier.getDollarRate()).dollars, 100);

    // And the round trip stops there: the cashier's device is not a second
    // source of truth for the rate.
    expect(await cashier.getPendingSyncAll(), isEmpty);

    disconnectSync();
    await admin.resetForTesting();
    await cashier.resetForTesting();
    tmp.deleteSync(recursive: true);
    // Hand the factory back, so a later test in this file that opens a widget is
    // not silently handed the isolating one.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
}

/// A stamp that sorts after [stored] without needing to parse it, which is how
/// the receiving side compares them.
String _bumpStamp(String stored) =>
    DateTime.parse(stored).add(const Duration(seconds: 1)).toIso8601String();

/// Signs a cashier in, starts their shift, lands them on the orders tab, and
/// then lets the page's own timers finish so nothing is left running when the
/// tree is torn down.
///
/// Two things here are not optional. A cashier with no shift open sees nothing
/// but the "start shift" gate, so starting the shift is the only way to reach
/// the tab at all. And the page auto-hosts the POS socket server with a local-IP
/// timeout, so the tree is pumped past that timeout and the server is
/// disconnected - otherwise the test ends with a pending timer and the failure
/// lands in whichever test happens to run next.
Future<void> _openCashierOrdersTab(WidgetTester tester, LocalDatabase db) async {
  const cashierId = 5;
  const cashierName = 'کاشێر 1';
  final auth = _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());
  auth.seed(
      const UserModel(id: cashierId, name: cashierName, pin: '2233', role: UserRole.cashier));
  await db.startShift(CashierShift(
    cashierId: cashierId,
    cashierName: cashierName,
    startedAt: DateTime.now().toIso8601String(),
  ));

  await tester.pumpWidget(_wrap(ProviderScope(
    overrides: [
      localDbProvider.overrideWithValue(db),
      authProvider.overrideWith((ref) => auth),
    ],
    child: const MaterialApp(home: CashierHomePage()),
  )));
  await _pumpUntil(tester, find.text('داواکاری'));
  await tester.tap(find.text('داواکاری'));
  await _pumpUntil(tester, find.text('گۆڕینەوەی نرخ'));

  await tester.pump(const Duration(seconds: 4));
  disconnectSync(db);
  await tester.pump();
}

/// Pumps the rate box on its own, the way a cashier's screen holds it.
///
/// Deliberately not a whole cashier home page. That page hosts the POS socket
/// server and keeps a clock timer running, so every test that stands one up
/// costs a real port bind and a teardown dance. The box itself is a plain widget
/// that reads one provider, so testing it here is both honest and cheap - and it
/// leaves exactly one test in this file driving the full page, where the
/// question is about placement rather than about the box.
Future<void> _pumpBanner(WidgetTester tester, LocalDatabase db) async {
  await tester.pumpWidget(_wrap(ProviderScope(
    overrides: [localDbProvider.overrideWithValue(db)],
    child: const MaterialApp(
      home: Scaffold(body: SizedBox.shrink(child: DollarRateBanner())),
    ),
  )));
  await _pumpUntil(tester, find.text('ئادمێن نرخی دۆلاری داناوە'));
}

/// Pumps the rate box on a provider whose read is [read] - a read that is
/// pending, or one the caller completes afterwards.
///
/// Never `pumpAndSettle`: a pending read has nothing to settle, and the box
/// under test is meant to be sitting there drawing nothing.
Future<void> _pumpBannerOn(
  WidgetTester tester,
  LocalDatabase db,
  Future<DollarRate> read,
) async {
  await tester.pumpWidget(_wrap(ProviderScope(
    overrides: [
      localDbProvider.overrideWithValue(db),
      dollarRateProvider.overrideWith((ref) => read),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SizedBox.shrink(child: DollarRateBanner())),
    ),
  )));
  // Two frames: one to build the box and start the read, one to let the provider
  // settle into whatever state the read is in.
  await tester.pump();
  await tester.pump();
}

/// Pumps until [finder] shows up, or gives up. Used instead of `pumpAndSettle`
/// because these pages keep a periodic clock running that will never settle.
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
/// viewport (the app's tablets run landscape, and a phone-sized window would
/// let text overflow hide a layout problem), and [AppState] because every
/// visible string goes through `context.tr`, which reads the language from
/// there and falls back to Kurdish without it.
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
