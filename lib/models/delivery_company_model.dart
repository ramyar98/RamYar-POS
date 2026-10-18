/// A delivery company (تەلەبات / لیزۆ / وادێ or a custom one like "Toters")
/// shown as a sub-tab inside the cashier delivery panel. Stored in the local
/// database and synced to every device through the same mutation protocol used
/// for tables and users, so companies persist across reboots.
class DeliveryCompany {
  /// How many slots a company gets the first time it appears.
  ///
  /// A busy branch can need more than the twenty the grid used to draw, and the
  /// cashier raises it from the delivery panel, so this is only the starting
  /// point rather than a fixed number.
  static const int defaultSlotsPerCompany = 50;

  /// The most slots one company can hold.
  ///
  /// Slot numbers are `base + companyId * 100 + slot`
  /// ([LocalDatabase.deliverySlotTableId]), so slot 100 would collide with the
  /// next company's first slot. 99 is the last number that stays inside the
  /// company's own hundred.
  static const int maxSlotsPerCompany = 99;

  final int id;
  final String name;
  final int sortOrder;

  /// How many delivery table slots this company offers. The cashier can raise
  /// it (and drop it again) from the delivery panel, so it is per company
  /// rather than one fixed number for every company on the bar.
  final int slotCount;

  const DeliveryCompany({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.slotCount = 50,
  });

  factory DeliveryCompany.fromMap(Map<String, dynamic> map) {
    return DeliveryCompany(
      id: map['id'] as int,
      name: (map['name'] as String?) ?? '',
      sortOrder: (map['sortOrder'] as int?) ?? 0,
      // A device syncing against an older build sends no `slotCount`; it falls
      // back to the shop default rather than to zero, which would hide the
      // whole grid.
      slotCount: _normaliseSlotCount(map['slotCount']),
    );
  }

  /// Keeps a stored or synced count inside what the slot numbering can hold.
  ///
  /// Slot numbers are worked out as `base + companyId * 100 + slot`
  /// ([LocalDatabase.deliverySlotTableId]), so a slot must stay below 100 or it
  /// would land on the next company's slot 0. Values outside the range are
  /// treated as "not set" rather than trusted.
  static int _normaliseSlotCount(Object? raw) {
    if (raw is! num) return defaultSlotsPerCompany;
    final value = raw.toInt();
    if (value < 1) return defaultSlotsPerCompany;
    return value > maxSlotsPerCompany ? maxSlotsPerCompany : value;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sortOrder': sortOrder,
        'slotCount': slotCount,
      };

  DeliveryCompany copyWith({String? name, int? sortOrder, int? slotCount}) {
    return DeliveryCompany(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      slotCount: slotCount ?? this.slotCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryCompany && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}