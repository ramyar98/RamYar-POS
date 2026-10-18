import 'package:flutter/material.dart';
import '../core/colors.dart';
import '../providers/network_lockdown_provider.dart';
import '../services/app_localizations.dart';

/// Full-screen, all-routes lockdown overlay shown when the restaurant network
/// is lost (Wi-Fi gone or device hopped onto a foreign subnet). It sits ABOVE
/// the Navigator (via MaterialApp.builder), so no page, dialog or drawer can
/// be operated underneath - the whole system is stopped, exactly as the
/// restaurant owner requires. The session is NOT destroyed: when the network
/// returns, the `networkLockProvider` is cleared and this screen disappears
/// automatically - the user resumes where they left off without re-entering
/// their PIN.
class NetworkLockScreen extends StatelessWidget {
  final NetworkLockReason reason;
  const NetworkLockScreen({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    final offline = reason == NetworkLockReason.offline;
    return PopScope(
      canPop: false,
      child: Material(
        color: AppColors.background,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.wifi_off_rounded,
                      size: 72,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    context.tr(
                      offline
                          ? 'قوفڵکرا - وایفای نەما'
                          : 'قوفڵکرا - تۆڕەکە نەناسراوە',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    offline
                        ? context.tr(
                            'سیستەم ڕاوەستاوە بۆ پاراستنی داتاکان. کاتێک وایفای گەڕایەوە، بە خۆکاری دەکرێتەوە.')
                        : context.tr(
                            'لە تۆڕی ڕێستۆرانت نیت. بگەڕێوە بۆ وایفای ڕێستۆرانتەکە و سیستەمەکە بە خۆکاری دەکرێتەوە.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.softText,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('چاوەڕوانی وایفای...'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.softText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}