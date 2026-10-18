import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';

class AdminAccountsPage extends ConsumerStatefulWidget {
  const AdminAccountsPage({super.key});

  @override
  ConsumerState<AdminAccountsPage> createState() => _AdminAccountsPageState();
}

class _AdminAccountsPageState extends ConsumerState<AdminAccountsPage> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _toDate = DateTime.now();
  double _totalEarnings = 0;
  double _totalPurchases = 0;
  double _totalRefunds = 0;
  double _netIncome = 0;
  bool _loading = false;

  late final LocalDatabase _db;
  late final VoidCallback _revisionListener;

  @override
  void initState() {
    super.initState();
    _db = ref.read(localDbProvider);
    _revisionListener = () {
      if (mounted) unawaited(_loadData());
    };
    // Accounts totals change on every settle/purchase/refund and on shift
    // rollups - follow both revisions so the admin's overview stays live.
    _db.orderRevision.addListener(_revisionListener);
    _db.shiftsRevision.addListener(_revisionListener);
    unawaited(_loadData());
  }

  @override
  void dispose() {
    try {
      _db.orderRevision.removeListener(_revisionListener);
      _db.shiftsRevision.removeListener(_revisionListener);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final db = ref.read(localDbProvider);
    final from = '${_fromDate.toIso8601String().substring(0, 10)}T00:00:00';
    final to = '${_toDate.toIso8601String().substring(0, 10)}T23:59:59';
    _totalEarnings = await db.getTotalSettledInRange(from, to);
    _totalPurchases = await db.getTotalPurchasesInRange(from, to);
    _totalRefunds = await db.getTotalRefundsInRange(from, to);
    _netIncome = _totalEarnings - _totalPurchases - _totalRefunds;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _loadData();
    }
  }

  Future<void> _setQuickRange(int days) async {
    setState(() {
      _fromDate = DateTime.now().subtract(Duration(days: days));
      _toDate = DateTime.now();
    });
    _loadData();
  }

  String _formatDate(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
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
          context.tr('حسابەکان'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: InkWell(
                            onTap: _pickDateRange,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.date_range_rounded,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${_formatDate(_fromDate)} - ${_formatDate(_toDate)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _quickChip(context.tr('ئەمڕۆ'), 0),
                        const SizedBox(width: 6),
                        _quickChip(context.tr('دوێنی'), 1),
                        const SizedBox(width: 6),
                        _quickChip(context.tr('7 ڕۆژ'), 7),
                        const SizedBox(width: 6),
                        _quickChip(context.tr('30 ڕۆژ'), 30),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = ResponsiveRow(
                      spacing: 16,
                      children: [
                        _accountCard(
                          icon: Icons.trending_up_rounded,
                          iconColor: AppColors.success,
                          label: context.tr('کۆی گشتی'),
                          value:
                              '${context.tr('د.ع')} ${money(_totalEarnings)}',
                          valueColor: AppColors.success,
                        ),
                        _accountCard(
                          icon: Icons.shopping_cart_rounded,
                          iconColor: AppColors.danger,
                          label: context.tr('کڕینی ئەشیاکان'),
                          value:
                              '${context.tr('د.ع')} ${money(_totalPurchases)}',
                          valueColor: AppColors.danger,
                        ),
                        _accountCard(
                          icon: Icons.currency_exchange_rounded,
                          iconColor: AppColors.blue,
                          label: context.tr('گەڕاندنەوە'),
                          value: '${context.tr('د.ع')} ${money(_totalRefunds)}',
                          valueColor: AppColors.blue,
                        ),
                        _accountCard(
                          icon: Icons.account_balance_wallet_rounded,
                          iconColor: AppColors.primary,
                          label: context.tr('داهاتی خاو'),
                          value: '${context.tr('د.ع')} ${money(_netIncome)}',
                          valueColor: _netIncome >= 0
                              ? AppColors.primary
                              : AppColors.danger,
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 600) {
                      return SingleChildScrollView(child: cards);
                    }
                    return cards;
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.softText, fontSize: 13),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickChip(String label, int days) {
    final isActive = _fromDate == DateTime.now().subtract(Duration(days: days));
    return GestureDetector(
      onTap: () => _setQuickRange(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : AppColors.darkText,
          ),
        ),
      ),
    );
  }
}
