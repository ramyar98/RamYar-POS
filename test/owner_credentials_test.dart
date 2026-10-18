import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/services/owner_credentials.dart';

import 'owner_test_login.dart';

/// Guards the owner PIN's secrecy.
///
/// The PIN is not in this repository in any form, so none of these tests know
/// it. What they verify instead is everything that *keeps* it hidden:
///
///  * the key-derivation is a real PBKDF2-HMAC-SHA256 (checked against values
///    produced by .NET's `Rfc2898DeriveBytes`, an independent implementation);
///  * the salt and the digest are stored scrambled, so reading the source top
///    to bottom does not reconstruct either one;
///  * no 5-digit literal anywhere in `lib/` is the owner PIN - this is the test
///    that would fail if someone ever hardcoded it.
void main() {
  tearDownAll(uninstallTestOwnerPin);

  group('PBKDF2-HMAC-SHA256', () {
    // Expected values cross-checked against
    // System.Security.Cryptography.Rfc2898DeriveBytes(..., SHA256).
    test('matches known answers at 1, 7 and 4096 rounds', () {
      expect(
        OwnerCredentials.deriveDigest('passwd0', salt: 'saltsalt', rounds: 1),
        'bec0ead4c81b174e9ff0eab66f7842e21f4044344313b3b402d830b4d1cda074',
      );
      expect(
        OwnerCredentials.deriveDigest('passwd0', salt: 'saltsalt', rounds: 7),
        '165b0330133e81acb1719843681c8dd995ec1a1c017a72afc0d15dd028fa5ac3',
      );
      expect(
        OwnerCredentials.deriveDigest(
          'passwd0',
          salt: 'saltsaltsaltsalt',
          rounds: 4096,
        ),
        '02ba109ad0b313b8b234359754a90e55270cf52ebf8bf6fc58621a9e096d8ebf',
      );
    });

    test('a different salt or round count gives a different digest', () {
      final base =
          OwnerCredentials.deriveDigest('passwd0', salt: 'saltsalt', rounds: 50);
      expect(
        OwnerCredentials.deriveDigest('passwd0', salt: 'saltsalt', rounds: 51),
        isNot(base),
      );
      expect(
        OwnerCredentials.deriveDigest('passwd1', salt: 'saltsalt', rounds: 50),
        isNot(base),
      );
    });

    test('the shipped round count is high enough to slow a sweep down', () {
      // Guards against someone "simplifying" the KDF back to a single hash,
      // which would make an offline sweep of the 100 000 possible PINs trivial.
      final sw = Stopwatch()..start();
      OwnerCredentials.deriveDigest('passwd0', salt: 'saltsalt', rounds: 10000);
      sw.stop();
      // 10k rounds must cost real time; a single sha256 is ~microseconds. The
      // bound is deliberately loose (Dart JIT on a slow CI box) - it only needs
      // to be far above "one hash per guess".
      expect(sw.elapsedMilliseconds, greaterThan(20),
          reason: '10k PBKDF2 rounds finished implausibly fast - is the KDF '
              'still being applied?');
    });
  });

  group('matches()', () {
    test('accepts exactly the PIN whose digest was installed', () {
      installTestOwnerPin();
      expect(OwnerCredentials.matches(testOwnerPin), isTrue);
    });

    test('rejects anything else of the right length', () {
      installTestOwnerPin();
      for (final wrong in <String>[
        '00000', '11111', '12345', '54321', '99999', '90806', '90808',
      ]) {
        expect(OwnerCredentials.matches(wrong), isFalse, reason: wrong);
      }
    });

    test('rejects wrong-length input', () {
      installTestOwnerPin();
      expect(OwnerCredentials.matches(''), isFalse);
      expect(OwnerCredentials.matches('9080'), isFalse);
      expect(OwnerCredentials.matches('908077'), isFalse);
    });

    test('the shipped digest is not the test digest once uninstalled', () {
      // Proves the override is what made the test PIN work, i.e. `matches` is
      // really reading the embedded PBKDF2 output in normal operation.
      uninstallTestOwnerPin();
      expect(OwnerCredentials.matches(testOwnerPin), isFalse);
      installTestOwnerPin();
    });
  });

  group('the PIN cannot be read out of the source', () {
    test('the digest fragments are stored out of order', () {
      // Reassembling by the documented permutation must be needed; the naive
      // top-to-bottom concatenation is a different string.
      expect(OwnerCredentials.debugNaiveDigest,
          isNot(OwnerCredentials.debugExpectedDigest));
      expect(OwnerCredentials.debugExpectedDigest, hasLength(64));
      expect(OwnerCredentials.debugExpectedDigest,
          matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(OwnerCredentials.debugDigestOrder, {0, 1, 2, 3, 4, 5, 6, 7});
    });

    test('the salt is not any single constant in the file', () {
      expect(OwnerCredentials.debugSalt, hasLength(greaterThan(16)));
      expect(OwnerCredentials.debugNaivePepper,
          isNot(OwnerCredentials.debugPepper));
      expect(OwnerCredentials.debugNaiveSalt, isNot(OwnerCredentials.debugSalt));
    });

    test('no 5-digit literal in lib/ is the owner PIN', () {
      // The real guarantee: whatever the PIN is, it is not written anywhere in
      // the shipped source. Every 5-digit run found inside a string literal in
      // lib/ is fed to the real `matches`, which is the only way to be sure.
      final candidates = <String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match in RegExp(r"'[^'\n]*\b\d{5}\b[^'\n]*'").allMatches(source)) {
          for (final run in RegExp(r'\d{5}').allMatches(match.group(0)!)) {
            candidates.add(run.group(0)!);
          }
        }
      }
      // sanity: the scan really did look at something
      expect(candidates, isNotEmpty,
          reason: 'no 5-digit string literals found in lib/ - the scan is '
              'probably broken, not the code');
      for (final candidate in candidates) {
        expect(OwnerCredentials.matches(candidate), isFalse,
            reason: 'lib/ contains a hardcoded owner PIN ($candidate)');
      }
    });

    test('no 5-digit literal in test/ is the owner PIN either', () {
      // owner_test_login.dart is skipped on purpose: its literal is the
      // throwaway PIN the suite installs, never the real one.
      final candidates = <String>{};
      for (final entity in Directory('test').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('owner_credentials_test.dart')) continue;
        if (entity.path.endsWith('owner_test_login.dart')) continue;
        final source = entity.readAsStringSync();
        for (final match in RegExp(r"'[^'\n]*\b\d{5}\b[^'\n]*'").allMatches(source)) {
          for (final run in RegExp(r'\d{5}').allMatches(match.group(0)!)) {
            candidates.add(run.group(0)!);
          }
        }
      }
      for (final candidate in candidates) {
        expect(OwnerCredentials.matches(candidate), isFalse,
            reason: 'test/ contains a hardcoded owner PIN ($candidate)');
      }
    });
  });

  test('owner is the virtual master account', () {
    final user = OwnerCredentials.masterUser;
    expect(user.id, OwnerCredentials.userId);
    expect(user.id, 0);
    expect(user.role.name, 'owner');
    expect(user.pin, isEmpty);
    expect(user.name, isNotEmpty);
  });
}
