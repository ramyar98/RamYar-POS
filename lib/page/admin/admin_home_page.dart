import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/responsive.dart';
import '../../database/local_db.dart';
import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/sync_provider.dart';
import '../../widgets/profile_icon.dart';
import '../login/dollar_rate_page.dart';
import '../login/login_page.dart';
import 'admin_accounts_page.dart';
import 'admin_backup_page.dart';
import 'admin_captain_intelligence_page.dart';
import 'admin_debts_page.dart';
import 'admin_food_demand_page.dart';
import 'admin_food_filter_page.dart';
import 'admin_menu_page.dart';
import 'admin_orders_page.dart';
import 'admin_printer_screen.dart';
import 'admin_print_design_page.dart';
import 'admin_purchases_page.dart';
import 'admin_refunds_page.dart';
import 'admin_shifts_page.dart';
import 'admin_table_notes_page.dart';
import 'admin_users_page.dart';

class AdminHomePage extends ConsumerStatefulWidget {
  const AdminHomePage({super.key});

  @override
  ConsumerState<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends ConsumerState<AdminHomePage> {
  @override
  void initState() {
    super.initState();
    // The desktop/laptop that signs in as admin is the central hub machine,
    // same as the cashier: host the WebSocket server so owner/mobile devices
    // push user/order/table changes through it and every device stays in sync.
    // Skipped under `flutter test` where real sockets would leak timers.
    if (isRunningInTest) return;
    Future.microtask(() async {
      final user = ref.read(authProvider);
      if (user == null) return;
      final ip = await startSyncServer(
        ref.read(localDbProvider),
        user.id,
        user.role.name,
        ref.read(syncConnectionProvider.notifier),
        printerConfig: ref.read(printerProvider),
      );
      // Recall across app restarts that this device hosts the central server.
      if (ip != null) {
        await markServerDevice();
      }
    });
  }

  Future<void> _confirmAndLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          context.tr('دەرچوون'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        content: Text(context.tr('دڵنیایت دەتەوێت دەربچیت؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('ڕەتکردنەوە')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('دەرچوون')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    // Admin is a server device (like cashier): keep the hub accepting and
    // broadcasting while the app sits at the login screen.
    logoutKeepServerRunning(ref.read(localDbProvider));
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider);
    // Six tiles per row on every device, as asked. Each tile scales its own
    // content down to the cell (see [_dashboardButton]), so the same six columns
    // fit a 320px phone and a wide monitor without overflowing.
    const crossAxisCount = 6;
    final bodyPadding = Responsive.screenPadding(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.admin_panel_settings_rounded,
              color: AppColors.primary,
              size: 26,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('ئادمێن'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        actions: [
          ScrollableAppBarActions(
            children: [
              ProfileIcon(user: currentUser),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.danger,
                  size: 22,
                ),
                tooltip: context.tr('دەرچوون'),
                onPressed: _confirmAndLogout,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: bodyPadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The gap and the cell shape follow the width so six columns stay
            // legible from a 320px phone to a wide monitor: a tight gap and a
            // taller-than-wide cell when the row is narrow, a roomy square when
            // it is not.
            final gap = constraints.maxWidth < 700 ? 8.0 : 16.0;
            final cellWidth =
                (constraints.maxWidth - gap * (crossAxisCount - 1)) /
                    crossAxisCount;
            final cellHeight = cellWidth < 96 ? 96.0 : cellWidth;
            return Center(
              child: GridView.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                childAspectRatio: cellWidth / cellHeight,
                shrinkWrap: true,
                children: [
              _dashboardButton(
                Icons.receipt_long_rounded,
                context.tr('حسابەکان'),
                AppColors.primary,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminAccountsPage(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.restaurant_menu_rounded,
                context.tr('مێنیو'),
                AppColors.blue,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminMenuPage()),
                  );
                },
              ),
              _dashboardButton(
                Icons.person_add_rounded,
                context.tr('زیادکردنی بەکارهێنەر'),
                AppColors.success,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminUsersPage()),
                  );
                },
              ),
              _dashboardButton(
                Icons.reorder_rounded,
                context.tr('ئۆردەرەکان'),
                AppColors.blue,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminOrdersPage()),
                  );
                },
              ),
              _dashboardButton(
                Icons.timeline_rounded,
                context.tr('شەفتی کاشێر'),
                const Color(0xFFFFA000),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminShiftsPage()),
                  );
                },
              ),
              _dashboardButton(
                Icons.shopping_cart_rounded,
                context.tr('خەرجیەکان'),
                AppColors.danger,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminPurchasesPage(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.bookmark_rounded,
                context.tr('قەرزەکان'),
                AppColors.danger,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminDebtsPage()),
                  );
                },
              ),
              _dashboardButton(
                Icons.undo_rounded,
                context.tr('ڕەتکراوەکان'),
                AppColors.softText,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminRefundsPage()),
                  );
                },
              ),
              _dashboardButton(
                Icons.print_rounded,
                context.tr('چاپکەر'),
                AppColors.darkText,
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminPrinterScreen(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.brush_rounded,
                context.tr('دیزاینی پرێنت'),
                const Color(0xFF00838F),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminPrintDesignPage(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.filter_list_rounded,
                context.tr('فلتەری خواردن'),
                const Color(0xFF1565C0),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminFoodFilterPage(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.attach_money_rounded,
                context.tr('نرخی دۆلار'),
                const Color(0xFF2E7D32),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DollarRatePage()),
                  );
                },
              ),
              _dashboardButton(
                Icons.psychology_rounded,
                context.tr('زیرەکی کاپتن'),
                const Color(0xFF7B1FA2),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminCaptainIntelligencePage(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.trending_up_rounded,
                context.tr('داواکاری خواردن'),
                const Color(0xFF00897B),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminFoodDemandPage(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.note_alt_rounded,
                context.tr('تێبینیی مێزەکان'),
                const Color(0xFF6A1B9A),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminTableNotesPage(),
                    ),
                  );
                },
              ),
              _dashboardButton(
                Icons.backup_rounded,
                context.tr('بەکاپ'),
                const Color(0xFF6A1B9A),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminBackupPage()),
                  );
                },
              ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _dashboardButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    final isPhone = Responsive.isPhone(context);
    final box = isPhone ? 42.0 : 60.0;
    final iconSize = isPhone ? 20.0 : 28.0;
    final fontSize = isPhone ? 13.0 : 15.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(isPhone ? 14 : 20),
      elevation: 0,
      shadowColor: color.withValues(alpha: 0.1),
      child: InkWell(
        borderRadius: BorderRadius.circular(isPhone ? 14 : 20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isPhone ? 14 : 20),
            border: Border.all(
              color: AppColors.borderSide.withValues(alpha: 0.3),
            ),
          ),
          padding: EdgeInsets.all(isPhone ? 8 : 20),
          child: Center(
            child: FittedBox(
              // Six columns are forced on every width. Scaling the whole tile
              // down to whatever cell the grid hands it is what keeps a 320px
              // phone and a wide monitor from ever showing an overflow stripe.
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: box,
                    height: box,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(isPhone ? 12 : 16),
                    ),
                    child: Icon(icon, color: color, size: iconSize),
                  ),
                  SizedBox(height: isPhone ? 8 : 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                        color: AppColors.darkText,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
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
