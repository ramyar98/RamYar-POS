import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/fmt.dart';
import '../../database/local_db.dart';
import '../../models/cancelled_item_model.dart';
import '../../services/app_localizations.dart';
import 'payment_method_style.dart';

/// «ڕەتکراوەکان» for one shift: every dish the cashier threw out during that
/// shift, with the full story the admin asked for - the dish, its table, who
/// rang it in (captain or cashier), who rejected it and when it was ordered
/// versus rejected.
///
/// Unlike the cashier's own queue this is a window only (no move-back button)
/// and it is scoped to the shift, so a closed shift keeps its own record even
/// after the live queue has moved on.
///
/// The view is deliberately scroll-agnostic: it returns its content as a
/// [Column] so it can be dropped straight into the shift report as a tab, and
/// [ShiftRejectedItemsPage] wraps the very same view in a scrolling page for
/// the places that still want one.
class ShiftRejectedItemsView extends ConsumerStatefulWidget {
  final int shiftId;

  /// Anything that changes identity when the report pulls fresh data. The tab
  /// embeds the view inside a page that reloads on pull-to-refresh, so without
  /// this the list would keep the snapshot taken when the tab first opened.
  final Object? refreshToken;

  const ShiftRejectedItemsView({
    super.key,
    required this.shiftId,
    this.refreshToken,
  });

  @override
  ConsumerState<ShiftRejectedItemsView> createState() =>
      ShiftRejectedItemsViewState();
}

class ShiftRejectedItemsViewState
    extends ConsumerState<ShiftRejectedItemsView> {
  late Future<List<CancelledItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _query();
  }

  @override
  void didUpdateWidget(covariant ShiftRejectedItemsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shiftId != widget.shiftId ||
        !identical(oldWidget.refreshToken, widget.refreshToken)) {
      _reload();
    }
  }

  Future<List<CancelledItem>> _query() =>
      ref.read(localDbProvider).getCancelledItemsByShift(widget.shiftId);

  /// Re-runs the shift query; the standalone page's pull-to-refresh calls it.
  Future<void> reload() async {
    setState(() => _future = _query());
    await _future;
  }

  void _reload() {
    setState(() => _future = _query());
  }

  /// «کاپتن ئاراس» / «کاشێر شیلان» rather than a bare name: both roles ring
  /// dishes onto tables, and only the role says who actually did.
  String _requesterLabel(CancelledItem item) {
    final role = switch (item.requestedByRole) {
      0 => context.tr('کاپتن'),
      1 => context.tr('کاشێر'),
      _ => '',
    };
    if (role.isEmpty) return item.requestedByName;
    return '$role ${item.requestedByName}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CancelledItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data ?? const <CancelledItem>[];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 72,
                  color: AppColors.softText.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    context.tr('هیچ خواردنێکی ڕەتکراو نییە'),
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.softText,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final pending = items.where((i) => i.status == 'pending').toList();
        final totalValue = items.fold<double>(
          0,
          (s, i) => s + (i.itemPrice * i.quantity),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summary(items.length, pending.length, totalValue),
            const SizedBox(height: 12),
            ...items.map(_itemCard),
          ],
        );
      },
    );
  }

  Widget _summary(int count, int pending, double totalValue) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_rounded, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.trp('{count} خواردنی ڕەتکراو', {
                    'count': count.toString(),
                  }),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.darkText,
                  ),
                ),
                if (pending > 0)
                  Text(
                    '${context.tr('چاوەڕوانە')}: $pending',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.softText,
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${context.tr('د.ع')} ${money(totalValue)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(CancelledItem item) {
    final subtotal = item.itemPrice * item.quantity;
    final pending = item.status == 'pending';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One row of facts first - the table, when it was ordered, when it
          // was rejected, who asked for it and what it is worth. A Wrap keeps
          // them on a single line on a tablet and folds them on a phone.
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _fact(
                Icons.table_restaurant_rounded,
                context.trp('مێزی {name}', {'name': item.tableName}),
                AppColors.primary,
              ),
              if (item.requestedAt.isNotEmpty)
                _fact(
                  Icons.add_circle_outline_rounded,
                  '${context.tr('کاتی داواکردن')}: '
                  '${formatShiftTime(item.requestedAt)}',
                  AppColors.primary,
                ),
              _fact(
                Icons.block_rounded,
                '${context.tr('کاتی ڕەتکردنەوە')}: '
                '${formatShiftTime(item.cancelledAt)}',
                AppColors.danger,
              ),
              if (item.requestedByName.isNotEmpty)
                _fact(
                  Icons.person_rounded,
                  '${context.tr('داواکەر')}: ${_requesterLabel(item)}',
                  AppColors.primary,
                ),
              _fact(
                Icons.payments_rounded,
                '${context.tr('کۆی گشتی')}: '
                '${context.tr('د.ع')} ${money(subtotal)}',
                AppColors.danger,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The dish itself sits below the row of facts.
          Row(
            children: [
              Expanded(
                child: Text(
                  item.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.darkText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (pending ? AppColors.danger : AppColors.success)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pending
                      ? context.tr('چاوەڕوانە')
                      : context.tr('گەڕێنراوەتەوە'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: pending ? AppColors.danger : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${item.quantity} × ${context.tr('د.ع')} ${money(item.itemPrice)}',
            style: const TextStyle(fontSize: 13, color: AppColors.softText),
          ),
          if (item.cancelledByName.isNotEmpty)
            _detailLine(
              Icons.person_off_outlined,
              '${context.tr('ڕەتکەر')}: ${item.cancelledByName}',
              AppColors.danger,
            ),
          if (item.servedAt.isNotEmpty)
            _detailLine(
              Icons.restore_rounded,
              '${context.tr('گەڕێنراوەتەوە')}: '
              '${formatShiftTime(item.servedAt)}',
              AppColors.success,
            ),
        ],
      ),
    );
  }

  /// One fact on the top row of a rejected card: a small icon plus its text,
  /// sized to its content so several share a line.
  Widget _fact(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }

  /// One labelled fact on its own line. A line rather than a chip because the
  /// names and timestamps are long: a wrap of chips overflowed on narrow phones,
  /// while a full-width row lets the text shrink and ellipsize instead.
  Widget _detailLine(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}

/// The pushable «ڕەتکراوەکان» page: the view above wrapped in its own app bar.
class ShiftRejectedItemsPage extends ConsumerStatefulWidget {
  final int shiftId;

  const ShiftRejectedItemsPage({super.key, required this.shiftId});

  @override
  ConsumerState<ShiftRejectedItemsPage> createState() =>
      _ShiftRejectedItemsPageState();
}

class _ShiftRejectedItemsPageState
    extends ConsumerState<ShiftRejectedItemsPage> {
  final _viewKey = GlobalKey<ShiftRejectedItemsViewState>();

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
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.block_rounded,
                color: AppColors.danger,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.tr('ڕەتکراوەکان'),
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
      body: RefreshIndicator(
        onRefresh: () =>
            _viewKey.currentState?.reload() ?? Future<void>.value(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: ShiftRejectedItemsView(
            key: _viewKey,
            shiftId: widget.shiftId,
          ),
        ),
      ),
    );
  }
}
