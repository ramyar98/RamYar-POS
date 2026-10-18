import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_db.dart';
import '../models/receipt_design_model.dart';

/// The receipt design the admin built, shared by the design screen, the cashier
/// and the shift report's reprint.
///
/// It watches the database's revision notifier, so when the design is saved on
/// one device and arrives as a `RECEIPT_DESIGN_CHANGED` mutation the revision
/// bumps and every open screen - including the design preview - re-reads it.
final receiptDesignProvider = FutureProvider<ReceiptDesign>((ref) async {
  final db = ref.read(localDbProvider);
  ref.watch(receiptDesignRevisionProvider);
  return db.getReceiptDesign();
});

/// Exposes the database's plain [ValueNotifier] as a Riverpod dependency so
/// [receiptDesignProvider] above can `watch` it.
final receiptDesignRevisionProvider =
    ChangeNotifierProvider<ReceiptDesignRevision>(
      (ref) => ReceiptDesignRevision(ref.read(localDbProvider)),
    );

/// Forwards the database revision notifier as change notifications.
class ReceiptDesignRevision extends ChangeNotifier {
  ReceiptDesignRevision(this._db) {
    _db.receiptDesignRevision.addListener(notifyListeners);
  }

  final LocalDatabase _db;

  @override
  void dispose() {
    _db.receiptDesignRevision.removeListener(notifyListeners);
    super.dispose();
  }
}
