class CancelledItem {
  final int id;

  /// The shift this rejection belongs to, as a row id on the device that
  /// recorded it. Auto-increment ids differ per device, so scoping by this alone
  /// hides a real rejection when the number collides with an unrelated shift
  /// here; [shiftCashierId] + [shiftStartedAt] are the device-independent key
  /// that always names the same shift (see `_shiftKeyFor` in the database).
  final int shiftId;

  /// Device-independent identity of the shift this rejection belongs to: the
  /// cashier and the shift's start time, which together name the same shift on
  /// every device. 0 / empty on records from before these columns existed, which
  /// fall back to [shiftId].
  final int shiftCashierId;
  final String shiftStartedAt;

  final int tableId;
  final String tableName;
  final String itemName;
  final double itemPrice;
  final int quantity;
  final String category;
  final String cancelledAt;
  final int cancelledBy;
  final String cancelledByName;
  final String requestedByName;

  /// When the dish was first ordered onto its table (the order row's
  /// `createdAt`), so the record answers "when was it ordered" and "when was
  /// it cancelled" together. Empty on records from before this column existed.
  final String requestedAt;

  /// Role of the person who ordered the dish (see `UserRole`): 0 is the
  /// waiter/captain, 1 the cashier. 0 with an empty name is an unknown hand.
  final int requestedByRole;

  final String status;
  final String servedAt;

  const CancelledItem({
    this.id = 0,
    this.shiftId = 0,
    this.shiftCashierId = 0,
    this.shiftStartedAt = '',
    required this.tableId,
    required this.tableName,
    required this.itemName,
    required this.itemPrice,
    this.quantity = 1,
    this.category = '',
    required this.cancelledAt,
    this.cancelledBy = 0,
    this.cancelledByName = '',
    this.requestedByName = '',
    this.requestedAt = '',
    this.requestedByRole = 0,
    this.status = 'pending',
    this.servedAt = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'shiftId': shiftId,
    'shiftCashierId': shiftCashierId,
    'shiftStartedAt': shiftStartedAt,
    'tableId': tableId,
    'tableName': tableName,
    'itemName': itemName,
    'itemPrice': itemPrice,
    'quantity': quantity,
    'category': category,
    'cancelledAt': cancelledAt,
    'cancelledBy': cancelledBy,
    'cancelledByName': cancelledByName,
    'requestedByName': requestedByName,
    'requestedAt': requestedAt,
    'requestedByRole': requestedByRole,
    'status': status,
    'servedAt': servedAt,
  };

  factory CancelledItem.fromMap(Map<String, dynamic> map) => CancelledItem(
    id: map['id'] as int? ?? 0,
    shiftId: map['shiftId'] as int? ?? 0,
    shiftCashierId: map['shiftCashierId'] as int? ?? 0,
    shiftStartedAt: map['shiftStartedAt'] as String? ?? '',
    tableId: map['tableId'] as int,
    tableName: map['tableName'] as String? ?? '',
    itemName: map['itemName'] as String,
    itemPrice: (map['itemPrice'] as num?)?.toDouble() ?? 0,
    quantity: map['quantity'] as int? ?? 1,
    category: map['category'] as String? ?? '',
    cancelledAt: map['cancelledAt'] as String? ?? '',
    cancelledBy: map['cancelledBy'] as int? ?? 0,
    cancelledByName: map['cancelledByName'] as String? ?? '',
    requestedByName: map['requestedByName'] as String? ?? '',
    requestedAt: map['requestedAt'] as String? ?? '',
    requestedByRole: map['requestedByRole'] as int? ?? 0,
    status: map['status'] as String? ?? 'pending',
    servedAt: map['servedAt'] as String? ?? '',
  );

  CancelledItem copyWith({
    String? status,
    String? servedAt,
    String? requestedByName,
    String? requestedAt,
    int? requestedByRole,
  }) => CancelledItem(
    id: id,
    shiftId: shiftId,
    shiftCashierId: shiftCashierId,
    shiftStartedAt: shiftStartedAt,
    tableId: tableId,
    tableName: tableName,
    itemName: itemName,
    itemPrice: itemPrice,
    quantity: quantity,
    category: category,
    cancelledAt: cancelledAt,
    cancelledBy: cancelledBy,
    cancelledByName: cancelledByName,
    requestedByName: requestedByName ?? this.requestedByName,
    requestedAt: requestedAt ?? this.requestedAt,
    requestedByRole: requestedByRole ?? this.requestedByRole,
    status: status ?? this.status,
    servedAt: servedAt ?? this.servedAt,
  );
}
