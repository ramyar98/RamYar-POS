import '../database/local_db.dart';
import '../models/order_model.dart';

/// What to do with an order batch that arrived from another device.
enum OrderConflictOutcome {
  /// The batch carries items this table does not have yet: insert them and add
  /// them to the total.
  apply,

  /// Every item in the batch is already on this table under the same id, so
  /// there is nothing to insert. This is the same batch being delivered a
  /// second time - a reconnect flush, or a repeat of one message - and the
  /// order is genuinely on the table, so the caller still reports success.
  alreadyApplied,
}

/// True when [incoming] would add nothing to [existing].
///
/// Identity is the item's own id: a uuid minted once, on the device that rang
/// the item in, and carried unchanged all the way to the hub.
///
/// It used to compare name + price + quantity instead, and that quietly threw
/// away real orders. A captain who asked for one kebab and then, ten minutes
/// later, asked for one kebab again - an ordinary second round - had the second
/// one dropped on the cashier's device: the captain's screen showed it, the
/// cashier's never did, and the table's total was short by one kebab. With the
/// id as the identity, a second round is a new id and is applied, while a
/// genuine repeat of the same batch is still caught and ignored.
///
/// An item with no id cannot be reasoned about, so such a batch is applied and
/// left to the database.
bool addsNothingNew(List<OrderItem> incoming, List<OrderItem> existing) {
  if (incoming.isEmpty || existing.isEmpty) return false;
  if (incoming.any((i) => i.id.isEmpty)) return false;
  final existingIds = existing.map((e) => e.id).where((id) => id.isNotEmpty).toSet();
  if (existingIds.isEmpty) return false;
  return incoming.every((i) => existingIds.contains(i.id));
}

/// Works out whether an order batch arriving for [tableId] is new.
///
/// There is deliberately no "replace what is there" outcome any more. It existed
/// to settle two devices holding the same order, and the id check above settles
/// that case exactly. What it also did was delete real items: a device whose
/// clock was slightly behind would send a batch stamped a moment earlier, and
/// the hub would throw away everything already on the table. On a till that is
/// money walking off the screen, so orders are only ever added.
Future<OrderConflictOutcome> resolveOrderConflict(
  LocalDatabase db,
  int tableId,
  List<OrderItem> incoming,
) async {
  final existing = await db.getOrderItems(tableId);
  if (addsNothingNew(incoming, existing)) return OrderConflictOutcome.alreadyApplied;
  return OrderConflictOutcome.apply;
}
