/// How the cashier's receipt looks.
///
/// The whole receipt is described by this one value: the shop's name and the
/// receipt title at the top, which of the guest/staff lines are printed, whether
/// the dish list, the sub-total, the discount and the total appear, the closing
/// message, the separator rule, the paper width and how much blank paper is fed
/// before the cut.
///
/// It is stored as one JSON row in `shop_settings` (like the dollar rate) and
/// synced to every device, so the admin designs the receipt once and the till
/// prints that design. [standard] reproduces the receipt the app printed before
/// this screen existed, so a device that has never been designed prints exactly
/// as it always did.
class ReceiptDesign {
  final String shopName;
  final bool showShopName;

  final String headerTitle;
  final bool showHeaderTitle;

  /// The rule drawn between sections: `dash`, `equals` or `dots`.
  final String separatorStyle;

  final bool showTable;
  final bool showGuestCount;
  final bool showSeatedAt;
  final bool showLeaveTime;
  final bool showDate;
  final bool showWaiter;
  final bool showCashier;

  /// False drops the dish list, leaving the money block - a "quick bill".
  final bool showItems;

  final bool showSubtotal;
  final bool showDiscount;
  final bool showTotal;

  /// The grand total in double-height type.
  final bool bigTotal;

  final bool showFooter;
  final String footerText;

  /// Characters per line: 32 for a 58mm roll, 40 for the small default, 48 for
  /// an 80mm roll.
  final int paperWidth;

  /// Blank lines fed before the paper is cut, so the slip tears off cleanly.
  final int feedBeforeCut;

  const ReceiptDesign({
    this.shopName = 'B I A B L O',
    this.showShopName = true,
    this.headerTitle = 'وەسڵی کاشێر',
    this.showHeaderTitle = true,
    this.separatorStyle = 'dash',
    this.showTable = true,
    this.showGuestCount = true,
    this.showSeatedAt = true,
    this.showLeaveTime = true,
    this.showDate = true,
    this.showWaiter = true,
    this.showCashier = true,
    this.showItems = true,
    this.showSubtotal = true,
    this.showDiscount = true,
    this.showTotal = true,
    this.bigTotal = true,
    this.showFooter = true,
    this.footerText = 'سوپاس بۆ بەکارهێنانی\nخزمەتگوزاری ئێمە',
    this.paperWidth = 40,
    this.feedBeforeCut = 4,
  });

  /// The receipt as it printed before the design screen existed.
  static const ReceiptDesign standard = ReceiptDesign();

  static const List<int> paperWidths = [32, 40, 48];
  static const List<String> separatorStyles = ['dash', 'equals', 'dots'];

  ReceiptDesign copyWith({
    String? shopName,
    bool? showShopName,
    String? headerTitle,
    bool? showHeaderTitle,
    String? separatorStyle,
    bool? showTable,
    bool? showGuestCount,
    bool? showSeatedAt,
    bool? showLeaveTime,
    bool? showDate,
    bool? showWaiter,
    bool? showCashier,
    bool? showItems,
    bool? showSubtotal,
    bool? showDiscount,
    bool? showTotal,
    bool? bigTotal,
    bool? showFooter,
    String? footerText,
    int? paperWidth,
    int? feedBeforeCut,
  }) {
    return ReceiptDesign(
      shopName: shopName ?? this.shopName,
      showShopName: showShopName ?? this.showShopName,
      headerTitle: headerTitle ?? this.headerTitle,
      showHeaderTitle: showHeaderTitle ?? this.showHeaderTitle,
      separatorStyle: separatorStyle ?? this.separatorStyle,
      showTable: showTable ?? this.showTable,
      showGuestCount: showGuestCount ?? this.showGuestCount,
      showSeatedAt: showSeatedAt ?? this.showSeatedAt,
      showLeaveTime: showLeaveTime ?? this.showLeaveTime,
      showDate: showDate ?? this.showDate,
      showWaiter: showWaiter ?? this.showWaiter,
      showCashier: showCashier ?? this.showCashier,
      showItems: showItems ?? this.showItems,
      showSubtotal: showSubtotal ?? this.showSubtotal,
      showDiscount: showDiscount ?? this.showDiscount,
      showTotal: showTotal ?? this.showTotal,
      bigTotal: bigTotal ?? this.bigTotal,
      showFooter: showFooter ?? this.showFooter,
      footerText: footerText ?? this.footerText,
      paperWidth: paperWidth ?? this.paperWidth,
      feedBeforeCut: feedBeforeCut ?? this.feedBeforeCut,
    );
  }

  Map<String, dynamic> toMap() => {
    'shopName': shopName,
    'showShopName': showShopName,
    'headerTitle': headerTitle,
    'showHeaderTitle': showHeaderTitle,
    'separatorStyle': separatorStyle,
    'showTable': showTable,
    'showGuestCount': showGuestCount,
    'showSeatedAt': showSeatedAt,
    'showLeaveTime': showLeaveTime,
    'showDate': showDate,
    'showWaiter': showWaiter,
    'showCashier': showCashier,
    'showItems': showItems,
    'showSubtotal': showSubtotal,
    'showDiscount': showDiscount,
    'showTotal': showTotal,
    'bigTotal': bigTotal,
    'showFooter': showFooter,
    'footerText': footerText,
    'paperWidth': paperWidth,
    'feedBeforeCut': feedBeforeCut,
  };

  factory ReceiptDesign.fromMap(Map<String, dynamic> map) {
    final width = (map['paperWidth'] as num?)?.toInt() ?? 40;
    final sep = map['separatorStyle'] as String? ?? 'dash';
    return ReceiptDesign(
      shopName: map['shopName'] as String? ?? 'B I A B L O',
      showShopName: map['showShopName'] as bool? ?? true,
      headerTitle: map['headerTitle'] as String? ?? 'وەسڵی کاشێر',
      showHeaderTitle: map['showHeaderTitle'] as bool? ?? true,
      separatorStyle: separatorStyles.contains(sep) ? sep : 'dash',
      showTable: map['showTable'] as bool? ?? true,
      showGuestCount: map['showGuestCount'] as bool? ?? true,
      showSeatedAt: map['showSeatedAt'] as bool? ?? true,
      showLeaveTime: map['showLeaveTime'] as bool? ?? true,
      showDate: map['showDate'] as bool? ?? true,
      showWaiter: map['showWaiter'] as bool? ?? true,
      showCashier: map['showCashier'] as bool? ?? true,
      showItems: map['showItems'] as bool? ?? true,
      showSubtotal: map['showSubtotal'] as bool? ?? true,
      showDiscount: map['showDiscount'] as bool? ?? true,
      showTotal: map['showTotal'] as bool? ?? true,
      bigTotal: map['bigTotal'] as bool? ?? true,
      showFooter: map['showFooter'] as bool? ?? true,
      footerText:
          map['footerText'] as String? ?? 'سوپاس بۆ بەکارهێنانی\nخزمەتگوزاری ئێمە',
      paperWidth: paperWidths.contains(width) ? width : 40,
      feedBeforeCut: ((map['feedBeforeCut'] as num?)?.toInt() ?? 4).clamp(0, 10),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReceiptDesign &&
      other.shopName == shopName &&
      other.showShopName == showShopName &&
      other.headerTitle == headerTitle &&
      other.showHeaderTitle == showHeaderTitle &&
      other.separatorStyle == separatorStyle &&
      other.showTable == showTable &&
      other.showGuestCount == showGuestCount &&
      other.showSeatedAt == showSeatedAt &&
      other.showLeaveTime == showLeaveTime &&
      other.showDate == showDate &&
      other.showWaiter == showWaiter &&
      other.showCashier == showCashier &&
      other.showItems == showItems &&
      other.showSubtotal == showSubtotal &&
      other.showDiscount == showDiscount &&
      other.showTotal == showTotal &&
      other.bigTotal == bigTotal &&
      other.showFooter == showFooter &&
      other.footerText == footerText &&
      other.paperWidth == paperWidth &&
      other.feedBeforeCut == feedBeforeCut;

  @override
  int get hashCode => Object.hashAll([
    shopName,
    showShopName,
    headerTitle,
    showHeaderTitle,
    separatorStyle,
    showTable,
    showGuestCount,
    showSeatedAt,
    showLeaveTime,
    showDate,
    showWaiter,
    showCashier,
    showItems,
    showSubtotal,
    showDiscount,
    showTotal,
    bigTotal,
    showFooter,
    footerText,
    paperWidth,
    feedBeforeCut,
  ]);
}
