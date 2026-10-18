/// Session gate for the hidden owner access.
///
/// The owner PIN is only accepted after the hidden "hama" connect page has been
/// completed on this launch. The flag lives in memory only: closing the app (or
/// logging out) locks the owner path again, so the hidden route has to be
/// re-used before the next owner login. Staff logins are never affected.
class OwnerAccess {
  OwnerAccess._();

  static bool _unlocked = false;

  /// Test-only bypass so the suite does not have to walk the hidden route
  /// before every owner login. Never set from application code.
  static bool _testBypass = false;

  /// Whether the hidden owner route has been completed for this session.
  static bool get isUnlocked => _testBypass || _unlocked;

  /// Grants owner access for the rest of the session.
  static void unlock() => _unlocked = true;

  /// Revokes owner access, so the hidden route is needed again.
  static void lock() => _unlocked = false;

  /// Enables/disables the test bypass. Only called from `test/`.
  static void setTestBypass(bool value) => _testBypass = value;
}
