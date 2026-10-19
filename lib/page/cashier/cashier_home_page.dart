import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/env.dart';
import '../../core/responsive.dart';
import '../../core/table_status_visuals.dart';
import '../../widgets/close_shift_dialog.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/dialog_controller_owner.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../models/debt_model.dart';
import '../../models/settlement_model.dart';
import '../../models/table_notification_model.dart';
import '../../models/table_lock_model.dart';
import '../../providers/waiter_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../services/sync_provider.dart';
import 'cashier_cancelled_items_page.dart';
import 'cashier_expenses_page.dart';
import 'cashier_previous_orders_page.dart';
import '../../widgets/profile_icon.dart';
import '../../widgets/table_card.dart';
import '../../widgets/currency_converter.dart';
import '../../widgets/dollar_rate_banner.dart';
import 'cashier_unified_table_page.dart';
import 'cashier_table_hold_page.dart';
import 'cashier_welcome_page.dart';
import 'delivery_page.dart';
import '../login/login_page.dart';

class CashierHomePage extends ConsumerStatefulWidget {
  const CashierHomePage({super.key});

  @override
  ConsumerState<CashierHomePage> createState() => _CashierHomePageState();
}

enum _TableFilterOption { all, occupied, empty, delivery }

class _CashierHomePageState extends ConsumerState<CashierHomePage>
    with WidgetsBindingObserver {
  int _currentTab = 0;
  _TableFilterOption _tableFilter = _TableFilterOption.all;
  Timer? _overdueTimer;
  CashierShift? _activeShift;
  late final LocalDatabase _db;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db = ref.read(localDbProvider);
    _db.onTableNotification = _handleTableNotification;
    Future.microtask(() async {
      await ref.read(localDbProvider).checkOverdueTables();
      ref.read(waiterProvider.notifier).refreshSilent();
      await _loadShift();
      if (_activeShift == null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const CashierWelcomePage()),
        );
        return;
      }
      final user = ref.read(authProvider);
      if (user != null) {
        final printerState = ref.read(printerProvider);
        final ip = await startSyncServer(
          ref.read(localDbProvider),
          user.id,
          user.role.name,
          ref.read(syncConnectionProvider.notifier),
          printerConfig: printerState,
        );
        // Recall across app restarts that this device hosts the central server.
        if (ip != null) {
          await markServerDevice();
        }
      }
    });
    // هەر ٢ چرکە جارێک دۆخی مێزەکان دەپشکنرێت و UI تازە دەکرێتەوە
    // Every second rather than two, so a table turns red close to the moment its
    // ten-minute window closes - see LocalDatabase.billOverdueSeconds. Skipped
    // under test for the same reason as the waiter's timer: widget tests run
    // under fake time, where a real periodic timer is left pending and fails the
    // suite.
    if (isRunningUnderTest) return;
    _overdueTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      // No checkOverdueTables() here: the shared waiterProvider owns the
      // one-second bill clock for the whole app (see WaiterNotifier), and every
      // home page watches it. Running it a second time on this screen was two
      // identical writes a second for one colour change - pure heat on the
      // shop's oldest phones. This timer exists only to keep the floor fresh.
      ref.read(waiterProvider.notifier).refreshSilent();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(waiterProvider.notifier).refreshSilent();
      ref.read(localDbProvider).checkOverdueTables();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overdueTimer?.cancel();
    _db.onTableNotification = null;
    super.dispose();
  }

  void _handleTableNotification() {
    if (mounted) {
      ref.invalidate(tableNotificationsProvider);
      ref.read(waiterProvider.notifier).refreshSilent();
    }
  }

  Future<void> _loadShift() async {
    final user = ref.read(authProvider);
    if (user != null && user.role == UserRole.cashier) {
      _activeShift = await ref.read(localDbProvider).getActiveShift(user.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _showAddTableDialog() async {
    final inputController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          context.tr('زیادکردنی مێزی نوێ'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: inputController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.tr('ژمارە یان ناوی مێز'),
            hintText: context.tr('بۆ نموونە: 51 یان Ramyar'),
            prefixIcon: const Icon(Icons.table_restaurant_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('ڕەتکردنەوە')),
          ),
          FilledButton(
            onPressed: () async {
              if (inputController.text.trim().isEmpty) return;
              final success = await ref
                  .read(waiterProvider.notifier)
                  .addTableWithInput(inputController.text);
              if (!ctx.mounted) return;
              if (success) {
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(ctx.tr('ببورە ئەم مێزە بوونی هەیە')),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            child: Text(context.tr('زیادکردن')),
          ),
        ],
      ),
    );
  }

  /// Opens the cashier's expense ledger for the open shift. On the way back the
  /// shift is reloaded so the totals the home screen shows - and the numbers the
  /// close-shift dialog will read - already include what was recorded.
  Future<void> _openExpensesPage() async {
    final shift = _activeShift;
    if (shift == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CashierExpensesPage(shiftId: shift.id)),
    );
    if (mounted) await _loadShift();
  }

  Future<void> _toggleShift() async {
    final user = ref.read(authProvider);
    if (user == null) return;
    final db = ref.read(localDbProvider);
    if (_activeShift != null) {
      final shiftExpenses = await db.getShiftExpensesTotal(_activeShift!.id);
      if (!mounted) return;
      final result = await showDialog<CloseShiftResult>(
        context: context,
        builder: (_) => CloseShiftDialog(
          startedAt: _activeShift!.startedAt,
          shiftExpenses: shiftExpenses,
        ),
      );
      if (result != null) {
        await db.endShift(
          _activeShift!.id,
          DateTime.now().toIso8601String(),
          result.collected,
        );
        if (mounted) {
          // Cashier logout: keep the background server alive so waiters keep
          // syncing while the app sits at the login screen.
          logoutKeepServerRunning(db);
          await ref.read(authProvider.notifier).logout();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      }
    } else {
      final startShift = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('دەستپێکردنی شەفت')),
          content: Text(context.tr('دڵنیایت دەتەوێت شەفت دەستپێبکەیت؟')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('ڕەتکردنەوە')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('دەستپێکردن')),
            ),
          ],
        ),
      );
      if (startShift == true) {
        await db.startShift(
          CashierShift(
            cashierId: user.id,
            cashierName: user.name,
            startedAt: DateTime.now().toIso8601String(),
          ),
        );
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CashierWelcomePage()),
          );
        }
      }
    }
    _loadShift();
  }

  Color _statusColor(TableStatus status) => TableStatusVisuals.color(status);

  IconData _statusIcon(TableStatus status) => TableStatusVisuals.icon(status);

  String _statusText(TableStatus status) {
    switch (status) {
      case TableStatus.empty:
        return context.tr('بەتاڵ');
      case TableStatus.occupied:
        return context.tr('دانیشتوو');
      case TableStatus.billRequested:
        return context.tr('داوای پارەی کردووە');
      case TableStatus.overdue:
        return context.tr('دواکەوتوو');
    }
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? context.tr('د.ن') : context.tr('پ.ن');
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  Future<void> _viewDebtItems(DebtModel debt) async {
    final db = ref.read(localDbProvider);
    final orders = await db.getSettledOrdersByTableId(debt.tableId);
    if (!mounted) return;
    final order = orders.isNotEmpty ? orders.first : null;
    List<SettledOrderItem> items = [];
    if (order != null) {
      items = await db.getSettledOrderItems(order.id);
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderSide)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      color: AppColors.danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          debt.tableName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${context.tr('د.ع')} ${money(debt.amount)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('داخستن'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    context.tr('هیچ جۆرە خواردنێک تۆمار نەکراوە'),
                    style: TextStyle(color: AppColors.softText, fontSize: 14),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.borderSide),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.restaurant_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.itemName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: AppColors.darkText,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${context.tr('د.ع')} ${money(item.itemPrice)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.softText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'x${item.quantity}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.softText,
                            ),
                          ),
                          const SizedBox(width: 12),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${context.tr('د.ع')} ${money((item.itemPrice * item.quantity))}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppColors.darkText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (order != null && order.discountPercent > 0)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.05),
                  border: const Border(
                    top: BorderSide(color: AppColors.borderSide),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.discount_rounded,
                      size: 16,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${context.tr('داشکاندن')}: ${order.discountPercent}% (${context.tr('د.ع')} ${money(order.discountAmount)})',
                        style: TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _collectDebt(DebtModel debt) async {
    final collectedCtrl = TextEditingController();
    final user = ref.read(authProvider);
    final db = ref.read(localDbProvider);
    final shift = user != null ? await db.getActiveShift(user.id) : null;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final amount = collectedCtrl.text.trim().isEmpty
              ? debt.amount
              : parseAmount(collectedCtrl.text).toDouble();
          return DialogControllerOwner(
            controllers: [collectedCtrl],
            child: AlertDialog(
              title: Text(context.tr('کۆکردنەوەی قەرز')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('قەرزی سەرەتا'),
                          style: TextStyle(color: AppColors.softText),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${context.tr('د.ع')} ${money(debt.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: collectedCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [AmountInputFormatter()],
                      decoration: InputDecoration(
                        labelText:
                            '${context.tr('بڕی وەرگیراو')} (${context.tr('د.ع')})',
                        hintText: money(debt.amount),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('کۆی گشتی'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${context.tr('د.ع')} ${money(amount)}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.tr('ڕەتکردنەوە')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.tr('کۆکردنەوە')),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      final amount = collectedCtrl.text.trim().isEmpty
          ? debt.amount
          : parseAmount(collectedCtrl.text).toDouble();
      final now = DateTime.now().toIso8601String();
      await db.db.insert('settled_orders', {
        'tableId': debt.tableId,
        'tableName': '${debt.tableName} (${context.tr('قەرز')})',
        'totalAmount': amount,
        'discountPercent': 0,
        'discountAmount': 0,
        'settledAt': now,
        'settledBy': user?.id ?? 0,
        'shiftId': shift?.id ?? 0,
        'waiterId': '',
        'seatedAt': '',
        'paymentMethod': 'debt',
      });
      if (amount >= debt.amount) {
        await db.deleteDebt(debt.id);
      } else {
        await db.updateDebtAmount(debt.id, debt.amount - amount);
      }
      setState(() {});
    }
  }

  /// Opens «داواکاری پێشوو»: the tables settled in the running shift, and the
  /// dishes each visit closed, so the cashier can answer "what did this table
  /// have last time?".
  ///
  /// This used to be a bottom sheet of the last 30 settlements with no dishes on
  /// it at all - a receipt list that could not answer the question the button's
  /// own label asks. The page groups by table and scopes itself to the open
  /// shift, because the shift is the cashier's own book.
  void _openPreviousOrders() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CashierPreviousOrdersPage(shiftId: _activeShift?.id ?? -1),
      ),
    );
  }

  Future<int?> _showGuestCountDialog() async {
    int count = 1;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('ژمارەی میوان')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.tr('ژمارەی کەسەکان بنووسە')),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: count > 1
                            ? () => setDialogState(() => count--)
                            : null,
                        icon: const Icon(Icons.remove_rounded),
                        iconSize: 22,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton.filled(
                        onPressed: () => setDialogState(() => count++),
                        icon: const Icon(Icons.add_rounded),
                        iconSize: 22,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('ڕەتکردنەوە')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, count),
              child: Text(context.tr('دەستپێکردن')),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Widget _buildOrdersTab() {
    final notifsAsync = ref.watch(tableNotificationsProvider);
    final isPhone = Responsive.isPhone(context);

    return notifsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (notifs) {
        return Column(
          children: [
            Expanded(
              child: isPhone
                  ? Column(
                      children: [
                        Expanded(flex: 3, child: _notificationsPanel(notifs)),
                        const SizedBox(height: 12),
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                const DollarRateBanner(),
                                const SizedBox(height: 12),
                                const CurrencyConverter(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 2, child: _notificationsPanel(notifs)),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                const DollarRateBanner(),
                                const SizedBox(height: 12),
                                const CurrencyConverter(),
                              ],
                            ),
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

  /// Opens a table the captain rang the bell for.
  ///
  /// The bell means a captain is standing at that table, so the cashier is told
  /// who before going in. The bell is not consumed here: the table page clears
  /// it when the cashier actually reaches the table, so a cashier who backs out
  /// of the hold screen leaves the call where it was instead of silently
  /// swallowing a captain who is still waiting.
  Future<void> _openNotifiedTable(TableNotification n) async {
    final db = ref.read(localDbProvider);

    final table = await db.getTable(n.tableId);
    if (!mounted) return;
    if (table == null) {
      // The table is gone, so the bell has nothing left to point at.
      await db.clearTableNotifications(n.tableId);
      ref.invalidate(tableNotificationsProvider);
      return;
    }

    final held = await _captainHolding(table.id);
    if (!mounted) return;
    if (held != null) {
      final ejected = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CashierTableHoldPage(table: table, lock: held),
        ),
      );
      if (!mounted) return;
      if (ejected != true) return;
    }

    if (!mounted) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CashierUnifiedTablePage(tableNumber: n.tableId, initialTab: 0),
      ),
    );
    // The table page consumes the bell on entry, so the list is brought back in
    // step with what is actually left to answer.
    ref.invalidate(tableNotificationsProvider);
    if (result == true && mounted) {
      await ref.read(waiterProvider.notifier).refresh();
    }
  }

  /// The captain currently working a table, or null when it is free.
  ///
  /// A cashier holding the table is not a hold: cashiers work every table and
  /// are not kept out of one another, so only a captain stops the cashier.
  Future<TableLock?> _captainHolding(int tableId) async {
    final lock = await ref.read(localDbProvider).getTableLockById(tableId);
    if (lock == null) return null;
    if (lock.role != 'waiter') return null;
    final me = ref.read(authProvider)?.id;
    if (lock.userId == me) return null;
    return lock;
  }

  Widget _notificationsPanel(List<TableNotification> notifs) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSide)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('ئاگەدارکردنەوەی مێز'),
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
                // The counter only appears once there is something to count.
                // A permanent "0 ئاگەدارکردنەوە" chip is a number on the tab
                // that nobody asked for, and it trains the cashier to read the
                // number as decoration rather than as somebody waiting.
                if (notifs.isNotEmpty) ...[
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        key: const ValueKey('notificationCount'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          context.trp('{count} ئاگەدارکردنەوە', {
                            'count': '${notifs.length}',
                          }),
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: notifs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_off_rounded,
                          size: 48,
                          color: AppColors.softText,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('هیچ ئاگەدارکردنەوەیەک نییە'),
                          style: const TextStyle(color: AppColors.softText),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: notifs.length,
                    itemBuilder: (_, index) {
                      final n = notifs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openNotifiedTable(n),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _statusColor(
                                      n.status,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${n.tableId}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _statusColor(n.status),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        n.tableName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${n.formattedOpenedAmPm(am: context.tr('پ.ن'), pm: context.tr('د.ن'))}  ·  ${_statusText(n.status)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _statusColor(n.status),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        context.tr('بینین'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
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

  Widget _buildTableFilterBar() {
    final tables = ref.watch(waiterProvider).asData?.value ?? <TableModel>[];
    final occupiedCount = tables
        .where(
          (t) =>
              t.status == TableStatus.occupied ||
              t.status == TableStatus.billRequested ||
              t.status == TableStatus.overdue,
        )
        .length;
    final emptyCount = tables
        .where((t) => t.status == TableStatus.empty)
        .length;

    Widget segment(
      _TableFilterOption opt,
      String label,
      Color color,
      IconData icon, {
      int? count,
    }) {
      final selected = _tableFilter == opt;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            // The delivery segment is an entry point to its own page rather
            // than a table-status filter.
            if (opt == _TableFilterOption.delivery) {
              _openDeliveryPage();
              return;
            }
            setState(() => _tableFilter = opt);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.12) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : AppColors.borderSide,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? color : AppColors.softText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: selected ? color : AppColors.darkText,
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: selected ? 0.9 : 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.white : color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.paddingSmall,
        10,
        AppConstants.paddingSmall,
        4,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderSide)),
      ),
      child: Row(
        children: [
          segment(
            _TableFilterOption.all,
            context.tr('هەموو مێزەکان'),
            AppColors.primary,
            Icons.grid_view_rounded,
            count: tables.length,
          ),
          const SizedBox(width: 10),
          segment(
            _TableFilterOption.occupied,
            context.tr('مێزە گیراوەکان'),
            AppColors.success,
            Icons.chair_rounded,
            count: occupiedCount,
          ),
          const SizedBox(width: 10),
          segment(
            _TableFilterOption.empty,
            context.tr('مێزە بەتاڵەکان'),
            AppColors.softText,
            Icons.table_restaurant_rounded,
            count: emptyCount,
          ),
          const SizedBox(width: 10),
          segment(
            _TableFilterOption.delivery,
            context.tr('دلیڤەری'),
            AppColors.blue,
            Icons.delivery_dining_rounded,
          ),
        ],
      ),
    );
  }

  Future<void> _openDeliveryPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DeliveryPage()));
  }

  Widget _buildMainTab() {
    final tablesAsync = ref.watch(waiterProvider);
    final waiterNamesAsync = ref.watch(waiterNamesProvider);

    return tablesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (tables) {
        final waiterNames = waiterNamesAsync.asData?.value ?? <int, String>{};
        final filtered = switch (_tableFilter) {
          _TableFilterOption.all => tables,
          _TableFilterOption.occupied =>
            tables
                .where(
                  (t) =>
                      t.status == TableStatus.occupied ||
                      t.status == TableStatus.billRequested ||
                      t.status == TableStatus.overdue,
                )
                .toList(),
          _TableFilterOption.empty =>
            tables.where((t) => t.status == TableStatus.empty).toList(),
          _TableFilterOption.delivery => tables,
        };
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.paddingSmall,
                  0,
                  AppConstants.paddingSmall,
                  AppConstants.paddingSmall,
                ),
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          switch (_tableFilter) {
                            _TableFilterOption.occupied => context.tr(
                              'هیچ مێزێکی گیراو نییە',
                            ),
                            _TableFilterOption.empty => context.tr(
                              'هیچ مێزێکی بەتاڵ نییە',
                            ),
                            _TableFilterOption.all => context.tr(
                              'هیچ مێزێکی چالاک نییە',
                            ),
                            _TableFilterOption.delivery => context.tr(
                              'هیچ مێزێکی چالاک نییە',
                            ),
                          },
                          style: TextStyle(
                            color: AppColors.softText,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ResponsiveGridView(
                        desktopColumns: 6,
                        tabletColumns: 4,
                        mobileColumns: 2,
                        spacing: 12,
                        runSpacing: 12,
                        childAspectRatio: 1.0,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final table = filtered[index];
                          final color = _statusColor(table.status);
                          final waiterName = table.createdBy > 0
                              ? waiterNames[table.createdBy]
                              : null;
                          return TableCard(
                            table: table,
                            statusColor: color,
                            statusText: _statusText(table.status),
                            statusIcon: _statusIcon(table.status),
                            index: index,
                            subtitle: waiterName,
                            onTap: () => _openTableFromGrid(table),
                            onLongPress: () async {
                              final action = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(context.tr('بەڕێوەبردنی مێز')),
                                  content: ListTile(
                                    leading: const Icon(
                                      Icons.delete_rounded,
                                      color: AppColors.danger,
                                    ),
                                    title: Text(
                                      context.tr('سڕینەوەی مێز'),
                                      style: TextStyle(color: AppColors.danger),
                                    ),
                                    onTap: () => Navigator.pop(ctx, 'delete'),
                                  ),
                                ),
                              );
                              if (action == 'delete') {
                                if (!context.mounted) return;
                                final db = ref.read(localDbProvider);
                                final user = ref.read(authProvider);
                                final openFood = await db.getOrderItems(
                                  table.id,
                                );
                                if (!context.mounted) return;
                                if (openFood.isNotEmpty) {
                                  // A table with food on it can never be deleted:
                                  // tell the cashier why and leave everything alone.
                                  await showDialog<void>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(
                                        ctx.tr('سڕینەوەی مێز'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      content: Text(
                                        ctx.tr(
                                          'ناتوانیت مێز بسڕیتەوە چونکە خواردن لەناو مێزەکەدایە. سەرەتا حیسابەکە واسڵ بکە یان خواردنەکە بۆ مێزێکی تر بگوازەوە.',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: Text(ctx.tr('باشە')),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }
                                await db.deleteTable(
                                  table.id,
                                  cancelledBy: user?.id ?? 0,
                                  cancelledByName: user?.name ?? '',
                                );
                                await ref
                                    .read(waiterProvider.notifier)
                                    .refresh();
                              }
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Opens a table from the cashier's own grid.
  ///
  /// The same hold screen stands in front of this path as in front of the bell
  /// queue, because a captain at the table is a captain at the table however
  /// the cashier arrived - otherwise walking over from the grid would be the
  /// way around the check.
  Future<void> _openTableFromGrid(TableModel table) async {
    final held = await _captainHolding(table.id);
    if (!mounted) return;
    if (held != null) {
      final ejected = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CashierTableHoldPage(table: table, lock: held),
        ),
      );
      if (!mounted) return;
      if (ejected != true) return;
      await ref.read(waiterProvider.notifier).refreshSilent();
    }

    if (!mounted) return;
    final isEmpty = table.status == TableStatus.empty;
    int? guestCount = table.guestCount;
    if (isEmpty) {
      guestCount = await _showGuestCountDialog();
      if (guestCount == null || !mounted) return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CashierUnifiedTablePage(
          tableNumber: table.id,
          initialGuestCount: guestCount ?? 1,
          initialTab: isEmpty ? 1 : 0,
        ),
      ),
    );
    if (result == true && mounted) {
      await ref.read(waiterProvider.notifier).refresh();
    }
  }

  Widget _buildDebtsTab() {
    final isPhone = Responsive.isPhone(context);
    // Debts are scoped to the shift that opened them: once the cashier closes
    // their shift (or a new one starts), the list is empty. The record itself
    // survives on the admin's «قەرزەکان» page. With no open shift there is no
    // list to show, so the query is sentineled to a shift id that cannot exist.
    final shiftId = _activeShift?.id ?? -1;
    return FutureBuilder<List<DebtModel>>(
      future: ref.read(localDbProvider).getDebtsByShift(shiftId),
      builder: (context, snapshot) {
        final debts = snapshot.data ?? [];
        final totalDebt = debts.fold<double>(0, (sum, d) => sum + d.amount);

        return Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: isPhone
              ? Column(
                  children: [
                    SizedBox(
                      height: 170,
                      child: _debtSummary(totalDebt, debts.length),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _debtListPanel(debts)),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 2, child: _debtListPanel(debts)),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 1,
                      child: _debtSummary(totalDebt, debts.length),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _debtListPanel(List<DebtModel> debts) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSide)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bookmark_rounded,
                  color: AppColors.danger,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('قەرزەکان'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        context.trp('{count} قەرز', {
                          'count': '${debts.length}',
                        }),
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: debts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bookmark_border_rounded,
                          size: 48,
                          color: AppColors.softText,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('هیچ قەرزێک نییە'),
                          style: const TextStyle(color: AppColors.softText),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: debts.length,
                    itemBuilder: (context, index) {
                      final debt = debts[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _viewDebtItems(debt),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.bookmark_rounded,
                                      color: AppColors.danger,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        debt.tableName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        debt.reason.isNotEmpty
                                            ? debt.reason
                                            : context.tr('بێ هۆکار'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.softText,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        _formatTime(debt.createdAt),
                                        style: const TextStyle(
                                          color: AppColors.softText,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '${context.tr('د.ع')} ${money(debt.amount)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.danger,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _collectDebt(debt),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.payments_rounded,
                                      size: 18,
                                      color: AppColors.success,
                                    ),
                                  ),
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

  Widget _debtSummary(double totalDebt, int count) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('پوختەی قەرز'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 16),
          const Icon(Icons.bookmark_rounded, size: 44, color: AppColors.danger),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${context.tr('د.ع')} ${money(totalDebt)}',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: AppColors.danger,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.trp('{count} قەرز', {'count': '$count'}),
            style: const TextStyle(fontSize: 15, color: AppColors.softText),
          ),
        ],
      ),
    );
  }

  Widget _appBarButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed, {
    int? badgeCount,
  }) {
    Widget iconWidget = Icon(icon, size: 16, color: color);
    if (badgeCount != null && badgeCount > 0) {
      iconWidget = Badge(
        label: Text(
          '$badgeCount',
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.danger,
        child: iconWidget,
      );
    }
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        // 40px floor + vertical centering: the old v:2 padding produced a
        // ~19px-high target, which is easy to miss and far under the touch
        // guidelines on every platform.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  iconWidget,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShiftButton() {
    if (_activeShift == null) {
      return _appBarButton(
        context.tr('دەستپێکردنی شەفت'),
        Icons.play_circle_outline_rounded,
        AppColors.primary,
        _toggleShift,
      );
    }
    final shift = _activeShift!;
    // Parsed through `_formatTime`, not sliced: `substring(0, 10)` throws a
    // RangeError on any stored value shorter than 19 chars.
    final started = _formatTime(shift.startedAt);
    return Material(
      color: AppColors.success.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _toggleShift,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('داخستن و چوونە دەرەوە'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    started,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.success.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.timeline_rounded,
                size: 22,
                color: AppColors.success,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatus() {
    return Consumer(
      builder: (context, ref, _) {
        final syncState = ref.watch(syncConnectionProvider);
        final connected = syncState.connected;
        final count = syncState.clientCount ?? 0;
        final color = connected ? AppColors.success : AppColors.danger;
        return Tooltip(
          message: connected
              ? 'Server: ${syncState.serverIp ?? ""} | $count client(s)'
              : 'Disconnected',
          child: Material(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _showConnectedDevices,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      size: 14,
                      color: color,
                    ),
                    if (connected && count > 0) ...[
                      const SizedBox(width: 3),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens the list of devices currently joined to this cashier's server, so
  /// the cashier can see which captain (and which device) is connected.
  Future<void> _showConnectedDevices() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ConnectedDevicesDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final cashierName = user?.name.trim() ?? '';
    final cashierTitle =
        (user?.role == UserRole.cashier && cashierName.isNotEmpty)
        ? '${context.tr('کاشێر')} $cashierName'
        : context.tr('کاشێر');
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        // «زیادکردنی مێز» is pulled out of the action cluster and pinned before
        // the cashier icon/name, so it is read first and stands apart from the
        // scrollable row of action buttons.
        leadingWidth: 132,
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: _appBarButton(
                context.tr('زیادکردنی مێز'),
                Icons.add_box_rounded,
                AppColors.success,
                _showAddTableDialog,
              ),
            ),
          ),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                cashierTitle,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.darkText,
                ),
              ),
            ],
          ),
        ),
        centerTitle: false,
        actions: [
          ScrollableAppBarActions(
            children: [
              // The live connection badge leads the action row, immediately
              // before the shift (close & logout) button, so the cashier sees
              // the connection state first. Tapping it opens the
              // connected-devices list.
              _buildSyncStatus(),
              const SizedBox(width: 2),
              _buildShiftButton(),
              if (_activeShift != null) ...[
                const SizedBox(width: 2),
                _appBarButton(
                  context.tr('خەرجیەکان'),
                  Icons.account_balance_wallet_rounded,
                  AppColors.danger,
                  _openExpensesPage,
                ),
              ],
              const SizedBox(width: 2),
              _appBarButton(
                context.tr('ڕێفرێش'),
                Icons.refresh_rounded,
                AppColors.primary,
                () async {
                  await ref.read(localDbProvider).checkOverdueTables();
                  ref.read(waiterProvider.notifier).refreshSilent();
                },
              ),
              const SizedBox(width: 2),
              _appBarButton(
                context.tr('داواکاری پێشوو'),
                Icons.receipt_rounded,
                AppColors.blue,
                _openPreviousOrders,
              ),
              const SizedBox(width: 2),
              // A live count of the dishes still sitting in «ڕەتکراوەکان», so the
              // cashier sees at a glance that something was thrown out and has
              // not been put back, without having to open the page. The button is
              // its own Consumer so only it repaints when the queue moves, not the
              // whole till.
              Consumer(
                builder: (context, ref, _) {
                  final count =
                      ref
                          .watch(pendingCancelledItemsProvider)
                          .asData
                          ?.value
                          .length ??
                      0;
                  return _appBarButton(
                    context.tr('ڕەتکراوەکان'),
                    Icons.block_rounded,
                    AppColors.danger,
                    () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CashierCancelledItemsPage(),
                        ),
                      );
                    },
                    badgeCount: count,
                  );
                },
              ),
              const SizedBox(width: 2),
              ProfileIcon(user: ref.watch(authProvider)),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTableFilterBar(),
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [_buildMainTab(), _buildOrdersTab(), _buildDebtsTab()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSide)),
        ),
        child: Consumer(
          builder: (context, ref, _) {
            // The number on «داواکاری» counts ONLY what a captain asked for by
            // pressing the 🔔 «ئاگەدارکردنەوە» button on that table. It used to
            // count tables that had sent their bill, which put a number on the
            // tab on its own the moment «ناردن بۆ کاشێر» was pressed - and that
            // is not a request for the cashier, it is the bill doing its job. A
            // number that appears without anyone ringing means the number can no
            // longer be trusted, so the tab now reads the bell queue and nothing
            // else: 0 stays bare until a captain rings.
            final bellCount =
                ref.watch(tableNotificationsProvider).value?.length ?? 0;
            return BottomNavigationBar(
              currentIndex: _currentTab,
              onTap: (index) => setState(() => _currentTab = index),
              backgroundColor: Colors.white,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.softText,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.table_restaurant_rounded),
                  label: context.tr('سەرەکی'),
                ),
                BottomNavigationBarItem(
                  icon: bellCount > 0
                      ? Badge(
                          label: Text(
                            '$bellCount',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: const Icon(Icons.receipt_long_rounded),
                        )
                      : const Icon(Icons.receipt_long_rounded),
                  label: context.tr('داواکاری'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.bookmark_rounded),
                  label: context.tr('قەرزەکان'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The list the cashier sees after tapping the Wi-Fi badge: every device that
/// is currently joined to this (server) device, with the captain's name, the
/// role, the device and its address, and when it connected.
///
/// It reads the live socket sessions, so the list updates by itself while the
/// dialog stays open.
class _ConnectedDevicesDialog extends ConsumerStatefulWidget {
  const _ConnectedDevicesDialog();

  @override
  ConsumerState<_ConnectedDevicesDialog> createState() =>
      _ConnectedDevicesDialogState();
}

class _ConnectedDevicesDialogState
    extends ConsumerState<_ConnectedDevicesDialog> {
  List<ConnectedClient> _clients = const [];
  Map<int, String> _names = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadNames();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final clients = connectedClients();
    setState(() => _clients = clients);
    // A captain we have never named before just joined: pull the account names
    // again so the row can show a person instead of a role.
    if (clients.any((c) => !_names.containsKey(c.userId))) {
      _loadNames();
    }
  }

  Future<void> _loadNames() async {
    try {
      final users = await ref.read(localDbProvider).getAllUsers();
      if (!mounted) return;
      setState(() {
        _names = {for (final u in users) u.id: u.name};
      });
    } catch (_) {
      // Names are a nicety - the list still works with the role shown.
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'waiter':
        return context.tr('کاپتن');
      case 'cashier':
        return context.tr('کاشێر');
      case 'admin':
        return context.tr('ئادمێن');
      case 'owner':
        return context.tr('خاوەن سیستەم');
      default:
        return role;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'waiter':
        return Icons.room_service_rounded;
      case 'cashier':
        return Icons.point_of_sale_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'owner':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'waiter':
        return AppColors.blue;
      case 'cashier':
        return AppColors.success;
      case 'admin':
        return AppColors.primary;
      case 'owner':
        return const Color(0xFF7C4DFF);
      default:
        return AppColors.softText;
    }
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hhmm = '${two(t.hour)}:${two(t.minute)}';
    return sameDay ? hhmm : '${two(t.month)}/${two(t.day)} $hhmm';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = screenWidth < 440 ? screenWidth - 88 : 380.0;
    final hasServer = syncServer?.isRunning ?? false;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 8),
      contentPadding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.wifi_rounded,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('ئامێرە بەستراوەکان'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: !hasServer
            ? _message(
                Icons.power_off_rounded,
                context.tr('ئەم ئامێرە سێرڤەر نییە'),
              )
            : _clients.isEmpty
            ? _message(
                Icons.wifi_off_rounded,
                context.tr('هیچ ئامێرێک بەستراو نییە'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.trp('{count} ئامێر بەستراوە', {
                      'count': '${_clients.length}',
                    }),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.softText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 330),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _clients.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _clientTile(_clients[i]),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('داخستن')),
        ),
      ],
    );
  }

  Widget _message(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 42,
            color: AppColors.softText.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.softText),
          ),
        ],
      ),
    );
  }

  Widget _clientTile(ConnectedClient client) {
    final name = _names[client.userId]?.trim() ?? '';
    final title = name.isNotEmpty ? name : _roleLabel(client.role);
    final device = client.deviceName.trim();
    final color = _roleColor(client.role);
    final address = device.isEmpty ? client.ip : '$device · ${client.ip}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(_roleIcon(client.role), color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _roleLabel(client.role),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.softText,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: AppColors.softText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${context.tr('بەستراوی لە')} ${_fmtTime(client.connectedAt)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.softText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
