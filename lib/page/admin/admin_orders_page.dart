import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/settlement_model.dart';
import '../../models/order_model.dart';
import '../../models/printer_model.dart';
import '../../providers/printer_provider.dart';

import '../../services/print_router.dart';
import '../../widgets/print_preview_dialog.dart';

class AdminOrdersPage extends ConsumerStatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  String _dateFilter = 'all';
  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customTo = DateTime.now();
  final _searchCtrl = TextEditingController();
  List<SettledOrder> _allOrders = [];
  List<SettledOrder> _filteredOrders = [];
  Map<int, String> _cashierNames = {};
  bool _loading = true;

  late final LocalDatabase _db;
  late final VoidCallback _revisionListener;

  @override
  void initState() {
    super.initState();
    _db = ref.read(localDbProvider);
    _revisionListener = () {
      if (mounted) {
        unawaited(_loadOrders());
      }
    };
    // Live updates: when any captain/cashier settles an order, records shift
    // totals or changes an order row, the admin sees it immediately without
    // pulling to refresh. Covers shiftsRevision + orderRevision + tables.
    _db.orderRevision.addListener(_revisionListener);
    _db.shiftsRevision.addListener(_revisionListener);
    unawaited(_loadOrders());
  }

  @override
  void dispose() {
    _db.orderRevision.removeListener(_revisionListener);
    _db.shiftsRevision.removeListener(_revisionListener);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final db = ref.read(localDbProvider);
    List<SettledOrder> orders;

    switch (_dateFilter) {
      case 'today':
        final today = DateTime.now();
        final start = DateTime(
          today.year,
          today.month,
          today.day,
        ).toIso8601String();
        final end = today.toIso8601String();
        orders = await db.getSettledOrdersByDateRange(start, end);
      case 'week':
        final now = DateTime.now();
        final start = now.subtract(Duration(days: now.weekday - 1));
        final from = DateTime(
          start.year,
          start.month,
          start.day,
        ).toIso8601String();
        final to = now.toIso8601String();
        orders = await db.getSettledOrdersByDateRange(from, to);
      case 'month':
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, 1).toIso8601String();
        final to = now.toIso8601String();
        orders = await db.getSettledOrdersByDateRange(start, to);
      case 'custom':
        final from = DateTime(
          _customFrom.year,
          _customFrom.month,
          _customFrom.day,
        ).toIso8601String();
        final to = DateTime(
          _customTo.year,
          _customTo.month,
          _customTo.day,
          23,
          59,
          59,
        ).toIso8601String();
        orders = await db.getSettledOrdersByDateRange(from, to);
      default:
        orders = await db.getAllSettledOrders();
    }

    final names = <int, String>{};
    for (final o in orders) {
      if (!names.containsKey(o.settledBy)) {
        final user = await db.getUserById(o.settledBy);
        names[o.settledBy] = user?.name ?? 'ID: ${o.settledBy}';
      }
    }

    if (mounted) {
      setState(() {
        _allOrders = orders;
        _cashierNames = names;
        _applySearch();
        _loading = false;
      });
    }
  }

  void _applySearch() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredOrders = List.from(_allOrders);
    } else {
      _filteredOrders = _allOrders.where((o) {
        final cashierName = _cashierNames[o.settledBy]?.toLowerCase() ?? '';
        return o.tableName.toLowerCase().contains(query) ||
            cashierName.contains(query);
      }).toList();
    }
  }

  String _fmtTime(String iso) {
    if (iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showOrderDetail(SettledOrder order) async {
    final db = ref.read(localDbProvider);
    final items = await db.getSettledOrderItems(order.id);
    final cashierName =
        _cashierNames[order.settledBy] ?? 'ID: ${order.settledBy}';
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.trp('مێزی {tableName}', {'tableName': order.tableName}),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 14,
                    color: AppColors.softText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cashierName,
                    style: TextStyle(color: AppColors.softText, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${context.tr('کات')}: ${_fmtDate(order.settledAt)} ${_fmtTime(order.settledAt)}',
                style: TextStyle(color: AppColors.softText, fontSize: 13),
              ),
              const Divider(),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'x${item.quantity} ${item.itemName}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '${context.tr('د.ع')} ${money((item.itemPrice * item.quantity))}',
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Text(
                    context.tr('کۆی گشتی'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${context.tr('د.ع')} ${money(order.totalAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (order.discountPercent > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      context.tr('داشکاندن'),
                      style: TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      '${order.discountPercent}% (${context.tr('د.ع')} ${money(order.discountAmount)})',
                      style: TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              if (!context.mounted) return;
              final printerState = ref.read(printerProvider);
              final cashierPrinter = printerState.printers
                  .where((p) => p.printerType == PrinterType.cashier)
                  .firstOrNull;
              final orderItems = items
                  .map(
                    (i) => OrderItem(
                      id: i.id.toString(),
                      name: i.itemName,
                      price: i.itemPrice,
                      quantity: i.quantity,
                      category: i.category,
                    ),
                  )
                  .toList();
              final design = await ref.read(localDbProvider).getReceiptDesign();
              if (!mounted) return;
              final confirmed = await PrintPreview.showReceiptPreview(
                context,
                tableNumber: order.tableId,
                guestCount: 1,
                items: orderItems,
                subtotal: order.totalAmount + order.discountAmount,
                discountPercent: order.discountPercent,
                discountAmount: order.discountAmount,
                total: order.totalAmount,
                waiterName: '',
                cashierName: cashierName,
                printerName: cashierPrinter?.name ?? '',
                design: design,
              );
              if (confirmed && context.mounted && cashierPrinter != null) {
                await PrintRouter.dispatchReceipt(
                  tableNumber: order.tableId,
                  guestCount: 1,
                  items: orderItems,
                  subtotal: order.totalAmount + order.discountAmount,
                  discountPercent: order.discountPercent,
                  discountAmount: order.discountAmount,
                  total: order.totalAmount,
                  printer: cashierPrinter,
                  waiterName: '',
                  cashierName: cashierName,
                  design: design,
                );
              }
            },
            icon: const Icon(Icons.print_rounded),
            label: Text(context.tr('چاپکردنەوەی حیساب')),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('داخستن')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final fromPicker = await showDatePicker(
      context: context,
      initialDate: _customFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (fromPicker == null || !mounted) return;
    final toPicker = await showDatePicker(
      context: context,
      initialDate: _customTo,
      firstDate: fromPicker,
      lastDate: DateTime.now(),
    );
    if (toPicker == null || !mounted) return;
    setState(() {
      _customFrom = fromPicker;
      _customTo = toPicker;
      _dateFilter = 'custom';
    });
    _loadOrders();
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
          context.tr('مێژووی داواکارییەکان'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: AppConstants.paddingMedium,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', context.tr('هەموو')),
                  const SizedBox(width: 6),
                  _filterChip('today', context.tr('ئەمڕۆ')),
                  const SizedBox(width: 6),
                  _filterChip('week', context.tr('ئەم هەفتەیە')),
                  const SizedBox(width: 6),
                  _filterChip('month', context.tr('ئەم مانگە')),
                  const SizedBox(width: 6),
                  _filterChip('custom', context.tr('تایبەت')),
                ],
              ),
            ),
          ),
          if (_dateFilter == 'custom')
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: 8,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _pickCustomRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.date_range_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_fmtDate(_customFrom.toIso8601String())} - ${_fmtDate(_customTo.toIso8601String())}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(
              AppConstants.paddingMedium,
              0,
              AppConstants.paddingMedium,
              10,
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(_applySearch),
              decoration: InputDecoration(
                hintText: context.tr('گەڕان بە ناوی مێز یان کاشێر'),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.softText,
                ),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 56,
                          color: AppColors.softText,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('هیچ داواکاریەک نەدۆزرایەوە'),
                          style: TextStyle(color: AppColors.softText),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppConstants.paddingMedium),
                    itemCount: _filteredOrders.length,
                    itemBuilder: (context, index) {
                      final order = _filteredOrders[index];
                      final cashierName = _cashierNames[order.settledBy] ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showOrderDetail(order),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${order.tableId}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        order.tableName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      if (cashierName.isNotEmpty)
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_rounded,
                                              size: 12,
                                              color: AppColors.softText,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              cashierName,
                                              style: TextStyle(
                                                color: AppColors.softText,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      Text(
                                        '${_fmtDate(order.settledAt)} ${_fmtTime(order.settledAt)}',
                                        style: TextStyle(
                                          color: AppColors.softText,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${context.tr('د.ع')} ${money(order.totalAmount)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.softText,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _dateFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.darkText,
        ),
      ),
      selected: selected,
      onSelected: (v) {
        if (value == 'custom') {
          _pickCustomRange();
        } else {
          setState(() => _dateFilter = value);
          _loadOrders();
        }
      },
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
    );
  }
}
