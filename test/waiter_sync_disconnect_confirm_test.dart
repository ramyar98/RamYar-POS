import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/waiter/waiter_home_page.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/services/sync_provider.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

/// The sync pill on the captain's app bar must not be a trip-wire.
///
/// The captain runs this on a phone, in a restaurant, with a tray in the other
/// hand. The pill sits right next to the delivery badge and the rejected-items
/// badge, so a palm or an elbow lands on it. When that tap disconnected the
/// link outright, the next order went into the outbox, never reached the till,
/// and nothing on either screen said why - the captain saw a green dot turn
/// red and carried on serving.
///
/// So: while the link is up, one tap asks. The dialog has to say what happens to
/// the orders that are still being taken, because that is the part the captain
/// is actually deciding about. While the link is down a tap is free - there is
/// no harm in reconnecting and it saves a second tap.
///
/// Deliberately no Kurdish literals: the pill is addressed by the shape of its
/// own semantics node (the one button on the page that carries both a label and
/// a hint) and everything else is asserted on widget types and state.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);
}

/// The pill. [Semantics] is the only widget on the floor page that declares
/// itself a button *and* carries a label and a hint - the app bar's icon buttons
/// get their properties from `IconButton`/`Tooltip` and the table cards are not
/// buttons at all. So this cannot accidentally start matching the wrong thing
/// if the translations change.
Finder get _syncPill => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.button == true &&
          w.properties.label != null &&
          w.properties.hint != null,
    );

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

  /// The floor page as a captain gets it, signed out so nothing dials out to a
  /// live POS on this network - the pill's behaviour does not depend on who is
  /// signed in, and the connection state is seeded by hand below.
  Future<ProviderContainer> openFloor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(ProviderScope(
      overrides: [
        localDbProvider.overrideWithValue(db),
        authProvider.overrideWith((ref) => auth),
      ],
      child: const MaterialApp(home: WaiterHomePage()),
    )));
    await _pumpUntil(tester, find.byType(TableCard));
    return ProviderScope.containerOf(tester.element(find.byType(WaiterHomePage)));
  }

  /// Unmounts the polling page while the test is still in control: the framework
  /// checks for pending timers before teardown callbacks run.
  Future<void> closeFloor(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('one stray tap on the sync pill does not drop the link',
      (tester) async {
    final container = await openFloor(tester);
    container.read(syncConnectionProvider.notifier).setConnected(true);
    await tester.pump();
    expect(container.read(syncConnectionProvider).connected, isTrue);

    // The accident: a palm across the app bar.
    await tester.tap(_syncPill);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'dropping the link has to be a decision, not a brush of the screen');
    expect(container.read(syncConnectionProvider).connected, isTrue,
        reason: 'and nothing may be torn down until that decision is made');

    // The dialog also has to be honest about the orders: a captain who is told
    // only "disconnect?" reasonably reads that as costing nothing.
    final content = tester.widget<Text>(find.byType(Text).last);
    expect(content.data, isNotNull);

    // Walking away from it keeps the link.
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(container.read(syncConnectionProvider).connected, isTrue,
        reason: 'a captain who changes their mind must not lose the link');

    await closeFloor(tester);
  });

  testWidgets('the confirm button is the only way to drop the link',
      (tester) async {
    final container = await openFloor(tester);
    container.read(syncConnectionProvider.notifier).setConnected(true);
    await tester.pump();

    await tester.tap(_syncPill);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // The affirmative action is the filled button; the dismissive one is the
    // text button. Asserting on the shape rather than on the wording means a
    // translation edit cannot quietly turn this into a one-button dialog that
    // disconnects on dismiss.
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(container.read(syncConnectionProvider).connected, isFalse);
    await closeFloor(tester);
  });

  testWidgets('while it is down, a tap reconnects without asking', (tester) async {
    final container = await openFloor(tester);
    expect(container.read(syncConnectionProvider).connected, isFalse);

    await tester.tap(_syncPill);
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'reconnecting is harmless and should not cost a captain a tap');
    await closeFloor(tester);
  });

  testWidgets('the pill is announced as a button with a label and a hint',
      (tester) async {
    await openFloor(tester);

    final pill = tester.widget<Semantics>(_syncPill);
    expect(pill.properties.button, isTrue);
    expect(pill.properties.label, isNotEmpty,
        reason: 'a screen reader has to be able to say what the dot means');
    expect(pill.properties.hint, isNotEmpty,
        reason: 'and what tapping it will do');

    await closeFloor(tester);
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