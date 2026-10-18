import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';

class AdminFoodDemandPage extends ConsumerStatefulWidget {
  const AdminFoodDemandPage({super.key});

  @override
  ConsumerState<AdminFoodDemandPage> createState() => _AdminFoodDemandPageState();
}

class _AdminFoodDemandPageState extends ConsumerState<AdminFoodDemandPage> {
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 1));
  List<_FoodDemand> _demands = [];
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(localDbProvider);
    final orders = await db.getSettledOrdersByDateRange(
      _start.toIso8601String(),
      _end.toIso8601String(),
    );

    final demandMap = <String, int>{};
    for (final order in orders) {
      final items = await db.getSettledOrderItems(order.id);
      for (final item in items) {
        demandMap[item.itemName] = (demandMap[item.itemName] ?? 0) + item.quantity;
      }
    }
    final cancelled = await db.getCancelledItemsByDateRange(
      _start.toIso8601String(),
      _end.toIso8601String(),
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

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end.subtract(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = DateTime(picked.year, picked.month, picked.day);
        } else {
          _end = DateTime(picked.year, picked.month, picked.day).add(const Duration(days: 1));
        }
      });
      _load();
    }
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
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(8)),
                      child: Text(_start.toString().substring(0, 10), style: const TextStyle(color: AppColors.darkText)),
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(context.tr('بۆ'), style: const TextStyle(color: AppColors.softText))),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(8)),
                      child: Text(_end.subtract(const Duration(days: 1)).toString().substring(0, 10), style: const TextStyle(color: AppColors.darkText)),
                    ),
                  ),
                ),
              ],
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
