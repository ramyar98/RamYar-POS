import 'package:flutter/material.dart';
import '../core/app.dart';
import '../core/colors.dart';
import '../core/language.dart';
import '../models/user_model.dart';
import '../services/app_localizations.dart';
import 'language_flag.dart';

class ProfileIcon extends StatelessWidget {
  final UserModel? user;
  final VoidCallback? onLogout;
  final VoidCallback? onOpenSettings;
  final bool showLanguage;

  const ProfileIcon({
    super.key,
    required this.user,
    this.onLogout,
    this.onOpenSettings,
    this.showLanguage = true,
  });

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox.shrink();
    final initial = user!.name.isNotEmpty ? user!.name[0] : '?';
    final roleLabels = {
      UserRole.waiter: context.tr('کاپتن'),
      UserRole.cashier: context.tr('کاشێر'),
      UserRole.admin: context.tr('ئادمێن'),
      UserRole.owner: context.tr('خاوەن سیستەم'),
    };
    final appState = AppState.of(context);

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.darkText)),
              const SizedBox(height: 2),
              Text(roleLabels[user!.role] ?? '',
                  style: const TextStyle(fontSize: 12, color: AppColors.softText)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (onOpenSettings != null) ...[
          PopupMenuItem<String>(
            value: 'settings',
            child: Row(
              children: [
                const Icon(Icons.settings_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Text(
                  context.tr('ڕێخستن'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.darkText),
                ),
              ],
            ),
          ),
        ],
        if (showLanguage)
          for (final lang in AppLanguage.values)
            PopupMenuItem<String>(
              value: 'lang_${lang.name}',
              child: Row(
                children: [
                  FlagIcon(language: lang, width: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      LanguageHelper.getLanguageName(lang),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: appState.currentLanguage == lang ? FontWeight.bold : FontWeight.w500,
                        color: appState.currentLanguage == lang ? AppColors.primary : AppColors.darkText,
                      ),
                    ),
                  ),
                  if (appState.currentLanguage == lang)
                    const Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
                ],
              ),
            ),
        if (onLogout != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                const Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
                const SizedBox(width: 10),
                Text(
                  context.tr('دەرچوون'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.danger),
                ),
              ],
            ),
          ),
        ],
      ],
      onSelected: (value) {
        if (value == 'logout') {
          onLogout?.call();
        } else if (value == 'settings') {
          onOpenSettings?.call();
        } else if (value.startsWith('lang_')) {
          final name = value.substring('lang_'.length);
          final lang = AppLanguage.values.firstWhere((l) => l.name == name);
          appState.onLanguageChanged(lang);
        }
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFFFF7A4A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}