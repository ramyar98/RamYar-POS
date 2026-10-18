/// The shop's dollar rate, as the admin sets it and every other device shows.
///
/// The rate is stored as a PAIR - "100$ equals 150,000 IQD" - rather than as a
/// single price per dollar. That is how the admin actually thinks about it and
/// how they type it: they are quoting a number they saw on a screen, and they
/// are free to change either side of it. Storing a bare price per dollar would
/// force the admin to do arithmetic to reproduce the figure they are quoting,
/// and rounding that figure to a whole dinar is what the cashiers are shown.
///
/// Nothing here is money arithmetic on an order: the bill is settled in dinars
/// exactly as before. This only decides the sentence the cashier reads at the
/// top of their screen, and what the admin can edit.
class DollarRate {
  /// How many dollars the admin quoted. Kept as entered (usually 100) because
  /// it is part of the sentence, not a derived number.
  final double dollars;

  /// How many Iraqi dinars those dollars are worth.
  final double iqd;

  static const double kDefaultDollars = 100;
  static const double kDefaultIqd = 150000;

  const DollarRate({required this.dollars, required this.iqd});

  /// What a fresh install - or a device that has never been told the rate -
  /// shows. Chosen to match the example the admin types rather than an
  /// invented market figure, so the first screen they see is not a wrong number.
  static const DollarRate fallback = DollarRate(dollars: kDefaultDollars, iqd: kDefaultIqd);

  /// True when the pair actually says something. A zero or negative figure would
  /// produce a nonsense sentence ("0$ equals 0"), so it is treated as unset.
  bool get isSet => dollars > 0 && iqd > 0;

  /// One dollar in dinars. Null while the rate is unset, so callers can say
  /// "no rate yet" instead of dividing by zero.
  double? get iqdPerDollar => isSet ? iqd / dollars : null;

  /// The dinar figure the way the admin typed it: whole dinars, no decimals.
  /// A rate like 1500.75 dinars is money the shop does not trade in, and
  /// showing ".75" on a screen every cashier reads would only invite doubt.
  int get iqdWhole => iqd.round();

  /// The dollar figure, dropping a pointless ".0" but keeping real cents.
  String get dollarsLabel {
    if ((dollars - dollars.roundToDouble()).abs() < 0.005) {
      return dollars.round().toString();
    }
    return dollars.toStringAsFixed(2);
  }

  /// "150,000" - grouped so a seven-figure rate is readable at a glance.
  String get iqdLabel => _groupThousands(iqdWhole);

  static String _groupThousands(int value) {
    final digits = value.abs().toString();
    final sb = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) sb.write(',');
      sb.write(digits[i]);
    }
    return value < 0 ? '-$sb' : sb.toString();
  }

  /// Round-trips through the value stored in `shop_settings`.
  Map<String, dynamic> toMap() => {'dollars': dollars, 'iqd': iqd};

  factory DollarRate.fromMap(Map<String, dynamic> map) => DollarRate(
        dollars: (map['dollars'] as num?)?.toDouble() ?? kDefaultDollars,
        iqd: (map['iqd'] as num?)?.toDouble() ?? kDefaultIqd,
      );

  @override
  bool operator ==(Object other) =>
      other is DollarRate && other.dollars == dollars && other.iqd == iqd;

  @override
  int get hashCode => Object.hash(dollars, iqd);
}
