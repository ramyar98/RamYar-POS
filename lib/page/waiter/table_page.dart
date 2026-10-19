import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../database/local_db.dart';
import '../../models/order_model.dart';
import '../../models/table_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/waiter_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/food_localization.dart';
import '../../services/menu_helper.dart';
import '../../services/print_router.dart';
import '../../services/sync_provider.dart';
import '../../services/table_lock_controller.dart';
import '../../services/table_note_policy.dart';
import '../cashier/transfer_page.dart';
import '../../widgets/table_note_dialog.dart';

class TablePage extends ConsumerStatefulWidget {
  final int tableNumber;
  final int initialGuestCount;
  const TablePage({
    super.key,
    required this.tableNumber,
    this.initialGuestCount = 1,
  });

  @override
  ConsumerState<TablePage> createState() => _TablePageState();
}

class _TablePageState extends ConsumerState<TablePage> {
  String _selectedCategory = 'هەموو';
  final List<OrderItem> _pendingItems = [];
  bool _printEnabled = true;

  /// True while `_sendPendingItems` is writing to the database.
  ///
  /// The send button is only gated on `_pendingItems.isEmpty`, which does not
  /// change until the awaited batch write returns - so without this guard a
  /// fast double-tap sends the same dishes twice and prints two kitchen tickets.
  bool _sendingPendingItems = false;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _menuItems = [];
  bool _menuLoading = true;
  late final LocalDatabase _db;
  late final int _userId;
  late final String _userName;
  TableLockController? _lock;

  @override
  void initState() {
    super.initState();
    _db = ref.read(localDbProvider);
    final user = ref.read(authProvider);
    _userId = user?.id ?? 0;
    _userName = user?.name ?? '';
    _loadMenu();
    // Live menu updates: when the admin adds/edits/deletes food items (or a
    // synced-in remote change lands), refresh the local menu immediately.
    _db.foodMenuRevision.addListener(_onMenuChanged);
    _acquireTableLock();
  }

  @override
  void dispose() {
    _db.foodMenuRevision.removeListener(_onMenuChanged);
    unawaited(_lock?.release());
    super.dispose();
  }

  Future<void> _acquireTableLock() async {
    final controller = TableLockController(
      db: _db,
      tableId: widget.tableNumber,
      userId: _userId,
      userName: _userName,
      role: 'waiter',
      onLost: _onTableLockLost,
    );
    _lock = controller;
    final taken = await controller.acquire();
    if (!taken) {
      // Somebody is already at this table. The grid blocks this path, so
      // reaching here means the table was taken between the tap and now -
      // stand down rather than serve it alongside them.
      controller.loseImmediately(TableLockLoss.heldByAnotherUser);
    }
  }

  /// The claim on this table is gone. Either the cashier threw this captain off
  /// it, or another device took it over. Either way this page has no business
  /// staying open, and the pending items were never sent so nothing is lost.
  Future<void> _onTableLockLost(TableLockLoss reason) async {
    if (!mounted) return;
    if (reason == TableLockLoss.heldByAnotherUser) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person_off_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('لە مێزەکە دەرکرایتەوە'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          context.trp(
            'کاپتنی دیکە {name} مێزەکەی لە دەستت دا، بۆیە ئیتر ناتوانیت لەسەر کار بکەیت.',
            {'name': _userName},
          ),
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('باشە')),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  void _onMenuChanged() {
    if (mounted) _loadMenu();
  }

  Future<void> _loadMenu() async {
    final db = ref.read(localDbProvider);
    _categories = await db.getFoodCategories();
    _menuItems = await db.getFoodItems();
    if (mounted) setState(() => _menuLoading = false);
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
        // Who rang the dish in, so the cashier can tell a captain's line from
        // one they added themselves.
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
        await _dispatchPrintJobs();
      }
      if (!mounted) return;
      setState(() => _pendingItems.clear());
    } finally {
      if (mounted) setState(() => _sendingPendingItems = false);
    }
  }

  Future<void> _notifyCashier() async {
    final db = ref.read(localDbProvider);
    await db.notifyTable(widget.tableNumber);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('ناردنی ئاگەدارکردنەوە بۆ کاشێر')),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _showTableNoteDialog() async {
    final table = await ref.read(localDbProvider).getTable(widget.tableNumber);
    if (table == null || !mounted) return;
    final noteParts = _decodeTableNote(table.note);
    final currentUser = ref.read(authProvider);
    final canEditAdminNote = TableNotePolicy.canEditAdminNote(
      currentUser?.role,
    );
    final saved = await showDialog<TableNoteResult>(
      context: context,
      builder: (ctx) => TableNoteDialog(
        title: ctx.tr('تێبینی'),
        captainText: noteParts['captain'] ?? '',
        adminText: noteParts['admin'] ?? '',
        showAdminField: canEditAdminNote,
      ),
    );
    if (saved != null && mounted) {
      final effectiveAdmin = TableNotePolicy.effectiveAdminNote(
        canEdit: canEditAdminNote,
        editedAdmin: saved.admin,
        existingAdmin: noteParts['admin'] ?? '',
      );
      final encoded = _encodeTableNote(
        captain: saved.captain,
        admin: effectiveAdmin,
      );
      await ref
          .read(localDbProvider)
          .updateTableNote(widget.tableNumber, encoded);
    }
  }

  Future<void> _dispatchPrintJobs() async {
    final printerState = ref.read(printerProvider);
    final router = PrintRouter(printerState);
    final user = ref.read(authProvider);
    final waiterName = user?.name ?? '';
    final jobs = router.routeOrder(
      _pendingItems,
      waiterName: waiterName,
      tableNumber: widget.tableNumber,
    );
    if (jobs.isEmpty) return;
    unawaited(dispatchOrderPrintJobs(ref.read(localDbProvider), jobs,
        tableId: widget.tableNumber));
  }

  /// What this table should be called on screen.
  ///
  /// The label the shop gave it, not its number. This title used to be built
  /// from the number alone, so a table renamed at the cashier's till kept
  /// reading its old number here on the captain's own screen - the same gap
  /// that made the rename look like it had not saved. The number is only the
  /// fallback, for a row that has not loaded yet or that carries no usable
  /// label at all.
  String _screenName(TableModel? table) {
    final stored = table?.name.trim() ?? '';
    return stored.isNotEmpty
        ? stored
        : '${context.tr('مێزی')} ${widget.tableNumber}';
  }

  Map<String, String> _decodeTableNote(String raw) => TableNote.decode(raw);

  String _encodeTableNote({required String captain, required String admin}) =>
      TableNote.encode(captain: captain, admin: admin);

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(tableOrdersProvider(widget.tableNumber));
    // The row itself, not just its orders: the appbar title is the name on this
    // row, so a rename has to be able to repaint it. Without the watch the
    // captain keeps reading the number until they leave and re-enter the table.
    final tableAsync = ref.watch(tableDetailProvider(widget.tableNumber));
    final isDesktop = Responsive.isDesktop(context);
    final isPhone = Responsive.isPhone(context);
    final itemB = isDesktop ? 0.8 : 0.85;
    final gridColumns = Responsive.gridColumns(
      context,
      desktop: 4,
      tablet: 3,
      mobile: 2,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      // The page has no text field of its own (the note editor is a dialog), so
      // the soft keyboard must not shrink the body: it did, and the fixed-height
      // cart column overflowed while the keyboard animated open.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _screenName(tableAsync.valueOrNull),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.note_alt_rounded, color: AppColors.blue),
            tooltip: context.tr('تێبینی'),
            onPressed: _showTableNoteDialog,
          ),
          IconButton(
            icon: const Icon(
              Icons.swap_horiz_rounded,
              color: AppColors.primary,
            ),
            tooltip: context.tr('گواستنەوەی مێز'),
            onPressed: () => _showTransferDialog(),
          ),
          if (isPhone)
            IconButton(
              icon: const Icon(
                Icons.notifications_active_rounded,
                color: AppColors.primary,
              ),
              tooltip: context.tr('ئاگەدارکردنەوە'),
              onPressed: _notifyCashier,
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8, start: 4),
              child: FilledButton.icon(
                onPressed: _notifyCashier,
                icon: const Icon(Icons.notifications_active_rounded, size: 18),
                label: Text(context.tr('ئاگەدارکردنەوە')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: _menuLoading
          ? const Center(child: CircularProgressIndicator())
          : ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (orderItems) {
                final filteredItems = _selectedCategory == 'هەموو'
                    ? _menuItems
                    : _menuItems
                          .where((f) => f['category'] == _selectedCategory)
                          .toList();
                final sentTotal = orderItems.fold<double>(
                  0,
                  (sum, item) => sum + (item.price * item.quantity),
                );
                final pendingTotal = _pendingItems.fold<double>(
                  0,
                  (sum, item) => sum + (item.price * item.quantity),
                );
                return isPhone
                    ? _buildPhoneBody(
                        orderItems,
                        sentTotal + pendingTotal,
                        orderItems.length + _pendingItems.length,
                        filteredItems,
                        gridColumns,
                        itemB,
                      )
                    : _buildDesktopBody(
                        orderItems,
                        sentTotal + pendingTotal,
                        orderItems.length + _pendingItems.length,
                        filteredItems,
                        gridColumns,
                        itemB,
                      );
              },
            ),
    );
  }

  Widget _buildDesktopBody(
    List<OrderItem> orderItems,
    double grandTotal,
    int totalItems,
    List<Map<String, dynamic>> filteredItems,
    int columns,
    double aspectRatio,
  ) {
    return Row(
      children: [
        // The fixed chrome scales with the device tier: 120/220 on a tablet
        // ate over half of a 768px-wide screen and left the menu grid ~85px
        // cells, while a 1920 desktop can afford a wider rail and a cart
        // that does not look pasted on as an afterthought.
        Container(
          width: Responsive.valueForDevice(
            context: context,
            mobileVal: 120,
            tabletVal: 120,
            desktopVal: 140,
          ),
          color: Colors.white,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _buildCategoryItem('هەموو', Icons.grid_view_rounded),
              ..._categories.map(
                (cat) => _buildCategoryItem(
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
              itemCount: filteredItems.length,
              desktopColumns: 4,
              tabletColumns: 3,
              mobileColumns: 2,
              spacing: 14,
              runSpacing: 14,
              childAspectRatio: aspectRatio,
              itemBuilder: (context, index) =>
                  _menuItemTile(filteredItems[index], index),
            ),
          ),
        ),
        Container(
          width: Responsive.valueForDevice(
            context: context,
            mobileVal: 220,
            tabletVal: 190,
            desktopVal: 260,
          ),
          color: Colors.white,
          child: Column(
            children: [
              _buildCartHeader(totalItems),
              Expanded(
                child: totalItems == 0
                    ? const _EmptyCart()
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          ...orderItems.map(_orderItemTile),
                          if (orderItems.isNotEmpty && _pendingItems.isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Divider(
                                height: 1,
                                color: AppColors.borderSide,
                              ),
                            ),
                          ..._pendingItems.asMap().entries.map(
                            (entry) => _pendingItemTile(entry.key),
                          ),
                        ],
                      ),
              ),
              _buildCartFooter(grandTotal: grandTotal),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneBody(
    List<OrderItem> orderItems,
    double grandTotal,
    int totalItems,
    List<Map<String, dynamic>> filteredItems,
    int columns,
    double aspectRatio,
  ) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildCategoryChips()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              ResponsiveGridView(
                itemCount: filteredItems.length,
                desktopColumns: 4,
                tabletColumns: 3,
                mobileColumns: columns,
                spacing: 10,
                runSpacing: 10,
                childAspectRatio: aspectRatio,
                shrinkWrap: true,
                itemBuilder: (context, index) =>
                    _menuItemTile(filteredItems[index], index),
              ),
              const SizedBox(height: 12),
              _buildPhoneCart(orderItems, grandTotal, totalItems),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneCart(
    List<OrderItem> orderItems,
    double grandTotal,
    int totalItems,
  ) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCartHeader(totalItems),
          if (totalItems == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: _EmptyCart(),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...orderItems.map(_orderItemTile),
                  if (orderItems.isNotEmpty && _pendingItems.isNotEmpty)
                    const Divider(height: 1, color: AppColors.borderSide),
                  ..._pendingItems.asMap().entries.map(
                    (entry) => _pendingItemTile(entry.key),
                  ),
                ],
              ),
            ),
          _buildCartFooter(grandTotal: grandTotal),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    final names = ['هەموو', ..._categories.map((c) => c['name'] as String)];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: names.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final name = names[index];
          final icon = index == 0
              ? Icons.grid_view_rounded
              : MenuHelper.iconFromString(
                  _categories[index - 1]['icon'] as String,
                );
          final selected = _selectedCategory == name;
          return InkWell(
            onTap: () => setState(() => _selectedCategory = name),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.borderSide,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? Colors.white : AppColors.softText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.tr(name),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.darkText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _menuItemTile(Map<String, dynamic> item, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      // Capped: a busy category can hold dozens of tiles, and a duration that
      // grows with the index kept the last of them fading for over a second -
      // continuous offscreen compositing on the shop's cheapest phones. The
      // first screenful still cascades; everything past it is already settled.
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
                  FoodLocalization.localizedName(
                    item,
                    AppState.of(context).currentLanguage,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
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
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartHeader(int totalItems) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSide)),
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
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderItemTile(OrderItem item) {
    final itemTime = item.createdAt.isNotEmpty
        ? '${DateTime.tryParse(item.createdAt)?.hour.toString().padLeft(2, '0') ?? ''}:${DateTime.tryParse(item.createdAt)?.minute.toString().padLeft(2, '0') ?? ''}'
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
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
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (item.waiterName.isNotEmpty) ...[
                      Icon(
                        Icons.person_rounded,
                        size: 10,
                        color: AppColors.softText,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
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
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${context.tr('د.ع')} ${money(item.price)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.softText,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (itemTime.isNotEmpty)
                  Text(
                    itemTime,
                    style: TextStyle(color: AppColors.softText, fontSize: 10),
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
        ],
      ),
    );
  }

  Widget _pendingItemTile(int index) {
    final item = _pendingItems[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
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
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 2),
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
          Row(
            children: [
              _QuantityButton(
                icon: Icons.remove,
                tooltip: context.tr('کەمکردن'),
                onTap: () => _decrementPending(index),
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
                tooltip: context.tr('زیادکردن'),
                onTap: () => _incrementPending(index),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: context.tr('سڕینەوە'),
                child: InkWell(
                  // The trash removes the whole line; it used to call
                  // `_decrementPending`, so a quantity of 5 needed five taps.
                  onTap: () => setState(() => _pendingItems.removeAt(index)),
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
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
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCartFooter({required double grandTotal}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderSide)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 40x40 hit area around the 22x22 visual box (same treatment
              // as the print toggles on the cashier's bill pages).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _printEnabled = !_printEnabled),
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
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('کۆی گشتی'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${context.tr('د.ع')} ${money(grandTotal)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _pendingItems.isEmpty || _sendingPendingItems
                  ? null
                  : _sendPendingItems,
              icon: const Icon(Icons.send_rounded),
              label: Text(
                _pendingItems.isEmpty
                    ? context.tr('خواردن هەڵبژێرە')
                    : context.tr('ناردن'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: Size(
                  double.infinity,
                  Responsive.buttonHeight(context),
                ),
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

  Future<void> _showTransferDialog() async {
    final transferred = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransferPage(sourceTableId: widget.tableNumber),
      ),
    );
    if (transferred == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildCategoryItem(String name, IconData icon) {
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
                Flexible(
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

  IconData _getCategoryIcon(String category) {
    final cat = _categories.where((c) => c['name'] == category).firstOrNull;
    if (cat != null) {
      return MenuHelper.iconFromString(cat['icon'] as String);
    }
    return Icons.restaurant;
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
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
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _QuantityButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // A 40x40 hit area around a 32px chip: the old 26px control was easy to
        // miss while the waiter was carrying a tray.
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}
