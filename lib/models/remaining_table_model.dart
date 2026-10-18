import 'dart:convert';

import 'order_model.dart';

/// A table that was still sitting with an open bill at the moment a cashier
/// closed their shift.
///
/// The snapshot belongs to the admin's shift report only: the table itself is
/// left exactly as it was, nothing is settled or repriced, and the amount is
/// never counted into the shift's money. It answers the one question the report
/// could not - which tables were left un-settled when the cashier walked out.
class RemainingTable {
  final int id;
  final int shiftId;

  /// The device-independent shift identity (cashierId + startedAt), kept beside
  /// [shiftId] so a snapshot that reaches another device can be re-linked to
  /// that device's own shift id.
  final int shiftCashierId;
  final String shiftStartedAt;

  final int tableId;
  final String tableName;
  final int guestCount;
  final String seatedAt;
  final String waiterId;
  final String waiterName;
  final String note;
  final double totalAmount;
  final String itemsJson;
  final String createdAt;

  const RemainingTable({
    this.id = 0,
    required this.shiftId,
    this.shiftCashierId = 0,
    this.shiftStartedAt = '',
    required this.tableId,
    required this.tableName,
    this.guestCount = 0,
    this.seatedAt = '',
    this.waiterId = '',
    this.waiterName = '',
    this.note = '',
    this.totalAmount = 0,
    this.itemsJson = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != 0) 'id': id,
    'shiftId': shiftId,
    'shiftCashierId': shiftCashierId,
    'shiftStartedAt': shiftStartedAt,
    'tableId': tableId,
    'tableName': tableName,
    'guestCount': guestCount,
    'seatedAt': seatedAt,
    'waiterId': waiterId,
    'waiterName': waiterName,
    'note': note,
    'totalAmount': totalAmount,
    'itemsJson': itemsJson,
    'createdAt': createdAt,
  };

  factory RemainingTable.fromMap(Map<String, dynamic> map) => RemainingTable(
    id: map['id'] as int? ?? 0,
    shiftId: map['shiftId'] as int? ?? 0,
    shiftCashierId: map['shiftCashierId'] as int? ?? 0,
    shiftStartedAt: map['shiftStartedAt'] as String? ?? '',
    tableId: map['tableId'] as int? ?? 0,
    tableName: map['tableName'] as String? ?? '',
    guestCount: map['guestCount'] as int? ?? 0,
    seatedAt: map['seatedAt'] as String? ?? '',
    waiterId: map['waiterId'] as String? ?? '',
    waiterName: map['waiterName'] as String? ?? '',
    note: map['note'] as String? ?? '',
    totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0,
    itemsJson: map['itemsJson'] as String? ?? '',
    createdAt: map['createdAt'] as String? ?? '',
  );
}

/// One dish on a remaining-table snapshot: what it was, what it cost and who
/// rang it in.
class RemainingTableItem {
  final String name;
  final double price;
  final int quantity;
  final String category;
  final String waiterName;
  final int waiterRole;

  const RemainingTableItem({
    required this.name,
    required this.price,
    this.quantity = 1,
    this.category = '',
    this.waiterName = '',
    this.waiterRole = OrderItem.unknownRole,
  });

  double get subtotal => price * quantity;
}

/// Encodes the dishes of one remaining table into [RemainingTable.itemsJson].
String encodeRemainingTableItems(Iterable<OrderItem> items) => jsonEncode(
  items
      .map(
        (i) => {
          'name': i.name,
          'price': i.price,
          'quantity': i.quantity,
          'category': i.category,
          'waiterName': i.waiterName,
          'waiterRole': i.waiterRole,
        },
      )
      .toList(),
);

/// Decodes [RemainingTable.itemsJson]; a blank or unparsable value yields an
/// empty list so a bad row can never crash the report.
List<RemainingTableItem> decodeRemainingTableItems(String itemsJson) {
  if (itemsJson.isEmpty) return const [];
  try {
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (m) => RemainingTableItem(
            name: m['name'] as String? ?? '',
            price: (m['price'] as num?)?.toDouble() ?? 0,
            quantity: (m['quantity'] as num?)?.toInt() ?? 1,
            category: m['category'] as String? ?? '',
            waiterName: m['waiterName'] as String? ?? '',
            waiterRole:
                (m['waiterRole'] as num?)?.toInt() ?? OrderItem.unknownRole,
          ),
        )
        .toList();
  } catch (_) {
    return const [];
  }
}
