import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_log.dart';
import 'language.dart';
import 'qa_harness.dart';
import 'responsive.dart';
import 'theme.dart';
import '../providers/auth_provider.dart';
import '../providers/waiter_provider.dart';
import '../providers/printer_provider.dart';
import '../providers/network_lockdown_provider.dart';
import '../database/local_db.dart';
import '../services/sync_provider.dart';
import '../services/network_guard_service.dart';
import '../widgets/network_lock_screen.dart';
import '../models/user_model.dart';
import '../page/waiter/waiter_home_page.dart';
import '../page/cashier/cashier_home_page.dart';
import '../page/cashier/cashier_welcome_page.dart';
import '../page/admin/admin_home_page.dart';
import '../page/owner/owner_home_page.dart';
import '../page/login/login_page.dart';

class AppState extends InheritedWidget {
  final AppLanguage currentLanguage;
  final Function(AppLanguage) onLanguageChanged;

  const AppState({
    super.key,
    required this.currentLanguage,
    required this.onLanguageChanged,
    required super.child,
  });

  static AppState of(BuildContext context) {
    final AppState? result = context.dependOnInheritedWidgetOfExactType<AppState>();
    return result!;
  }

  @override
  bool updateShouldNotify(AppState oldWidget) {
    return oldWidget.currentLanguage != currentLanguage;
  }
}

class RamyarPosApp extends ConsumerStatefulWidget {
  const RamyarPosApp({super.key});

  @override
  ConsumerState<RamyarPosApp> createState() => _RamyarPosAppState();
}

class _RamyarPosAppState extends ConsumerState<RamyarPosApp> {
  AppLanguage _currentLanguage = AppLanguage.kurdish;
  bool _initialized = false;
  bool _keepAliveStarted = false;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Refresh the tables UI whenever a server snapshot lands on this device.
    onSyncDataApplied = () {
      ref.read(waiterProvider.notifier).refreshSilent();
    };
    _initAuth();
  }

  Future<void> _startAndroidKeepAlive() async {
    if (kIsWeb || _keepAliveStarted) return;
    _keepAliveStarted = true;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        const channel = MethodChannel('com.kalakchi.ramyar.pos/keepalive');
        await channel.invokeMethod<void>('requestNotificationPermission');
        await channel.invokeMethod<void>('startService');
      }
    } catch (_) {}
  }

  void _wireNetworkGuard() {
    final guard = NetworkGuardService.instance;
    guard.onNetworkLost = () {
      appLog('[App] Network guard triggered lockdown');
      final user = ref.read(authProvider);
      if (user == null) {
        // No session - just surface the blocking Wi-Fi banner at the login
        // screen (nobody can log in while the restaurant network is down).
        ref.read(logoutReasonProvider.notifier)
            .set(NetworkGuardService.wifiLostBanner);
        return;
      }
      // LOCKDOWN instead of logout: the session and the exact screen stay
      // alive underneath a full-screen blocker. When the restaurant network
      // returns (onNetworkRestored), the blocker is removed automatically and
      // the worker carries on where they stopped - no PIN re-entry. The socket
      // server keeps running so reconnecting clients are still served.
      final status = guard.status.value;
      ref.read(networkLockProvider.notifier).lock(
            status == RestaurantNetworkStatus.wrongNetwork
                ? NetworkLockReason.wrongNetwork
                : NetworkLockReason.offline,
            localIp: guard.lastLocalIp,
          );
    };
    guard.onNetworkRestored = () {
      appLog('[App] Network guard restored - unlocking');
      ref.read(logoutReasonProvider.notifier).clear();
      ref.read(networkLockProvider.notifier).unlock();
    };
    guard.startMonitoring();
  }

  Future<void> _initAuth() async {
    _wireNetworkGuard();
    await ref.read(authProvider.notifier).tryAutoLogin();
    final user = ref.read(authProvider);
    if (user != null && user.role == UserRole.waiter) {
      await ref.read(waiterProvider.notifier).syncTableScope();
    }
    // This device may be the central server from an earlier session, and the
    // restaurant's captains send their orders to it whether or not anyone is
    // sitting here. The rule is in [shouldStartServerAtBoot] so it can be
    // tested; it is not "nobody is signed in", which left a real shop broken -
    // a cashier whose session was restored with a closed shift lands on the
    // welcome screen and never reaches its own `startSyncServer`, so a device
    // explicitly flagged as the server answered on nothing and every captain's
    // order stopped arriving with no error anywhere.
    if (shouldStartServerAtBoot(user)) {
      try {
        if (await isServerDevice()) {
          await ref.read(printerProvider.notifier).load();
          await startBackgroundServerAtBoot(
            ref.read(localDbProvider),
            ref.read(syncConnectionProvider.notifier),
            printerConfig: ref.read(printerProvider),
          );
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _initialized = true);
  }

  void _changeLanguage(AppLanguage newLanguage) {
    setState(() => _currentLanguage = newLanguage);
  }

  @override
  Widget build(BuildContext context) {
    // دوای دەچنە ژوورەوە (خۆکار یان دەستی) لە ئەندرۆید خزمەتگوزاری پسوڕەوە
    // دەست پێ دەکرێت تا ئەپەکە لە باگراوەند نەکوژرێتەوە و هەمیشە بەستراو بێت.
    ref.listen<UserModel?>(authProvider, (prev, next) {
      if (next != null && prev == null) {
        _startAndroidKeepAlive();
      }
    });
    final textDirection = LanguageHelper.getTextDirection(_currentLanguage);

    Widget home;
    if (!_initialized) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else {
      final user = ref.watch(authProvider);
      if (user != null) {
        switch (user.role) {
          case UserRole.waiter:
            home = const WaiterHomePage();
          case UserRole.cashier:
            // A cashier without a running shift lands on the welcome screen so
            // THE cashier decides when to officially open one - a closed shift
            // is never silently reopened, and this redirect renders (no route
            // push), so the app home can swap the initial route in place
            // without stacking a second copy of the page.
            home = _CashierRedirect(userId: user.id);
          case UserRole.admin:
            home = const AdminHomePage();
          case UserRole.owner:
            home = const OwnerHomePage();
        }
      } else {
        home = const LoginPage();
      }
    }

    return AppState(
      currentLanguage: _currentLanguage,
      onLanguageChanged: _changeLanguage,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        // Names the top route for the QA screen digest; inert in a normal build.
        navigatorObservers: [qaNavigatorObserver],
        title: 'RAMYAR POS',
        theme: AppTheme.lightTheme,
        builder: (context, child) {
          // تێکستی گەورە (بەهۆی ڕێکخستنی فۆنتی own سیستەمەکە) دەتوانێت
          // لەیبڵە درێژەکانی بۆکسەکان ببڕێت — لێرە سنوورێکی سەرەوە (1.15)
          // بۆ تێکست دادەنرێت بەڵام لە کاتی ئاساییدا (1.0) هیچ ناکات.
          final media = MediaQuery.of(context);
          final capped = media.textScaler.clamp(maxScaleFactor: 1.15);
          Widget content =
              Directionality(textDirection: textDirection, child: child!);
          // Network lockdown: when the restaurant network is lost while a
          // worker is signed in, a full-screen blocker covers EVERY route
          // (home and pushed routes) so the whole system stops. Clearing the
          // state (network restored) removes it automatically - the worker
          // resumes exactly where they were, no PIN re-entry.
          final lockState = ref.watch(networkLockProvider);
          if (lockState.locked && ref.read(authProvider) != null) {
            content = Stack(
              textDirection: textDirection,
              children: [
                content,
                NetworkLockScreen(
                  reason: lockState.reason ?? NetworkLockReason.offline,
                ),
              ],
            );
          }
          // Small-screen zoom-out: the whole app (every route, dialog and lock
          // screen) renders smaller on an iPad (0.9) and now on an Android/iOS
          // phone (0.85) too, so the identical laptop design shows far more at
          // once. Implemented like a browser zoom-out: the app lays out as if
          // the screen were 1/zoom bigger (more columns/rows fit) and is then
          // scaled back down, so nothing is cut off and there is no empty
          // margin. The Windows laptop, web and every tablet stay
          // byte-for-byte untouched.
          final double? zoom = Responsive.isIpadWide(media)
              ? Responsive.ipadZoomOut
              : Responsive.isPhoneWide(media)
                  ? Responsive.phoneZoomOut
                  : null;
          if (zoom != null) {
            final virtual = Size(
              media.size.width / zoom,
              media.size.height / zoom,
            );
            return MediaQuery(
              data: media.copyWith(size: virtual, textScaler: capped),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: virtual.width,
                  maxWidth: virtual.width,
                  minHeight: virtual.height,
                  maxHeight: virtual.height,
                  child: Transform.scale(
                    scale: zoom,
                    alignment: Alignment.topLeft,
                    child: content,
                  ),
                ),
              ),
            );
          }
          if (capped != media.textScaler) {
            content =
                MediaQuery(data: media.copyWith(textScaler: capped), child: content);
          }
          return content;
        },
        home: home,
      ),
    );
  }
}

class _CashierRedirect extends ConsumerStatefulWidget {
  final int userId;
  const _CashierRedirect({required this.userId});

  @override
  ConsumerState<_CashierRedirect> createState() => _CashierRedirectState();
}

class _CashierRedirectState extends ConsumerState<_CashierRedirect> {
  bool? _hasShift;

  @override
  void initState() {
    super.initState();
    _checkShift();
  }

  Future<void> _checkShift() async {
    // True when a shift is running. A cashier without a running shift is sent
    // to the welcome page so THEY decide when to officially open one - a
    // closed shift is never silently reopened. This redirect only RENDERS the
    // right page (no route push), so the app home swaps the initial route in
    // place and a second copy of the page is never stacked.
    final shift = await ref.read(localDbProvider).getActiveShift(widget.userId);
    if (!mounted) return;
    setState(() => _hasShift = shift != null);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasShift == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _hasShift! ? const CashierHomePage() : const CashierWelcomePage();
  }
}

class RamyarPosAppWrapper extends ConsumerWidget {
  const RamyarPosAppWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const RamyarPosApp();
  }
}
