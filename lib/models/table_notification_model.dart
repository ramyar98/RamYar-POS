import 'table_model.dart';

class TableNotification {
  final int id;
  final int tableId;
  final String tableName;
  final TableStatus status;
  final double totalAmount;
  final String openedAt;

  const TableNotification({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.status,
    required this.totalAmount,
    required this.openedAt,
  });

  DateTime? get _openedDateTime => DateTime.tryParse(openedAt);

  String formattedOpenedAmPm({String am = 'AM', String pm = 'PM'}) {
    final dt = _openedDateTime;
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ap = dt.hour >= 12 ? pm : am;
    return '${two(h)}:${two(dt.minute)} $ap';
  }

  factory TableNotification.fromMap(Map<String, dynamic> map) => TableNotification(
    id: map['nid'] as int,
    tableId: map['tableId'] as int,
    tableName: map['tableName'] as String,
    status: tableStatusFrom(map['status']),
    totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
    openedAt: map['openedAt'] as String,
  );
}