// QA helper: remove test-fixture rows from a device database, using another
// device's copy as the authority for what actually exists.
//
//   dart run tool/qa_db_clean.dart <target.db> <authority.db>
//
// Why this exists. Running `flutter test -d <device>` writes fixtures straight
// into the live shop database on the handset - there was no guard - and the
// captain's copy of the dining room then permanently disagreed with the till
// about what a table cost. `LocalDatabase.init` now refuses its real path under
// a test, so it cannot happen again; this clears what it already did.
//
// An order row is only removed when the authority database has never heard of
// its id. Anything the till knows about is left alone, so this can never
// delete a real order - it can only delete rows that exist on exactly one
// device and are not that device's own business to have.
//
// The affected tables' `totalAmount` is then recomputed from the rows that
// survive, so the floor card and the bill agree again.
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stdout.writeln('usage: qa_db_clean <target.db> <authority.db>');
    exitCode = 2;
    return;
  }
  sqfliteFfiInit();
  final target = File(args[0]).absolute.path;
  final authority = File(args[1]).absolute.path;
  for (final f in [target, authority]) {
    if (!File(f).existsSync()) {
      stdout.writeln('MISSING $f');
      exitCode = 2;
      return;
    }
  }

  final authorityDb = await databaseFactoryFfiNoIsolate.openDatabase(
    authority,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  final knownIds = <String>{
    for (final r in await authorityDb.query('order_items', columns: ['id']))
      r['id'] as String,
  };
  await authorityDb.close();
  stdout.writeln('authority knows ${knownIds.length} order rows');

  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    target,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    // Fold the write-ahead log in first: the file this script rewrites has to
    // stand on its own, because the stale -wal gets removed on the way back to
    // the device.
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

    final rows = await db.query('order_items');
    final orphans = rows.where((r) => !knownIds.contains(r['id'])).toList();
    if (orphans.isEmpty) {
      stdout.writeln('nothing to clean - target already agrees with authority');
      return;
    }
    final byTable = <int, List<Map<String, Object?>>>{};
    for (final r in orphans) {
      byTable.putIfAbsent((r['tableId'] as int?) ?? 0, () => []).add(r);
    }
    for (final entry in byTable.entries) {
      stdout.writeln('table ${entry.key}: removing ${entry.value.length} row(s)');
      for (final r in entry.value) {
        stdout.writeln('   - ${r['id']} ${r['name']} ${r['price']}'
            ' x${r['quantity']} @ ${r['createdAt']} (${r['waiterName']})');
      }
    }

    await db.transaction((txn) async {
      for (final r in orphans) {
        await txn.delete('order_items', where: 'id = ?', whereArgs: [r['id']]);
      }
      // Only the touched tables are recomputed, from what is left on them.
      for (final tableId in byTable.keys) {
        if (tableId <= 0) continue;
        final sumRows = await txn.rawQuery(
          'SELECT IFNULL(SUM(price * quantity), 0) s FROM order_items WHERE tableId = ?',
          [tableId],
        );
        final sum = (sumRows.first['s'] as num?)?.toDouble() ?? 0;
        final before = await txn.query('tables',
            columns: ['totalAmount'], where: 'id = ?', whereArgs: [tableId]);
        final was = (before.isEmpty ? 0 : (before.first['totalAmount'] as num?)?.toDouble()) ?? 0;
        await txn.update('tables', {'totalAmount': sum.toDouble()},
            where: 'id = ?', whereArgs: [tableId]);
        stdout.writeln('table $tableId totalAmount ${was.toInt()} -> $sum');
      }
    });

    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    stdout.writeln('cleaned ${orphans.length} row(s) across ${byTable.length} table(s)');
  } finally {
    await db.close();
  }
}