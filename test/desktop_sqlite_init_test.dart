import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ramyar_pos/core/desktop_sqlite.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
/// A release build on Windows used to open a window and stop: `sqflite` only
/// ships a platform channel for Android, iOS and macOS, so on desktop its
/// default database factory was still the plugin one and the first
/// `openDatabase()` raised `MissingPluginException` before the first frame was
/// ever drawn. Nothing in the unit tests noticed, because the test harness
/// selects the FFI implementation itself in its own setUpAll - so the bug only
/// ever appeared when the program was actually launched.
///
/// These tests pin the two halves of the fix: the factory is selected on
/// desktop, and a database opened afterwards really works against a file on
/// disk.
void main() {
  test('a desktop build selects the FFI SQLite implementation', () {
    // Deliberately not calling sqfliteFfiInit() first: the point is that the
    // app's own startup code is what puts the working factory in place.
    expect(needsDesktopDatabaseFactory, isTrue, reason: 'tests run on desktop');

    expect(ensureDesktopDatabaseFactory(), isTrue);
    expect(
      isDesktopDatabaseFactoryReady,
      isTrue,
      reason: 'a desktop build must not leave the global factory unset, which '
          'is what made a release build open a window and then stop',
    );
  });

  test('selecting the factory again changes nothing', () {
    expect(ensureDesktopDatabaseFactory(), isTrue);
    expect(ensureDesktopDatabaseFactory(), isTrue);
    expect(isDesktopDatabaseFactoryReady, isTrue);
  });

  test('a real database file can then be created, used and read back', () async {
    ensureDesktopDatabaseFactory();

    final dir = Directory.systemTemp.createTempSync('ramyar_sqlite_');
    final file = File('${dir.path}${Platform.pathSeparator}probe.db');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final db = LocalDatabase();
    // No inMemory flag: this is the path the real program takes, and it is what
    // a missing desktop factory used to break.
    await db.init(path: file.path);

    expect(db.isOpen, isTrue, reason: 'the database must actually be open');
    expect(file.existsSync(), isTrue, reason: 'and it must be on disk');

    await db.addUser('تاقیکار', '4455', UserRole.waiter);
    final back = await db.getUserByPin('4455');
    expect(back, isNotNull);
    expect(back!.name, 'تاقیکار');

    await db.resetForTesting();
  });
}
