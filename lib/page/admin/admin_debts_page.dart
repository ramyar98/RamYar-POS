import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/debt_model.dart';
import '../../providers/auth_provider.dart';

class AdminDebtsPage extends ConsumerStatefulWidget {
  const AdminDebtsPage({super.key});

  @override
  ConsumerState<AdminDebtsPage> createState() => _AdminDebtsPageState();
}

class _AdminDebtsPageState extends ConsumerState<AdminDebtsPage> {
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 1));
  late final VoidCallback _revisionListener;

  @override
  void initState() {
    super.initState();
    _revisionListener = () {
      if (mounted) setState(() {});
    };
    final db = ref.read(localDbProvider);
    db.shiftsRevision.addListener(_revisionListener);
    db.orderRevision.addListener(_revisionListener);
  }

  @override
  void dispose() {
    try {
      final db = ref.read(localDbProvider);
      db.shiftsRevision.removeListener(_revisionListener);
      db.orderRevision.removeListener(_revisionListener);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end.subtract(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = DateTime(picked.year, picked.month, picked.day);
        } else {
          _end = DateTime(
            picked.year,
            picked.month,
            picked.day,
          ).add(const Duration(days: 1));
        }
      });
    }
  }

  Future<void> _deleteDebt(DebtModel debt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('سڕینەوەی قەرز')),
        content: Text(
          context.trp('دڵنیایت دەتەوێت قەرزی {name} - د.ع {amount} بسڕیتەوە؟', {
            'name': debt.tableName,
            'amount': money(debt.amount),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('ڕەتکردنەوە')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('سڕینەوە')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(localDbProvider).deleteDebt(debt.id);
      setState(() {});
    }
  }

  void _settleDebt(DebtModel debt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('واسڵکردنی قەرز')),
        content: Text(
          context.trp(
            'دڵنیایت دەتەوێت قەرزی {name} - د.ع {amount} واسڵ بکەیت؟',
            {'name': debt.tableName, 'amount': money(debt.amount)},
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
    if (confirm == true) {
      if (!mounted) return;
      final db = ref.read(localDbProvider);
      final user = ref.read(authProvider);
      final now = DateTime.now().toIso8601String();
      await db.db.insert('settled_orders', {
        'tableId': debt.tableId,
        'tableName': '${debt.tableName} (${context.tr('قەرز')})',
        'totalAmount': debt.amount,
        'discountPercent': 0,
        'discountAmount': 0,
        'settledAt': now,
        'settledBy': user?.id ?? 0,
        'shiftId': 0,
        'waiterId': '',
        'seatedAt': '',
        'paymentMethod': 'debt',
      });
      await db.deleteDebt(debt.id);
      setState(() {});
    }
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
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
          context.tr('قەرزەکان'),
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
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _start.toString().substring(0, 10),
                        style: const TextStyle(color: AppColors.darkText),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    context.tr('بۆ'),
                    style: const TextStyle(color: AppColors.softText),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _end
                            .subtract(const Duration(days: 1))
                            .toString()
                            .substring(0, 10),
                        style: const TextStyle(color: AppColors.darkText),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<DebtModel>>(
              future: ref.read(localDbProvider).getDebts(),
              builder: (context, snapshot) {
                final allDebts = snapshot.data ?? [];
                final debts = allDebts.where((d) {
                  final dt = DateTime.tryParse(d.createdAt);
                  return dt != null && dt.isAfter(_start) && dt.isBefore(_end);
                }).toList();

                final totalDebt = debts.fold<double>(
                  0,
                  (sum, d) => sum + d.amount,
                );

                if (debts.isEmpty) {
                  return Center(
                    child: Text(
                      context.tr('هیچ قەرزێک نییە'),
                      style: TextStyle(color: AppColors.softText),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(AppConstants.paddingMedium),
                  itemCount: debts.length + 1,
                  itemBuilder: (context, index) {
                    if (index == debts.length) {
                      return Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Text(
                              context.tr('کۆی گشتی'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${context.tr('د.ع')} ${money(totalDebt)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final debt = debts[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
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
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.bookmark_rounded,
                                color: AppColors.danger,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
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
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (debt.reason.isNotEmpty)
                                      Text(
                                        debt.reason,
                                        style: TextStyle(
                                          color: AppColors.softText,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (debt.reason.isNotEmpty)
                                      const SizedBox(width: 8),
                                    Text(
                                      _formatTime(debt.createdAt),
                                      style: TextStyle(
                                        color: AppColors.softText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${context.tr('د.ع')} ${money(debt.amount)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 10px padding puts both action buttons at the
                          // 40x40 floor (the old 8px left them at 36).
                          InkWell(
                            onTap: () => _settleDebt(debt),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _deleteDebt(debt),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
