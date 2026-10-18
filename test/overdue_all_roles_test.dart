import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';

/// The three colours, driven by the table's state, on every role's screen:
///
///  * empty  - the neutral card;
///  * occupied (a customer sits down) - green;
///  * billRequested (the bill was printed) - blue IMMEDIATELY, and the
///    TEN-MINUTE clock starts at that print;
///  * overdue (ten minutes after the print with no settle) - red.
///
/// The window is 10 MINUTES, per the shop's rule, and it is counted in SECONDS -
/// 600 of them. The blue spell is a working colour: the bill is out with the
/// customer and the table is being paid. It began as `billOverdueMinutes = 10`
/// compared with `inMinutes`, which truncates and put the red anywhere from ten
/// to eleven minutes after the print.
///
/// Every role reads the same tables table, so the colour changes made by the
/// database are what every role's home page shows - the tests below drive the
/// database through the exact calls the roles' buttons make.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  group('the three colours', () {
    test('a customer sits down - the table turns green (occupied)', () async {
      await db.occupyTable(1, '101', guestCount: 2);
      final t = await db.getTable(1);
      expect(t!.status, TableStatus.occupied);
      expect(t.seatedTime, isNotEmpty,
          reason: 'the bill clock is measured from the print, not from seating');
    });

    test('printing the bill turns the table blue (billRequested) immediately',
        () async {
      await db.occupyTable(1, '101', guestCount: 2);
      // What the cashier's چاپکردن button does.
      await db.markAsPrinted(1);

      final t = await db.getTable(1);
      expect(t!.status, TableStatus.billRequested, reason: 'blue right away');
      expect(t.printedAt, isNotEmpty,
          reason: 'the ten-minute clock starts at the print');
    });

    test('a captain asking for the bill ALSO turns the table blue at once',
        () async {
      await db.occupyTable(2, '101', guestCount: 3);
      // What the captain's ناردن بۆ کاشێر button does.
      await db.requestBill(2);

      final t = await db.getTable(2);
      expect(t!.status, TableStatus.billRequested);
      expect(t.sentToCashier, isTrue);
      expect(t.printedAt, isNotEmpty);
    });

    test('10 minutes after the print with no settle - the table turns red',
        () async {
      await db.occupyTable(1, '101', guestCount: 2);
      await db.markAsPrinted(1);

      // Wind the print time back past the window.
      final past = DateTime.now()
          .subtract(const Duration(minutes: 11))
          .toIso8601String();
      await db.db
          .update('tables', {'printedAt': past}, where: 'id = ?', whereArgs: [1]);

      await db.checkOverdueTables();

      final t = await db.getTable(1);
      expect(t!.status, TableStatus.overdue,
          reason: 'red once the ten minutes are up');
    });

    test('the window is ten minutes, written in seconds so it cannot truncate',
        () async {
      // The bug this pins: the window was once `billOverdueMinutes = 10`
      // compared with `inMinutes`, and `inMinutes` truncates - so a bill could
      // turn anywhere from ten to eleven minutes after the print. Ten minutes
      // written as 600 seconds is exact.
      await db.occupyTable(1, '101');
      await db.markAsPrinted(1);

      final elevenMinutesAgo = DateTime.now()
          .subtract(const Duration(minutes: 11))
          .toIso8601String();
      await db.db.update('tables', {'printedAt': elevenMinutesAgo},
          where: 'id = ?', whereArgs: [1]);

      await db.checkOverdueTables();

      expect((await db.getTable(1))!.status, TableStatus.overdue,
          reason: 'eleven minutes is past a ten minute window');
      expect(LocalDatabase.billOverdueSeconds, 600,
          reason: 'the shop rule is ten minutes, and the constant is in seconds');
      expect(LocalDatabase.billOverdueSeconds % 60, 0,
          reason: 'a whole number of minutes, so no fraction of the window is '
              'lost to truncation');
    });

    test('inside the window the table is still blue, not red', () async {
      await db.occupyTable(1, '101');
      await db.markAsPrinted(1);

      // Nine and a half minutes. Under the ten-SECOND spell this table would
      // have been red long ago; the blue spell is what this pins.
      final almost = DateTime.now()
          .subtract(const Duration(seconds: 570))
          .toIso8601String();
      await db.db.update('tables', {'printedAt': almost}, where: 'id = ?',
          whereArgs: [1]);

      await db.checkOverdueTables();
      expect((await db.getTable(1))!.status, TableStatus.billRequested,
          reason: 'nine and a half minutes in is still inside the window');
    });

    test('settling the bill clears the colour - the table is empty again',
        () async {
      await db.occupyTable(1, '101', guestCount: 2);
      await db.markAsPrinted(1);

      // What واسڵکردن does.
      await db.settleTable(1, 25000, 0, 0, 4);

      final t = await db.getTable(1);
      expect(t!.status, TableStatus.empty,
          reason: 'settling frees the table whatever colour it was');
    });

    test('an occupied table never goes red - only a printed bill can', () async {
      await db.occupyTable(1, '101', guestCount: 2);
      // Sit for a very long time.
      final longAgo = DateTime.now()
          .subtract(const Duration(hours: 3))
          .toIso8601String();
      await db.db
          .update('tables', {'seatedTime': longAgo}, where: 'id = ?', whereArgs: [1]);

      await db.checkOverdueTables();

      expect((await db.getTable(1))!.status, TableStatus.occupied,
          reason: 'only billRequested tables carry the ten-minute clock');
    });

    test('a table asked about but never printed carries no clock', () async {
      // The countdown belongs to the print, so a request with no printedAt must
      // never be swept into red - otherwise a captain's unanswered request would
      // flag the table red for a bill that was never handed over.
      await db.occupyTable(1, '101');
      await db.db.update('tables',
          {'status': TableStatus.billRequested.index, 'printedAt': ''},
          where: 'id = ?', whereArgs: [1]);

      final longAgo = DateTime.now()
          .subtract(const Duration(hours: 3))
          .toIso8601String();
      await db.db
          .update('tables', {'seatedTime': longAgo}, where: 'id = ?', whereArgs: [1]);

      await db.checkOverdueTables();

      expect((await db.getTable(1))!.status, TableStatus.billRequested,
          reason: 'no print means no clock, however old the request');
    });
  });

  group('the same floor for every role', () {
    test('the overdue flag the timer sets is visible through the same read',
        () async {
      // Whatever role's screen is open, it reads the same tables table through
      // getAllTables. A red table on the cashier must be red on the admin and
      // the captain's grid too - which is guaranteed by the state being in the
      // database, not in one page's local list.
      await db.occupyTable(1, '101');
      await db.markAsPrinted(1);
      final past = DateTime.now()
          .subtract(const Duration(minutes: 12))
          .toIso8601String();
      await db.db
          .update('tables', {'printedAt': past}, where: 'id = ?', whereArgs: [1]);

      await db.checkOverdueTables();

      final floor = await db.getAllTables();
      final t1 = floor.firstWhere((t) => t.id == 1);
      expect(t1.status, TableStatus.overdue,
          reason: 'every role reads this same state and shows the same red');
    });

    test('several printed bills can go red in one sweep', () async {
      for (final id in [1, 2, 3]) {
        await db.occupyTable(id, '101');
        await db.markAsPrinted(id);
        final past = DateTime.now()
            .subtract(const Duration(minutes: 15))
            .toIso8601String();
        await db.db.update('tables', {'printedAt': past},
            where: 'id = ?', whereArgs: [id]);
      }
      await db.occupyTable(4, '101');
      await db.markAsPrinted(4); // fresh print - stays blue

      await db.checkOverdueTables();

      for (final id in [1, 2, 3]) {
        expect((await db.getTable(id))!.status, TableStatus.overdue);
      }
      expect((await db.getTable(4))!.status, TableStatus.billRequested);
    });
  });
}
