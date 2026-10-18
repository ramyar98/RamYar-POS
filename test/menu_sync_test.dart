import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';

/// Verifies the "food items added by the Admin appear automatically on every
/// account/device" behaviour:
///  - local add/edit/delete emits the right mutations (online broadcast),
///  - the same actions are queued in the offline outbox when disconnected,
///  - remote devices apply those mutations so the menu converges,
///  - buildSnapshot/applySnapshot also carry the full menu so an offline device
///    catches up on the next (re)connect.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDatabase db;
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ramyar_pos_menu_sync');
    db = LocalDatabase();
    // Per-test temp FILE: sqflite's `:memory:` is ONE shared store per process,
    // so file paths are used whenever the test models 2+ devices.
    await db.init(path: '${tmp.path}${Platform.pathSeparator}admin.db');
  });

  tearDown(() async {
    await db.resetForTesting();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A second device with its own private store.
  Future<LocalDatabase> newDevice(String name) async {
    final device = LocalDatabase();
    await device.init(path: '${tmp.path}${Platform.pathSeparator}$name.db');
    return device;
  }

  test('admin adding a food item online emits FOOD_ITEM_CREATED with the full row', () async {
    final emitted = <String, List<Map<String, dynamic>>>{};
    db.onMutation = (action, data) {
      emitted[action] = [...(emitted[action] ?? []), data];
    };
    await db.addFoodCategory('گۆشتی', 'lunch_dining');
    await db.addFoodItem('کەبابی تاقیکاری سەرچاوە', 10000, 'گۆشتی');

    final created = emitted['FOOD_ITEM_CREATED'];
    expect(created, hasLength(1));
    final item = created!.single['item'] as Map<String, dynamic>;
    expect(item['name'], 'کەبابی تاقیکاری سەرچاوە');
    expect(item['price'], 10000);
    expect(item['category'], 'گۆشتی');
    expect(item['id'], isA<int>());
    expect(item['id'], greaterThan(0));

    final catCreated = emitted['FOOD_CATEGORY_CREATED'];
    expect(catCreated, hasLength(1));
    final cat = catCreated!.single['category'] as Map<String, dynamic>;
    expect(cat['name'], 'گۆشتی');
  });

  test('offline food menu edits are queued in the pending outbox', () async {
    // onMutation == null => the app treats this device as offline and queues.
    await db.addFoodCategory('گۆشتی', 'lunch_dining');
    await db.addFoodItem('کەبابی تاقیکاری ئۆفلاین', 10000, 'گۆشتی');
    // Allow the fire-and-forget outbox writes to land.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final pending = await db.getPendingSyncAll();
    final actions = pending.map((p) => p['action']).toList();
    expect(actions, contains('FOOD_CATEGORY_CREATED'));
    expect(actions, contains('FOOD_ITEM_CREATED'));
  });

  test('a food item added on the admin device reaches a remote device', () async {
    final admin = await newDevice('admin');
    try {
      final emitted = <String, Map<String, dynamic>>{};
      admin.onMutation = (action, data) => emitted[action] = data;

      await admin.addFoodCategory('گۆشتی', 'lunch_dining');
      await admin.addFoodItem('کەبابی تاقیکاری گواستنەوە', 8000, 'گۆشتی');

      final created = emitted['FOOD_ITEM_CREATED']!['item'] as Map<String, dynamic>;
      // The receiving (cashier/captain) device applies the relayed mutation.
      await db.applyRemoteFoodItem(Map<String, dynamic>.from(created));

      final remoteItems = await db.getFoodItems();
      final synced = remoteItems.where((i) => i['name'] == 'کەبابی تاقیکاری گواستنەوە').toList();
      expect(synced, hasLength(1));
      expect(synced.single['price'], 8000);
    } finally {
      await admin.resetForTesting();
    }
  });

  test('category rename on the admin device re-links items everywhere', () async {
    await db.addFoodCategory('گۆشتی', 'lunch_dining');
    final itemId = await db.addFoodItem('کەبابی تاقیکاری گۆڕین', 10000, 'گۆشتی');
    final catId = (await db.getFoodCategories()).first['id'] as int;

    await db.updateFoodCategory(catId, 'گۆشتی نوێ', 'lunch_dining');

    // Remote device that already had the item under the old category name.
    final remote = await newDevice('remote');
    try {
      final items = await db.getFoodItems();
      final item = items.firstWhere((i) => i['id'] == itemId);
      await remote.applyRemoteFoodItem(Map<String, dynamic>.from(item));

      final cats = await db.getFoodCategories();
      final renamed = cats.firstWhere((c) => c['name'] == 'گۆشتی نوێ');
      await remote.applyRemoteFoodCategory(
        Map<String, dynamic>.from(renamed),
        oldCategory: 'گۆشتی',
      );

      final remoteItems = await remote.getFoodItems();
      final synced = remoteItems.firstWhere((i) => i['id'] == itemId);
      expect(synced['category'], 'گۆشتی نوێ');
    } finally {
      await remote.resetForTesting();
    }
  });

  test('food menu travels inside the snapshot and lands on a fresh device', () async {
    await db.addFoodCategory('گۆشتی', 'lunch_dining');
    await db.addFoodItem('کەبابی تاقیکاری سنەپشۆت', 10000, 'گۆشتی');

    final snap = await db.buildSnapshot();
    expect(snap['food_categories'], isA<List<dynamic>>());
    expect(snap['food_items'], isA<List<dynamic>>());
    expect((snap['food_items'] as List).isNotEmpty, isTrue);

    final client = await newDevice('client');
    try {
      await client.applySnapshot(snap);
      final items = await client.getFoodItems();
      final synced = items.where((i) => i['name'] == 'کەبابی تاقیکاری سنەپشۆت').toList();
      expect(synced, hasLength(1));
    } finally {
      await client.resetForTesting();
    }
  });
}