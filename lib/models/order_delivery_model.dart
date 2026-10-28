/// One dish of a sent order, as the delivery screen sees it.
///
/// The delivery page works per LINE, not per table: "did THIS dish reach the
/// till?" and "did THIS dish's ticket come out of ITS printer?" are the two
/// questions the captain actually asks, and an order where four of five dishes
/// made it must be able to say so.
class DeliveryItemStatus {
  final String id;
  final String name;
  final int quantity;
  final String category;

  /// When the till confirmed the line; empty = still travelling.
  final String syncedAt;

  /// First successful ticket for the line; empty = nothing printed yet.
  final String printedAt;

  /// Printer types (`PrinterType` indexes, CSV) still owing a ticket.
  final String failedPrinters;

  const DeliveryItemStatus({
    required this.id,
    required this.name,
    this.quantity = 1,
    this.category = '',
    this.syncedAt = '',
    this.printedAt = '',
    this.failedPrinters = '',
  });

  /// True once the till confirmed this line.
  bool get arrived => syncedAt.isNotEmpty;

  /// Printer types still owing a ticket for this line.
  List<int> get failedPrinterTypes => failedPrinters
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();

  /// A printer assigned to this line failed its ticket.
  bool get printFailed => failedPrinterTypes.isNotEmpty;

  /// Every assigned printer has printed this line.
  bool get printed => printedAt.isNotEmpty && !printFailed;

  /// Not printed at all, or some assigned printer is still owed a ticket.
  /// Anything in here belongs in the "دوبارە پرێنت" filter.
  bool get needsPrint => !printed;
}

class OrderDeliveryModel {
  final int tableId;
  final String sentAt;
  final String arrivedAt;
  final String printedAt;
  final String printFailedAt;
  final bool rejected;

  /// Per-dish delivery state, newest truth for the delivery screen.
  ///
  /// Empty only for legacy rows (no dishes readable) - in that case the
  /// table-level timestamps above still drive the UI exactly as before.
  final List<DeliveryItemStatus> items;

  const OrderDeliveryModel({
    required this.tableId,
    required this.sentAt,
    this.arrivedAt = '',
    this.printedAt = '',
    this.printFailedAt = '',
    this.rejected = false,
    this.items = const [],
  });

  bool get hasArrived => arrivedAt.isNotEmpty;
  bool get hasPrinted => printedAt.isNotEmpty;
  bool get isPrintFailed => printFailedAt.isNotEmpty && !hasPrinted;
  bool get isNotArrived =>
      !hasArrived &&
      !hasPrinted &&
      !isPrintFailed &&
      !rejected &&
      !shouldAutoExpire;
  bool get isPrinted => hasPrinted && !rejected && !shouldAutoExpire;
  bool get isRetryPrint => isPrintFailed && !rejected && !shouldAutoExpire;
  bool get shouldAutoExpire {
    if (rejected || hasPrinted) return false;
    final sent = DateTime.tryParse(sentAt);
    if (sent == null) return false;
    final age = DateTime.now().difference(sent.toLocal());
    return age >= const Duration(hours: 3);
  }

  bool get needsResend => isNotArrived && !shouldAutoExpire;
  bool get canRetry => needsResend || isRetryPrint;

  // ==================== Item-level truth ====================

  bool get hasItemState => items.isNotEmpty;
  int get itemTotal => items.length;
  int get arrivedItemCount => items.where((i) => i.arrived).length;
  int get printedItemCount => items.where((i) => i.printed).length;

  /// Dishes the till has not confirmed yet - the "نەگەیشت" filter.
  List<DeliveryItemStatus> get pendingItems =>
      items.where((i) => !i.arrived).toList();

  /// Dishes whose ticket is missing somewhere - the "دوبارە پرێنت" filter.
  List<DeliveryItemStatus> get unprintedItems =>
      items.where((i) => i.needsPrint).toList();

  bool get allItemsArrived => items.isNotEmpty && arrivedItemCount == itemTotal;
  bool get allItemsPrinted => items.isNotEmpty && printedItemCount == itemTotal;
  bool get anyItemPrintFailed => items.any((i) => i.printFailed);

  /// The pill shown on the card: item truth when there are dishes, the
  /// table-level timestamps as a legacy fallback.
  String get itemStatusLabel {
    if (rejected) return 'rejected';
    if (items.isEmpty) return statusLabel;
    if (allItemsPrinted) return 'printed';
    if (allItemsArrived) return anyItemPrintFailed ? 'print_failed' : 'arrived';
    // Partial arrival (or nothing arrived): the still-travelling dishes are
    // the urgent thing, so the card reads as waiting.
    return 'not_arrived';
  }

  OrderDeliveryModel withItems(List<DeliveryItemStatus> newItems) =>
      OrderDeliveryModel(
        tableId: tableId,
        sentAt: sentAt,
        arrivedAt: arrivedAt,
        printedAt: printedAt,
        printFailedAt: printFailedAt,
        rejected: rejected,
        items: newItems,
      );

  String get statusLabel {
    if (rejected) return 'rejected';
    if (hasPrinted) return 'printed';
    if (isPrintFailed) return 'print_failed';
    if (hasArrived) return 'arrived';
    return 'not_arrived';
  }

  factory OrderDeliveryModel.fromMap(Map<String, dynamic> map) =>
      OrderDeliveryModel(
        tableId: map['tableId'] as int,
        sentAt: map['sentAt'] as String,
        arrivedAt: map['arrivedAt'] as String? ?? '',
        printedAt: map['printedAt'] as String? ?? '',
        printFailedAt: map['printFailedAt'] as String? ?? '',
        rejected: (map['rejected'] as int? ?? 0) == 1,
      );
}

/// One table's sending state as the CASHIER's device sees it.
///
/// The captain's [OrderDeliveryModel] is built from `order_delivery` rows, and
/// those rows exist only on the device that sent the order. The till therefore
/// never has them - but it does have the table and its dishes, and those carry
/// the two facts the cashier needs: `order_items.syncedAt` (this line reached
/// the till) and `order_items.printedAt` / `failedPrinters` (this line's ticket
/// came out of every printer it was routed to).
///
/// The cashier needs this view because they can add food to a table before the
/// captain has started their shift. Without it, a dish added on the till that
/// never printed has nowhere to be seen.
class TillDeliveryModel {
  final int tableId;

  /// What the till calls the table ("مێزی 1", or the name the cashier gave it).
  final String tableName;

  /// When the guests sat down; empty for a table that was never seated.
  final String seatedAt;

  /// Newest dish time on the table - what the card shows as "نێردراوە".
  final String sentAt;

  /// The captain who opened the table, when known.
  final String waiterName;

  /// Per-dish delivery state, ordered as the dishes were added.
  final List<DeliveryItemStatus> items;

  const TillDeliveryModel({
    required this.tableId,
    required this.tableName,
    this.seatedAt = '',
    this.sentAt = '',
    this.waiterName = '',
    this.items = const [],
  });

  bool get hasItemState => items.isNotEmpty;
  int get itemTotal => items.length;
  int get arrivedItemCount => items.where((i) => i.arrived).length;
  int get printedItemCount => items.where((i) => i.printed).length;

  /// Dishes that have not reached the till yet - the «نەگەیشت» filter.
  List<DeliveryItemStatus> get pendingItems =>
      items.where((i) => !i.arrived).toList();

  /// Dishes still owing a ticket somewhere - the «دوبارە پرێنت» filter.
  List<DeliveryItemStatus> get unprintedItems =>
      items.where((i) => i.needsPrint).toList();

  bool get allArrived => items.isNotEmpty && arrivedItemCount == itemTotal;
  bool get allPrinted => items.isNotEmpty && printedItemCount == itemTotal;
  bool get anyPrintFailed => items.any((i) => i.printFailed);

  /// The pill shown on the card.
  ///
  /// Only four states, because a till card is a question with four answers:
  /// did the food get here, and did the ticket come out?
  String get statusLabel {
    if (items.isEmpty) return 'not_arrived';
    if (allPrinted) return 'printed';
    if (!allArrived) return 'not_arrived';
    return 'print_failed';
  }
}
