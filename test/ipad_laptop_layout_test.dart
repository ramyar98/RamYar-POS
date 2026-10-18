import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/core/responsive.dart';

/// Every iPad (portrait or landscape, mini through Pro) must render the same
/// layout as the Windows laptop - the same 5-column floors, 16px fonts, 48px
/// buttons and 24px padding - simply scaled to its smaller screen. These tests
/// pin that behaviour so a future breakpoint edit cannot quietly send iPads
/// back to the smaller "tablet" design.
///
/// The end-to-end overflow guard lives in responsive_test.dart, which visits
/// every admin/cashier/waiter page at 768x1024 and 1024x768 and fails on any
/// RenderFlex overflow.
void main() {
  Future<BuildContext> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  const iPadSizes = <String, Size>{
    'ipad-mini-744x1133': Size(744, 1133),
    'ipad-9.7-portrait-768x1024': Size(768, 1024),
    'ipad-air-portrait-820x1180': Size(820, 1180),
    'ipad-landscape-1024x768': Size(1024, 768),
    'ipad-pro-portrait-1024x1366': Size(1024, 1366),
  };

  for (final entry in iPadSizes.entries) {
    testWidgets('${entry.key} uses the laptop layout', (tester) async {
      final context = await pumpAt(tester, entry.value);
      expect(Responsive.isDesktop(context), isTrue,
          reason: '${entry.key} should use the desktop tier');
      expect(Responsive.isPhone(context), isFalse);
      expect(Responsive.gridColumns(context), 5,
          reason: '${entry.key} should get the laptop 5-column floors');
      expect(Responsive.fontSize(context), 16,
          reason: '${entry.key} should get the laptop text size');
      expect(Responsive.buttonHeight(context), 48,
          reason: '${entry.key} should get the laptop button height');
      expect(Responsive.screenPadding(context), const EdgeInsets.all(24),
          reason: '${entry.key} should get the laptop padding');
    });
  }

  testWidgets('phones keep the mobile layout', (tester) async {
    final small = await pumpAt(tester, const Size(390, 844));
    expect(Responsive.isPhone(small), isTrue);
    expect(Responsive.isDesktop(small), isFalse);
    expect(Responsive.gridColumns(small), 2);
    expect(Responsive.screenPadding(small), const EdgeInsets.all(8));
  });

  testWidgets('a 667-wide landscape phone stays below the iPad breakpoint',
      (tester) async {
    final context = await pumpAt(tester, const Size(667, 375));
    expect(Responsive.isDesktop(context), isFalse);
    expect(Responsive.isPhone(context), isFalse);
  });

  testWidgets('laptop and 1500+ keep their existing columns', (tester) async {
    final laptop = await pumpAt(tester, const Size(1280, 800));
    expect(Responsive.gridColumns(laptop), 5);
    final wide = await pumpAt(tester, const Size(1600, 900));
    expect(Responsive.gridColumns(wide), 6);
  });

  testWidgets('safeGridColumns keeps fixed tiles roomy on an iPad',
      (tester) async {
    final iPad = await pumpAt(tester, const Size(768, 1024));
    expect(
      Responsive.safeGridColumns(iPad, desktop: 6, tablet: 4, mobile: 3),
      4,
      reason: 'iPad keeps the roomier 4-tile transfer grid',
    );
    final laptop = await pumpAt(tester, const Size(1280, 800));
    expect(
      Responsive.safeGridColumns(laptop, desktop: 6, tablet: 4, mobile: 3),
      6,
      reason: 'a true laptop gets the full 6-tile grid',
    );
    final phone = await pumpAt(tester, const Size(390, 844));
    expect(
      Responsive.safeGridColumns(phone, desktop: 6, tablet: 4, mobile: 3),
      3,
    );
  });
}
