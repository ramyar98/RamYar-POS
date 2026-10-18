import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/fmt.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/user_model.dart';

class AdminCaptainIntelligencePage extends ConsumerStatefulWidget {
  const AdminCaptainIntelligencePage({super.key});

  @override
  ConsumerState<AdminCaptainIntelligencePage> createState() =>
      _AdminCaptainIntelligencePageState();
}

class _AdminCaptainIntelligencePageState
    extends ConsumerState<AdminCaptainIntelligencePage> {
  List<_CaptainStats> _stats = [];
  bool _loading = true;

  Future<void> _load() async {
    final db = ref.read(localDbProvider);
    final waiters = await db.getUsersByRole(UserRole.waiter);
    final allOrders = await db.getSettledOrdersByDateRange(
      DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
      DateTime.now().add(const Duration(days: 1)).toIso8601String(),
    );

    _stats = [];
    for (final w in waiters) {
      final waiterItems = allOrders
          .where((o) => o.waiterId == w.id.toString())
          .toList();
      final totalAmount = waiterItems.fold<double>(
        0,
        (s, o) => s + o.totalAmount,
      );
      _stats.add(
        _CaptainStats(
          name: w.name,
          orders: waiterItems.length,
          amount: totalAmount,
        ),
      );
    }

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
        title: Text(
          context.tr('زیرەکی کاپتن'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stats.isEmpty
          ? Center(
              child: Text(
                context.tr('هیچ زانیاریەک نییە'),
                style: TextStyle(color: AppColors.softText),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              itemCount: _stats.length,
              itemBuilder: (context, index) {
                final s = _stats[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: AppColors.darkText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${context.tr('داواکاری')}: ${s.orders} | ${context.tr('کۆی بڕ')}: ${money(s.amount)} ${context.tr('د.ع')}',
                              style: TextStyle(
                                color: AppColors.softText,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _CaptainStats {
  final String name;
  final int orders;
  final double amount;
  _CaptainStats({
    required this.name,
    required this.orders,
    required this.amount,
  });
}
