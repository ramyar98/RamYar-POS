import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../database/local_db.dart';
import '../../models/table_lock_model.dart';
import '../../models/table_model.dart';
import '../../services/app_localizations.dart';

/// Full-screen stand between the cashier and a table a captain is working.
///
/// The cashier has every table at their disposal, so nothing here is a
/// permission wall - it is a "this table is not yours right now" wall. It
/// answers the only question that matters at the moment a bill is waiting: who
/// is standing at this table? The captain's name is on screen in full, with
/// the running bill, and the way forward is to take the table off them. There
/// is no way past this page, because walking into a table another captain is
/// serving is exactly the collision the lock exists to prevent.
class CashierTableHoldPage extends ConsumerStatefulWidget {
  const CashierTableHoldPage({super.key, required this.table, required this.lock});

  final TableModel table;
  final TableLock lock;

  @override
  ConsumerState<CashierTableHoldPage> createState() => _CashierTableHoldPageState();
}

class _CashierTableHoldPageState extends ConsumerState<CashierTableHoldPage> {
  bool _ejecting = false;

  bool get _isCaptain => widget.lock.role == 'waiter';

  /// How long this captain has had the table, phrased for a person rather than
  /// a stopwatch.
  String get _heldFor {
    final held = DateTime.now().difference(widget.lock.lockedAt);
    if (held.inMinutes >= 60) {
      final h = held.inHours;
      return context.trp('{h} کاتژمێر', {'h': '$h'});
    }
    if (held.inMinutes >= 1) {
      return context.trp('{m} خولەک', {'m': '${held.inMinutes}'});
    }
    return context.tr('چەند چرکەیەک');
  }

  Future<void> _eject() async {
    if (_ejecting) return;
    setState(() => _ejecting = true);
    final db = ref.read(localDbProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await db.ejectCaptainFromTable(widget.table.id);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(context.trp('{name} لە مێزی {table} دەرکرایتەوە', {
          'name': widget.lock.userName,
          'table': widget.table.name,
        })),
        backgroundColor: AppColors.success,
      ));
      // The bill is untouched, so the cashier walks straight into the table to
      // settle it.
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ejecting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('دەرکردن سەرکەوتوو نەبوو، دووبارە هەوڵ بدەوە')),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  void _back() {
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < 600;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _back,
            tooltip: context.tr('گەڕانەوە'),
          ),
          title: Text(context.tr('مێز بەسەردەستە'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        // The eject button is the only way into this table, so it is pinned
        // rather than left at the end of a scroll. The phone this runs on is
        // used in landscape (914x411 logical), and a button that scrolls below
        // the fold on that screen is a button nobody finds.
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      AppConstants.paddingLarge, AppConstants.paddingLarge, AppConstants.paddingLarge, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(isPhone),
                          const SizedBox(height: AppConstants.paddingLarge),
                          _captainCard(),
                          const SizedBox(height: AppConstants.paddingLarge),
                          _billCard(),
                          const SizedBox(height: AppConstants.paddingMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool isPhone) {
    return Column(
      children: [
        Container(
          width: isPhone ? 84 : 104,
          height: isPhone ? 84 : 104,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isCaptain ? Icons.person_pin_rounded : Icons.lock_person_rounded,
            size: isPhone ? 44 : 56,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.trp('مێزی {name} لەلایەن کاپتنەوە گرتەیەتەوە', {'name': widget.table.name}),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isPhone ? 20 : 26,
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('بۆ ئەوەی بچیتە ناو مێزەکە، پێویستە کاپتنەکە لە مێزەکە دەربکەیت'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: isPhone ? 14 : 16, color: AppColors.softText, height: 1.6),
        ),
      ],
    );
  }

  Widget _captainCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_rounded, size: 18, color: AppColors.softText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(context.tr('کاپتنی مێزەکە'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.softText, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The name is the whole point of this screen, so it is the largest
          // thing on it.
          Text(
            widget.lock.userName.isEmpty ? context.tr('ناسەرەوە') : widget.lock.userName,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.darkText),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                icon: _isCaptain ? Icons.person_rounded : Icons.point_of_sale_rounded,
                label: _isCaptain ? context.tr('کاپتن') : context.tr('کاشێر'),
                color: AppColors.primary,
              ),
              _chip(
                icon: Icons.schedule_rounded,
                label: context.trp('لە {time}ەوە', {'time': _heldFor}),
                color: AppColors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          // A long held-time label ("لە چەند چرکەیەکەوە") must shrink inside
          // the chip instead of pushing the Row past the Wrap's lane width on
          // a 320px phone.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _billCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14)],
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
              icon: Icons.groups_rounded,
              label: context.tr('میوان'),
              value: '${widget.table.guestCount}',
            ),
          ),
          Container(width: 1, height: 42, color: AppColors.borderSide),
          Expanded(
            child: _stat(
              icon: Icons.payments_rounded,
              label: context.tr('کۆی گشتی'),
              value: _money(widget.table.totalAmount),
              valueColor: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.softText),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor ?? AppColors.darkText)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.softText)),
      ],
    );
  }

  String _money(double amount) {
    final text = amount.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return '${buffer.toString()} IQD';
  }

  Widget _actions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppConstants.paddingLarge, AppConstants.paddingMedium, AppConstants.paddingLarge, AppConstants.paddingMedium),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderSide)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // One button, no way past. The bill survives the eject, so taking
              // the table is never destructive - it just ends whose table it is.
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed: _ejecting ? null : _eject,
                  icon: _ejecting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      // Fixed at the size of the icon it replaces: a spinner
                      // that grows the row makes the button jump under the
                      // cashier's thumb at the exact moment they press it again.
                      : const SizedBox(
                          width: 24,
                          height: 24,
                          child: Icon(Icons.person_remove_rounded, size: 24),
                        ),
                  label: Text(
                    _ejecting
                        ? context.tr('دەرکردن...')
                        : context.trp('دەرکردنی {name} لە مێزەکە', {'name': widget.lock.userName}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    disabledBackgroundColor: AppColors.danger.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.paddingSmall),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _ejecting ? null : _back,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  label: Text(context.tr('گەڕانەوە بۆ مێزەکان'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.softText,
                    side: const BorderSide(color: AppColors.borderSide),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
