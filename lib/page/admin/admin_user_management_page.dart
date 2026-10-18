import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/language.dart';
import '../../core/app.dart';
import '../../services/app_localizations.dart';
import '../../models/user_model.dart';
import '../../widgets/language_flag.dart';
import '../../widgets/role_users_tab.dart';

/// Admin user management with strict 5-digit numeric PIN validation, access
/// code assignment and real-time registry sync. Rendered through the shared
/// [RoleUsersTab] so the Owner dashboard and this page stay identical.
class AdminUserManagementPage extends ConsumerStatefulWidget {
  const AdminUserManagementPage({super.key});

  @override
  ConsumerState<AdminUserManagementPage> createState() => _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends ConsumerState<AdminUserManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Language picker as a click-to-open spinner (dropdown) on the add-user
  /// page so the admin can switch the interface language from a single
  /// dropdown instead of a list of separate items.
  Widget _buildLanguageSelector() {
    final appState = AppState.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSide),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppLanguage>(
          value: appState.currentLanguage,
          icon: const Icon(Icons.language_rounded, color: AppColors.primary, size: 20),
          dropdownColor: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          onChanged: (AppLanguage? newLang) {
            if (newLang != null) appState.onLanguageChanged(newLang);
          },
          items: AppLanguage.values.map((AppLanguage lang) {
            return DropdownMenuItem<AppLanguage>(
              value: lang,
              child: LanguageLabel(
                language: lang,
                flagWidth: 18,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
            );
          }).toList(),
        ),
      ),
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
        title: Text(context.tr('بەڕێوەبردنی بەکارهێنەران'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
        centerTitle: true,
        actions: [
          _buildLanguageSelector(),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.softText,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(icon: const Icon(Icons.people_rounded), text: context.tr('کاپتن')),
            Tab(icon: const Icon(Icons.receipt_long_rounded), text: context.tr('کاشێر')),
            Tab(icon: const Icon(Icons.admin_panel_settings_rounded), text: context.tr('ئادمێن')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const RoleUsersTab(role: UserRole.waiter),
          const RoleUsersTab(role: UserRole.cashier),
          const RoleUsersTab(role: UserRole.admin),
        ],
      ),
    );
  }
}