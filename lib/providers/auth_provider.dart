import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_prefs.dart';
import '../models/user_model.dart';
import '../database/local_db.dart';
import '../services/network_guard_service.dart';
import '../services/owner_access.dart';
import '../services/owner_credentials.dart';
import '../services/sync_provider.dart';

/// User session: `null` means logged out / sitting at the login screen.
final authProvider = StateNotifierProvider<AuthNotifier, UserModel?>((ref) {
  return AuthNotifier(
    ref.read(localDbProvider),
    ref.read(logoutReasonProvider.notifier),
    LoginNoticeNotifier(),
  );
});

/// The same [LoginNoticeNotifier] instance owned by [AuthNotifier], exposed
/// so the login screen can read and clear the provisioning notice. Sharing
/// ONE instance matters: [AuthNotifier] writes to it during login attempts,
/// so a separate registration would never see those writes.
final loginNoticeProvider = Provider<LoginNoticeNotifier>(
  (ref) => ref.watch(authProvider.notifier).loginNotice,
);

/// Holds the reason state surfaced by a forced logout (network guard) so the
/// login screen can show the blocking "Network Lost" dialog / banner.
final logoutReasonProvider =
    StateNotifierProvider<LogoutReasonNotifier, String?>(
        (ref) => LogoutReasonNotifier());

class LogoutReasonNotifier extends StateNotifier<String?> {
  LogoutReasonNotifier() : super(null);

  void set(String? reason) => state = reason;

  void clear() => state = null;
}

/// Holds a localizable message key explaining why a staff login was refused
/// because the device has not been provisioned with the account's IP yet
/// (entered on the login screen's "Connect" page). Cleared on success.
class LoginNoticeNotifier extends StateNotifier<String?> {
  LoginNoticeNotifier() : super(null);

  void set(String? key) => state = key;

  void clear() => state = null;

  /// Read the current notice outside the notifier. `StateNotifier.state` is
  /// protected/visible-for-testing, so exposing a public getter keeps the
  /// login screen (which is not a subclass) warning-free.
  String? get current => state;
}

class AuthNotifier extends StateNotifier<UserModel?> {
  final LocalDatabase _db;
  final LogoutReasonNotifier _logoutReason;
  final LoginNoticeNotifier _loginNotice;

  AuthNotifier(this._db, this._logoutReason, this._loginNotice) : super(null);

  /// Exposes the notice notifier this notifier writes to, so the login screen
  /// can observe/clear it through [loginNoticeProvider].
  LoginNoticeNotifier get loginNotice => _loginNotice;

  Future<UserModel?> _persistSession(UserModel user) async {
    state = user;
    await AppPrefs.instance.setInt('loggedUserId', user.id);
    return user;
  }

  /// Strict network-first login. Refuses to authenticate (and flags the login
  /// screen to show the Wi-Fi blocking banner) unless the device is confirmed
  /// to be on the restaurant network.
  Future<UserModel?> loginWithPin(String pin) async {
    final guard = NetworkGuardService.instance;
    final verdict = await guard.evaluateNow();
    if (verdict != RestaurantNetworkStatus.secure) {
      _logoutReason.set(NetworkGuardService.wifiLostBanner);
      return null;
    }
    if (OwnerCredentials.matches(pin)) {
      // The owner PIN only works after the hidden "hama" connect page was
      // completed on this launch. Until then the owner path stays locked and
      // the screen explains how to reach it.
      if (!OwnerAccess.isUnlocked) {
        _loginNotice.set(
            'تکایە کۆنێکت لاپتۆپی بکە');
        return null;
      }
      _loginNotice.clear();
      _logoutReason.clear();
      return _persistSession(OwnerCredentials.masterUser);
    }
    final user = await _db.getUserByPin(pin);
    if (user != null) {
      final anyAccessCode = await _db.hasAnyAccessCode();
      // Fresh/default installs may still use the legacy placeholder accounts
      // until the owner adds per-user IP bindings. Once any user has an access
      // code, the device-IP guard becomes active for all staff PINs.
      if (!anyAccessCode) {
        _loginNotice.clear();
        _logoutReason.clear();
        return _persistSession(user);
      }

      // LAN provisioning rule: a staff account only unlocks on a device after
      // the account's own IP (the one the owner created it with) was entered
      // on the login screen's "Connect" page. A device may be bound to many
      // IPs at once, so any match unlocks. Until then only the owner
      // (خاوەن سیستەم) exists on this device - nobody else can log in.
      if (!await _deviceIsProvisionedFor(user)) {
        _loginNotice.set(
            'چوونە ژوورەوە ناکرێت هەتا ئەو IPـەی بۆ هەژمارەکەت دراوە داخل نەکرێت - لە دوگمەی (!) بەستنەوە بکە');
        return null;
      }
      _loginNotice.clear();
      _logoutReason.clear();
      return _persistSession(user);
    }
    return null;
  }

  /// Compatibility entry-point (kept for older callers that call `login`).
  Future<UserModel?> login(String pin) => loginWithPin(pin);

  /// Restores the session saved on this device when the app starts again.
  ///
  /// A staff session is only restored while this device is still provisioned
  /// for it. The saved session used to be restored unconditionally, which meant
  /// that unbinding an account's IP - or taking a tablet from somebody who was
  /// let go - changed nothing until the session was explicitly logged out: the
  /// next launch put that person straight back in. The same check the PIN login
  /// does is applied here, so being removed takes effect immediately.
  Future<void> tryAutoLogin() async {
    final savedId = await AppPrefs.instance.getInt('loggedUserId');
    if (savedId == null) return;
    if (savedId == OwnerCredentials.userId) {
      state = OwnerCredentials.masterUser;
      return;
    }
    final user = await _db.getUserById(savedId);
    if (user == null) return;
    if (!await _deviceIsProvisionedFor(user)) {
      // The saved session is dropped rather than left behind, so the login
      // screen starts from the owner instead of a staff member nobody can
      // explain.
      await AppPrefs.instance.remove('loggedUserId');
      _loginNotice.set(
          'چوونە ژوورەوە ناکرێت هەتا ئەو IPـەی بۆ هەژمارەکەت دراوە داخل نەکرێت - لە دوگمەی (!) بەستنەوە بکە');
      return;
    }
    state = user;
  }

  /// Whether this device may hold a session for [user], per the LAN
  /// provisioning rule: once any account carries an access code the guard is
  /// active for everyone, and a staff account only unlocks on a device that was
  /// bound to the account's own IP.
  Future<bool> _deviceIsProvisionedFor(UserModel user) async {
    if (!await _db.hasAnyAccessCode()) return true;
    final userCode = (user.accessCode ?? '').trim();
    if (userCode.isEmpty) return false;
    return (await getDeviceAccessCodes()).contains(userCode);
  }

  /// Normal, user-initiated logout (clear session, no forced reason).
  Future<void> logout() async {
    state = null;
    // A logout also re-locks the hidden owner route: the owner PIN alone is
    // never enough - the "hama" connect must be done again first.
    OwnerAccess.lock();
    await AppPrefs.instance.remove('loggedUserId');
  }

  /// Security-triggered logout invoked by [NetworkGuardService] when the device
  /// leaves the restaurant Wi-Fi or switches to a foreign network. Ejects the
  /// user to the login screen and records the blocking reason for the modal.
  Future<void> forceLogout() async {
    await logout();
    _logoutReason.set(NetworkGuardService.networkLostMessage);
  }
}