import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../widgets/admin_date_filter_bar.dart';

class AdminAccountsPage extends ConsumerStatefulWidget {
  const AdminAccountsPage({super.key});

  @override
  ConsumerState<AdminAccountsPage> createState() => _AdminAccountsPageState();
}

class _AdminAccountsPageState extends ConsumerState<AdminAccountsPage> {
  AdminDatePeriodRange _range = resolveAdminDatePeriod(AdminDatePeriod.month);
  double _electronic = 0;
  double _cashPlusElectronic = 0;
  double _expenses = 0;
  double _net = 0;
  bool _loading = false;

  /// Sticky: the admin's chosen period survives reopening the page.
  static const String _prefKey = 'admin_accounts_date_filter';

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
    final from = _range.fromIso;
    final to = _range.toIso;
    _electronic = await db.getSettledElectronicInRange(from, to);
    _cashPlusElectronic = await db.getSettledCashPlusElectronicInRange(from, to);
    final purchases = await db.getTotalPurchasesInRange(from, to);
    final expenses = await db.getCashierExpensesTotalInRange(from, to);
    final refunds = await db.getTotalRefundsInRange(from, to);
    _expenses = purchases + expenses + refunds;
    _net = _cashPlusElectronic - _expenses;
    if (mounted) setState(() => _loading = false);
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
              child: AdminDateFilterBar(
                options: const [
                  AdminDatePeriod.month,
                  AdminDatePeriod.today,
                  AdminDatePeriod.yesterday,
                  AdminDatePeriod.dayBeforeYesterday,
                  AdminDatePeriod.custom,
                ],
                initial: AdminDatePeriod.month,
                labels: {
                  AdminDatePeriod.today: context.tr('ڕۆژانە'),
                },
                persist: true,
                prefKey: _prefKey,
                onChanged: (period, range) {
                  setState(() => _range = range);
                  unawaited(_loadData());
                },
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
                          label: context.tr('کۆی گشتی پارەکان'),
                          value:
                              '${context.tr('د.ع')} ${money(_net)}',
                          valueColor: _net >= 0
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                        _accountCard(
                          icon: Icons.credit_card_rounded,
                          iconColor: AppColors.blue,
                          label: context.tr('پارەی ئەلیکترۆنی'),
                          value:
                              '${context.tr('د.ع')} ${money(_electronic)}',
                          valueColor: AppColors.blue,
                        ),
                        _accountCard(
                          icon: Icons.account_balance_wallet_rounded,
                          iconColor: AppColors.primary,
                          label: context.tr('کاش + ئەلیکترۆنی'),
                          value: '${context.tr('د.ع')} ${money(_cashPlusElectronic)}',
                          valueColor: AppColors.primary,
                        ),
                        _accountCard(
                          icon: Icons.shopping_cart_rounded,
                          iconColor: AppColors.danger,
                          label: context.tr('خەرجیەکان'),
                          value: '${context.tr('د.ع')} ${money(_expenses)}',
                          valueColor: AppColors.danger,
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


}
