import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';

/// A test may never write into the shop's real database.
///
/// This one exists because it already happened. `flutter test` also runs on a
/// device, and on a device [LocalDatabase]'s default path is the live
/// `ramyar_pos.db` of an installation that may be mid-service. A test that
/// reaches that branch by accident - a `LocalDatabase` built by a Riverpod
/// provider whose override was forgotten - writes its fixtures into the shop's
/// orders and then wipes them again in `resetForTesting`, so nothing throws and
/// nothing is logged.
///
/// What it looked like from the outside, on a live two-device QA run: the
/// captain's handset said table 5 was 56,000 and the till said 36,000. The
/// extra rows were `id = 'w1-1'`, `createdAt = 2026-01-01T10:00:00`,
/// `waiterName = 'وەیتەر 1'` - order ids that exist only in
/// `offline_sync_test.dart` and `sync_integration_test.dart`. Not a sync bug at
/// all: test fixtures, written into the shop's books by a test.
///
/// So the database now refuses to open its real path under a test process and
/// says why. This pins that refusal, because it is the only thing standing
/// between a forgotten override and a real shift's arithmetic.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  test('the guard is actually armed in this process', () {
    // If this ever stops being true the rest of this file proves nothing, and
    // it would fail for a reason that looks like the database's fault.
    expect(Platform.environment['FLUTTER_TEST'], 'true',
        reason: 'the guard keys off FLUTTER_TEST; if flutter_tools stops '
            'setting it the protection is silently gone');
  });

  test('init() with no arguments is refused, and says what to pass instead', () async {
    final db = LocalDatabase();
    await expectLater(
      db.init(),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        allOf(contains('real shop database'), contains('inMemory')),
      )),
    );
    expect(db.isOpen, isFalse,
        reason: 'and it must not have half-opened anything on the way out');
    expect(db.currentDbPath, isEmpty);
  });

  test('an explicit path is allowed - that is what the file tests use', () async {
    final tmp = Directory.systemTemp.createTempSync('ramyar_pos_init_guard');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final db = LocalDatabase();
    await db.init(path: '${tmp.path}${Platform.pathSeparator}x.db');
    expect(db.isOpen, isTrue);
    await db.resetForTesting();
  });

  test('in-memory is allowed, which is what every widget test uses', () async {
    final db = LocalDatabase();
    await db.init(inMemory: true);
    expect(db.isOpen, isTrue);
    await db.resetForTesting();
  });
}