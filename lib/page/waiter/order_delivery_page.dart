import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../models/order_delivery_model.dart';
import '../../providers/waiter_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/sync_provider.dart';
import 'table_page.dart';

/// ڕەنگی زەرد بۆ داواکارییە چاوەڕێکەرەکەن (Pending Connection)
const Color _pendingYellow = Color(0xFFE6A700);

/// پەڕەی تەواو بۆ دۆخی ناردنی داواکارییەکان (Order Delivery).
///
/// ئەم پەڕەیە دۆخی هەر داواکارییەک پیشان دەدات:
///  - زەرد (Pending Connection): داواکاری نێردراوە بەڵام نەگەیشتووە / لە ڕیزی سینکدایە
///  - شین (Arrived): گەیشتە لای کاشێر بەڵام هێشتا پرێنت نەکراوە
///  - سەوز (Printed): پرێنت کرا
///  - سوور (Rejected): ڕەفز کراوە (دوبارە بووە)
class OrderDeliveryPage extends ConsumerStatefulWidget {
  const OrderDeliveryPage({super.key});

  @override
  ConsumerState<OrderDeliveryPage> createState() => _OrderDeliveryPageState();
}

class _OrderDeliveryPageState extends ConsumerState<OrderDeliveryPage> {
  Timer? _refreshTimer;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.invalidate(deliveryStatusProvider);
        ref.invalidate(pendingSyncCountProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(deliveryStatusProvider);
    ref.invalidate(pendingSyncCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncConnectionProvider);
    final deliveriesAsync = ref.watch(deliveryStatusProvider);
    final pendingAsync = ref.watch(pendingSyncCountProvider);
    final deliveries =
        deliveriesAsync.asData?.value ?? const <OrderDeliveryModel>[];
    final pendingCount = pendingAsync.asData?.value ?? 0;

    final waiting = deliveries.where((d) => d.isNotArrived).length;
    final arrived = deliveries
        .where(
          (d) =>
              d.hasArrived && !d.hasPrinted && !d.isPrintFailed && !d.rejected,
        )
        .length;
    final retryPrints = deliveries.where((d) => d.isRetryPrint).length;
    final printed = deliveries.where((d) => d.isPrinted).length;
    final rejected = deliveries.where((d) => d.rejected).length;
    final visibleDeliveries = deliveries.where((d) {
      switch (_selectedFilter) {
        case 'arrived':
          return d.hasArrived &&
              !d.hasPrinted &&
              !d.isPrintFailed &&
              !d.rejected;
        case 'not_arrived':
          return d.isNotArrived;
        case 'printed':
          return d.isPrinted;
        case 'retry_print':
          return d.isRetryPrint;
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          context.tr('دۆخی ناردنی داواکاری'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('نوێکردنەوە'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: Responsive.screenPadding(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 600, the app-wide phone/tablet breakpoint (the page used 700
              // before, which left 600-699 on the phone layout while every
              // other page went tablet there).
              final isDesktop = constraints.maxWidth >= 600;
              // One scroll region for the whole body. The old layout was a
              // Column with a fixed header stack (banner + filter chips +
              // legend) above an Expanded list: on a short landscape phone the
              // header alone was taller than the body and the Column threw a
              // RenderFlex overflow, and the empty state inside the leftover
              // Expanded got whatever tiny height remained and overflowed a
              // second time. As slivers, the header, the legend and the cards
              // share one viewport and simply scroll when they do not fit.
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildConnectionBanner(syncState, pendingCount),
                  ),
                  SliverToBoxAdapter(child: _buildFilterBar()),
                  SliverToBoxAdapter(
                    child: _buildLegendRow(
                      waiting,
                      arrived,
                      retryPrints,
                      printed,
                      rejected,
                    ),
                  ),
                  if (visibleDeliveries.isEmpty)
                    // fillOverscroll:false + FittedBox: the message is laid out
                    // in whatever height is left (even close to zero on a
                    // very short screen) and scales down instead of
                    // overflowing.
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildEmptyState(),
                      ),
                    )
                  else if (isDesktop)
                    _buildDesktopSliverGrid(
                      visibleDeliveries,
                      constraints.maxWidth,
                    )
                  else
                    _buildMobileSliverList(visibleDeliveries),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(SyncState syncState, int pendingCount) {
    final disconnectedWithPending = !syncState.connected && pendingCount > 0;
    final Color color = disconnectedWithPending
        ? _pendingYellow
        : AppColors.success;
    final IconData icon = disconnectedWithPending
        ? Icons.cloud_off_rounded
        : Icons.cloud_done_rounded;
    final String text = disconnectedWithPending
        ? context.trp('{count} داواکاری چاوەڕێی پەیوەندین', {
            'count': '$pendingCount',
          })
        : context.tr('سینک چالاکە');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      ('all', context.tr('هەموو')),
      ('arrived', context.tr('گەیشت')),
      ('not_arrived', context.tr('نەگەیشت')),
      ('printed', context.tr('پرێنت')),
      ('retry_print', context.tr('دوبارە پرێنت')),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: filters.map((entry) {
          final (value, label) = entry;
          final selected = _selectedFilter == value;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => setState(() => _selectedFilter = value),
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
            ),
            showCheckmark: false,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLegendRow(
    int waiting,
    int arrived,
    int retryPrints,
    int printed,
    int rejected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildLegendChip(_pendingYellow, context.tr('نەگەیشت'), waiting),
          _buildLegendChip(AppColors.blue, context.tr('گەیشت'), arrived),
          _buildLegendChip(
            _pendingYellow,
            context.tr('دوبارە پرێنت'),
            retryPrints,
          ),
          _buildLegendChip(AppColors.success, context.tr('پرێنت'), printed),
          if (rejected > 0)
            _buildLegendChip(AppColors.danger, context.tr('ڕەفز'), rejected),
        ],
      ),
    );
  }

  Widget _buildLegendChip(Color color, String label, int count) {
    return Container(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.trp('{label} ({count})', {
                'label': label,
                'count': '$count',
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    // No Center here: this column is wrapped in a FittedBox at the call site
    // (which already centers and scales it), and a Center inside would try to
    // fill the box, defeating the scale-down.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.mark_email_unread_outlined,
          size: 52,
          color: AppColors.softText.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('هیچ داواکارییەک نەنێردراوە'),
          style: const TextStyle(color: AppColors.softText, fontSize: 15),
        ),
      ],
    );
  }

  Future<void> _retryOrderDelivery(OrderDeliveryModel delivery) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = context.tr('داواکاری دوبارە نێردرا');
    await ref.read(waiterProvider.notifier).resendOrder(delivery.tableId);
    if (!mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _retryPrintDelivery(OrderDeliveryModel delivery) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = context.tr('دوبارە پرێنت کردن');
    await ref.read(waiterProvider.notifier).resendOrder(delivery.tableId);
    if (!mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildDesktopSliverGrid(List<OrderDeliveryModel> deliveries,
      double totalWidth) {
    // Any iPad (740+ pt, matching Responsive.desktopBreakpoint) renders the
    // same laptop card layout. 600-739 keeps the older, tighter delivery list.
    final maxCrossAxisExtent = totalWidth >= Responsive.desktopBreakpoint
        ? 340.0
        : totalWidth >= 600
        ? 300.0
        : 260.0;
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: totalWidth >= Responsive.desktopBreakpoint ? 146 : 156,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildDeliveryCard(deliveries[index]),
        childCount: deliveries.length,
      ),
    );
  }

  Widget _buildMobileSliverList(List<OrderDeliveryModel> deliveries) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          // The last card needs no trailing gap: the scroll view's own
          // padding is enough, and skipping it keeps the list bottom flush.
          padding: EdgeInsets.only(
            bottom: index == deliveries.length - 1 ? 0 : 10,
          ),
          child: _buildDeliveryCard(deliveries[index]),
        ),
        childCount: deliveries.length,
      ),
    );
  }

  Widget _buildDeliveryCard(OrderDeliveryModel d) {
    final (Color color, String text, IconData icon) = _deliveryStatus(d);
    // Shared retry button: a 28px-tall tap target is beneath the 44px floor
    // this app uses everywhere else, and the card has the room for it.
    Widget retryButton() => TextButton.icon(
          onPressed: () => d.isRetryPrint
              ? _retryPrintDelivery(d)
              : _retryOrderDelivery(d),
          icon: const Icon(Icons.restart_alt_rounded, size: 15),
          label: Text(
            d.isRetryPrint
                ? context.tr('دوبارە پرێنت')
                : context.tr('دوبارە ناردن'),
          ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusMedium,
                      ),
                    ),
                    child: Center(child: Icon(icon, color: color, size: 22)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.trp('مێزی {tableNumber}', {
                            'tableNumber': '${d.tableId}',
                          }),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.darkText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${context.tr('نێردراوە')} - ${_formatSentTime(d.sentAt)}',
                          style: const TextStyle(
                            color: AppColors.softText,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                spacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusSmall,
                      ),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  if (d.canRetry)
                    retryButton(),
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              ),
              child: Center(child: Icon(icon, color: color, size: 24)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.trp('مێزی {tableNumber}', {
                      'tableNumber': '${d.tableId}',
                    }),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.darkText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${context.tr('نێردراوە')} - ${_formatSentTime(d.sentAt)}',
                    style: const TextStyle(
                      color: AppColors.softText,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusSmall,
                      ),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (d.canRetry) ...[
                    const SizedBox(height: 6),
                    retryButton(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TablePage(tableNumber: d.tableId),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
          ),
          child: content,
        ),
      ),
    );
  }

  (Color, String, IconData) _deliveryStatus(OrderDeliveryModel d) {
    if (d.isPrinted) {
      return (
        AppColors.success,
        context.tr('پرێنت'),
        Icons.check_circle_rounded,
      );
    }
    if (d.isRetryPrint) {
      return (
        _pendingYellow,
        context.tr('دوبارە پرێنت'),
        Icons.print_disabled_rounded,
      );
    }
    if (d.rejected) {
      return (AppColors.danger, context.tr('ڕەفز'), Icons.cancel_rounded);
    }
    if (d.hasArrived) {
      return (AppColors.blue, context.tr('گەیشت'), Icons.outbox_rounded);
    }
    return (_pendingYellow, context.tr('نەگەیشت'), Icons.schedule_rounded);
  }

  String _formatSentTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
