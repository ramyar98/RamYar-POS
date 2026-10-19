import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/fmt.dart';
import '../../database/local_db.dart';
import '../../services/app_localizations.dart';
import 'payment_method_style.dart';

/// «خەرجیەکان» / «گەڕانەوەی خەرجی» for one shift, from the admin report.
///
/// Expenses and their returns share one table (`cashier_expenses`): a normal
/// expense is written with a positive price and a return with a negative one.
/// This is the shift-scoped window onto one of those two halves, so the admin
/// can open a shift - closed or still running - and read exactly what was taken
/// out of the drawer (or put back) and when.
///
/// Like the rejected view it is scroll-agnostic (returns a [Column]) so the
/// shift report can show it as a tab; [ShiftExpensesPage] wraps the same view
/// for the entry points that still push a page.
class ShiftExpensesView extends ConsumerStatefulWidget {
  final int shiftId;

  /// When true the view lists the returned expenses (the negative prices)
  /// instead of the expenses themselves.
  final bool returnsOnly;

  /// Changes identity when the report pulls fresh data (see the rejected view).
  final Object? refreshToken;

  const ShiftExpensesView({
    super.key,
    required this.shiftId,
    this.returnsOnly = false,
    this.refreshToken,
  });

  @override
  ConsumerState<ShiftExpensesView> createState() => ShiftExpensesViewState();
}

class ShiftExpensesViewState extends ConsumerState<ShiftExpensesView> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShiftExpensesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shiftId != widget.shiftId ||
        oldWidget.returnsOnly != widget.returnsOnly ||
        !identical(oldWidget.refreshToken, widget.refreshToken)) {
      _reloadSync();
    }
  }

  void _load() {
    _future = ref.read(localDbProvider).getShiftExpenses(widget.shiftId);
  }

  /// Re-runs the shift query; the standalone page's pull-to-refresh calls it.
  Future<void> reload() async {
    setState(_load);
    await _future;
  }

  void _reloadSync() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final returns = widget.returnsOnly;
    final accent = returns ? AppColors.blue : const Color(0xFFFF6B35);
    final icon = returns ? Icons.replay_rounded : Icons.money_off_csred_rounded;
    final title = context.tr(returns ? 'گەڕانەوەی خەرجی' : 'خەرجیەکان');

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rows = (snapshot.data ?? const [])
            .where(
              (e) => returns
                  ? (e['price'] as num) < 0
                  : (e['price'] as num) > 0,
            )
            .toList(growable: false);
        if (rows.isEmpty) return _empty(returns, icon);
        final total = rows.fold<double>(
          0,
          (sum, e) => sum + (e['price'] as num).abs().toDouble(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary(title, rows.length, total, accent, icon),
            const SizedBox(height: 12),
            ...rows.map((e) => _row(e, accent, icon)),
          ],
        );
      },
    );
  }

  Widget _empty(bool returns, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 72, color: AppColors.softText.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              context.tr(
                returns ? 'هیچ گەڕانەوەی خەرجی نییە' : 'هیچ خەرجییەک نییە',
              ),
              style: const TextStyle(fontSize: 16, color: AppColors.softText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(
    String title,
    int count,
    double total,
    Color accent,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title ($count)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.darkText,
                  ),
                ),
                Text(
                  context.tr('کۆی گشتی'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.softText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${context.tr('د.ع')} ${money(total)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> expense, Color accent, IconData icon) {
    final name = (expense['itemName'] ?? '').toString();
    final amount = (expense['price'] as num).abs().toDouble();
    final createdAt = (expense['createdAt'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSide),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.darkText,
                  ),
                ),
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 12,
                        color: AppColors.softText,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${context.tr('کات')}: ${formatShiftTime(context, createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.softText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${context.tr('د.ع')} ${money(amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pushable «خەرجیەکان» / «گەڕانەوەی خەرجی» page.
class ShiftExpensesPage extends ConsumerStatefulWidget {
  final int shiftId;

  /// When true the page lists the returned expenses (the negative prices)
  /// instead of the expenses themselves.
  final bool returnsOnly;

  const ShiftExpensesPage({
    super.key,
    required this.shiftId,
    this.returnsOnly = false,
  });

  @override
  ConsumerState<ShiftExpensesPage> createState() => _ShiftExpensesPageState();
}

class _ShiftExpensesPageState extends ConsumerState<ShiftExpensesPage> {
  final _viewKey = GlobalKey<ShiftExpensesViewState>();

  @override
  Widget build(BuildContext context) {
    final returns = widget.returnsOnly;
    final accent = returns ? AppColors.blue : const Color(0xFFFF6B35);
    final icon = returns ? Icons.replay_rounded : Icons.money_off_csred_rounded;
    final title = context.tr(returns ? 'گەڕانەوەی خەرجی' : 'خەرجیەکان');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
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
      body: RefreshIndicator(
        onRefresh: () =>
            _viewKey.currentState?.reload() ?? Future<void>.value(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: ShiftExpensesView(
            key: _viewKey,
            shiftId: widget.shiftId,
            returnsOnly: widget.returnsOnly,
          ),
        ),
      ),
    );
  }
}
