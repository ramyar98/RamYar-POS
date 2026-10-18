import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/providers/auth_provider.dart';
import 'package:ramyar_pos/services/owner_access.dart';
import 'package:ramyar_pos/services/owner_credentials.dart';

import 'owner_test_login.dart';

/// The owner PIN is hidden behind the "hama" route: it must be refused until
/// that route is completed on this launch, accepted afterwards, and locked
/// again by a logout.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() {
    OwnerCredentials.clearExpectedDigestForTesting();
    OwnerAccess.setTestBypass(false);
    OwnerAccess.lock();
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Install the test digest directly (NOT through installTestOwnerPin, which
    // also enables the test bypass) so we can assert the locked behaviour.
    OwnerCredentials.setExpectedDigestForTesting(
      OwnerCredentials.deriveDigest(testOwnerPin),
    );
    OwnerAccess.setTestBypass(false);
    OwnerAccess.lock();
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    await db.resetForTesting();
    OwnerAccess.lock();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [localDbProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the owner PIN is refused until the hidden route is completed',
      () async {
    final container = makeContainer();
    final auth = container.read(authProvider.notifier);

    expect(OwnerAccess.isUnlocked, isFalse);
    final blocked = await auth.loginWithPin(testOwnerPin);
    expect(blocked, isNull);
    expect(container.read(loginNoticeProvider).state, isNotNull);
  });

  test('the owner PIN works once the hidden route unlocked the session',
      () async {
    final container = makeContainer();
    final auth = container.read(authProvider.notifier);

    OwnerAccess.unlock();
    final user = await auth.loginWithPin(testOwnerPin);
    expect(user, isNotNull);
    expect(user!.role, UserRole.owner);
    expect(container.read(loginNoticeProvider).state, isNull);
  });

  test('a logout locks the owner PIN behind the hidden route again', () async {
    final container = makeContainer();
    final auth = container.read(authProvider.notifier);

    OwnerAccess.unlock();
    expect(await auth.loginWithPin(testOwnerPin), isNotNull);

    await auth.logout();
    expect(OwnerAccess.isUnlocked, isFalse);
    expect(await auth.loginWithPin(testOwnerPin), isNull);
  });
}
