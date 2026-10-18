import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app.dart';
import '../../core/colors.dart';
import '../../core/digits.dart';
import '../../core/language.dart';
import '../../core/responsive.dart';
import '../../database/local_db.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/waiter_provider.dart';
import '../../services/app_localizations.dart';
import '../../services/network_guard_service.dart';
import '../../services/sync_provider.dart';
import '../../widgets/language_flag.dart';
import '../admin/admin_home_page.dart';
import '../cashier/cashier_home_page.dart';
import '../cashier/cashier_welcome_page.dart';
import '../owner/owner_home_page.dart';
import '../waiter/waiter_home_page.dart';
import 'connect_ip_page.dart';
import 'hama_page.dart';

/// Reusable 5-digit PIN keypad (dots + numeric grid). Supports an `enabled`
/// flag so it can be locked down while the network is not the restaurant one.
class PinKeypad extends StatefulWidget {
  final bool enabled;
  final bool isLoading;
  final int pinLength;
  final double scale;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onComplete;
  final VoidCallback onBackspace;

  const PinKeypad({
    super.key,
    this.enabled = true,
    this.isLoading = false,
    this.pinLength = 5,
    this.scale = 1.0,
    required this.onChanged,
    required this.onComplete,
    required this.onBackspace,
  });

  @override
  State<PinKeypad> createState() => PinKeypadState();
}

class PinKeypadState extends State<PinKeypad> {
  /// The PIN is held in a real (invisible) text field so the device keyboard
  /// works everywhere: the physical keyboard on the laptop/Windows cashier and
  /// the phone's own soft keyboard on Android. The on-screen dialer is just a
  /// second way to feed the same controller.
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocus = FocusNode(debugLabel: 'pin_device_keyboard');
  bool _sanitizing = false;

  String get pin => _pinController.text;

  /// Exposed for tests: lets a test check/focus the device-keyboard input.
  FocusNode get keyboardFocusNode => _pinFocus;

  @override
  void initState() {
    super.initState();
    // Single place that reacts to the field changing (typed from the device
    // keyboard OR tapped on the on-screen dialer): normalize, clamp, refresh
    // the dots, notify and auto-submit once the PIN is complete.
    _pinController.addListener(_onPinChanged);
  }

  @override
  void dispose() {
    _pinController.removeListener(_onPinChanged);
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _onPinChanged() {
    if (_sanitizing) return;
    _sanitizing = true;
    try {
      // Digits must stay Latin (0-9) in every language. Localized forms an
      // Arabic/Persian (or fullwidth) keyboard can produce are mapped back to
      // ASCII here; anything that is not a digit is dropped.
      final sanitized = toLatinDigits(_pinController.text).replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final clamped = sanitized.length > widget.pinLength
          ? sanitized.substring(0, widget.pinLength)
          : sanitized;
      if (clamped != _pinController.text) {
        _pinController.value = TextEditingValue(
          text: clamped,
          selection: TextSelection.collapsed(offset: clamped.length),
        );
        return;
      }
      if (mounted) setState(() {});
      if (!widget.enabled || widget.isLoading) return;
      widget.onChanged(clamped);
      if (clamped.length == widget.pinLength) widget.onComplete(clamped);
    } finally {
      _sanitizing = false;
    }
  }

  /// Tap on the on-screen dialer digit.
  void _handlePinInput(String value) {
    if (!widget.enabled || widget.isLoading) return;
    if (_pinController.text.length >= widget.pinLength) return;
    final digit = toLatinDigits(value).replaceAll(RegExp(r'[^0-9]'), '');
    if (digit.isEmpty) return;
    _pinController.value = TextEditingValue(
      text: _pinController.text + digit,
      selection: TextSelection.collapsed(
        offset: _pinController.text.length + digit.length,
      ),
    );
  }

  /// Backspace key (on-screen dialer or device keyboard).
  void _onBackspace() {
    if (!widget.enabled || widget.isLoading) return;
    if (_pinController.text.isEmpty) return;
    final next = _pinController.text.substring(
      0,
      _pinController.text.length - 1,
    );
    _pinController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onBackspace();
  }

  /// "OK"/"check" on the dialer, or Enter/done on the device keyboard.
  void _openSubmit() {
    if (widget.isLoading || widget.pinLength != _pinController.text.length) {
      return;
    }
    widget.onComplete(_pinController.text);
  }

  /// Clears the current pin (used on auth failure).
  void reset() {
    if (_pinController.text.isEmpty) return;
    _pinController.clear();
  }

  /// Brings up the device keyboard (mobile soft keyboard / laptop physical
  /// keyboard) so the PIN can be typed there instead of the on-screen dialer.
  void _requestKeyboardFocus() {
    if (!widget.enabled || widget.isLoading) return;
    _pinFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final keyFontSize = (20 * s).clamp(15.0, 26.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // An invisible but focusable field that captures the device keyboard -
        // the physical one on a laptop and the soft one on a phone, in ANY
        // layout. Whatever the keyboard produces is sanitized to 0-9 in the
        // controller listener, so a Kurdish/Arabic/Persian/English keyboard all
        // type the same PIN. Offstage keeps it out of the painted tree (and out
        // of text finders) while still owning the real text-input connection.
        _buildKeyboardField(),
        // The dots are also the focus target for the device keyboard:
        // tapping them opens the phone keyboard / arms the laptop's.
        _buildDotIndicatorRow(s),
        SizedBox(height: 24 * s),
        // The keypad always looks like a standard (English) dialer - 1-2-3 on
        // the top row starting from the LEFT - in EVERY language. Forcing the
        // grid to LTR stops RTL languages (Kurdish/Arabic/Persian) from
        // mirroring the number order.
        Directionality(
          textDirection: TextDirection.ltr,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10 * s,
              crossAxisSpacing: 10 * s,
              childAspectRatio: 1.5,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              if (index == 9) {
                return _buildKeypadButton(
                  child: Icon(
                    Icons.backspace_outlined,
                    color: widget.enabled
                        ? AppColors.darkText
                        : AppColors.softText.withValues(alpha: 0.35),
                    size: 20 * s,
                  ),
                  onPressed: _onBackspace,
                  backgroundColor: AppColors.background,
                );
              } else if (index == 10) {
                return _buildKeypadButton(
                  child: Text(
                    toLatinDigits("0"),
                    style: TextStyle(
                      fontSize: keyFontSize,
                      fontWeight: FontWeight.bold,
                      color: widget.enabled
                          ? AppColors.darkText
                          : AppColors.softText.withValues(alpha: 0.35),
                    ),
                  ),
                  onPressed: () => _handlePinInput("0"),
                );
              } else if (index == 11) {
                return _buildKeypadButton(
                  child: widget.isLoading
                      ? SizedBox(
                          width: 20 * s,
                          height: 20 * s,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.check_circle_rounded,
                          color: widget.enabled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                          size: 24 * s,
                        ),
                  onPressed: _openSubmit,
                  backgroundColor: widget.enabled
                      ? AppColors.primary
                      : AppColors.softText.withValues(alpha: 0.4),
                );
              } else {
                final number = toLatinDigits((index + 1).toString());
                return _buildKeypadButton(
                  child: Text(
                    number,
                    style: TextStyle(
                      fontSize: keyFontSize,
                      fontWeight: FontWeight.bold,
                      color: widget.enabled
                          ? AppColors.darkText
                          : AppColors.softText.withValues(alpha: 0.35),
                    ),
                  ),
                  onPressed: () => _handlePinInput(number),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  /// The dot indicators + a subtle hint that the device keyboard also works.
  /// Tapping it focuses the hidden field (opens the mobile keyboard).
  Widget _buildDotIndicatorRow(double s) {
    return GestureDetector(
      key: const ValueKey('pin_dots_tap_target'),
      behavior: HitTestBehavior.opaque,
      onTap: _requestKeyboardFocus,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...List.generate(widget.pinLength, (index) {
            final isFilled = index < _pinController.text.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.symmetric(horizontal: 7 * s),
              width: 16 * s,
              height: 16 * s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFilled ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: widget.enabled
                      ? (isFilled
                            ? AppColors.primary
                            : AppColors.softText.withValues(alpha: 0.4))
                      : AppColors.softText.withValues(alpha: 0.2),
                  width: 2.5 * s,
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_outlined,
            size: 15 * s,
            color: widget.enabled
                ? AppColors.softText.withValues(alpha: 0.7)
                : AppColors.softText.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
  }

  /// Invisible field that owns the device keyboard connection. It stays
  /// [Offstage] so it never paints and never shows up in text finders: the
  /// digits are reflected only by the dot indicators above.
  Widget _buildKeyboardField() {
    return Offstage(
      offstage: true,
      child: TextField(
        key: const ValueKey('pin_keyboard_input'),
        controller: _pinController,
        focusNode: _pinFocus,
        enabled: widget.enabled && !widget.isLoading,
        showCursor: false,
        enableInteractiveSelection: false,
        // Not forced to a numeric keyboard: every device keyboard style
        // (letters, symbols, Arabic/Persian, ...) can feed the field, and
        // only real digits are kept by the sanitizer.
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.none,
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontSize: 10),
        inputFormatters: [
          // Order matters: keep only digits FIRST (a pasted string like
          // "A-1 b2.3" must keep digits 1, 2 and 3), THEN clamp to the PIN
          // length. The reverse order truncates the raw string at 5 chars and
          // silently drops valid digits that follow.
          FilteringTextInputFormatter.allow(
            RegExp('[0-9\\u0660-\\u0669\\u06F0-\\u06F9\\uFF10-\\uFF19]'),
          ),
          LengthLimitingTextInputFormatter(widget.pinLength),
        ],
        decoration: const InputDecoration(
          border: InputBorder.none,
          counterText: '',
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (_) => _openSubmit(),
      ),
    );
  }

  Widget _buildKeypadButton({
    required Widget child,
    required VoidCallback onPressed,
    Color? backgroundColor,
  }) {
    return Material(
      color: backgroundColor ?? AppColors.background.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: widget.enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(14),
        child: Center(child: child),
      ),
    );
  }
}

/// Full login / PIN screen. Disables the keypad and shows a blocking banner
/// whenever the device is not confirmed to be on the restaurant network, and
/// displays the "Network Lost / Access Denied" dialog after a forced logout.
class PinLoginPage extends ConsumerStatefulWidget {
  const PinLoginPage({super.key});

  @override
  ConsumerState<PinLoginPage> createState() => _PinLoginPageState();
}

class _PinLoginPageState extends ConsumerState<PinLoginPage> {
  final GlobalKey<PinKeypadState> _keypadKey = GlobalKey<PinKeypadState>();
  bool _isLoading = false;
  bool _networkSecure = true;
  bool _blockedByWifi = false;

  @override
  void initState() {
    super.initState();
    _networkSecure = NetworkGuardService.instance.isSecure;
    NetworkGuardService.instance.status.addListener(_onNetworkChanged);
    _blockedByWifi = ref.read(logoutReasonProvider) != null;
  }

  void _onLogoutReasonChanged(String? next) {
    if (next == NetworkGuardService.networkLostMessage) {
      ref.read(logoutReasonProvider.notifier).clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.wifi_off_rounded,
              color: AppColors.danger,
              size: 34,
            ),
            title: Text(
              context.tr('تۆڕ لە دەست چوو'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              NetworkGuardService.networkLostMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.darkText),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.tr('باشە')),
              ),
            ],
          ),
        );
      });
    } else if (next == NetworkGuardService.wifiLostBanner && mounted) {
      setState(() => _blockedByWifi = true);
    } else if (next == null && mounted) {
      setState(() => _blockedByWifi = false);
    }
  }

  @override
  void dispose() {
    NetworkGuardService.instance.status.removeListener(_onNetworkChanged);
    super.dispose();
  }

  void _onNetworkChanged() {
    final secure = NetworkGuardService.instance.isSecure;
    if (!mounted) return;
    setState(() {
      _networkSecure = secure;
      if (secure) _blockedByWifi = false;
    });
  }

  Future<void> _onPinComplete(String pin) async {
    if (_isLoading || !_networkSecure) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final user = await ref.read(authProvider.notifier).loginWithPin(pin);
    if (!mounted) return;

    if (user != null) {
      // Only a captain gets a narrowed table list; every other role (a cashier
      // above all) must see the whole floor. Started without awaiting so this
      // stays synchronous up to the navigation below.
      unawaited(ref.read(waiterProvider.notifier).syncTableScope());
      // When this login page IS the app's home-built initial route (named '/',
      // i.e. right after boot), the auth-driven app home swaps it in place -
      // navigating here too would stack a second copy of the same page. When
      // the page was pushed on top of a live session (back-to-login and
      // multi-account logins) the home cannot swap a manual route, so replace
      // it explicitly. Read before anything below is awaited, so the decision
      // is made against the same route the login started on.
      final route = ModalRoute.of(context);
      final isHomeRoute =
          route != null &&
          route.isFirst &&
          route.settings.name == Navigator.defaultRouteName;
      if (!isHomeRoute) {
        Widget page;
        switch (user.role) {
          case UserRole.waiter:
            page = const WaiterHomePage();
          case UserRole.cashier:
            final activeShift = await ref
                .read(localDbProvider)
                .getActiveShift(user.id);
            if (!mounted) return;
            page = activeShift != null
                ? const CashierHomePage()
                : const CashierWelcomePage();
          case UserRole.admin:
            page = const AdminHomePage();
          case UserRole.owner:
            page = const OwnerHomePage();
        }
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => page));
      }
      return;
    } else {
      final reason = ref.read(logoutReasonProvider);
      if (reason != null) {
        setState(() {
          _isLoading = false;
          _blockedByWifi = true;
        });
      } else {
        final noticeNotifier = ref.read(loginNoticeProvider);
        final notice = noticeNotifier.current;
        if (notice != null && notice.isNotEmpty) {
          noticeNotifier.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(notice),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() => _isLoading = false);
          _keypadKey.currentState?.reset();
        } else {
          // No IP-binding notice is pending: tell the user why the PIN failed.
          // This device may already be bound (codes were saved through the
          // "!" Connect page) - then the PIN itself matches no account in the
          // synced registry here. Without any saved code the plain
          // "wrong password" message is the honest answer.
          final codes = await getDeviceAccessCodes();
          if (!mounted) return;
          if (codes.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.tr(
                    'ئەم PINـە لەم ئامێرەدا نەدۆزرایەوە - دڵنیابە IPـەکە ڕاستە و ئامێرەکە لەسەر هەمان وای-فایە',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: AppColors.danger,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.tr('وشەی نهێنی هەڵەیە'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: AppColors.danger,
                duration: const Duration(seconds: 1),
              ),
            );
          }
          setState(() => _isLoading = false);
          _keypadKey.currentState?.reset();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      logoutReasonProvider,
      (prev, next) => _onLogoutReasonChanged(next),
    );
    final offline = _blockedByWifi || !_networkSecure;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bg_login.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: _buildLanguageSelector(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildIpConnectIconButton(),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildPinCard(offline),
                    ],
                  ),
                ),
              ),
              // The invisible owner-access target in the top-left corner: the
              // only way into the hidden hama connect page from the login
              // screen (see hama_page.dart). It carries the key the test looks
              // for so a silent removal of it fails the suite instead of
              // quietly locking the owner out.
              Positioned(
                left: 0,
                top: 0,
                child: Semantics(
                  label: 'hama',
                  button: true,
                  child: GestureDetector(
                    key: const ValueKey('hama_hidden_button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HamaPage()),
                    ),
                    child: const SizedBox(width: 56, height: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The "!" icon button (icon only, next to the language selector): opens the
  /// pre-login Connect page where the account IP (given to each staff member by
  /// the owner) is entered and connected, after which the member logs in with
  /// their PIN.
  Widget _buildIpConnectIconButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ConnectIpPage()));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  '!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Scale factor that grows the PIN card on big screens (tablet, desktop,
  /// Windows) and gently shrinks it on very narrow phones, so the keypad never
  /// overflows and always looks balanced. It is width-driven for a smooth
  /// "grows as the screen grows" feel, height-capped so short screens
  /// (landscape phones / small devices) keep the whole stack nearly visible.
  double _loginScale(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    double s;
    if (w >= 1400) {
      s = 1.60;
    } else if (w >= Responsive.desktopBreakpoint) {
      // Any iPad (740-1399) gets the same 1.45 scale as a laptop window: the
      // login opens on iPad exactly as it does on the Windows machine.
      s = 1.45;
    } else if (w >= 680) {
      s = 1.20;
    } else if (w >= 480) {
      s = 1.15;
    } else if (w >= 428) {
      s = 1.05;
    } else if (w >= 360) {
      s = 1.0;
    } else {
      s = (w / 360).clamp(0.80, 1.0);
    }

    // Total login stack height at scale 1.0 (language bar + gaps + PIN card)
    // is ~486px on the reference phones. Cap the scale so short screens never
    // turn the keypad into a far-away scroll target.
    const baseStackHeight = 486.0;
    final byHeight = (h - 24) / baseStackHeight;
    if (byHeight < s) s = byHeight.clamp(0.72, s);
    return s.clamp(0.72, 1.6);
  }

  Widget _buildPinCard(bool offline) {
    final scale = _loginScale(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale.clamp(0.86, 1.0)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320 * scale),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 24 * scale,
            vertical: 24 * scale,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(12 * scale),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  offline ? Icons.wifi_off_rounded : Icons.lock_open_rounded,
                  color: offline ? AppColors.danger : AppColors.primary,
                  size: 24 * scale,
                ),
              ),
              SizedBox(height: 16 * scale),
              if (offline) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    NetworkGuardService.wifiLostBanner,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: 16 * scale),
              ],
              PinKeypad(
                key: _keypadKey,
                enabled: !offline,
                isLoading: _isLoading,
                scale: scale,
                onChanged: (_) {},
                onComplete: _onPinComplete,
                onBackspace: () {},
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    final appState = AppState.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppLanguage>(
          value: appState.currentLanguage,
          // No custom "globe" icon: the default dropdown arrow is shown.
          dropdownColor: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          onChanged: (AppLanguage? newLang) {
            if (newLang != null) appState.onLanguageChanged(newLang);
          },
          items: AppLanguage.values.map((AppLanguage lang) {
            return DropdownMenuItem<AppLanguage>(
              value: lang,
              child: LanguageLabel(
                language: lang,
                flagWidth: 20,
                textStyle: const TextStyle(
                  fontSize: 13,
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
}
