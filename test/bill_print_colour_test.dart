import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/colors.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/core/table_status_visuals.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/page/cashier/cashier_unified_table_page.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';
import 'package:ramyar_pos/widgets/table_card.dart';

/// The floor's colour signal, from the moment the cashier prints a bill.
///
/// Two complaints are pinned here.
///
/// 1. THE DELAY. The print button used to push the receipt to the printer and
///    only then stamp the table. That put the printer's clock in front of the
///    floor's: a network printer that is switched off blocks on a five-second
///    connect, so the card stayed GREEN for five seconds after the cashier had
///    already printed - and with no cashier printer configured at all the table
///    was never stamped, so the bill never showed on the floor and the
///    ten-second red clock never started. Issuing the bill is a fact about the
///    floor and the paper is a side effect, so the fact is now written first.
///    Pressing print also used to call `refresh()`, which parks the whole floor
///    on a spinner; it is `refreshSilent()` now, so the grid never blinks.
///
/// 2. THE READABILITY. The status only tinted the card's corner by eight per
///    cent, which is invisible across a room - the only distance from which a
///    floor of a hundred cards is ever read. Each card now carries its status
///    as a real border, and the entrance cascade no longer stretches to four
///    and a half seconds on the last of a hundred cards.
///
/// No Kurdish literals are used to find things except the one message the
/// cashier is shown, so the tests keep working the way the rest of the suite
/// does.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // No isolate: a widget test runs inside `FakeAsync`, and a database in a
    // real isolate would never hand its results back.
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

  testWidgets('printing the bill turns the table blue at once, with no printer '
      'configured at all', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await db.occupyTable(1, '101', guestCount: 2);
    expect((await db.getTable(1))!.status, TableStatus.occupied);

    final container =
        ProviderContainer(overrides: [localDbProvider.overrideWithValue(db)]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: AppState(
        currentLanguage: AppLanguage.kurdish,
        onLanguageChanged: (_) {},
        child: const MaterialApp(
          home: CashierUnifiedTablePage(tableNumber: 1, initialTab: 0),
        ),
      ),
    ));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byIcon(Icons.print_rounded).evaluate().isNotEmpty) break;
    }
    final printButton = find.byIcon(Icons.print_rounded);
    expect(printButton, findsOneWidget, reason: 'the bill tab offers print');

    // Every state the floor list passes through, including the ones that live
    // only for a microtask. A plain read after the tap cannot see those - the
    // test's fake clock drains the microtasks before `tap` even returns - but a
    // listener on the provider sees each one as it happens.
    final states = <AsyncValue<List<TableModel>>>[];
    final subscription = container.listen(
      waiterProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await tester.ensureVisible(printButton);
    await tester.pumpAndSettle();

    states.clear();
    await tester.tap(printButton);
    await tester.pumpAndSettle();

    expect(states.where((s) => s.isLoading), isEmpty,
        reason: 'printing a bill must not blink the whole floor to a spinner');
    expect(container.read(waiterProvider).isLoading, isFalse);

    final table = await db.getTable(1);
    expect(table!.status, TableStatus.billRequested,
        reason: 'the bill is a fact about the floor and is written first');
    expect(table.printedAt, isNotEmpty,
        reason: 'the ten-second red clock starts when the bill is issued');

    // And the cashier is told the paper did not come out, instead of being
    // left to guess why the printer stayed quiet.
    expect(find.text('هیچ چاپکەرێک ڕێکنەخراوە'), findsOneWidget,
        reason: 'a missing printer is reported, not passed off as a success');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });

  testWidgets('every status paints its own colour on the card border, so a '
      'floor of cards can be read from across the room', (tester) async {
    Color borderOf(WidgetTester t) {
      final container =
          t.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final decoration = container.decoration! as BoxDecoration;
      return (decoration.border! as Border).top.color;
    }

    final seen = <Color>{};
    for (final status in TableStatus.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: TableCard(
                table: TableModel(id: 1, name: 'T', status: status),
                statusColor: TableStatusVisuals.color(status),
                statusText: status.name,
                statusIcon: TableStatusVisuals.icon(status),
                index: 0,
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      final border = borderOf(tester);
      final expected = status == TableStatus.empty
          ? AppColors.borderSide.withValues(alpha: 0.55)
          : TableStatusVisuals.color(status).withValues(alpha: 0.55);
      expect(border, expected,
          reason: 'a ${status.name} card must wear its own status colour');
      seen.add(border);
    }

    expect(seen, hasLength(TableStatus.values.length),
        reason: 'four statuses must not collapse onto one visible colour');
    // The free card stays quiet; the three live ones are a real edge.
    expect(
      borderOf(tester),
      isNot(AppColors.borderSide.withValues(alpha: 0.55)),
      reason: 'the loop ended on a live status, not on the free card',
    );
  });

  testWidgets('the entrance cascade is bounded, so a colour change is never '
      'waiting behind the animation', (tester) async {
    Future<Duration> durationFor(int index) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: TableCard(
                table: const TableModel(id: 1, name: 'T'),
                statusColor: TableStatusVisuals.free,
                statusText: 'empty',
                statusIcon: TableStatusVisuals.icon(TableStatus.empty),
                index: index,
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      return tester
          .widget<TweenAnimationBuilder<double>>(
              find.byType(TweenAnimationBuilder<double>))
          .duration;
    }

    // A hundred cards used to stagger forty milliseconds apart, so card 100
    // was still fading in four and a half seconds after the floor opened.
    final last = await durationFor(100);
    expect(last, lessThanOrEqualTo(const Duration(milliseconds: 620)),
        reason: 'the last card of a full floor must not lag seconds behind');
    expect(last, greaterThan(const Duration(milliseconds: 200)),
        reason: 'it should still be a cascade, not a hard cut');
  });
}
