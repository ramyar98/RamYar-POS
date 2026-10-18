import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/fmt.dart';
import '../../database/local_db.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../../services/app_localizations.dart';

/// «زیرەکی کاپتن» for one shift: how much each person sold while that shift
/// was open, biggest seller first. The admin asked to see "who sold the most" -
/// so the leader gets a crown and the list is a ranking, not an alphabet.
///
/// A sale is credited to whoever rang the dish in (`SettledOrderItem.waiterName`
/// + `waiterRole`, copied off the order line at settlement) rather than to the
/// table's waiter. That is deliberate: a cashier who adds food to a table is a
/// salesperson too, so both captains and cashiers show up here. Every captain
/// is listed even when they sold nothing; a cashier appears only when they
/// actually rang something in.
///
/// Scroll-agnostic (returns a [Column]) so the shift report can show it as a
/// tab; [ShiftCaptainReportPage] wraps the same view in a page.
class ShiftCaptainReportView extends ConsumerStatefulWidget {
  final List<SettledOrder> orders;

  const ShiftCaptainReportView({super.key, required this.orders});

  @override
  ConsumerState<ShiftCaptainReportView> createState() =>
      ShiftCaptainReportViewState();
}

class ShiftCaptainReportViewState extends ConsumerState<ShiftCaptainReportView> {
  List<_CaptainRow> _rows = [];
  double _totalAmount = 0;
  int _totalItems = 0;
  int _orders = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShiftCaptainReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A live shift keeps settling orders; re-rank whenever the report refreshes.
    if (!identical(oldWidget.orders, widget.orders)) _load();
  }

  Future<void> _load() async {
    final db = ref.read(localDbProvider);
    final orders = widget.orders;
    final waiters = await db.getUsersByRole(UserRole.waiter);
    final cashiers = await db.getUsersByRole(UserRole.cashier);
    final items = await db.getSettledOrderItemsByOrderIds(
      orders.map((o) => o.id).toList(),
    );
    if (!mounted) return;

    // Credit every dish to the person who rang it in, not to the table's
    // waiter: a cashier who adds food to a table is a salesperson too, and the
    // admin wants to see who worked more.
    final byName = <String, _Tally>{};
    var unknownItems = 0;
    var unknownAmount = 0.0;
    for (final item in items) {
      final value = item.itemPrice * item.quantity;
      final name = item.waiterName.trim();
      if (name.isEmpty) {
        // A line from before the adder was recorded: keep its money visible.
        unknownItems += item.quantity;
        unknownAmount += value;
        continue;
      }
      final tally = byName.putIfAbsent(name, _Tally.new);
      tally.items += item.quantity;
      tally.amount += value;
    }

    final rows = <_CaptainRow>[];
    // Every captain is listed, even one who sold nothing: the ranking is how
    // the admin sees who worked.
    for (final w in waiters) {
      final t = byName.remove(w.name);
      rows.add(
        _CaptainRow(
          name: w.name,
          role: context.tr('کاپتن'),
          items: t?.items ?? 0,
          amount: t?.amount ?? 0,
        ),
      );
    }
    // Cashiers only appear when they actually rang something in.
    for (final c in cashiers) {
      final t = byName.remove(c.name);
      if (t == null || t.items == 0) continue;
      rows.add(
        _CaptainRow(
          name: c.name,
          role: context.tr('کاشێر'),
          items: t.items,
          amount: t.amount,
        ),
      );
    }
    // A line whose adder is no longer a captain or cashier (deleted account,
    // legacy row) still belongs to the shift, so surface it rather than hide
    // the money.
    byName.forEach((name, t) {
      rows.add(
        _CaptainRow(name: name, role: '', items: t.items, amount: t.amount),
      );
    });
    if (unknownItems > 0) {
      rows.add(
        _CaptainRow(
          name: context.tr('کەس'),
          role: '',
          items: unknownItems,
          amount: unknownAmount,
          unknown: true,
        ),
      );
    }

    rows.sort((a, b) => b.amount.compareTo(a.amount));

    _totalAmount = rows.fold<double>(0, (s, r) => s + r.amount);
    _totalItems = rows.fold<int>(0, (s, r) => s + r.items);
    _orders = orders.length;
    _rows = rows;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _totalsCard(),
        const SizedBox(height: 12),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                context.tr('هیچ زانیاریەک نییە'),
                style: const TextStyle(color: AppColors.softText),
              ),
            ),
          )
        else
          ...List.generate(_rows.length, (i) => _captainCard(_rows[i], i)),
      ],
    );
  }

  Widget _totalsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.psychology_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${context.tr('داواکاری')}: $_orders  •  '
                  '${context.tr('خواردنەکان')}: $_totalItems',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.softText,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${context.tr('کۆی بڕ')}: ${context.tr('د.ع')} ${money(_totalAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _captainCard(_CaptainRow row, int index) {
    final isTop = index == 0 && !row.unknown && row.amount > 0;
    final color = isTop ? const Color(0xFFF9A825) : AppColors.primary;
    final subtitle = [
      if (row.role.isNotEmpty) row.role,
      '${context.tr('خواردنەکان')}: ${row.items}',
    ].join('  •  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTop ? color.withValues(alpha: 0.5) : AppColors.borderSide,
          width: isTop ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Icon(
                isTop ? Icons.workspace_premium_rounded : Icons.person_rounded,
                color: color,
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
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.softText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${context.tr('د.ع')} ${money(row.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isTop ? const Color(0xFFF9A825) : AppColors.darkText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pushable «زیرەکی کاپتن» page.
class ShiftCaptainReportPage extends ConsumerStatefulWidget {
  final List<SettledOrder> orders;

  const ShiftCaptainReportPage({super.key, required this.orders});

  @override
  ConsumerState<ShiftCaptainReportPage> createState() =>
      _ShiftCaptainReportPageState();
}

class _ShiftCaptainReportPageState
    extends ConsumerState<ShiftCaptainReportPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const Icon(Icons.psychology_rounded, color: Color(0xFF7B1FA2)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.tr('زیرەکی کاپتن'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: ShiftCaptainReportView(orders: widget.orders),
      ),
    );
  }
}

class _CaptainRow {
  final String name;
  final String role;
  final int items;
  final double amount;
  final bool unknown;

  _CaptainRow({
    required this.name,
    required this.role,
    required this.items,
    required this.amount,
    this.unknown = false,
  });
}

/// Running total for one person while the shift's dish lines are tallied.
class _Tally {
  int items = 0;
  double amount = 0;
}
