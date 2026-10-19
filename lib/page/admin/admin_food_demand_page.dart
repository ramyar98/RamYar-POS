import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../widgets/admin_date_filter_bar.dart';

class AdminFoodDemandPage extends ConsumerStatefulWidget {
  const AdminFoodDemandPage({super.key});

  @override
  ConsumerState<AdminFoodDemandPage> createState() => _AdminFoodDemandPageState();
}

class _AdminFoodDemandPageState extends ConsumerState<AdminFoodDemandPage> {
  AdminDatePeriod _period = AdminDatePeriod.today;
  AdminDatePeriodRange _range = resolveAdminDatePeriod(AdminDatePeriod.today);
  List<_FoodDemand> _demands = [];
  bool _loading = false;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final db = ref.read(localDbProvider);
    final orders = await db.getSettledOrdersByDateRange(
      _range.fromIso,
      _range.toIso,
    );

    final demandMap = <String, int>{};
    for (final order in orders) {
      final items = await db.getSettledOrderItems(order.id);
      for (final item in items) {
        demandMap[item.itemName] = (demandMap[item.itemName] ?? 0) + item.quantity;
      }
    }
    final cancelled = await db.getCancelledItemsByDateRange(
      _range.fromIso,
      _range.toIso,
    );
    for (final item in cancelled) {
      if (item.status != 'pending') continue;
      final current = demandMap[item.itemName] ?? 0;
      final remaining = current - item.quantity;
      if (remaining <= 0) {
        demandMap.remove(item.itemName);
      } else {
        demandMap[item.itemName] = remaining;
      }
    }

    _demands = demandMap.entries
      .map((e) => _FoodDemand(name: e.key, quantity: e.value, total: 0))
      .toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    if (mounted) setState(() => _loading = false);
  }



  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(context.tr('داواکاری خواردن'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: AdminDateFilterBar(
              options: const [
                AdminDatePeriod.all,
                AdminDatePeriod.today,
                AdminDatePeriod.yesterday,
                AdminDatePeriod.week,
                AdminDatePeriod.custom,
              ],
              initial: _period,
              onChanged: (period, range) {
                setState(() {
                  _period = period;
                  _range = range;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _demands.isEmpty
                    ? Center(child: Text(context.tr('هیچ خواردنێک نەفرۆشراوە لەم ماوەیە'), style: const TextStyle(color: AppColors.softText)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppConstants.paddingMedium),
                        itemCount: _demands.length,
                        itemBuilder: (context, index) {
                          final d = _demands[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${d.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                      const SizedBox(width: 4),
                                      Text(context.tr('دانە'), style: TextStyle(fontSize: 12, color: AppColors.primary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _FoodDemand {
  final String name;
  final int quantity;
  final double total;
  _FoodDemand({required this.name, required this.quantity, required this.total});
}
