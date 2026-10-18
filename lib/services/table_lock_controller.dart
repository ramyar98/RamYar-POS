import 'dart:async';

import '../core/app_log.dart';
import '../database/local_db.dart';
import '../models/table_lock_model.dart';
import 'sync_provider.dart';

/// Why a table page lost its claim on a table.
enum TableLockLoss {
  /// Another user is already working this table. The page must not open.
  heldByAnotherUser,

  /// The claim was taken away while the page was open - the cashier threw this
  /// captain off the table, or another device took the table over.
  takenAway,
}

/// Owns one device's claim on one table for as long as a table page is open.
///
/// Every page that can hold a table (the captain's and the cashier's) used to
/// grow its own copy of this logic, and both copies were wrong in the same way:
/// they took the lock once and then never said anything again. The lock's
/// expiry is a safety net for a device that died, not a normal path, so a
/// silent owner looked exactly like a dead one - after a few seconds every
/// other captain was let into a table that already had one. This controller
/// keeps the claim alive with a heartbeat and, just as importantly, notices
/// when the claim is gone and tells the page so the person is not left standing
/// at a table that is no longer theirs.
class TableLockController {
  TableLockController({
    required this.db,
    required this.tableId,
    required this.userId,
    required this.userName,
    required this.role,
    required this.onLost,
  });

  final LocalDatabase db;
  final int tableId;
  final int userId;
  final String userName;
  final String role;
  final void Function(TableLockLoss reason) onLost;

  /// Identifies this one open table page, so a page can only ever release or
  /// refresh the claim it made itself.
  late final String deviceId =
      '$role-$userId-${DateTime.now().microsecondsSinceEpoch}';

  Timer? _timer;
  StreamSubscription<int>? _ejectionSub;
  bool _released = false;
  bool _lostNotified = false;

  /// Takes the table if it is free. Returns false - without disturbing anyone -
  /// when another user already holds it, in which case the caller must not open
  /// the page.
  ///
  /// [force] takes the table from whoever has it. Cashiers use it: they are
  /// never kept out of a table, and the hold screen in front of their page is
  /// what makes them ask before they get here.
  Future<bool> acquire({bool force = false}) async {
    if (!force) {
      final existing = await db.getTableLockById(tableId);
      if (_released) return false;
      if (existing != null && !existing.isHeldBy(userId)) return false;
    }
    await db.lockTable(TableLock(
      tableId: tableId,
      deviceId: deviceId,
      userId: userId,
      userName: userName,
      role: role,
    ));
    // A page can be closed again while this is still in flight - people open and
    // abandon tables fast. Writing the row after the release ran would leave a
    // lock nobody will ever clear, and that table then stays shut to every
    // captain until the row times out on its own.
    if (_released) {
      await db.unlockTable(tableId, deviceId);
      return false;
    }
    _broadcast('TABLE_LOCK_ACQUIRED');
    _watchEjections();
    _startHeartbeat();
    return true;
  }

  /// Stops the claim and cleans up every timer and listener. Safe to call more
  /// than once; the page's `dispose` and a lost claim both reach it.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    _timer?.cancel();
    _timer = null;
    // The delete is issued before anything is awaited. An await in between hands
    // control back to a still-running `acquire()`, whose insert can then land
    // after the row was removed - and the orphan that leaves behind looks to
    // every other captain exactly like a table somebody is working.
    // The delete is issued before anything is awaited. An await in between hands
    // control back to a still-running `acquire()`, whose insert can then land
    // after the row was removed - and the orphan that leaves behind looks to
    // every other captain exactly like a table somebody is working.
    final removed = db.unlockTable(tableId, deviceId);
    await _ejectionSub?.cancel();
    _ejectionSub = null;
    try {
      await removed;
    } catch (e) {
      appLog('[TableLock] release failed for table $tableId: $e');
    }
    _broadcast('TABLE_LOCK_RELEASED');
  }

  void _watchEjections() {
    _ejectionSub = db.tableEjections
        .where((id) => id == tableId)
        .listen((_) => _lose(TableLockLoss.takenAway));
  }

  void _startHeartbeat() {
    _timer?.cancel();
    _timer = Timer.periodic(kTableLockHeartbeatInterval, (_) => _beat());
    // The claim has to be alive before the first beat interval elapses, or a
    // page opened right after another one closed could be told it lost a table
    // it still holds.
    unawaited(_beat());
  }

  Future<void> _beat() async {
    if (_released || _lostNotified) return;
    try {
      await db.updateLockHeartbeat(tableId, deviceId);
      final lock = await db.getTableLockById(tableId);
      // The row is gone, expired, or now belongs to somebody else. Any of those
      // means this page is standing at a table that is not its own, so it has
      // to step out rather than carry on serving it.
      if (lock == null || !lock.isHeldBy(userId)) {
        _lose(TableLockLoss.takenAway);
        return;
      }
      _broadcast('TABLE_LOCK_HEARTBEAT');
    } catch (e) {
      appLog('[TableLock] heartbeat failed for table $tableId: $e');
    }
  }

  void _lose(TableLockLoss reason) {
    if (_lostNotified) return;
    _lostNotified = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_ejectionSub?.cancel());
    _ejectionSub = null;
    onLost(reason);
  }

  /// The claim is gone and the page should not be opened at all.
  void loseImmediately(TableLockLoss reason) => _lose(reason);

  void _broadcast(String action) {
    final payload = <String, dynamic>{
      'tableId': tableId,
      'deviceId': deviceId,
      'userId': userId,
      'userName': userName,
      'role': role,
    };
    try {
      final client = syncClient;
      if (client != null && client.isConnected) {
        client.sendMutation(payload, action: action);
        return;
      }
      final server = syncServer;
      if (server != null && server.isRunning) {
        server.broadcastMutation(payload, action: action);
      }
    } catch (e) {
      appLog('[TableLock] broadcast $action failed: $e');
    }
  }
}
