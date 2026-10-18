import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_db.dart';
import '../models/dollar_rate_model.dart';

/// The admin's dollar rate, shared by every screen that shows it.
///
/// The provider watches the database's revision notifier, so when the admin
/// saves a new rate the change arrives on the other devices as a
/// `DOLLAR_RATE_CHANGED` mutation, the database bumps the revision, and every
/// open screen re-reads the new figure - nobody has to reopen the page. This is
/// the same live-refresh mechanism the food menu and the shifts already use.
final dollarRateProvider = FutureProvider<DollarRate>((ref) async {
  final db = ref.read(localDbProvider);
  // Depending on the notifier is what re-runs this body on every change.
  ref.watch(dollarRateRevisionProvider);
  return db.getDollarRate();
});

/// Exposes the database's plain [ValueNotifier] as a Riverpod dependency so
/// [dollarRateProvider] above can `watch` it. Riverpod re-runs a `watch`ed
/// provider when its value changes, which is exactly the behaviour the revision
/// notifier already provides.
final dollarRateRevisionProvider = ChangeNotifierProvider<DollarRateRevision>(
  (ref) => DollarRateRevision(ref.read(localDbProvider)),
);

/// Forwards the database revision notifier as change notifications.
class DollarRateRevision extends ChangeNotifier {
  DollarRateRevision(this._db) {
    _db.dollarRateRevision.addListener(notifyListeners);
  }

  final LocalDatabase _db;

  @override
  void dispose() {
    _db.dollarRateRevision.removeListener(notifyListeners);
    super.dispose();
  }
}
