import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ramyar_pos/core/single_instance.dart';

/// The single-instance lock must stop a second copy of the *same install* while
/// letting *different installs* run side by side. That second half is what the
/// `tools/instances` three-shop harness depends on: before this the lock was one
/// machine-wide port, so `start_all.bat` could only ever keep instance 1 alive
/// and the documented multi-shop setup silently collapsed to a single shop.
void main() {
  test('the same install always derives the same lock port', () {
    final a = instanceLockPortFor(r'C:\Shop\ramyar_pos.exe');
    final b = instanceLockPortFor(r'C:\Shop\ramyar_pos.exe');
    expect(a, b);
  });

  test('Windows path case does not change the lock port', () {
    expect(
      instanceLockPortFor(r'C:\Shop\ramyar_pos.exe'),
      instanceLockPortFor(r'c:\shop\RAMYAR_POS.EXE'),
    );
  });

  test('different install folders derive different lock ports', () {
    // Synthetic install folders mirroring the tools/instances layout. Only
    // "three different paths" matters to the lock, so no absolute
    // machine-specific path is used - the suite stays portable and CI-runnable.
    final ports = {
      for (final n in [1, 2, 3])
        instanceLockPortFor('C:\\Shops\\inst$n\\ramyar_pos.exe'),
    };
    expect(
      ports,
      hasLength(3),
      reason: 'the three test instances must not collide on the lock',
    );
  });

  test('the lock port stays clear of the real service ports', () {
    final ports = [
      for (var i = 0; i < 500; i++)
        instanceLockPortFor('C:\\shop$i\\ramyar_pos.exe'),
    ];
    for (final p in ports) {
      expect(p, inInclusiveRange(49152, 49152 + 4096 - 1));
      expect(p, isNot(9876)); // sync server
      expect(p, isNot(9877)); // UDP discovery
      expect(p, isNot(0));
    }
  });

  test('the real executable path yields a usable port', () {
    final p = instanceLockPortFor(Platform.resolvedExecutable);
    expect(p, inInclusiveRange(49152, 49152 + 4096 - 1));
  });

  test('duplicate-instance launch stays non-fatal for the active app', () {
    expect(shouldExitDuplicateInstance(), isFalse);
  });
}
