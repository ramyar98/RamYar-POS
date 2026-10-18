import 'package:ramyar_pos/core/fmt.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../services/app_localizations.dart';
import '../../database/local_db.dart';
import '../../models/settlement_model.dart';
import 'admin_shift_detail_page.dart';

class AdminShiftsPage extends ConsumerStatefulWidget {
  const AdminShiftsPage({super.key});

  @override
  ConsumerState<AdminShiftsPage> createState() => _AdminShiftsPageState();
}

class _AdminShiftsPageState extends ConsumerState<AdminShiftsPage> {
  String _formatTime(String iso) {
    if (iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  Future<void> _openShiftDetail(CashierShift shift) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminShiftDetailPage(shift: shift)),
    );
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
          context.tr('شەفتی کاشێر'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: ref.read(localDbProvider).shiftsRevision,
        builder: (context, revision, _) {
          // Re-query on every revision bump so shifts started/ended on REMOTE
          // cashier devices (or flushed from an offline queue) appear on the
          // admin device as soon as they arrive.
          return FutureBuilder<List<CashierShift>>(
            future: ref.read(localDbProvider).getAllShifts(),
            builder: (context, snapshot) {
              final shifts = snapshot.data ?? [];
              if (shifts.isEmpty) {
                return Center(
                  child: Text(
                    context.tr('هیچ شەفتێک نییە'),
                    style: TextStyle(color: AppColors.softText),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                itemCount: shifts.length,
                itemBuilder: (context, index) {
                  final shift = shifts[index];
                  final isActive =
                      shift.endedAt == null || shift.endedAt!.isEmpty;
                  return _ShiftCard(
                    shift: shift,
                    isActive: isActive,
                    formatTime: _formatTime,
                    onTap: () => _openShiftDetail(shift),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ShiftCard extends ConsumerWidget {
  final CashierShift shift;
  final bool isActive;
  final String Function(String) formatTime;
  final VoidCallback onTap;

  const _ShiftCard({
    required this.shift,
    required this.isActive,
    required this.formatTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isActive
            ? Border.all(color: AppColors.success, width: 2)
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isActive
                          ? Icons.play_circle_rounded
                          : Icons.check_circle_rounded,
                      color: isActive ? AppColors.success : AppColors.softText,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shift.cashierName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${context.tr('دەستپێکردن')}: ${formatTime(shift.startedAt)}',
                          style: TextStyle(
                            color: AppColors.softText,
                            fontSize: 12,
                          ),
                        ),
                        if (!isActive) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${context.tr('کۆتایی')}: ${formatTime(shift.endedAt!)}',
                            style: TextStyle(
                              color: AppColors.softText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (isActive)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              context.tr('چالاکە'),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isActive)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.softText,
                    ),
                ],
              ),
              if (!isActive) ...[
                const SizedBox(height: 12),
                _ComparisonIndicator(shift: shift),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparisonIndicator extends ConsumerWidget {
  final CashierShift shift;
  const _ComparisonIndicator({required this.shift});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<double>(
      future: ref
          .read(localDbProvider)
          .getSettledCashLikeTotalByShiftId(shift.id),
      builder: (context, snapshot) {
        final systemTotal = snapshot.data ?? 0;
        final diff = shift.totalCollected - systemTotal;

        Color color;
        IconData icon;
        if (shift.totalCollected == systemTotal) {
          color = AppColors.success;
          icon = Icons.check_circle_rounded;
        } else if (shift.totalCollected > systemTotal) {
          color = const Color(0xFFFFA000);
          icon = Icons.trending_up_rounded;
        } else {
          color = AppColors.danger;
          icon = Icons.trending_down_rounded;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                context.tr('کاشێر'),
                style: TextStyle(fontSize: 12, color: AppColors.softText),
              ),
              const SizedBox(width: 4),
              Text(
                '${context.tr('د.ع')} ${money(shift.totalCollected)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.compare_arrows_rounded,
                size: 14,
                color: AppColors.softText,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('سیستەم'),
                style: TextStyle(fontSize: 12, color: AppColors.softText),
              ),
              const SizedBox(width: 4),
              Text(
                '${context.tr('د.ع')} ${money(systemTotal)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.darkText,
                ),
              ),
              const Spacer(),
              Text(
                diff == 0
                    ? '='
                    : (diff > 0 ? '+${money(diff)}' : money(diff)),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FutureBuilder3<T1, T2, T3> extends StatelessWidget {
  final Future<T1> future1;
  final Future<T2> future2;
  final Future<T3> future3;
  final Widget Function(
    BuildContext,
    AsyncSnapshot<T1>,
    AsyncSnapshot<T2>,
    AsyncSnapshot<T3>,
  )
  builder;

  const FutureBuilder3({
    super.key,
    required this.future1,
    required this.future2,
    required this.future3,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T1>(
      future: future1,
      builder: (context, snap1) {
        return FutureBuilder<T2>(
          future: future2,
          builder: (context, snap2) {
            return FutureBuilder<T3>(
              future: future3,
              builder: (context, snap3) =>
                  builder(context, snap1, snap2, snap3),
            );
          },
        );
      },
    );
  }
}
