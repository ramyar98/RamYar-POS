import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/env.dart';
import '../database/local_db.dart';
import '../models/cancelled_item_model.dart';
import '../models/order_delivery_model.dart';
import '../models/order_model.dart';
import '../models/table_model.dart';
import '../models/table_notification_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

/// Bridges the database's plain [ValueNotifier] into Riverpod, so a provider can
/// `watch` it and be rebuilt the moment a change lands - locally or arriving
/// from another device. This is the same pattern the food menu, the shifts and
/// the dollar rate already use.
final orderRevisionProvider = ChangeNotifierProvider<OrderRevision>(
  (ref) => OrderRevision(ref.read(localDbProvider)),
);

/// Forwards the database's order/table revision notifier as change notifications.
class OrderRevision extends ChangeNotifier {
  OrderRevision(this._db) {
    _db.orderRevision.addListener(notifyListeners);
  }

  final LocalDatabase _db;

  @override
  void dispose() {
    _db.orderRevision.removeListener(notifyListeners);
    super.dispose();
  }
}

final tableNotificationsProvider = FutureProvider<List<TableNotification>>((
  ref,
) async {
  final db = ref.read(localDbProvider);
  return db.getTableNotifications();
});

/// The cashier's «ڕەتکراوەکان» queue: everything the cashier has rejected and has
/// not yet moved back onto a table.
///
/// Every device watches this, not just the cashier's, because a captain has to
/// be able to see that a dish they rang in was thrown out - that is the whole
/// reason to look at the list. Watching [orderRevisionProvider] is what makes it
/// live: the rejection arrives from the cashier's device as a database write, and
/// a rejected dish is an order change like any other, so the revision notifier is
/// the signal that this queue just moved.
final pendingCancelledItemsProvider = FutureProvider<List<CancelledItem>>((
  ref,
) async {
  ref.watch(orderRevisionProvider);
  final db = ref.read(localDbProvider);
  return db.getPendingCancelledItems();
});

final waiterNamesProvider = FutureProvider<Map<int, String>>((ref) async {
  final db = ref.read(localDbProvider);
  final waiters = await db.getUsersByRole(UserRole.waiter);
  final map = <int, String>{};
  for (final w in waiters) {
    map[w.id] = w.name;
  }
  return map;
});

final deliveryStatusProvider = FutureProvider<List<OrderDeliveryModel>>((
  ref,
) async {
  final db = ref.read(localDbProvider);
  return db.getOrderDeliveries();
});

final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(localDbProvider);
  return db.getPendingCount();
});

/// The list of tables - the grid every captain and cashier sees on their home
/// screen.
///
/// Watches the revision notifier so a table's status, its total and who is on it
/// repaint when the change came from another device. This is the screen the
/// complaint was actually about: a captain rang food in, the rows arrived at the
/// hub, and the grid kept showing an empty table because nothing had told it to
/// look again.
final allTablesProvider = FutureProvider<List<TableModel>>((ref) async {
  ref.watch(orderRevisionProvider);
  final db = ref.read(localDbProvider);
  return db.getAllTables();
});

/// The table row itself: its status, its total, who is on it, whether the bill
/// went to the cashier.
///
/// Watches the revision notifier, so a table that changes on ANOTHER device -
/// a captain ringing food in, the cashier settling it - repaints here without
/// anyone leaving and re-entering the page. Without this the row kept whatever
/// it looked like when the page was first opened.
final tableDetailProvider = FutureProvider.family<TableModel?, int>((
  ref,
  tableId,
) async {
  // The watch is the whole point of this provider, so it is kept even though the
  // value below does not read it.
  ref.watch(orderRevisionProvider);
  final db = ref.read(localDbProvider);
  return db.getTable(tableId);
});

/// The items on a table - the food list and the total derived from it.
///
/// Watches the revision notifier for the same reason as [tableDetailProvider].
/// This is the list that used to go stale: the rows arrived from the captain's
/// device, the database had them, and this provider kept serving the list it
/// built the first time - so the cashier saw an empty table and a total of zero
/// for an order that had already been paid for at the table.
final tableOrdersProvider = FutureProvider.family<List<OrderItem>, int>((
  ref,
  tableId,
) async {
  ref.watch(orderRevisionProvider);
  final db = ref.read(localDbProvider);
  return db.getOrderItems(tableId);
});

class WaiterNotifier extends StateNotifier<AsyncValue<List<TableModel>>> {
  final LocalDatabase _db;
  final Ref _ref;
  int? _scopeLoadedFor;
  int? _rangeStart;
  int? _rangeEnd;
  Set<int> _cashierIds = {};
  Timer? _overdueTimer;

  WaiterNotifier(this._db, this._ref) : super(const AsyncValue.data([])) {
    // Re-read the floor whenever anything about a table changes, including when
    // the change arrived from another device. Without this the grid only ever
    // moved when the person in front of it acted: a captain ringing food in on
    // another device left this screen showing the table exactly as it was.
    _db.orderRevision.addListener(_onOrdersChanged);
    // The owner or an admin can narrow or widen a captain's tables at any
    // moment. The scope is cached per waiter id, so a range/assignment change
    // that lands here (locally or from the owner's device) has to drop that
    // cache - otherwise the captain keeps seeing the old floor until the next
    // sign-in.
    _db.usersRevision.addListener(_onUsersChanged);
    // The 10-minute bill clock belongs to the FLOOR, not to one role: whichever
    // role is signed in (cashier, admin, owner, waiter), a bill that was printed
    // and not settled within the window turns its table red on every screen that
    // shows tables. It runs here - on the one provider every role's home page
    // watches - rather than in each page, so a role that forgets its own timer
    // still gets the colour change.
    // Widget tests run under fake time; a real periodic timer there would be
    // left pending and fail the suite, so it is skipped under test - the tests
    // call checkOverdueTables() directly instead.
    // Every second, not the five it used to be. The poll has to be fine enough
    // that a table turns red close to the moment its window closes rather than
    // up to a poll late, and a single indexed read of the handful of
    // billRequested rows out of the floor makes once a second cheap.
    if (isRunningUnderTest) return;
    _overdueTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      await _db.checkOverdueTables();
    });
  }

  bool _refreshScheduled = false;

  void _onOrdersChanged() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    // Coalesce: a batch of items arriving one by one should rebuild once, not
    // once per item.
    scheduleMicrotask(() async {
      _refreshScheduled = false;
      if (!mounted) return;
      await refreshSilent();
    });
  }

  /// A user-registry change (range, assignment, new account) just landed.
  /// Drop the cached scope so the next floor read re-applies it.
  void _onUsersChanged() {
    _scopeLoadedFor = null;
    _onOrdersChanged();
  }

  @override
  void dispose() {
    _overdueTimer?.cancel();
    _db.orderRevision.removeListener(_onOrdersChanged);
    _db.usersRevision.removeListener(_onUsersChanged);
    super.dispose();
  }

  /// The captain whose table assignment currently narrows the list, or null
  /// when every table is visible.
  ///
  /// Table scope follows the SIGNED-IN ROLE, re-read on every list build, and
  /// is never carried over from a previous login. That is deliberate: a
  /// remembered id used to leak the last captain's tables to whoever logged in
  /// next. Only a captain (waiter) is limited to their assigned tables - a
  /// cashier, an admin, the owner and a logged-out device all see the whole
  /// floor, however many tables it has or gains later.
  int? get scopeWaiterId {
    final user = _ref.read(authProvider);
    if (user == null || user.role != UserRole.waiter) return null;
    return user.id;
  }

  /// Re-applies the table scope for whoever is signed in now. Call on login,
  /// on auto-login and when a role's home page opens.
  Future<void> syncTableScope() async {
    await _loadScopeData(scopeWaiterId);
    await refreshSilent();
  }

  Future<void> _loadScopeData(int? waiterId) async {
    if (waiterId == null) {
      _scopeLoadedFor = null;
      _rangeStart = null;
      _rangeEnd = null;
      _cashierIds = {};
      return;
    }
    if (_scopeLoadedFor == waiterId) return;
    final user = await _db.getUserById(waiterId);
    final cashiers = await _db.getUsersByRole(UserRole.cashier);
    // A newer request may have landed while we were reading. If the scope we
    // just loaded is no longer the one wanted, drop it instead of installing
    // stale data.
    if (scopeWaiterId != waiterId) return;
    _rangeStart = user?.rangeStart;
    _rangeEnd = user?.rangeEnd;
    _cashierIds = cashiers.map((u) => u.id).toSet();
    _scopeLoadedFor = waiterId;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _getTables());
    _ref.invalidate(tableNotificationsProvider);
  }

  Future<void> refreshSilent() async {
    final tables = await _getTables();
    // Both the one-second floor poll and the change-driven refresh land here.
    // Publishing a freshly-read list on every call would rebuild the whole
    // floor up to twice a second even when nothing on it changed - exactly the
    // churn that makes a tablet feel slow. Only publish when the data really
    // differs; the bell queue is cheap and is still refreshed so a notification
    // arriving from another device shows up promptly either way.
    if (!_sameFloor(state.valueOrNull, tables)) {
      state = AsyncValue.data(tables);
    }
    _ref.invalidate(tableNotificationsProvider);
  }

  /// Whether two floor reads describe the same floor. [TableModel] has no
  /// `==`, and every read hands back fresh instances, so identity or object
  /// equality could never say "nothing changed" - compare the fields a floor
  /// card renders instead. The database returns tables in id order, so the
  /// index-by-index comparison is stable.
  bool _sameFloor(List<TableModel>? previous, List<TableModel> next) {
    if (previous == null || previous.length != next.length) return false;
    for (var i = 0; i < previous.length; i++) {
      final a = previous[i];
      final b = next[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.status != b.status ||
          a.seatedTime != b.seatedTime ||
          a.waiterId != b.waiterId ||
          a.totalAmount != b.totalAmount ||
          a.guestCount != b.guestCount ||
          a.sentToCashier != b.sentToCashier ||
          a.printedAt != b.printedAt ||
          a.note != b.note ||
          a.createdBy != b.createdBy ||
          a.isDelivery != b.isDelivery ||
          a.deliveryCompanyId != b.deliveryCompanyId ||
          a.deliverySlot != b.deliverySlot) {
        return false;
      }
    }
    return true;
  }

  Future<List<TableModel>> _getTables() async {
    final all = await _db.getAllTables();
    final waiterId = scopeWaiterId;
    if (waiterId == null) return all;
    await _loadScopeData(waiterId);
    final assigned = (await _db.getWaiterTableIds(waiterId)).toSet();
    final hasRange = _rangeStart != null && _rangeEnd != null;
    // The owner narrows a captain two ways - a numeric مەودا, or picking tables
    // by hand - but both mean the SAME thing: this captain may see only those
    // tables. As soon as EITHER is set the rest of the floor must disappear.
    //
    // The old rule only hid tables owned by ANOTHER captain and let every
    // unowned table through, so a picked list was additive: a captain told "you
    // have tables 3, 4 and 7" still saw the other 97. And a مەودا only matched
    // unowned tables, so a range set on tables another captain already held
    // showed the captain nothing at all. A scope now means a scope.
    final hasScope = assigned.isNotEmpty || hasRange;
    return all.where((t) {
      // Named for this captain, by hand or by مەودا.
      if (assigned.contains(t.id)) return true;
      if (hasRange && t.id >= _rangeStart! && t.id <= _rangeEnd!) return true;
      // A table this captain opened, or one a cashier opened for the shared
      // floor, stays visible even under a narrow scope.
      if (t.createdBy == waiterId) return true;
      if (_cashierIds.contains(t.createdBy)) return true;
      // A scope hides everything else. With no scope at all the account is
      // "normal" and the whole floor is theirs - which is exactly the state
      // «گەڕانەوە بۆ ئاسایی» hands back.
      if (hasScope) return false;
      return true;
    }).toList();
  }

  Future<void> occupyTable(
    int tableId, {
    int guestCount = 1,
    String waiterId = '',
  }) async {
    await _db.occupyTable(tableId, waiterId, guestCount: guestCount);
    await refresh();
  }

  Future<void> freeTable(int tableId) async {
    await _db.freeTable(tableId);
    await refresh();
  }

  Future<void> requestBill(int tableId) async {
    await _db.requestBill(tableId);
    await refresh();
  }

  Future<void> addItemToOrder(int tableId, OrderItem item) async {
    await _db.addOrderItem(tableId, item);
    _ref.invalidate(tableOrdersProvider(tableId));
    await refresh();
  }

  Future<void> batchAddItemsToOrder(int tableId, List<OrderItem> items) async {
    if (items.isEmpty) return;
    await _db.batchAddOrderItems(tableId, items);
    _ref.invalidate(tableOrdersProvider(tableId));
    await refresh();
  }

  Future<void> resendOrder(int tableId) async {
    final items = await _db.getOrderItems(tableId);
    if (items.isEmpty) return;
    final user = _ref.read(authProvider);
    final waiterId = user?.id.toString() ?? '';
    await _db.batchSendAndOccupyPending(
      tableId,
      items,
      guestCount: await _db.getTableGuestCount(tableId),
      waiterId: waiterId,
    );
    await _db.recordOrderSent(tableId);
    _ref.invalidate(deliveryStatusProvider);
    _ref.invalidate(tableOrdersProvider(tableId));
    await refresh();
  }

  Future<void> batchSendAndOccupy(
    int tableId,
    List<OrderItem> items, {
    int guestCount = 1,
    String waiterId = '',
  }) async {
    if (items.isEmpty) return;
    await _db.batchSendAndOccupyPending(
      tableId,
      items,
      guestCount: guestCount,
      waiterId: waiterId,
    );
    final user = _ref.read(authProvider);
    if (user != null && user.role == UserRole.waiter) {
      await _db.recordOrderSent(tableId);
      _ref.invalidate(deliveryStatusProvider);
    }
    _ref.invalidate(tableOrdersProvider(tableId));
    await refresh();
  }

  Future<void> updateItemQuantity(
    int tableId,
    String itemId,
    int quantity,
  ) async {
    final user = _ref.read(authProvider);
    if (quantity <= 0) {
      await _db.removeOrderItem(
        tableId,
        itemId,
        cancelledBy: user?.id ?? 0,
        cancelledByName: user?.name ?? '',
      );
    } else {
      await _db.updateOrderItemQuantity(tableId, itemId, quantity);
    }
    _ref.invalidate(tableOrdersProvider(tableId));
    await refresh();
  }

  Future<void> removeItem(int tableId, String itemId) async {
    final user = _ref.read(authProvider);
    await _db.removeOrderItem(
      tableId,
      itemId,
      cancelledBy: user?.id ?? 0,
      cancelledByName: user?.name ?? '',
    );
    _ref.invalidate(tableOrdersProvider(tableId));
    await refresh();
  }

  Future<bool> addNewTable(int id, String name) async {
    if (await _db.isTableIdTaken(id)) return false;
    if (await _db.isTableNameTaken(name)) return false;
    final creatorId = _ref.read(authProvider)?.id ?? 0;
    await _db.addTable(TableModel(id: id, name: name, createdBy: creatorId));
    await refresh();
    return true;
  }

  Future<bool> addTableWithInput(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    final creatorId = _ref.read(authProvider)?.id ?? 0;
    int newId;
    final parsedId = int.tryParse(trimmed);
    if (parsedId != null) {
      if (await _db.isTableNameTaken('مێز $parsedId')) return false;
      if (await _db.isTableNameTaken('$parsedId')) return false;
      final tables = await _db.getAllTables();
      newId = parsedId;
      while (tables.any((t) => t.id == newId)) {
        newId++;
      }
      // Re-derive the display name from the final id so the name never
      // disagrees with the stored id after a collision bump.
      await _db.addTable(
        TableModel(
          id: newId,
          name: newId == parsedId ? 'مێز $parsedId' : 'مێز $newId',
          createdBy: creatorId,
        ),
      );
    } else {
      final tables = await _db.getAllTables();
      newId = 1;
      while (tables.any((t) => t.id == newId)) {
        newId++;
      }
      if (await _db.isTableNameTaken(trimmed)) return false;
      await _db.addTable(
        TableModel(id: newId, name: trimmed, createdBy: creatorId),
      );
    }
    await refreshSilent();
    return true;
  }

  Future<void> deleteTable(
    int tableId, {
    int cancelledBy = 0,
    String cancelledByName = '',
  }) async {
    await _db.deleteTable(
      tableId,
      cancelledBy: cancelledBy,
      cancelledByName: cancelledByName,
    );
    await refresh();
  }

  String generateId() => const Uuid().v4();
}

final waiterProvider =
    StateNotifierProvider<WaiterNotifier, AsyncValue<List<TableModel>>>((ref) {
      final db = ref.read(localDbProvider);
      return WaiterNotifier(db, ref);
    });
