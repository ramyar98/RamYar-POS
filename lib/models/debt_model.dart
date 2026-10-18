import 'dart:convert';

class DebtModel {
  final int id;
  final int tableId;
  final String tableName;
  final double amount;
  final String reason;
  final String createdAt;
  final int createdBy;

  /// The cashier shift this debt was opened under.
  ///
  /// A debt lives and dies with the shift that rang it up: when that shift is
  /// closed the debt leaves the cashier's «قەرزەکان» list, and the next shift
  /// starts with an empty one. Rows written before the column existed carry 0
  /// and therefore belong to no shift - they show on the admin's record only.
  final int shiftId;

  /// A JSON snapshot of the dishes that were on the table when it was moved to
  /// «قەرزەکان»: `[{"name": ..., "price": ..., "quantity": ...}, ...]`.
  ///
  /// Moving a table to credit clears its order, so this is the only record of
  /// what was ordered. Empty for debts opened before the column existed (or for
  /// hand-entered debts with no table order behind them).
  final String itemsJson;

  const DebtModel({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.amount,
    this.reason = '',
    required this.createdAt,
    required this.createdBy,
    this.shiftId = 0,
    this.itemsJson = '',
  });

  Map<String, dynamic> toMap() => {
    if (id != 0) 'id': id,
    'tableId': tableId,
    'tableName': tableName,
    'amount': amount,
    'reason': reason,
    'createdAt': createdAt,
    'createdBy': createdBy,
    'shiftId': shiftId,
    'itemsJson': itemsJson,
  };

  factory DebtModel.fromMap(Map<String, dynamic> map) => DebtModel(
    id: map['id'] as int,
    tableId: map['tableId'] as int,
    tableName: map['tableName'] as String,
    amount: (map['amount'] as num).toDouble(),
    reason: map['reason'] as String? ?? '',
    createdAt: map['createdAt'] as String,
    createdBy: map['createdBy'] as int,
    shiftId: map['shiftId'] as int? ?? 0,
    itemsJson: map['itemsJson'] as String? ?? '',
  );

  DebtModel copyWith({double? amount, String? reason}) => DebtModel(
    id: id,
    tableId: tableId,
    tableName: tableName,
    amount: amount ?? this.amount,
    reason: reason ?? this.reason,
    createdAt: createdAt,
    createdBy: createdBy,
    shiftId: shiftId,
    itemsJson: itemsJson,
  );
}

/// One dish stored on a debt's snapshot.
class DebtLine {
  final String name;
  final double price;
  final int quantity;

  const DebtLine({
    required this.name,
    required this.price,
    required this.quantity,
  });

  double get subtotal => price * quantity;
}

/// A JSON snapshot of the dishes that were on a table when it went to credit.
String encodeDebtLines(Iterable<DebtLine> lines) => jsonEncode(
  lines
      .map((l) => {'name': l.name, 'price': l.price, 'quantity': l.quantity})
      .toList(),
);

/// Decodes [DebtModel.itemsJson]; returns an empty list for blanks or anything
/// that will not parse, so a bad row can never crash the report.
List<DebtLine> decodeDebtLines(String itemsJson) {
  if (itemsJson.isEmpty) return const [];
  try {
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (m) => DebtLine(
            name: m['name'] as String? ?? '',
            price: (m['price'] as num?)?.toDouble() ?? 0,
            quantity: (m['quantity'] as num?)?.toInt() ?? 1,
          ),
        )
        .toList();
  } catch (_) {
    return const [];
  }
}
