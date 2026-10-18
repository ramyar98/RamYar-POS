import 'package:ramyar_pos/services/owner_access.dart';
import 'package:ramyar_pos/services/owner_credentials.dart';

/// A **stand-in** owner PIN for the test suite.
///
/// The real owner PIN is not in this repository in any form - not as a literal,
/// not as a hash. So instead of hardcoding it here, the tests install a digest
/// derived from this throwaway value. The whole production path is still
/// exercised: PBKDF2 with the real salt and round count, plus the constant-time
/// comparison, only the expected digest is swapped.
const testOwnerPin = '90807';

/// Makes [testOwnerPin] the accepted owner PIN for the rest of the test run,
/// and unlocks the hidden owner gate (see [OwnerAccess]) so owner logins behave
/// exactly as they did before the hidden "hama" route existed. A test that
/// wants to assert the locked behaviour calls `OwnerAccess.lock()` itself.
void installTestOwnerPin() {
  OwnerCredentials.setExpectedDigestForTesting(
    OwnerCredentials.deriveDigest(testOwnerPin),
  );
  OwnerAccess.setTestBypass(true);
}

/// Restores the shipped digest and re-locks the hidden owner gate. Call this in
/// `tearDownAll` so a file that installs it cannot leak into another test file.
void uninstallTestOwnerPin() {
  OwnerCredentials.clearExpectedDigestForTesting();
  OwnerAccess.setTestBypass(false);
  OwnerAccess.lock();
}
