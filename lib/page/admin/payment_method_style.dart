import 'package:flutter/material.dart';

import '../../core/colors.dart';
import '../../services/app_localizations.dart';

/// Canonical order of the money-collection methods shown in the shift report
/// and its per-method page.
///
/// «قەرز» is intentionally absent: debts have their own tab in the report, so
/// listing them here again would double-count them.
const List<String> kPaymentMethods = [
  'cash',
  'fib',
  'fastpay',
  'superqi',
  'zincash',
  'nass',
  'switch',
];

/// Human label for a settlement's `paymentMethod` value. The card/wallet names
/// (FIB, FastPay, …) are brand names and stay as-is in every language.
String paymentMethodLabel(BuildContext context, String method) {
  switch (method) {
    case 'cash':
      return context.tr('وەسڵ (نەقد)');
    case 'debt':
      return context.tr('قەرز');
    case 'fib':
      return 'FIB';
    case 'fastpay':
      return 'FastPay';
    case 'superqi':
      return 'Super QI';
    case 'zincash':
      return 'ZinCash';
    case 'nass':
      return 'NassPay';
    case 'switch':
      return 'Switch';
    default:
      return method;
  }
}

Color paymentMethodColor(String method) {
  switch (method) {
    case 'cash':
      return AppColors.success;
    case 'debt':
      return const Color(0xFFFF6B35);
    case 'fib':
      return const Color(0xFF1565C0);
    case 'fastpay':
      return const Color(0xFF3949AB);
    case 'switch':
      return const Color(0xFF00897B);
    case 'superqi':
      return const Color(0xFF7B1FA2);
    case 'zincash':
      return const Color(0xFFF9A825);
    case 'nass':
      return const Color(0xFFC62828);
    default:
      return AppColors.softText;
  }
}

IconData paymentMethodIcon(String method) {
  switch (method) {
    case 'cash':
      return Icons.monetization_on_rounded;
    case 'debt':
      return Icons.bookmark_rounded;
    case 'fib':
      return Icons.credit_card_rounded;
    case 'fastpay':
      return Icons.bolt_rounded;
    case 'switch':
      return Icons.swap_horiz_rounded;
    case 'superqi':
      return Icons.flash_on_rounded;
    case 'zincash':
      return Icons.account_balance_wallet_rounded;
    case 'nass':
      return Icons.payment_rounded;
    default:
      return Icons.receipt_rounded;
  }
}

/// «2026/10/12 08:34 PM» for a stored ISO timestamp; falls back to the raw
/// value when it cannot be parsed.
String formatShiftTime(String iso) {
  if (iso.isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  final amPm = dt.hour >= 12 ? 'PM' : 'AM';
  return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
      '${dt.day.toString().padLeft(2, '0')} '
      '${hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')} $amPm';
}
