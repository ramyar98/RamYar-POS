import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../database/local_db.dart';
import '../../models/debt_model.dart';
import '../../models/order_model.dart';
import '../../models/printer_model.dart';
import '../../models/remaining_table_model.dart';
import '../../models/settlement_model.dart';
import '../../providers/printer_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/print_router.dart';
import '../../services/table_note_policy.dart';
import 'payment_method_style.dart';
import 'shift_captain_report_page.dart';
import 'shift_expenses_page.dart';
import 'shift_payment_method_page.dart';
import 'shift_rejected_items_page.dart';

/// The two money figures the shift report opens with: the shift's settled
/// orders and the total still owed on the debts it opened («قەرزەکان»).
///
/// They are fetched together because the «کاش (نەقد) + قەرز» card needs both and
/// the page would otherwise have to nest two `FutureBuilder`s.
class _ShiftMoney {
  final List<SettledOrder> orders;
  final double debtTotal;

  const _ShiftMoney({required this.orders, required this.debtTotal});
}

class AdminShiftDetailPage extends ConsumerStatefulWidget {
  final CashierShift shift;
  const AdminShiftDetailPage({super.key, required this.shift});

  @override
  ConsumerState<AdminShiftDetailPage> createState() =>
      _AdminShiftDetailPageState();
}

class _AdminShiftDetailPageState extends ConsumerState<AdminShiftDetailPage> {
  // Held in state rather than created inside `build` so that switching tabs or
  // pulling to refresh does not re-run the shift query on every repaint. The
  // settled orders and the till's outstanding debts are read together: the money
  // summary needs both figures before it can paint.
  late Future<_ShiftMoney> _moneyFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final db = ref.read(localDbProvider);
    _moneyFuture = _loadMoney(db);
  }

  Future<_ShiftMoney> _loadMoney(LocalDatabase db) async {
    final orders = await db.getSettledOrdersByShiftId(widget.shift.id);
    final debtTotal = await db.getDebtTotalByShift(widget.shift.id);
    return _ShiftMoney(orders: orders, debtTotal: debtTotal);
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? context.tr('د.ن') : context.tr('پ.ن');
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final shift = widget.shift;
    final isActive = shift.endedAt == null || shift.endedAt!.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.timeline_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.tr('ڕاپۆرتی شەفت'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.darkText,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: FutureBuilder<_ShiftMoney>(
        future: _moneyFuture,
        builder: (context, moneySnap) {
          final money = moneySnap.data;
          final orders = money?.orders ?? const <SettledOrder>[];
          final debtTotal = money?.debtTotal ?? 0;

          // «کاش (نەقد) + قەرز» is the money the tables put on the books: the
          // cash they paid plus everything they took on credit. A bill moved to
          // «قەرزەکان» writes a debt row but no settled order, so the till's
          // outstanding debts are added on top - otherwise that money would
          // vanish from the report. Electronic brands never reach the drawer, so
          // they are left out. Computed independently of «کاش (نەقد)» below,
          // which is the physical cash alone.
          final systemTotal = orders
                  .where(
                    (o) =>
                        o.paymentMethod == 'cash' || o.paymentMethod == 'debt',
                  )
                  .fold<double>(0, (s, o) => s + o.totalAmount) +
              debtTotal;

          final Map<String, double> methodTotals = {};
          for (final o in orders) {
            methodTotals.update(
              o.paymentMethod,
              (v) => v + o.totalAmount,
              ifAbsent: () => o.totalAmount,
            );
          }

          // «کاش (نەقد)» is the physical-cash take alone: debt is money still
          // owed and the electronic brands never reach the drawer, so neither
          // belongs in what the cashier should be holding.
          final cashTotal = methodTotals['cash'] ?? 0;
          // The cashier declares a counted figure only when the shift closes; an
          // open shift has nothing to reconcile yet.
          final declared = isActive ? 0.0 : shift.totalCollected;
          // کاشێر بەرامبەر ئەو نەقدەی سیستەم تۆماری کردووە: زیادە یان کەمە.
          final systemAccount = declared - cashTotal;

          Color comparisonColor;
          String comparisonLabel;
          IconData comparisonIcon;
          if (isActive) {
            comparisonColor = AppColors.softText;
            comparisonLabel = context.tr('شەفت چالاکە');
            comparisonIcon = Icons.play_circle_rounded;
          } else if (systemAccount == 0) {
            comparisonColor = AppColors.success;
            comparisonLabel = context.tr('یەکسانە');
            comparisonIcon = Icons.check_circle_rounded;
          } else if (systemAccount > 0) {
            comparisonColor = const Color(0xFFFFA000);
            comparisonLabel = context.tr('زیاترە');
            comparisonIcon = Icons.trending_up_rounded;
          } else {
            comparisonColor = AppColors.danger;
            comparisonLabel = context.tr('کەمترە');
            comparisonIcon = Icons.trending_down_rounded;
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(_load);
              await _moneyFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildShiftHeader(shift, isActive),
                const SizedBox(height: 16),
                _buildFinancialSummary(
                  systemTotal,
                  cashTotal,
                  shift.totalCollected,
                  comparisonColor,
                  comparisonLabel,
                  comparisonIcon,
                  isActive,
                ),
                const SizedBox(height: 16),
                _buildPaymentMethods(methodTotals, orders),
                const SizedBox(height: 16),
                _ShiftDetailTabs(
                  shift: shift,
                  orders: orders,
                  formatTime: _formatTime,
                  paymentLabel: (m) => paymentMethodLabel(context, m),
                  paymentColor: paymentMethodColor,
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildShiftHeader(CashierShift shift, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [
                  AppColors.success.withValues(alpha: 0.08),
                  AppColors.success.withValues(alpha: 0.02),
                ]
              : [AppColors.primary.withValues(alpha: 0.06), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.borderSide,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isActive ? Icons.play_circle_rounded : Icons.check_circle_rounded,
              color: isActive ? AppColors.success : AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shift.cashierName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 4),
                _infoRow(
                  Icons.login_rounded,
                  context.tr('دەستپێکردن'),
                  _formatTime(shift.startedAt),
                ),
                if (!isActive) ...[
                  const SizedBox(height: 2),
                  _infoRow(
                    Icons.logout_rounded,
                    context.tr('کۆتایی'),
                    _formatTime(shift.endedAt!),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.softText.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? AppColors.success.withValues(alpha: 0.3)
                    : AppColors.borderSide,
              ),
            ),
            child: Text(
              isActive ? context.tr('چالاکە') : context.tr('داخراوە'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isActive ? AppColors.success : AppColors.softText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppColors.softText),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$label: ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.softText),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.darkText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialSummary(
    double systemTotal,
    double cashTotal,
    double collected,
    Color compColor,
    String compLabel,
    IconData compIcon,
    bool isActive,
  ) {
    final declared = isActive ? 0.0 : collected;
    // The fourth card is the system's account of the drawer discrepancy: the
    // size of the gap between the cash the system says should be there
    // («کاش (نەقد)») and the cashier's declared count. The pill underneath
    // («زیاترە» amber / «کەمترە» red / «یەکسانە» green) names its direction, so
    // the amount itself is shown unsigned. Showing the expected cash here would
    // just repeat «کاش (نەقد)» and hide how far off the count is.
    final systemAccount = (declared - cashTotal).abs();
    final cards = <Widget>[
      _summaryCard(
        context.tr('کاش (نەقد) + قەرز'),
        systemTotal,
        AppColors.primary,
        Icons.receipt_rounded,
      ),
      _summaryCard(
        context.tr('کاش (نەقد)'),
        cashTotal,
        AppColors.success,
        Icons.payments_rounded,
      ),
      _summaryCard(
        context.tr('کاشێر'),
        declared,
        AppColors.blue,
        Icons.person_rounded,
      ),
      _summaryCard(
        context.tr('حسابی سیستەم'),
        systemAccount,
        compColor,
        compIcon,
        status: compLabel,
        statusColor: compColor,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.analytics_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('پوختەی دارایی'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Four money cards need room. On a tablet/laptop they sit in one row;
          // on a phone four would each be too narrow to read, so they fall into
          // two rows of two and keep a sane width.
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final perRow = constraints.maxWidth >= 640 ? 4 : 2;
              final cardWidth =
                  (constraints.maxWidth - gap * (perRow - 1)) / perRow;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final card in cards)
                    SizedBox(width: cardWidth, child: card),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    String label,
    double amount,
    Color color,
    IconData icon, {
    String? status,
    Color? statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          // Money strings can run long ("د.ع 1,250,000"). Scale them down
          // instead of letting them wrap or overflow on a narrow phone.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${context.tr('د.ع')} ${money(amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: AppColors.softText),
            textAlign: TextAlign.center,
          ),
          if (status != null && status.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (statusColor ?? color).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor ?? color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethods(
    Map<String, double> methodTotals,
    List<SettledOrder> orders,
  ) {
    // The admin asked for a card grid: the first row is a single, full-width
    // «وەسڵ (نەقد)» banner, and their sum is written once as
    // «کۆی دراوی ئەلیکترۆنی» directly beneath it. Each electronic brand then
    // gets its own card with the icon and name on top and the amount
    // underneath — three to a row. Every card is drawn even at zero so its own
    // page stays reachable.
    const int perRow = 3;
    final cashTotal = methodTotals['cash'] ?? 0;
    final electronicMethods =
        kPaymentMethods.where((m) => m != 'cash').toList(growable: false);
    final electronicTotal = electronicMethods.fold<double>(
      0,
      (sum, m) => sum + (methodTotals[m] ?? 0),
    );

    // Bucket the brands so the grid is always laid out in rows of [perRow].
    final List<List<String>> rows = [];
    for (var i = 0; i < electronicMethods.length; i += perRow) {
      final end = (i + perRow) <= electronicMethods.length
          ? i + perRow
          : electronicMethods.length;
      rows.add(electronicMethods.sublist(i, end));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.payment_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('ڕێگاکانی وەرگرتنی پارە'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Row 1: one card, the full width of the section.
          _paymentWideCard('cash', cashTotal, orders),
          // The electronic total sits directly under the «وەسڵ (نەقد)» banner,
          // before the individual electronic brand cards.
          const SizedBox(height: 14),
          _electronicTotalRow(electronicTotal),
          // Rows 2 & 3: three brand cards each.
          for (final row in rows) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < perRow; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: (i < row.length)
                        ? _paymentCard(
                            row[i],
                            methodTotals[row[i]] ?? 0,
                            orders,
                          )
                        : const SizedBox(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Opens the dedicated page for one collection method.
  void _openPaymentMethodPage(String method, List<SettledOrder> orders) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShiftPaymentMethodPage(
          method: method,
          orders: orders
              .where((o) => o.paymentMethod == method)
              .toList(growable: false),
        ),
      ),
    );
  }

  /// The one method that fronts the section as a full-width banner: its icon
  /// and name on the starting side, the amount on the other.
  Widget _paymentWideCard(
    String method,
    double total,
    List<SettledOrder> orders,
  ) {
    final color = paymentMethodColor(method);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openPaymentMethodPage(method, orders),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(paymentMethodIcon(method), size: 23, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                paymentMethodLabel(context, method),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.darkText,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${context.tr('د.ع')} ${money(total)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: color.withValues(alpha: 0.75),
            ),
          ],
        ),
      ),
    );
  }

  /// One electronic brand as a card: icon and name on top, the amount
  /// underneath. Always drawn, even at zero, so its own page stays reachable.
  Widget _paymentCard(String method, double total, List<SettledOrder> orders) {
    final color = paymentMethodColor(method);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openPaymentMethodPage(method, orders),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(paymentMethodIcon(method), size: 20, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              paymentMethodLabel(context, method),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${context.tr('د.ع')} ${money(total)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The sum of every electronic brand, written once directly under the
  /// «وەسڵ (نەقد)» banner so the two headline totals sit together.
  ///
  /// Sized and laid out like [_paymentWideCard] - the same 46px badge, 15pt
  /// label and 20pt amount - so the two headline figures read as a pair instead
  /// of this total looking like a footnote to the cash banner above it.
  Widget _electronicTotalRow(double total) {
    const color = AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              size: 23,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              context.tr('کۆی دراوی ئەلیکترۆنی'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.darkText,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${context.tr('د.ع')} ${money(total)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _SettledOrderCard extends ConsumerStatefulWidget {
  final SettledOrder order;
  final String Function(String) formatTime;
  final String Function(String) paymentLabel;
  final Color Function(String) paymentColor;

  const _SettledOrderCard({
    required this.order,
    required this.formatTime,
    required this.paymentLabel,
    required this.paymentColor,
  });

  @override
  ConsumerState<_SettledOrderCard> createState() => _SettledOrderCardState();
}

class _SettledOrderCardState extends ConsumerState<_SettledOrderCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final pmColor = widget.paymentColor(order.paymentMethod);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSide.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.table_restaurant_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.tableName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.formatTime(order.settledAt),
                          style: TextStyle(
                            color: AppColors.softText,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: pmColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.paymentLabel(order.paymentMethod),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: pmColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${context.tr('د.ع')} ${money(order.totalAmount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  _ReprintButton(order: order),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.softText,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildOrderItems(order.id),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItems(int settledOrderId) {
    final note = TableNote.decode(order.note);
    final captainNote = (note['captain'] ?? '').trim();
    final cashierNote = (note['admin'] ?? '').trim();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (captainNote.isNotEmpty || cashierNote.isNotEmpty) ...[
            _noteLine(
              Icons.person_rounded,
              AppColors.primary,
              context.tr('تێبینیی کاپتن'),
              captainNote,
            ),
            if (cashierNote.isNotEmpty) const SizedBox(height: 6),
            if (cashierNote.isNotEmpty)
              _noteLine(
                Icons.point_of_sale_rounded,
                const Color(0xFFFF6B35),
                context.tr('تێبینی کاشێر'),
                cashierNote,
              ),
            const SizedBox(height: 10),
          ],
          FutureBuilder<List<SettledOrderItem>>(
            future: ref
                .read(localDbProvider)
                .getSettledOrderItems(settledOrderId),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Text(
                  context.tr('هیچ بڕگەیەک نییە'),
                  style: TextStyle(color: AppColors.softText, fontSize: 12),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.discountPercent > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${context.tr('داشکاندن')}: ${order.discountPercent}% (${context.tr('د.ع')} ${money(order.discountAmount)})',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ),
                  ...items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 5,
                            color: AppColors.softText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.itemName,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.darkText,
                              ),
                            ),
                          ),
                          Text(
                            'x${item.quantity}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.softText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${context.tr('د.ع')} ${money((item.itemPrice * item.quantity))}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// One labelled note - the captain's or the cashier's - sitting above the
  /// dish list. Shown to the admin only; it is deliberately kept out of the
  /// receipt bytes in `EscPosBuilder`.
  Widget _noteLine(
    IconData icon,
    Color color,
    String label,
    String text,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppColors.darkText),
            ),
          ),
        ],
      ),
    );
  }

  SettledOrder get order => widget.order;
}

/// Reprints the receipt of one settled order from the shift report.
///
/// The admin can hand a guest a fresh copy of a bill that was closed earlier:
/// the button rebuilds the same cashier receipt the till prints (via
/// `PrintRouter.dispatchReceipt`), from the settled order's stored lines, so the
/// copy carries the dishes, the discount and the total - and, like the original,
/// never the table's note.
class _ReprintButton extends ConsumerStatefulWidget {
  const _ReprintButton({required this.order});

  final SettledOrder order;

  @override
  ConsumerState<_ReprintButton> createState() => _ReprintButtonState();
}

class _ReprintButtonState extends ConsumerState<_ReprintButton> {
  bool _busy = false;

  Future<void> _reprint() async {
    if (_busy) return;
    final order = widget.order;
    final cashierPrinter = ref
        .read(printerProvider)
        .printers
        .where((p) => p.printerType == PrinterType.cashier)
        .firstOrNull;
    final messenger = ScaffoldMessenger.of(context);
    if (cashierPrinter == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr('هیچ پرێنتەرێکی کاشێر ڕێک نەخراوە')),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final db = ref.read(localDbProvider);
      final settledItems = await db.getSettledOrderItems(order.id);
      final items = settledItems
          .map(
            (it) => OrderItem(
              id: '${it.id}',
              name: it.itemName,
              price: it.itemPrice,
              quantity: it.quantity,
              category: it.category,
              waiterName: it.waiterName,
              waiterRole: it.waiterRole,
            ),
          )
          .toList();
      final cashier = await db.getUserById(order.settledBy);
      final design = await db.getReceiptDesign();
      final subtotal = order.totalAmount + order.discountAmount;
      final ok = await PrintRouter.dispatchReceipt(
        tableNumber: order.tableId,
        guestCount: 0,
        items: items,
        subtotal: subtotal,
        discountPercent: order.discountPercent,
        discountAmount: order.discountAmount,
        total: order.totalAmount,
        printer: cashierPrinter,
        cashierName: cashier?.name ?? '',
        seatedAt: order.seatedAt,
        tableLabel: order.tableName,
        design: design,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? context.tr('چاپکردنەوەی وەسڵ')
                : context.tr('نەتوانرا چاپ بکرێت'),
          ),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr('نەتوانرا چاپ بکرێت')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.tr('چاپکردنەوەی وەسڵ'),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _busy ? null : _reprint,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : Icon(
                  Icons.print_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
        ),
      ),
    );
  }
}

/// The lower half of the shift report: one answer per tab, so the whole shift
/// lives on one page instead of being scattered across the admin home.
///
/// The five tabs mirror the admin's own sections - tables, orders, purchases,
/// debts and food demand - but scoped to this shift: orders are the shift's
/// settled orders, purchases fall inside the shift's open window, debts are the
/// shift's debt settlements and food demand is what the shift actually sold.
class _ShiftDetailTabs extends ConsumerStatefulWidget {
  final CashierShift shift;
  final List<SettledOrder> orders;
  final String Function(String) formatTime;
  final String Function(String) paymentLabel;
  final Color Function(String) paymentColor;

  const _ShiftDetailTabs({
    required this.shift,
    required this.orders,
    required this.formatTime,
    required this.paymentLabel,
    required this.paymentColor,
  });

  @override
  ConsumerState<_ShiftDetailTabs> createState() => _ShiftDetailTabsState();
}

class _ShiftDetailTabsState extends ConsumerState<_ShiftDetailTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<List<_DemandRow>> _demand;
  late Future<List<DebtModel>> _debts;
  late Future<List<RemainingTable>> _remaining;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 8, vsync: this);
    // The bar is a selector, not a page switcher: content is drawn below the
    // indicator so the page keeps scrolling as one list on every screen size.
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant _ShiftDetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live shift keeps growing: when the report pulls fresh orders the two
    // async tabs have to re-query too, or they would keep showing the snapshot
    // taken when the page first opened.
    if (!identical(oldWidget.orders, widget.orders) ||
        oldWidget.shift.id != widget.shift.id) {
      _load();
    }
  }

  void _load() {
    final db = ref.read(localDbProvider);
    _demand = _loadDemand();
    // The tables still on credit for this shift. Collected debts are settled
    // orders and already ride in `widget.orders`; these rows are the ones that
    // have not been paid off yet.
    _debts = db.getDebtsByShift(widget.shift.id);
    // The tables that were still seated when this shift was locked up - an
    // informational snapshot for the admin only.
    _remaining = db.getRemainingTablesByShift(widget.shift.id);
  }

  Future<List<_DemandRow>> _loadDemand() async {
    final db = ref.read(localDbProvider);
    final counts = <String, int>{};
    // One query covers every order in the shift. The previous loop ran a
    // separate `getSettledOrderItems` per settled order, so a busy shift fired
    // dozens of round-trips before this tab could paint.
    final items = await db.getSettledOrderItemsByShiftId(widget.shift.id);
    for (final it in items) {
      counts[it.itemName] = (counts[it.itemName] ?? 0) + it.quantity;
    }
    // A rejected-and-not-returned dish never reached a guest, so it is not
    // demand - the same rule the all-time food-demand page uses.
    final cancelled = await db.getCancelledItemsByShift(widget.shift.id);
    for (final c in cancelled) {
      if (c.status != 'pending') continue;
      final remaining = (counts[c.itemName] ?? 0) - c.quantity;
      if (remaining <= 0) {
        counts.remove(c.itemName);
      } else {
        counts[c.itemName] = remaining;
      }
    }
    final rows = counts.entries
        .map((e) => _DemandRow(name: e.key, quantity: e.value))
        .toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return rows;
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.insights_rounded,
                    color: AppColors.primary,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.tr('وردەکاری زیاتر'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.softText,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                text: context.tr('ئۆردەرەکان'),
              ),
              Tab(
                icon: const Icon(Icons.table_restaurant_rounded, size: 18),
                text: context.tr('مێزەکانی ماون'),
              ),
              Tab(
                icon: const Icon(Icons.bookmark_rounded, size: 18),
                text: context.tr('قەرزەکان'),
              ),
              Tab(
                icon: const Icon(Icons.trending_up_rounded, size: 18),
                text: context.tr('داواکاری خواردن'),
              ),
              // The four shift-scoped reports used to be jump-off tiles that
              // pushed a page; they now live in the same bar as the data tabs so
              // their content shows inline, right under the selector.
              Tab(
                icon: const Icon(Icons.block_rounded, size: 18),
                text: context.tr('ڕەتکراوەکان'),
              ),
              Tab(
                icon: const Icon(Icons.money_off_csred_rounded, size: 18),
                text: context.tr('خەرجیەکان'),
              ),
              Tab(
                icon: const Icon(Icons.replay_rounded, size: 18),
                text: context.tr('گەڕانەوەی خەرجی'),
              ),
              Tab(
                icon: const Icon(Icons.psychology_rounded, size: 18),
                text: context.tr('زیرەکی کاپتن'),
              ),
            ],
          ),
          const Divider(height: 1, color: AppColors.borderSide),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _content(_tab.index),
          ),
        ],
      ),
    );
  }

  Widget _content(int index) {
    switch (index) {
      case 0:
        return _ordersTab();
      case 1:
        return _remainingTab();
      case 2:
        return _debtsTab();
      case 3:
        return _demandTab();
      case 4:
        return ShiftRejectedItemsView(
          shiftId: widget.shift.id,
          refreshToken: widget.orders,
        );
      case 5:
        return ShiftExpensesView(
          shiftId: widget.shift.id,
          refreshToken: widget.orders,
        );
      case 6:
        return ShiftExpensesView(
          shiftId: widget.shift.id,
          returnsOnly: true,
          refreshToken: widget.orders,
        );
      default:
        return ShiftCaptainReportView(orders: widget.orders);
    }
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 40,
            color: AppColors.softText.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.softText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _ordersTab() {
    final orders = widget.orders;
    if (orders.isEmpty) return _empty(context.tr('هیچ زانیاریەک نییە'));
    return Column(
      children: orders
          .map(
            (o) => _SettledOrderCard(
              order: o,
              formatTime: widget.formatTime,
              paymentLabel: widget.paymentLabel,
              paymentColor: widget.paymentColor,
            ),
          )
          .toList(),
    );
  }

  // «مێزەکانی ماون» is the informational snapshot taken when the shift closed:
  // the tables that were still sitting with an open bill. It is for the admin
  // only - nothing here is settled or counted - so the tab simply lists the
  // tables and opens their full contents on tap.
  Widget _remainingTab() {
    return FutureBuilder<List<RemainingTable>>(
      future: _remaining,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final tables = snap.data ?? const <RemainingTable>[];
        if (tables.isEmpty) {
          return _empty(context.tr('هیچ مێزێکی ماوە نییە'));
        }
        final total = tables.fold<double>(0, (s, t) => s + t.totalAmount);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.table_restaurant_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${context.tr('مێزەکانی ماون')}: ${tables.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${context.tr('کۆی گشتی')}: '
                          '${context.tr('د.ع')} ${money(total)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.softText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...tables.map(_remainingTableCard),
          ],
        );
      },
    );
  }

  Widget _remainingTableCard(RemainingTable t) {
    final items = decodeRemainingTableItems(t.itemsJson);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showRemainingTable(t),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.table_restaurant_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tableName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          '${context.tr('میوان')}: ${t.guestCount}',
                          if (t.waiterName.isNotEmpty) t.waiterName,
                          if (items.isNotEmpty)
                            '${context.tr('خواردنەکان')}: ${items.length}',
                          widget.formatTime(t.seatedAt),
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.softText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${context.tr('د.ع')} ${money(t.totalAmount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.softText,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Everything that table had when the shift was locked up: the people, the
  /// note and the full dish list, shown when its row is tapped.
  void _showRemainingTable(RemainingTable t) {
    final items = decodeRemainingTableItems(t.itemsJson);
    final note = TableNote.decode(t.note);
    final captainNote = (note['captain'] ?? '').trim();
    final cashierNote = (note['admin'] ?? '').trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.table_restaurant_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.tableName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                      Text(
                        '${context.tr('د.ع')} ${money(t.totalAmount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _remainingChip(
                        Icons.people_alt_rounded,
                        '${context.tr('میوان')}: ${t.guestCount}',
                      ),
                      if (t.waiterName.isNotEmpty)
                        _remainingChip(Icons.person_rounded, t.waiterName),
                      if (t.seatedAt.isNotEmpty)
                        _remainingChip(
                          Icons.schedule_rounded,
                          widget.formatTime(t.seatedAt),
                        ),
                      _remainingChip(
                        Icons.access_time_rounded,
                        widget.formatTime(t.createdAt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (captainNote.isNotEmpty || cashierNote.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  children: [
                    if (captainNote.isNotEmpty)
                      _noteLine(
                        Icons.person_rounded,
                        AppColors.primary,
                        context.tr('تێبینیی کاپتن'),
                        captainNote,
                      ),
                    if (captainNote.isNotEmpty && cashierNote.isNotEmpty)
                      const SizedBox(height: 6),
                    if (cashierNote.isNotEmpty)
                      _noteLine(
                        Icons.point_of_sale_rounded,
                        const Color(0xFFFF6B35),
                        context.tr('تێبینی کاشێر'),
                        cashierNote,
                      ),
                  ],
                ),
              ),
            ],
            const Divider(height: 1, color: AppColors.borderSide),
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          context.tr('هیچ زانیاریەک نییە'),
                          style: const TextStyle(color: AppColors.softText),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: AppColors.borderSide,
                      ),
                      itemBuilder: (_, i) {
                        final l = items[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: AppColors.darkText,
                                      ),
                                    ),
                                    if (l.waiterName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        staffLabel(
                                          context,
                                          l.waiterRole,
                                          l.waiterName,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.softText,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Text(
                                '×${l.quantity}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.softText,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${context.tr('د.ع')} ${money(l.subtotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.darkText,
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
      ),
    );
  }

  Widget _remainingChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 2),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.darkText,
            ),
          ),
        ],
      ),
    );
  }

  // One labelled note - the captain's or the cashier's - sitting above the dish
  // list. Shown to the admin only.
  Widget _noteLine(
    IconData icon,
    Color color,
    String label,
    String text,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppColors.darkText),
            ),
          ),
        ],
      ),
    );
  }

  // «قەرزەکان» shows the shift's credit in two parts: the tables that are still
  // on credit (rows in the `debts` table, nothing collected yet) and the debts
  // that were collected during the shift (settled orders paid as `debt`). The
  // money card up top already adds both; here the admin can see which tables
  // they are.
  Widget _debtsTab() {
    return FutureBuilder<List<DebtModel>>(
      future: _debts,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final open = snap.data ?? const <DebtModel>[];
        final collected = widget.orders
            .where((o) => o.paymentMethod == 'debt')
            .toList();
        if (open.isEmpty && collected.isEmpty) {
          return _empty(context.tr('هیچ زانیاریەک نییە'));
        }
        final openTotal = open.fold<double>(0, (s, d) => s + d.amount);
        final collectedTotal = collected.fold<double>(
          0,
          (s, o) => s + o.totalAmount,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bookmark_rounded,
                    color: Color(0xFFFF6B35),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${context.tr('کۆی گشتی')}: '
                          '${context.tr('د.ع')} '
                          '${money(openTotal + collectedTotal)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${context.tr('مێزەکانی قەرز')}: '
                          '${context.tr('د.ع')} ${money(openTotal)}  |  '
                          '${context.tr('قەرزی وەرگیراو')}: '
                          '${context.tr('د.ع')} ${money(collectedTotal)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.softText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (open.isNotEmpty) ...[
              _debtGroupLabel(
                context.tr('مێزەکانی قەرز'),
                open.length,
                const Color(0xFFFF6B35),
              ),
              ...open.map(_openDebtCard),
            ],
            if (collected.isNotEmpty) ...[
              _debtGroupLabel(
                context.tr('قەرزی وەرگیراو'),
                collected.length,
                AppColors.primary,
              ),
              ...collected.map(
                (o) => _SettledOrderCard(
                  order: o,
                  formatTime: widget.formatTime,
                  paymentLabel: widget.paymentLabel,
                  paymentColor: widget.paymentColor,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _debtGroupLabel(String text, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$text ($count)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // A table that is still on credit. Its dishes live in the debt's snapshot
  // (taken when the table was moved, before the order was cleared), so tapping
  // the row opens them: the admin asked to see what a credit table ordered.
  Widget _openDebtCard(DebtModel d) {
    final lines = decodeDebtLines(d.itemsJson);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showDebtItems(d),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.table_restaurant_rounded,
                    color: Color(0xFFFF6B35),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.tableName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (lines.isNotEmpty)
                            '${context.tr('خواردنەکان')}: ${lines.length}',
                          if (d.reason.isNotEmpty) d.reason,
                          widget.formatTime(d.createdAt),
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.softText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${context.tr('د.ع')} ${money(d.amount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFFFF6B35),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.softText,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The dishes that were on a credit table, shown when its row is tapped.
  void _showDebtItems(DebtModel d) {
    final lines = decodeDebtLines(d.itemsJson);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.table_restaurant_rounded,
                    color: Color(0xFFFF6B35),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.tableName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.darkText,
                          ),
                        ),
                        Text(
                          '${context.tr('خواردنەکان')}: ${lines.length}  •  '
                          '${widget.formatTime(d.createdAt)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.softText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${context.tr('د.ع')} ${money(d.amount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderSide),
            Flexible(
              child: lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          context.tr('هیچ زانیاریەک نییە'),
                          style: const TextStyle(color: AppColors.softText),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      itemCount: lines.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: AppColors.borderSide,
                      ),
                      itemBuilder: (_, i) {
                        final l = lines[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: AppColors.darkText,
                                  ),
                                ),
                              ),
                              Text(
                                '×${l.quantity}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.softText,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${context.tr('د.ع')} ${money(l.subtotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.darkText,
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
      ),
    );
  }

  Widget _demandTab() {
    return FutureBuilder<List<_DemandRow>>(
      future: _demand,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rows = snap.data ?? const <_DemandRow>[];
        if (rows.isEmpty) {
          return _empty(context.tr('هیچ خواردنێک نەفرۆشراوە لەم ماوەیە'));
        }
        return Column(
          children: rows
              .map(
                (r) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${r.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              context.tr('دانە'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DemandRow {
  final String name;
  final int quantity;
  const _DemandRow({required this.name, required this.quantity});
}
