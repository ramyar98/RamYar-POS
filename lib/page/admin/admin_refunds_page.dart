import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/settlement_model.dart';
import '../../widgets/admin_date_filter_bar.dart';

class AdminRefundsPage extends ConsumerStatefulWidget {
  const AdminRefundsPage({super.key});

  @override
  ConsumerState<AdminRefundsPage> createState() => _AdminRefundsPageState();
}

class _AdminRefundsPageState extends ConsumerState<AdminRefundsPage> {
  final Map<int, String> _userNames = {};
  AdminDatePeriod _period = AdminDatePeriod.all;
  AdminDatePeriodRange _range = resolveAdminDatePeriod(AdminDatePeriod.all);
  late final VoidCallback _revisionListener;

  /// Sticky: the admin's chosen period survives reopening the page.
  static const String _prefKey = 'admin_refunds_date_filter';

  @override
  void initState() {
    super.initState();
    _revisionListener = () {
      if (mounted) setState(() {});
    };
    ref.read(localDbProvider).shiftsRevision.addListener(_revisionListener);
  }

  @override
  void dispose() {
    try {
      ref
          .read(localDbProvider)
          .shiftsRevision
          .removeListener(_revisionListener);
    } catch (_) {}
    super.dispose();
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

  Future<String> _getUserName(int userId) async {
    if (_userNames.containsKey(userId)) return _userNames[userId]!;
    final db = ref.read(localDbProvider);
    final user = await db.getUserById(userId);
    final name = user?.name ?? 'ID: $userId';
    _userNames[userId] = name;
    return name;
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
          context.tr('ڕەتکراوەکان'),
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
            child: AdminDateFilterBar(
              options: const [
                AdminDatePeriod.all,
                AdminDatePeriod.today,
                AdminDatePeriod.yesterday,
                AdminDatePeriod.dayBeforeYesterday,
                AdminDatePeriod.custom,
              ],
              initial: _period,
              persist: true,
              prefKey: _prefKey,
              onChanged: (period, range) {
                setState(() {
                  _period = period;
                  _range = range;
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Refund>>(
              future: ref.read(localDbProvider).getRefunds(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allRefunds = snapshot.data ?? [];
                final refunds = allRefunds.where((r) {
                  final dt = DateTime.tryParse(r.refundedAt);
                  return dt != null && _range.contains(dt);
                }).toList();
                if (refunds.isEmpty) {
                  return Center(
                    child: Text(
                      context.tr('هیچ ڕەتکراوەیەک تۆمارنەکراوە'),
                      style: TextStyle(color: AppColors.softText),
                    ),
                  );
                }
                final totalPrice = refunds.fold<double>(
                  0,
                  (sum, r) => sum + (r.price * r.quantity),
                );
                return ListView.builder(
                  padding: const EdgeInsets.all(AppConstants.paddingMedium),
                  itemCount: refunds.length + 1,
                  itemBuilder: (context, index) {
                    if (index == refunds.length) {
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
                              '${context.tr('د.ع')} ${money(totalPrice)}',
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
                    final refund = refunds[index];
                    return FutureBuilder<String>(
                      future: _getUserName(refund.refundedBy),
                      builder: (context, nameSnap) {
                        final userName = nameSnap.data ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.undo_rounded,
                                    color: AppColors.danger,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            refund.itemName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
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
                                            color: AppColors.danger.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            'x${refund.quantity}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.danger,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          '${context.tr('مێز')} ${refund.tableId}',
                                          style: TextStyle(
                                            color: AppColors.softText,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (userName.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.person_rounded,
                                            size: 10,
                                            color: AppColors.softText,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            userName,
                                            style: TextStyle(
                                              color: AppColors.primary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      _formatTime(refund.refundedAt),
                                      style: TextStyle(
                                        color: AppColors.softText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${context.tr('د.ع')} ${money((refund.price * refund.quantity))}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
