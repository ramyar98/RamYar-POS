import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/fmt.dart';
import '../../database/local_db.dart';
import '../../models/settlement_model.dart';
import '../../services/app_localizations.dart';
import 'payment_method_style.dart';

/// One money-collection method (FIB, FastPay, Super QI, …) inside a single
/// shift: every settled order that was paid that way, each expandable into the
/// dishes it carried. Reached from the «ڕێگاکانی وەرگرتنی پارە» rows of the shift
/// report, so what used to be a cramped dialog is now a full page that answers
/// the same questions as opening a table and reading its food.
class ShiftPaymentMethodPage extends ConsumerStatefulWidget {
  final String method;
  final List<SettledOrder> orders;

  const ShiftPaymentMethodPage({
    super.key,
    required this.method,
    required this.orders,
  });

  @override
  ConsumerState<ShiftPaymentMethodPage> createState() =>
      _ShiftPaymentMethodPageState();
}

class _ShiftPaymentMethodPageState
    extends ConsumerState<ShiftPaymentMethodPage> {
  @override
  Widget build(BuildContext context) {
    final method = widget.method;
    final orders = widget.orders;
    final total = orders.fold<double>(0, (s, o) => s + o.totalAmount);
    final color = paymentMethodColor(method);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Icon(paymentMethodIcon(method), color: color, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                paymentMethodLabel(context, method),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(context, method, color, total, orders.length),
          const SizedBox(height: 16),
          if (orders.isEmpty)
            _emptyState(context)
          else
            ...orders.map(
              (o) => _PaymentOrderTile(
                order: o,
                color: color,
                formatTime: formatShiftTime,
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context,
    String method,
    Color color,
    double total,
    int count,
  ) {
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
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(paymentMethodIcon(method), color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${context.tr('کۆی گشتی')}:',
                  style: TextStyle(fontSize: 12, color: AppColors.softText),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${context.tr('د.ع')} ${money(total)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color,
                  ),
                ),
                Text(
                  context.tr('داواکاری'),
                  style: TextStyle(fontSize: 10, color: AppColors.softText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 48,
            color: AppColors.softText.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('هیچ بڕگەیەک نییە'),
            style: TextStyle(color: AppColors.softText, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// A settled order paid with one method. Collapsed it shows the table, the time
/// and the amount; expanded it fetches and lists the dishes (with quantities and
/// line totals), exactly like the report's order cards.
class _PaymentOrderTile extends ConsumerStatefulWidget {
  final SettledOrder order;
  final Color color;
  final String Function(String) formatTime;

  const _PaymentOrderTile({
    required this.order,
    required this.color,
    required this.formatTime,
  });

  @override
  ConsumerState<_PaymentOrderTile> createState() => _PaymentOrderTileState();
}

class _PaymentOrderTileState extends ConsumerState<_PaymentOrderTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
                      color: widget.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.table_restaurant_rounded,
                      color: widget.color,
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
                  Text(
                    '${context.tr('د.ع')} ${money(order.totalAmount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: widget.color,
                    ),
                  ),
                  const SizedBox(width: 8),
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
            secondChild: _buildItems(order.id),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildItems(int settledOrderId) {
    final order = widget.order;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
      ),
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<List<SettledOrderItem>>(
        future: ref.read(localDbProvider).getSettledOrderItems(settledOrderId),
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
                      '${context.tr('داشکاندن')}: ${order.discountPercent}% '
                      '(${context.tr('د.ع')} ${money(order.discountAmount)})',
                      style: const TextStyle(
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
                      Icon(Icons.circle, size: 5, color: AppColors.softText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.itemName,
                          style: const TextStyle(
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
                        '${context.tr('د.ع')} ${money(item.itemPrice * item.quantity)}',
                        style: const TextStyle(
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
    );
  }
}
