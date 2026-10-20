enum TableStatus { empty, occupied, billRequested, overdue }

/// Reads a stored table status without ever throwing.
///
/// `TableStatus.values[raw]` throws a RangeError on any value the enum does not
/// have: a row written by a newer build, a hand-edited database, or a NULL that
/// slipped past the `?? 0`. An unreadable status must not take the whole floor
/// down, so it degrades to [TableStatus.empty].
TableStatus tableStatusFrom(Object? raw) {
  final index = raw is int ? raw : int.tryParse('${raw ?? ''}');
  if (index == null || index < 0 || index >= TableStatus.values.length) {
    return TableStatus.empty;
  }
  return TableStatus.values[index];
}

class TableModel {
  final int id;
  final String name;
  final TableStatus status;
  final String seatedTime;
  final String waiterId;
  final double totalAmount;
  final int guestCount;
  final bool sentToCashier;
  final String printedAt;
  final String note;
  final String noteUpdatedAt;
  final int createdBy;

  /// The user id of whoever first seated this table (captain or cashier), or 0
  /// when unknown.
  ///
  /// Distinct from [createdBy], which is the table's range owner - the captain
  /// the floor row was assigned to - not the person who actually opened it. Set
  /// once, on the empty-to-occupied transition, and never overwritten while the
  /// same sitting is open.
  final int openedBy;

  /// True for a delivery slot ("دلیڤەری تەلەبات 3") rather than a table in the
  /// dining room.
  ///
  /// A delivery order is a real order: it has items, a total, a bill, a print
  /// and it travels to the kitchen. So a slot is a genuine table row carrying
  /// this flag instead of a separate kind of record that would need all of that
  /// built twice. The flag is what keeps the dining room free of them.
  final bool isDelivery;

  /// The company this slot belongs to ([isDelivery] only).
  final int deliveryCompanyId;

  /// Which slot of that company, 1-based ([isDelivery] only).
  final int deliverySlot;

  String get formattedSeatedTime {
    if (seatedTime.isEmpty) return '';
    // Guard the tail length: a hand-edited/legacy row like "2026-01-01T9" used
    // to throw RangeError from substring(0, 5) and blank the whole table card.
    String hhmm(String tail) => tail.length >= 5 ? tail.substring(0, 5) : tail;
    if (seatedTime.contains('T')) {
      final parts = seatedTime.split('T');
      return hhmm(parts[1]);
    }
    if (seatedTime.contains(' ')) {
      final parts = seatedTime.split(' ');
      return hhmm(parts[1]);
    }
    return hhmm(seatedTime);
  }

  DateTime? _seatedDateTime() {
    if (seatedTime.isEmpty) return null;
    return DateTime.tryParse(seatedTime);
  }

  String get formattedSeatedDate {
    final dt = _seatedDateTime();
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)}';
  }

  String formattedSeatedTimeAmPm({String am = 'AM', String pm = 'PM'}) {
    final dt = _seatedDateTime();
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ap = dt.hour >= 12 ? pm : am;
    return '${two(h)}:${two(dt.minute)} $ap';
  }

  /// The seating time as the cashier should read it, or `-` when there is none.
  ///
  /// Never hand [seatedTime] itself to a label. It is what the database stores -
  /// `2026-10-03T15:26:30.465168` - and the bill header printed it verbatim
  /// while the floor card two taps away said `03:26 PM`, which is both ugly and
  /// a giveaway that the number is machine output rather than something the
  /// shop wrote.
  String seatedTimeDisplay({String am = 'AM', String pm = 'PM'}) {
    final formatted = formattedSeatedTimeAmPm(am: am, pm: pm);
    return formatted.isEmpty ? '-' : formatted;
  }

  String formattedPrintedTimeAmPm({String am = 'AM', String pm = 'PM'}) {
    if (printedAt.isEmpty) return '';
    final dt = DateTime.tryParse(printedAt);
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ap = dt.hour >= 12 ? pm : am;
    return '${two(h)}:${two(dt.minute)} $ap';
  }

  const TableModel({
    required this.id,
    required this.name,
    this.status = TableStatus.empty,
    this.seatedTime = '',
    this.waiterId = '',
    this.totalAmount = 0.0,
    this.guestCount = 0,
    this.sentToCashier = false,
    this.printedAt = '',
    this.note = '',
    this.noteUpdatedAt = '',
    this.createdBy = 0,
    this.openedBy = 0,
    this.isDelivery = false,
    this.deliveryCompanyId = 0,
    this.deliverySlot = 0,
  });

  /// True for a delivery slot. Cheap to read on the rows that come back from a
  /// query without this model (raw maps), where the column is absent on a
  /// database created before delivery slots existed.
  static bool mapIsDelivery(Map<String, dynamic> map) =>
      (map['isDelivery'] as int? ?? 0) == 1;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'status': status.index,
    'seatedTime': seatedTime,
    'waiterId': waiterId,
    'totalAmount': totalAmount,
    'guestCount': guestCount,
    'sentToCashier': sentToCashier ? 1 : 0,
    'printedAt': printedAt,
    'note': note,
    'noteUpdatedAt': noteUpdatedAt,
    'createdBy': createdBy,
    'openedBy': openedBy,
    'isDelivery': isDelivery ? 1 : 0,
    'deliveryCompanyId': deliveryCompanyId,
    'deliverySlot': deliverySlot,
  };

  factory TableModel.fromMap(Map<String, dynamic> map) => TableModel(
    id: map['id'] as int,
    name: map['name'] as String,
    status: tableStatusFrom(map['status']),
    seatedTime: map['seatedTime'] as String? ?? '',
    waiterId: map['waiterId'] as String? ?? '',
    totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
    guestCount: map['guestCount'] as int? ?? 0,
    sentToCashier: map['sentToCashier'] == 1,
    printedAt: map['printedAt'] as String? ?? '',
    note: map['note'] as String? ?? '',
    noteUpdatedAt: map['noteUpdatedAt'] as String? ?? '',
    createdBy: map['createdBy'] as int? ?? 0,
    openedBy: map['openedBy'] as int? ?? 0,
    isDelivery: mapIsDelivery(map),
    deliveryCompanyId: map['deliveryCompanyId'] as int? ?? 0,
    deliverySlot: map['deliverySlot'] as int? ?? 0,
  );

  TableModel copyWith({
    int? id,
    String? name,
    TableStatus? status,
    String? seatedTime,
    String? waiterId,
    double? totalAmount,
    int? guestCount,
    bool? sentToCashier,
    String? printedAt,
    String? note,
    String? noteUpdatedAt,
    int? createdBy,
    int? openedBy,
    bool? isDelivery,
    int? deliveryCompanyId,
    int? deliverySlot,
  }) => TableModel(
    id: id ?? this.id,
    name: name ?? this.name,
    status: status ?? this.status,
    seatedTime: seatedTime ?? this.seatedTime,
    waiterId: waiterId ?? this.waiterId,
    totalAmount: totalAmount ?? this.totalAmount,
    guestCount: guestCount ?? this.guestCount,
    sentToCashier: sentToCashier ?? this.sentToCashier,
    printedAt: printedAt ?? this.printedAt,
    note: note ?? this.note,
    noteUpdatedAt: noteUpdatedAt ?? this.noteUpdatedAt,
    createdBy: createdBy ?? this.createdBy,
    openedBy: openedBy ?? this.openedBy,
    isDelivery: isDelivery ?? this.isDelivery,
    deliveryCompanyId: deliveryCompanyId ?? this.deliveryCompanyId,
    deliverySlot: deliverySlot ?? this.deliverySlot,
  );
}
