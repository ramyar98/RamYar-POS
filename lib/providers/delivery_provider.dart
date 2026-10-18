import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/local_db.dart';
import '../models/delivery_company_model.dart';
import '../models/table_model.dart';
import 'waiter_provider.dart';

/// Live list of delivery companies. The delivery page listens to the database
/// revision notifier (`deliveryCompaniesRevision`) and invalidates this
/// provider whenever a company is added or deleted locally or synced in from
/// another device, so every machine shows the same registry.
final deliveryCompaniesProvider = FutureProvider<List<DeliveryCompany>>(
  (ref) async => ref.watch(localDbProvider).getDeliveryCompanies(),
);

/// The delivery slots of one company, as real table rows.
///
/// Invalidated when an order arrives or is settled so the grid shows which
/// slots have something on them - both locally and on a captain's order synced
/// in from another till, because [orderRevision] covers both.
final deliverySlotsProvider =
    FutureProvider.family<List<TableModel>, int>((ref, companyId) async {
  // The order revision is watched, not just the company revision: a delivery
  // order changing does not touch the company list, and the grid would keep
  // showing a free slot for an order that is already rung in.
  ref.watch(orderRevisionProvider);
  return ref.watch(localDbProvider).getDeliverySlots(companyId);
});