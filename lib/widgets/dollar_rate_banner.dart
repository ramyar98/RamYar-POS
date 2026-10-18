import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/colors.dart';
import '../providers/dollar_rate_provider.dart';
import '../services/app_localizations.dart';

/// The rate the admin set, read by the cashier.
///
/// The cashier does not edit this and cannot be led to think they can: there is
/// no button and no field, only the sentence the admin's number produces. The
/// wording names who set it, because a rate is only worth reading if the person
/// reading it knows whose figure it is and that it is the current one - a bare
/// number on a till screen is indistinguishable from a stray total.
///
/// Separate from the page that shows it, so it can be dropped into any screen
/// that needs the rate and so its behaviour can be tested without standing up a
/// whole cashier shift to look at it.
class DollarRateBanner extends ConsumerWidget {
  const DollarRateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rateAsync = ref.watch(dollarRateProvider);
    return rateAsync.maybeWhen(
      // While the value is still on its way from the database, or if the read
      // fails, say nothing at all. An empty gap is honest; a placeholder rate
      // would be a number the cashier might quote to a customer.
      data: (rate) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_money_rounded, color: AppColors.success, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      context.tr('ئادمێن نرخی دۆلاری داناوە'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.trp('{dollars}\$ بەرامبەر بە دیناری عیراقی {iqd}', {
                  'dollars': rate.dollarsLabel,
                  'iqd': rate.iqdLabel,
                }),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
