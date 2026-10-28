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
import 'cashier_unified_table_page.dart';

/// ڕەنگی زەرد بۆ داواکارییە چاوەڕێکەرەکان (Pending Connection)
const Color _pendingYellow = Color(0xFFE6A700);

/// دۆخی ناردنی داواکاری - لە ڕوانگەی کاشێرەوە.
///
/// وەیتەر پەڕەی خۆی هەیە کە لە ڕیزی `order_delivery` دەخوێنێتەوە، بەڵام ئەو
/// ڕیزانە تەنها لەسەر ئەو ئامێرە دروست دەبن کە داواکارییەکەی ناردووە. کاشێر
/// هەمان ئەو ڕیزانە نابینێت، بۆیە ئەم پەڕەیە هەمان پرسیار لەسەر ئەو داتایە
/// وەڵام دەداتەوە کە کاشێر هەیەتی: مێزە کراوەکان و خواردنەکانیان.
///
///  - «نەگەیشت»: ئەو خواردنانەی هێشتا نەگەیشتوونەتە ئەم ئامێرە.
///  - «دوبارە پرێنت»: ئەو خواردنانەی تیکەتیان لە هەموو پرێنتەرە
///    تەرخانکراوەکان دەرنەچووە.
///
/// ئەمە پێویستە چونکە کاشێر دەتوانێت پێش هاتنی کاپتن خواردن بۆ مێز زیاد
/// بکات؛ ئەگەر ئەو خواردنە نەگات یان پرێنت نەکرێت، دەبێت لێرەوە بزانێت.
class CashierOrderDeliveryPage extends ConsumerStatefulWidget {
  const CashierOrderDeliveryPage({super.key});

  @override
  ConsumerState<CashierOrderDeliveryPage> createState() =>
      _CashierOrderDeliveryPageState();
}

class _CashierOrderDeliveryPageState
    extends ConsumerState<CashierOrderDeliveryPage> {
  Timer? _refreshTimer;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    // Printing stamps `order_items` without bumping the order revision, so the
    // list is polled as well as watched: a ticket that comes out must clear its
    // dish from «دوبارە پرێنت» without the cashier leaving and re-entering.
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
    ref.invalidate(tillDeliveryStatusProvider);
  }

  // ==================== Item-level filters ====================

  bool _matchesFilter(TillDeliveryModel d, String filter) {
    if (filter == 'all') return true;
    switch (filter) {
      case 'not_arrived':
        return d.items.any((i) => !i.arrived);
      case 'retry_print':
        return d.items.any((i) => i.needsPrint);
    }
    return true;
  }

  int _dishContribution(TillDeliveryModel d, String filter) {
    switch (filter) {
      case 'not_arrived':
        return d.items.where((i) => !i.arrived).length;
      case 'retry_print':
        return d.unprintedItems.length;
      default:
        return d.itemTotal;
    }
  }

  int _countFor(List<TillDeliveryModel> deliveries, String filter) {
    var count = 0;
    for (final d in deliveries) {
      count += _dishContribution(d, filter);
    }
    return count;
  }

  /// ئایتیمەکانی ناو کارتێک کە لەگەڵ فلتەری هەڵبژێردراو دەگونجێن.
  List<DeliveryItemStatus> _visibleItems(TillDeliveryModel d) {
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
    final deliveriesAsync = ref.watch(tillDeliveryStatusProvider);
    final deliveries = deliveriesAsync.asData?.value ?? const <TillDeliveryModel>[];

    // A failed read must never read as "nothing was sent": the cashier would
    // add the same dishes again on top of an order that is already there.
    if (deliveriesAsync.hasError) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _appBar(context.tr('دۆخی ناردنی داواکاری')),
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

    final visibleDeliveries = deliveries
        .where((d) => _matchesFilter(d, _selectedFilter))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _appBar(context.tr('دۆخی ناردنی داواکاری')),
      body: SafeArea(
        child: Padding(
          padding: Responsive.screenPadding(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 600, the app-wide phone/tablet breakpoint.
              final isDesktop = constraints.maxWidth >= 600;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildFilterBar(deliveries)),
                  SliverToBoxAdapter(child: _buildLegendRow()),
                  if (visibleDeliveries.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildEmptyState(
                          hasAnyOrder: deliveries.isNotEmpty,
                        ),
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

  AppBar _appBar(String title) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      title: Text(
        title,
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
    );
  }

  Widget _buildFilterBar(List<TillDeliveryModel> deliveries) {
    // The same three questions the captain answers, because the cashier is
    // checking the same two things: what is still on its way, and what still
    // owes a ticket. «گەیشت» and «پرێنت» are states the cards already show.
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

  /// A compact colour key for the card status pills.
  Widget _buildLegendRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildLegendChip(_pendingYellow, context.tr('نەگەیشت')),
          _buildLegendChip(_pendingYellow, context.tr('دوبارە پرێنت')),
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

  /// Opens the table so the cashier can add food, print the bill or settle it -
  /// the three things they came to this page to check for.
  Future<void> _openTable(TillDeliveryModel d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CashierUnifiedTablePage(tableNumber: d.tableId),
      ),
    );
    if (mounted) _refresh();
  }

  /// دوبارە پرێنتنتی تەنها ئەو ئایتیمانەی تیکەتیان کەمە.
  Future<void> _reprintItems(
    TillDeliveryModel d,
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
    if (mounted) _refresh();
  }

  // ==================== Cards ====================

  Widget _buildDesktopSliverGrid(
    List<TillDeliveryModel> deliveries,
    double totalWidth,
  ) {
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
        (context, index) =>
            _buildDeliveryCard(deliveries[index], bounded: true),
        childCount: deliveries.length,
      ),
    );
  }

  Widget _buildMobileSliverList(List<TillDeliveryModel> deliveries) {
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

  Widget _buildDeliveryCard(TillDeliveryModel d, {bool bounded = false}) {
    final (Color color, String text, IconData icon) = _cardStatus(d);
    final items = _visibleItems(d);
    final tableLabel = d.tableName.trim().isNotEmpty
        ? d.tableName
        : context.trp('مێزی {tableNumber}', {'tableNumber': '${d.tableId}'});

    Widget retryButton() => TextButton.icon(
          onPressed: () => _reprintItems(d, d.unprintedItems),
          icon: const Icon(Icons.restart_alt_rounded, size: 16),
          label: Text(context.tr('دوبارە پرێنت')),
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
                tableLabel,
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
                [
                  '${context.tr('نێردراوە')} - ${_formatSentTime(d.sentAt)}',
                  if (d.waiterName.trim().isNotEmpty) d.waiterName,
                ].join('  •  '),
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

    if (d.unprintedItems.isNotEmpty) {
      // In every filter this button acts on exactly the dishes that still owe a
      // ticket, so the cashier can clear the whole table in one tap.
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
        onTap: () => _openTable(d),
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

  Widget _itemSummary(TillDeliveryModel d) {
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

  Widget _buildItemRow(TillDeliveryModel d, DeliveryItemStatus it) {
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

  (Color, String, IconData) _cardStatus(TillDeliveryModel d) {
    switch (d.statusLabel) {
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
    if (dt == null) return '-';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  /// ناوی پرێنتەر(ەکان) بۆ یەک ئایتم.
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
