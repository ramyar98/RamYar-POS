import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/owner/ip_settings_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Server IP persistence (sync_provider)', () {
    test('returns null before anything is saved', () async {
      expect(await getSavedServerIp(), isNull);
    });

    test('saveServerIp then getSavedServerIp round-trips', () async {
      await saveServerIp('192.168.8.97');
      expect(await getSavedServerIp(), '192.168.8.97');
    });

    test('overwrites the previous saved server IP', () async {
      await saveServerIp('192.168.8.97');
      await saveServerIp('10.0.0.5');
      expect(await getSavedServerIp(), '10.0.0.5');
    });

    test('getServerIpOrDefault falls back to the default server IP', () async {
      expect(await getServerIpOrDefault(), '192.168.8.97');
      await saveServerIp('192.168.1.10');
      expect(await getServerIpOrDefault(), '192.168.1.10');
    });

    test('empty saved value falls back to the default', () async {
      await saveServerIp('   ');
      expect(await getServerIpOrDefault(), '192.168.8.97');
    });
  });

  group('IpSettingsPage widget', () {
    late LocalDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = LocalDatabase();
      await db.resetForTesting();
      await db.init(inMemory: true);
    });

    tearDown(() async {
      await db.resetForTesting();
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDbProvider.overrideWithValue(db),
          ],
          child: AppState(
            currentLanguage: AppLanguage.kurdish,
            onLanguageChanged: (_) {},
            child: const MaterialApp(home: IpSettingsPage()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('shows the IP box with a Save button below it', (tester) async {
      await pumpPage(tester);
      expect(find.text('ڕێخستنی IP'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('پاشەکەوتکردن'), findsOneWidget);
    });

    testWidgets('rejects an invalid IP and shows an error', (tester) async {
      await pumpPage(tester);
      await tester.enterText(find.byType(TextField), '999.1.1.abc');
      await tester.tap(find.text('پاشەکەوتکردن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('هەڵەیە'), findsOneWidget);
      expect(await getSavedServerIp(), isNull);
    });

    testWidgets('saves a valid IP and confirms', (tester) async {
      await pumpPage(tester);
      await tester.enterText(find.byType(TextField), '192.168.1.10');
      await tester.tap(find.text('پاشەکەوتکردن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('پاشەکەوت کرا'), findsOneWidget);
      expect(await getSavedServerIp(), '192.168.1.10');
    });
  });
}