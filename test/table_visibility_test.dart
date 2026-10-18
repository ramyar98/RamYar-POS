import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/providers/waiter_provider.dart';

/// Who may see which tables.
///
/// Only a captain (کاپتن) is narrowed. The owner narrows a captain either with a
/// مەودا (range) or by picking tables by hand, and BOTH mean the same thing: the
/// captain then sees only those tables, plus the ones they opened themselves and
/// the ones a cashier opened for the shared floor. With no scope at all the
/// captain is "normal" and sees the whole floor - the state
/// «گەڕانەوە بۆ ئاسایی» returns them to. A cashier must ALWAYS see the whole
/// floor - however many tables exist, however many were added since they signed
/// in, and no matter which captain used this device before them. Owner and admin
/// see everything.
///
/// The list used to be narrowed by an id remembered from the last login, and
/// that id was only ever *set* for a captain and never cleared - so a cashier
/// logging in after a captain inherited that captain's short list. These tests
/// pin the role-driven rule down.
class _SeededAuthNotifier extends AuthNotifier {
  _SeededAuthNotifier(super.db, super.logoutReason, super.loginNotice);

  void seed(UserModel? user) => state = user;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;
  late _SeededAuthNotifier auth;
  late ProviderContainer container;
  late WaiterNotifier notifier;

  /// A fresh install seeds 100 unowned tables ('مێز 1' .. 'مێز 100').
  const seeded = 100;

  var pinSeq = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pinSeq = 0;
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    auth = _SeededAuthNotifier(db, LogoutReasonNotifier(), LoginNoticeNotifier());
    container = ProviderContainer(
      overrides: [
        localDbProvider.overrideWithValue(db),
        authProvider.overrideWith((ref) => auth),
      ],
    );
    addTearDown(container.dispose);
    notifier = container.read(waiterProvider.notifier);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  /// `addUser` lets SQLite assign the id, so read the real account back rather
  /// than assuming one - `waiter_tables`, `tables.createdBy` and the table
  /// scope are all keyed on the stored id.
  Future<UserModel> createAccount(String name, UserRole role,
      {int? from, int? to}) async {
    final pin = '90${(++pinSeq).toString().padLeft(3, '0')}';
    final ok = await db.addUser(name, pin, role, rangeStart: from, rangeEnd: to);
    expect(ok, isTrue, reason: 'creating $name');
    final created = await db.getUserByPin(pin);
    expect(created, isNotNull, reason: 'reading $name back');
    return created!;
  }

  Future<UserModel> createCaptain({int? from, int? to}) =>
      createAccount('کاپتن', UserRole.waiter, from: from, to: to);

  Future<UserModel> createCashier() => createAccount('کاشێر', UserRole.cashier);

  /// Signs [user] in and returns the table ids they can see, ascending.
  Future<List<int>> seeAs(UserModel? user) async {
    auth.seed(user);
    await notifier.syncTableScope();
    await notifier.refreshSilent();
    final tables =
        container.read(waiterProvider).asData?.value ?? const <TableModel>[];
    return tables.map((TableModel t) => t.id).toList()..sort();
  }

  /// A table created by [ownerId], past the seeded id range so it can never be
  /// mistaken for a seeded one.
  Future<void> addTableOwnedBy(int id, int ownerId) async {
    await db.addTable(TableModel(id: id, name: 'مێزی $id', createdBy: ownerId));
  }

  List<int> range(int from, int to) => [for (var i = from; i <= to; i++) i];

  group('a captain is narrowed', () {
    test('a مەودا alone limits them to that window', () async {
      final a = await createCaptain(from: 1, to: 10);
      expect(await seeAs(a), range(1, 10));
    });

    test('an assigned table outside the مەودا joins their list', () async {
      final a = await createCaptain(from: 1, to: 10);
      await db.assignTablesToWaiter(a.id, [55, 56]);
      expect(await seeAs(a), [...range(1, 10), 55, 56]);
    });

    test('a captain with no مەودا sees every unowned table', () async {
      final a = await createCaptain();
      expect(await seeAs(a), range(1, seeded));
    });

    test("another captain's own tables stay hidden", () async {
      final a = await createCaptain(from: 1, to: 10);
      final b = await createCaptain(from: 11, to: 20);
      await addTableOwnedBy(201, a.id);
      await addTableOwnedBy(202, b.id);
      expect(await seeAs(a), [...range(1, 10), 201]);
      expect(await seeAs(b), [...range(11, 20), 202]);
    });

    test('a table a cashier created is visible to every captain', () async {
      final a = await createCaptain(from: 1, to: 5);
      final c = await createCashier();
      await addTableOwnedBy(203, c.id);
      expect(await seeAs(a), [...range(1, 5), 203]);
    });
  });

  group('a cashier always sees every table', () {
    test('a cashier sees the whole floor', () async {
      final c = await createCashier();
      expect(await seeAs(c), range(1, seeded));
    });

    test('a cashier who signs in AFTER a captain is not narrowed by them',
        () async {
      // The regression: the captain's scope used to survive the switch, so this
      // cashier saw 11 tables instead of 100.
      final a = await createCaptain(from: 1, to: 10);
      final c = await createCashier();
      await db.assignTablesToWaiter(a.id, [55]);

      expect(await seeAs(a), [...range(1, 10), 55],
          reason: 'the captain should start narrowed');
      expect(await seeAs(c), range(1, seeded),
          reason: 'the cashier must not inherit the captain scope');
    });

    test('a cashier is not narrowed even by a legacy assignment row', () async {
      // Cashiers were never meant to be assignable, but an old install can hold
      // `waiter_tables` rows for them. Those rows must not hide anything.
      final c = await createCashier();
      await db.assignTablesToWaiter(c.id, [1, 2]);
      expect(await seeAs(c), range(1, seeded));
    });

    test('a cashier is not narrowed by a legacy مەودا on their account',
        () async {
      // The owner UI only offers مەودا to captains, but a cashier row can still
      // carry one from an old install or a hand-edited database. A cashier must
      // see the whole floor regardless - this is the case that proves the role,
      // not the remembered account, decides the scope.
      final c = await createAccount('کاشێر', UserRole.cashier, from: 1, to: 5);
      expect(await seeAs(c), range(1, seeded));
    });

    test('a cashier is not narrowed when captains hold assignments', () async {
      final a = await createCaptain(from: 1, to: 10);
      final b = await createCaptain(from: 11, to: 20);
      final c = await createCashier();
      await db.assignTablesToWaiter(a.id, [1, 2, 3]);
      await db.assignTablesToWaiter(b.id, [11, 12, 13]);
      expect(await seeAs(c), range(1, seeded));
    });

    test('a cashier keeps seeing tables added after they signed in', () async {
      final c = await createCashier();
      expect((await seeAs(c)).length, seeded);

      // Added the way the app does it: a number, or a name typed by the user.
      // Ids past 100 so they cannot collide with the seeded tables.
      for (final input in ['201', '202', 'مێزی نوێی بەناو']) {
        expect(await notifier.addTableWithInput(input), isTrue,
            reason: 'adding "$input"');
      }
      final after = await seeAs(c);
      expect(after.length, seeded + 3);
      expect(after, containsAll(<int>[201, 202]));
    });
  });

  group('every other role sees every table', () {
    test('the owner sees the whole floor', () async {
      const owner = UserModel(
          id: 0, name: 'خاوەن سیستەم', pin: '', role: UserRole.owner);
      expect(await seeAs(owner), range(1, seeded));
    });

    test('an admin sees the whole floor', () async {
      final admin = await createAccount('ئادمێن', UserRole.admin);
      expect(await seeAs(admin), range(1, seeded));
    });

    test('a logged-out device sees the whole floor', () async {
      // The login screen and the background server both list tables, and must
      // not be narrowed by the last captain who used this device.
      final a = await createCaptain(from: 1, to: 10);
      await db.assignTablesToWaiter(a.id, [55]);
      expect(await seeAs(a), [...range(1, 10), 55]);
      expect(await seeAs(null), range(1, seeded));
    });
  });

  group('the scope follows the live role, never a remembered one', () {
    test('flipping between captain, cashier and logged-out flips both ways',
        () async {
      final a = await createCaptain(from: 1, to: 10);
      final c = await createCashier();
      await db.assignTablesToWaiter(a.id, [55]);
      final narrowed = [...range(1, 10), 55];
      final everything = range(1, seeded);

      for (var round = 0; round < 3; round++) {
        expect(await seeAs(a), narrowed, reason: 'round $round: captain');
        expect(await seeAs(c), everything, reason: 'round $round: cashier');
        expect(await seeAs(null), everything,
            reason: 'round $round: logged out');
      }
    });

    test('two captains in a row each get their own list', () async {
      final a = await createCaptain(from: 1, to: 10);
      final b = await createCaptain(from: 11, to: 20);
      expect(await seeAs(a), range(1, 10));
      expect(await seeAs(b), range(11, 20));
      expect(await seeAs(a), range(1, 10));
    });
  });

  group('a scope hides the rest of the floor', () {
    // The regression the owner reported: picking tables for a captain left the
    // whole unowned floor visible, so «تەنها ئەم مێزانە ببینێت» never held.
    test('picked tables alone limit a captain to exactly those tables',
        () async {
      final a = await createCaptain(); // no مەودا
      await db.assignTablesToWaiter(a.id, [3, 4, 7]);
      expect(await seeAs(a), [3, 4, 7],
          reason: 'picking tables is a scope: the other 97 must disappear');
    });

    // The other half: a مەودا must work even when the tables already belong to
    // another captain, which is the normal case once the defaults are seeded.
    test('a مەودا limits a captain even when other captains own the tables',
        () async {
      final b = await createCaptain(from: 11, to: 20);
      await db.updateUserRange(b.id, 11, 20); // b now owns 11..20
      final a = await createCaptain(from: 1, to: 10);
      expect(await seeAs(a), range(1, 10),
          reason: "the owner's مەودا must not depend on who owns the table");
    });

    test('reset hands the whole floor back', () async {
      final a = await createCaptain();
      await db.updateUserRange(a.id, 1, 10);
      await db.assignTablesToWaiter(a.id, [50]);
      expect(await seeAs(a), [...range(1, 10), 50]);

      await db.resetWaiterScope(a.id);
      expect(await seeAs(a), range(1, seeded),
          reason: 'normal again: every table, not a narrowed list');
    });
  });

  group('a scope change is felt on the captain device right away', () {
    /// Reads the floor WITHOUT re-applying the scope - the same path the
    /// registry-revision listener drives, so this is what the captain's next
    /// floor read really sees after the owner edits their account.
    List<int> liveFloor() {
      final tables =
          container.read(waiterProvider).asData?.value ?? const <TableModel>[];
      return tables.map((TableModel t) => t.id).toList()..sort();
    }

    test('a مەودا set while signed in narrows the captain without re-login',
        () async {
      final a = await createCaptain();
      expect(await seeAs(a), range(1, seeded));

      await db.updateUserRange(a.id, 1, 10);
      await notifier.refreshSilent();
      expect(liveFloor(), range(1, 10));
    });

    test('picked tables land on the next floor read', () async {
      final a = await createCaptain(from: 1, to: 10);
      expect(await seeAs(a), range(1, 10));

      await db.assignTablesToWaiter(a.id, [50, 51]);
      await notifier.refreshSilent();
      expect(liveFloor(), [...range(1, 10), 50, 51]);
    });

    test('a reset while signed in widens the captain back out', () async {
      final a = await createCaptain(from: 1, to: 10);
      expect(await seeAs(a), range(1, 10));

      await db.resetWaiterScope(a.id);
      await notifier.refreshSilent();
      expect(liveFloor(), range(1, seeded));
    });
  });
}
