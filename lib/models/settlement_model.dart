class SettledOrder {
  final int id;
  final int tableId;
  final String tableName;
  final double totalAmount;
  final double discountPercent;
  final double discountAmount;
  final String settledAt;
  final int settledBy;
  final int shiftId;
  final String seatedAt;
  final String paymentMethod;
  final String waiterId;

  /// The table's note at the moment it was settled - the captain's line plus the
  /// cashier's line, packed exactly as `tables.note` stores them (see
  /// `decodeTableNote`). Shown to the admin in the shift report; never printed.
  final String note;

  const SettledOrder({
    this.id = 0,
    required this.tableId,
    required this.tableName,
    required this.totalAmount,
    this.discountPercent = 0,
    this.discountAmount = 0,
    required this.settledAt,
    required this.settledBy,
    this.shiftId = 0,
    this.seatedAt = '',
    this.paymentMethod = 'cash',
    this.waiterId = '',
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'tableId': tableId,
    'tableName': tableName,
    'totalAmount': totalAmount,
    'discountPercent': discountPercent,
    'discountAmount': discountAmount,
    'settledAt': settledAt,
    'settledBy': settledBy,
    'shiftId': shiftId,
    'seatedAt': seatedAt,
    'paymentMethod': paymentMethod,
    'waiterId': waiterId,
    'note': note,
  };

  factory SettledOrder.fromMap(Map<String, dynamic> map) => SettledOrder(
    id: map['id'] as int,
    tableId: map['tableId'] as int,
    tableName: map['tableName'] as String,
    totalAmount: (map['totalAmount'] as num).toDouble(),
    discountPercent: (map['discountPercent'] as num?)?.toDouble() ?? 0,
    discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
    settledAt: map['settledAt'] as String,
    settledBy: map['settledBy'] as int,
    shiftId: map['shiftId'] as int? ?? 0,
    seatedAt: map['seatedAt'] as String? ?? '',
    paymentMethod: map['paymentMethod'] as String? ?? 'cash',
    waiterId: map['waiterId'] as String? ?? '',
    note: map['note'] as String? ?? '',
  );
}

class SettledOrderItem {
  final int id;
  final int settledOrderId;
  final String itemName;
  final double itemPrice;
  final int quantity;
  final String category;

  /// Who rang this dish in, copied from the order line at settlement: the name
  /// and the `UserRole` index (0 = captain, 1 = cashier, ...). -1 / empty when
  /// the adder is not known (rows settled before the columns existed).
  ///
  /// The captain report credits a sale to this pair, not to the table's waiter,
  /// so a cashier who added food to a table is counted as the salesperson.
  final String waiterName;
  final int waiterRole;

  const SettledOrderItem({
    this.id = 0,
    required this.settledOrderId,
    required this.itemName,
    required this.itemPrice,
    required this.quantity,
    this.category = '',
    this.waiterName = '',
    this.waiterRole = -1,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'settledOrderId': settledOrderId,
    'itemName': itemName,
    'itemPrice': itemPrice,
    'quantity': quantity,
    'category': category,
    'waiterName': waiterName,
    'waiterRole': waiterRole,
  };

  factory SettledOrderItem.fromMap(Map<String, dynamic> map) => SettledOrderItem(
    id: map['id'] as int,
    settledOrderId: map['settledOrderId'] as int,
    itemName: map['itemName'] as String,
    itemPrice: (map['itemPrice'] as num).toDouble(),
    quantity: map['quantity'] as int,
    category: map['category'] as String? ?? '',
    waiterName: map['waiterName'] as String? ?? '',
    waiterRole: map['waiterRole'] as int? ?? -1,
  );
}

class CashierShift {
  final int id;
  final int cashierId;
  final String cashierName;
  final String startedAt;
  final String? endedAt;
  final double totalCollected;

  const CashierShift({
    this.id = 0,
    required this.cashierId,
    required this.cashierName,
    required this.startedAt,
    this.endedAt,
    this.totalCollected = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'cashierId': cashierId,
    'cashierName': cashierName,
    'startedAt': startedAt,
    'endedAt': endedAt ?? '',
    'totalCollected': totalCollected,
  };

  factory CashierShift.fromMap(Map<String, dynamic> map) => CashierShift(
    id: map['id'] as int,
    cashierId: map['cashierId'] as int,
    cashierName: map['cashierName'] as String,
    startedAt: map['startedAt'] as String,
    endedAt: map['endedAt'] as String? ?? '',
    totalCollected: (map['totalCollected'] as num?)?.toDouble() ?? 0,
  );

  CashierShift copyWith({String? endedAt, double? totalCollected}) => CashierShift(
    id: id,
    cashierId: cashierId,
    cashierName: cashierName,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    totalCollected: totalCollected ?? this.totalCollected,
  );
}

class Purchase {
  final int id;
  final String itemName;
  final double price;
  final String purchasedAt;
  final int purchasedBy;

  const Purchase({
    this.id = 0,
    required this.itemName,
    required this.price,
    required this.purchasedAt,
    required this.purchasedBy,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'itemName': itemName,
    'price': price,
    'purchasedAt': purchasedAt,
    'purchasedBy': purchasedBy,
  };

  factory Purchase.fromMap(Map<String, dynamic> map) => Purchase(
    id: map['id'] as int,
    itemName: map['itemName'] as String,
    price: (map['price'] as num).toDouble(),
    purchasedAt: map['purchasedAt'] as String,
    purchasedBy: map['purchasedBy'] as int,
  );
}

class CashierExpense {
  final int id;
  final int shiftId;
  final String itemName;
  final double price;
  final String createdAt;

  const CashierExpense({
    this.id = 0,
    required this.shiftId,
    required this.itemName,
    required this.price,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'shiftId': shiftId,
    'itemName': itemName,
    'price': price,
    'createdAt': createdAt,
  };

  factory CashierExpense.fromMap(Map<String, dynamic> map) => CashierExpense(
    id: map['id'] as int,
    shiftId: map['shiftId'] as int,
    itemName: map['itemName'] as String,
    price: (map['price'] as num).toDouble(),
    createdAt: map['createdAt'] as String,
  );
}

class Refund {
  final int id;
  final int tableId;
  final String itemName;
  final int quantity;
  final double price;
  final String refundedAt;
  final int refundedBy;
  final int shiftId;

  const Refund({
    this.id = 0,
    required this.tableId,
    required this.itemName,
    required this.quantity,
    required this.price,
    required this.refundedAt,
    required this.refundedBy,
    this.shiftId = 0,
  });

  Map<String, dynamic> toMap() => {
    if (id != 0) 'id': id,
    'tableId': tableId,
    'itemName': itemName,
    'quantity': quantity,
    'price': price,
    'refundedAt': refundedAt,
    'refundedBy': refundedBy,
    'shiftId': shiftId,
  };

  factory Refund.fromMap(Map<String, dynamic> map) => Refund(
    id: map['id'] as int,
    tableId: map['tableId'] as int,
    itemName: map['itemName'] as String,
    quantity: map['quantity'] as int,
    price: (map['price'] as num).toDouble(),
    refundedAt: map['refundedAt'] as String,
    refundedBy: map['refundedBy'] as int,
    shiftId: map['shiftId'] as int? ?? 0,
  );
}
