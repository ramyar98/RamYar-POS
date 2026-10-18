import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../database/local_db.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/sync_provider.dart';
import '../../widgets/profile_icon.dart';
import '../../widgets/role_users_tab.dart';
import 'ip_settings_page.dart';
import '../login/login_page.dart';

/// Owner (خاوەن سیستەم) dashboard. The owner opens accounts for
/// کاپتن / کاشێر / ئادمێن here and sees each account's name + 5-digit PIN live.
/// The tab bar sits under the app bar like a second bar.
///
/// The view refreshes automatically whenever the user registry changes — both
/// local edits and remote `USER_UPDATED` syncs — so a PIN changed by an admin
/// is reflected here immediately.
class OwnerHomePage extends ConsumerStatefulWidget {
  const OwnerHomePage({super.key});

  @override
  ConsumerState<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends ConsumerState<OwnerHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  LocalDatabase? _db;

  @override
  void initState() {
    super.initState();
    _db = ref.read(localDbProvider);
    _tabController = TabController(length: 3, vsync: this);
    _db!.usersRevision.addListener(_onUsersChanged);
    // The owner manages accounts from the phone AND the laptop, and expects an
    // account opened on one to appear on the other as soon as both are on the
    // restaurant's Wi-Fi. [startOwnerPeerSync] runs this device as a hub and a
    // client at the same time so the two owner devices find each other AND
    // both stay connected to the central cashier server.
    // Skipped under `flutter test` where real sockets would leak timers.
    if (isRunningInTest) return;
    Future.microtask(() async {
      final user = ref.read(authProvider);
      if (user == null) return;
      await startOwnerPeerSync(
        ref.read(localDbProvider),
        user.id,
        user.role.name,
        ref.read(syncConnectionProvider.notifier),
      );
    });
  }

  @override
  void dispose() {
    _db?.usersRevision.removeListener(_onUsersChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onUsersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmAndLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('دەرچوون'), maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Text(context.tr('دڵنیایت دەتەوێت دەربچیت؟')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('ڕەتکردنەوە'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('دەرچوون'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    // Drop the owner peer link on logout. A device that is also the
    // restaurant's cashier server keeps serving, so waiters and cashiers are
    // not cut off just because the owner signed out.
    stopOwnerPeerSync(ref.read(localDbProvider));
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('خاوەن سیستەم'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          ProfileIcon(user: currentUser),
          const SizedBox(width: 4),
          // دوگمەی ڕێخستنی IP - ڕاستەوخۆ دەچێتە پەیجی ئای-پی
          IconButton(
            icon: const Icon(Icons.router_rounded, color: Colors.white, size: 22),
            tooltip: context.tr('ڕێخستنی IP'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IpSettingsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 22),
            tooltip: context.tr('دەرچوون'),
            onPressed: _confirmAndLogout,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.72),
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            Tab(icon: const Icon(Icons.people_alt_rounded), text: context.tr('کاپتن')),
            Tab(icon: const Icon(Icons.receipt_long_rounded), text: context.tr('کاشێر')),
            Tab(icon: const Icon(Icons.admin_panel_settings_rounded), text: context.tr('ئادمێن')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          RoleUsersTab(role: UserRole.waiter),
          RoleUsersTab(role: UserRole.cashier),
          RoleUsersTab(role: UserRole.admin),
        ],
      ),
    );
  }
}