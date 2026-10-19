class OrderItem {
  /// Marks a line whose adder's role is not known.
  ///
  /// A dish stored before `waiterRole` existed - or one that arrived from a
  /// device still running the old build - carries this instead of a guess, so
  /// the screen shows the name alone rather than wrongly calling a cashier's
  /// line the captain's.
  static const int unknownRole = -1;

  final String id;
  final String name;
  final double price;
  int quantity;
  final String category;
  final String createdAt;
  final String waiterName;

  /// Which staff role added this line, as a `UserRole` index
  /// (0 = captain, 1 = cashier, 2 = admin, 3 = owner).
  ///
  /// Stamped at capture from the signed-in user, so the shop can tell a dish the
  /// cashier added from one the captain added. [unknownRole] when the adder is
  /// not known.
  final int waiterRole;

  /// When the till (the central cashier system) confirmed this line.
  ///
  /// Empty means "not there yet": the line is still travelling (or waiting in
  /// the outbox). The captain's delivery screen reads this per line, so one
  /// order can show three dishes already arrived and a fourth still on its way.
  final String syncedAt;

  /// When the first ticket for this line printed successfully.
  final String printedAt;

  /// Printer types (as `PrinterType` indexes) whose ticket for this line is
  /// still owed - a failure, or simply nothing printed yet on that printer.
  ///
  /// A CSV because one dish can be routed to more than one printer (kitchen AND
  /// bar): it only counts as "printed" once every assigned printer has done its
  /// part, and a single missing ticket must keep it in the reprint list.
  final String failedPrinters;

  OrderItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.category = '',
    this.createdAt = '',
    this.waiterName = '',
    this.waiterRole = unknownRole,
    this.syncedAt = '',
    this.printedAt = '',
    this.failedPrinters = '',
  });

  /// The wire payload: deliberately WITHOUT the delivery/print stamps.
  ///
  /// Those stamps belong to THIS device's view of the line (did MY order reach
  /// the till, did the ticket I printed come out) and are never a property of
  /// the line itself - sending them would let a stamp on one handset overwrite
  /// the truth on another.
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'price': price,
    'quantity': quantity,
    'category': category,
    'createdAt': createdAt,
    'waiterName': waiterName,
    'waiterRole': waiterRole,
  };

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
    id: map['id'] as String,
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    quantity: map['quantity'] as int? ?? 1,
    category: map['category'] as String? ?? '',
    createdAt: map['createdAt'] as String? ?? '',
    waiterName: map['waiterName'] as String? ?? '',
    waiterRole: map['waiterRole'] as int? ?? unknownRole,
    syncedAt: map['syncedAt'] as String? ?? '',
    printedAt: map['printedAt'] as String? ?? '',
    failedPrinters: map['failedPrinters'] as String? ?? '',
  );

  /// True once the till confirmed this line (or this device IS the till).
  bool get arrived => syncedAt.isNotEmpty;

  /// True once every printer assigned to this line has printed its ticket.
  bool get printed => printedAt.isNotEmpty && failedPrinterTypes.isEmpty;

  /// The printer types (as `PrinterType` indexes) still owing a ticket.
  List<int> get failedPrinterTypes => failedPrinters
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();

  /// This line still needs a ticket: never printed, or some printer failed.
  bool get needsPrint => !printed;

  OrderItem copyWith({
    int? quantity,
    String? waiterName,
    String? createdAt,
    int? waiterRole,
    String? syncedAt,
    String? printedAt,
    String? failedPrinters,
  }) => OrderItem(
    id: id,
    name: name,
    price: price,
    quantity: quantity ?? this.quantity,
    category: category,
    createdAt: createdAt ?? this.createdAt,
    waiterName: waiterName ?? this.waiterName,
    waiterRole: waiterRole ?? this.waiterRole,
    syncedAt: syncedAt ?? this.syncedAt,
    printedAt: printedAt ?? this.printedAt,
    failedPrinters: failedPrinters ?? this.failedPrinters,
  );
}

class SeatedOrder {
  final int tableId;
  final List<OrderItem> items;
  final double total;
  final String createdAt;

  SeatedOrder({
    required this.tableId,
    required this.items,
    required this.total,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'tableId': tableId,
    'items': items.map((e) => e.toMap()).toList(),
    'total': total,
    'createdAt': createdAt,
  };

  factory SeatedOrder.fromMap(Map<String, dynamic> map) => SeatedOrder(
    tableId: map['tableId'] as int,
    items: (map['items'] as List).map((e) => OrderItem.fromMap(e as Map<String, dynamic>)).toList(),
    total: (map['total'] as num).toDouble(),
    createdAt: map['createdAt'] as String,
  );
}
