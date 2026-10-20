import 'package:ramyar_pos/core/fmt.dart';
import 'package:ramyar_pos/widgets/amount_input_formatter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/settlement_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/admin_date_filter_bar.dart';
import 'payment_method_style.dart';

class AdminPurchasesPage extends ConsumerStatefulWidget {
  const AdminPurchasesPage({super.key});

  @override
  ConsumerState<AdminPurchasesPage> createState() => _AdminPurchasesPageState();
}

class _AdminPurchasesPageState extends ConsumerState<AdminPurchasesPage> {
  final _itemController = TextEditingController();
  final _priceController = TextEditingController();
  bool _isAdding = false;
  bool _loading = false;
  bool _loadedOnce = false;

  AdminDatePeriod _period = AdminDatePeriod.all;
  AdminDatePeriodRange _range = resolveAdminDatePeriod(AdminDatePeriod.all);

  /// Sticky: the admin's chosen period survives reopening the page.
  static const String _prefKey = 'admin_expenses_date_filter';

  double _moneyIn = 0;
  double _moneyOut = 0;
  double _moneyReturned = 0;
  List<_ExpenseRow> _rows = [];

  late final VoidCallback _revisionListener;

  @override
  void initState() {
    super.initState();
    _load();
    _revisionListener = () {
      if (mounted) unawaited(_load());
    };
    final db = ref.read(localDbProvider);
    db.shiftsRevision.addListener(_revisionListener);
    db.orderRevision.addListener(_revisionListener);
  }

  @override
  void dispose() {
    try {
      final db = ref.read(localDbProvider);
      db.shiftsRevision.removeListener(_revisionListener);
      db.orderRevision.removeListener(_revisionListener);
    } catch (_) {}
    _itemController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final db = ref.read(localDbProvider);
    final from = _range.fromIso;
    final to = _range.toIso;

    // لە دەخیلە counts every settled bill of the period (cash, card/wallet
    // and later-cleared debts); ڕاکێشراوە counts purchases plus the shift
    // expenses the cashiers entered; گەڕاوەتەوە is refunded money.
    final moneyIn = await db.getTotalSettledInRange(from, to);
    final purchases = await db.getPurchasesInRange(from, to);
    final expenses = await db.getCashierExpensesInRange(from, to);
    final refunds = await db.getTotalRefundsInRange(from, to);

    _moneyIn = moneyIn;
    _moneyOut =
        purchases.fold<double>(0, (s, p) => s + p.price) +
        expenses.fold<double>(0, (s, e) => s + e.price);
    _moneyReturned = refunds;
    _rows = [
      for (final p in purchases)
        _ExpenseRow(
          name: p.itemName,
          price: p.price,
          at: p.purchasedAt,
          isPurchase: true,
        ),
      for (final e in expenses)
        _ExpenseRow(
          name: e.itemName,
          price: e.price,
          at: e.createdAt,
          isPurchase: false,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    _loadedOnce = true;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addPurchase() async {
    if (_isAdding) return;
    final name = _itemController.text.trim();
    final price = parseAmount(_priceController.text).toDouble();
    if (name.isEmpty || price <= 0) return;
    setState(() => _isAdding = true);
    try {
      final db = ref.read(localDbProvider);
      final user = ref.read(authProvider);
      await db.addPurchase(
        Purchase(
          itemName: name,
          price: price,
          purchasedAt: DateTime.now().toIso8601String(),
          purchasedBy: user?.id ?? 0,
        ),
      );
      if (!mounted) return;
      _itemController.clear();
      _priceController.clear();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('هەڵەیەک ڕوویدا لە زیادکردندا')),
              backgroundColor: AppColors.danger),
        );
      }
    } finally {
      // One failed write used to leave the Add button disabled for the rest of
      // the session, with nothing on screen to say why.
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppConstants.paddingMedium;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.tr('خەرجیەکان'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      // Everything lives in one scroll view: the page fits a tiny phone by
      // scrolling instead of overflowing.
      body: CustomScrollView(
        slivers: [
          // Period filter: هەموو / ئەمڕۆ / دوێنی / پێری / تایبەت.
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: AdminDateFilterBar(
                  options: const [
                    AdminDatePeriod.all,
                    AdminDatePeriod.today,
                    AdminDatePeriod.yesterday,
                    AdminDatePeriod.dayBeforeYesterday,
                    AdminDatePeriod.custom,
                  ],
                  initial: _period,
                  persist: true,
                  prefKey: _prefKey,
                  onChanged: (period, range) {
                    setState(() {
                      _period = period;
                      _range = range;
                    });
                    unawaited(_load());
                  },
                ),
              ),
            ),
          ),
          // The three answers the page exists for: what came in, what went
          // out, what was handed back.
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
            sliver: SliverToBoxAdapter(
              child: ResponsiveRow(
                spacing: 12,
                children: [
                  _statCard(
                    icon: Icons.south_west_rounded,
                    color: AppColors.success,
                    label: context.tr('لە دەخیلە'),
                    value: '${context.tr('د.ع')} ${money(_moneyIn)}',
                    caption:
                        '${context.tr('کاش + ئەلیکترۆنی')} + ${context.tr('قەرز')}',
                  ),
                  _statCard(
                    icon: Icons.south_east_rounded,
                    color: AppColors.danger,
                    label: context.tr('ڕاکێشراوە'),
                    value: '${context.tr('د.ع')} ${money(_moneyOut)}',
                    caption:
                        '${context.tr('کڕینی ئەشیاکان')} + ${context.tr('شەفتی کاشێر')}',
                  ),
                  _statCard(
                    icon: Icons.replay_rounded,
                    color: AppColors.blue,
                    label: context.tr('گەڕاوەتەوە'),
                    value: '${context.tr('د.ع')} ${money(_moneyReturned)}',
                  ),
                ],
              ),
            ),
          ),
          // The add form - the admin still books purchases from here.
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
            sliver: SliverToBoxAdapter(child: _buildAddForm(context)),
          ),
          if (_loading && !_loadedOnce)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  context.tr('هیچ خەرجێک نییە'),
                  style: const TextStyle(color: AppColors.softText),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, pad),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  for (final row in _rows) _buildRow(context, row),
                  _buildTotalFooter(context),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Responsive.isPhone(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _itemController,
                  decoration: InputDecoration(
                    labelText: context.tr('ناوی ئاشیا'),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [AmountInputFormatter()],
                        decoration: InputDecoration(
                          labelText: context.tr('نرخ (د.ع)'),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isAdding ? null : _addPurchase,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(context.tr('زیادکردن')),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemController,
                    decoration: InputDecoration(
                      labelText: context.tr('ناوی ئاشیا'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [AmountInputFormatter()],
                    decoration: InputDecoration(
                      labelText: context.tr('نرخ (د.ع)'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isAdding ? null : _addPurchase,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(context.tr('زیادکردن')),
                ),
              ],
            ),
    );
  }

  Widget _buildTotalFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            context.tr('کۆی گشتی'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const Spacer(),
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${context.tr('د.ع')} ${money(_moneyOut)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _ExpenseRow row) {
    final isPurchase = row.isPurchase;
    final color = isPurchase ? AppColors.danger : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPurchase
                  ? Icons.shopping_cart_rounded
                  : Icons.receipt_long_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.tr(
                            isPurchase ? 'کڕینی ئەشیاکان' : 'شەفتی کاشێر',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      row.at.isEmpty ? '' : formatIsoDate(row.at),
                      style: const TextStyle(
                        color: AppColors.softText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${context.tr('د.ع')} ${money(row.price)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    String? caption,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.softText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (caption != null)
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.softText,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One outflow entry on the expenses ledger: a purchase booked here, or a
/// shift expense a cashier typed during their shift.
class _ExpenseRow {
  const _ExpenseRow({
    required this.name,
    required this.price,
    required this.at,
    required this.isPurchase,
  });

  final String name;
  final double price;
  final String at;
  final bool isPurchase;
}
