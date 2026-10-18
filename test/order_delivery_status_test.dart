import 'package:flutter_test/flutter_test.dart';
import 'package:ramyar_pos/models/cancelled_item_model.dart';
import 'package:ramyar_pos/models/order_delivery_model.dart';

void main() {
  group('OrderDeliveryModel lifecycle statuses', () {
    test('separates not-arrived, arrived, print failed and printed states', () {
      final now = DateTime.now();
      final notArrived = OrderDeliveryModel.fromMap({
        'tableId': 1,
        'sentAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
        'arrivedAt': '',
        'printedAt': '',
        'printFailedAt': '',
        'rejected': 0,
      });
      final arrived = OrderDeliveryModel.fromMap({
        'tableId': 2,
        'sentAt': now.subtract(const Duration(minutes: 20)).toIso8601String(),
        'arrivedAt': now.subtract(const Duration(minutes: 5)).toIso8601String(),
        'printedAt': '',
        'printFailedAt': '',
        'rejected': 0,
      });
      final failedPrint = OrderDeliveryModel.fromMap({
        'tableId': 3,
        'sentAt': now.subtract(const Duration(minutes: 30)).toIso8601String(),
        'arrivedAt': now
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        'printedAt': '',
        'printFailedAt': now
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'rejected': 0,
      });
      final printed = OrderDeliveryModel.fromMap({
        'tableId': 4,
        'sentAt': now.subtract(const Duration(minutes: 35)).toIso8601String(),
        'arrivedAt': now
            .subtract(const Duration(minutes: 15))
            .toIso8601String(),
        'printedAt': now.subtract(const Duration(minutes: 2)).toIso8601String(),
        'printFailedAt': '',
        'rejected': 0,
      });

      expect(notArrived.hasArrived, isFalse);
      expect(notArrived.hasPrinted, isFalse);
      expect(notArrived.isPrintFailed, isFalse);
      expect(notArrived.isNotArrived, isTrue);
      expect(notArrived.statusLabel, 'not_arrived');

      expect(arrived.hasArrived, isTrue);
      expect(arrived.hasPrinted, isFalse);
      expect(arrived.isPrintFailed, isFalse);
      expect(arrived.isNotArrived, isFalse);
      expect(arrived.statusLabel, 'arrived');

      expect(failedPrint.isPrintFailed, isTrue);
      expect(failedPrint.isRetryPrint, isTrue);
      expect(failedPrint.statusLabel, 'print_failed');

      expect(printed.hasPrinted, isTrue);
      expect(printed.isPrinted, isTrue);
      expect(printed.statusLabel, 'printed');
    });

    test('expires stale delivery rows automatically after 3 hours', () {
      final stale = OrderDeliveryModel.fromMap({
        'tableId': 5,
        'sentAt': DateTime.now()
            .subtract(const Duration(hours: 4))
            .toIso8601String(),
        'arrivedAt': '',
        'printedAt': '',
        'printFailedAt': '',
        'rejected': 0,
      });

      final fresh = OrderDeliveryModel.fromMap({
        'tableId': 6,
        'sentAt': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'arrivedAt': '',
        'printedAt': '',
        'printFailedAt': '',
        'rejected': 0,
      });

      expect(stale.shouldAutoExpire, isTrue);
      expect(fresh.shouldAutoExpire, isFalse);
    });

    test('tracks both requester and rejector names on cancelled items', () {
      final item = CancelledItem.fromMap({
        'id': 1,
        'shiftId': 2,
        'tableId': 3,
        'tableName': 'مێزی 1',
        'itemName': 'کۆکایە',
        'itemPrice': 250,
        'quantity': 1,
        'category': 'خواردن',
        'cancelledAt': DateTime.now().toIso8601String(),
        'cancelledBy': 9,
        'cancelledByName': 'عەلی',
        'requestedByName': 'محمد',
        'status': 'pending',
        'servedAt': '',
      });

      expect(item.requestedByName, 'محمد');
      expect(item.cancelledByName, 'عەلی');
    });
  });
}
