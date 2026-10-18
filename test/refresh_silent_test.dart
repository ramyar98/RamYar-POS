import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';

/// An unchanged floor must not be re-published.
///
/// The cashier's page polls the floor every second and the captain's every
/// two, and `refreshSilent()` used to publish a freshly-read list on every
/// call - so a tablet showing a hundred tables rebuilt and repainted the whole
/// grid once a second for as long as the app sat idle. That is the heat, the
/// jank and the battery an idle POS tablet used to burn. The poll still runs
/// (the 10-minute overdue clock depends on it), but publishing now happens
/// only when the data really differs: same floor in, same state out, no
/// listeners fire; a genuine change still reaches the screen.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;
  late ProviderContainer container;
  late WaiterNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    container = ProviderContainer(
      overrides: [localDbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    notifier = container.read(waiterProvider.notifier);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  test('refreshSilent publishes a change, and stays quiet when there is none',
      () async {
    // A fresh install seeds 100 tables. This is the first read, so it has to
    // land - nothing has been published yet.
    await notifier.refreshSilent();
    final idle = container.read(waiterProvider).asData?.value;
    expect(idle, isNotNull, reason: 'the first read must publish');
    expect(idle, hasLength(100), reason: 'the seeded floor');

    // The idle case: reading identical data again must leave the very same
    // list instance in place. Swapping it for a new instance is what notifies
    // every listener - and what rebuilt the whole grid on every poll.
    await notifier.refreshSilent();
    expect(
      identical(container.read(waiterProvider).asData?.value, idle),
      isTrue,
      reason: 'an unchanged floor must not be re-published: every publish '
          'rebuilds and repaints every card on screen',
    );

    // A real change: seating a table moves its status, waiter and guest
    // count, so the very next refresh must publish it.
    await db.occupyTable(1, '7', guestCount: 3);
    await notifier.refreshSilent();
    final seated = container.read(waiterProvider).asData?.value;
    expect(
      identical(seated, idle),
      isFalse,
      reason: 'a status change must reach the floor',
    );
    expect(seated, hasLength(100));
  });
}
