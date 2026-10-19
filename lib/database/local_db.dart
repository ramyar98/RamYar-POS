import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/app_log.dart';
import '../core/app_prefs.dart';
import '../models/cancelled_item_model.dart';
import '../models/debt_model.dart';
import '../models/delivery_company_model.dart';
import '../models/dollar_rate_model.dart';
import '../models/order_delivery_model.dart';
import '../models/order_model.dart';
import '../models/printer_model.dart';
import '../models/receipt_design_model.dart';
import '../models/remaining_table_model.dart';
import '../models/settlement_model.dart';
import '../models/table_lock_model.dart';
import '../models/table_model.dart';
import '../models/table_notification_model.dart';
import '../models/user_model.dart';
import '../services/owner_access.dart';

/// The dining room is always these tables, ids 1..100. Renaming a table is a
/// label change; the id (and so the table itself) stays. A delete is repaired
/// automatically - see [LocalDatabase.ensureStandardTables].
const int kStandardTableCount = 100;

final localDbProvider = Provider<LocalDatabase>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

class LocalDatabase {
  LocalDatabase();

  Database? _db;
  String _dbPath = '';

  void Function(String action, Map<String, dynamic> data)? onMutation;
  int remoteMutationDepth = 0;

  /// Default delivery companies shipped with a fresh install; more can be
  /// added later from the cashier delivery panel (e.g. "Toters").
  static const List<String> _defaultDeliveryCompanies = [
    'تەلەبات',
    'لیزۆ',
    'وادێ',
  ];

  /// Bumped on every user-registry mutation so live views (e.g. the owner
  /// page) can refresh immediately, including changes synced in remotely.
  final ValueNotifier<int> usersRevision = ValueNotifier<int>(0);

  void _bumpUsers() => usersRevision.value += 1;

  /// Bumped on every delivery-company registry mutation (add / delete, local
  /// or synced in remotely) so the cashier delivery panel refreshes live.
  final ValueNotifier<int> deliveryCompaniesRevision = ValueNotifier<int>(0);

  void _bumpDeliveryCompanies() => deliveryCompaniesRevision.value += 1;

  /// Bumped on every food-menu mutation (category or item - add / edit /
  /// delete, local or synced in remotely). Open menu screens (waiter table
  /// page, cashier settlement page, admin menu manager) listen and refresh
  /// immediately, so a food item added by the admin shows up on EVERY device
  /// live - and keeps showing once a device reconnects after being offline.
  final ValueNotifier<int> foodMenuRevision = ValueNotifier<int>(0);

  void _bumpFoodMenu() => foodMenuRevision.value += 1;

  /// Bumped on every cashier-shift change (start / end, local or synced in
  /// remotely) so the admin shifts list and open shift details can refresh as
  /// soon as a remote cashier device starts or ends a shift.
  final ValueNotifier<int> shiftsRevision = ValueNotifier<int>(0);

  void _bumpShifts() => shiftsRevision.value += 1;

  /// Bumped whenever the admin's dollar rate changes - on this device or synced
  /// in from the device that saved it - so every screen already showing the rate
  /// (the cashier's order tab, the rate editor) updates the moment it moves,
  /// without anyone having to reopen the page.
  final ValueNotifier<int> dollarRateRevision = ValueNotifier<int>(0);

  void _bumpDollarRate() => dollarRateRevision.value += 1;

  /// Bumped whenever the receipt design changes - on this device or synced in
  /// from the device that saved it - so the design screen's preview and any open
  /// print path re-read the new layout without a restart.
  final ValueNotifier<int> receiptDesignRevision = ValueNotifier<int>(0);

  void _bumpReceiptDesign() => receiptDesignRevision.value += 1;

  /// Bumped whenever anything about a table's money or its items changes - a
  /// captain ringing items in, the cashier adding something at the table,
  /// cancelling, transferring, merging, or one of those arriving over the link
  /// from another device.
  ///
  /// This is the reason a captain's order used to be invisible on the cashier's
  /// screen. The rows landed in the database and the table total was correct, but
  /// the screens that show them (`tableOrdersProvider`, `tableDetailProvider`)
  /// were caches that nothing ever invalidated once a change came from another
  /// device - so the cashier saw the pre-order list and a stale total until they
  /// restarted the app. Every write that changes items or a total bumps this.
  final ValueNotifier<int> orderRevision = ValueNotifier<int>(0);

  void _bumpOrders() => orderRevision.value += 1;

  /// Fires with a table id when a captain is thrown off that table, whether the
  /// throw happened here or arrived over the link from the cashier's device.
  /// The table page listens so it can drop the captain out of the table the
  /// moment it happens instead of letting them keep working a table they no
  /// longer have.
  final StreamController<int> _tableEjections =
      StreamController<int>.broadcast();

  Stream<int> get tableEjections => _tableEjections.stream;

  void emitTableEjection(int tableId) {
    if (!_tableEjections.isClosed) _tableEjections.add(tableId);
  }

  void _emitMutation(String action, Map<String, dynamic> data) {
    if (remoteMutationDepth != 0) return;
    // One concise line per mutation instead of two. The old pair ("_emitMutation
    // …" plus a second "OFFLINE - queueing mutation …") wrote every local change
    // to the console twice, drowning the sync/discovery traces a developer
    // actually needs. `appLog` still keeps it debug-only.
    final isOnline = onMutation != null;
    final tableId = data['tableId'];
    final where = tableId == null ? '' : ' table=$tableId';
    if (isOnline) {
      onMutation?.call(action, data);
      appLog('[DB] $action$where → sent online');
    } else {
      appLog('[DB] $action$where → queued offline');
      addPendingSync(action, Map<String, dynamic>.from(data));
    }
  }

  Database get db {
    if (_db == null) throw StateError('Database not initialized');
    return _db!;
  }

  String get currentDbPath => _dbPath;

  /// Whether the database is open and can be queried.
  ///
  /// Widgets ask before reading: a page can still be on screen when the
  /// database is being closed (an admin reset, a restore, shutdown), and a
  /// live-update listener firing at that moment would throw out of the listener
  /// where nothing can catch it.
  bool get isOpen => _db != null;

  /// Current on-disk schema version. Bumped whenever [_createTables] or
  /// [_migrate] gain a table, a column or an index.
  static const int schemaVersion = 45;

  Future<void> init({bool inMemory = false, String? path}) async {
    if (_db != null) return;
    // A test may never fall through to the shop's real database file.
    //
    // `flutter test` runs on the host *and* on a device, and on a device the
    // default path is the live `ramyar_pos.db` of an installation that may be
    // mid-service. A test that reaches this branch by accident - typically a
    // `LocalDatabase` built by a Riverpod provider whose override was forgotten -
    // writes its fixtures into the shop's orders and then deletes them on
    // `resetForTesting`, so the failure is silent and the damage shows up later
    // as a captain and the cashier disagreeing about what a table cost. Failing
    // here instead costs the author five minutes; the other way costs a real
    // shift its books. Callers that genuinely want a file pass `path:`.
    if (!inMemory &&
        path == null &&
        Platform.environment['FLUTTER_TEST'] == 'true') {
      throw StateError(
        'LocalDatabase.init() would open the real shop database during a test. '
        "Pass init(inMemory: true), or init(path: <temp file>).",
      );
    }
    if (inMemory) {
      _dbPath = inMemoryDatabasePath;
    } else if (path != null) {
      _dbPath = path;
    } else {
      final dbDir = await _resolveDesktopDataDir();
      final newPath = p.join(dbDir, 'ramyar_pos.db');
      // The database used to sit in a folder relative to the *working*
      // directory, which moves depending on how the app was started. Carry the
      // existing data across once so nothing is left behind.
      final previous = p.join(await getDatabasesPath(), 'ramyar_pos.db');
      if (!await File(newPath).exists() && await File(previous).exists()) {
        try {
          await File(previous).rename(newPath);
        } catch (_) {}
      }
      final legacyPath = p.join(dbDir, 'biablo.db');
      // One-time migration: carry existing local data over to the renamed DB.
      if (!await File(newPath).exists() && await File(legacyPath).exists()) {
        try {
          await File(legacyPath).rename(newPath);
        } catch (_) {}
      }
      _dbPath = newPath;
    }
    _db = await _openDb(_dbPath);
    // The dining room is always tables 1..100. A rename or a delete must never
    // be able to shrink the floor permanently: whatever happened on a previous
    // run - a cashier typing over a table's name, a delete, an old database
    // carried across - is repaired here before the first screen opens.
    await ensureStandardTables();
  }

  /// Opens the app database under the durability policy a POS needs.
  ///
  /// WAL tolerates a process crash mid-write, and FULL forces an fsync at every
  /// COMMIT - so an order the captain saw as saved is on the platter before the
  /// app reports it saved, and a power cut cannot take it back. Every open path
  /// (normal, in-memory test, backup reopen) goes through here, so the policy
  /// can never drift between them.
  Future<Database> _openDb(
    String path, {
    OnDatabaseVersionChangeFn? onDowngrade,
  }) {
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _configureDb,
      onOpen: _prepareDb,
      onCreate: _createTables,
      onUpgrade: _migrate,
      onDowngrade: onDowngrade,
    );
  }

  static Future<void> _configureDb(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _prepareDb(Database db) async {
    // WAL first: the journal mode that survives a crash in the middle of a
    // write instead of leaving a rollback journal to recover from.
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
    } catch (_) {}
    // FULL: fsync at every COMMIT. A little slower than NORMAL, but a committed
    // order is durable before it is acknowledged.
    try {
      await db.execute('PRAGMA synchronous = FULL');
    } catch (_) {}
    // Absorb the brief contention between a UI write and the sync write instead
    // of failing one of them with "database is locked".
    try {
      await db.execute('PRAGMA busy_timeout = 5000');
    } catch (_) {}
    // Belt and braces: an already-open database picks the sync indexes up here
    // even if it was created before they existed.
    try {
      await _createSyncIndexes(db);
    } catch (_) {}
  }

  /// Makes sure the dining room always contains tables 1..[kStandardTableCount].
  ///
  /// The room is identified by ID, not by name: id N is the Nth place in the
  /// room, and the name is only the label stuck on that place. So:
  ///
  ///  * a row with a missing id (a delete, an old database with a hole) is
  ///    re-created as a fresh, empty "مێز N";
  ///  * a renamed row keeps its id and its custom label ("مێزی حەمە") - it
  ///    stays exactly as the shop made it. The grid may then show both the
  ///    custom label AND the standard "مێز N" beside it, because the room is
  ///    allowed to be bigger than 100 labels; what must never happen is the
  ///    standard PLACE going missing.
  ///
  /// Delivery slots live in the same table under ids >= [deliverySlotBase];
  /// they are not part of the dining room and are never touched.
  Future<void> ensureStandardTables() async {
    if (_db == null) return;
    try {
      final rows = await _db!.query('tables', columns: ['id']);
      final presentIds = rows.map((m) => m['id'] as int).toSet();
      var restored = 0;
      for (int i = 1; i <= kStandardTableCount; i++) {
        if (presentIds.contains(i)) continue;
        await _db!.insert('tables', {
          'id': i,
          'name': standardTableName(i),
          'status': TableStatus.empty.index,
          'seatedTime': '',
          'waiterId': '',
          'totalAmount': 0.0,
          'guestCount': 0,
          'sentToCashier': 0,
          'note': '',
          'createdBy': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        restored++;
      }
      if (restored > 0) {
        _bumpOrders();
        appLog(
          '[DB] ensureStandardTables restored $restored missing table(s)',
        );
      }
    } catch (e) {
      // A failure here must not keep the app from starting; the tables screen
      // degrades to whatever rows exist instead of crashing on boot.
      appLog('[DB] ensureStandardTables failed: $e');
    }
  }

  /// Where the database file lives on a desktop machine.
  ///
  /// `sqflite` resolves its desktop path relative to the *working* directory,
  /// so the same program could end up with a different database - or with no
  /// database at all, and no explanation - depending on whether it was opened by
  /// double-clicking the exe, from a shortcut, or by a script. Anchoring the
  /// folder to the executable instead means the data always travels with the
  /// program, and two copies of the app in two folders stay two separate shops.
  Future<String> _resolveDesktopDataDir() async {
    if (kIsWeb) return getDatabasesPath();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final exeDir = p.dirname(Platform.resolvedExecutable);
        final dir = Directory(p.join(exeDir, 'data', 'databases'));
        await dir.create(recursive: true);
        // Prove it is writable before committing to it: a program folder under
        // Program Files is not.
        final probe = File(p.join(dir.path, '.writable'));
        await probe.writeAsString('');
        await probe.delete();
        return dir.path;
      } catch (_) {
        // Not writable here - fall back to the platform default below.
      }
    }
    return getDatabasesPath();
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    await _db?.close();
    _db = null;
    _dbPath = '';
    onMutation = null;
    remoteMutationDepth = 0;
    usersRevision.value = 0;
    deliveryCompaniesRevision.value = 0;
    foodMenuRevision.value = 0;
    shiftsRevision.value = 0;
    dollarRateRevision.value = 0;
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tables (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        seatedTime TEXT DEFAULT '',
        waiterId TEXT DEFAULT '',
        totalAmount REAL DEFAULT 0.0,
        guestCount INTEGER DEFAULT 0,
        sentToCashier INTEGER DEFAULT 0,
        printedAt TEXT DEFAULT '',
        note TEXT DEFAULT '',
        noteUpdatedAt TEXT DEFAULT '',
        createdBy INTEGER DEFAULT 0,
        openedBy INTEGER DEFAULT 0,
        isDelivery INTEGER DEFAULT 0,
        deliveryCompanyId INTEGER DEFAULT 0,
        deliverySlot INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id TEXT NOT NULL,
        tableId INTEGER NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        category TEXT DEFAULT '',
        createdAt TEXT NOT NULL,
        waiterName TEXT DEFAULT '',
        waiterRole INTEGER DEFAULT -1,
        PRIMARY KEY (id, tableId)
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        pin TEXT NOT NULL UNIQUE,
        role INTEGER NOT NULL,
        rangeStart INTEGER,
        rangeEnd INTEGER,
        accessCode TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tableId INTEGER NOT NULL,
        tableName TEXT NOT NULL,
        amount REAL NOT NULL,
        reason TEXT DEFAULT '',
        createdAt TEXT NOT NULL,
        createdBy INTEGER NOT NULL,
        shiftId INTEGER DEFAULT 0,
        itemsJson TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE printer_configs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        portName TEXT NOT NULL,
        printerType INTEGER NOT NULL,
        isDefault INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE category_printer_mappings (
        category TEXT NOT NULL PRIMARY KEY,
        printerConfigId INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE item_printer_overrides (
        itemName TEXT NOT NULL PRIMARY KEY,
        printerConfigId INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE item_printer_assignments (
        itemName TEXT NOT NULL,
        printerType INTEGER NOT NULL,
        PRIMARY KEY (itemName, printerType)
      )
    ''');

    await db.execute('''
      CREATE TABLE settled_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tableId INTEGER NOT NULL,
        tableName TEXT NOT NULL,
        totalAmount REAL NOT NULL,
        discountPercent REAL DEFAULT 0,
        discountAmount REAL DEFAULT 0,
        settledAt TEXT NOT NULL,
        settledBy INTEGER NOT NULL,
        shiftId INTEGER DEFAULT 0,
        seatedAt TEXT DEFAULT '',
        paymentMethod TEXT DEFAULT 'cash',
        waiterId TEXT DEFAULT '',
        note TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE settled_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        settledOrderId INTEGER NOT NULL,
        itemName TEXT NOT NULL,
        itemPrice REAL NOT NULL,
        quantity INTEGER NOT NULL,
        category TEXT DEFAULT '',
        waiterName TEXT DEFAULT '',
        waiterRole INTEGER DEFAULT -1
      )
    ''');

    await db.execute('''
      CREATE TABLE cashier_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cashierId INTEGER NOT NULL,
        cashierName TEXT NOT NULL,
        startedAt TEXT NOT NULL,
        endedAt TEXT DEFAULT '',
        totalCollected REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itemName TEXT NOT NULL,
        price REAL NOT NULL,
        purchasedAt TEXT NOT NULL,
        purchasedBy INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE refunds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tableId INTEGER NOT NULL,
        itemName TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        refundedAt TEXT NOT NULL,
        refundedBy INTEGER NOT NULL,
        shiftId INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE cashier_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shiftId INTEGER NOT NULL,
        itemName TEXT NOT NULL,
        price REAL NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS shift_remaining_tables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shiftId INTEGER NOT NULL,
        shiftCashierId INTEGER DEFAULT 0,
        shiftStartedAt TEXT DEFAULT '',
        tableId INTEGER NOT NULL,
        tableName TEXT NOT NULL,
        guestCount INTEGER DEFAULT 0,
        seatedAt TEXT DEFAULT '',
        waiterId TEXT DEFAULT '',
        waiterName TEXT DEFAULT '',
        note TEXT DEFAULT '',
        totalAmount REAL DEFAULT 0,
        itemsJson TEXT DEFAULT '',
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cancelled_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shiftId INTEGER DEFAULT 0,
        shiftCashierId INTEGER DEFAULT 0,
        shiftStartedAt TEXT DEFAULT '',
        tableId INTEGER NOT NULL,
        tableName TEXT NOT NULL,
        itemName TEXT NOT NULL,
        itemPrice REAL NOT NULL,
        quantity INTEGER DEFAULT 1,
        category TEXT DEFAULT '',
        cancelledAt TEXT NOT NULL,
        cancelledBy INTEGER DEFAULT 0,
        cancelledByName TEXT DEFAULT '',
        requestedByName TEXT DEFAULT '',
        requestedAt TEXT DEFAULT '',
        requestedByRole INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending',
        servedAt TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS table_notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tableId INTEGER NOT NULL,
        openedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE food_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT DEFAULT 'restaurant',
        section TEXT DEFAULT '',
        sortOrder INTEGER DEFAULT 0,
        name_ar TEXT DEFAULT '',
        name_fa TEXT DEFAULT '',
        name_en TEXT DEFAULT '',
        name_tr TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS waiter_tables (
        waiterId INTEGER NOT NULL,
        tableId INTEGER NOT NULL,
        PRIMARY KEY (waiterId, tableId)
      )
    ''');

    await db.execute('''
      CREATE TABLE food_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        category TEXT NOT NULL,
        imageUrl TEXT DEFAULT '',
        sortOrder INTEGER DEFAULT 0,
        name_ar TEXT DEFAULT '',
        name_fa TEXT DEFAULT '',
        name_en TEXT DEFAULT '',
        name_tr TEXT DEFAULT ''
      )
    ''');

    await _seedMenuData(db);

    for (int i = 1; i <= 100; i++) {
      await db.insert('tables', {
        'id': i,
        'name': 'مێز $i',
        'status': TableStatus.empty.index,
        'seatedTime': '',
        'waiterId': '',
        'totalAmount': 0.0,
        'guestCount': 0,
        'sentToCashier': 0,
        'createdBy': 0,
      });
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_sync (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        data TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        status INTEGER DEFAULT 0,
        batchId TEXT,
        retryCount INTEGER DEFAULT 0,
        lastError TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS print_jobs (
        batchId TEXT NOT NULL,
        printerType INTEGER NOT NULL,
        tableId INTEGER NOT NULL,
        payload TEXT NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        attempts INTEGER NOT NULL DEFAULT 0,
        lastError TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        PRIMARY KEY (batchId, printerType)
      )
    ''');

    await _createSyncIndexes(db);

    await db.execute('''
      CREATE TABLE order_delivery (
        tableId INTEGER PRIMARY KEY,
        sentAt TEXT NOT NULL,
        arrivedAt TEXT DEFAULT '',
        printedAt TEXT DEFAULT '',
        printFailedAt TEXT DEFAULT '',
        rejected INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS table_locks (
        tableId INTEGER PRIMARY KEY,
        deviceId TEXT NOT NULL,
        userId INTEGER NOT NULL,
        userName TEXT NOT NULL,
        role TEXT NOT NULL,
        lockedAt TEXT NOT NULL,
        heartbeat TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_companies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sortOrder INTEGER DEFAULT 0,
        slotCount INTEGER NOT NULL DEFAULT 50
      )
    ''');

    for (var i = 0; i < _defaultDeliveryCompanies.length; i++) {
      await db.insert('delivery_companies', {
        'name': _defaultDeliveryCompanies[i],
        'sortOrder': i,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await _createShopSettingsTable(db);
  }

  /// Indexes the sync paths rely on: a flush scans `pending_sync` by status and
  /// a table's items are summed by `tableId`, and both happen on the hot path
  /// of every order.
  ///
  /// The partial unique index on `batchId` makes a queued order idempotent at
  /// the database level too - a double-tap or a retried enqueue can never create
  /// two copies of the same batch.
  static Future<void> _createSyncIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_status ON pending_sync(status, createdAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_items_table ON order_items(tableId)',
    );
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_batch ON pending_sync(batchId) WHERE batchId IS NOT NULL',
      );
    } catch (_) {
      // A very old system SQLite can refuse the partial index; the server-side
      // item-UUID dedup still prevents a double-post.
    }
    // Everything below keeps a cheap read cheap as the shop's history grows.
    //
    // `tables.status` is read once a SECOND by the bill clock (and the notify
    // bell joins tables the same way), so leaving it unindexed is the one query
    // that runs forever - on every screen, on a slow CPU, for the whole app's
    // life. A single-column index makes it a lookup instead of a scan.
    //
    // The settled_order*/cancelled_items/refunds indexes back the shift
    // reports: as the shop's history grows these tables get large, and every
    // report row would otherwise be a scan. Each is wrapped so an ancient
    // system SQLite can skip one it does not understand without breaking open.
    for (final statement in const [
      'CREATE INDEX IF NOT EXISTS idx_tables_status ON tables(status)',
      'CREATE INDEX IF NOT EXISTS idx_settled_shift ON settled_orders(shiftId)',
      'CREATE INDEX IF NOT EXISTS idx_settled_table ON settled_orders(tableId)',
      'CREATE INDEX IF NOT EXISTS idx_settled_items_order ON settled_order_items(settledOrderId)',
      'CREATE INDEX IF NOT EXISTS idx_cancelled_shift ON cancelled_items(shiftId)',
      'CREATE INDEX IF NOT EXISTS idx_refunds_shift ON refunds(shiftId)',
      'CREATE INDEX IF NOT EXISTS idx_expenses_shift ON cashier_expenses(shiftId)',
      'CREATE INDEX IF NOT EXISTS idx_remaining_shift ON shift_remaining_tables(shiftId)',
      'CREATE INDEX IF NOT EXISTS idx_debts_table ON debts(tableId)',
      'CREATE INDEX IF NOT EXISTS idx_notifications_table ON table_notifications(tableId)',
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {
        // A handful of extra indexes is never worth failing to open the shop.
      }
    }
  }

  /// Shop-wide settings as plain key/value text.
  ///
  /// A table rather than shared preferences on purpose: the dollar rate is set
  /// by the admin on one device and has to appear on every cashier's screen, so
  /// it has to travel through the same sync path as the menu and the shifts. A
  /// device-local preference would leave every cashier reading yesterday's rate.
  static Future<void> _createShopSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shop_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updatedAt TEXT DEFAULT ''
      )
    ''');
  }

  Future<void> _seedMenuData(Database db) async {
    final cats = [
      'بەرگەر',
      'پیتزا',
      'مریشک',
      'برنج',
      'کەباب',
      'ماسی',
      'شیرینی',
      'خواردنەوە',
    ];
    final catIcons = [
      'lunch_dining',
      'local_pizza',
      'set_meal',
      'rice_bowl',
      'kebab_dining',
      'set_meal',
      'cake',
      'local_drink',
    ];
    final catSections = [
      'گەرمی',
      'گەرمی',
      'گەرمی',
      'گەرمی',
      'گەرمی',
      'گەرمی',
      'شیرینی',
      'ساردی',
    ];
    for (int i = 0; i < cats.length; i++) {
      await db.insert('food_categories', {
        'name': cats[i],
        'icon': catIcons[i],
        'section': catSections[i],
        'sortOrder': i,
      });
    }
    final items = [
      _mi('بەرگەری گۆشتی', 5000, 'بەرگەر'),
      _mi('بەرگەری مریشک', 6000, 'بەرگەر'),
      _mi('بەرگەری پەنەر', 7000, 'بەرگەر'),
      _mi('بەرگەری دەبل', 9000, 'بەرگەر'),
      _mi('بەرگەری سپێشاڵ', 12000, 'بەرگەر'),
      _mi('پیتزای مۆزاریلا', 8000, 'پیتزا'),
      _mi('پیتزای پەپەرۆنی', 10000, 'پیتزا'),
      _mi('پیتزای سەوزە', 9000, 'پیتزا'),
      _mi('پیتزای مریشک', 12000, 'پیتزا'),
      _mi('پیتزای مەرگیڕیتا', 11000, 'پیتزا'),
      _mi('مریشکی برژاو', 8000, 'مریشک'),
      _mi('مریشکی کریسپی', 10000, 'مریشک'),
      _mi('باڵی مریشک', 7000, 'مریشک'),
      _mi('مریشکی فەجر', 15000, 'مریشک'),
      _mi('مریشکی ساتەی', 12000, 'مریشک'),
      _mi('برنجی بەرز', 5000, 'برنج'),
      _mi('برنجی سەوزە', 6000, 'برنج'),
      _mi('برنجی لەحم', 9000, 'برنج'),
      _mi('کەبابی کۆی', 10000, 'کەباب'),
      _mi('کەبابی تیکە', 12000, 'کەباب'),
      _mi('کەبابی شیش', 8000, 'کەباب'),
      _mi('کەبابی دۆنەر', 15000, 'کەباب'),
      _mi('کەبابی کوبدە', 7000, 'کەباب'),
      _mi('ماسی سورخاو', 15000, 'ماسی'),
      _mi('ماسی سالمۆن', 25000, 'ماسی'),
      _mi('ماسی قەرەزا', 12000, 'ماسی'),
      _mi('ماسی بەرگەر', 10000, 'ماسی'),
      _mi('کەیک چۆکەلات', 5000, 'شیرینی'),
      _mi('شیرینی دۆنات', 5000, 'شیرینی'),
      _mi('ئایس کریم', 6000, 'شیرینی'),
      _mi('پانکەیک', 7000, 'شیرینی'),
      _mi('کونافە', 8000, 'شیرینی'),
      _mi('کۆکاکۆلا', 5000, 'خواردنەوە'),
      _mi('فانتا', 5000, 'خواردنەوە'),
      _mi('سپرایت', 5000, 'خواردنەوە'),
      _mi('ئاو', 2500, 'خواردنەوە'),
      _mi('چای کاکە ڕەش', 3000, 'خواردنەوە'),
      _mi('چای سەوز', 3000, 'خواردنەوە'),
      _mi('کاپوچینۆ', 6000, 'خواردنەوە'),
      _mi('عەسیر', 7000, 'خواردنەوە'),
      _mi('ماهیتی کاڵد', 5000, 'خواردنەوە'),
    ];
    for (final item in items) {
      await db.insert('food_items', item);
    }
  }

  final List<String> _foodIcons = [
    'lunch_dining',
    'local_pizza',
    'set_meal',
    'rice_bowl',
    'kebab_dining',
    'cake',
    'local_drink',
    'egg',
    'bakery_dining',
    'ramen_dining',
    'tapas',
    'icecream',
    'coffee',
    'water_drop',
    'soup_kitchen',
    'fastfood',
  ];

  Map<String, dynamic> _mi(String name, double price, String category) => {
    'name': name,
    'price': price,
    'category': category,
    'sortOrder': 0,
    'imageUrl': _foodIcons[(name.length + price.toInt()) % _foodIcons.length],
  };

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE tables ADD COLUMN guestCount INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE tables ADD COLUMN sentToCashier INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          pin TEXT NOT NULL UNIQUE,
          role INTEGER NOT NULL
        )
      ''');
      await db.insert('users', {
        'id': 1,
        'name': 'Admin',
        'pin': '3344',
        'role': UserRole.admin.index,
      });
      await db.insert('users', {
        'id': 2,
        'name': 'وەیتەر 1',
        'pin': '1122',
        'role': UserRole.waiter.index,
      });
      await db.insert('users', {
        'id': 3,
        'name': 'کاشێر 1',
        'pin': '2233',
        'role': UserRole.cashier.index,
      });
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE tables ADD COLUMN printedAt TEXT DEFAULT ""',
      );
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS debts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tableId INTEGER NOT NULL,
          tableName TEXT NOT NULL,
          amount REAL NOT NULL,
          reason TEXT DEFAULT '',
          createdAt TEXT NOT NULL,
          createdBy INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
          'ALTER TABLE tables ADD COLUMN printedAt TEXT DEFAULT ""',
        );
      } catch (_) {}
    }
    if (oldVersion < 36) {
      try {
        await db.execute(
          'ALTER TABLE order_delivery ADD COLUMN printFailedAt TEXT DEFAULT ""',
        );
      } catch (_) {}
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS printer_configs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          portName TEXT NOT NULL,
          printerType INTEGER NOT NULL,
          isDefault INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS category_printer_mappings (
          category TEXT NOT NULL PRIMARY KEY,
          printerConfigId INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS item_printer_overrides (
          itemName TEXT NOT NULL PRIMARY KEY,
          printerConfigId INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS food_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon TEXT DEFAULT 'restaurant',
          section TEXT DEFAULT '',
          sortOrder INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS food_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          category TEXT NOT NULL,
          imageUrl TEXT DEFAULT '',
          sortOrder INTEGER DEFAULT 0
        )
      ''');
      await _seedMenuData(db);
    }
    if (oldVersion < 12) {
      try {
        await db.execute(
          "ALTER TABLE food_categories ADD COLUMN section TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_items ADD COLUMN imageUrl TEXT DEFAULT ''",
        );
      } catch (_) {}
    }
    if (oldVersion < 13) {
      try {
        await db.execute(
          "ALTER TABLE settled_orders ADD COLUMN shiftId INTEGER DEFAULT 0",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE refunds ADD COLUMN shiftId INTEGER DEFAULT 0",
        );
      } catch (_) {}
    }
    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS item_printer_assignments (
          itemName TEXT NOT NULL,
          printerType INTEGER NOT NULL,
          PRIMARY KEY (itemName, printerType)
        )
      ''');
    }
    if (oldVersion < 15) {
      try {
        await db.execute(
          "ALTER TABLE settled_orders ADD COLUMN seatedAt TEXT DEFAULT ''",
        );
      } catch (_) {}
    }
    if (oldVersion < 16) {
      try {
        await db.execute(
          "ALTER TABLE settled_orders ADD COLUMN paymentMethod TEXT DEFAULT 'cash'",
        );
      } catch (_) {}
    }
    if (oldVersion < 17) {
      try {
        await db.execute(
          "ALTER TABLE order_items ADD COLUMN waiterName TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE tables ADD COLUMN note TEXT DEFAULT ''");
      } catch (_) {}
    }
    if (oldVersion < 18) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS waiter_tables (
          waiterId INTEGER NOT NULL,
          tableId INTEGER NOT NULL,
          PRIMARY KEY (waiterId, tableId)
        )
      ''');
      final existingIds = await db.rawQuery('SELECT id FROM tables');
      final ids = existingIds.map((m) => m['id'] as int).toSet();
      for (int i = 1; i <= 100; i++) {
        if (!ids.contains(i)) {
          await db.insert('tables', {
            'id': i,
            'name': 'مێز $i',
            'status': 0,
            'seatedTime': '',
            'waiterId': '',
            'totalAmount': 0.0,
            'guestCount': 0,
            'sentToCashier': 0,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      try {
        await db.insert('users', {
          'id': 2,
          'name': 'وەیتەر 1',
          'pin': '1122',
          'role': UserRole.waiter.index,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('users', {
          'id': 3,
          'name': 'وەیتەر 2',
          'pin': '1123',
          'role': UserRole.waiter.index,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('users', {
          'id': 4,
          'name': 'کاشێر 1',
          'pin': '2233',
          'role': UserRole.cashier.index,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
      for (int i = 1; i <= 50; i++) {
        await db.insert('waiter_tables', {
          'waiterId': 2,
          'tableId': i,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (int i = 51; i <= 100; i++) {
        await db.insert('waiter_tables', {
          'waiterId': 3,
          'tableId': i,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    if (oldVersion < 19) {
      try {
        await db.execute(
          "ALTER TABLE food_items ADD COLUMN name_ar TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_items ADD COLUMN name_fa TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_items ADD COLUMN name_en TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_items ADD COLUMN name_tr TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_categories ADD COLUMN name_ar TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_categories ADD COLUMN name_fa TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_categories ADD COLUMN name_en TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE food_categories ADD COLUMN name_tr TEXT DEFAULT ''",
        );
      } catch (_) {}
    }
    if (oldVersion < 20) {
      try {
        await db.execute(
          "ALTER TABLE tables ADD COLUMN createdBy INTEGER DEFAULT 0",
        );
      } catch (_) {}
      await db.rawUpdate('''
        UPDATE tables SET createdBy = (
          SELECT waiterId FROM waiter_tables WHERE waiter_tables.tableId = tables.id LIMIT 1
        ) WHERE id IN (SELECT tableId FROM waiter_tables)
      ''');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cashier_expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shiftId INTEGER NOT NULL,
          itemName TEXT NOT NULL,
          price REAL NOT NULL,
          createdAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 21) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_sync (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          data TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          status INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 22) {
      try {
        await db.execute(
          "ALTER TABLE settled_orders ADD COLUMN seatedAt TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE settled_orders ADD COLUMN paymentMethod TEXT DEFAULT 'cash'",
        );
      } catch (_) {}
    }
    if (oldVersion < 23) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS table_locks (
          tableId INTEGER PRIMARY KEY,
          deviceId TEXT NOT NULL,
          userId INTEGER NOT NULL,
          userName TEXT NOT NULL,
          role TEXT NOT NULL,
          lockedAt TEXT NOT NULL,
          heartbeat TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 25) {
      try {
        await db.execute('''
          CREATE TABLE order_delivery (
            tableId INTEGER PRIMARY KEY,
            sentAt TEXT NOT NULL,
            arrivedAt TEXT DEFAULT '',
            printedAt TEXT DEFAULT '',
            rejected INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 28) {
      try {
        await db.execute(
          "ALTER TABLE settled_orders ADD COLUMN waiterId TEXT DEFAULT ''",
        );
      } catch (_) {}
    }
    if (oldVersion < 24) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN rangeStart INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN rangeEnd INTEGER');
      } catch (_) {}
      try {
        await db.rawUpdate(
          'UPDATE users SET rangeStart = 1, rangeEnd = 50 WHERE id = 2',
        );
        await db.rawUpdate(
          'UPDATE users SET rangeStart = 51, rangeEnd = 100 WHERE id = 3',
        );
      } catch (_) {}
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settled_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tableId INTEGER NOT NULL,
          tableName TEXT NOT NULL,
          totalAmount REAL NOT NULL,
          discountPercent REAL DEFAULT 0,
          discountAmount REAL DEFAULT 0,
          settledAt TEXT NOT NULL,
          settledBy INTEGER NOT NULL,
          shiftId INTEGER DEFAULT 0,
          seatedAt TEXT DEFAULT '',
          paymentMethod TEXT DEFAULT 'cash'
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settled_order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          settledOrderId INTEGER NOT NULL,
          itemName TEXT NOT NULL,
          itemPrice REAL NOT NULL,
          quantity INTEGER NOT NULL,
          category TEXT DEFAULT ''
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cashier_shifts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cashierId INTEGER NOT NULL,
          cashierName TEXT NOT NULL,
          startedAt TEXT NOT NULL,
          endedAt TEXT DEFAULT '',
          totalCollected REAL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS purchases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          itemName TEXT NOT NULL,
          price REAL NOT NULL,
          purchasedAt TEXT NOT NULL,
          purchasedBy INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS refunds (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tableId INTEGER NOT NULL,
          itemName TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          price REAL NOT NULL,
          refundedAt TEXT NOT NULL,
          refundedBy INTEGER NOT NULL,
          shiftId INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 26) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cancelled_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shiftId INTEGER DEFAULT 0,
          tableId INTEGER NOT NULL,
          tableName TEXT NOT NULL,
          itemName TEXT NOT NULL,
          itemPrice REAL NOT NULL,
          quantity INTEGER DEFAULT 1,
          category TEXT DEFAULT '',
          cancelledAt TEXT NOT NULL,
          cancelledBy INTEGER DEFAULT 0,
          cancelledByName TEXT DEFAULT '',
          requestedByName TEXT DEFAULT '',
          requestedAt TEXT DEFAULT '',
          requestedByRole INTEGER DEFAULT 0,
          status TEXT DEFAULT 'pending',
          servedAt TEXT DEFAULT ''
        )
      ''');
    }
    if (oldVersion < 37) {
      try {
        await db.execute(
          'ALTER TABLE cancelled_items ADD COLUMN requestedByName TEXT DEFAULT ""',
        );
      } catch (_) {}
    }
    if (oldVersion < 38) {
      // Audit columns for the «ڕەتکراوەکان» record: when the dish was first
      // ordered onto the table, and the role (captain or cashier) of the person
      // who ordered it. Old records keep empty/0 and read as unknown.
      try {
        await db.execute(
          'ALTER TABLE cancelled_items ADD COLUMN requestedAt TEXT DEFAULT ""',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE cancelled_items ADD COLUMN requestedByRole INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 39) {
      // Who added each order line, and who opened each table.
      //
      // `waiterRole` mirrors the adder's `UserRole` (0 = captain, 1 = cashier,
      // 2 = admin, 3 = owner); old lines default to -1, which reads as "unknown"
      // rather than wrongly claiming the captain added a cashier's dish.
      // `openedBy` is the user id of whoever first seated the table - separate
      // from `createdBy`, the table's range owner.
      try {
        await db.execute(
          'ALTER TABLE order_items ADD COLUMN waiterRole INTEGER DEFAULT -1',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE tables ADD COLUMN openedBy INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 40) {
      // «قەرز» belongs to the shift that rang it up. The debt list is scoped to
      // the active shift, so closing a shift takes its debts off the till and
      // the next cashier starts with an empty list. Rows written before the
      // column existed default to 0 ("no shift"): they stay on the admin's
      // record but no longer surface on a cashier's shift.
      try {
        await db.execute(
          'ALTER TABLE debts ADD COLUMN shiftId INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 41) {
      // A rejection is scoped to its shift by a DEVICE-INDEPENDENT key, the same
      // (cashierId, startedAt) pair expenses and refunds already use. The bare
      // `shiftId` is a per-device auto-increment number: as soon as another
      // device's counter diverges, a rejection stamped with the till's number
      // collided with an unrelated closed shift here and vanished from the
      // captain's «ڕەتکراوەکان» and the admin's shift report. Old rows keep 0 / ''
      // and fall back to `shiftId` in the scoping query.
      try {
        await db.execute(
          'ALTER TABLE cancelled_items ADD COLUMN shiftCashierId INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE cancelled_items ADD COLUMN shiftStartedAt TEXT DEFAULT ""',
        );
      } catch (_) {}
    }
    if (oldVersion < 27) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS table_notifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tableId INTEGER NOT NULL,
          openedAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 29) {
      try {
        await db.execute(
          "ALTER TABLE users ADD COLUMN accessCode TEXT DEFAULT ''",
        );
      } catch (_) {}
    }
    if (oldVersion < 30) {
      // v30 "Fresh system": wipe all accounts and operational data so the new
      // owner-only login model starts clean (only the Owner exists until the
      // owner or an admin creates accounts). Menu/categories are left intact.
      for (final table in const [
        'order_items',
        'tables',
        'debts',
        'settled_orders',
        'settled_order_items',
        'waiter_tables',
        'cashier_expenses',
        'cashier_shifts',
        'refunds',
        'purchases',
        'pending_sync',
        'table_locks',
        'order_delivery',
        'cancelled_items',
        'table_notifications',
        'users',
      ]) {
        try {
          await db.delete(table);
        } catch (_) {}
      }
      for (int i = 1; i <= 100; i++) {
        try {
          await db.insert('tables', {
            'id': i,
            'name': 'مێز $i',
            'status': TableStatus.empty.index,
            'seatedTime': '',
            'waiterId': '',
            'totalAmount': 0.0,
            'guestCount': 0,
            'sentToCashier': 0,
            'createdBy': 0,
          });
        } catch (_) {}
      }
    }
    if (oldVersion < 31) {
      // v31: delivery-company registry backing the cashier delivery panel.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS delivery_companies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          sortOrder INTEGER DEFAULT 0
        )
      ''');
      final existing = await db.query('delivery_companies', limit: 1);
      if (existing.isEmpty) {
        for (var i = 0; i < _defaultDeliveryCompanies.length; i++) {
          await db.insert('delivery_companies', {
            'name': _defaultDeliveryCompanies[i],
            'sortOrder': i,
          });
        }
      }
    }

    // v32: shop-wide settings (the admin's dollar rate).
    await _createShopSettingsTable(db);

    if (oldVersion < 33) {
      // v33: delivery slots are real table rows, flagged so the dining room
      // never shows them. A delivery order needs the whole table machinery -
      // items, total, bill, print, sync - so it is a table, not a parallel kind
      // of record that would need all of that built a second time.
      try {
        await db.execute(
          'ALTER TABLE tables ADD COLUMN isDelivery INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE tables ADD COLUMN deliveryCompanyId INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE tables ADD COLUMN deliverySlot INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }

    if (oldVersion < 34) {
      // v34: durable, at-most-once kitchen printing. One ledger row per
      // (batch, printer) so a reconnect resend cannot print a second ticket,
      // and a printer that was off can be caught up later.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS print_jobs (
          batchId TEXT NOT NULL,
          printerType INTEGER NOT NULL,
          tableId INTEGER NOT NULL,
          payload TEXT NOT NULL,
          status INTEGER NOT NULL DEFAULT 0,
          attempts INTEGER NOT NULL DEFAULT 0,
          lastError TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          PRIMARY KEY (batchId, printerType)
        )
      ''');
      try {
        await db.execute('ALTER TABLE pending_sync ADD COLUMN batchId TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE pending_sync ADD COLUMN retryCount INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE pending_sync ADD COLUMN lastError TEXT DEFAULT ''",
        );
      } catch (_) {}
    }

    if (oldVersion < 35) {
      // v35: every delivery company carries its own slot count instead of the
      // grid painting one fixed number for all of them. Shops run branches of
      // very different sizes - one courier may need a handful of slots while
      // another needs fifty - and the cashier can raise a company's count
      // without the owner touching a setting.
      try {
        await db.execute(
          'ALTER TABLE delivery_companies ADD COLUMN slotCount INTEGER NOT NULL DEFAULT 50',
        );
      } catch (_) {}
    }

    if (oldVersion < 42) {
      // v42: two things the report needs that the rows did not carry.
      //
      // 1. A debt keeps a snapshot of the dishes that were on its table. Moving
      //    a table to «قەرزەکان» clears the order, so without this the admin can
      //    never see what a credit table ordered.
      // 2. A settled line remembers who rang the dish in (`waiterName` +
      //    `waiterRole`, the same pair `order_items` already carries), so the
      //    captain report can credit captains *and* cashiers for what they sold.
      try {
        await db.execute(
          "ALTER TABLE debts ADD COLUMN itemsJson TEXT DEFAULT ''",
        );
      } catch (_) {}
      for (final stmt in const [
        "ALTER TABLE settled_order_items ADD COLUMN waiterName TEXT DEFAULT ''",
        'ALTER TABLE settled_order_items ADD COLUMN waiterRole INTEGER DEFAULT -1',
      ]) {
        try {
          await db.execute(stmt);
        } catch (_) {}
      }
    }

    if (oldVersion < 43) {
      // v43: a settled order keeps the table's note - the captain's line and the
      // cashier's line packed into `tables.note` - so the admin's shift report
      // can still show what was written on the table after it has been freed and
      // the table row reused. The note is for the record only; it never reaches
      // a printed receipt.
      try {
        await db.execute(
          "ALTER TABLE settled_orders ADD COLUMN note TEXT DEFAULT ''",
        );
      } catch (_) {}
    }

    if (oldVersion < 44) {
      // v44: when a cashier closes their shift while tables are still seated,
      // the report keeps a snapshot of those tables - their dishes, waiter,
      // seated time and note - so the admin can see which tables were left
      // un-settled after the shift was locked up. The snapshot is informational
      // only: it never changes a table or counts into the shift's money.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shift_remaining_tables (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shiftId INTEGER NOT NULL,
          shiftCashierId INTEGER DEFAULT 0,
          shiftStartedAt TEXT DEFAULT '',
          tableId INTEGER NOT NULL,
          tableName TEXT NOT NULL,
          guestCount INTEGER DEFAULT 0,
          seatedAt TEXT DEFAULT '',
          waiterId TEXT DEFAULT '',
          waiterName TEXT DEFAULT '',
          note TEXT DEFAULT '',
          totalAmount REAL DEFAULT 0,
          itemsJson TEXT DEFAULT '',
          createdAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 45) {
      // v45: the admin's table-notes page filters by day, so the tables row
      // remembers when its note was last written. Existing notes keep an
      // empty stamp and stay visible under the "هەموو" period only.
      try {
        await db.execute(
          "ALTER TABLE tables ADD COLUMN noteUpdatedAt TEXT DEFAULT ''",
        );
      } catch (_) {}
    }

    await _createSyncIndexes(db);
  }

  // ==================== Users ====================

  Future<UserModel?> getUserByPin(String pin) async {
    final maps = await db.query('users', where: 'pin = ?', whereArgs: [pin]);
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
  }

  Future<UserModel?> getUserById(int id) async {
    final maps = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return UserModel.fromMap(maps.first);
  }

  Future<List<UserModel>> getUsersByRole(UserRole role) async {
    final maps = await db.query(
      'users',
      where: 'role = ?',
      whereArgs: [role.index],
      orderBy: 'name ASC',
    );
    return maps.map((m) => UserModel.fromMap(m)).toList();
  }

  /// Every real account (id > 0; the virtual owner is id 0 and lives only in
  /// [OwnerCredentials]). Used for the user-registry portion of snapshots and
  /// for the device → server reconciliation upload.
  Future<List<UserModel>> getAllUsers() async {
    final maps = await db.query('users', orderBy: 'id ASC');
    return maps
        .map((m) => UserModel.fromMap(m))
        .where((u) => u.id > 0)
        .toList();
  }

  Future<bool> addUser(
    String name,
    String pin,
    UserRole role, {
    int? rangeStart,
    int? rangeEnd,
    String? accessCode,
  }) async {
    try {
      final id = await db.insert('users', {
        'name': name,
        'pin': pin,
        'role': role.index,
        'rangeStart': rangeStart,
        'rangeEnd': rangeEnd,
        'accessCode': accessCode == null ? '' : accessCode.trim(),
      });
      _emitMutation('USER_CREATED', {
        'user': {
          'id': id,
          'name': name,
          'pin': pin,
          'role': role.index,
          'rangeStart': rangeStart,
          'rangeEnd': rangeEnd,
          'accessCode': accessCode == null ? '' : accessCode.trim(),
        },
      });
      _bumpUsers();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteUser(int id) async {
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
    await db.delete('waiter_tables', where: 'waiterId = ?', whereArgs: [id]);
    _emitMutation('USER_DELETED', {'id': id});
    _bumpUsers();
  }

  // ==================== Delivery Companies ====================

  Future<List<DeliveryCompany>> getDeliveryCompanies() async {
    final maps = await db.query(
      'delivery_companies',
      orderBy: 'sortOrder ASC, id ASC',
    );
    return maps.map((m) => DeliveryCompany.fromMap(m)).toList();
  }

  /// Creates a delivery company, broadcasts a `DELIVERY_COMPANY_CREATED`
  /// mutation to every connected device and returns its new id.
  ///
  /// The new company goes to the **end** of the bar. Adding used to write
  /// `sortOrder: 0`, so every company the cashier added landed at the front
  /// instead of after the ones already there - and once two companies shared a
  /// sort order their relative position was decided by id, not by when they
  /// were added.
  Future<int> addDeliveryCompany(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 0;
    final sortOrder = await _nextCompanySortOrder();
    final id = await db.insert('delivery_companies', {
      'name': trimmed,
      'sortOrder': sortOrder,
      'slotCount': DeliveryCompany.defaultSlotsPerCompany,
    });
    _emitMutation('DELIVERY_COMPANY_CREATED', {
      'company': DeliveryCompany(
        id: id,
        name: trimmed,
        sortOrder: sortOrder,
        slotCount: DeliveryCompany.defaultSlotsPerCompany,
      ).toMap(),
    });
    _bumpDeliveryCompanies();
    return id;
  }

  /// Changes how many table slots a company offers and tells every other
  /// device, so two tills never disagree about how big a company is.
  ///
  /// The count is clamped to what the slot numbering can represent (see
  /// [DeliveryCompany.maxSlotsPerCompany]) and is never allowed below the slots
  /// that already hold an order: dropping those would hide live deliveries off
  /// the grid, leaving food rung in that nobody can reach or settle.
  /// Returns the count actually stored.
  Future<int> setDeliveryCompanySlotCount(int id, int count) async {
    final company = await getDeliveryCompany(id);
    if (company == null) return 0;
    final inUse = await getHighestUsedDeliverySlot(id);
    var wanted = count < 1 ? 1 : count;
    if (wanted > DeliveryCompany.maxSlotsPerCompany) {
      wanted = DeliveryCompany.maxSlotsPerCompany;
    }
    if (wanted < inUse) wanted = inUse;
    if (wanted == company.slotCount) return wanted;
    await db.update(
      'delivery_companies',
      {'slotCount': wanted},
      where: 'id = ?',
      whereArgs: [id],
    );
    _emitMutation('DELIVERY_COMPANY_UPDATED', {
      'company': company.copyWith(slotCount: wanted).toMap(),
    });
    _bumpDeliveryCompanies();
    return wanted;
  }

  Future<DeliveryCompany?> getDeliveryCompany(int id) async {
    final maps = await db.query(
      'delivery_companies',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return DeliveryCompany.fromMap(maps.first);
  }

  /// Highest slot number of [companyId] that has ever been used, 0 when none
  /// has. Used to keep a shrunken company from swallowing its own live slots.
  Future<int> getHighestUsedDeliverySlot(int companyId) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(deliverySlot), 0) AS top FROM tables '
      'WHERE deliveryCompanyId = ? AND isDelivery = 1',
      [companyId],
    );
    if (result.isEmpty) return 0;
    return (result.first['top'] as num?)?.toInt() ?? 0;
  }

  /// The company's slots that still carry an order, cheapest reading first.
  ///
  /// This is what stands between the cashier and a delete that would throw away
  /// food that has already been rung in. Slots created but never ordered on are
  /// not "in use" - they hold nothing.
  Future<List<TableModel>> getOccupiedDeliverySlots(int companyId) async {
    final maps = await db.query(
      'tables',
      where: 'deliveryCompanyId = ? AND isDelivery = 1',
      whereArgs: [companyId],
      orderBy: 'deliverySlot ASC',
    );
    final occupied = <TableModel>[];
    for (final map in maps) {
      final table = TableModel.fromMap(map);
      final items = await getOrderItems(table.id);
      if (items.isNotEmpty) occupied.add(table);
    }
    occupied.sort((a, b) => a.deliverySlot.compareTo(b.deliverySlot));
    return occupied;
  }

  /// Throws out the whole order on a table, one item at a time.
  ///
  /// Each item goes through [removeOrderItem], so every line lands in
  /// `cancelled_items` and shows up on the cashier's discarded-items page: a
  /// voided delivery is an audited act, not a silent wipe. Once the last item
  /// goes the table is freed like any other emptied table, and the total
  /// recalculates on the way.
  /// Returns how many items were thrown out.
  Future<int> voidTableOrder(
    int tableId, {
    int cancelledBy = 0,
    String cancelledByName = '',
  }) async {
    final items = await getOrderItems(tableId);
    for (final item in items) {
      await removeOrderItem(
        tableId,
        item.id,
        cancelledBy: cancelledBy,
        cancelledByName: cancelledByName,
      );
    }
    if (items.isNotEmpty) await freeTable(tableId);
    return items.length;
  }

  /// One past the last company on the bar, so a new one appends after it.
  Future<int> _nextCompanySortOrder() async {
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), -1) AS top FROM delivery_companies',
    );
    final top = result.isEmpty
        ? -1
        : ((result.first['top'] as num?)?.toInt() ?? -1);
    return top + 1;
  }

  /// Saves a new order for the company bar and tells every other device.
  ///
  /// [orderedIds] is the bar left to right. Only the positions are sent, never
  /// names, so one cashier dragging a chip cannot rewrite a company another
  /// cashier is in the middle of renaming.
  Future<void> reorderDeliveryCompanies(List<int> orderedIds) async {
    if (orderedIds.length < 2) return;
    final current = await getDeliveryCompanies();
    // A stale bar (a company added on another device a moment ago) must not
    // rewrite positions from a list that is no longer the whole truth.
    if (current.length != orderedIds.length) return;
    // Nothing actually moved - do not make every other device redraw for it.
    if (_sameOrder([for (final company in current) company.id], orderedIds)) {
      return;
    }
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'delivery_companies',
          {'sortOrder': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
    _emitMutation('DELIVERY_COMPANIES_REORDERED', {'order': orderedIds});
    _bumpDeliveryCompanies();
  }

  bool _sameOrder(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Deletes a delivery company and broadcasts `DELIVERY_COMPANY_DELETED`.
  /// Safe to call from the sync layer - the mutation is suppressed while
  /// `remoteMutationDepth > 0` so remote applications never echo back.
  ///
  /// The company's slots go with it, along with the orders on them. Leaving
  /// those behind would strand live delivery orders: a slot row that belongs to
  /// no company shows up nowhere, so its food and its money are unreachable.
  ///
  /// A company that still has food rung in on it is **not** deleted: the money
  /// and the kitchen ticket on those slots would vanish with the row, and a
  /// settled day would no longer add up. Returns false and leaves everything
  /// alone so the caller can settle or void those orders first - which is the
  /// order the shop actually wants, "settle it or throw it out, then delete".
  ///
  /// [force] skips that guard. The sync layer passes it because the deletion
  /// was already decided on the device that owns the company, and that device
  /// made the orders disappear before announcing the delete; a second till that
  /// has not caught up yet must not keep a company the whole shop already
  /// removed.
  Future<bool> deleteDeliveryCompany(
    int id, {
    bool force = false,
    int cancelledBy = 0,
    String cancelledByName = '',
  }) async {
    if (!force && (await getOccupiedDeliverySlots(id)).isNotEmpty) return false;
    await _deleteDeliverySlotsOf(
      id,
      // A local delete keeps the same "food is never lost" promise as a table
      // delete: whatever is still on the slots goes into «ڕەتکراوەکان» first.
      // A forced delete arrives from another device that already sent its own
      // cancelled records, so it purges without repeating them.
      cancelFood: !force,
      cancelledBy: cancelledBy,
      cancelledByName: cancelledByName,
    );
    await db.delete('delivery_companies', where: 'id = ?', whereArgs: [id]);
    _emitMutation('DELIVERY_COMPANY_DELETED', {'id': id});
    _bumpDeliveryCompanies();
    return true;
  }

  /// Removes every slot belonging to [companyId] and the orders on them.
  ///
  /// `remoteMutationDepth` is raised so the hub that asked for the deletion
  /// does not hear about each slot going, and a device that had those orders
  /// in flight stops trying to push them. Cancelled records made inside this
  /// depth window stay local on purpose: they belong to this device's shift.
  Future<void> _deleteDeliverySlotsOf(
    int companyId, {
    bool cancelFood = false,
    int cancelledBy = 0,
    String cancelledByName = '',
  }) async {
    remoteMutationDepth++;
    try {
      final slots = await db.query(
        'tables',
        columns: ['id', 'name'],
        where: 'deliveryCompanyId = ? AND isDelivery = 1',
        whereArgs: [companyId],
      );
      for (final slot in slots) {
        await _purgeTableRows(
          slot['id'] as int,
          tableName: slot['name'] as String? ?? '',
          cancelledBy: cancelledBy,
          cancelledByName: cancelledByName,
          cancelFood: cancelFood,
        );
      }
      await db.delete(
        'tables',
        where: 'deliveryCompanyId = ? AND isDelivery = 1',
        whereArgs: [companyId],
      );
    } finally {
      remoteMutationDepth--;
    }
    _bumpOrders();
  }

  /// Removes a table and everything recorded against it.
  ///
  /// Food still sitting on the table is never silently lost: open
  /// [order_items] are first moved into `cancelled_items` («ڕەتکراوەکان») with
  /// their full data - dish name, price, quantity, category, table, and who
  /// removed them - so the shift keeps a complete, refundable record of what
  /// was on the table. The same records are pushed to the hub, so the captain
  /// and the admin see the exact same cancelled dishes on their own devices.
  ///
  /// [cancelFood] exists for the sync path: a delete that was already decided
  /// on another device already sent those cancelled records ahead of itself, so
  /// applying it must purge WITHOUT recording the same dishes again - repeating
  /// them would double the cancelled orders for one shift.
  ///
  /// Shared by [deleteTable] and the delivery-slot cleanup so a removed
  /// delivery order leaves no debt, no lock and no printed record pointing at a
  /// table that no longer exists.
  Future<void> _purgeTableRows(
    int tableId, {
    String tableName = '',
    int cancelledBy = 0,
    String cancelledByName = '',
    bool cancelFood = true,
  }) async {
    if (cancelFood) {
      await _recordTableFoodAsCancelled(
        tableId: tableId,
        tableName: tableName,
        cancelledBy: cancelledBy,
        cancelledByName: cancelledByName,
      );
    }
    await db.delete('order_items', where: 'tableId = ?', whereArgs: [tableId]);
    await db.delete(
      'waiter_tables',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    await db.delete(
      'order_delivery',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    await db.delete(
      'table_notifications',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    await db.delete('table_locks', where: 'tableId = ?', whereArgs: [tableId]);
    await db.delete('refunds', where: 'tableId = ?', whereArgs: [tableId]);
    for (final row in await db.query(
      'debts',
      where: 'tableId = ?',
      whereArgs: [tableId],
    )) {
      final settled = (row['isSettled'] as int? ?? 0) == 1;
      if (!settled) {
        await db.delete('debts', where: 'tableId = ?', whereArgs: [tableId]);
      }
    }
  }

  /// Moves every open dish still sitting on [tableId] into «ڕەتکراوەکان»
  /// (`cancelled_items`) before the table itself is removed.
  ///
  /// The rule is simple: deleting a table must never eat an order. Each dish
  /// becomes its own cancelled record carrying the FULL row - name, price,
  /// quantity, category, the table it was on, the waiter who rang it in, and
  /// who removed the table - so the cashier's «ڕەتکراوەکان» page and the shift
  /// report show exactly what was on the table and what happened to it.
  ///
  /// [tableName] is passed in because the `tables` row may already be gone by
  /// the time this runs (the delete removes it first); the order rows are still
  /// there, so nothing is missing either way.
  Future<void> _recordTableFoodAsCancelled({
    required int tableId,
    required String tableName,
    required int cancelledBy,
    required String cancelledByName,
  }) async {
    final items = await db.query(
      'order_items',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    for (final row in items) {
      await recordCancelledItem(
        tableId: tableId,
        tableName: tableName,
        itemName: row['name'] as String? ?? '',
        price: (row['price'] as num?)?.toDouble() ?? 0,
        quantity: row['quantity'] as int? ?? 1,
        category: row['category'] as String? ?? '',
        cancelledBy: cancelledBy,
        cancelledByName: cancelledByName,
        requestedByName: row['waiterName'] as String? ?? '',
        requestedAt: row['createdAt'] as String? ?? '',
      );
    }
  }

  /// Upserts a delivery company received from another device (id is kept, so
  /// every node references the same company ids across the network).
  Future<void> applyRemoteDeliveryCompany(DeliveryCompany company) async {
    // A hub on a newer build carries fields this device has never heard of, and
    // SQLite refuses the whole statement for one unknown column - so the
    // company would neither update nor appear. Take the fields this table has
    // and leave the rest for when this device is updated.
    final row = _restrictToColumns(
      company.toMap(),
      await _tableColumns(db, 'delivery_companies'),
    );
    final updated = await db.update(
      'delivery_companies',
      row,
      where: 'id = ?',
      whereArgs: [company.id],
    );
    if (updated == 0) {
      await db.insert(
        'delivery_companies',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _bumpDeliveryCompanies();
  }

  /// The column names a table actually has.
  ///
  /// Null when the question cannot be answered, which callers read as "say
  /// nothing about the columns" and pass the row through untouched - a missing
  /// answer must not empty a row.
  static Future<Set<String>?> _tableColumns(
    DatabaseExecutor txn,
    String table,
  ) async {
    try {
      final info = await txn.rawQuery('PRAGMA table_info($table)');
      if (info.isEmpty) return null;
      return info.map((c) => c['name'] as String).toSet();
    } catch (_) {
      return null;
    }
  }

  /// Keeps only the fields [columns] has. [columns] of null means "unknown",
  /// and the row is returned as it came in.
  static Map<String, dynamic> _restrictToColumns(
    Map<String, dynamic> row,
    Set<String>? columns,
  ) {
    if (columns == null) return row;
    if (row.keys.every(columns.contains)) return row;
    return Map<String, dynamic>.fromEntries(
      row.entries.where((entry) => columns.contains(entry.key)),
    );
  }

  Future<bool> updateUserPin(int id, String newPin) async {
    try {
      await db.update(
        'users',
        {'pin': newPin},
        where: 'id = ?',
        whereArgs: [id],
      );
      final user = await getUserById(id);
      if (user != null) {
        _emitMutation('USER_UPDATED', {'user': user.toMap()});
      }
      _bumpUsers();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateUserName(int id, String newName) async {
    try {
      await db.update(
        'users',
        {'name': newName},
        where: 'id = ?',
        whereArgs: [id],
      );
      _bumpUsers();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateUserRange(int id, int? rangeStart, int? rangeEnd) async {
    // A range with a missing end is not a range: treat it as the reset instead
    // of writing half a scope the captain can never clear.
    if (rangeStart == null || rangeEnd == null) {
      return resetWaiterScope(id);
    }
    try {
      // A مەودا REPLACES whatever scope was there. The owner is redefining this
      // captain's floor, so the tables picked for them earlier - by an older
      // مەودا or by the pick-tables dialog - must not survive and keep their
      // old tables on the captain's screen. Left behind, they are exactly why
      // writing a fresh مەودا used to look like it did nothing.
      await db.update(
        'users',
        {'rangeStart': rangeStart, 'rangeEnd': rangeEnd},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.delete(
        'waiter_tables',
        where: 'waiterId = ?',
        whereArgs: [id],
      );
      // Release the tables the PREVIOUS scope had locked to this captain, then
      // lock the unowned ones inside the new window. Releasing first stops an
      // old مەودا's tables from staying glued to them through `createdBy`, which
      // would otherwise keep showing a window the owner has moved away from.
      await db.update(
        'tables',
        {'createdBy': 0},
        where: 'createdBy = ?',
        whereArgs: [id],
      );
      await db.rawUpdate(
        'UPDATE tables SET createdBy = ? WHERE createdBy = 0 AND id >= ? AND id <= ?',
        [id, rangeStart, rangeEnd],
      );
      // Both halves of the scope travel: the picked tables are cleared and the
      // registry line below carries the new مەودا to the captain's device.
      _emitMutation('WAITER_TABLES_UPDATED', {
        'waiterId': id,
        'tableIds': const <int>[],
      });
      final user = await getUserById(id);
      if (user != null) {
        _emitMutation('USER_UPDATED', {'user': user.toMap()});
      }
      _bumpUsers();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// «گەڕانەوە بۆ ئاسایی»: hand the captain back a plain account.
  ///
  /// The numeric range and the explicit table picks are two ways of writing the
  /// SAME scope, so a reset has to clear BOTH. When each dialog cleared only its
  /// own half, resetting from one left the other still in force and the account
  /// was not normal at all. Both dialogs call this one method, so one press is
  /// one action: no range, no picked tables, and every table the range had
  /// locked to this captain is released back to the shared floor.
  Future<bool> resetWaiterScope(int id) async {
    try {
      await db.update(
        'users',
        {'rangeStart': null, 'rangeEnd': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.update(
        'tables',
        {'createdBy': 0},
        where: 'createdBy = ?',
        whereArgs: [id],
      );
      await db.delete(
        'waiter_tables',
        where: 'waiterId = ?',
        whereArgs: [id],
      );
      // Both halves travel to the captain's device: the registry mutation below
      // clears the range, and this one clears the picked tables.
      _emitMutation('WAITER_TABLES_UPDATED', {
        'waiterId': id,
        'tableIds': const <int>[],
      });
      final user = await getUserById(id);
      if (user != null) {
        _emitMutation('USER_UPDATED', {'user': user.toMap()});
      }
      _bumpUsers();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setUserAccessCode(int id, String code) async {
    try {
      await db.update(
        'users',
        {'accessCode': code.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );
      final user = await getUserById(id);
      if (user != null) {
        _emitMutation('USER_UPDATED', {'user': user.toMap()});
      }
      _bumpUsers();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Applies a user registry sync mutation (USER_CREATED / USER_UPDATED) coming
  /// from the central cashier/server. Never re-emits a mutation so remote
  /// updates can't loop back.
  ///
  /// The id is the account's identity on the wire, and it is the identity every
  /// other registry message uses too (USER_DELETED, the table assignments in
  /// `waiter_tables`, and each account's own edits), so a row is matched by id
  /// and updated in place. Matching by PIN instead would break the everyday
  /// case of an owner CHANGING somebody's PIN: the changed PIN matches no local
  /// row, the row would be treated as a different person, and the edit would
  /// silently create a second account instead of applying.
  ///
  /// The open limitation this leaves is that two devices which were apart can
  /// hand the same AUTOINCREMENT id to two different people, and the later
  /// write wins. Closing that properly needs a device-scoped account id carried
  /// on every registry message - a schema migration plus a change to every
  /// account message - not a heuristic, which would be wrong in one direction or
  /// the other. The owner-peer snapshot path
  /// ([applyRegistrySnapshotUsers]) is already collision-safe, because there the
  /// copy is additive and the PIN is checked first.
  Future<void> applyRemoteUser(Map<String, dynamic> userMap) async {
    final id = userMap['id'] as int? ?? 0;
    if (id <= 0) return;
    remoteMutationDepth++;
    try {
      final existing = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final map = Map<String, dynamic>.from(userMap);
      map['accessCode'] = (userMap['accessCode'] as String? ?? '').trim();
      if (existing.isEmpty) {
        await db.insert(
          'users',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        await db.update('users', map, where: 'id = ?', whereArgs: [id]);
        // A مەودا change does TWO things on the device that made it: it writes
        // the range, and it re-locks the `createdBy` ownership of the window
        // (see [updateUserRange]). Only the range travels as a registry
        // mutation, so without this the captain's device keeps the OLD lock:
        // its own floor - and every cashier's list - still shows the tables the
        // previous مەودا glued to them, and a freshly-narrowed captain sees the
        // old window as well as the new one. Re-derive the lock from the range
        // that just arrived, exactly as the owner's device did.
        final oldStart = existing.first['rangeStart'] as int?;
        final oldEnd = existing.first['rangeEnd'] as int?;
        final newStart = (map['rangeStart'] as num?)?.toInt();
        final newEnd = (map['rangeEnd'] as num?)?.toInt();
        if (oldStart != newStart || oldEnd != newEnd) {
          await _mirrorWaiterTableLock(id, newStart, newEnd);
        }
      }
    } finally {
      remoteMutationDepth--;
      _bumpUsers();
    }
  }

  /// Re-derives one captain's `createdBy` table lock from a range that arrived
  /// from another device, mirroring [updateUserRange] and [resetWaiterScope].
  ///
  /// Release first, then lock the unowned tables inside the new window, so an
  /// old مەودا's window is let go before the new one is taken. Kept to the same
  /// order as the owner's device so both ends converge on the same set.
  Future<void> _mirrorWaiterTableLock(
    int waiterId,
    int? rangeStart,
    int? rangeEnd,
  ) async {
    await db.update(
      'tables',
      {'createdBy': 0},
      where: 'createdBy = ?',
      whereArgs: [waiterId],
    );
    if (rangeStart != null && rangeEnd != null) {
      await db.rawUpdate(
        'UPDATE tables SET createdBy = ? WHERE createdBy = 0 AND id >= ? AND id <= ?',
        [waiterId, rangeStart, rangeEnd],
      );
    }
    // The floor is rebuilt from `orderRevision` on the pages that show tables,
    // so a lock change that only bumped the user registry would sit invisible
    // until something else moved the floor.
    _bumpOrders();
  }

  Future<void> deleteRemoteUser(int id) async {
    if (id <= 0) return;
    remoteMutationDepth++;
    try {
      await db.delete('users', where: 'id = ?', whereArgs: [id]);
      await db.delete('waiter_tables', where: 'waiterId = ?', whereArgs: [id]);
    } finally {
      remoteMutationDepth--;
      _bumpUsers();
    }
  }

  /// Adopts the account list of a SIBLING OWNER DEVICE (the owner peer link).
  ///
  /// Deliberately additive: nothing that already exists here is modified and
  /// nothing is ever deleted. Two owner devices that each pushed their whole
  /// registry at each other would otherwise overwrite one another in a loop.
  /// This snapshot only fills the gaps; every later change (name, PIN, table
  /// range, access code, deletion) travels as a USER_UPDATED / USER_DELETED
  /// mutation, which carries the author and a message id, so those edits are
  /// what actually converge.
  ///
  /// A peer's account can land on an id this device already handed to a
  /// DIFFERENT account - two devices that were apart each numbered their own
  /// accounts from 1. Dropping it would lose an account silently, so the peer's
  /// copy is inserted under a fresh local id instead. The PIN is the account's
  /// real identity (it is what a staff member types to sign in), so a matching
  /// PIN means it is the same account and nothing is inserted at all.
  Future<void> applyRegistrySnapshotUsers(
    List<Map<String, dynamic>> userMaps,
  ) async {
    if (userMaps.isEmpty) return;
    remoteMutationDepth++;
    var adopted = 0;
    var renumbered = 0;
    try {
      for (final map in userMaps) {
        final id = map['id'] as int? ?? 0;
        if (id <= 0) continue;
        final pin = (map['pin'] as String? ?? '').trim();
        if (pin.isNotEmpty) {
          final samePin = await db.query(
            'users',
            where: 'pin = ?',
            whereArgs: [pin],
            limit: 1,
          );
          if (samePin.isNotEmpty) continue;
        }
        final row = Map<String, dynamic>.from(map)
          ..['accessCode'] = (map['accessCode'] as String? ?? '').trim();
        final taken = await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (taken.isNotEmpty) {
          // The id belongs to a different local account - keep both by letting
          // SQLite pick the next free id for the peer's copy.
          row.remove('id');
          renumbered++;
        }
        await db.insert(
          'users',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        adopted++;
      }
    } finally {
      remoteMutationDepth--;
      if (adopted > 0) _bumpUsers();
    }
    appLog(
      '[DB] Peer registry: adopted $adopted account(s) from the other owner device'
      '${renumbered > 0 ? ' ($renumbered re-numbered after an id clash)' : ''}',
    );
  }

  /// Recreates the classic default staff accounts (admin / two waiters with
  /// ranges / one cashier) with 5-digit PINs. Used only by tests so the rest of
  /// the suite keeps its historical user ids and table ownership behaviour.
  @visibleForTesting
  Future<void> seedDefaultStaff() async {
    final existing = await db.query('users');
    if (existing.isNotEmpty) return;
    await addUser('Admin', '33441', UserRole.admin, accessCode: '');
    await addUser(
      'وەیتەر 1',
      '11221',
      UserRole.waiter,
      rangeStart: 1,
      rangeEnd: 50,
      accessCode: '',
    );
    await addUser(
      'وەیتەر 2',
      '11223',
      UserRole.waiter,
      rangeStart: 51,
      rangeEnd: 100,
      accessCode: '',
    );
    await addUser('کاشێر 1', '22334', UserRole.cashier, accessCode: '');
    await updateUserRange(2, 1, 50);
    await updateUserRange(3, 51, 100);
    for (int i = 1; i <= 50; i++) {
      await db.insert('waiter_tables', {'waiterId': 2, 'tableId': i});
    }
    for (int i = 51; i <= 100; i++) {
      await db.insert('waiter_tables', {'waiterId': 3, 'tableId': i});
    }
  }

  Future<List<String>> getAllAccessCodes() async {
    final rows = await db.query('users', columns: ['accessCode']);
    return rows
        .map((m) => (m['accessCode'] as String? ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toList();
  }

  /// Access-code enforcement turns on as soon as ANY user has one, so a fresh
  /// install keeps working until the admin assigns IP codes.
  Future<bool> hasAnyAccessCode() async {
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM users WHERE accessCode IS NOT NULL AND accessCode != ''",
    );
    return (result.first['cnt'] as int) > 0;
  }

  // ==================== Delivery slots ====================

  /// Where delivery-slot table numbers start.
  ///
  /// A slot is a table row, so its id has to sit clear of the dining room's
  /// numbers. 100000 leaves room for a hundred thousand tables and a thousand
  /// companies, which is far past anything a shop will reach, and keeps the
  /// arithmetic below readable: the number itself says which company and which
  /// slot it is.
  static const int deliverySlotBase = 100000;

  /// The table number a company's slot is stored under.
  static int deliverySlotTableId(int companyId, int slot) =>
      deliverySlotBase + companyId * 100 + slot;

  /// The delivery slots of one company, empty ones first then in use, so the
  /// cashier reaches for a free slot first.
  Future<List<TableModel>> getDeliverySlots(int companyId) async {
    final maps = await db.query(
      'tables',
      where: 'deliveryCompanyId = ? AND isDelivery = 1',
      whereArgs: [companyId],
      orderBy: 'deliverySlot ASC',
    );
    final list = maps.map((m) => TableModel.fromMap(m)).toList();
    list.sort((a, b) {
      final freeA = a.status == TableStatus.empty ? 0 : 1;
      final freeB = b.status == TableStatus.empty ? 0 : 1;
      if (freeA != freeB) return freeA.compareTo(freeB);
      return a.deliverySlot.compareTo(b.deliverySlot);
    });
    return list;
  }

  /// The row behind a delivery slot, created the first time it is opened.
  ///
  /// Slots are made on demand rather than all fifty up front so a device that
  /// has never been used for that company holds no rows for it, and a company
  /// added today does not push fifty rows through the sync link to every
  /// device. The row is shared by every device through the ordinary
  /// `addTable` mutation, so all of them end up pointing at the same number.
  ///
  /// [slot] is refused outside the company's own hundred: slot numbers are
  /// `base + companyId * 100 + slot`, so slot 100 would be the next company's
  /// slot 0 and two companies would share one table row.
  Future<TableModel> ensureDeliverySlot(
    int companyId,
    String companyName,
    int slot,
  ) async {
    if (slot < 1 || slot > DeliveryCompany.maxSlotsPerCompany) {
      throw ArgumentError.value(
        slot,
        'slot',
        'delivery slot must be 1..${DeliveryCompany.maxSlotsPerCompany}',
      );
    }
    final tableId = deliverySlotTableId(companyId, slot);
    final existing = await getTable(tableId);
    if (existing != null) return existing;
    final table = TableModel(
      id: tableId,
      // The company's own name, so the print, the bill and the order list all
      // read correctly without anyone having to remember the table number.
      name: '$companyName $slot',
      isDelivery: true,
      deliveryCompanyId: companyId,
      deliverySlot: slot,
    );
    await addTable(table);
    return table;
  }

  // ==================== Tables ====================
  /// Every table in the dining room.
  ///
  /// Delivery slots are left out unless [includeDelivery] is set: they are
  /// orders, not places to sit, so they must not turn up in the table grid, in
  /// a captain's narrowed list, in the transfer picker or in the "which tables
  /// are still free" count. The snapshot that seeds a newly connected device
  /// asks for them, because a cashier that had never opened a slot still has to
  /// end up with the same slots the other devices have.
  Future<List<TableModel>> getAllTables({bool includeDelivery = false}) async {
    final maps = includeDelivery
        ? await db.query('tables')
        : await db.query(
            'tables',
            where: 'isDelivery = 0 OR isDelivery IS NULL',
          );
    final list = maps.map((m) => Map<String, dynamic>.from(m)).toList();
    list.sort((a, b) {
      final keyA = _extractSortKey(a['name'] as String);
      final keyB = _extractSortKey(b['name'] as String);
      if (keyA is int && keyB is int) return keyA.compareTo(keyB);
      if (keyA is int) return -1;
      if (keyB is int) return 1;
      return (a['id'] as int).compareTo(b['id'] as int);
    });
    return list.map((m) => TableModel.fromMap(m)).toList();
  }

  dynamic _extractSortKey(String name) {
    final trimmed = name.trim();
    final parsed = int.tryParse(trimmed);
    if (parsed != null) return parsed;
    if (trimmed.startsWith('مێز ')) {
      final afterPrefix = trimmed.substring(4).trim();
      final parsedAfter = int.tryParse(afterPrefix);
      if (parsedAfter != null) return parsedAfter;
    }
    return name;
  }

  Future<TableModel?> getTable(int id) async {
    final maps = await db.query('tables', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return TableModel.fromMap(maps.first);
  }

  Future<int> getTableGuestCount(int tableId) async {
    final table = await getTable(tableId);
    return table?.guestCount ?? 1;
  }

  Future<bool> isTableNameTaken(String name) async {
    final result = await db.query(
      'tables',
      where: 'name = ?',
      whereArgs: [name],
    );
    return result.isNotEmpty;
  }

  Future<bool> isTableIdTaken(int id) async {
    final result = await db.query('tables', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty;
  }

  Future<void> updateTable(TableModel table) async {
    await db.update(
      'tables',
      table.toMap(),
      where: 'id = ?',
      whereArgs: [table.id],
    );
  }

  Future<void> addTable(TableModel table) async {
    await db.insert('tables', table.toMap());
    _emitMutation('addTable', {'table': table.toMap()});
  }

  /// Deletes the dining-room tables and their orders, then creates tables 1 to
  /// [count].
  ///
  /// Delivery slots and the orders on them are left alone. This is "the dining
  /// room is 1 to [count] now" - a change to the room, not a decision to throw
  /// away food that has been rung in and money that is owed on it. Wiping them
  /// here would also leave the other tills holding slots this device no longer
  /// has, and the same delivery would then exist on one till and not another.
  Future<void> resetTablesToRange(int count) async {
    await db.delete(
      'order_items',
      where: 'tableId NOT IN (SELECT id FROM tables WHERE isDelivery = 1)',
    );
    await db.delete('tables', where: 'isDelivery = 0 OR isDelivery IS NULL');
    for (int i = 1; i <= count; i++) {
      await db.insert('tables', TableModel(id: i, name: '$i').toMap());
    }
    _bumpOrders();
  }

  /// Deletes a table's row and data.
  ///
  /// The dining room is fixed at 1..[kStandardTableCount]: a standard table is
  /// a place in the room, not a record the shop can run out of. Deleting one
  /// used to punch a permanent hole in every grid, transfer picker and waiter
  /// range until someone re-seeded the database by hand. So right after the
  /// delete the standard tables are re-checked and the deleted row comes back
  /// as a fresh, empty "مێز N" - and the same happens on the other devices when
  /// the delete arrives over the link, because the synced apply path ends in
  /// the same restore.
  ///
  /// Any food still on the table is recorded into «ڕەتکراوەکان» first (see
  /// [_recordTableFoodAsCancelled]), so a delete can never silently eat an
  /// order. Pass the cashier who tapped delete as [cancelledBy]/[cancelledByName]
  /// so the cancelled record names exactly who closed the table.
  Future<void> deleteTable(
    int tableId, {
    int cancelledBy = 0,
    String cancelledByName = '',
  }) async {
    final row = await db.query(
      'tables',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [tableId],
      limit: 1,
    );
    final tableName = row.isEmpty ? '' : (row.first['name'] as String? ?? '');
    await _deleteTableCore(
      tableId,
      tableName: tableName,
      cancelledBy: cancelledBy,
      cancelledByName: cancelledByName,
    );
  }

  /// Applies a table deletion that was already decided and announced by
  /// another device.
  ///
  /// The deleting device moved any food into «ڕەتکراوەکان» and pushed those
  /// records ahead of this delete, so this device must purge WITHOUT recording
  /// the same dishes again - repeating them would double the cancelled orders
  /// for one shift. The no-echo wrapper in the sync layer stops this from being
  /// re-announced back to the hub.
  Future<void> applyRemoteTableDelete(int tableId) async {
    await _deleteTableCore(tableId, cancelFood: false);
  }

  Future<void> _deleteTableCore(
    int tableId, {
    bool cancelFood = true,
    String tableName = '',
    int cancelledBy = 0,
    String cancelledByName = '',
  }) async {
    await db.delete('tables', where: 'id = ?', whereArgs: [tableId]);
    await _purgeTableRows(
      tableId,
      tableName: tableName,
      cancelledBy: cancelledBy,
      cancelledByName: cancelledByName,
      cancelFood: cancelFood,
    );
    if (tableId >= 1 && tableId <= kStandardTableCount) {
      // Removing the place must also remove any spare row that carried its
      // standard label, or deleting a renamed table leaves a ghost "مێز N" card
      // behind for the cashier to click on by mistake. Same range check as the
      // restore, because [standardLabelRowId] only means anything for a place.
      await db.delete(
        'tables',
        where: 'id = ?',
        whereArgs: [standardLabelRowId(tableId)],
      );
      await ensureStandardTables();
    }
    _bumpOrders();
    _emitMutation('deleteTable', {'tableId': tableId});
  }

  /// The label a place carries before anyone renames it.
  ///
  /// One definition, because three things have to agree on it: the rows the
  /// database seeds, the spare row [_syncStandardLabelRow] puts back after a
  /// rename, and the tests that pin what the default actually reads.
  static String standardTableName(int placeId) => 'مێز $placeId';

  /// The spare row that carries place [placeId]'s standard label once the place
  /// itself has been renamed to something else.
  ///
  /// Derived from the place rather than from the current largest id on purpose:
  /// every till in the restaurant runs this same line of code on the same rename,
  /// and a "largest + 1" would let two devices that happened to be in different
  /// states invent two different rows for the same place, so the floors would
  /// quietly double up instead of agreeing. This way they all pick the same id,
  /// and the insert is skipped outright when that row is already there.
  static int standardLabelRowId(int placeId) => kStandardTableCount + placeId;

  /// Renames a table.
  ///
  /// A standard table (1..[kStandardTableCount]) is a PLACE in the room; its name
  /// is only a label the shop sticks on that place. Renaming the first place to
  /// whatever the shop likes keeps the place - same id, same guests, same bill -
  /// and only moves the label off it. What the room then lacks is that standard
  /// label, so it is handed back to the floor as a spare, empty row of its own:
  /// there is still a plain table 1 to seat at the top of the grid.
  ///
  /// The spare is empty, so nothing anybody ordered ever moves. The renamed table
  /// keeps seating its guests under its new name, and the spare waits empty
  /// beside it. Renaming the place back onto its own standard label takes the
  /// spare away again - two cards reading the same would be a duplicate for a
  /// cashier to seat somebody at by mistake.
  ///
  /// The same repair runs on every other device, because the synced apply path
  /// calls this same method, and it lands on the same ids there, so the floors
  /// agree.
  Future<void> renameTable(int tableId, String newName) async {
    await db.update(
      'tables',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [tableId],
    );
    if (tableId >= 1 && tableId <= kStandardTableCount) {
      await _syncStandardLabelRow(tableId, newName);
      await ensureStandardTables();
    }
    _bumpOrders();
    _emitMutation('renameTable', {'tableId': tableId, 'name': newName});
  }

  /// Keeps exactly one row carrying place [placeId]'s standard label.
  ///
  /// A rename away from that label hands the floor an empty spare row under
  /// [standardLabelRowId]; a rename back onto it removes the spare. The insert is
  /// guarded on that id being free, so running this twice - locally, and again
  /// when the same rename arrives from another device - leaves one spare, not
  /// two.
  Future<void> _syncStandardLabelRow(int placeId, String newName) async {
    final twinId = standardLabelRowId(placeId);
    if (newName.trim() == standardTableName(placeId)) {
      // The place reads as its own standard label again, so the spare has
      // nothing left to stand in for.
      await db.delete('tables', where: 'id = ?', whereArgs: [twinId]);
      return;
    }
    if (await isTableIdTaken(twinId)) return;
    await db.insert('tables', {
      'id': twinId,
      'name': standardTableName(placeId),
      'status': TableStatus.empty.index,
      'seatedTime': '',
      'waiterId': '',
      'totalAmount': 0.0,
      'guestCount': 0,
      'sentToCashier': 0,
      'note': '',
      'createdBy': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateTableNote(int tableId, String note,
      {String? noteUpdatedAt}) async {
    // An emptied note keeps no date; it is no longer shown anywhere.
    final updatedAt = note.trim().isEmpty
        ? ''
        : (noteUpdatedAt ?? DateTime.now().toIso8601String());
    await db.update(
      'tables',
      {'note': note, 'noteUpdatedAt': updatedAt},
      where: 'id = ?',
      whereArgs: [tableId],
    );
    _emitMutation('updateTableNote', {
      'tableId': tableId,
      'note': note,
      'noteUpdatedAt': updatedAt,
    });
  }

  Future<void> occupyTable(
    int tableId,
    String waiterId, {
    int guestCount = 1,
  }) async {
    final existing = await getTable(tableId);
    if (existing != null && existing.status != TableStatus.empty) {
      await db.update(
        'tables',
        {'waiterId': waiterId.isNotEmpty ? waiterId : existing.waiterId},
        where: 'id = ?',
        whereArgs: [tableId],
      );
    } else {
      await db.update(
        'tables',
        {
          'status': TableStatus.occupied.index,
          'seatedTime': DateTime.now().toIso8601String(),
          'waiterId': waiterId,
          'guestCount': guestCount,
          'sentToCashier': 0,
          // Record the first person to seat this table. Parsed from the id the
          // seat-and-order paths already carry, so opening a table does not need
          // a new argument threaded through every caller.
          'openedBy': int.tryParse(waiterId) ?? 0,
        },
        where: 'id = ?',
        whereArgs: [tableId],
      );
    }
    // A table that just filled up looks different on every screen showing the
    // floor, whether it was seated here or on the captain's own device.
    _bumpOrders();
    _emitMutation('occupyTable', {
      'tableId': tableId,
      'waiterId': waiterId,
      'guestCount': guestCount,
    });
  }

  Future<void> freeTable(int tableId) async {
    await db.update(
      'tables',
      {
        'status': TableStatus.empty.index,
        'seatedTime': '',
        'waiterId': '',
        'totalAmount': 0.0,
        'guestCount': 0,
        'sentToCashier': 0,
        'openedBy': 0,
      },
      where: 'id = ?',
      whereArgs: [tableId],
    );
    try {
      await db.update(
        'tables',
        {'printedAt': ''},
        where: 'id = ?',
        whereArgs: [tableId],
      );
    } catch (_) {}
    await db.delete('order_items', where: 'tableId = ?', whereArgs: [tableId]);
    await db.delete(
      'order_delivery',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    await _clearTableNotifications(tableId);
    // Every open screen is showing this table's items and total, and both just
    // changed - including screens on other devices, once this reaches them.
    _bumpOrders();
    _emitMutation('freeTable', {'tableId': tableId});
  }

  Future<void> _clearTableNotifications(int tableId) async {
    try {
      await db.delete(
        'table_notifications',
        where: 'tableId = ?',
        whereArgs: [tableId],
      );
      onTableNotification?.call();
    } catch (_) {}
  }

  Future<void> clearTableNotifications(int tableId) async {
    await _clearTableNotifications(tableId);
  }

  /// Puts a table in the cashier's «ئاگەدارکردنەوەی مێز» panel.
  ///
  /// This is the ONLY way a table gets into that panel: the captain presses the
  /// 🔔 «ئاگەدارکردنەوە» button on the table, and it shows up on the cashier's
  /// main tab. Nothing enters it automatically - not seating a guest, not a
  /// merge, not a transfer. The cashier's queue is exactly what a captain asked
  /// for and nothing else.
  Future<void> notifyTable(int tableId) async {
    try {
      final existing = await db.query(
        'table_notifications',
        where: 'tableId = ?',
        whereArgs: [tableId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await db.update(
          'table_notifications',
          {'openedAt': DateTime.now().toIso8601String()},
          where: 'tableId = ?',
          whereArgs: [tableId],
        );
      } else {
        await db.insert('table_notifications', {
          'tableId': tableId,
          'openedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {}
    onTableNotification?.call();
    _emitMutation('notifyTable', {'tableId': tableId});
  }

  Future<List<TableNotification>> getTableNotifications() async {
    final maps = await db.rawQuery(
      'SELECT n.id as nid, n.tableId as tableId, n.openedAt as openedAt, '
      't.name as tableName, t.status as status, t.totalAmount as totalAmount '
      'FROM table_notifications n INNER JOIN tables t ON t.id = n.tableId '
      'WHERE t.status != ? '
      'ORDER BY n.openedAt DESC',
      [TableStatus.empty.index],
    );
    return maps.map((m) => TableNotification.fromMap(m)).toList();
  }

  Future<void> settleTable(
    int tableId,
    double totalAmount,
    double discountPercent,
    double discountAmount,
    int settledBy, {
    int shiftId = 0,
    String paymentMethod = 'cash',
  }) async {
    final table = await getTable(tableId);
    if (table == null) return;
    final items = await getOrderItems(tableId);
    final now = DateTime.now().toIso8601String();
    final orderId = await db.insert('settled_orders', {
      'tableId': tableId,
      'tableName': table.name,
      'totalAmount': totalAmount,
      'discountPercent': discountPercent,
      'discountAmount': discountAmount,
      'settledAt': now,
      'settledBy': settledBy,
      'shiftId': shiftId,
      'seatedAt': table.seatedTime,
      'paymentMethod': paymentMethod,
      'waiterId': table.waiterId,
      'note': table.note,
    });
    for (final item in items) {
      await db.insert('settled_order_items', {
        'settledOrderId': orderId,
        'itemName': item.name,
        'itemPrice': item.price,
        'quantity': item.quantity,
        'category': item.category,
        'waiterName': item.waiterName,
        'waiterRole': item.waiterRole,
      });
    }
    _emitMutation('settleTable', {
      'tableId': tableId,
      'totalAmount': totalAmount,
      'discountPercent': discountPercent,
      'discountAmount': discountAmount,
      'settledBy': settledBy,
      'shiftId': shiftId,
      'paymentMethod': paymentMethod,
      // Full settled order + items so every device (admin included) sees the
      // exact same settlement, and the device-independent shift key so the
      // order is linked to the matching shift on every device.
      'shiftKey': await _shiftKeyFor(shiftId),
      'order': {
        'id': orderId,
        'tableId': tableId,
        'tableName': table.name,
        'totalAmount': totalAmount,
        'discountPercent': discountPercent,
        'discountAmount': discountAmount,
        'settledAt': now,
        'settledBy': settledBy,
        'shiftId': shiftId,
        'seatedAt': table.seatedTime,
        'paymentMethod': paymentMethod,
        'waiterId': table.waiterId,
        'note': table.note,
      },
      'items': items
          .map(
            (item) => {
              'itemName': item.name,
              'itemPrice': item.price,
              'quantity': item.quantity,
              'category': item.category,
              'waiterName': item.waiterName,
              'waiterRole': item.waiterRole,
            },
          )
          .toList(),
    });
    await freeTable(tableId);
  }

  Future<void> requestBill(int tableId) async {
    await db.update(
      'tables',
      {
        'status': TableStatus.billRequested.index,
        'sentToCashier': 1,
        'printedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [tableId],
    );
    // The bell is the whole point: the cashier's floor has to light up the
    // moment a captain presses it on their own device.
    _bumpOrders();
    _emitMutation('requestBill', {'tableId': tableId});
  }

  Future<void> markAsPrinted(int tableId) async {
    final now = DateTime.now().toIso8601String();
    await db.update(
      'tables',
      {'status': TableStatus.billRequested.index, 'printedAt': now},
      where: 'id = ?',
      whereArgs: [tableId],
    );
    _bumpOrders();
    _emitMutation('markAsPrinted', {'tableId': tableId});
  }

  /// How long a printed bill may sit unpaid before its table is flagged.
  ///
  /// The shop's rule is 10 MINUTES from the print. The blue card is a working
  /// colour, not a warning: the bill is in the customer's hands and the table is
  /// being paid. Only after ten minutes of that does the cashier want the table
  /// flagged red, so a bill that never reaches the till stands out on the floor.
  ///
  /// Counted in SECONDS on purpose, and that is the point of the unit. This
  /// began as `billOverdueMinutes = 10` compared with `inMinutes`, which
  /// truncates, so a bill could turn anywhere from 10 to 11 minutes after the
  /// print; a spell at ten seconds compared with `inSeconds` was the
  /// over-correction. Ten minutes written in seconds is exact, and it stays one
  /// named constant - the only place to change if the shop picks another window.
  static const int billOverdueSeconds = 600;

  Future<void> checkOverdueTables() async {
    final now = DateTime.now();
    final requested = await db.query(
      'tables',
      where: 'status = ?',
      whereArgs: [TableStatus.billRequested.index],
    );
    for (final map in requested) {
      final printedAtStr = map['printedAt'] as String? ?? '';
      // A table that was asked about but never printed carries no clock: the
      // countdown belongs to the print, not to the request.
      if (printedAtStr.isEmpty) continue;
      final printedAt = DateTime.tryParse(printedAtStr);
      if (printedAt != null &&
          now.difference(printedAt).inSeconds >= billOverdueSeconds) {
        await db.update(
          'tables',
          {'status': TableStatus.overdue.index},
          where: 'id = ?',
          whereArgs: [map['id']],
        );
        _bumpOrders();
        _emitMutation('markOverdue', {'tableId': map['id']});
      }
    }
  }

  Future<void> markOverdue(int tableId) async {
    await db.update(
      'tables',
      {'status': TableStatus.overdue.index},
      where: 'id = ?',
      whereArgs: [tableId],
    );
    _bumpOrders();
    _emitMutation('markOverdue', {'tableId': tableId});
  }

  Future<List<OrderItem>> getOrderItems(int tableId) async {
    final maps = await db.query(
      'order_items',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    return maps.map((m) => OrderItem.fromMap(m)).toList();
  }

  /// The floor rule for a bill that is already out: another dish goes on the
  /// same account, so the table is not finished any more.
  ///
  /// A table whose bill was printed is blue, and one whose bill sat unpaid turns
  /// red. As soon as more food lands on it, either colour goes back to the
  /// working green and the print clock is cleared - otherwise a dish ordered
  /// after the bill would be born already overdue. The cashier prints the bill
  /// again once the customer is really done.
  ///
  /// [txn] lets a caller that is already inside a transaction reuse its handle.
  /// A table that is empty or simply occupied is left alone, so seating a table
  /// and topping up a green table never change colour.
  Future<void> _reopenBilledTable(int tableId, {DatabaseExecutor? txn}) async {
    final executor = txn ?? db;
    final rows = await executor.query(
      'tables',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [tableId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final status = rows.first['status'] as int?;
    if (status != TableStatus.billRequested.index &&
        status != TableStatus.overdue.index) {
      return;
    }
    await executor.update(
      'tables',
      {'status': TableStatus.occupied.index, 'printedAt': ''},
      where: 'id = ?',
      whereArgs: [tableId],
    );
  }

  /// Fills in an order line's `createdAt` when the caller left it empty, and
  /// returns the copy that carries it. The SAME copy has to be both stored and
  /// broadcast: `createdAt` is what a later rejection keys on to recognise the
  /// dish across devices (see [removeOrderItem]), so if this device stamped its
  /// own clock while the receiving device stamped another, the two copies of one
  /// order line would look like two different dishes and a phantom would survive
  /// the «ڕەتکراوەکان» dedup.
  OrderItem _stampOrderItem(OrderItem item, String now) =>
      item.createdAt.isEmpty ? item.copyWith(createdAt: now) : item;

  Future<void> addOrderItem(int tableId, OrderItem item) async {
    final now = DateTime.now().toIso8601String();
    final resolved = _stampOrderItem(item, now);
    await db.transaction((txn) async {
      await txn.insert('order_items', {
        'id': resolved.id,
        'tableId': tableId,
        'name': resolved.name,
        'price': resolved.price,
        'quantity': resolved.quantity,
        'category': resolved.category,
        'createdAt': resolved.createdAt,
        'waiterName': resolved.waiterName,
        'waiterRole': resolved.waiterRole,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await _reopenBilledTable(tableId, txn: txn);
      await _recalculateTotalInTxn(txn, tableId);
    });
    _bumpOrders();
    _emitMutation('addOrderItem', {
      'tableId': tableId,
      'item': resolved.toMap(),
    });
  }

  Future<void> batchAddOrderItems(int tableId, List<OrderItem> items) async {
    final nowStr = DateTime.now().toIso8601String();
    // One stamp for the whole batch, applied to every line that arrived without
    // one - and carried on the broadcast too, so every device agrees on the
    // order line's `createdAt` (see [_stampOrderItem]).
    final resolved = items.map((i) => _stampOrderItem(i, nowStr)).toList();
    await db.transaction((txn) async {
      for (final item in resolved) {
        await txn.insert('order_items', {
          'id': item.id,
          'tableId': tableId,
          'name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'category': item.category,
          'createdAt': item.createdAt,
          'waiterName': item.waiterName,
          'waiterRole': item.waiterRole,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await _reopenBilledTable(tableId, txn: txn);
      await _recalculateTotalInTxn(txn, tableId);
    });
    _bumpOrders();
    _emitMutation('batchAddOrderItems', {
      'tableId': tableId,
      'items': resolved.map((e) => e.toMap()).toList(),
    });
  }

  Future<void> batchSendAndOccupy(
    int tableId,
    List<OrderItem> items, {
    int guestCount = 1,
    String waiterId = '',
  }) async {
    final table = await getTable(tableId);
    final isEmpty = table == null || table.status == TableStatus.empty;
    final now = DateTime.now();
    final nowStr = now.toIso8601String();
    // Minted once, at capture, and carried on every resend so the server can
    // tell "the same order again" from "a second, identical order".
    final batchId = const Uuid().v4();
    // Resolve `createdAt` once for the whole batch and use the SAME list for the
    // local insert and the broadcast, so a receiving device stores the identical
    // timestamp instead of stamping its own (see [_stampOrderItem]).
    final resolved = items.map((i) => _stampOrderItem(i, nowStr)).toList();
    await db.transaction((txn) async {
      if (isEmpty) {
        await txn.update(
          'tables',
          {
            'status': TableStatus.occupied.index,
            'seatedTime': nowStr,
            'waiterId': waiterId,
            'guestCount': guestCount,
            'sentToCashier': 1,
            'openedBy': int.tryParse(waiterId) ?? 0,
          },
          where: 'id = ?',
          whereArgs: [tableId],
        );
      } else {
        // More food for a table that is already open. If its bill was already
        // printed (blue) or has gone overdue (red), the extra dish re-opens the
        // account: back to the working green with the print clock cleared, so
        // the new dish is not already counted as overdue. A table that is simply
        // occupied stays occupied.
        final wasBilled =
            table.status == TableStatus.billRequested ||
            table.status == TableStatus.overdue;
        await txn.update(
          'tables',
          {
            'sentToCashier': 1,
            if (wasBilled) 'status': TableStatus.occupied.index,
            if (wasBilled) 'printedAt': '',
          },
          where: 'id = ?',
          whereArgs: [tableId],
        );
      }
      for (final item in resolved) {
        // The item's UUID is its identity: an identical resend cannot double.
        await txn.insert('order_items', {
          'id': item.id,
          'tableId': tableId,
          'name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'category': item.category,
          'createdAt': item.createdAt,
          'waiterName': item.waiterName,
          'waiterRole': item.waiterRole,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      // The total is computed from the items in the SAME transaction that wrote
      // them, so a crash can never leave a table whose food is saved but whose
      // money is stale.
      await _recalculateTotalInTxn(txn, tableId);
    });
    _bumpOrders();
    _emitMutation('batchSendAndOccupy', {
      'batchId': batchId,
      'tableId': tableId,
      'items': resolved.map((e) => e.toMap()).toList(),
      'guestCount': guestCount,
      'waiterId': waiterId,
    });
  }

  Future<void> replaceTableItems(
    int tableId,
    List<OrderItem> items, {
    String waiterId = '',
  }) async {
    final now = DateTime.now();
    final nowStr = now.toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(
        'order_items',
        where: 'tableId = ?',
        whereArgs: [tableId],
      );
      for (final item in items) {
        final itemNow = item.createdAt.isNotEmpty ? item.createdAt : nowStr;
        await txn.insert('order_items', {
          'id': item.id,
          'tableId': tableId,
          'name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'category': item.category,
          'createdAt': itemNow,
          'waiterName': item.waiterName,
          'waiterRole': item.waiterRole,
        });
      }
      final updateMap = <String, dynamic>{'sentToCashier': 1};
      if (waiterId.isNotEmpty) updateMap['waiterId'] = waiterId;
      await txn.update(
        'tables',
        updateMap,
        where: 'id = ?',
        whereArgs: [tableId],
      );
    });
    await _recalculateTotal(tableId);
  }

  Future<void> updateOrderItemQuantity(
    int tableId,
    String itemId,
    int quantity,
  ) async {
    await db.transaction((txn) async {
      await txn.update(
        'order_items',
        {'quantity': quantity},
        where: 'id = ? AND tableId = ?',
        whereArgs: [itemId, tableId],
      );
      await _recalculateTotalInTxn(txn, tableId);
    });
    _bumpOrders();
    _emitMutation('updateItemQuantity', {
      'tableId': tableId,
      'itemId': itemId,
      'quantity': quantity,
    });
  }

  /// Throws one line off an order and keeps it on the discarded-items page.
  ///
  /// The audit line is written whatever the caller knows about the user. It
  /// used to be skipped when no id was available, which meant a rejected dish
  /// could disappear with nobody's name on it - and "nobody's name" is not the
  /// same as "nobody did it". The columns default to 0 and '', which read as an
  /// unknown hand rather than a missing record.
  ///
  /// [recordCancellation] is false when this call is replaying a *remote*
  /// `removeOrderItem` mutation. The deleting device sends the audit row itself
  /// (as a `cancelledOrderItem` mutation, emitted before this one), so writing
  /// the cancellation again on the receiving device stamped a second row with
  /// that device's own clock - a different key, so the dedup could not collapse
  /// it and the captain's «ڕەتکراوەکان» showed every rejected dish twice.
  Future<void> removeOrderItem(
    int tableId,
    String itemId, {
    int cancelledBy = 0,
    String cancelledByName = '',
    bool recordCancellation = true,
  }) async {
    if (recordCancellation) {
      try {
        final item = await getOrderItem(tableId, itemId);
        if (item != null) {
          final table = await getTable(tableId);
          await recordCancelledItem(
            tableId: tableId,
            tableName: table?.name ?? tableId.toString(),
            itemName: item.name,
            price: item.price,
            quantity: item.quantity,
            category: item.category,
            cancelledBy: cancelledBy,
            cancelledByName: cancelledByName,
            requestedByName: item.waiterName,
            requestedAt: item.createdAt,
          );
        }
      } catch (_) {}
    }
    await db.transaction((txn) async {
      await txn.delete(
        'order_items',
        where: 'id = ? AND tableId = ?',
        whereArgs: [itemId, tableId],
      );
      await _recalculateTotalInTxn(txn, tableId);
    });
    _bumpOrders();
    final remaining = await getOrderItems(tableId);
    _emitMutation('removeOrderItem', {'tableId': tableId, 'itemId': itemId});
    if (remaining.isEmpty) {
      await freeTable(tableId);
    }
  }

  Future<OrderItem?> getOrderItem(int tableId, String itemId) async {
    final maps = await db.query(
      'order_items',
      where: 'tableId = ? AND id = ?',
      whereArgs: [tableId, itemId],
    );
    if (maps.isEmpty) return null;
    return OrderItem.fromMap(maps.first);
  }

  // ==================== Cancelled Items ====================

  /// The shift that a rejection should be filed under: the acting user's own
  /// open shift if there is one, otherwise the most recently started open shift
  /// on this device (a captain rejecting has no shift of their own, but the
  /// cashier's is the right home for it).
  ///
  /// Returns the whole row so the caller can stamp both the local `shiftId` and
  /// the device-independent (cashierId, startedAt) key onto the record.
  Future<Map<String, dynamic>?> _activeShiftRowFor(int by) async {
    var shifts = await db.query(
      'cashier_shifts',
      where: 'cashierId = ? AND endedAt = ?',
      whereArgs: [by, ''],
      // A cashier normally has at most one open shift, but a crash mid-shift can
      // leave a stale row behind. Ordering by the newest start makes the stamp
      // land on the shift actually running now instead of whichever row SQLite
      // happens to return first.
      orderBy: 'startedAt DESC',
      limit: 1,
    );
    if (shifts.isEmpty) {
      shifts = await db.query(
        'cashier_shifts',
        where: 'endedAt = ?',
        whereArgs: [''],
        orderBy: 'startedAt DESC',
        limit: 1,
      );
    }
    if (shifts.isEmpty) return null;
    return shifts.first;
  }

  Future<void> recordCancelledItem({
    required int tableId,
    required String tableName,
    required String itemName,
    required double price,
    required int quantity,
    required String category,
    required int cancelledBy,
    String cancelledByName = '',
    String requestedByName = '',
    String requestedAt = '',
  }) async {
    final shift = await _activeShiftRowFor(cancelledBy);
    final map = {
      'shiftId': shift?['id'] as int? ?? 0,
      // The pair below names the SAME shift on every device; the numeric
      // `shiftId` only means anything on the device that wrote it.
      'shiftCashierId': shift?['cashierId'] as int? ?? 0,
      'shiftStartedAt': shift?['startedAt'] as String? ?? '',
      'tableId': tableId,
      'tableName': tableName,
      'itemName': itemName,
      'itemPrice': price,
      'quantity': quantity,
      'category': category,
      'cancelledAt': DateTime.now().toIso8601String(),
      'cancelledBy': cancelledBy,
      'cancelledByName': cancelledByName,
      'requestedByName': requestedByName,
      // When the dish was first ordered onto the table, so the record answers
      // "when was it ordered" as well as "when was it cancelled". Comes from
      // the order row's own createdAt - the ring-in moment, not this event.
      'requestedAt': requestedAt,
      // Who ordered it (captain or cashier), resolved from the users table so
      // the cancelled record names the role as well as the person. 0 is the
      // waiter/captain role, 1 cashier; unknown hands keep 0 with no name.
      'requestedByRole': await _requestedByRoleFor(requestedByName),
      'status': 'pending',
      'servedAt': '',
    };
    await addCancelledItem(map);
    _emitMutation('cancelledOrderItem', map);
  }

  /// The role of the person who ordered a dish, looked up by name from the
  /// local users table (users sync across devices like every other row).
  ///
  /// Only a role tells the «ڕەتکراوەکان» record who actually sat the dish:
  /// "کاپتن ئاراس" vs "کاشێر شیلان" are both possible and a bare name cannot
  /// tell them apart. Unknown names (off-device staff, old records) stay 0.
  Future<int> _requestedByRoleFor(String name) async {
    if (name.isEmpty) return 0;
    final rows = await db.query(
      'users',
      columns: ['role'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['role'] as num?)?.toInt() ?? 0;
  }

  /// Identifies one rejection event on every device. `cancelledAt` is the exact
  /// ISO second the till stamped it, so the same dish by the same cashier on
  /// the same table twice within that same second is not a real case - which is
  /// what makes the field set safe to collapse on. The row id is deliberately
  /// not in the key: each device assigns its own, so it names nothing on a
  /// foreign one.
  String _cancelledDedupKey(Map<String, dynamic> m) {
    final price = (m['itemPrice'] as num?)?.toDouble();
    return [
      '${m['cancelledAt']}',
      '${m['tableId']}',
      '${m['itemName']}',
      price?.toString() ?? '',
      '${m['cancelledBy']}',
      '${m['quantity']}',
    ].join('|');
  }

  /// The *order line* a rejection came off, independent of who re-audited it and
  /// when the second copy was stamped.
  ///
  /// One order line can be rejected exactly once - it is deleted from the table
  /// by the same action - so two pending rows that share this tuple are
  /// necessarily one rejection recorded twice. That is the damage the pre-fix
  /// remote `removeOrderItem` left behind (see [removeOrderItem]): its phantom
  /// copy carries `cancelledBy == 0` but the same dish, table, quantity and
  /// requester as the real record.
  ///
  /// `requestedAt` is deliberately NOT part of the key. It is the order line's
  /// `createdAt`, and the old build stamped that separately on each device (the
  /// cart left it empty and both ends filled in their own clock), so the two
  /// copies of one line could disagree on it. Keying on it meant the phantom was
  /// never recognised and the captain's «ڕەتکراوەکان» kept showing one rejected
  /// dish twice. What still ties the copies together is the dish itself plus the
  /// person who ordered it.
  String _cancelledSourceKey(Map<String, dynamic> m) {
    final price = (m['itemPrice'] as num?)?.toDouble();
    return [
      '${m['tableId']}',
      '${m['itemName']}',
      price?.toString() ?? '',
      '${m['quantity']}',
      '${m['requestedByName']}',
    ].join('\u0001');
  }

  DateTime? _cancelledStamp(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

  String _cancelledDedupKeyWhere() =>
      'cancelledAt = ? AND tableId = ? AND itemName = ? AND itemPrice = ? '
      'AND cancelledBy = ? AND quantity = ?';

  List<Object?> _cancelledDedupKeyArgs(Map<String, dynamic> m) => [
    m['cancelledAt'],
    m['tableId'],
    m['itemName'],
    m['itemPrice'],
    m['cancelledBy'],
    m['quantity'],
  ];

  Future<void> addCancelledItem(Map<String, dynamic> map) async {
    final m = Map<String, dynamic>.from(map);
    m.remove('id');
    // The same rejection can land here more than once - the till's broadcast
    // plus a relayed copy, or a reconnect flush - but it has to exist in the
    // queue exactly once. Without this, a captain's «ڕەتکراوەکان» listed every
    // rejected dish 3-4 times, all of them copies of the single rejection the
    // till made. Any status matches, not just `pending`: a buffered re-delivery
    // arriving after the cashier already moved the dish back must not resurrect
    // it as a fresh pending row.
    final existing = await db.query(
      'cancelled_items',
      columns: ['id'],
      where: _cancelledDedupKeyWhere(),
      whereArgs: _cancelledDedupKeyArgs(m),
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert('cancelled_items', m);
    // A rejected dish is an order change, so every open screen on this device -
    // and every captain watching their own «ڕەتکراوەکان» queue - has to hear about
    // it. This is the single insert point, local or arriving from the cashier's
    // device, so bumping here covers both.
    _bumpOrders();
  }

  /// Every shift window on this device, newest start first, as the raw rows the
  /// cancelled-queue and shift-report scoping both read.
  Future<List<Map<String, Object?>>> _shiftWindows() => db.query(
        'cashier_shifts',
        columns: ['id', 'cashierId', 'startedAt', 'endedAt'],
        orderBy: 'startedAt DESC',
      );

  /// The shift a keyless rejection belongs to, resolved by time: the latest
  /// shift that had started when the dish was thrown out and had not yet ended.
  ///
  /// `cancelled_items` written before the device-independent key existed carry
  /// only the per-device `shiftId`, a number that names an unrelated shift - or
  /// nothing - on any other device (see [getCancelledItemsByShift]). The
  /// rejection's own timestamp, read against the shift windows here, recovers
  /// the owner without trusting that number. A null result means no shift was
  /// open then (a captain rejecting with the till shut), which keeps the row.
  Map<String, Object?>? _keylessOwnerShift(
    String cancelledAt,
    List<Map<String, Object?>> shifts,
  ) {
    final at = DateTime.tryParse(cancelledAt);
    if (at == null) return null;
    for (final s in shifts) {
      final start = DateTime.tryParse('${s['startedAt']}');
      if (start == null || start.isAfter(at)) continue;
      final endRaw = '${s['endedAt']}';
      if (endRaw.isNotEmpty) {
        final end = DateTime.tryParse(endRaw);
        if (end != null && end.isBefore(at)) continue;
      }
      // `shifts` is newest-start first, so the first window that covers the
      // rejection is the one that was running when it happened.
      return s;
    }
    return null;
  }

  /// Whether a rejection has left the live «ڕەتکراوەکان» queue because the shift
  /// it belongs to is closed on this device.
  ///
  /// A keyed row answers directly from its device-independent
  /// (`shiftCashierId`, `shiftStartedAt`) pair. A keyless row (written before
  /// v41) is placed by time and hidden only when that shift is positively known
  /// to be closed here; a rejection with no shift - or one this device has never
  /// heard of - stays, because hiding a real rejection is worse than showing a
  /// stale one.
  bool _isCancelledRowStale(
    Map<String, Object?> row,
    List<Map<String, Object?>> shifts,
  ) {
    final keyCashier = (row['shiftCashierId'] as num?)?.toInt() ?? 0;
    final keyStart = '${row['shiftStartedAt']}';
    if (keyCashier > 0 && keyStart.isNotEmpty) {
      for (final s in shifts) {
        if ((s['cashierId'] as num?)?.toInt() == keyCashier &&
            '${s['startedAt']}' == keyStart) {
          return '${s['endedAt']}'.isNotEmpty;
        }
      }
      return false;
    }
    final owner = _keylessOwnerShift('${row['cancelledAt']}', shifts);
    return owner != null && '${owner['endedAt']}'.isNotEmpty;
  }

  /// «ڕەتکراوەکان»: what was thrown out and has not been put back yet.
  ///
  /// Scoped to the shift each rejection belongs to (see [recordCancelledItem]):
  /// a rejection is audited against the shift that was open when it happened, so
  /// closing that shift takes its leftovers out of this queue and the next shift
  /// starts with an empty «ڕەتکراوەکان». A row whose shift is not known on this
  /// device is still shown: hiding a real rejection is worse than showing a
  /// stale one.
  Future<List<CancelledItem>> getPendingCancelledItems() async {
    // A rejection leaves the queue only when its OWN shift is positively known
    // to be closed on this device (see [_isCancelledRowStale]). The old query
    // hid a rejection whenever its numeric `shiftId` matched ANY closed shift
    // here, so a till id that collided with an unrelated local shift erased a
    // live rejection from the captain's list - and a rejection foreign to this
    // device was shown or hidden by a number that names nothing here.
    final maps = await db.rawQuery(
      "SELECT c.* FROM cancelled_items c WHERE c.status = 'pending' "
      "ORDER BY c.cancelledAt DESC",
    );
    final shifts = await _shiftWindows();
    final visible = maps.where((m) => !_isCancelledRowStale(m, shifts));
    // Heal queues that were corrupted before the dedup above landed: a device
    // that was served the same rejection several times can still be holding
    // 2-4 copies per dish. Collapse them here and drop the stragglers so the
    // captain's list is already clean when they open it - not only from the
    // next rejection on.
    final seen = <String>{};
    final strayIds = <int>[];
    final unique = <Map<String, dynamic>>[];
    for (final row in visible) {
      if (!seen.add(_cancelledDedupKey(row))) {
        strayIds.add(row['id'] as int);
        continue;
      }
      unique.add(row);
    }
    // Second heal, for the regression the dedup above cannot see: the old
    // remote `removeOrderItem` re-audited one order line, so the phantom copy
    // shares the real one's dish and requester but not its
    // `cancelledAt`/`cancelledBy` (and, on the old build, not its `requestedAt`
    // either - see [_cancelledSourceKey]). Group by the order line and, when a
    // group holds one named record plus anonymous copies, keep the named one:
    // the anonymous copies can only be that same rejection recorded again. The
    // time guard keeps two genuinely different rejections of one dish - hours
    // apart - from being folded together.
    final bySource = <String, List<Map<String, dynamic>>>{};
    for (final row in unique) {
      bySource.putIfAbsent(_cancelledSourceKey(row), () => <Map<String, dynamic>>[]).add(row);
    }
    for (final group in bySource.values) {
      if (group.length < 2) continue;
      final named = group.where((r) => ((r['cancelledBy'] as num?) ?? 0) != 0);
      if (named.length != 1) continue;
      final keep = named.first;
      final keepAt = _cancelledStamp(keep['cancelledAt']);
      for (final row in group) {
        if (row['id'] == keep['id']) continue;
        final rowAt = _cancelledStamp(row['cancelledAt']);
        final close = keepAt == null ||
            rowAt == null ||
            keepAt.difference(rowAt).inMinutes.abs() <= 10;
        if (close) strayIds.add(row['id'] as int);
      }
    }
    final straySet = strayIds.toSet();
    for (final id in strayIds) {
      await db.delete('cancelled_items', where: 'id = ?', whereArgs: [id]);
    }
    return unique
        .where((m) => !straySet.contains(m['id']))
        .map((m) => CancelledItem.fromMap(m))
        .toList();
  }

  /// Every rejection filed under one shift, for the shift report.
  ///
  /// A rejection names its shift two ways: the per-device auto-increment
  /// `shiftId` (which only means anything on the device that wrote it) and the
  /// device-independent `(shiftCashierId, shiftStartedAt)` key. On the till both
  /// agree, so the old `WHERE shiftId = ?` looked right there - but it is
  /// exactly wrong on EVERY OTHER device. The admin's own `cashier_shifts` rows
  /// carry their own auto-increment ids, so the shift the till filed under id 1
  /// can be id 5 here; matching on that id then finds nothing and the shift
  /// report's «ڕەتکراوەکان» is empty even though the rejections are on the device.
  ///
  /// So the key is the truth: a row that carries one is matched by the key alone,
  /// never by an id that could collide with an unrelated shift here and pull a
  /// stranger's rejection into this report. A row written before the key existed
  /// (v41) is placed by the time window it falls in - the same rule the live
  /// queue uses - and only falls back to its stored local id when no window
  /// covers it.
  Future<List<CancelledItem>> getCancelledItemsByShift(int shiftId) async {
    final shifts = await _shiftWindows();
    Map<String, Object?>? shift;
    for (final s in shifts) {
      if ((s['id'] as num?)?.toInt() == shiftId) {
        shift = s;
        break;
      }
    }
    final cashierId =
        shift == null ? 0 : (shift['cashierId'] as num?)?.toInt() ?? 0;
    final startedAt = shift == null ? '' : '${shift['startedAt']}';

    final maps = await db.query('cancelled_items', orderBy: 'cancelledAt DESC');
    bool belongs(Map<String, Object?> m) {
      final keyCashier = (m['shiftCashierId'] as num?)?.toInt() ?? 0;
      final keyStart = '${m['shiftStartedAt']}';
      if (keyCashier > 0 && keyStart.isNotEmpty) {
        return cashierId > 0 && keyCashier == cashierId && keyStart == startedAt;
      }
      final owner = _keylessOwnerShift('${m['cancelledAt']}', shifts);
      if (owner != null) return (owner['id'] as num?)?.toInt() == shiftId;
      // No window covers the row (an old record, or a rejection while no shift
      // was open): its stored local id is the only handle left.
      return ((m['shiftId'] as num?)?.toInt() ?? 0) == shiftId;
    }

    return maps.where(belongs).map((m) => CancelledItem.fromMap(m)).toList();
  }

  Future<List<CancelledItem>> getCancelledItemsByDateRange(
    String start,
    String end,
  ) async {
    final maps = await db.query(
      'cancelled_items',
      where: 'cancelledAt >= ? AND cancelledAt <= ?',
      whereArgs: [start, end],
      orderBy: 'cancelledAt DESC',
    );
    return maps.map((m) => CancelledItem.fromMap(m)).toList();
  }

  Future<void> markCancelledItemServed(
    int id, {
    String cancelledAt = '',
    int tableId = 0,
    String itemName = '',
    double itemPrice = 0,
    int cancelledBy = 0,
    int quantity = 0,
  }) async {
    final served = {
      'status': 'served',
      'servedAt': DateTime.now().toIso8601String(),
    };
    // The till's own row id only exists on the till, so a served mutation that
    // matches by id alone could never find this device's copy of the record.
    // The record's own fields travel with the mutation and name the same
    // rejection on every device, so they are the authoritative match; the id
    // stays as the fallback for callers (and old peers) that only know their
    // own row.
    if (cancelledAt.isNotEmpty) {
      await db.update(
        'cancelled_items',
        served,
        where: _cancelledDedupKeyWhere(),
        whereArgs: [
          cancelledAt,
          tableId,
          itemName,
          itemPrice,
          cancelledBy,
          quantity,
        ],
      );
    } else {
      await db.update(
        'cancelled_items',
        served,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    // The row leaves the queue, so the count every captain is watching drops by
    // one without anybody pulling to refresh.
    _bumpOrders();
    _emitMutation(
      'markCancelledItemServed',
      {
        'id': id,
        'cancelledAt': cancelledAt,
        'tableId': tableId,
        'itemName': itemName,
        'itemPrice': itemPrice,
        'cancelledBy': cancelledBy,
        'quantity': quantity,
      },
    );
  }

  /// Rewrites a table's total from its items and tells every open screen about
  /// it.
  ///
  /// The bump belongs here rather than in each caller: every single path that
  /// adds, removes or changes an item ends in this method, so this is the one
  /// place that cannot be forgotten. It fires whether the change came from
  /// someone tapping on this device or from a captain's order arriving over the
  /// link, which is exactly the case that used to leave the cashier looking at a
  /// stale food list and a zero total for an order that had already been rung in.
  Future<void> _recalculateTotal(int tableId) async {
    final items = await getOrderItems(tableId);
    final total = items.fold<double>(
      0,
      (sum, item) => sum + (item.price * item.quantity),
    );
    await db.update(
      'tables',
      {'totalAmount': total},
      where: 'id = ?',
      whereArgs: [tableId],
    );
    _bumpOrders();
  }

  /// Recomputes a table's total on the caller's transaction handle.
  ///
  /// Must be used instead of [_recalculateTotal] from inside a transaction: the
  /// latter takes a second connection, and sqflite serialises a single
  /// connection, so querying `db` while a transaction is open is how a total
  /// recalculation deadlocks the app. The bump is left to the caller so it can
  /// fire once, after the transaction commits.
  Future<void> _recalculateTotalInTxn(DatabaseExecutor txn, int tableId) async {
    final rows = await txn.query(
      'order_items',
      columns: ['price', 'quantity'],
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    final total = rows.fold<double>(
      0,
      (sum, r) => sum + ((r['price'] as num) * (r['quantity'] as num)),
    );
    await txn.update(
      'tables',
      {'totalAmount': total},
      where: 'id = ?',
      whereArgs: [tableId],
    );
  }

  /// Empties the dining room, leaving live delivery orders untouched for the
  /// same reason as [resetTablesToRange]: clearing the floor of the restaurant
  /// is not a reason to throw away an order that is still out for delivery.
  Future<void> clearAllTables() async {
    final cleared = <String, Object?>{
      'status': TableStatus.empty.index,
      'seatedTime': '',
      'waiterId': '',
      'totalAmount': 0.0,
      'guestCount': 0,
      'sentToCashier': 0,
      'printedAt': '',
      'openedBy': 0,
    };
    await db.update(
      'tables',
      cleared,
      where: 'isDelivery = 0 OR isDelivery IS NULL',
    );
    await db.delete(
      'order_items',
      where: 'tableId NOT IN (SELECT id FROM tables WHERE isDelivery = 1)',
    );
    _bumpOrders();
  }

  // Builds the authoritative state snapshot (tables + all order items + the
  // user registry) that a newly connected device applies so it sees the exact
  // same table states and the same accounts.
  Future<Map<String, dynamic>> buildSnapshot() async {
    final tables = await getAllTables(includeDelivery: true);
    final rawItems = await db.query('order_items');
    final items = <String, List<Map<String, dynamic>>>{};
    for (final row in rawItems) {
      final key = '${row['tableId']}';
      (items[key] ??= []).add(Map<String, dynamic>.from(row));
    }
    final users = (await getAllUsers()).map((u) => u.toMap()).toList();
    final deliveryCompanies = (await getDeliveryCompanies())
        .map((c) => c.toMap())
        .toList();
    final foodCategories = await db.query(
      'food_categories',
      orderBy: 'sortOrder ASC',
    );
    final foodItems = await db.query(
      'food_items',
      orderBy: 'sortOrder ASC, id ASC',
    );
    final shifts = (await getAllShifts()).map((s) => s.toMap()).toList();
    // The admin's dollar rate rides along with the snapshot so a cashier device
    // that was switched off (or offline) when the rate changed still reads the
    // new one the moment it reconnects, instead of showing yesterday's figure
    // until somebody happens to re-save it.
    final rate = await getDollarRate();
    return {
      'tables': tables.map((t) => t.toMap()).toList(),
      'items': items,
      'users': users,
      'delivery_companies': deliveryCompanies,
      'food_categories': foodCategories,
      'food_items': foodItems,
      'cashier_shifts': shifts,
      'dollar_rate': rate.toMap(),
    };
  }

  // Applies a server snapshot: table rows are upserted (server authoritative),
  // missing order items are inserted (local offline items are kept so queued
  // orders are never lost), users are upserted so the registry converges on
  // every device, then totals are recomputed. Local-only accounts are never
  // deleted here - deletions travel through USER_DELETED mutations only.
  // The food menu (categories + items, added by the admin) and cashier shifts
  // are also upserted so a device that was offline while the admin edited the
  // menu catches up on the next (re)connect.
  Future<void> applySnapshot(Map<String, dynamic> data) async {
    final tableMaps = (data['tables'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final itemsMap = (data['items'] as Map? ?? {});
    final userMaps = (data['users'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final companyMaps = (data['delivery_companies'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final foodCategoryMaps = (data['food_categories'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final foodItemMaps = (data['food_items'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final shiftMaps = (data['cashier_shifts'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final rateMap = (data['dollar_rate'] as Map?) == null
        ? null
        : Map<String, dynamic>.from(data['dollar_rate'] as Map);
    await db.transaction((txn) async {
      // Tables with an offline change still waiting to flush keep their local
      // state. The server does not know about that order yet, so applying its
      // (older) table row would blank the table the captain is standing at,
      // and the flush would then re-occupy it a moment later - a visible
      // flicker at best, a lost seating at worst.
      final pendingTableIds = <int>{};
      final pendingRows = await txn.query(
        'pending_sync',
        columns: ['data'],
        where: 'status = 0',
      );
      for (final row in pendingRows) {
        try {
          final decoded =
              jsonDecode(row['data'] as String) as Map<String, dynamic>;
          final pendingTableId = decoded['tableId'] as int?;
          if (pendingTableId != null && pendingTableId > 0) {
            pendingTableIds.add(pendingTableId);
          }
        } catch (_) {}
      }
      for (final map in tableMaps) {
        final tableId = map['id'] as int? ?? 0;
        if (tableId <= 0) continue;
        if (pendingTableIds.contains(tableId)) continue;
        final updated = await txn.update(
          'tables',
          map,
          where: 'id = ?',
          whereArgs: [tableId],
        );
        if (updated == 0) {
          await txn.insert('tables', map);
        }
      }
      for (final entry in itemsMap.entries) {
        final tableId = int.tryParse('${entry.key}') ?? 0;
        if (tableId <= 0) continue;
        final rows = (entry.value as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        for (final row in rows) {
          final existing = await txn.query(
            'order_items',
            where: 'id = ? AND tableId = ?',
            whereArgs: [row['id'], tableId],
            limit: 1,
          );
          if (existing.isEmpty) {
            await txn.insert('order_items', row);
          }
        }
      }
      for (final map in userMaps) {
        final userId = map['id'] as int? ?? 0;
        if (userId <= 0) continue;
        final updated = await txn.update(
          'users',
          map,
          where: 'id = ?',
          whereArgs: [userId],
        );
        if (updated == 0) {
          await txn.insert(
            'users',
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      // Delivery companies are upserted (never wholesale-replaced) so a
      // company added offline on this device survives a server snapshot.
      // Deletions travel through DELIVERY_COMPANY_DELETED mutations only.
      // Read the columns once for the whole bar: a hub on a newer build sends
      // fields this device does not have, and one unknown column would throw
      // the statement and roll back every other table in this transaction.
      final companyColumns = await _tableColumns(txn, 'delivery_companies');
      for (final map in companyMaps) {
        final companyId = map['id'] as int? ?? 0;
        if (companyId <= 0) continue;
        final row = _restrictToColumns(map, companyColumns);
        final updated = await txn.update(
          'delivery_companies',
          row,
          where: 'id = ?',
          whereArgs: [companyId],
        );
        if (updated == 0) {
          await txn.insert(
            'delivery_companies',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    for (final map in tableMaps) {
      final tableId = map['id'] as int? ?? 0;
      if (tableId > 0) {
        await _recalculateTotal(tableId);
      }
    }
    if (companyMaps.isNotEmpty) _bumpDeliveryCompanies();
    if (userMaps.isNotEmpty) _bumpUsers();
    // Food menu (admin-authoritative) and cashier shifts are upserted per-row
    // after the transaction (same semantics as the live mutations, so they are
    // never echoed back and never throw inside the snapshot transaction).
    for (final map in foodCategoryMaps) {
      await applyRemoteFoodCategory(map);
    }
    for (final map in foodItemMaps) {
      await applyRemoteFoodItem(map);
    }
    for (final map in shiftMaps) {
      await applyRemoteShift(map);
    }
    // The rate is applied through the same remote path as the live mutation, so
    // a snapshot never echoes one back out to the devices it just came from.
    if (rateMap != null) {
      await applyDollarRate(DollarRate.fromMap(rateMap));
    }
    // A snapshot carries whatever tables the other device has - which can be a
    // room with holes in it if that device deleted a table before the restore
    // rule existed. Re-check the standard range so this device never inherits
    // a missing table.
    await ensureStandardTables();
    onTableNotification?.call();
  }

  // Computes the target table's state update after items move between tables.
  // The destination keeps the "hottest" state carried from either side
  // (empty < occupied < billRequested < overdue) so a transfer never
  // downgrades or artificially escalates a live state. A green occupied
  // table therefore stays green, while a real bill request (blue/overdue)
  // survives the transfer together with its printedAt for the overdue timer.
  Map<String, dynamic> _transferStateUpdate(TableModel? from, TableModel? to) {
    final update = <String, dynamic>{};
    final fromStatus = from?.status ?? TableStatus.empty;
    final toStatus = to?.status ?? TableStatus.empty;
    final carriedIndex = fromStatus.index > toStatus.index
        ? fromStatus.index
        : toStatus.index;
    final carriedStatus = TableStatus.values[carriedIndex];
    final billCarried =
        carriedStatus == TableStatus.billRequested ||
        carriedStatus == TableStatus.overdue;
    final needsAttention =
        from?.sentToCashier == true || to?.sentToCashier == true || billCarried;

    if (to != null) {
      if (toStatus == TableStatus.empty) {
        update['status'] = carriedStatus.index;
        update['seatedTime'] = DateTime.now().toIso8601String();
        update['waiterId'] = from?.waiterId ?? '';
        update['guestCount'] = (from?.guestCount ?? 0) < 1
            ? 1
            : from!.guestCount;
        update['sentToCashier'] = needsAttention ? 1 : 0;
        update['printedAt'] = billCarried
            ? ((from?.printedAt.isNotEmpty ?? false)
                  ? from!.printedAt
                  : DateTime.now().toIso8601String())
            : '';
      } else if (carriedIndex > toStatus.index) {
        update['status'] = carriedStatus.index;
        update['sentToCashier'] = needsAttention ? 1 : 0;
        update['printedAt'] = billCarried
            ? ((from?.printedAt.isNotEmpty ?? false)
                  ? from!.printedAt
                  : (to.printedAt.isNotEmpty
                        ? to.printedAt
                        : DateTime.now().toIso8601String()))
            : to.printedAt;
      } else if (needsAttention && !to.sentToCashier) {
        update['sentToCashier'] = 1;
      }
    }
    return update;
  }

  Future<void> transferItems(int fromTableId, int toTableId) async {
    if (fromTableId == toTableId) return;
    final items = await getOrderItems(fromTableId);
    if (items.isEmpty) return;
    await db.transaction((txn) async {
      for (final item in items) {
        await txn.delete(
          'order_items',
          where: 'id = ? AND tableId = ?',
          whereArgs: [item.id, fromTableId],
        );
        await txn.insert('order_items', {
          'id': item.id,
          'tableId': toTableId,
          'name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'category': item.category,
          'createdAt': item.createdAt,
          'waiterName': item.waiterName,
          'waiterRole': item.waiterRole,
        });
      }
    });
    final fromTable = await getTable(fromTableId);
    final toTable = await getTable(toTableId);
    final tUpdate = _transferStateUpdate(fromTable, toTable);
    if (tUpdate.isNotEmpty) {
      await db.update(
        'tables',
        tUpdate,
        where: 'id = ?',
        whereArgs: [toTableId],
      );
    }
    await _recalculateTotal(fromTableId);
    await _recalculateTotal(toTableId);
    await db.update(
      'tables',
      {
        'status': TableStatus.empty.index,
        'seatedTime': '',
        'waiterId': '',
        'totalAmount': 0.0,
        'guestCount': 0,
        'sentToCashier': 0,
        'printedAt': '',
        'openedBy': 0,
      },
      where: 'id = ?',
      whereArgs: [fromTableId],
    );
    await db.delete(
      'order_delivery',
      where: 'tableId = ?',
      whereArgs: [fromTableId],
    );
    await _clearTableNotifications(fromTableId);
    _emitMutation('transferItems', {
      'fromTableId': fromTableId,
      'toTableId': toTableId,
    });
  }

  Future<void> transferSingleItem(
    int fromTableId,
    int toTableId,
    String itemId,
  ) async {
    if (fromTableId == toTableId) return;
    final item = (await getOrderItems(
      fromTableId,
    )).where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    await db.delete(
      'order_items',
      where: 'id = ? AND tableId = ?',
      whereArgs: [itemId, fromTableId],
    );
    await db.insert('order_items', {
      'id': item.id,
      'tableId': toTableId,
      'name': item.name,
      'price': item.price,
      'quantity': item.quantity,
      'category': item.category,
      'createdAt': item.createdAt,
      'waiterName': item.waiterName,
      'waiterRole': item.waiterRole,
    });
    final toTable = await getTable(toTableId);
    final fromTable = await getTable(fromTableId);
    final tUpdate = _transferStateUpdate(fromTable, toTable);
    if (tUpdate.isNotEmpty) {
      await db.update(
        'tables',
        tUpdate,
        where: 'id = ?',
        whereArgs: [toTableId],
      );
    }
    await _recalculateTotal(fromTableId);
    await _recalculateTotal(toTableId);
    final remaining = await getOrderItems(fromTableId);
    if (remaining.isEmpty) {
      await db.update(
        'tables',
        {
          'status': TableStatus.empty.index,
          'seatedTime': '',
          'waiterId': '',
          'totalAmount': 0.0,
          'guestCount': 0,
          'sentToCashier': 0,
          'printedAt': '',
          'openedBy': 0,
        },
        where: 'id = ?',
        whereArgs: [fromTableId],
      );
      await db.delete(
        'order_delivery',
        where: 'tableId = ?',
        whereArgs: [fromTableId],
      );
      await _clearTableNotifications(fromTableId);
    }
    _emitMutation('transferSingleItem', {
      'fromTableId': fromTableId,
      'toTableId': toTableId,
      'itemId': itemId,
    });
  }

  Future<void> mergeTables(int sourceTableId, int targetTableId) async {
    if (sourceTableId == targetTableId) return;
    final sourceItems = await getOrderItems(sourceTableId);
    if (sourceItems.isEmpty) return;
    final sourceTable = await getTable(sourceTableId);
    final targetTable = await getTable(targetTableId);
    if (targetTable == null) return;
    await db.transaction((txn) async {
      for (final item in sourceItems) {
        await txn.delete(
          'order_items',
          where: 'id = ? AND tableId = ?',
          whereArgs: [item.id, sourceTableId],
        );
        await txn.insert('order_items', {
          'id': item.id,
          'tableId': targetTableId,
          'name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'category': item.category,
          'createdAt': item.createdAt,
          'waiterName': item.waiterName,
          'waiterRole': item.waiterRole,
        });
      }
      if (sourceTable != null && sourceTable.status != TableStatus.empty) {
        final mergedGuests =
            (targetTable.guestCount) + (sourceTable.guestCount);
        final mergedWaiter = targetTable.waiterId.isNotEmpty
            ? targetTable.waiterId
            : sourceTable.waiterId;
        final state = _transferStateUpdate(sourceTable, targetTable);
        if (targetTable.status == TableStatus.empty) {
          await txn.update(
            'tables',
            {
              ...state,
              'seatedTime': sourceTable.seatedTime.isNotEmpty
                  ? sourceTable.seatedTime
                  : targetTable.seatedTime,
              'waiterId': mergedWaiter,
              'guestCount': mergedGuests,
            },
            where: 'id = ?',
            whereArgs: [targetTableId],
          );
        } else {
          await txn.update(
            'tables',
            {...state, 'guestCount': mergedGuests},
            where: 'id = ?',
            whereArgs: [targetTableId],
          );
        }
        await txn.update(
          'tables',
          {
            'status': TableStatus.empty.index,
            'seatedTime': '',
            'waiterId': '',
            'totalAmount': 0.0,
            'guestCount': 0,
            'sentToCashier': 0,
            'printedAt': '',
            'openedBy': 0,
          },
          where: 'id = ?',
          whereArgs: [sourceTableId],
        );
        await txn.delete(
          'order_delivery',
          where: 'tableId = ?',
          whereArgs: [sourceTableId],
        );
      }
    });
    await _recalculateTotal(targetTableId);
    await _recalculateTotal(sourceTableId);
    await _clearTableNotifications(sourceTableId);
    _emitMutation('mergeTables', {
      'sourceTableId': sourceTableId,
      'targetTableId': targetTableId,
    });
  }

  // ==================== Printers ====================

  Future<List<PrinterConfig>> getAllPrinters() async {
    final maps = await db.query('printer_configs', orderBy: 'id ASC');
    return maps.map((m) => PrinterConfig.fromMap(m)).toList();
  }

  Future<PrinterConfig?> getPrinterByType(PrinterType type) async {
    final maps = await db.query(
      'printer_configs',
      where: 'printerType = ?',
      whereArgs: [type.index],
    );
    if (maps.isEmpty) return null;
    final defaultOne = maps.where((m) => m['isDefault'] == 1).firstOrNull;
    return PrinterConfig.fromMap(defaultOne ?? maps.first);
  }

  Future<int> addPrinter(PrinterConfig config) async {
    return await db.insert('printer_configs', config.toMap());
  }

  Future<void> updatePrinter(PrinterConfig config) async {
    await db.update(
      'printer_configs',
      config.toMap(),
      where: 'id = ?',
      whereArgs: [config.id],
    );
  }

  Future<void> deletePrinter(int id) async {
    await db.delete('printer_configs', where: 'id = ?', whereArgs: [id]);
    await db.delete(
      'category_printer_mappings',
      where: 'printerConfigId = ?',
      whereArgs: [id],
    );
    await db.delete(
      'item_printer_overrides',
      where: 'printerConfigId = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, PrinterType>> getCategoryPrinterMappings() async {
    final maps = await db.query('category_printer_mappings');
    final map = <String, PrinterType>{};
    for (final m in maps) {
      final printerMaps = await db.query(
        'printer_configs',
        where: 'id = ?',
        whereArgs: [m['printerConfigId']],
      );
      if (printerMaps.isNotEmpty) {
        final printer = PrinterConfig.fromMap(printerMaps.first);
        map[m['category'] as String] = printer.printerType;
      }
    }
    return map;
  }

  Future<void> setCategoryPrinterMapping(
    String category,
    int printerConfigId,
  ) async {
    await db.insert('category_printer_mappings', {
      'category': category,
      'printerConfigId': printerConfigId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeCategoryPrinterMapping(String category) async {
    await db.delete(
      'category_printer_mappings',
      where: 'category = ?',
      whereArgs: [category],
    );
  }

  Future<Map<String, PrinterType>> getItemPrinterOverrides() async {
    final maps = await db.query('item_printer_overrides');
    final map = <String, PrinterType>{};
    for (final m in maps) {
      final printerMaps = await db.query(
        'printer_configs',
        where: 'id = ?',
        whereArgs: [m['printerConfigId']],
      );
      if (printerMaps.isNotEmpty) {
        final printer = PrinterConfig.fromMap(printerMaps.first);
        map[m['itemName'] as String] = printer.printerType;
      }
    }
    return map;
  }

  Future<void> setItemPrinterOverride(
    String itemName,
    int printerConfigId,
  ) async {
    await db.insert('item_printer_overrides', {
      'itemName': itemName,
      'printerConfigId': printerConfigId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeItemPrinterOverride(String itemName) async {
    await db.delete(
      'item_printer_overrides',
      where: 'itemName = ?',
      whereArgs: [itemName],
    );
  }

  Future<Map<String, List<PrinterType>>> getAllItemPrinterAssignments() async {
    final maps = await db.query('item_printer_assignments');
    final result = <String, List<PrinterType>>{};
    for (final map in maps) {
      final name = map['itemName'] as String;
      final raw = map['printerType'] as int;
      if (raw < 0 || raw >= PrinterType.values.length) continue;
      final type = PrinterType.values[raw];
      result.putIfAbsent(name, () => []).add(type);
    }
    return result;
  }

  Future<void> setItemPrinterAssignments(
    String itemName,
    List<PrinterType> types,
  ) async {
    await db.delete(
      'item_printer_assignments',
      where: 'itemName = ?',
      whereArgs: [itemName],
    );
    for (final type in types) {
      await db.insert('item_printer_assignments', {
        'itemName': itemName,
        'printerType': type.index,
      });
    }
  }

  // ==================== Settled Orders ====================

  Future<int> addSettledOrder(SettledOrder order) async {
    final id = await db.insert('settled_orders', order.toMap());
    return id;
  }

  Future<void> addSettledOrderItems(
    int settledOrderId,
    List<OrderItem> items,
  ) async {
    for (final item in items) {
      await db.insert('settled_order_items', {
        'settledOrderId': settledOrderId,
        'itemName': item.name,
        'itemPrice': item.price,
        'quantity': item.quantity,
        'category': item.category,
        'waiterName': item.waiterName,
        'waiterRole': item.waiterRole,
      });
    }
  }

  Future<List<SettledOrder>> getSettledOrdersByDateRange(
    String from,
    String to,
  ) async {
    final maps = await db.query(
      'settled_orders',
      where: 'settledAt >= ? AND settledAt <= ?',
      whereArgs: [from, to],
      orderBy: 'settledAt DESC',
    );
    return maps.map((m) => SettledOrder.fromMap(m)).toList();
  }

  Future<List<SettledOrder>> getAllSettledOrders() async {
    final maps = await db.query('settled_orders', orderBy: 'settledAt DESC');
    return maps.map((m) => SettledOrder.fromMap(m)).toList();
  }

  Future<List<SettledOrderItem>> getSettledOrderItems(
    int settledOrderId,
  ) async {
    final maps = await db.query(
      'settled_order_items',
      where: 'settledOrderId = ?',
      whereArgs: [settledOrderId],
    );
    return maps.map((m) => SettledOrderItem.fromMap(m)).toList();
  }

  /// Every dish line of the given settled orders, in one query.
  ///
  /// The captain report credits a dish to whoever rang it in, so it needs the
  /// lines of the whole shift while only holding the orders; asking
  /// `getSettledOrderItems` once per order turned a busy shift into a burst of
  /// round-trips, so the ids go out together.
  Future<List<SettledOrderItem>> getSettledOrderItemsByOrderIds(
    List<int> orderIds,
  ) async {
    if (orderIds.isEmpty) return const [];
    final placeholders = List.filled(orderIds.length, '?').join(',');
    final maps = await db.rawQuery(
      'SELECT * FROM settled_order_items '
      'WHERE settledOrderId IN ($placeholders)',
      orderIds,
    );
    return maps.map((m) => SettledOrderItem.fromMap(m)).toList();
  }

  /// Every dish line of every settled order in a shift, fetched in one query.
  ///
  /// The shift's "داواکاری خواردن" tab needs all of them at once; asking
  /// `getSettledOrderItems` once per order turned a busy shift into a burst of
  /// round-trips and made the tab linger on its spinner. One join keeps it to a
  /// single query no matter how many orders the shift closed.
  Future<List<SettledOrderItem>> getSettledOrderItemsByShiftId(
    int shiftId,
  ) async {
    final maps = await db.rawQuery(
      'SELECT i.* FROM settled_order_items i '
      'INNER JOIN settled_orders o ON o.id = i.settledOrderId '
      'WHERE o.shiftId = ?',
      [shiftId],
    );
    return maps.map((m) => SettledOrderItem.fromMap(m)).toList();
  }

  Future<double> getTotalSettledInRange(String from, String to) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(totalAmount), 0) as total FROM settled_orders WHERE settledAt >= ? AND settledAt <= ?',
      [from, to],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<double> getSettledElectronicInRange(String from, String to) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(totalAmount), 0) as total FROM settled_orders WHERE settledAt >= ? AND settledAt <= ? AND paymentMethod IN ('fib','fastpay','superqi','zincash','nass','switch')",
      [from, to],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<double> getSettledCashPlusElectronicInRange(String from, String to) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(totalAmount), 0) as total FROM settled_orders WHERE settledAt >= ? AND settledAt <= ? AND paymentMethod NOT IN ('debt')",
      [from, to],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<double> getCashierExpensesTotalInRange(String from, String to) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(price), 0) as total FROM cashier_expenses WHERE createdAt >= ? AND createdAt <= ?',
      [from, to],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<List<SettledOrder>> getSettledOrdersByTableId(int tableId) async {
    final maps = await db.query(
      'settled_orders',
      where: 'tableId = ?',
      whereArgs: [tableId],
      orderBy: 'settledAt DESC',
    );
    return maps.map((m) => SettledOrder.fromMap(m)).toList();
  }

  Future<List<SettledOrder>> getSettledOrdersByShiftId(int shiftId) async {
    final maps = await db.query(
      'settled_orders',
      where: 'shiftId = ?',
      whereArgs: [shiftId],
      orderBy: 'settledAt DESC',
    );
    return maps.map((m) => SettledOrder.fromMap(m)).toList();
  }

  Future<double> getSettledOrdersTotalByShiftId(int shiftId) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(totalAmount), 0) as total FROM settled_orders WHERE shiftId = ?',
      [shiftId],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<double> getSettledCashLikeTotalByShiftId(int shiftId) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(totalAmount), 0) as total FROM settled_orders WHERE shiftId = ? AND paymentMethod IN ('cash', 'debt')",
      [shiftId],
    );
    return (result.first['total'] as num).toDouble();
  }

  // ==================== Cashier Shifts ====================

  Future<int> startShift(CashierShift shift) async {
    final map = shift.toMap();
    if (map['id'] == 0) map.remove('id');
    final id = await db.insert('cashier_shifts', map);
    _bumpShifts();
    // Broadcast the full row (incl. the auto-assigned id) so the admin can see
    // this shift on every device - even when the laptop was turned off and the
    // shift started entirely offline (the mutation flushes on reconnect).
    final rows = await db.query(
      'cashier_shifts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) _emitMutation('SHIFT_STARTED', {'shift': rows.first});
    return id;
  }

  Future<void> endShift(int id, String endTime, double collected) async {
    await db.update(
      'cashier_shifts',
      {'endedAt': endTime, 'totalCollected': collected},
      where: 'id = ?',
      whereArgs: [id],
    );
    _bumpShifts();
    final rows = await db.query(
      'cashier_shifts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) _emitMutation('SHIFT_ENDED', {'shift': rows.first});
    // Record which tables were left sitting with an open bill when the till was
    // locked up. This runs AFTER the end mutation so a device receiving both
    // has the shift row first and can attach the snapshot to it. Purely an
    // admin-facing record: the tables themselves are never touched.
    await captureRemainingTables(id);
  }

  /// Snapshots every dining table still seated (occupied, so un-settled) at the
  /// moment a shift closes.
  ///
  /// The rows keep what the table had - its dishes, waiter, seated time and
  /// note - so the admin's shift report can show what was left behind. Nothing
  /// here settles, frees or reprices a table: the snapshot is informational
  /// only and never counts into the shift's money. A shift that already has a
  /// snapshot keeps it, so a double close can never duplicate the record.
  Future<void> captureRemainingTables(int shiftId) async {
    if (shiftId <= 0) return;
    try {
      final already = await db.query(
        'shift_remaining_tables',
        columns: ['id'],
        where: 'shiftId = ?',
        whereArgs: [shiftId],
        limit: 1,
      );
      if (already.isNotEmpty) return;

      // Delivery slots live in the same `tables` table but are not tables in
      // the dining room, so they are left out of the report.
      final rows = await db.query(
        'tables',
        where: "(isDelivery = 0 OR isDelivery IS NULL) AND status != ?",
        whereArgs: [TableStatus.empty.index],
      );
      if (rows.isEmpty) return;

      final shiftKey = await _shiftKeyFor(shiftId);
      final now = DateTime.now().toIso8601String();
      final captured = <Map<String, dynamic>>[];
      for (final row in rows) {
        final tableId = row['id'] as int? ?? 0;
        if (tableId <= 0) continue;
        final waiterId = row['waiterId'] as String? ?? '';
        final items = await getOrderItems(tableId);
        final map = <String, dynamic>{
          'shiftId': shiftId,
          'shiftCashierId': shiftKey['cashierId'] as int? ?? 0,
          'shiftStartedAt': shiftKey['startedAt'] as String? ?? '',
          'tableId': tableId,
          'tableName': row['name'] as String? ?? '',
          'guestCount': row['guestCount'] as int? ?? 0,
          'seatedAt': row['seatedTime'] as String? ?? '',
          'waiterId': waiterId,
          'waiterName': await _waiterNameFor(waiterId),
          'note': row['note'] as String? ?? '',
          'totalAmount': (row['totalAmount'] as num?)?.toDouble() ?? 0,
          'itemsJson': encodeRemainingTableItems(items),
          'createdAt': now,
        };
        final id = await db.insert('shift_remaining_tables', map);
        map['id'] = id;
        captured.add(map);
      }
      if (captured.isEmpty) return;
      _emitMutation('SHIFT_REMAINING_TABLES', {
        'tables': captured,
        if (shiftKey.isNotEmpty) 'shiftKey': shiftKey,
      });
    } catch (_) {
      // The snapshot is a convenience for the report; it must never stop a
      // shift from closing, so a failure here is swallowed.
    }
  }

  /// Resolves a `tables.waiterId` (stored as the user id string) to the name the
  /// report should show, or an empty string when the person is unknown.
  Future<String> _waiterNameFor(String waiterId) async {
    final id = int.tryParse(waiterId) ?? 0;
    if (id <= 0) return '';
    final user = await getUserById(id);
    return user?.name ?? '';
  }

  /// The tables left un-settled when [shiftId] closed, newest snapshot first.
  Future<List<RemainingTable>> getRemainingTablesByShift(int shiftId) async {
    if (shiftId <= 0) return const [];
    final maps = await db.query(
      'shift_remaining_tables',
      where: 'shiftId = ?',
      whereArgs: [shiftId],
      orderBy: 'tableId ASC',
    );
    return maps.map((m) => RemainingTable.fromMap(m)).toList();
  }

  /// Applies a remaining-tables snapshot sent by another device, re-linking it
  /// to the matching shift on THIS device via the device-independent shift key.
  Future<void> applyRemoteRemainingTables(
    List<Map<String, dynamic>> tables, {
    Map<String, dynamic>? shiftKey,
  }) async {
    final localShiftId = await resolveShiftIdByKey(shiftKey);
    if (localShiftId == null) return;
    for (final map in tables) {
      final raw = Map<String, dynamic>.from(map);
      final tableId = raw['tableId'] as int? ?? 0;
      if (tableId <= 0) continue;
      final existing = await db.query(
        'shift_remaining_tables',
        columns: ['id'],
        where: 'shiftId = ? AND tableId = ?',
        whereArgs: [localShiftId, tableId],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      raw['shiftId'] = localShiftId;
      raw.remove('id');
      await db.insert('shift_remaining_tables', raw);
    }
  }

  Future<CashierShift?> getActiveShift(int cashierId) async {
    final maps = await db.query(
      'cashier_shifts',
      where: 'cashierId = ? AND endedAt = ?',
      whereArgs: [cashierId, ''],
    );
    if (maps.isEmpty) return null;
    return CashierShift.fromMap(maps.first);
  }

  Future<List<CashierShift>> getAllShifts() async {
    final maps = await db.query('cashier_shifts', orderBy: 'startedAt DESC');
    return maps.map((m) => CashierShift.fromMap(m)).toList();
  }

  // ==================== Cashier Shifts (remote sync) ====================

  /// Maps a LOCAL shift id to its device-independent key (cashierId + startedAt)
  /// so remote devices can attach expenses / refunds / settlements to the SAME
  /// shift even though auto-increment ids differ per device.
  Future<Map<String, dynamic>> _shiftKeyFor(int shiftId) async {
    if (shiftId <= 0) return const {};
    final rows = await db.query(
      'cashier_shifts',
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    if (rows.isEmpty) return const {};
    return {
      'cashierId': rows.first['cashierId'] as int? ?? 0,
      'startedAt': rows.first['startedAt'] as String? ?? '',
    };
  }

  /// Resolves a device-independent shift key to THIS device's shift id, or
  /// `null` when the shift has not reached this device yet.
  Future<int?> resolveShiftIdByKey(Map<String, dynamic>? key) async {
    if (key == null) return null;
    final cashierId = key['cashierId'] as int? ?? 0;
    final startedAt = key['startedAt'] as String? ?? '';
    if (cashierId <= 0 || startedAt.isEmpty) return null;
    final rows = await db.query(
      'cashier_shifts',
      where: 'cashierId = ? AND startedAt = ?',
      whereArgs: [cashierId, startedAt],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int? ?? 0;
  }

  /// Upserts a shift received from another device (mutation or snapshot),
  /// matched by (cashierId, startedAt) so start/end updates always reach the
  /// same shift regardless of per-device auto-increment ids.
  Future<void> applyRemoteShift(Map<String, dynamic> map) async {
    final cashierId = map['cashierId'] as int? ?? 0;
    final startedAt = map['startedAt'] as String? ?? '';
    if (cashierId <= 0 || startedAt.isEmpty) return;
    final rows = await db.query(
      'cashier_shifts',
      where: 'cashierId = ? AND startedAt = ?',
      whereArgs: [cashierId, startedAt],
      limit: 1,
    );
    if (rows.isEmpty) {
      final insert = Map<String, dynamic>.from(map);
      final remoteId = insert['id'] as int? ?? 0;
      if (remoteId > 0) {
        final taken = await db.query(
          'cashier_shifts',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [remoteId],
          limit: 1,
        );
        if (taken.isNotEmpty) insert.remove('id');
      } else {
        insert.remove('id');
      }
      await db.insert(
        'cashier_shifts',
        insert,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      final rowId = rows.first['id'] as int? ?? 0;
      if (rowId > 0) {
        await db.update(
          'cashier_shifts',
          {
            'cashierId': cashierId,
            'cashierName': map['cashierName'] as String? ?? '',
            'startedAt': startedAt,
            'endedAt': map['endedAt'] as String? ?? '',
            'totalCollected': (map['totalCollected'] as num?)?.toDouble() ?? 0,
          },
          where: 'id = ?',
          whereArgs: [rowId],
        );
      }
    }
    _bumpShifts();
  }

  /// Applies a cashier expense sent by another device, re-linking it to the
  /// matching shift on THIS device via the device-independent shift key.
  Future<void> applyRemoteExpense(
    Map<String, dynamic> map, {
    Map<String, dynamic>? shiftKey,
  }) async {
    int shiftId = map['shiftId'] as int? ?? 0;
    final localShiftId = await resolveShiftIdByKey(shiftKey);
    if (localShiftId != null) shiftId = localShiftId;
    if (shiftId <= 0) return;
    final itemName = map['itemName'] as String? ?? '';
    final price = (map['price'] as num?)?.toDouble() ?? 0;
    final createdAt = map['createdAt'] as String? ?? '';
    if (itemName.isEmpty || createdAt.isEmpty) return;
    final existing = await db.query(
      'cashier_expenses',
      where: 'shiftId = ? AND itemName = ? AND createdAt = ? AND price = ?',
      whereArgs: [shiftId, itemName, createdAt, price],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert('cashier_expenses', {
      'shiftId': shiftId,
      'itemName': itemName,
      'price': price,
      'createdAt': createdAt,
    });
  }

  /// Applies a refund sent by another device, re-linking it to the matching
  /// shift on THIS device via the device-independent shift key.
  Future<void> applyRemoteRefund(
    Map<String, dynamic> map, {
    Map<String, dynamic>? shiftKey,
  }) async {
    int shiftId = map['shiftId'] as int? ?? 0;
    final localShiftId = await resolveShiftIdByKey(shiftKey);
    if (localShiftId != null) shiftId = localShiftId;
    final tableId = map['tableId'] as int? ?? 0;
    final itemName = map['itemName'] as String? ?? '';
    final quantity = map['quantity'] as int? ?? 1;
    final price = (map['price'] as num?)?.toDouble() ?? 0;
    final refundedAt = map['refundedAt'] as String? ?? '';
    if (itemName.isEmpty || refundedAt.isEmpty) return;
    final existing = await db.query(
      'refunds',
      where:
          'tableId = ? AND itemName = ? AND quantity = ? AND price = ? AND refundedAt = ?',
      whereArgs: [tableId, itemName, quantity, price, refundedAt],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert('refunds', {
      'tableId': tableId,
      'itemName': itemName,
      'quantity': quantity,
      'price': price,
      'refundedAt': refundedAt,
      'refundedBy': map['refundedBy'] as int? ?? 0,
      'shiftId': shiftId,
    });
  }

  /// Applies a purchase sent by another device (deduplicated by content so a
  /// relayed mutation or snapshot never double-counts).
  Future<void> applyRemotePurchase(Map<String, dynamic> map) async {
    final itemName = map['itemName'] as String? ?? '';
    final price = (map['price'] as num?)?.toDouble() ?? 0;
    final purchasedAt = map['purchasedAt'] as String? ?? '';
    if (itemName.isEmpty || purchasedAt.isEmpty) return;
    final existing = await db.query(
      'purchases',
      where: 'itemName = ? AND price = ? AND purchasedAt = ?',
      whereArgs: [itemName, price, purchasedAt],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert('purchases', {
      'itemName': itemName,
      'price': price,
      'purchasedAt': purchasedAt,
      'purchasedBy': map['purchasedBy'] as int? ?? 0,
    });
  }

  /// Applies a settled order (with its items) sent by another device. The
  /// order is inserted with ITS ORIGINAL id when that id is still free, so all
  /// devices keep the same settled_orders identity, and its shiftId is
  /// re-mapped to this device's shift via the device-independent shift key.
  Future<void> applyRemoteSettledOrder(
    Map<String, dynamic> order, {
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? shiftKey,
  }) async {
    int shiftId = (order['shiftId'] as num?)?.toInt() ?? 0;
    final localShiftId = await resolveShiftIdByKey(shiftKey);
    if (localShiftId != null) shiftId = localShiftId;
    if (shiftId <= 0) return;
    final id = (order['id'] as num?)?.toInt() ?? 0;
    final orderMap = Map<String, dynamic>.from(order);
    orderMap['shiftId'] = shiftId;
    int settledOrderId;
    if (id > 0) {
      final taken = await db.query(
        'settled_orders',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (taken.isEmpty) {
        await db.insert(
          'settled_orders',
          orderMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        settledOrderId = id;
      } else {
        // The remote id is already used by a different local settlement - fall
        // back to a fresh local id instead of overwriting someone else's data.
        orderMap.remove('id');
        settledOrderId = await db.insert('settled_orders', orderMap);
      }
    } else {
      orderMap.remove('id');
      settledOrderId = await db.insert('settled_orders', orderMap);
    }
    for (final item in items) {
      await db.insert('settled_order_items', {
        'settledOrderId': settledOrderId,
        'itemName': item['itemName'] as String? ?? '',
        'itemPrice': (item['itemPrice'] as num?)?.toDouble() ?? 0,
        'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
        'category': item['category'] as String? ?? '',
        'waiterName': item['waiterName'] as String? ?? '',
        'waiterRole': (item['waiterRole'] as num?)?.toInt() ?? -1,
      });
    }
  }

  // ==================== Purchases ====================

  Future<int> addPurchase(Purchase purchase) async {
    final id = await db.insert('purchases', purchase.toMap());
    final map = purchase.toMap();
    map['id'] = id;
    _emitMutation('PURCHASE_CREATED', {'purchase': map});
    return id;
  }

  Future<List<Purchase>> getPurchasesByDateRange(String from, String to) async {
    final maps = await db.query(
      'purchases',
      where: 'purchasedAt >= ? AND purchasedAt <= ?',
      whereArgs: [from, to],
      orderBy: 'purchasedAt DESC',
    );
    return maps.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<List<Purchase>> getAllPurchases() async {
    final maps = await db.query('purchases', orderBy: 'purchasedAt DESC');
    return maps.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<List<Purchase>> getPurchasesInRange(String from, String to) async {
    final maps = await db.query(
      'purchases',
      where: 'purchasedAt >= ? AND purchasedAt <= ?',
      whereArgs: [from, to],
      orderBy: 'purchasedAt DESC',
    );
    return maps.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<List<CashierExpense>> getAllCashierExpenses() async {
    final maps = await db.query('cashier_expenses', orderBy: 'createdAt DESC');
    return maps.map((m) => CashierExpense.fromMap(m)).toList();
  }

  Future<List<CashierExpense>> getCashierExpensesInRange(String from, String to) async {
    final maps = await db.query(
      'cashier_expenses',
      where: 'createdAt >= ? AND createdAt <= ?',
      whereArgs: [from, to],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => CashierExpense.fromMap(m)).toList();
  }

  Future<double> getTotalPurchasesInRange(String from, String to) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(price), 0) as total FROM purchases WHERE purchasedAt >= ? AND purchasedAt <= ?',
      [from, to],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<double> getTotalRefundsInRange(String from, String to) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(price * quantity), 0) as total FROM refunds WHERE refundedAt >= ? AND refundedAt <= ?',
      [from, to],
    );
    return (result.first['total'] as num).toDouble();
  }

  Future<List<Refund>> getRefundsInRange(String from, String to) async {
    final maps = await db.query(
      'refunds',
      where: 'refundedAt >= ? AND refundedAt <= ?',
      whereArgs: [from, to],
      orderBy: 'refundedAt DESC',
    );
    return maps.map((m) => Refund.fromMap(m)).toList();
  }

  // ==================== Refunds ====================

  Future<int> addRefund(Refund refund) async {
    int shiftId = refund.shiftId;
    if (shiftId == 0) {
      final shifts = await db.query(
        'cashier_shifts',
        where: 'cashierId = ? AND endedAt = ?',
        whereArgs: [refund.refundedBy, ''],
      );
      if (shifts.isNotEmpty) {
        shiftId = shifts.first['id'] as int;
      }
    }
    final map = refund.toMap();
    map['shiftId'] = shiftId;
    final id = await db.insert('refunds', map);
    map['id'] = id;
    // Send the device-independent shift key (cashierId + startedAt) alongside
    // the refund so the receiving device attaches it to the SAME shift.
    final key = await _shiftKeyFor(shiftId);
    _emitMutation('REFUND_CREATED', {
      'refund': map,
      if (key.isNotEmpty) 'shiftKey': key,
    });
    return id;
  }

  Future<List<Refund>> getRefunds() async {
    final maps = await db.query('refunds', orderBy: 'refundedAt DESC');
    return maps.map((m) => Refund.fromMap(m)).toList();
  }

  Future<List<Refund>> getRefundsByDateRange(String from, String to) async {
    final maps = await db.query(
      'refunds',
      where: 'refundedAt >= ? AND refundedAt <= ?',
      whereArgs: [from, to],
      orderBy: 'refundedAt DESC',
    );
    return maps.map((m) => Refund.fromMap(m)).toList();
  }

  Future<List<Refund>> getRefundsByShiftId(int shiftId) async {
    final maps = await db.query(
      'refunds',
      where: 'shiftId = ?',
      whereArgs: [shiftId],
      orderBy: 'refundedAt DESC',
    );
    return maps.map((m) => Refund.fromMap(m)).toList();
  }

  // ==================== Debts ====================

  Future<int> addDebt(DebtModel debt) async {
    return await db.insert('debts', debt.toMap());
  }

  Future<List<DebtModel>> getDebts() async {
    final maps = await db.query('debts', orderBy: 'id DESC');
    return maps.map((m) => DebtModel.fromMap(m)).toList();
  }

  /// «قەرزەکان» for the till: only the debts opened under [shiftId].
  ///
  /// A debt is tied to the shift that rang it up, so a new shift - whether a
  /// different cashier or the same one back on - starts with an empty list.
  /// Pass 0 to read the debts that belong to no shift (pre-migration rows);
  /// those are deliberately not shown to a cashier whose shift has a real id.
  Future<List<DebtModel>> getDebtsByShift(int shiftId) async {
    final maps = await db.query(
      'debts',
      where: 'shiftId = ?',
      whereArgs: [shiftId],
      orderBy: 'id DESC',
    );
    return maps.map((m) => DebtModel.fromMap(m)).toList();
  }

  Future<List<DebtModel>> getDebtsByTableId(int tableId) async {
    final maps = await db.query(
      'debts',
      where: 'tableId = ?',
      whereArgs: [tableId],
      orderBy: 'id DESC',
    );
    return maps.map((m) => DebtModel.fromMap(m)).toList();
  }

  Future<void> deleteDebt(int id) async {
    await db.delete('debts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateDebtAmount(int id, double newAmount) async {
    await db.update(
      'debts',
      {'amount': newAmount},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<double> getTotalDebt() async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM debts',
    );
    return (result.first['total'] as num).toDouble();
  }

  /// The money still owed on the debts opened under [shiftId].
  ///
  /// A table moved to «قەرزەکان» writes a debt row but no settled order - the
  /// income is only recorded when the debt is collected - so this is the only
  /// place the shift report can still see that money. A debt that *was* collected
  /// already shows up as a `debt` settled order and is gone from here, so adding
  /// the two never counts the same bill twice.
  Future<double> getDebtTotalByShift(int shiftId) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM debts WHERE shiftId = ?',
      [shiftId],
    );
    return (result.first['total'] as num).toDouble();
  }

  // ==================== Cashier Expenses ====================

  Future<int> addCashierExpense(
    int shiftId,
    String itemName,
    double price,
  ) async {
    final createdAt = DateTime.now().toIso8601String();
    final id = await db.insert('cashier_expenses', {
      'shiftId': shiftId,
      'itemName': itemName,
      'price': price,
      'createdAt': createdAt,
    });
    // Send the device-independent shift key (cashierId + startedAt) alongside
    // the expense so the receiving device attaches it to the SAME shift.
    final key = await _shiftKeyFor(shiftId);
    _emitMutation('CASHIER_EXPENSE_CREATED', {
      'expense': {
        'id': id,
        'shiftId': shiftId,
        'itemName': itemName,
        'price': price,
        'createdAt': createdAt,
      },
      if (key.isNotEmpty) 'shiftKey': key,
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> getShiftExpenses(int shiftId) async {
    return await db.query(
      'cashier_expenses',
      where: 'shiftId = ?',
      whereArgs: [shiftId],
      orderBy: 'createdAt ASC',
    );
  }

  Future<double> getShiftExpensesTotal(int shiftId) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(price), 0) as total FROM cashier_expenses WHERE shiftId = ?',
      [shiftId],
    );
    return (result.first['total'] as num).toDouble();
  }

  // ==================== Food Menu ====================

  Future<List<Map<String, dynamic>>> getFoodCategories() async {
    return await db.query('food_categories', orderBy: 'sortOrder ASC');
  }

  Future<List<Map<String, dynamic>>> getFoodItems() async {
    return await db.query('food_items', orderBy: 'sortOrder ASC, id ASC');
  }

  Future<List<Map<String, dynamic>>> getFoodItemsByCategory(
    String category,
  ) async {
    return await db.query(
      'food_items',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'sortOrder ASC, id ASC',
    );
  }

  /// Reads one food category row back by id (used to broadcast the full row,
  /// including the auto-assigned id, to every device).
  Future<void> _emitFoodCategoryMutation(String action, int id) async {
    if (id <= 0) return;
    final rows = await db.query(
      'food_categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    _emitMutation(action, {'category': rows.first});
  }

  /// Reads one food item row back by id (used to broadcast the full row,
  /// including the auto-assigned id, to every device).
  Future<void> _emitFoodItemMutation(String action, int id) async {
    if (id <= 0) return;
    final rows = await db.query(
      'food_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    _emitMutation(action, {'item': rows.first});
  }

  Future<int> addFoodCategory(
    String name,
    String icon, {
    String section = '',
  }) async {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM food_categories'),
        ) ??
        0;
    final id = await db.insert('food_categories', {
      'name': name,
      'icon': icon,
      'section': section,
      'sortOrder': count,
    });
    _bumpFoodMenu();
    await _emitFoodCategoryMutation('FOOD_CATEGORY_CREATED', id);
    return id;
  }

  Future<void> updateFoodCategory(
    int id,
    String name,
    String icon, {
    String section = '',
  }) async {
    final rows = await db.query(
      'food_categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final oldName = rows.isEmpty ? null : rows.first['name'] as String;
    await db.update(
      'food_categories',
      {'name': name, 'icon': icon, 'section': section},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (oldName != null && oldName != name) {
      await db.update(
        'food_items',
        {'category': name},
        where: 'category = ?',
        whereArgs: [oldName],
      );
      await db.update(
        'category_printer_mappings',
        {'category': name},
        where: 'category = ?',
        whereArgs: [oldName],
      );
    }
    _bumpFoodMenu();
    // Include the OLD category name so remote devices can re-link their food
    // items (and printer mappings) when the category is renamed.
    final updated = await db.query(
      'food_categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (updated.isNotEmpty) {
      _emitMutation('FOOD_CATEGORY_UPDATED', {
        'category': updated.first,
        if (oldName != null && oldName != name) 'oldCategory': oldName,
      });
    }
  }

  Future<void> deleteFoodCategory(int id, String name) async {
    await db.delete('food_items', where: 'category = ?', whereArgs: [name]);
    await db.delete('food_categories', where: 'id = ?', whereArgs: [id]);
    await db.delete(
      'category_printer_mappings',
      where: 'category = ?',
      whereArgs: [name],
    );
    _bumpFoodMenu();
    _emitMutation('FOOD_CATEGORY_DELETED', {'id': id, 'name': name});
  }

  Future<int> addFoodItem(
    String name,
    double price,
    String category, {
    String imageUrl = '',
    String nameAr = '',
    String nameFa = '',
    String nameEn = '',
    String nameTr = '',
  }) async {
    final id = await db.insert('food_items', {
      'name': name,
      'price': price,
      'category': category,
      'imageUrl': imageUrl,
      'sortOrder': 0,
      'name_ar': nameAr,
      'name_fa': nameFa,
      'name_en': nameEn,
      'name_tr': nameTr,
    });
    _bumpFoodMenu();
    await _emitFoodItemMutation('FOOD_ITEM_CREATED', id);
    return id;
  }

  Future<void> updateFoodItem(
    int id,
    String name,
    double price,
    String category, {
    String imageUrl = '',
    String nameAr = '',
    String nameFa = '',
    String nameEn = '',
    String nameTr = '',
  }) async {
    final rows = await db.query(
      'food_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final oldName = rows.isEmpty ? null : rows.first['name'] as String;
    await db.update(
      'food_items',
      {
        'name': name,
        'price': price,
        'category': category,
        'imageUrl': imageUrl,
        'name_ar': nameAr,
        'name_fa': nameFa,
        'name_en': nameEn,
        'name_tr': nameTr,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (oldName != null && oldName != name) {
      await db.update(
        'item_printer_assignments',
        {'itemName': name},
        where: 'itemName = ?',
        whereArgs: [oldName],
      );
      await db.update(
        'item_printer_overrides',
        {'itemName': name},
        where: 'itemName = ?',
        whereArgs: [oldName],
      );
    }
    _bumpFoodMenu();
    await _emitFoodItemMutation('FOOD_ITEM_UPDATED', id);
  }

  Future<void> deleteFoodItem(int id) async {
    final rows = await db.query(
      'food_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final name = rows.isEmpty ? null : rows.first['name'] as String;
    await db.delete('food_items', where: 'id = ?', whereArgs: [id]);
    if (name != null) {
      await db.delete(
        'item_printer_assignments',
        where: 'itemName = ?',
        whereArgs: [name],
      );
      await db.delete(
        'item_printer_overrides',
        where: 'itemName = ?',
        whereArgs: [name],
      );
    }
    _bumpFoodMenu();
    _emitMutation('FOOD_ITEM_DELETED', {'id': id});
  }

  // ==================== Food Menu (remote sync) ====================

  /// Upserts a food category received from another device (mutation or
  /// snapshot). When the category was renamed remotely, `oldCategory` lets
  /// this device re-link its food items and printer mappings to the new name.
  Future<void> applyRemoteFoodCategory(
    Map<String, dynamic> map, {
    String oldCategory = '',
  }) async {
    final id = map['id'] as int? ?? 0;
    if (id <= 0) return;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'food_categories',
        map,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        await txn.insert(
          'food_categories',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final newName = map['name'] as String? ?? '';
      if (oldCategory.isNotEmpty &&
          newName.isNotEmpty &&
          newName != oldCategory) {
        await txn.update(
          'food_items',
          {'category': newName},
          where: 'category = ?',
          whereArgs: [oldCategory],
        );
        await txn.update(
          'category_printer_mappings',
          {'category': newName},
          where: 'category = ?',
          whereArgs: [oldCategory],
        );
      }
    });
    _bumpFoodMenu();
  }

  /// Deletes a food category and everything linked to it by name.
  Future<void> applyRemoteFoodCategoryDelete(int id, String name) async {
    if (id <= 0) return;
    if (name.isNotEmpty) {
      await db.delete('food_items', where: 'category = ?', whereArgs: [name]);
      await db.delete(
        'category_printer_mappings',
        where: 'category = ?',
        whereArgs: [name],
      );
    }
    await db.delete('food_categories', where: 'id = ?', whereArgs: [id]);
    _bumpFoodMenu();
  }

  /// Upserts a food item received from another device (mutation or snapshot).
  Future<void> applyRemoteFoodItem(Map<String, dynamic> map) async {
    final id = map['id'] as int? ?? 0;
    if (id <= 0) return;
    final updated = await db.update(
      'food_items',
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) {
      await db.insert(
        'food_items',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _bumpFoodMenu();
  }

  /// Deletes a food item by its shared id.
  Future<void> applyRemoteFoodItemDelete(int id) async {
    if (id <= 0) return;
    await db.delete('food_items', where: 'id = ?', whereArgs: [id]);
    _bumpFoodMenu();
  }

  // ==================== Waiter Table Assignments ====================

  Future<List<int>> getWaiterTableIds(int waiterId) async {
    final maps = await db.query(
      'waiter_tables',
      where: 'waiterId = ?',
      whereArgs: [waiterId],
    );
    return maps.map((m) => m['tableId'] as int).toList();
  }

  Future<void> assignTablesToWaiter(int waiterId, List<int> tableIds) async {
    await db.delete(
      'waiter_tables',
      where: 'waiterId = ?',
      whereArgs: [waiterId],
    );
    for (final id in tableIds) {
      await db.insert('waiter_tables', {'waiterId': waiterId, 'tableId': id});
    }
    // The assignment is a decision the OWNER or an admin made for a captain on
    // another device, so it has to travel the same way every other registry
    // change does. Without the broadcast the captain's floor and the owner's
    // list could never agree on who owns which table.
    _emitMutation('WAITER_TABLES_UPDATED', {
      'waiterId': waiterId,
      'tableIds': tableIds,
    });
    _bumpUsers();
  }

  /// Applies a `WAITER_TABLES_UPDATED` mutation arriving from another device.
  ///
  /// A full replace, not a merge: the sending device is the authority on the
  /// captain's whole set, and an empty list is the documented "reset to normal"
  /// - so "delete then insert what was sent" is the only faithful application.
  Future<void> applyRemoteWaiterTables(int waiterId, List<int> tableIds) async {
    if (waiterId <= 0) return;
    await db.delete(
      'waiter_tables',
      where: 'waiterId = ?',
      whereArgs: [waiterId],
    );
    for (final id in tableIds) {
      await db.insert('waiter_tables', {
        'waiterId': waiterId,
        'tableId': id,
      });
    }
    _bumpUsers();
  }

  Future<List<int>> getUnassignedTableIds() async {
    final assignedMap = await db.rawQuery(
      'SELECT DISTINCT tableId FROM waiter_tables',
    );
    final assigned = assignedMap.map((m) => m['tableId'] as int).toSet();
    final allMaps = await db.query('tables', columns: ['id']);
    final all = allMaps.map((m) => m['id'] as int).toList();
    return all.where((id) => !assigned.contains(id)).toList();
  }

  Future<List<Map<String, dynamic>>> getAllWaitersWithTableCount() async {
    final maps = await db.query(
      'users',
      where: 'role = ?',
      whereArgs: [UserRole.waiter.index],
    );
    final result = <Map<String, dynamic>>[];
    for (final m in maps) {
      final count =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM waiter_tables WHERE waiterId = ?',
              [m['id']],
            ),
          ) ??
          0;
      result.add({'id': m['id'], 'name': m['name'], 'tableCount': count});
    }
    return result;
  }

  // ==================== Backup & Restore ====================

  Future<String> exportBackup() async {
    if (kIsWeb) return '';
    final dbDir = p.dirname(_dbPath);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupName = 'ramyar_pos_backup_$timestamp.db';
    final backupPath = p.join(dbDir, backupName);
    // Under WAL the freshest commits live in the -wal file until a checkpoint.
    // Flush them into the main file first, or the copied backup would silently
    // miss the last order or two.
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await File(_dbPath).copy(backupPath);
    return backupPath;
  }

  Future<List<Map<String, dynamic>>> listBackups() async {
    if (kIsWeb) return [];
    final dbDir = p.dirname(_dbPath);
    final dir = Directory(dbDir);
    final files = dir.listSync().whereType<File>().where((f) {
      final name = p.basename(f.path);
      // New backups use `ramyar_pos_backup_`; legacy `biablo_/biablu_backup_`
      // files remain listed so old exports stay restorable.
      return (name.startsWith('ramyar_pos_backup_') ||
              name.startsWith('biablo_backup_') ||
              name.startsWith('biablu_backup_')) &&
          f.path.endsWith('.db');
    }).toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files
        .map(
          (f) => {
            'path': f.path,
            'name': p.basename(f.path),
            'size': f.lengthSync(),
            'modified': f.lastModifiedSync().toIso8601String(),
          },
        )
        .toList();
  }

  void Function(int pendingCount)? onPendingQueueChange;
  void Function()? onTableNotification;

  Future<void> addPendingSync(
    String action,
    Map<String, dynamic> data, {
    String? batchId,
  }) async {
    final explicit =
        batchId ??
        (data['batchId'] is String ? data['batchId'] as String : null);
    try {
      await db.insert('pending_sync', {
        'action': action,
        'data': jsonEncode(data),
        'createdAt': DateTime.now().toIso8601String(),
        'status': 0,
        'batchId': explicit,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } catch (e) {
      // A write that cannot be queued is the one failure the offline model must
      // never hide. It is logged loudly here; the caller keeps its row in the
      // UI instead of pretending the order was saved.
      appLog('[DB] addPendingSync FAILED for $action: $e');
    }
    _notifyPendingCount();
  }

  /// Notes that a queued change was not accepted by the hub yet.
  ///
  /// The row stays at `status = 0` so the next flush retries it - a rejection
  /// is usually a transient link/auth problem, and dropping the order would be
  /// the data loss this whole queue exists to prevent. The counters simply make
  /// a stuck order visible to the operator.
  Future<void> recordPendingFailure(int localId, String error) async {
    try {
      await db.rawUpdate(
        'UPDATE pending_sync SET retryCount = COALESCE(retryCount, 0) + 1, '
        'lastError = ? WHERE id = ?',
        [error, localId],
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getPendingSyncAll() async {
    final rows = await db.query(
      'pending_sync',
      where: 'status = 0',
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (row) => {
            'localId': row['id'],
            'action': row['action'],
            'data': jsonDecode(row['data'] as String) as Map<String, dynamic>,
            'createdAt': row['createdAt'],
          },
        )
        .toList();
  }

  Future<int> getPendingCount() async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM pending_sync WHERE status = 0',
    );
    return (result.first['cnt'] as int);
  }

  void _notifyPendingCount() async {
    // Fire-and-forget: callers queue a mutation and move on. If the database
    // was closed (a reset, a shutdown) before this query got its turn in the
    // event queue, there is no listener left to inform anyway - so the failure
    // must not escape as an unhandled async error.
    try {
      final count = await getPendingCount();
      onPendingQueueChange?.call(count);
    } catch (e) {
      appLog('[DB] _notifyPendingCount skipped: $e');
    }
  }

  Future<void> markSynced(int localId) async {
    await db.update(
      'pending_sync',
      {'status': 1},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markSyncedMatching(String action, int tableId) async {
    final pending = await getPendingSyncAll();
    final ids = pending
        .where(
          (p) =>
              p['action'] == action &&
              ((p['data'] as Map<String, dynamic>)['tableId'] as int?) ==
                  tableId,
        )
        .map((p) => p['localId'] as int)
        .toList();
    if (ids.isEmpty) return;
    for (final id in ids) {
      await markSynced(id);
    }
    _notifyPendingCount();
  }

  Future<void> clearSyncedOrders() async {
    await db.delete('pending_sync', where: 'status = 1');
  }

  // ==================== Print Job Ledger ====================
  //
  // A kitchen ticket is a physical side effect: it cannot be rolled back, so
  // the only safe policy is at-most-once. Every (batch, printer) pair gets one
  // row. The first caller to claim it prints; a resend after a lost ack, or a
  // crash-recovery retry, loses the claim and stays quiet. Failed rows are
  // retried by resumePendingPrints().

  static const int printJobPending = 0;
  static const int printJobPrinting = 1;
  static const int printJobPrinted = 2;
  static const int printJobFailed = 3;

  /// How many times an automatic retry will keep trying one ticket.
  ///
  /// The retry timer runs every 30 seconds for as long as the app is open, so
  /// an unbounded retry against a printer that can never take this job - no
  /// printer configured for that station, a spooler that rejects the job, a
  /// printer that is switched off for the evening - does not cost anything
  /// once and then stop. It costs a dispatch every 30 seconds for the rest of
  /// the shift, forever, and pushes a `print_status` onto the wire each time so
  /// every captain's handset re-renders a red dot.
  ///
  /// Five tries is about two and a half minutes at the timer's cadence, which
  /// covers a printer being switched on or a cable being reseated. Past that
  /// the ticket stops asking and waits for a person: the row stays in the
  /// ledger with its error, so nothing is lost and an operator can still settle
  /// it by hand, which is the right answer for a job the machine has already
  /// proven it cannot do.
  static const int printJobMaxAttempts = 5;

  /// Claims the right to print one (batch, printer) ticket.
  ///
  /// Returns true for the caller that owns the print: the first one ever, or
  /// the one taking over a job that failed earlier. Returns false when the
  /// ticket is already printed, or a worker is printing it right now - which is
  /// what stops a reconnect resend from producing a second ticket.
  Future<bool> claimPrintJob({
    required String batchId,
    required int printerType,
    required int tableId,
    required String payload,
  }) async {
    final now = DateTime.now().toIso8601String();
    return db.transaction<bool>((txn) async {
      final existing = await txn.query(
        'print_jobs',
        where: 'batchId = ? AND printerType = ?',
        whereArgs: [batchId, printerType],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('print_jobs', {
          'batchId': batchId,
          'printerType': printerType,
          'tableId': tableId,
          'payload': payload,
          'status': printJobPrinting,
          'attempts': 1,
          'lastError': '',
          'createdAt': now,
          'updatedAt': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return true;
      }
      final status = existing.first['status'] as int? ?? printJobPending;
      if (status == printJobPrinted || status == printJobPrinting) {
        return false;
      }
      final attempts = (existing.first['attempts'] as int?) ?? 0;
      await txn.update(
        'print_jobs',
        {
          'status': printJobPrinting,
          'attempts': attempts + 1,
          'updatedAt': now,
        },
        where: 'batchId = ? AND printerType = ?',
        whereArgs: [batchId, printerType],
      );
      return true;
    });
  }

  Future<void> completePrintJob(
    String batchId,
    int printerType, {
    required bool success,
    String error = '',
  }) async {
    try {
      await db.update(
        'print_jobs',
        {
          'status': success ? printJobPrinted : printJobFailed,
          'lastError': error,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'batchId = ? AND printerType = ?',
        whereArgs: [batchId, printerType],
      );
    } catch (_) {}
  }

  /// Jobs still owed a ticket: never dispatched, or dispatched and failed, and
  /// not yet given up on.
  ///
  /// A crash leaves a row at [printJobPrinting] on purpose, and it is NOT
  /// retried - the ticket may already be on the kitchen wall, and printing it
  /// twice is worse than asking the operator about that one batch.
  ///
  /// Jobs past [printJobMaxAttempts] are excluded too, for the same reason:
  /// the machine has already failed this one repeatedly and automatic effort
  /// has stopped helping. [stalledPrintJobs] is how they are still seen.
  Future<List<Map<String, dynamic>>> getPendingPrintJobs() async {
    final rows = await db.query(
      'print_jobs',
      where: 'status IN (?, ?) AND attempts < ?',
      whereArgs: [printJobPending, printJobFailed, printJobMaxAttempts],
      orderBy: 'createdAt ASC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Jobs the retry loop has stopped chasing, so the failure is not invisible.
  ///
  /// Deliberately read-only: re-arming one is an operator decision, not
  /// something the app may do to itself on a timer.
  Future<List<Map<String, dynamic>>> stalledPrintJobs() async {
    final rows = await db.query(
      'print_jobs',
      where: 'status IN (?, ?) AND attempts >= ?',
      whereArgs: [printJobPending, printJobFailed, printJobMaxAttempts],
      orderBy: 'createdAt ASC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> batchSendAndOccupyPending(
    int tableId,
    List<OrderItem> items, {
    int guestCount = 1,
    String waiterId = '',
  }) async {
    final isConnected = onMutation != null;
    if (isConnected) {
      await batchSendAndOccupy(
        tableId,
        items,
        guestCount: guestCount,
        waiterId: waiterId,
      );
      return;
    }
    final table = await getTable(tableId);
    final isEmpty = table == null || table.status == TableStatus.empty;
    final now = DateTime.now();
    final nowStr = now.toIso8601String();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // Stable id minted here, at capture, and carried through the queue on every
    // resend so the server can tell "the same order again" from a new one.
    final batchId = const Uuid().v4();
    await db.transaction((txn) async {
      if (isEmpty) {
        await txn.update(
          'tables',
          {
            'status': TableStatus.occupied.index,
            'seatedTime': timeStr,
            'waiterId': waiterId,
            'guestCount': guestCount,
            'sentToCashier': 1,
            'openedBy': int.tryParse(waiterId) ?? 0,
          },
          where: 'id = ?',
          whereArgs: [tableId],
        );
      } else {
        await txn.update(
          'tables',
          {'sentToCashier': 1},
          where: 'id = ?',
          whereArgs: [tableId],
        );
      }
      for (final item in items) {
        final itemNow = item.createdAt.isNotEmpty ? item.createdAt : nowStr;
        await txn.insert('order_items', {
          'id': item.id,
          'tableId': tableId,
          'name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'category': item.category,
          'createdAt': itemNow,
          'waiterName': item.waiterName,
          'waiterRole': item.waiterRole,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      // Same transaction as the items: the table's money can never be stale
      // relative to its food.
      await _recalculateTotalInTxn(txn, tableId);
    });
    _bumpOrders();
    await addPendingSync('batchSendAndOccupy', {
      'batchId': batchId,
      'tableId': tableId,
      'items': items.map((e) => e.toMap()).toList(),
      'guestCount': guestCount,
      'waiterId': waiterId,
    }, batchId: batchId);
  }

  // ==================== Order Delivery Status ====================

  Future<void> recordOrderSent(int tableId, {String sentAt = ''}) async {
    final now = sentAt.isNotEmpty ? sentAt : DateTime.now().toIso8601String();
    await db.insert('order_delivery', {
      'tableId': tableId,
      'sentAt': now,
      'arrivedAt': '',
      'printedAt': '',
      'printFailedAt': '',
      'rejected': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markOrderArrived(
    int tableId, {
    bool rejected = false,
    String arrivedAt = '',
  }) async {
    final now = arrivedAt.isNotEmpty
        ? arrivedAt
        : DateTime.now().toIso8601String();
    await db.update(
      'order_delivery',
      {'arrivedAt': now, 'printFailedAt': '', 'rejected': rejected ? 1 : 0},
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
  }

  Future<void> markOrderPrinted(int tableId, {String printedAt = ''}) async {
    final now = printedAt.isNotEmpty
        ? printedAt
        : DateTime.now().toIso8601String();
    await db.update(
      'order_delivery',
      {'printedAt': now, 'printFailedAt': '', 'rejected': 0},
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
  }

  Future<void> markOrderPrintFailed(int tableId, {String failedAt = ''}) async {
    final now = failedAt.isNotEmpty
        ? failedAt
        : DateTime.now().toIso8601String();
    await db.update(
      'order_delivery',
      {'printedAt': '', 'printFailedAt': now, 'rejected': 0},
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
  }

  Future<List<OrderDeliveryModel>> getOrderDeliveries() async {
    final maps = await db.query('order_delivery', orderBy: 'sentAt DESC');
    final deliveries = maps.map((m) => OrderDeliveryModel.fromMap(m)).toList();
    return deliveries.where((d) => !d.shouldAutoExpire).toList();
  }

  Future<void> clearOrderDelivery(int tableId) async {
    await db.delete(
      'order_delivery',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
  }

  // ==================== Table Locks ====================

  Future<void> lockTable(TableLock lock) async {
    await db.insert(
      'table_locks',
      lock.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> unlockTable(int tableId, String deviceId) async {
    await db.delete(
      'table_locks',
      where: 'tableId = ? AND deviceId = ?',
      whereArgs: [tableId, deviceId],
    );
  }

  Future<void> unlockAllByDevice(String deviceId) async {
    await db.delete(
      'table_locks',
      where: 'deviceId = ?',
      whereArgs: [deviceId],
    );
  }

  Future<List<TableLock>> getAllTableLocks() async {
    final maps = await db.query('table_locks');
    return maps.map((m) => TableLock.fromMap(m)).toList();
  }

  Future<TableLock?> getTableLockById(int tableId) async {
    final maps = await db.query(
      'table_locks',
      where: 'tableId = ?',
      whereArgs: [tableId],
    );
    if (maps.isEmpty) return null;
    final lock = TableLock.fromMap(maps.first);
    if (lock.isExpired) {
      await db.delete(
        'table_locks',
        where: 'tableId = ?',
        whereArgs: [tableId],
      );
      return null;
    }
    return lock;
  }

  Future<void> updateLockHeartbeat(int tableId, String deviceId) async {
    await db.update(
      'table_locks',
      {'heartbeat': DateTime.now().toIso8601String()},
      where: 'tableId = ? AND deviceId = ?',
      whereArgs: [tableId, deviceId],
    );
  }

  Future<void> clearExpiredLocks() async {
    final locks = await getAllTableLocks();
    for (final lock in locks) {
      if (lock.isExpired) {
        await db.delete(
          'table_locks',
          where: 'tableId = ? AND deviceId = ?',
          whereArgs: [lock.tableId, lock.deviceId],
        );
      }
    }
  }

  /// Throws the captain currently working a table off it.
  ///
  /// The order is deliberately left completely alone - the items, the running
  /// total and the table's status all survive, because the cashier is about to
  /// settle that bill and must not lose it. What goes away is the claim on the
  /// table: the lock row is dropped and the table no longer names a serving
  /// captain, so the next captain to take it owns it cleanly.
  Future<void> ejectCaptainFromTable(int tableId) async {
    await db.delete('table_locks', where: 'tableId = ?', whereArgs: [tableId]);
    await db.update(
      'tables',
      {'waiterId': ''},
      where: 'id = ?',
      whereArgs: [tableId],
    );
    emitTableEjection(tableId);
    _emitMutation('TABLE_LOCK_EJECTED', {'tableId': tableId});
  }

  /// Drops a lock no matter who holds it. Used when a captain's device stops
  /// heartbeating: the row is already past its timeout, so nobody is really
  /// serving the table and holding the claim longer only locks people out.
  Future<void> forceUnlockTable(int tableId) async {
    await db.delete('table_locks', where: 'tableId = ?', whereArgs: [tableId]);
    _emitMutation('TABLE_LOCK_RELEASED_FORCED', {'tableId': tableId});
  }

  // ==================== Shop settings ====================

  static const String _kDollarRateKey = 'dollar_rate';

  /// The rate the admin last saved, or [DollarRate.fallback] on a device that
  /// has never been told one.
  ///
  /// A malformed stored value falls back rather than throwing: this is read on
  /// the cashier's home screen during a normal shift, and one bad row must not
  /// be able to take the whole screen down.
  Future<DollarRate> getDollarRate() async {
    try {
      final rows = await db.query(
        'shop_settings',
        where: 'key = ?',
        whereArgs: [_kDollarRateKey],
        limit: 1,
      );
      if (rows.isEmpty) return DollarRate.fallback;
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) return DollarRate.fallback;
      return DollarRate.fromMap(Map<String, dynamic>.from(decoded));
    } catch (e) {
      return DollarRate.fallback;
    }
  }

  /// Saves the rate the admin typed and tells every other device.
  ///
  /// The write and the broadcast are separate steps on purpose: the value is
  /// saved locally first, so a device that is offline (or is the device the
  /// admin is standing at, with no link at all) still shows the new rate to the
  /// person who just set it. [LocalDatabase.onMutation] queues the broadcast for
  /// later when there is no link, so the rate still reaches the cashiers as soon
  /// as one of them comes back onto the network.
  Future<void> setDollarRate(DollarRate rate) async {
    // One stamp, used for both the row and the broadcast. Two separate
    // `DateTime.now()` calls could straddle a millisecond and hand the message
    // a time that sorts *after* the row it came from, which is harmless here but
    // makes the "newest rate wins" comparison impossible to reason about.
    final stamp = DateTime.now().toIso8601String();
    await db.insert('shop_settings', {
      'key': _kDollarRateKey,
      'value': jsonEncode(rate.toMap()),
      'updatedAt': stamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bumpDollarRate();
    _emitMutation('DOLLAR_RATE_CHANGED', {...rate.toMap(), 'updatedAt': stamp});
  }

  /// Applies a rate that arrived from another device without sending it on
  /// again. A stale rate must never win a race against a newer one, so a message
  /// carrying an older `updatedAt` than what is already stored is dropped.
  Future<void> applyDollarRate(DollarRate rate, {String? updatedAt}) async {
    if (updatedAt != null && updatedAt.isNotEmpty) {
      final rows = await db.query(
        'shop_settings',
        where: 'key = ?',
        whereArgs: [_kDollarRateKey],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final current = (rows.first['updatedAt'] as String?) ?? '';
        // ISO-8601 sorts chronologically as text, which is why the stamp is
        // compared as a string and not parsed.
        if (current.isNotEmpty && updatedAt.compareTo(current) < 0) return;
      }
    }
    await db.insert('shop_settings', {
      'key': _kDollarRateKey,
      'value': jsonEncode(rate.toMap()),
      'updatedAt': updatedAt ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bumpDollarRate();
  }

  static const String _kReceiptDesignKey = 'receipt_design';

  /// The receipt design the admin last saved, or the stock look on a device that
  /// has never been given one.
  Future<ReceiptDesign> getReceiptDesign() async {
    try {
      final rows = await db.query(
        'shop_settings',
        where: 'key = ?',
        whereArgs: [_kReceiptDesignKey],
        limit: 1,
      );
      if (rows.isEmpty) return ReceiptDesign.standard;
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) return ReceiptDesign.standard;
      return ReceiptDesign.fromMap(Map<String, dynamic>.from(decoded));
    } catch (e) {
      return ReceiptDesign.standard;
    }
  }

  /// Saves the design the admin built and tells every other device, so the
  /// cashiers print the same receipt the admin designed.
  Future<void> setReceiptDesign(ReceiptDesign design) async {
    final stamp = DateTime.now().toIso8601String();
    await db.insert('shop_settings', {
      'key': _kReceiptDesignKey,
      'value': jsonEncode(design.toMap()),
      'updatedAt': stamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bumpReceiptDesign();
    _emitMutation('RECEIPT_DESIGN_CHANGED', {
      ...design.toMap(),
      'updatedAt': stamp,
    });
  }

  /// Applies a design that arrived from another device without sending it on
  /// again. A stale design must not win a race against a newer one, so a message
  /// carrying an older `updatedAt` than what is already stored is dropped.
  Future<void> applyReceiptDesign(ReceiptDesign design, {String? updatedAt}) async {
    if (updatedAt != null && updatedAt.isNotEmpty) {
      final rows = await db.query(
        'shop_settings',
        where: 'key = ?',
        whereArgs: [_kReceiptDesignKey],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final current = (rows.first['updatedAt'] as String?) ?? '';
        if (current.isNotEmpty && updatedAt.compareTo(current) < 0) return;
      }
    }
    await db.insert('shop_settings', {
      'key': _kReceiptDesignKey,
      'value': jsonEncode(design.toMap()),
      'updatedAt': updatedAt ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _bumpReceiptDesign();
  }

  Future<void> resetAllData() async {
    await AppPrefs.instance.clearAll();
    OwnerAccess.lock();

    await db.delete('order_items');
    await db.delete('tables');
    await db.delete('debts');
    await db.delete('settled_orders');
    await db.delete('settled_order_items');
    await db.delete('waiter_tables');
    await db.delete('cashier_expenses');
    await db.delete('cashier_shifts');
    await db.delete('refunds');
    await db.delete('purchases');
    await db.delete('pending_sync');
    await db.delete('table_locks');
    await db.delete('order_delivery');
    await db.delete('print_jobs');

    final waiters = await getUsersByRole(UserRole.waiter);
    final rangeWaiters = waiters.where((w) => w.hasRange).toList();
    for (int i = 1; i <= 100; i++) {
      int owner = 0;
      for (final w in rangeWaiters) {
        if (i >= w.rangeStart! && i <= w.rangeEnd!) {
          owner = w.id;
          break;
        }
      }
      await db.insert(
        'tables',
        TableModel(id: i, name: 'مێز $i', createdBy: owner).toMap(),
      );
      for (final w in rangeWaiters) {
        if (i >= w.rangeStart! && i <= w.rangeEnd!) {
          await db.insert('waiter_tables', {'waiterId': w.id, 'tableId': i});
        }
      }
    }
    _bumpOrders();
  }

  Future<void> restoreBackup(String backupPath) async {
    if (kIsWeb) {
      appLog('[DB] Restore is not supported on web');
      return;
    }
    if (!await File(backupPath).exists()) {
      appLog('[DB] Backup file not found: $backupPath');
      return;
    }
    final Database? current = _db;
    if (current != null) {
      await current.close();
    }
    _db = null;
    // A stale WAL/SHM pair from the database we just closed would be replayed
    // on top of the restored file, mixing two databases together. Clear it so
    // the backup is unambiguously what opens.
    for (final sidecar in ['$_dbPath-wal', '$_dbPath-shm']) {
      try {
        final f = File(sidecar);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    try {
      await File(backupPath).copy(_dbPath);
      _db = await _openDb(
        _dbPath,
        onDowngrade: (db, oldVersion, newVersion) async {
          appLog(
            '[DB] Backup has newer schema (v$oldVersion), reinitializing',
          );
          await _createTables(db, newVersion);
        },
      );
    } catch (e) {
      appLog('[DB] Restore failed, reopening original database: $e');
      _db = await _openDb(_dbPath);
    }
  }
}
