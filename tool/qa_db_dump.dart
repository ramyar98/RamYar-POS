// QA helper: dump the interesting parts of a RAMYAR POS SQLite file.
//
//   dart run tool/qa_db_dump.dart <path-to.db> [table ...]
//
// Each table argument is `name`, or `name?col=value&col2=value2` to dump only
// the rows a question is actually about - without it every dump is capped and
// the rows that matter are the ones that got cut.
//
// Read-only, and it never creates the file: a QA run must not be able to
// manufacture a database that then gets mistaken for real shop data.
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final path = File(args.first).absolute.path;
  final wanted = args.length > 1 ? args.sublist(1) : const <String>[];
  final file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('MISSING $path');
    exitCode = 2;
    return;
  }
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
        .map((m) => m['name'] as String)
        .toList();
    stdout.writeln('== tables: ${tables.join(", ")}');
    for (final spec in wanted) {
      final parts = spec.split('?');
      final t = parts.first;
      if (!tables.contains(t)) {
        stdout.writeln('-- $t: NO SUCH TABLE');
        continue;
      }
      final where = <String>[];
      final whereArgs = <Object?>[];
      if (parts.length > 1) {
        for (final pair in parts[1].split('&')) {
          if (pair.isEmpty) continue;
          final kv = pair.split('=');
          where.add('"${kv.first}" = ?');
          whereArgs.add(kv.sublist(1).join('='));
        }
      }
      final whereSql = where.isEmpty ? '' : ' WHERE ${where.join(" AND ")}';
      final total =
          (await db.rawQuery('SELECT COUNT(*) c FROM "$t"')).first['c'] as int;
      final rows = await db.rawQuery(
        'SELECT * FROM "$t"$whereSql ORDER BY rowid LIMIT 400',
        whereArgs,
      );
      stdout.writeln('-- $t${whereSql.isEmpty ? '' : ' $whereSql'} '
          '(${rows.length} of $total rows)');
      final cols =
          (await db.rawQuery('PRAGMA table_info("$t")')).map((m) => m['name'] as String).toList();
      for (final r in rows) {
        final parts2 = <String>[];
        for (final c in cols) {
          final v = r[c];
          if (v == null) continue;
          final s = v.toString();
          if (s.isEmpty) continue;
          parts2.add('$c=$s');
        }
        stdout.writeln('   ${parts2.join(" | ")}');
      }
    }
  } finally {
    await db.close();
  }
}
