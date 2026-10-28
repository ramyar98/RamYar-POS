import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../database/local_db.dart';
import '../../models/order_delivery_model.dart';
import '../../models/order_model.dart';
import '../../models/printer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/waiter_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/print_router.dart';
import '../../services/sync_provider.dart';
import 'table_page.dart';

/// ڕەنگی زەرد بۆ داواکارییە چاوەڕێکەرەکان (Pending Connection)
const Color _pendingYellow = Color(0xFFE6A700);

/// پەڕەی تەواو بۆ دۆخی ناردنی داواکارییەکان (Order Delivery).
///
/// ئەم پەڕەیە بە ئاستی ئایتیم کار دەکات، نەک تەنها بە ئاستی مێز:
///  - نەگەیشت: ئایا ئەم خواردنە هێشتا نەگەیشتووەتە سیستەمی کاشێر؟
///  - دووبارە پرێنت: ئایا تیکەتی ئەم خواردنە لە هەموو پرێنتەرە
///    تەرخانکراوەکانی (چێشتخانە، باڕ، پرێنتی کاشێر، ژووری نێرگیلە) دەرچووە؟
///    هەر ئایتیمێک پرێنت نەکرابێت لە بەشی «دوبارە پرێنت» دەردەکەوێت.
///
/// فلتەرەکان تەنها سێ بەشن: «هەموو» (هەموو ئایتیمەکان)، «نەگەیشت» (ئەوەی
/// هێشتا گەیشتووە نییە) و «دوبارە پرێنت» (ئەوەی تیکەتی بەردەستە). بەشەکانی
/// «گەیشت» و «پرێنت» لابردەن: ئەوان دۆخەکان بە ڕەنگی خۆیان لەسەر کارتەکان
/// دیارە و فلتەرێکی تایبەتیان پێویست نییە.
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
      if (mounted) _refresh();
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

  // ==================== Item-level filters ====================

  /// ئایا ئەم داواکارییە لانیکەم یەک ئایتمی هەیە کە لەگەڵ فلتەرەکە دەگونجێت؟
  ///
  /// کاتێک ئایتیمەکان نەخوێنرێنەوە (ڕیزی کۆن)، دۆخی ئاستی مێز وەک پشتیوان
  /// بەکار دەهێنرێت تا ڕەفتاری پێشوو نەفەوتێت.
  bool _matchesFilter(OrderDeliveryModel d, String filter) {
    if (filter == 'all') return true;
    if (d.items.isEmpty) {
      switch (filter) {
        case 'not_arrived':
          return d.isNotArrived;
        case 'retry_print':
          return d.isRetryPrint;
      }
      return true;
    }
    switch (filter) {
      case 'not_arrived':
        return d.items.any((i) => !i.arrived);
      case 'retry_print':
        return d.items.any((i) => i.needsPrint);
    }
    return true;
  }

  /// بەشدارییەکی یەک داواکاری بۆ ژماردنی فلتەرەکە (بە ژمارەی ئایتیم).
  int _dishContribution(OrderDeliveryModel d, String filter) {
    switch (filter) {
      case 'not_arrived':
        return d.items.where((i) => !i.arrived).length;
      case 'retry_print':
        return d.unprintedItems.length;
      default:
        return d.itemTotal;
    }
  }

  int _countFor(List<OrderDeliveryModel> deliveries, String filter) {
    var count = 0;
    for (final d in deliveries) {
      if (d.items.isEmpty) {
        if (_matchesFilter(d, filter)) count++;
        continue;
      }
      count += _dishContribution(d, filter);
    }
    return count;
  }

  /// ئایتیمەکانی ناو کارتێک کە لەگەڵ فلتەری هەڵبژێردراو دەگونجێن.
  List<DeliveryItemStatus> _visibleItems(OrderDeliveryModel d) {
    if (d.items.isEmpty) return const [];
    switch (_selectedFilter) {
      case 'not_arrived':
        return d.items.where((i) => !i.arrived).toList();
      case 'retry_print':
        return d.unprintedItems;
      default:
        return d.items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncConnectionProvider);
    final deliveriesAsync = ref.watch(deliveryStatusProvider);
    final pendingAsync = ref.watch(pendingSyncCountProvider);
    final deliveries =
        deliveriesAsync.asData?.value ?? const <OrderDeliveryModel>[];
    final pendingCount = pendingAsync.asData?.value ?? 0;

    final visibleDeliveries = deliveries
        .where((d) => _matchesFilter(d, _selectedFilter))
        .toList();

    final rejected = deliveries.where((d) => d.rejected).length;

    // A failed read (or the very first frame) must not read as "nothing was
    // sent": a captain who believes the list is simply empty re-sends food that
    // already went to the kitchen.
    if (deliveriesAsync.hasError) {
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
        body: Center(
          child: Text(
            context.tr('هەڵەیەک ڕوویدا لە خوێندنەوە'),
            style: const TextStyle(color: AppColors.softText),
          ),
        ),
      );
    }
    if (deliveriesAsync.isLoading && deliveries.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
              // 600, the app-wide phone/tablet breakpoint.
              final isDesktop = constraints.maxWidth >= 600;
              // One scroll region for the whole body. As slivers, the header,
              // the legend and the cards share one viewport and simply scroll
              // when they do not fit - no RenderFlex overflow on short screens.
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildConnectionBanner(syncState, pendingCount),
                  ),
                  SliverToBoxAdapter(
                    child: _buildFilterBar(deliveries),
                  ),
                  SliverToBoxAdapter(
                    child: _buildLegendRow(rejected),
                  ),
                  if (visibleDeliveries.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildEmptyState(hasAnyOrder: deliveries.isNotEmpty),
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

  Widget _buildFilterBar(List<OrderDeliveryModel> deliveries) {
    // Only three buckets, because those are the three questions the captain
    // actually asks: what is still on its way, and what still owes a ticket.
    final filters = [
      ('all', context.tr('هەموو')),
      ('not_arrived', context.tr('نەگەیشت')),
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
          final count = _countFor(deliveries, value);
          return ChoiceChip(
            label: Text(
              context.trp('{label} ({count})', {
                'label': label,
                'count': '$count',
              }),
            ),
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

  /// A compact colour key for the card status pills. Counts deliberately live
  /// on the filter chips only, so the two rows never repeat the same numbers.
  Widget _buildLegendRow(int rejected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildLegendChip(_pendingYellow, context.tr('نەگەیشت')),
          _buildLegendChip(_pendingYellow, context.tr('دوبارە پرێنت')),
          if (rejected > 0)
            _buildLegendChip(AppColors.danger, context.tr('ڕەفز')),
        ],
      ),
    );
  }

  Widget _buildLegendChip(Color color, String label) {
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
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
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

  Widget _buildEmptyState({required bool hasAnyOrder}) {
    // No Center here: this column is wrapped in a FittedBox at the call site
    // (which already centers and scales it).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          hasAnyOrder
              ? Icons.filter_alt_off_outlined
              : Icons.mark_email_unread_outlined,
          size: 52,
          color: AppColors.softText.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 12),
        Text(
          hasAnyOrder
              ? context.tr('هیچ ئایتیمێک نەدۆزرایەوە')
              : context.tr('هیچ داواکارییەک نەنێردراوە'),
          style: const TextStyle(color: AppColors.softText, fontSize: 15),
        ),
      ],
    );
  }

  // ==================== Actions ====================

  /// دوبارە ناردنی داواکارییەکی نەگەیشتوو (ئاستی مێز).
  Future<void> _retryOrderDelivery(OrderDeliveryModel delivery) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final okMsg = context.tr('داواکاری دوبارە نێردرا');
    final errMsg = context.tr('هەڵە لە دووبارە ناردن');
    try {
      await ref.read(waiterProvider.notifier).resendOrder(delivery.tableId);
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(errMsg)));
    }
  }

  /// دوبارە پرێنتنتی تەنها ئەو ئایتیمانەی تیکەتیان کەمە.
  ///
  /// پرێنتەرەکان بەم ئایتیمە تەرخانکراوانە ڕێک دەخرێنەوە و تەنها ئەوان
  /// دەنێردرێن - هەر ئایتیمێک پرێنت نەبێت لە «دوبارە پرێنت» دەردەکەوێت.
  Future<void> _reprintItems(
    OrderDeliveryModel d,
    List<DeliveryItemStatus> targets,
  ) async {
    if (targets.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final okMsg = context.tr('دوبارە پرێنت');
    final errMsg = context.tr('هەڵە لە پرێنت');
    final user = ref.read(authProvider);
    final router = PrintRouter(ref.read(printerProvider));
    final items = targets
        .map(
          (t) => OrderItem(
            id: t.id,
            name: t.name,
            price: 0,
            quantity: t.quantity,
            category: t.category,
          ),
        )
        .toList();
    final jobs = router.routeOrder(
      items,
      waiterName: user?.name ?? '',
      tableNumber: d.tableId,
    );
    if (jobs.isEmpty) return;
    try {
      await dispatchOrderPrintJobs(
        ref.read(localDbProvider),
        jobs,
        tableId: d.tableId,
      );
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(errMsg)));
    }
    if (mounted) ref.invalidate(deliveryStatusProvider);
  }

  /// یەک دوگمە: ئەگەر ئایتیمی پرێنت نەکراو هەبوو، ئەوان دەنێردرێن؛
  /// ئەگەر نا، داواکارییەکە بە تەواوی دوبارە دەنێردرێت.
  Future<void> _handleRetry(OrderDeliveryModel d) async {
    if (d.hasItemState && d.unprintedItems.isNotEmpty) {
      await _reprintItems(d, d.unprintedItems);
    } else if (d.isRetryPrint && d.items.isNotEmpty) {
      await _reprintItems(d, d.items);
    } else {
      await _retryOrderDelivery(d);
    }
  }

  // ==================== Cards ====================

  Widget _buildDesktopSliverGrid(
    List<OrderDeliveryModel> deliveries,
    double totalWidth,
  ) {
    // Any iPad (740+ pt, matching Responsive.desktopBreakpoint) renders the
    // wider card layout. 600-739 keeps the tighter one.
    final maxCrossAxisExtent = totalWidth >= Responsive.desktopBreakpoint
        ? 360.0
        : totalWidth >= 600
        ? 320.0
        : 280.0;
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: totalWidth >= Responsive.desktopBreakpoint ? 250 : 230,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildDeliveryCard(
          deliveries[index],
          bounded: true,
        ),
        childCount: deliveries.length,
      ),
    );
  }

  Widget _buildMobileSliverList(List<OrderDeliveryModel> deliveries) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: EdgeInsets.only(
            bottom: index == deliveries.length - 1 ? 0 : 10,
          ),
          child: _buildDeliveryCard(deliveries[index]),
        ),
        childCount: deliveries.length,
      ),
    );
  }

  Widget _buildDeliveryCard(OrderDeliveryModel d, {bool bounded = false}) {
    final (Color color, String text, IconData icon) = _cardStatus(d);
    final items = _visibleItems(d);

    Widget retryButton() => TextButton.icon(
          onPressed: () => _handleRetry(d),
          icon: const Icon(Icons.restart_alt_rounded, size: 16),
          label: Text(
            d.unprintedItems.isNotEmpty
                ? context.tr('دوبارە پرێنت')
                : context.tr('دوبارە ناردن'),
          ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        );

    final header = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          child: Center(child: Icon(icon, color: color, size: 21)),
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
              const SizedBox(height: 2),
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
        const SizedBox(width: 6),
        _statusPill(color, text),
      ],
    );

    final children = <Widget>[header];

    if (items.isNotEmpty) {
      final rows = <Widget>[
        const Divider(height: 16),
        if (d.itemTotal > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _itemSummary(d),
          ),
        for (final it in items) _buildItemRow(d, it),
      ];
      final itemColumn = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
      children.add(
        bounded
            ? Expanded(child: SingleChildScrollView(child: itemColumn))
            : itemColumn,
      );
    } else if (bounded) {
      children.add(const Spacer());
    }

    if (d.canRetry || d.unprintedItems.isNotEmpty) {
      children.add(
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: retryButton(),
        ),
      );
    }

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _statusPill(Color color, String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
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
    );
  }

  Widget _itemSummary(OrderDeliveryModel d) {
    const style = TextStyle(fontSize: 11, color: AppColors.softText);
    return Row(
      children: [
        const Icon(Icons.cloud_done_rounded, size: 13, color: AppColors.blue),
        const SizedBox(width: 3),
        Text('${d.arrivedItemCount}/${d.itemTotal}', style: style),
        const SizedBox(width: 10),
        const Icon(Icons.print_rounded, size: 13, color: AppColors.success),
        const SizedBox(width: 3),
        Text('${d.printedItemCount}/${d.itemTotal}', style: style),
      ],
    );
  }

  Widget _buildItemRow(OrderDeliveryModel d, DeliveryItemStatus it) {
    final label = _printerLabelForItem(it);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${it.name} ×${it.quantity}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.darkText),
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(child: _itemPrinterChip(label)),
          ],
          const SizedBox(width: 8),
          _itemStatusIcons(it),
          if (it.needsPrint)
            // 40px target: 30px was below the floor this app uses everywhere
            // else, and this is the replay button a captain taps one-handed.
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 18,
                tooltip: context.tr('دوبارە پرێنت'),
                onPressed: () => _reprintItems(d, [it]),
                icon: const Icon(
                  Icons.replay_rounded,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemPrinterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.softText.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: AppColors.softText),
      ),
    );
  }

  Widget _itemStatusIcons(DeliveryItemStatus it) {
    final arrivalColor = it.arrived ? AppColors.blue : _pendingYellow;
    final printColor = it.printed ? AppColors.success : _pendingYellow;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: it.arrived ? context.tr('گەیشت') : context.tr('نەگەیشت'),
          child: Icon(
            it.arrived ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            size: 15,
            color: arrivalColor,
          ),
        ),
        const SizedBox(width: 5),
        Tooltip(
          message:
              it.printed ? context.tr('پرێنت') : context.tr('پرێنت نەکراوە'),
          child: Icon(
            it.printed ? Icons.print_rounded : Icons.print_disabled_rounded,
            size: 15,
            color: printColor,
          ),
        ),
      ],
    );
  }

  (Color, String, IconData) _cardStatus(OrderDeliveryModel d) {
    switch (d.itemStatusLabel) {
      case 'rejected':
        return (AppColors.danger, context.tr('ڕەفز'), Icons.cancel_rounded);
      case 'printed':
        return (
          AppColors.success,
          context.tr('پرێنت'),
          Icons.check_circle_rounded,
        );
      case 'print_failed':
        return (
          _pendingYellow,
          context.tr('دوبارە پرێنت'),
          Icons.print_disabled_rounded,
        );
      case 'arrived':
        return (AppColors.blue, context.tr('گەیشت'), Icons.check_rounded);
      default:
        return (_pendingYellow, context.tr('نەگەیشت'), Icons.schedule_rounded);
    }
  }

  String _formatSentTime(String iso) {
    final dt = DateTime.tryParse(iso);
    // Never print a raw ISO string at the user: an unparseable timestamp used
    // to be echoed verbatim onto the card.
    if (dt == null) return '-';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  /// ناوی پرێنتەر(ەکان) بۆ یەک ئایتم.
  ///
  /// ئەگەر پرێنتەرێک شکستی هێنابێت، ئەو پرێنتەرانە پیشان دەدرێن کە هێشتا
  /// تیکەتیان دەوێت؛ ئەگەر نا، پرێنتەرە تەرخانکراوەکان لە ڕێکخستنی خۆجێیی
  /// ئەم ئامێرەوە دەخوێنرێنەوە (وەک ئەوەی ئەم ئامێرە خۆی دەیچاپەڕێژێت).
  String _printerLabelForItem(DeliveryItemStatus it) {
    final failed = it.failedPrinterTypes;
    if (failed.isNotEmpty) {
      return failed.map(_printerLabel).join(' · ');
    }
    final router = PrintRouter(ref.read(printerProvider));
    final types = router.resolvePrintersForItem(
      OrderItem(id: it.id, name: it.name, price: 0, category: it.category),
    );
    if (types.isEmpty) return '';
    return types.map((t) => _printerLabel(t.index)).join(' · ');
  }

  String _printerLabel(int typeIndex) {
    if (typeIndex == PrinterType.kitchen.index) return context.tr('چێشتخانە');
    if (typeIndex == PrinterType.bar.index) return context.tr('باڕ');
    if (typeIndex == PrinterType.cashier.index) return context.tr('پرێنتی کاشێر');
    if (typeIndex == PrinterType.hookah.index) return context.tr('ژووری نێرگیلە');
    return context.tr('چێشتخانە');
  }
}
