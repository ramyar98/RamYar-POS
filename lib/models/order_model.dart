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

  OrderItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.category = '',
    this.createdAt = '',
    this.waiterName = '',
    this.waiterRole = unknownRole,
  });

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
  );

  OrderItem copyWith({
    int? quantity,
    String? waiterName,
    String? createdAt,
    int? waiterRole,
  }) => OrderItem(
    id: id,
    name: name,
    price: price,
    quantity: quantity ?? this.quantity,
    category: category,
    createdAt: createdAt ?? this.createdAt,
    waiterName: waiterName ?? this.waiterName,
    waiterRole: waiterRole ?? this.waiterRole,
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
