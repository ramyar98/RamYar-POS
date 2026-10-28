import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../core/table_status_visuals.dart';
import '../../database/local_db.dart';
import '../../models/debt_model.dart';
import '../../models/order_model.dart';
import '../../models/printer_model.dart';
import '../../models/settlement_model.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/waiter_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/esc_pos_builder.dart';
import '../../services/menu_helper.dart';
import '../../services/print_router.dart';
import '../../services/sync_provider.dart';
import '../../services/table_lock_controller.dart';
import '../../services/table_note_policy.dart';
import '../../widgets/cash_calculator_dialog.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/print_preview_dialog.dart';
import '../../widgets/table_note_dialog.dart';
import 'transfer_page.dart';

class CashierUnifiedTablePage extends ConsumerStatefulWidget {
  final int tableNumber;
  final int initialGuestCount;
  final int initialTab;

  /// True when this is a delivery slot rather than a table in the dining room.
  ///
  /// A delivery order is worked exactly like a table - the same food grid, the
  /// same cart, the same bill - so it is the same page. What changes is the
  /// wording and the handful of actions that make no sense on a delivery: a
  /// slot cannot be renamed, and moving a delivery to a dining table is not
  /// something the cashier means by tapping "transfer".
  final bool isDelivery;

  /// What the app bar calls this order, e.g. "تەلەبات 4". A delivery slot's
  /// own name already reads that way, so it is used instead of "مێزی 100104".
  final String? deliveryTitle;

  const CashierUnifiedTablePage({
    super.key,
    required this.tableNumber,
    this.initialGuestCount = 1,
    this.initialTab = 1,
    this.isDelivery = false,
    this.deliveryTitle,
  });

  @override
  ConsumerState<CashierUnifiedTablePage> createState() =>
      _CashierUnifiedTablePageState();
}

/// What the discount box means right now: a percent of the bill, or a fixed
/// Iraqi-dinar amount taken straight off the total.
enum _DiscountMode { percent, amount }

class _CashierUnifiedTablePageState
    extends ConsumerState<CashierUnifiedTablePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late LocalDatabase _db;
  late UserModel? _lockUser;

  String _selectedCategory = 'هەموو';
  final List<OrderItem> _pendingItems = [];
  bool _printEnabled = true;

  /// True while `_sendPendingItems` is writing to the database.
  ///
  /// The send buttons are only gated on `_pendingItems.isEmpty`, which does not
  /// change until the awaited batch write returns - so without this guard a
  /// fast double-tap sends the same dishes twice and duplicates the bill lines.
  bool _sendingPendingItems = false;

  final _discountController = TextEditingController();

  _DiscountMode _discountMode = _DiscountMode.percent;

  int _parseDiscountPercent() {
    return parseAmount(_discountController.text).clamp(0, 100);
  }

  /// Resolve the discount sitting in the box into (percent, dinar amount).
  ///
  /// In percent mode the typed number is a percent and the dinar amount is
  /// derived from the bill. In د.ع mode the typed number IS the dinar amount,
  /// and the percent is only derived so the live bill keeps showing it.
  ({int percent, int amount}) _parseDiscount(double total) {
    final raw = parseAmount(_discountController.text);
    if (raw <= 0) return (percent: 0, amount: 0);
    if (_discountMode == _DiscountMode.amount) {
      final amount = raw > total.toInt() ? total.toInt() : raw;
      final percent = total > 0 ? ((amount / total) * 100).round() : 0;
      return (percent: percent, amount: amount);
    }
    final percent = _parseDiscountPercent();
    return (percent: percent, amount: _calcDiscountAmount(total, percent));
  }

  /// Switches the box between percent and Iraqi-dinar. A value typed for one
  /// unit makes no sense in the other, so switching clears the field - a
  /// leftover "25" must never silently become 25 د.ع (or 25% of the bill).
  void _setDiscountMode(_DiscountMode mode) {
    if (_discountMode == mode) return;
    setState(() {
      _discountMode = mode;
      _discountController.clear();
    });
  }

  /// The "% / د.ع" switch that decides what the discount box means.
  Widget _buildDiscountModeToggle() {
    Widget chip(_DiscountMode mode, String label) {
      final selected = _discountMode == mode;
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => _setDiscountMode(mode),
          // The visible pill stays compact, but the touch area around it is
          // padded out to ~44px: at its old 22px a thumb aiming at "%" or
          // "د.ع" regularly hit the field behind it instead.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : AppColors.darkText,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.borderSide.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(_DiscountMode.percent, '%'),
          chip(_DiscountMode.amount, context.tr('د.ع')),
        ],
      ),
    );
  }

  /// What the cart's button says once there is something in it.
  ///
  /// On a table the order is being *sent* to the kitchen. On a delivery slot the
  /// cashier is the one taking the order down, so there is nobody to send it to
  /// - it is being *recorded*, and a button promising to send it somewhere
  /// would only make the cashier wait for a confirmation that means nothing.
  String get _saveLabel =>
      widget.isDelivery ? context.tr('تۆمارکردن') : context.tr('ناردن');

  /// What a printed ticket should call this order.
  ///
  /// Only a delivery slot needs it, and only because its number is internal.
  /// Everything else keeps printing "مێز: 12" exactly as before.
  String _printLabel(TableModel? table) =>
      widget.isDelivery ? (table?.name ?? widget.deliveryTitle ?? '') : '';

  /// What this table should be called on screen.
  ///
  /// The label the shop gave it, not its number. The headings on this page used
  /// to be built from the number, so a table the cashier had just renamed kept
  /// reading its old "مێزی 1" title right here, while the card on the grid one
  /// screen away - fed from the very same row - already showed the new name.
  /// That gap is what made a rename look like it had not saved. The number is
  /// only the fallback, for a row that has not loaded yet or that carries no
  /// usable label at all.
  String _screenName(TableModel? table) {
    final stored = table?.name.trim() ?? '';
    return stored.isNotEmpty ? stored : _defaultScreenName;
  }

  /// "مێزی N" - what the table is called while its row is still on its way.
  String get _defaultScreenName => context.trp('مێزی {tableNumber}', {
    'tableNumber': widget.tableNumber.toString(),
  });
  int _calcDiscountAmount(double total, int percent) {
    if (percent <= 0) return 0;
    return (total * percent / 100).round();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _db = ref.read(localDbProvider);
    _lockUser = ref.read(authProvider);
    // Opening the table consumes its notification (from the grid or the
    // notification panel) so it no longer stays in the cashier's list.
    unawaited(_db.clearTableNotifications(widget.tableNumber));
    _loadMenu();
    // Live menu updates: when the admin adds/edits/deletes food items (or a
    // synced-in remote change lands), refresh the local menu immediately.
    _db.foodMenuRevision.addListener(_onMenuChanged);
    _acquireTableLock();
  }

  @override
  void dispose() {
    _disposed = true;
    _db.foodMenuRevision.removeListener(_onMenuChanged);
    unawaited(_lock?.release());
    _tabController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _onMenuChanged() {
    if (mounted) _loadMenu();
  }

  TableLockController? _lock;
  bool _disposed = false;

  Future<void> _acquireTableLock() async {
    final user = _lockUser;
    if (user == null) return;
    // `late final` so the controller can refer to itself: losing the claim is
    // its own job to clean up, not the page's.
    late final TableLockController controller;
    controller = TableLockController(
      db: _db,
      tableId: widget.tableNumber,
      userId: user.id,
      userName: user.name,
      role: 'cashier',
      onLost: (reason) {
        // A cashier holds every table there is, so losing the claim here means
        // it was taken over by another device working the same table. There is
        // nothing to warn about - just stop claiming it.
        if (reason == TableLockLoss.takenAway) unawaited(controller.release());
      },
    );
    _lock = controller;
    // Deliberately unconditional: cashiers are never kept out of a table. The
    // hold screen is what asks before this page is ever reached, so arriving
    // here means the table is free (or its captain was thrown off).
    final taken = await controller.acquire(force: true);
    // Opened and closed again before the write landed. The controller cleans
    // up after itself in that case, but holding the reference would leave a
    // disposed page as the one a later callback reaches for.
    if (_disposed) {
      unawaited(controller.release());
      return;
    }
    if (!taken) unawaited(controller.release());
  }

  void _addPendingItem(Map<String, dynamic> item) {
    final user = ref.read(authProvider);
    _pendingItems.add(
      OrderItem(
        id: ref.read(waiterProvider.notifier).generateId(),
        name: item['name'] as String,
        price: (item['price'] as num).toDouble(),
        category: item['category'] as String,
        // Stamped at capture and carried with the order, so every device stores
        // the same order time for this line - the field a later rejection keys on
        // to recognise the dish across devices.
        createdAt: DateTime.now().toIso8601String(),
        waiterName: user?.name ?? '',
        // Who rang the dish in: here, the cashier. The captain's list shows the
        // same label, so a dish the till added is never read as the captain's.
        waiterRole: user?.role.index ?? OrderItem.unknownRole,
      ),
    );
    setState(() {});
  }

  void _incrementPending(int index) {
    final item = _pendingItems[index];
    _pendingItems[index] = item.copyWith(quantity: item.quantity + 1);
    setState(() {});
  }

  void _decrementPending(int index) {
    final item = _pendingItems[index];
    if (item.quantity <= 1) {
      _pendingItems.removeAt(index);
    } else {
      _pendingItems[index] = item.copyWith(quantity: item.quantity - 1);
    }
    setState(() {});
  }

  Future<void> _sendPendingItems() async {
    if (_sendingPendingItems || _pendingItems.isEmpty) return;
    setState(() => _sendingPendingItems = true);
    try {
      final notifier = ref.read(waiterProvider.notifier);
      final user = ref.read(authProvider);
      await notifier.batchSendAndOccupy(
        widget.tableNumber,
        _pendingItems,
        guestCount: widget.initialGuestCount,
        waiterId: user?.id.toString() ?? '',
      );
      if (!mounted) return;
      if (_printEnabled) {
        final printerState = ref.read(printerProvider);
        final router = PrintRouter(printerState);
        final userName = user?.name ?? '';
        final jobs = router.routeOrder(
          _pendingItems,
          waiterName: userName,
          tableNumber: widget.tableNumber,
          tableLabel: _printLabel(null),
        );
        if (jobs.isNotEmpty) {
          unawaited(dispatchOrderPrintJobs(ref.read(localDbProvider), jobs,
              tableId: widget.tableNumber));
        }
      }
      setState(() => _pendingItems.clear());
    } finally {
      if (mounted) setState(() => _sendingPendingItems = false);
    }
  }

  Future<void> _showRenameDialog() async {
    final table = await ref.read(localDbProvider).getTable(widget.tableNumber);
    if (table == null || !mounted) return;
    // The dialog hands back the typed name, or null when it was dismissed - so
    // there is nothing for this page to keep alive after the route is gone.
    final renamed = await showDialog<String>(
      context: context,
      builder: (_) => _RenameTableDialog(initialName: table.name),
    );
    if (renamed != null && renamed.isNotEmpty && mounted) {
      await ref.read(localDbProvider).renameTable(widget.tableNumber, renamed);
      setState(() {});
    }
  }

  String _tableInfoStatusText(TableStatus? status) {
    switch (status) {
      case TableStatus.empty:
        return context.tr('بەتاڵ');
      case TableStatus.occupied:
        return context.tr('دانیشتوو');
      case TableStatus.billRequested:
        return context.tr('داوای حیسابی کردووە');
      case TableStatus.overdue:
        return context.tr('دواکەوتوو');
      default:
        return '-';
    }
  }

  Color _tableInfoStatusColor(TableStatus? status) {
    return status == null
        ? AppColors.darkText
        : TableStatusVisuals.color(status);
  }

  Widget _tableInfoRow(String label, String value, Color valueColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 145,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.softText),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showTableInfoDialog() async {
    final db = ref.read(localDbProvider);
    final table = await db.getTable(widget.tableNumber);
    final lock = await db.getTableLockById(widget.tableNumber);
    // «کرایەوە» is the person who actually seated the table, not the captain
    // whose مەودا owns the row - those differ the moment the cashier opens a
    // table that sits inside a captain's range.
    final opener = table != null && table.openedBy > 0
        ? await db.getUserById(table.openedBy)
        : null;
    if (!mounted) return;
    final hasSeatedTime = table != null && table.seatedTime.isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.priority_high_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              ctx.trp('زانیاری مێزی {tableNumber}', {
                'tableNumber': widget.tableNumber.toString(),
              }),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tableInfoRow(
              ctx.tr('دۆخی ئێستای مێز'),
              _tableInfoStatusText(table?.status),
              _tableInfoStatusColor(table?.status),
            ),
            const SizedBox(height: 10),
            _tableInfoRow(
              ctx.tr('کاتی دانیشتن'),
              hasSeatedTime
                  ? table.formattedSeatedTimeAmPm(
                      am: ctx.tr('پ.ن'),
                      pm: ctx.tr('د.ن'),
                    )
                  : '-',
              AppColors.darkText,
            ),
            const SizedBox(height: 10),
            _tableInfoRow(
              ctx.tr('بەروار'),
              hasSeatedTime ? table.formattedSeatedDate : '-',
              AppColors.softText,
            ),
            const SizedBox(height: 10),
            _tableInfoRow(
              ctx.tr('چەند میوان دانیشتووە'),
              table == null ? '-' : table.guestCount.toString(),
              AppColors.darkText,
            ),
            if (table != null &&
                table.status == TableStatus.billRequested &&
                table.printedAt.isNotEmpty) ...[
              const SizedBox(height: 10),
              _tableInfoRow(
                ctx.tr('کاتی داوای حیساب'),
                table.formattedPrintedTimeAmPm(
                  am: ctx.tr('پ.ن'),
                  pm: ctx.tr('د.ن'),
                ),
                AppColors.blue,
              ),
            ],
            const SizedBox(height: 10),
            _tableInfoRow(
              ctx.tr('مێزەکە لە لایان کێ کرایەوە'),
              opener == null
                  ? '-'
                  : staffLabel(ctx, opener.role.index, opener.name),
              opener == null ? AppColors.softText : AppColors.primary,
            ),
            const SizedBox(height: 10),
            _tableInfoRow(
              ctx.tr('کێ خواردنی داوا کردووە'),
              lock == null
                  ? '-'
                  : '${lock.userName} (${lock.role == 'waiter' ? ctx.tr('کاپتن') : ctx.tr('کاشێر')})',
              lock == null ? AppColors.softText : AppColors.primary,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('داخستن')),
          ),
        ],
      ),
    );
  }

  Map<String, String> _decodeTableNote(String raw) => TableNote.decode(raw);

  String _encodeTableNote({required String captain, required String admin}) =>
      TableNote.encode(captain: captain, admin: admin);

  Future<void> _showTableNoteDialog() async {
    final table = await ref.read(localDbProvider).getTable(widget.tableNumber);
    if (table == null || !mounted) return;
    final noteParts = _decodeTableNote(table.note);
    final saved = await showDialog<TableNoteResult>(
      context: context,
      builder: (ctx) => TableNoteDialog(
        title: ctx.tr('تێبینی بۆ مێز'),
        captainText: noteParts['captain'] ?? '',
        adminText: noteParts['admin'] ?? '',
      ),
    );
    if (saved != null && mounted) {
      final encoded = _encodeTableNote(
        captain: saved.captain,
        admin: saved.admin,
      );
      await ref
          .read(localDbProvider)
          .updateTableNote(widget.tableNumber, encoded);
    }
  }

  double _calcDiscountedTotal(double total, int discountAmount) {
    if (discountAmount <= 0) return total;
    final discounted = total - discountAmount;
    return discounted < 0 ? 0 : discounted;
  }

  Future<void> _moveToDebts(double amount) async {
    final db = ref.read(localDbProvider);
    final user = ref.read(authProvider);
    final now = DateTime.now().toIso8601String();
    // Read before the first await: [context] must not be touched across an
    // async gap.
    final reason = context.tr('قەرز');
    // The debt belongs to whatever shift is open right now: when that shift is
    // closed the till's «قەرزەکان» list drops it, so the next cashier starts
    // clean (see LocalDatabase.getDebtsByShift).
    final shift = user != null ? await db.getActiveShift(user.id) : null;
    // A debt is a permanent record, so it has to carry the name the shop
    // gave the table - writing its number in would keep the old name on the
    // debt list for good, long after the rename.
    final tableName = _screenName(await db.getTable(widget.tableNumber));
    // Snapshot the dishes before `freeTable` wipes the order: the admin opens a
    // debt to see what was ordered, and after the move there is nothing else to
    // read it from.
    final items = await db.getOrderItems(widget.tableNumber);
    final snapshot = encodeDebtLines(
      items.map(
        (i) => DebtLine(name: i.name, price: i.price, quantity: i.quantity),
      ),
    );
    await db.addDebt(
      DebtModel(
        id: 0,
        tableId: widget.tableNumber,
        tableName: tableName,
        amount: amount,
        reason: reason,
        createdAt: now,
        createdBy: user?.id ?? 0,
        shiftId: shift?.id ?? 0,
        itemsJson: snapshot,
      ),
    );
    // پارە هێشتا نەدراوە: مێزەکە ئازاد دەکرێت بەبێ تۆمارکردنی داهات،
    // داهاتەکە تەنها لە کاتی کۆکردنەوە تۆمار دەکرێت.
    await db.freeTable(widget.tableNumber);
    await ref.read(waiterProvider.notifier).refresh();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _printReceipt(
    List<OrderItem> items,
    double finalAmount,
    double discountAmount, {
    int? guestCount,
    String? seatedAt,
  }) async {
    final db = ref.read(localDbProvider);
    final printerState = ref.read(printerProvider);
    final cashierPrinter = printerState.printers
        .where((p) => p.printerType == PrinterType.cashier)
        .firstOrNull;
    if (cashierPrinter == null) return;
    final tableModel = await db.getTable(widget.tableNumber);
    final currentUser = ref.read(authProvider);
    final design = await db.getReceiptDesign();
    if (!mounted) return;
    final subtotal = items.fold<double>(
      0,
      (s, item) => s + (item.price * item.quantity),
    );
    final confirmed = await PrintPreview.showReceiptPreview(
      context,
      tableNumber: widget.tableNumber,
      guestCount: guestCount ?? tableModel?.guestCount ?? 0,
      items: items,
      subtotal: subtotal,
      discountPercent: 0,
      discountAmount: discountAmount,
      total: finalAmount,
      cashierName: currentUser?.name ?? '',
      printerName: cashierPrinter.name,
      seatedAt: seatedAt ?? tableModel?.seatedTime ?? '',
      design: design,
    );
    if (confirmed && context.mounted) {
      await PrintRouter.dispatchReceipt(
        tableNumber: widget.tableNumber,
        guestCount: guestCount ?? tableModel?.guestCount ?? 0,
        items: items,
        subtotal: subtotal,
        discountPercent: 0,
        discountAmount: discountAmount,
        total: finalAmount,
        printer: cashierPrinter,
        cashierName: currentUser?.name ?? '',
        seatedAt: seatedAt ?? tableModel?.seatedTime ?? '',
        tableLabel: _printLabel(tableModel),
        design: design,
      );
    }
  }

  Future<void> _openCashDrawer() async {
    final printerState = ref.read(printerProvider);
    final cashierPrinter = printerState.printers
        .where((p) => p.printerType == PrinterType.cashier)
        .firstOrNull;
    if (cashierPrinter == null) return;
    try {
      await PrintRouter.dispatchRawCommand(
        cashierPrinter,
        EscPosBuilder.buildDrawerKick(),
      );
    } catch (e) {
      appLog('[Cashier] Drawer kick failed: $e');
    }
  }

  void _showTransferSingleItemDialog(String itemId, String itemName) {
    final tablesAsync = ref.read(waiterProvider);
    tablesAsync.whenData((tables) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          int? selectedId;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final emptyTables = tables
                  .where(
                    (t) =>
                        t.status == TableStatus.empty &&
                        t.id != widget.tableNumber,
                  )
                  .toList();
              final occupiedTables = tables
                  .where(
                    (t) =>
                        t.status != TableStatus.empty &&
                        t.id != widget.tableNumber,
                  )
                  .toList();
              return AlertDialog(
                title: Text(
                  context.trp('گواستنەوەی {itemName}', {'itemName': itemName}),
                ),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('بەتاڵەکان:'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (emptyTables.isEmpty)
                          Text(
                            context.tr('نییە'),
                            style: TextStyle(color: AppColors.softText),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: emptyTables.map((t) {
                              final isSel = selectedId == t.id;
                              return ChoiceChip(
                                label: Text(
                                  t.name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: isSel,
                                onSelected: (_) =>
                                    setDialogState(() => selectedId = t.id),
                                selectedColor: AppColors.success.withValues(
                                  alpha: 0.2,
                                ),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('گیراوەکان:'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (occupiedTables.isEmpty)
                          Text(
                            context.tr('نییە'),
                            style: TextStyle(color: AppColors.softText),
                          )
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: occupiedTables.map((t) {
                              final isSel = selectedId == t.id;
                              return ChoiceChip(
                                label: Text(
                                  t.name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: isSel,
                                onSelected: (_) =>
                                    setDialogState(() => selectedId = t.id),
                                selectedColor: AppColors.primary.withValues(
                                  alpha: 0.2,
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.tr('ڕەتکردنەوە')),
                  ),
                  FilledButton(
                    onPressed: selectedId == null
                        ? null
                        : () => Navigator.pop(ctx, selectedId!),
                    child: Text(context.tr('گواستنەوە')),
                  ),
                ],
              );
            },
          );
        },
      ).then((targetId) async {
        if (targetId == null) return;
        final db = ref.read(localDbProvider);
        await db.transferSingleItem(
          widget.tableNumber,
          targetId as int,
          itemId,
        );
        ref.invalidate(tableOrdersProvider(widget.tableNumber));
        ref.invalidate(tableOrdersProvider(targetId));
        await ref.read(waiterProvider.notifier).refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.trp('{itemName} گوازرایەوە', {'itemName': itemName}),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      });
    });
  }

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _menuItems = [];
  bool _menuLoading = true;

  Future<void> _loadMenu() async {
    final db = ref.read(localDbProvider);
    // This page can still be on screen when the database goes - the admin
    // resetting the app, a restore, shutdown - and the menu notification that
    // comes with it would otherwise be an unhandled error out of a listener.
    if (!db.isOpen) return;
    try {
      final categories = await db.getFoodCategories();
      final items = await db.getFoodItems();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _menuItems = items;
        _menuLoading = false;
      });
    } catch (e) {
      appLog('[CashierTable] Menu could not be read: $e');
      if (mounted) setState(() => _menuLoading = false);
    }
  }

  IconData _getCategoryIcon(String category) {
    final cat = _categories.where((c) => c['name'] == category).firstOrNull;
    if (cat != null) {
      return MenuHelper.iconFromString(cat['icon'] as String);
    }
    return Icons.restaurant;
  }

  Widget _buildCategoryTile(String name, IconData icon) {
    final isSelected = _selectedCategory == name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedCategory = name),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppColors.primary : AppColors.softText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.darkText,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChipsBar() {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _buildCategoryChip('هەموو', Icons.grid_view_rounded),
          ..._categories.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildCategoryChip(
                cat['name'] as String,
                MenuHelper.iconFromString(cat['icon'] as String),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String name, IconData icon) {
    final isSelected = _selectedCategory == name;
    return Material(
      color: isSelected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _selectedCategory = name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.borderSide,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.softText,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  context.tr(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? Colors.white : AppColors.darkText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget Function(BuildContext, int) _menuTileBuilder(
    List<Map<String, dynamic>> filteredItems,
  ) {
    return (context, index) {
      final item = filteredItems[index];
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        // Same cap as the captain's menu: the stagger stops scaling with the
        // index so a long category settles in ~half a second, not over a
        // second of offscreen compositing on a low-end tablet.
        duration: Duration(milliseconds: 250 + ((index > 8 ? 8 : index) * 30)),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - value)),
              child: child,
            ),
          );
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _addPendingItem(item),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Icon(
                        _getCategoryIcon(item['category'] as String),
                        size: 42,
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    item['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${context.tr('د.ع')} ${money((item['price'] as num))}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      );
    };
  }

  Widget _buildPhoneCartBar({
    required double grandTotal,
    required int totalItems,
    required bool hasPending,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderSide)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            InkWell(
              onTap: totalItems == 0 ? null : _showPhoneCartSheet,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.shopping_cart_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    if (totalItems > 0)
                      Positioned(
                        top: -8,
                        left: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$totalItems',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${context.tr('کۆی گشتی')}: ${context.tr('د.ع')} ${money(grandTotal)}',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: hasPending && !_sendingPendingItems
                  ? _sendPendingItems
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.borderSide,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _saveLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetRow(
    String name,
    int quantity,
    double lineTotal,
    Color accent,
    VoidCallback onDelete,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.darkText,
              ),
            ),
          ),
          Text(
            'x$quantity',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${context.tr('د.ع')} ${money(lineTotal)}',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneCartFooter({
    required double grandTotal,
    required VoidCallback notify,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderSide)),
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 40x40 hit area around the 22x22 visual box: the old bare
                // 22px target was under half the minimum tap size, and the
                // opaque behavior makes the padding area tappable too.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _printEnabled = !_printEnabled);
                    notify();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _printEnabled
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _printEnabled
                              ? AppColors.primary
                              : AppColors.softText,
                          width: 1.5,
                        ),
                      ),
                      child: _printEnabled
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('چاپ'),
                  style: TextStyle(fontSize: 13, color: AppColors.softText),
                ),
                const SizedBox(width: 12),
                Text(
                  context.tr('کۆی گشتی'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(width: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${context.tr('د.ع')} ${money(grandTotal)}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _pendingItems.isEmpty || _sendingPendingItems
                  ? null
                  : () async {
                      await _sendPendingItems();
                      notify();
                    },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _pendingItems.isEmpty
                    ? context.tr('خواردن هەڵبژێرە')
                    : _saveLabel,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.borderSide,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPhoneCartSheet() async {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          void notify() => setSheetState(() {});
          final orderItems =
              ref.read(tableOrdersProvider(widget.tableNumber)).valueOrNull ??
              <OrderItem>[];
          final sentTotal = orderItems.fold<double>(
            0,
            (s, i) => s + (i.price * i.quantity),
          );
          final pendingTotal = _pendingItems.fold<double>(
            0,
            (s, i) => s + (i.price * i.quantity),
          );
          final grandTotal = sentTotal + pendingTotal;
          final totalItems = orderItems.length + _pendingItems.length;
          return FractionallySizedBox(
            heightFactor: 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_cart_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('داواکاری'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$totalItems',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('داخستن'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: totalItems == 0
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_shopping_cart_outlined,
                                size: 48,
                                color: AppColors.softText,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                context.tr('هیچ خواردنێک هەڵنەبژێردراوە'),
                                style: TextStyle(color: AppColors.softText),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: orderItems.length + _pendingItems.length,
                          itemBuilder: (context, index) {
                            if (index < orderItems.length) {
                              final item = orderItems[index];
                              return _buildSheetRow(
                                item.name,
                                item.quantity,
                                item.price * item.quantity,
                                AppColors.softText,
                                () async {
                                  await _rejectOnePortion(item);
                                  notify();
                                },
                              );
                            }
                            final pendingItem =
                                _pendingItems[index - orderItems.length];
                            return _buildSheetRow(
                              pendingItem.name,
                              pendingItem.quantity,
                              pendingItem.price * pendingItem.quantity,
                              AppColors.primary,
                              () {
                                _decrementPending(index - orderItems.length);
                                notify();
                              },
                            );
                          },
                        ),
                ),
                _buildPhoneCartFooter(grandTotal: grandTotal, notify: notify),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(tableOrdersProvider(widget.tableNumber));
    final tableAsync = ref.watch(tableDetailProvider(widget.tableNumber));
    final isDesktop = Responsive.isDesktop(context);
    final isPhone = Responsive.isPhone(context);

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            widget.isDelivery
                // A delivery slot is named after its company and number, so
                // showing "مێزی 100104" would tell the cashier nothing.
                ? (widget.deliveryTitle ?? context.tr('دلیڤەری'))
                : _screenName(tableAsync.valueOrNull),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
          centerTitle: true,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.softText,
            tabs: [
              Tab(
                icon: const Icon(Icons.receipt_rounded),
                text: context.tr('حیساب'),
              ),
              Tab(
                icon: const Icon(Icons.restaurant_rounded),
                text: context.tr('خواردن'),
              ),
            ],
          ),
          actions: [
            ScrollableAppBarActions(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.priority_high_rounded,
                    color: AppColors.primary,
                  ),
                  tooltip: context.tr('زانیاری مێز'),
                  onPressed: _showTableInfoDialog,
                ),
                const SizedBox(width: 4),
                // A delivery slot's name is its company's plus its number: renaming
                // it would break the number the whole network agrees on.
                if (!widget.isDelivery) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: AppColors.primary,
                    ),
                    tooltip: context.tr('گۆڕینی ناوی مێز'),
                    onPressed: _showRenameDialog,
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: const Icon(
                    Icons.note_alt_rounded,
                    color: AppColors.blue,
                  ),
                  tooltip: context.tr('تێبینی'),
                  onPressed: _showTableNoteDialog,
                ),
                const SizedBox(width: 4),
                // Likewise, moving a delivery order onto a dining table is never
                // what the cashier means here, and the picker does not even show
                // delivery slots.
                if (!widget.isDelivery)
                  IconButton(
                    icon: const Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.primary,
                    ),
                    tooltip: context.tr('گواستنەوەی مێز'),
                    onPressed: () async {
                      final transferred = await Navigator.of(context)
                          .push<bool>(
                            MaterialPageRoute(
                              builder: (_) => TransferPage(
                                sourceTableId: widget.tableNumber,
                              ),
                            ),
                          );
                      if (transferred == true && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildBillTab(isPhone, ordersAsync, tableAsync),
            _buildFoodTab(isDesktop, isPhone),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodTab(bool isDesktop, bool isPhone) {
    final ordersAsync = ref.watch(tableOrdersProvider(widget.tableNumber));
    final filteredItems = _selectedCategory == 'هەموو'
        ? _menuItems
        : _menuItems.where((f) => f['category'] == _selectedCategory).toList();

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (orderItems) {
        final sentTotal = orderItems.fold<double>(
          0,
          (sum, item) => sum + (item.price * item.quantity),
        );
        final pendingTotal = _pendingItems.fold<double>(
          0,
          (sum, item) => sum + (item.price * item.quantity),
        );
        final grandTotal = sentTotal + pendingTotal;
        final totalItems = orderItems.length + _pendingItems.length;

        if (_menuLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (isPhone) {
          return Column(
            children: [
              _buildCategoryChipsBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ResponsiveGridView(
                    desktopColumns: 4,
                    tabletColumns: 3,
                    mobileColumns: 2,
                    spacing: 14,
                    runSpacing: 14,
                    childAspectRatio: 0.85,
                    itemCount: filteredItems.length,
                    itemBuilder: _menuTileBuilder(filteredItems),
                  ),
                ),
              ),
              _buildPhoneCartBar(
                grandTotal: grandTotal,
                totalItems: totalItems,
                hasPending: _pendingItems.isNotEmpty && !_sendingPendingItems,
              ),
            ],
          );
        }

        return Row(
          children: [
            Container(
              width: isDesktop ? 160 : 120,
              color: Colors.white,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildCategoryTile('هەموو', Icons.grid_view_rounded),
                  ..._categories.map(
                    (cat) => _buildCategoryTile(
                      cat['name'] as String,
                      MenuHelper.iconFromString(cat['icon'] as String),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: ResponsiveGridView(
                  // On an iPad portrait the menu area is only the width left
                  // after the side panes, so keep 3 columns until the screen
                  // really is laptop-wide; 4 fit from 1000pt up (iPad
                  // landscape and every Windows window).
                  desktopColumns:
                      MediaQuery.sizeOf(context).width >= 1000 ? 4 : 3,
                  tabletColumns: 3,
                  mobileColumns: 2,
                  spacing: 14,
                  runSpacing: 14,
                  childAspectRatio: 0.85,
                  itemCount: filteredItems.length,
                  itemBuilder: _menuTileBuilder(filteredItems),
                ),
              ),
            ),
            Container(
              width: isDesktop ? 280 : 220,
              color: Colors.white,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.borderSide),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shopping_cart_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            context.tr('داواکاری'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (totalItems > 0) ...[
                          InkWell(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(ctx.tr('سڕینەوەی هەموو')),
                                  content: Text(
                                    ctx.tr(
                                      'دڵنیایت دەتەوێت هەموو خواردنەکان بسڕیتەوە؟',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(ctx.tr('ڕەتکردنەوە')),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(ctx.tr('سڕینەوە')),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final db = ref.read(localDbProvider);
                                final user = ref.read(authProvider);
                                final notifier = ref.read(
                                  waiterProvider.notifier,
                                );
                                for (final item in orderItems) {
                                  await db.addRefund(
                                    Refund(
                                      tableId: widget.tableNumber,
                                      itemName: item.name,
                                      quantity: item.quantity,
                                      price: item.price,
                                      refundedAt: DateTime.now()
                                          .toIso8601String(),
                                      refundedBy: user?.id ?? 0,
                                    ),
                                  );
                                  notifier.removeItem(
                                    widget.tableNumber,
                                    item.id,
                                  );
                                }
                                setState(() => _pendingItems.clear());
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.delete_sweep_rounded,
                                size: 18,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$totalItems',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: totalItems == 0
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_shopping_cart_outlined,
                                  size: 48,
                                  color: AppColors.softText,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  context.tr('هیچ خواردنێک هەڵنەبژێردراوە'),
                                  style: TextStyle(color: AppColors.softText),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              ...orderItems.map((item) {
                                final itemTime = item.createdAt.isNotEmpty
                                    ? '${DateTime.tryParse(item.createdAt)?.hour.toString().padLeft(2, '0') ?? ''}:${DateTime.tryParse(item.createdAt)?.minute.toString().padLeft(2, '0') ?? ''}'
                                    : '';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.background.withValues(
                                      alpha: 0.5,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppColors.darkText,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: AlignmentDirectional
                                                  .centerStart,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (item
                                                      .waiterName
                                                      .isNotEmpty) ...[
                                                    Icon(
                                                      Icons.person_rounded,
                                                      size: 10,
                                                      color: AppColors.softText,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      staffLabel(
                                                        context,
                                                        item.waiterRole,
                                                        item.waiterName,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  Text(
                                                    '${context.tr('د.ع')} ${money(item.price)}',
                                                    style: const TextStyle(
                                                      color: AppColors.softText,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (itemTime.isNotEmpty)
                                              Text(
                                                itemTime,
                                                style: TextStyle(
                                                  color: AppColors.softText,
                                                  fontSize: 10,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        'x${item.quantity}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // The row's own line total, so what the
                                      // cashier reads here adds up to the
                                      // «کۆی گشتی» at the foot of the cart.
                                      SizedBox(
                                        width: 72,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            '${context.tr('د.ع')} ${money(item.price * item.quantity)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.darkText,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Consumer(
                                        builder: (context, ref, _) {
                                          return InkWell(
                                            onTap: () =>
                                                _rejectOnePortion(item),
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: AppColors.danger
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18,
                                                color: AppColors.danger,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              if (orderItems.isNotEmpty &&
                                  _pendingItems.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Divider(
                                    height: 1,
                                    color: AppColors.borderSide,
                                  ),
                                ),
                              ..._pendingItems.asMap().entries.map((entry) {
                                final index = entry.key;
                                final item = entry.value;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.04,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppColors.darkText,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                '${context.tr('د.ع')} ${money(item.price * item.quantity)}',
                                                style: const TextStyle(
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          _QuantityButton(
                                            icon: Icons.remove,
                                            onTap: () =>
                                                _decrementPending(index),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${item.quantity}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.darkText,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          _QuantityButton(
                                            icon: Icons.add,
                                            onTap: () =>
                                                _incrementPending(index),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () =>
                                                _decrementPending(index),
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: AppColors.danger
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 18,
                                                color: AppColors.danger,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.borderSide),
                      ),
                    ),
                    child: Column(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              // 40x40 hit area around the 22x22 visual box
                              // (see the same toggle in the bottom bar above).
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(
                                  () => _printEnabled = !_printEnabled,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: _printEnabled
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: _printEnabled
                                            ? AppColors.primary
                                            : AppColors.softText,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: _printEnabled
                                        ? const Icon(
                                            Icons.check_rounded,
                                            size: 16,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                context.tr('چاپ'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.softText,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                context.tr('کۆی گشتی'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.darkText,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${context.tr('د.ع')} ${money(grandTotal)}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _pendingItems.isEmpty || _sendingPendingItems
                                ? null
                                : _sendPendingItems,
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: Text(
                              _pendingItems.isEmpty
                                  ? context.tr('خواردن هەڵبژێرە')
                                  : _saveLabel,
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              backgroundColor: AppColors.primary,
                              disabledBackgroundColor: AppColors.borderSide,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Throws ONE portion off the bill, not the whole line.
  ///
  /// A dish ordered x3 falls to x2 on the first tap and x1 on the next; only
  /// the last portion clears the line. The food tab's cart already worked this
  /// way, but the bill tab - the one the cashier lands on when the table is not
  /// empty - dropped every portion at once, so fixing one wrong dish lost the
  /// whole round.
  ///
  /// Each tap refunds its own one-portion line. The final tap removes the line,
  /// and *that* removal is what writes the single «ڕەتکراوەکان» record: the queue
  /// dedups a rejection per order line, so recording each portion separately
  /// would make the partial records collapse into one another.
  Future<void> _rejectOnePortion(OrderItem item) async {
    final db = ref.read(localDbProvider);
    final user = ref.read(authProvider);
    final notifier = ref.read(waiterProvider.notifier);
    if (item.quantity > 1) {
      await db.addRefund(
        Refund(
          tableId: widget.tableNumber,
          itemName: item.name,
          quantity: 1,
          price: item.price,
          refundedAt: DateTime.now().toIso8601String(),
          refundedBy: user?.id ?? 0,
        ),
      );
      await notifier.updateItemQuantity(
        widget.tableNumber,
        item.id,
        item.quantity - 1,
      );
    } else {
      await db.addRefund(
        Refund(
          tableId: widget.tableNumber,
          itemName: item.name,
          quantity: item.quantity,
          price: item.price,
          refundedAt: DateTime.now().toIso8601String(),
          refundedBy: user?.id ?? 0,
        ),
      );
      await notifier.removeItem(widget.tableNumber, item.id);
    }
  }

  Widget _billItemRow(OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (item.waiterName.isNotEmpty)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 10,
                          color: AppColors.softText,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          staffLabel(
                            context,
                            item.waiterRole,
                            item.waiterName,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${context.tr('د.ع')} ${money(item.price)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'x${item.quantity}',
            style: const TextStyle(color: AppColors.softText),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${context.tr('د.ع')} ${money((item.price * item.quantity))}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _showTransferSingleItemDialog(item.id, item.name),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _rejectOnePortion(item),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillTab(
    bool isPhone,
    AsyncValue<List<OrderItem>> ordersAsync,
    AsyncValue<TableModel?> tableAsync,
  ) {
    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (orderItems) {
        final table = tableAsync.valueOrNull;
        final total = orderItems.fold<double>(
          0,
          (sum, item) => sum + (item.price * item.quantity),
        );
        final discount = _parseDiscount(total);
        final discountPercent = discount.percent;
        final discountAmount = discount.amount;
        final discountedTotal = _calcDiscountedTotal(total, discountAmount);

        final itemsCard = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.receipt_rounded,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.trp('مێزی {tableNumber} - حیساب', {
                            'tableNumber': widget.tableNumber.toString(),
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                          ),
                        ),
                        if (table != null)
                          Text(
                            context.trp(
                              'میوان: {guestCount} کەس • کاتی دانیشتن: {seatedTime}',
                              {
                                'guestCount': table.guestCount.toString(),
                                'seatedTime': table.seatedTimeDisplay(
                                  am: context.tr('پ.ن'),
                                  pm: context.tr('د.ن'),
                                ),
                              },
                            ),
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
                ],
              ),
              const Divider(height: 24),
              if (isPhone)
                orderItems.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            context.tr('هیچ خواردنێک تۆمارنەکراوە'),
                            style: TextStyle(color: AppColors.softText),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: orderItems.length,
                        itemBuilder: (context, index) =>
                            _billItemRow(orderItems[index]),
                      ),
              if (!isPhone)
                Expanded(
                  child: orderItems.isEmpty
                      ? Center(
                          child: Text(
                            context.tr('هیچ خواردنێک تۆمارنەکراوە'),
                            style: TextStyle(color: AppColors.softText),
                          ),
                        )
                      : ListView.builder(
                          itemCount: orderItems.length,
                          itemBuilder: (context, index) =>
                              _billItemRow(orderItems[index]),
                        ),
                ),
            ],
          ),
        );
        final payCard = SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('وردەکاری پارەدان'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                if (discountAmount > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.discount_rounded,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${context.tr('داشکاندن')} ($discountPercent%)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '-${context.tr('د.ع')} ${money(discountAmount)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.receipt_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            context.tr('کۆی پاش داشکاندن'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${context.tr('د.ع')} ${money(discountedTotal)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.discount_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _discountMode == _DiscountMode.percent
                                  ? context.tr('داشکاندن (%)')
                                  : context.tr('داشکاندن (د.ع)'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Spacer(),
                          _buildDiscountModeToggle(),
                          if (discountAmount > 0) ...[
                            const SizedBox(width: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '-${context.tr('د.ع')} ${money(discountAmount)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _discountController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                if (_discountMode == _DiscountMode.amount)
                                  // Whole dinars with comma separators
                                  // ("5,000", "125,000"), capped at the bill.
                                  AmountInputFormatter(maxValue: total.toInt())
                                else
                                  FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                hintText: '0',
                                filled: true,
                                fillColor: Colors.white,
                                suffixText:
                                    _discountMode == _DiscountMode.percent
                                    ? '%'
                                    : context.tr('د.ع'),
                                suffixStyle: TextStyle(
                                  color: AppColors.softText,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 42,
                            child: FilledButton(
                              onPressed: () {
                                _discountController.clear();
                                setState(() {});
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger.withValues(
                                  alpha: 0.1,
                                ),
                                foregroundColor: AppColors.danger,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              child: const Icon(Icons.clear_rounded, size: 18),
                            ),
                          ),
                        ],
                      ),
                      if (_discountMode == _DiscountMode.percent) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [5, 10, 15, 20, 25, 50].map((pct) {
                            final isSelected = discountPercent == pct;
                            return InkWell(
                              onTap: () {
                                _discountController.text = pct.toString();
                                setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.borderSide,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Text(
                                  '$pct%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.darkText,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('کۆی گشتی'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${context.tr('د.ع')} ${money(total)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final db = ref.read(localDbProvider);
                            final printerState = ref.read(printerProvider);
                            final cashierPrinter = printerState.printers
                                .where(
                                  (p) => p.printerType == PrinterType.cashier,
                                )
                                .firstOrNull;
                            final tableModel = table;
                            final currentUser = ref.read(authProvider);

                            // Stamp the bill FIRST and print it second.
                            //
                            // It used to be the other way round, which put
                            // the printer's clock in front of the floor's: a
                            // network printer that is switched off blocks on a
                            // five-second connect, so the table stayed GREEN
                            // for five seconds after the cashier had already
                            // printed, and a configured fallback printer could
                            // double it. Worse, with no cashier printer at all
                            // the table was never marked - the bill never
                            // showed on the floor and the ten-second red clock
                            // never started.
                            //
                            // Issuing the bill is a fact about the floor; the
                            // paper is a side effect of it. The fact goes
                            // first, so the card turns blue the moment the
                            // cashier presses the button.
                            await db.markAsPrinted(widget.tableNumber);
                            // Silent: the whole floor must not blink to a
                            // spinner in the same frame the bill is printed.
                            await ref
                                .read(waiterProvider.notifier)
                                .refreshSilent();
                            if (!mounted) return;

                            bool? printed; // null = there was no printer to try
                            if (cashierPrinter != null) {
                              final design = await db.getReceiptDesign();
                              printed = await PrintRouter.dispatchReceipt(
                                tableNumber: widget.tableNumber,
                                guestCount: tableModel?.guestCount ?? 0,
                                items: orderItems,
                                subtotal: total,
                                discountPercent: 0,
                                discountAmount: discountAmount.toDouble(),
                                total: discountAmount > 0
                                    ? discountedTotal
                                    : total,
                                printer: cashierPrinter,
                                cashierName: currentUser?.name ?? '',
                                seatedAt: tableModel?.seatedTime ?? '',
                                tableLabel: _printLabel(tableModel),
                                design: design,
                              );
                            }
                            if (!mounted) return;
                            // The bill reached the floor either way, so the
                            // message reports what happened to the paper.
                            final message = printed == null
                                ? 'هیچ چاپکەرێک ڕێکنەخراوە'
                                : printed
                                ? 'بە سەرکەوتووی چاپکرا'
                                : 'گەیشتە لای کاشێر - پرێنت نەکراوە';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.tr(message)),
                                backgroundColor: printed == true
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            );
                          },
                          icon: const Icon(Icons.print_rounded),
                          label: Text(context.tr('چاپکردن')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.darkText,
                            side: const BorderSide(color: AppColors.borderSide),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(ctx.tr('قەرز')),
                                content: Text(
                                  ctx.tr(
                                    'دڵنیایت دەتەوێت ئەم مێزە بخەیتە بەشی قەرزەکانەوە؟',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(ctx.tr('ڕەتکردنەوە')),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(ctx.tr('بەڵێ')),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              _moveToDebts(
                                discountAmount > 0 ? discountedTotal : total,
                              );
                            }
                          },
                          icon: const Icon(Icons.bookmark_add_rounded),
                          label: Text(context.tr('قەرز')),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final finalAmount = discountAmount > 0
                                ? discountedTotal
                                : total;
                            final result = await CashCalculatorDialog.show(
                              context,
                              totalDue: finalAmount,
                              tableName: context.trp('مێزی {tableNumber}', {
                                'tableNumber': widget.tableNumber.toString(),
                              }),
                            );
                            if (result == null || !context.mounted) return;
                            final db = ref.read(localDbProvider);
                            final user = ref.read(authProvider);
                            final shift = user != null
                                ? await db.getActiveShift(user.id)
                                : null;
                            final tableBefore = await db.getTable(
                              widget.tableNumber,
                            );
                            await db.settleTable(
                              widget.tableNumber,
                              finalAmount,
                              0,
                              discountAmount.toDouble(),
                              user?.id ?? 0,
                              shiftId: shift?.id ?? 0,
                              paymentMethod: 'cash',
                            );
                            await _printReceipt(
                              orderItems,
                              finalAmount,
                              discountAmount.toDouble(),
                              guestCount: tableBefore?.guestCount,
                              seatedAt: tableBefore?.seatedTime,
                            );
                            await _openCashDrawer();
                            await ref.read(waiterProvider.notifier).refresh();
                            if (!mounted) return;
                            Navigator.pop(context, true);
                          },
                          icon: const Icon(Icons.monetization_on_rounded),
                          label: Text(context.tr('واسڵ کردن')),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final choice = await showDialog<_CardPaymentChoice>(
                              context: context,
                              builder: (_) => const _CardPaymentDialog(),
                            );
                            if (choice == null || !mounted) return;
                            final finalAmount = discountAmount > 0
                                ? discountedTotal
                                : total;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(context.tr('واسڵکردن')),
                                content: Text(
                                  context.trp(
                                    'دڵنیایت دەتەوێت مێزی {tableNumber} بە {method} واسڵ بکەیت؟',
                                    {
                                      'tableNumber': widget.tableNumber
                                          .toString(),
                                      'method': choice.label,
                                    },
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(context.tr('ڕەتکردنەوە')),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(context.tr('واسڵکردن')),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !mounted) return;
                            final db = ref.read(localDbProvider);
                            final user = ref.read(authProvider);
                            final shift = user != null
                                ? await db.getActiveShift(user.id)
                                : null;
                            final tableBefore = await db.getTable(
                              widget.tableNumber,
                            );
                            await db.settleTable(
                              widget.tableNumber,
                              finalAmount,
                              0,
                              discountAmount.toDouble(),
                              user?.id ?? 0,
                              shiftId: shift?.id ?? 0,
                              paymentMethod: choice.method,
                            );
                            if (choice.printReceipt && mounted) {
                              await _printReceipt(
                                orderItems,
                                finalAmount,
                                discountAmount.toDouble(),
                                guestCount: tableBefore?.guestCount,
                                seatedAt: tableBefore?.seatedTime,
                              );
                            }
                            await ref.read(waiterProvider.notifier).refresh();
                            if (!mounted) return;
                            Navigator.pop(context, true);
                          },
                          icon: const Icon(Icons.credit_card_rounded),
                          label: Text(context.tr('کارت')),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        if (isPhone) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [payCard, const SizedBox(height: 12), itemsCard],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: payCard),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: itemsCard),
            ],
          ),
        );
      },
    );
  }
}

/// A card brand option plus how the cashier wants to finish the sale.
class _CardPaymentChoice {
  const _CardPaymentChoice({
    required this.method,
    required this.label,
    required this.printReceipt,
  });

  /// Storage key written into `settled_orders.paymentMethod`.
  final String method;

  /// Human-readable brand name shown to the cashier and in shift reports.
  final String label;

  /// True when the cashier asked for a receipt (وەسڵ) to be printed while
  /// settling — card machines usually give their own slip, so this is a per
  /// settlement decision, toggled right next to the "جۆری کارت" title.
  final bool printReceipt;
}

/// Card-type picker with the "print receipt" toggle.
///
/// Returns a [_CardPaymentChoice] when a brand is picked, or null when the
/// dialog is dismissed.
class _CardPaymentDialog extends StatefulWidget {
  const _CardPaymentDialog();

  @override
  State<_CardPaymentDialog> createState() => _CardPaymentDialogState();
}

class _CardPaymentDialogState extends State<_CardPaymentDialog> {
  bool _printReceipt = true;

  static const List<({String method, String label, IconData icon})> _methods = [
    (method: 'fib', label: 'FIB', icon: Icons.credit_card_rounded),
    (method: 'fastpay', label: 'FastPay', icon: Icons.bolt_rounded),
    (method: 'superqi', label: 'Super QI', icon: Icons.flash_on_rounded),
    (
      method: 'zincash',
      label: 'ZinCash',
      icon: Icons.account_balance_wallet_rounded,
    ),
    (method: 'nass', label: 'NassPay', icon: Icons.payment_rounded),
    (method: 'switch', label: 'Switch', icon: Icons.swap_horiz_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('جۆری کارت'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          _buildPrintToggle(),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _methods.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 56),
              ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _methods[i].icon,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  _methods[i].label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.softText,
                ),
                onTap: () => Navigator.pop(
                  context,
                  _CardPaymentChoice(
                    method: _methods[i].method,
                    label: _methods[i].label,
                    printReceipt: _printReceipt,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A small "چاپکردنی وەسڵ" toggle pill next to the dialog title.
  ///
  /// Filled (primary) = the receipt will print when the table is settled;
  /// outlined (grey) = settlement goes through without printing.
  Widget _buildPrintToggle() {
    final active = _printReceipt;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _printReceipt = !_printReceipt),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.borderSide,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.print_rounded,
              size: 17,
              color: active ? AppColors.primary : AppColors.softText,
            ),
            const SizedBox(width: 6),
            Text(
              context.tr('چاپکردنی وەسڵ'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: active ? AppColors.primary : AppColors.softText,
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: 0.7,
              child: Switch(
                value: active,
                activeTrackColor: AppColors.primary,
                onChanged: (v) => setState(() => _printReceipt = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rename dialog owns its own text field.
///
/// It used to own nothing: the page built the controller, awaited the dialog and
/// then disposed the controller - which happens *before* the dialog has finished
/// sliding off the screen, so its field rebuilt one last time against a disposed
/// controller and Flutter threw "A TextEditingController was used after being
/// disposed". A dialog that keeps its own controller dies with its own route
/// instead, which is the lifecycle the field really has.
///
/// It answers with the typed name, or null if it was dismissed, so the guard
/// against a blank name lives in one place and the page never has to hold state
/// from a route that is already closing.
class _RenameTableDialog extends StatefulWidget {
  const _RenameTableDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameTableDialog> createState() => _RenameTableDialogState();
}

class _RenameTableDialogState extends State<_RenameTableDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('گۆڕینی ناوی مێز')),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: context.tr('ناوی مێز'),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('ڕەتکردنەوە')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.tr('گۆڕین')),
        ),
      ],
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QuantityButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }
}
