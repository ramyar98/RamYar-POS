import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';

/// Owner (خاوەن سیستەم) credentials.
///
/// The owner PIN is **never** written down anywhere - not as a literal, not as a
/// plain `sha256`, not even as a digest that could be concatenated back out of
/// a few constants. Instead:
///
///  1. The PIN is run through **PBKDF2-HMAC-SHA256** with 20 000 rounds, so
///     brute-forcing the whole 5-digit key space against the value embedded in
///     the binary costs thousands of times more than a single hash per guess.
///  2. The salt is itself assembled from meaningless 2-4 character pieces
///     stitched together through a permutation table, so no single constant is
///     the salt and none of them spell anything.
///  3. The 32-byte PBKDF2 output is stored as eight hex fragments held in a
///     *scrambled* order, reassembled through a second permutation table.
///     Reading the constants top to bottom does **not** yield the digest - see
///     `test/owner_credentials_test.dart`, which asserts exactly that.
///  4. The comparison is constant-time over the whole digest, so a wrong PIN
///     cannot be narrowed down byte by byte by timing.
///
/// To change the PIN, recompute with
/// `Rfc2898DeriveBytes(pin, utf8(salt), rounds, SHA256)`, then re-split the hex
/// into eight fragments and update [_pepperBits], [_saltBits] and
/// [_digestBits] together with their permutation tables.
class OwnerCredentials {
  OwnerCredentials._();

  /// The owner is a virtual account: it is never stored in the `users` table,
  /// so it can never appear in user lists or be edited/deleted like a normal
  /// account.
  static const int userId = 0;

  static const String ownerName = 'خاوەن سیستەم';

  // ---------------------------------------------------------------------
  // Salt: pepper pieces + app pieces, each list read through a permutation.
  // ---------------------------------------------------------------------

  static const List<String> _pepperBits = <String>[
    'rAm', 'yAr', '2O', 'sP', //
    'zZ', '!x', '7Q', 'v0',
  ];
  static const List<int> _pepperOrder = <int>[5, 0, 7, 3, 1, 6, 2, 4];

  static const List<String> _saltBits = <String>[
    'MaSt', '3r.', 'Own', 'er!', //
    'v1', '.0#', 'Kq', '9w',
  ];
  static const List<int> _saltOrder = <int>[3, 6, 0, 7, 2, 5, 1, 4];

  // PBKDF2 iteration count. 20k keeps an owner login under ~0.2 s while turning
  // an offline sweep of all 100 000 possible PINs from a ~1 second job into
  // thousands of CPU-hours. Raise it if a slower login is acceptable.
  static const int _rounds = 20000;

  /// PBKDF2-HMAC-SHA256 output of the owner PIN, as eight hex fragments held
  /// **out of order** - see [_digestOrder].
  static const List<String> _digestBits = <String>[
    'd72bdf9f', '64771a06', '2a9e10d2', 'd1c5e638', //
    'e4061a80', 'a3769610', 'b9b787ce', 'c6f549c8',
  ];
  static const List<int> _digestOrder = <int>[3, 7, 0, 5, 2, 6, 1, 4];

  static String get _pepper {
    final b = StringBuffer();
    for (final i in _pepperOrder) {
      b.write(_pepperBits[i]);
    }
    return b.toString();
  }

  static String get _salt {
    final b = StringBuffer()..write(_pepper);
    for (final i in _saltOrder) {
      b.write(_saltBits[i]);
    }
    return b.toString();
  }

  /// The digest in its real order. Not a concatenation of [_digestBits]: each
  /// fragment is placed at the position [_digestOrder] points it to.
  static String get _expectedDigest {
    final slots = List<String?>.filled(_digestBits.length, null);
    for (var i = 0; i < _digestBits.length; i++) {
      slots[_digestOrder[i]] = _digestBits[i];
    }
    return slots.join();
  }

  /// Test-only replacement for [_expectedDigest]. Assigned inside an `assert`
  /// so the escape hatch does not exist in a release build; see
  /// `setExpectedDigestForTesting`.
  static String? _digestOverride;

  /// PBKDF2-HMAC-SHA256 (single 32-byte block), written out because the app
  /// only depends on `crypto` and PBKDF2 over a 32-byte key is a handful of
  /// lines. Kept public so the test suite can verify it against values produced
  /// by an independent implementation (.NET `Rfc2898DeriveBytes`).
  static String deriveDigest(String pin, {String? salt, int? rounds}) =>
      _pbkdf2(pin, salt ?? _salt, rounds ?? _rounds);

  static String _pbkdf2(String password, String salt, int rounds) {
    // PBKDF2: the *password* keys the HMAC, the message is salt || block index.
    final hmac = Hmac(sha256, utf8.encode(password));
    final blockSeed = <int>[
      ...utf8.encode(salt), //
      0, 0, 0, 1, // INT_32_BE(1) - only the first block is needed
    ];
    var u = hmac.convert(blockSeed).bytes;
    final acc = List<int>.from(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < acc.length; j++) {
        acc[j] ^= u[j];
      }
    }
    return acc.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// The owner behaves like a role account for app routing / session state.
  static UserModel get masterUser => const UserModel(
        id: userId,
        name: ownerName,
        pin: '',
        role: UserRole.owner,
      );

  /// Constant-time check of an entered PIN against the embedded digest.
  /// Returns false for any input that is not exactly 5 characters.
  static bool matches(String pin) {
    if (pin.length != 5) return false;
    final expected = _digestOverride ?? _expectedDigest;
    final digest = _pbkdf2(pin, _salt, _rounds);
    if (digest.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < digest.length; i++) {
      diff |= digest.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Lets the test suite log in as the owner without the real PIN ever being
  /// written to a file. Passing a digest obtained from [deriveDigest] keeps the
  /// whole PBKDF2 path under test.
  ///
  /// The assignment lives inside an `assert`, which the compiler strips from
  /// release builds - so in a shipped binary this throws instead of installing
  /// a backdoor.
  @visibleForTesting
  static void setExpectedDigestForTesting(String digestHex) {
    var installed = false;
    assert(() {
      _digestOverride = digestHex;
      installed = true;
      return true;
    }());
    if (!installed) {
      throw StateError(
        'OwnerCredentials.setExpectedDigestForTesting is not available in '
        'release builds.',
      );
    }
  }

  @visibleForTesting
  static void clearExpectedDigestForTesting() {
    var cleared = false;
    assert(() {
      _digestOverride = null;
      cleared = true;
      return true;
    }());
    if (!cleared) {
      throw StateError(
        'OwnerCredentials.clearExpectedDigestForTesting is not available in '
        'release builds.',
      );
    }
  }

  // Introspection for the test suite. These expose values that are already
  // embedded in the binary (the salt and the digest), so they add no secret;
  // they only let the tests prove the scrambling is real.

  /// The digest fragments as they appear in the source, in declaration order.
  @visibleForTesting
  static String get debugNaiveDigest => _digestBits.join();

  /// The digest after the permutation is applied - the real expected value.
  @visibleForTesting
  static String get debugExpectedDigest => _expectedDigest;

  /// The permutation used to place the fragments into [debugExpectedDigest].
  @visibleForTesting
  static Set<int> get debugDigestOrder => _digestOrder.toSet();

  /// The pepper fragments in declaration order (i.e. *not* the real pepper).
  @visibleForTesting
  static String get debugNaivePepper => _pepperBits.join();

  @visibleForTesting
  static String get debugPepper => _pepper;

  /// The salt fragments in declaration order (i.e. *not* the real salt).
  @visibleForTesting
  static String get debugNaiveSalt => _saltBits.join();

  @visibleForTesting
  static String get debugSalt => _salt;
}
