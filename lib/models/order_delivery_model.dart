class OrderDeliveryModel {
  final int tableId;
  final String sentAt;
  final String arrivedAt;
  final String printedAt;
  final String printFailedAt;
  final bool rejected;

  const OrderDeliveryModel({
    required this.tableId,
    required this.sentAt,
    this.arrivedAt = '',
    this.printedAt = '',
    this.printFailedAt = '',
    this.rejected = false,
  });

  bool get hasArrived => arrivedAt.isNotEmpty;
  bool get hasPrinted => printedAt.isNotEmpty;
  bool get isPrintFailed => printFailedAt.isNotEmpty && !hasPrinted;
  bool get isNotArrived =>
      !hasArrived &&
      !hasPrinted &&
      !isPrintFailed &&
      !rejected &&
      !shouldAutoExpire;
  bool get isPrinted => hasPrinted && !rejected && !shouldAutoExpire;
  bool get isRetryPrint => isPrintFailed && !rejected && !shouldAutoExpire;
  bool get shouldAutoExpire {
    if (rejected || hasPrinted) return false;
    final sent = DateTime.tryParse(sentAt);
    if (sent == null) return false;
    final age = DateTime.now().difference(sent.toLocal());
    return age >= const Duration(hours: 3);
  }

  bool get needsResend => isNotArrived && !shouldAutoExpire;
  bool get canRetry => needsResend || isRetryPrint;

  String get statusLabel {
    if (rejected) return 'rejected';
    if (hasPrinted) return 'printed';
    if (isPrintFailed) return 'print_failed';
    if (hasArrived) return 'arrived';
    return 'not_arrived';
  }

  factory OrderDeliveryModel.fromMap(Map<String, dynamic> map) =>
      OrderDeliveryModel(
        tableId: map['tableId'] as int,
        sentAt: map['sentAt'] as String,
        arrivedAt: map['arrivedAt'] as String? ?? '',
        printedAt: map['printedAt'] as String? ?? '',
        printFailedAt: map['printFailedAt'] as String? ?? '',
        rejected: (map['rejected'] as int? ?? 0) == 1,
      );
}
