import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/responsive.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/page/login/login_page.dart';
import 'package:ramyar_pos/services/sync_provider.dart';

/// The owner asked for a zoom-out on the iPad (captain + cashier screens) and
/// now on phones too, so the laptop design renders smaller and the whole floor
/// fits on one screen. The Windows laptop, web at laptop sizes and Android
/// tablets must stay exactly as they are. These tests pin who gets which zoom
/// and who never does.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDatabase();
    await db.resetForTesting();
    await db.init(inMemory: true);
    await db.seedDefaultStaff();
  });

  tearDown(() async {
    await db.resetForTesting();
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDbProvider.overrideWithValue(db),
        ],
        child: const RamyarPosApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    if (find.byType(LoginPage).evaluate().isEmpty) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .toList();
      fail('No LoginPage at $size. Visible texts:\n$texts');
    }
    expect(tester.takeException(), isNull);
  }

  group('Responsive.isIpadWide', () {
    test('tags every real iPad size on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // Landscape-first app: iPad mini through Pro in landscape and portrait.
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(1133, 744))),
          isTrue);
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(1024, 768))),
          isTrue);
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(1180, 820))),
          isTrue);
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(1366, 1024))),
          isTrue);
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(744, 1133))),
          isTrue);
    });

    test('excludes an iPhone in landscape and narrow split-view windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // The widest iPhone in landscape: wide enough for the desktop tier, but
      // its short side (430) is far below the 600 tablet floor.
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(932, 430))),
          isFalse);
      // A split-view iPad window below the desktop breakpoint.
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(700, 900))),
          isFalse);
    });

    test('excludes every non-iOS platform (laptop and Android safe)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(1440, 900))),
          isFalse);
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(1280, 800))),
          isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(Responsive.isIpadWide(const MediaQueryData(size: Size(1024, 768))),
          isFalse);
    });
  });

  group('Responsive.isPhoneWide', () {
    test('tags a landscape Android/iOS phone that shows the desktop layout', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // The real handset: Galaxy A52s locked to landscape - desktop width, but a
      // short side (411) far below the 600 tablet floor.
      expect(Responsive.isPhoneWide(const MediaQueryData(size: Size(833, 411))),
          isTrue);
      // A wider phone in landscape.
      expect(Responsive.isPhoneWide(const MediaQueryData(size: Size(932, 430))),
          isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(Responsive.isPhoneWide(const MediaQueryData(size: Size(932, 430))),
          isTrue);
    });

    test('never tags a tablet or a laptop', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // An Android tablet at iPad size: wide AND tall enough to be a tablet.
      expect(Responsive.isPhoneWide(const MediaQueryData(size: Size(1024, 768))),
          isFalse);
      // A portrait phone stays in the mobile tier and keeps its full-size layout.
      expect(Responsive.isPhoneWide(const MediaQueryData(size: Size(414, 896))),
          isFalse);
      // A small laptop window is a desktop, not a phone.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(Responsive.isPhoneWide(const MediaQueryData(size: Size(800, 500))),
          isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(Responsive.isPhoneWide(const MediaQueryData(size: Size(800, 500))),
          isFalse);
    });
  });

  group('whole-app zoom on device', () {
    testWidgets('an iPad gets the zoomed-out layout (smaller, more content)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpApp(tester, const Size(1024, 768));

      // The layout thinks the screen is 1/zoom bigger...
      final virtual = Size(
          1024 / Responsive.ipadZoomOut, 768 / Responsive.ipadZoomOut);
      final ctx = tester.element(find.byType(LoginPage));
      expect(MediaQuery.sizeOf(ctx).width, closeTo(virtual.width, 0.01),
          reason: 'the app must lay out against the enlarged virtual screen');
      expect(MediaQuery.sizeOf(ctx).height, closeTo(virtual.height, 0.01));
      // ...and the whole tree is scaled back down to fit the physical screen.
      expect(_hasIpadZoom(tester), isTrue,
          reason: 'every page (captain/cashier included) is zoomed on an iPad');
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await _finish(tester);
    });

    testWidgets('a macOS window is never zoomed, even at wide sizes',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpApp(tester, const Size(1280, 800));
      expect(_hasIpadZoom(tester), isFalse);
      final ctx = tester.element(find.byType(LoginPage));
      expect(MediaQuery.sizeOf(ctx).width, 1280,
          reason: 'the laptop render is byte-for-byte what it was before');
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await _finish(tester);
    });

    testWidgets('a Windows laptop keeps the existing full-size layout',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpApp(tester, const Size(1440, 900));
      expect(_hasIpadZoom(tester), isFalse);
      final ctx = tester.element(find.byType(LoginPage));
      expect(MediaQuery.sizeOf(ctx).width, 1440);
      expect(MediaQuery.sizeOf(ctx).height, 900);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await _finish(tester);
    });

    testWidgets('an Android tablet at iPad size is not zoomed', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpApp(tester, const Size(1024, 768));
      expect(_hasIpadZoom(tester), isFalse);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await _finish(tester);
    });

    testWidgets('an Android phone in landscape gets the phone zoom',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // The real handset: 833x411 due to the cutout, the exact device-landscape
      // size the shop runs.
      await pumpApp(tester, const Size(833, 411));

      final virtual = Size(
          833 / Responsive.phoneZoomOut, 411 / Responsive.phoneZoomOut);
      final ctx = tester.element(find.byType(LoginPage));
      expect(MediaQuery.sizeOf(ctx).width, closeTo(virtual.width, 0.01),
          reason: 'the app must lay out against the enlarged virtual screen');
      expect(MediaQuery.sizeOf(ctx).height, closeTo(virtual.height, 0.01));
      expect(_hasPhoneZoom(tester), isTrue,
          reason: 'the laptop design renders smaller on the phone');
      expect(_hasIpadZoom(tester), isFalse);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await _finish(tester);
    });

    testWidgets('an iPhone in landscape gets the phone zoom too',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpApp(tester, const Size(932, 430));
      expect(_hasPhoneZoom(tester), isTrue);
      expect(_hasIpadZoom(tester), isFalse);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await _finish(tester);
    });
  });
}

Future<void> _finish(WidgetTester tester) async {
  final ctx = tester.element(find.byType(Navigator).first);
  Navigator.of(ctx).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (route) => false,
  );
  disconnectSync();
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(LoginPage).evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(seconds: 11));
  expect(tester.takeException(), isNull);
}

/// True when the app tree carries [zoom] as the whole-app transform (the whole
/// app wrapped in Transform.scale(zoom)).
bool _hasZoom(WidgetTester tester, double zoom) {
  for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
    final m = t.transform.storage;
    if ((m[0] - zoom).abs() < 0.001 && (m[5] - zoom).abs() < 0.001) {
      return true;
    }
  }
  return false;
}

/// True when the app tree carries the iPad zoom transform (Transform.scale(0.9)).
bool _hasIpadZoom(WidgetTester tester) =>
    _hasZoom(tester, Responsive.ipadZoomOut);

/// True when the app tree carries the phone zoom transform (Transform.scale(0.85)).
bool _hasPhoneZoom(WidgetTester tester) =>
    _hasZoom(tester, Responsive.phoneZoomOut);