import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../core/table_status_visuals.dart';
import '../../services/app_localizations.dart';
import '../../services/sync_provider.dart';
import '../../services/sync_types.dart' show AckMessage;
import '../../database/local_db.dart';
import '../../providers/waiter_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../models/order_delivery_model.dart';
import '../../models/table_lock_model.dart';
import '../../widgets/profile_icon.dart';
import '../../widgets/table_card.dart';
import 'table_page.dart';
import 'waiter_settings_page.dart';
import 'order_delivery_page.dart';
import '../cashier/cashier_cancelled_items_page.dart';
import '../login/login_page.dart';

class WaiterHomePage extends ConsumerStatefulWidget {
  const WaiterHomePage({super.key});

  @override
  ConsumerState<WaiterHomePage> createState() => _WaiterHomePageState();
}

class _WaiterHomePageState extends ConsumerState<WaiterHomePage>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      if (!mounted) return;
      final user = ref.read(authProvider);
      if (user != null && user.role == UserRole.waiter) {
        // A captain is a pure client and always follows the cashier. Clear the
        // server flag (and stop any hub) a previous cashier/admin session left
        // on this device before the sync link comes up, so the phone can never
        // answer as a second restaurant server.
        await clearServerDevice(ref.read(syncConnectionProvider.notifier));
        if (!mounted) return;
        ref.read(waiterProvider.notifier).syncTableScope();
      } else {
        // Any other role sees every table - make sure no captain's scope is
        // left over from a previous login on this device.
        ref.read(waiterProvider.notifier).refreshSilent();
      }
      _autoConnect();
    });
    // ئۆتۆماتیکی لە پسوڕەوە: هەر ٢ چرکە جارێک خزمەتگوزارییەکان تازە دەکرێنەوە
    // (سینکەکە خۆی ڕاستەوخۆ لە ڕێگەی WebSocket ئەنجام دەدرێت - ئەمە تەنها UI)
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      // The one-second bill clock is owned by waiterProvider (see
      // WaiterNotifier), so this timer only refreshes what the captain's own
      // screen shows. Keeping a second checkOverdueTables() here was the same
      // query and the same write, done twice, on the phone that can least
      // afford it.
      ref.read(waiterProvider.notifier).refreshSilent();
      ref.invalidate(deliveryStatusProvider);
    });

    ref.listenManual(syncConnectionProvider, (prev, next) {
      final p = prev?.lastAck;
      final n = next.lastAck;
      if (p == null && n != null) {
        ref.invalidate(deliveryStatusProvider);
      } else if (p != null && n != null && p.timestamp != n.timestamp) {
        ref.invalidate(deliveryStatusProvider);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // گەڕانەوە بۆ ئەپەکە دوای ماوەیەك لە باگراوەند: ڕاستەوخۆ تازە بکەوە و
      // دڵنیابە لە بەستراوی (گەر پەککەوتوو بێت دووبارە دەبەسترێتەوە).
      ref.read(waiterProvider.notifier).refreshSilent();
      ref.invalidate(deliveryStatusProvider);
      _autoConnect();
    }
  }

  void _autoConnect() {
    final syncState = ref.read(syncConnectionProvider);
    if (syncState.connected) return;
    final user = ref.read(authProvider);
    if (user == null) return;
    final db = ref.read(localDbProvider);
    final state = ref.read(syncConnectionProvider.notifier);
    Future.microtask(() async {
      final accessCode = user.accessCode?.trim();
      startAutoDiscovery(db, user.id, user.role.name, state,
        knownServerIp: await getServerIpOrDefault(), knownPort: 9876,
        accessCode: accessCode,
      );
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WaiterSettingsPage()),
    );
  }

  bool _isRecentAck(AckMessage? ack) {
    if (ack == null) return false;
    return DateTime.now().difference(ack.timestamp).inSeconds < 30;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
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
    disconnectSync(ref.read(localDbProvider));
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false,
    );
  }

  Color _statusColor(TableStatus status) => TableStatusVisuals.color(status);

  IconData _statusIcon(TableStatus status) => TableStatusVisuals.icon(status);

  String _statusText(TableStatus status) {
    switch (status) {
      case TableStatus.empty:
        return context.tr('بەتاڵ');
      case TableStatus.occupied:
        return context.tr('دانیشتوو');
      case TableStatus.billRequested:
        return context.tr('داوای حیسابی کردووە');
      case TableStatus.overdue:
        return context.tr('دواکەوتوو');
    }
  }

  Future<void> _showAddTableDialog() async {
    final inputController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(context.tr('زیادکردنی مێزی نوێ'), style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: TextField(
          controller: inputController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.tr('ژمارە یان ناوی مێز'),
            hintText: context.tr('بۆ نموونە: 51 یان Ramyar'),
            prefixIcon: const Icon(Icons.table_restaurant_rounded),
          ),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('ڕەتکردنەوە'))),
          FilledButton(
            onPressed: () async {
              if (inputController.text.trim().isEmpty) return;
              final success = await ref.read(waiterProvider.notifier).addTableWithInput(inputController.text);
              if (!ctx.mounted) return;
              if (success) {
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(ctx.tr('ببورە ئەم مێزە بوونی هەیە')),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            child: Text(context.tr('زیادکردن')),
          ),
        ],
      ),
    );
  }

  void _showGuestCountDialog(int tableId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            const Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 28),
            const SizedBox(width: 12),
            Text(
              context.tr('چەند کەسن؟'),
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText),
            ),
          ],
        ),
        content: SingleChildScrollView(
          // Constrained instead of a hard 320px: inside an AlertDialog on a
          // 320dp phone the content box is only ~224dp, so the last guest tile
          // was clipped off the edge and unreachable.
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('بەخێربێیت! ژمارەی کڕیاران هەڵبژێرە'),
                style: const TextStyle(color: AppColors.softText, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ...List.generate(7, (index) {
                  final count = index + 1;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TablePage(tableNumber: tableId, initialGuestCount: count),
                        ),
                      );
                    },
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.1),
                            AppColors.primary.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                  // Icon-only "+" tile: opens an input for a custom guest
                  // count such as 20 or 22 (request 2).
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _showCustomGuestCountDialog(tableId);
                    },
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
                      ),
                      child: const Icon(Icons.add_rounded, color: AppColors.primary, size: 30),
                    ),
                  ),
                ],
              ),
            ],
          ),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('ڕەتکردنەوە'), style: const TextStyle(color: AppColors.softText)),
          ),
        ],
      ),
    );
  }

  /// Custom guest-count input reached from the "+" tile of the guest dialog:
  /// lets the captain type any number (for example 20 or 22) instead of being
  /// limited to the default 1-7 tiles.
  Future<void> _showCustomGuestCountDialog(int tableId) async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            const Icon(Icons.group_add_rounded, color: AppColors.primary, size: 28),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                ctx.tr('ژمارەی موشتەرییەکان'),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.pop(ctx, v),
            decoration: InputDecoration(
              labelText: ctx.tr('ژمارەی کەسەکان بنووسە'),
              hintText: '20',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.people_alt_rounded, color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('ڕەتکردنەوە'), style: const TextStyle(color: AppColors.softText)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(ctx.tr('زیادکردن')),
          ),
        ],
      ),
    );
    // Cancelled (null) - do nothing at all. Backing out of the dialog used to
    // fall into the "invalid number" branch below and flash a red error, which
    // told the captain they had typed something wrong when they had typed
    // nothing.
    if (raw == null) return;
    final parsed = raw.trim().isEmpty ? null : int.tryParse(raw.trim());
    if (parsed == null || parsed < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('ژمارەیەکی دروست بنووسە')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TablePage(tableNumber: tableId, initialGuestCount: parsed),
      ),
    );
  }

  Widget _buildSyncStatusIndicator() {
    return Consumer(
      builder: (context, ref, _) {
        final syncState = ref.watch(syncConnectionProvider);
        final connected = syncState.connected;
        final ack = syncState.lastAck;
        final hasRecentAck = connected && _isRecentAck(ack);
        final printed = hasRecentAck && ack!.printed;

        Color dotColor;
        String statusText;
        Widget? trailingIcon;

        if (!connected) {
          dotColor = AppColors.danger;
          statusText = context.tr('پەککەوتوو');
        } else if (hasRecentAck && ack!.rejected) {
          dotColor = AppColors.danger;
          statusText = context.tr('ڕەفز');
          trailingIcon = Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.block, size: 12, color: AppColors.danger),
          );
        } else if (hasRecentAck && !ack!.success) {
          dotColor = AppColors.danger;
          statusText = context.tr('هەڵە');
          trailingIcon = Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.error_outline, size: 12, color: AppColors.danger),
          );
        } else if (hasRecentAck && printed) {
          dotColor = AppColors.success;
          statusText = context.tr('چاپ کرا');
          trailingIcon = Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.check_circle, size: 12, color: AppColors.success),
          );
        } else if (hasRecentAck && !printed) {
          dotColor = AppColors.blue;
          statusText = context.tr('نێردرا');
          trailingIcon = Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.check, size: 12, color: AppColors.blue),
          );
        } else {
          dotColor = const Color(0xFFFFA000);
          statusText = context.tr('بەستراوی');
        }

        // Tapping the pill while the link is up is the dangerous direction: a
        // captain carrying a tray brushes the screen and every order stops
        // reaching the till. Going up needs a deliberate confirmation, coming
        // back up is harmless so it happens straight away.
        return Semantics(
          button: true,
          // The label already carries the status, so the child's own text would
          // be announced twice - once as part of this node and once on its own.
          excludeSemantics: true,
          label: context.trp('دەستی پەیوەندی: {status}', {'status': statusText}),
          hint: connected
              ? context.tr('بۆ ڕاگرتنی پەیوەندی دووبارە بکەرەوە')
              : context.tr('بۆ پەیوەندی دووبارە بکەرەوە'),
          child: GestureDetector(
            onTap: _toggleConnection,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: dotColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dotColor.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.4),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (trailingIcon != null) ...[trailingIcon],
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: dotColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeliveryBadge() {
    return Consumer(
      builder: (context, ref, _) {
        final deliveryAsync = ref.watch(deliveryStatusProvider);
        final deliveries =
            deliveryAsync.asData?.value ?? const <OrderDeliveryModel>[];
        // Item-aware: the badge counts the dishes still on their way (not yet
        // confirmed by the till) plus the rejected ones - the captain's real
        // backlog. Legacy rows with no dishes fall back to the table count.
        var pendingItems = 0;
        var rejectedDishes = 0;
        for (final d in deliveries) {
          if (d.rejected) {
            rejectedDishes += d.items.isEmpty ? 1 : d.itemTotal;
            continue;
          }
          if (d.items.isEmpty) {
            if (!d.hasArrived) pendingItems++;
            continue;
          }
          pendingItems += d.pendingItems.length;
        }
        final count = pendingItems + rejectedDishes;
        return IconButton(
          tooltip: context.tr('دۆخی ناردنی داواکاری'),
          onPressed: _openDeliveryPage,
          icon: Badge(
            isLabelVisible: count > 0,
            backgroundColor: AppColors.primary,
            label: Text('$count'),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }

  void _openDeliveryPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrderDeliveryPage()),
    );
  }

  /// «ڕەتکراوەکان» on the captain's app bar.
  ///
  /// A captain is the one who rang the dish in, so they are the one who gets
  /// asked why it never arrived. When the cashier throws something out it has to
  /// be visible on the floor without anyone having to walk to the till - hence
  /// the live count. It is a window, though: the page opens read-only, because
  /// putting a rejected dish back writes onto a live table order and that is the
  /// cashier's call to make.
  Widget _buildCancelledBadge() {
    return Consumer(
      builder: (context, ref, _) {
        final async = ref.watch(pendingCancelledItemsProvider);
        final count = async.asData?.value.length ?? 0;
        return IconButton(
          tooltip: context.tr('ڕەتکراوەکان'),
          onPressed: _openCancelledItems,
          icon: Badge(
            isLabelVisible: count > 0,
            backgroundColor: AppColors.danger,
            label: Text('$count'),
            child: const Icon(Icons.block_rounded, color: AppColors.danger),
          ),
        );
      },
    );
  }

  void _openCancelledItems() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CashierCancelledItemsPage(canMoveBack: false)),
    );
  }

  Future<void> _toggleConnection() async {
    final syncState = ref.read(syncConnectionProvider);
    if (syncState.connected) {
      // Never drop the link on a single tap. A captain is moving around with a
      // tray on the phone; one accidental brush must not silently send every
      // subsequent order into the outbox with nobody watching the cashier
      // screen. Ask, and say what actually happens to the orders.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('ڕاگرتنی پەیوەندی')),
          content: Text(context.tr(
            'تاکە پەیوەندیکە دادەخەیت. داواکاریە نوێەکان لەسەر ئامێرەکەت دەمێننەوە و کاتێک پەیوەندی دەگەڕێتەوە خۆکار دەنێردرێنن. ئایا دڵنیایت؟')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('ڕەتکردنەوە')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('بەڵێ، ڕابگرە')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      disconnectSync(ref.read(localDbProvider));
      ref.read(syncConnectionProvider.notifier).setConnected(false);
      return;
    }
    final user = ref.read(authProvider);
    if (user == null) return;
    Future.microtask(() async {
      final accessCode = user.accessCode?.trim();
      startAutoDiscovery(
        ref.read(localDbProvider),
        user.id,
        user.role.name,
        ref.read(syncConnectionProvider.notifier),
        knownServerIp: await getServerIpOrDefault(), knownPort: 9876,
        accessCode: accessCode,
      );
    });
    ref.read(waiterProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tablesAsync = ref.watch(waiterProvider);
    final isPhone = Responsive.isPhone(context);
    // One slim orange pill for both layouts. The captain's app bar is crowded,
    // so the button stays short from top to bottom while it keeps its long
    // sideways shape; the gradient runs top→bottom inside the orange family (no
    // second hue), so it reads as a single orange button with a little depth.
    const addTableGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF7A4A), AppColors.primary],
    );
    final addTableButton = isPhone
        ? Container(
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              gradient: addTableGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              onPressed: _showAddTableDialog,
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 19),
              tooltip: context.tr('زیادکردنی مێز'),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 32),
                maximumSize: const Size(40, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          )
        : Container(
            height: 32,
            decoration: BoxDecoration(
              gradient: addTableGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextButton.icon(
              onPressed: _showAddTableDialog,
              icon: const Icon(Icons.add, size: 14, color: Colors.white),
              label: Text(context.tr('زیادکردنی مێز'),
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
                maximumSize: const Size(double.infinity, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.table_restaurant_rounded, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('مێزەکان'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.darkText),
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        leadingWidth: isPhone ? 48 : 130,
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: Center(child: addTableButton),
        ),
        actions: [
          ScrollableAppBarActions(children: [
            _buildSyncStatusIndicator(),
            const SizedBox(width: 4),
            _buildDeliveryBadge(),
            const SizedBox(width: 4),
            _buildCancelledBadge(),
            const SizedBox(width: 4),
            ProfileIcon(
              user: ref.watch(authProvider),
              showLanguage: false,
              onOpenSettings: _openSettings,
              onLogout: _confirmAndLogout,
            ),
          ]),
        ],
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('$e', style: const TextStyle(color: AppColors.softText)),
              const SizedBox(height: 16),
              FilledButton.icon(
            onPressed: () => ref.read(waiterProvider.notifier).refreshSilent(),
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('هەوڵدنەوە')),
              ),
            ],
          ),
        ),
        data: (tables) => Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: ResponsiveGridView(
            desktopColumns: 6,
            tabletColumns: 4,
            mobileColumns: 2,
            spacing: 16,
            runSpacing: 16,
            childAspectRatio: 0.95,
            itemCount: tables.length,
            itemBuilder: (context, index) {
            final table = tables[index];
            final color = _statusColor(table.status);
            return TableCard(
              table: table,
              statusColor: color,
              statusText: _statusText(table.status),
              statusIcon: _statusIcon(table.status),
              index: index,
              onTap: () => _openTable(table),
              onLongPress: null,
            );
          },
          ),
        ),
      ),
    );
  }

  /// Opens a table for this captain, or explains why not.
  ///
  /// One captain per table is the rule, and it is checked on the way in for
  /// every table regardless of its state. It used to be checked only for tables
  /// that already had guests, so an empty table was a way straight past it - two
  /// captains could sit down at the same free table and only one of them would
  /// ever find out. The check is also repeated by the page itself when it takes
  /// the lock, because a table can be taken between the tap and the open.
  Future<void> _openTable(TableModel table) async {
    final db = ref.read(localDbProvider);
    final myUserId = ref.read(authProvider)?.id;
    final lock = await db.getTableLockById(table.id);
    if (lock != null && lock.userId != myUserId) {
      if (!mounted) return;
      await _showTableTakenDialog(lock);
      return;
    }
    if (!mounted) return;
    if (table.status == TableStatus.empty) {
      _showGuestCountDialog(table.id);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TablePage(tableNumber: table.id),
      ),
    );
  }

  /// A blocking dialog, not a snackbar. A snackbar can be missed or covered by
  /// whatever the captain was doing, and this is a hard stop - the screen has to
  /// wait for them to acknowledge whose table it is.
  Future<void> _showTableTakenDialog(TableLock lock) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.person_pin_rounded, color: AppColors.primary, size: 40),
        title: Text(
          context.tr('ئەم مێزە لای کاپتن یان لای کاشێر کراوەیە'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                lock.userName.isEmpty ? context.tr('ناسەرەوە') : lock.userName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.trp('ببورە {role} {name} لەناو مێزەکەدایە، کاتێکیتر هەوڵ بدەوە', {
                'role': lock.role == 'cashier' ? context.tr('کاشێر') : context.tr('کاپتن'),
                'name': lock.userName,
              }),
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.7, fontSize: 15),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(context.tr('باشە، تێدەگەم'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}


