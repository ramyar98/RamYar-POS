import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/fmt.dart';
import '../../database/local_db.dart';
import '../../services/app_localizations.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/dialog_controller_owner.dart';
import '../admin/payment_method_style.dart' show formatShiftTime;

/// Accent for «خەرجی» (money taken out of the drawer).
const Color _expenseAccent = Color(0xFFFF6B35);

/// «خەرجیەکان» — the cashier's ledger for the shift that is open.
///
/// One table (`cashier_expenses`) holds both halves of the ledger: an expense
/// (money taken out of the drawer) is stored with a **positive** price and a
/// return (money put back) with a **negative** one. The page mirrors that split
/// with two sections under the app bar — «خەرجی» and «گەڕانەوەی خەرجی» — so the
/// cashier records a cost, sees it listed, and can put the same amount back with
/// one tap: the replay button on an expense row reopens the return form
/// pre-filled with the same name and amount, and the money goes straight back.
///
/// Nothing here is cashier-only bookkeeping. Every row is written through
/// `addCashierExpense`, which attaches the device-independent shift key and
/// emits a mutation, so the admin's «حسابەکان» and the shift report read the
/// exact same money — how much came out, how much went back, and what it was
/// for.
class CashierExpensesPage extends ConsumerStatefulWidget {
  const CashierExpensesPage({super.key, required this.shiftId});

  /// The open shift whose ledger this page edits.
  final int shiftId;

  @override
  ConsumerState<CashierExpensesPage> createState() =>
      _CashierExpensesPageState();
}

class _CashierExpensesPageState extends ConsumerState<CashierExpensesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<List<Map<String, dynamic>>> _future;
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // The FAB and the section accents follow the selected tab. Rebuilding on
    // every frame of the slide is cheap here (two short lists) and keeps the
    // action in step with the finger during a swipe.
    if (mounted) setState(() {});
  }

  void _load() {
    _future = ref.read(localDbProvider).getShiftExpenses(widget.shiftId);
  }

  Future<void> _reload() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final returns = _tab.index == 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: _searching ? _searchField(context) : _title(context),
        actions: _actions(context),
        bottom: TabBar(
          controller: _tab,
          onTap: (_) => setState(() {}),
          labelColor: AppColors.darkText,
          unselectedLabelColor: AppColors.softText,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.money_off_csred_rounded, size: 18),
              text: context.tr('خەرجی'),
            ),
            Tab(
              icon: const Icon(Icons.replay_rounded, size: 18),
              text: context.tr('گەڕانەوەی خەرجی'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: returns
            ? () => _openLedgerDialog(returns: true)
            : () => _openLedgerDialog(returns: false),
        backgroundColor: returns ? AppColors.blue : _expenseAccent,
        foregroundColor: Colors.white,
        icon: Icon(returns ? Icons.replay_rounded : Icons.add_rounded),
        label: Text(
          context.tr(returns ? 'گەڕانەوەی خەرجی' : 'تۆمارکردنی خەرجی'),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ledger(context, returns: false),
          _ledger(context, returns: true),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _expenseAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.account_balance_wallet_rounded,
          color: _expenseAccent,
          size: 18,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          context.tr('خەرجیەکان'),
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
  );

  Widget _searchField(BuildContext context) => TextField(
    controller: _searchCtrl,
    autofocus: true,
    textInputAction: TextInputAction.search,
    onChanged: (_) => setState(() {}),
    style: const TextStyle(fontSize: 15, color: AppColors.darkText),
    decoration: InputDecoration(
      hintText: context.tr('گەڕان بە ناوی خەرجی'),
      border: InputBorder.none,
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.softText),
    ),
  );

  List<Widget> _actions(BuildContext context) {
    if (_searching) {
      return [
        IconButton(
          tooltip: context.tr('ڕەتکردنەوە'),
          icon: const Icon(Icons.close_rounded, color: AppColors.darkText),
          onPressed: () => setState(() {
            _searching = false;
            _searchCtrl.clear();
          }),
        ),
      ];
    }
    return [
      IconButton(
        tooltip: context.tr('گەڕان'),
        icon: const Icon(Icons.search_rounded, color: AppColors.darkText),
        onPressed: () => setState(() => _searching = true),
      ),
      IconButton(
        tooltip: context.tr('ڕێفرێش'),
        icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
        onPressed: _reload,
      ),
    ];
  }

  // ==================== Ledger ====================

  Widget _ledger(BuildContext context, {required bool returns}) {
    final accent = returns ? AppColors.blue : _expenseAccent;
    final icon = returns ? Icons.replay_rounded : Icons.money_off_csred_rounded;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final query = _searchCtrl.text.trim().toLowerCase();
        final rows =
            (snapshot.data ?? const <Map<String, dynamic>>[])
                .where(
                  (e) => returns
                      ? (e['price'] as num) < 0
                      : (e['price'] as num) > 0,
                )
                .where((e) => _matches(e, query))
                .toList()
              ..sort(
                (a, b) => (b['createdAt'] ?? '').toString().compareTo(
                  (a['createdAt'] ?? '').toString(),
                ),
              );
        return RefreshIndicator(
          onRefresh: _reload,
          child: rows.isEmpty
              ? _empty(context, returns, icon, query.isNotEmpty)
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppConstants.paddingMedium,
                    AppConstants.paddingMedium,
                    AppConstants.paddingMedium,
                    96,
                  ),
                  children: [
                    _summary(context, rows, accent, icon, returns),
                    const SizedBox(height: 12),
                    ...rows.map((e) => _row(context, e, accent, icon, returns)),
                  ],
                ),
        );
      },
    );
  }

  bool _matches(Map<String, dynamic> e, String query) {
    if (query.isEmpty) return true;
    final name = (e['itemName'] ?? '').toString().toLowerCase();
    if (name.contains(query)) return true;
    final amount = money((e['price'] as num).abs());
    return amount.toLowerCase().contains(query) ||
        amount.replaceAll(',', '').contains(query.replaceAll(',', ''));
  }

  Widget _empty(
    BuildContext context,
    bool returns,
    IconData icon,
    bool searching,
  ) {
    final label = searching
        ? context.tr('هیچ ئەنجامێک نەدۆزرایەوە')
        : context.tr(returns ? 'هیچ گەڕانەوەی خەرجی نییە' : 'هیچ خەرجییەک نییە');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppConstants.paddingMedium),
      children: [
        const SizedBox(height: 64),
        Icon(icon, size: 72, color: AppColors.softText.withValues(alpha: 0.3)),
        const SizedBox(height: 12),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: AppColors.softText),
        ),
      ],
    );
  }

  Widget _summary(
    BuildContext context,
    List<Map<String, dynamic>> rows,
    Color accent,
    IconData icon,
    bool returns,
  ) {
    final total = rows.fold<double>(
      0,
      (sum, e) => sum + (e['price'] as num).abs().toDouble(),
    );
    final label = context.tr(
      returns ? 'کۆی گەڕانەوەی خەرجی' : 'کۆی خەرجیەکان',
    );
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
                  '$label (${rows.length})',
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

  Widget _row(
    BuildContext context,
    Map<String, dynamic> expense,
    Color accent,
    IconData icon,
    bool returns,
  ) {
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
                          '${context.tr('کات')}: ${formatShiftTime(createdAt)}',
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
          const SizedBox(width: 8),
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
          // An expense can be handed straight back: the replay button opens the
          // return form pre-filled with this row, so 20,000 typed out earlier
          // goes back the same 20,000 with one tap.
          if (!returns)
            IconButton(
              tooltip: context.tr('گەڕاندنەوەی ئەم خەرجییە'),
              icon: const Icon(
                Icons.replay_rounded,
                color: AppColors.blue,
                size: 20,
              ),
              onPressed: () => _openLedgerDialog(returns: true, prefill: expense),
            ),
        ],
      ),
    );
  }

  // ==================== Add / return ====================

  Future<void> _openLedgerDialog({
    required bool returns,
    Map<String, dynamic>? prefill,
  }) async {
    final nameCtrl = TextEditingController(
      text: (prefill?['itemName'] ?? '').toString(),
    );
    final priceCtrl = TextEditingController(
      text: prefill == null ? '' : money((prefill['price'] as num).abs()),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogControllerOwner(
        controllers: [nameCtrl, priceCtrl],
        child: AlertDialog(
          title: Text(
            context.tr(returns ? 'گەڕانەوەی خەرجی' : 'تۆمارکردنی خەرجی'),
          ),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: _fieldDecoration(context.tr('ناوی خەرجی')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [AmountInputFormatter()],
                    decoration: _fieldDecoration(
                      '${context.tr('نرخ')} (${context.tr('د.ع')})',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('ڕەتکردنەوە')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: returns ? AppColors.blue : _expenseAccent,
              ),
              child: Text(
                context.tr(returns ? 'گەڕاندنەوەی خەرجی' : 'تۆمارکردن'),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    final name = nameCtrl.text.trim();
    final price = parseAmount(priceCtrl.text).toDouble();
    if (name.isEmpty || price <= 0) return;
    await ref
        .read(localDbProvider)
        .addCashierExpense(widget.shiftId, name, returns ? -price : price);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    // A return belongs on the returns side, so show it there straight away.
    if (returns && _tab.index != 1) _tab.animateTo(1);
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
