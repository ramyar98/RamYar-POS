import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

class Responsive extends StatelessWidget {
  /// Width at which the app switches to the full laptop layout. Set at iPad
  /// mini width (744pt) so every iPad - portrait or landscape - renders the
  /// same design as the Windows laptop, simply scaled to its smaller screen.
  /// The laptop's absolute sizes (16px fonts, 5-column grids, 24px padding)
  /// fit comfortably in an iPad's 744-1024pt width.
  static const double desktopBreakpoint = 740;

  /// iPad zoom-out: on a real iPad every page renders at this scale so far more
  /// content (tables, lists, buttons) fits on one screen - a browser-style
  /// zoom-out. The Windows laptop, web at laptop sizes and Android tablets are
  /// NEVER zoomed. One constant, so the strength is trivial to tune
  /// (0.85 = more zoomed out, 0.95 = gentler).
  static const double ipadZoomOut = 0.9;

  /// Phone zoom-out: an Android/iOS phone locked to landscape shows the very
  /// same laptop layout the iPad shows, just on a far shorter screen, so it
  /// gets the same whole-app zoom-out - the identical design rendered smaller.
  /// Slightly stronger than the iPad's 0.9 because the phone screen is smaller
  /// still. One constant, so the strength is trivial to tune (0.8 = more zoomed
  /// out, 0.9 = gentler).
  static const double phoneZoomOut = 0.85;

  /// True only on wide iOS tablets - a native iPad app or iPad Safari (Flutter
  /// reports iOS for both). An iPhone in landscape (shortest side ~430 below
  /// the 600 tablet floor), an Android tablet and every laptop/window report
  /// false, so the iPad zoom-out never touches them.
  static bool isIpadWide(MediaQueryData media) =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      media.size.width >= desktopBreakpoint &&
      media.size.shortestSide >= 600;

  /// True on a phone - never a tablet, never a laptop - that is wide enough to
  /// be showing the full desktop layout: an Android/iOS handset locked to
  /// landscape, whose shortest side (~360-430) sits well below the 600 tablet
  /// floor. That phone renders the laptop design and should render it smaller,
  /// exactly as the iPad does. Laptops, web and every tablet report false.
  static bool isPhoneWide(MediaQueryData media) =>
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      media.size.width >= desktopBreakpoint &&
      media.size.shortestSide < 600;

  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const Responsive({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  static bool isSmallPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 380;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 600 && w < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static double valueForDevice({
    required BuildContext context,
    required double mobileVal,
    double? tabletVal,
    required double desktopVal,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktopBreakpoint) return desktopVal;
    if (width >= 600) return tabletVal ?? desktopVal;
    return mobileVal;
  }

  /// قەبارەی دروست بۆ دوگمەکان بەپێی شاشەکە (موبایل بچووکتر، دێسکتۆپ گەورەتر)
  static double buttonHeight(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return 48;
    if (w >= 600) return 44;
    return 40;
  }

  static double iconSize(BuildContext context, {double phone = 20, double tablet = 22, double desktop = 24}) {
    return valueForDevice(context: context, mobileVal: phone, tabletVal: tablet, desktopVal: desktop);
  }

  static int gridColumns(BuildContext context, {int? desktop, int? tablet, int? mobile}) {
    final w = MediaQuery.sizeOf(context).width;
    // One extra column on very wide screens: the same five columns that fill
    // a 1440 monitor leave noticeably sparse, oversized cells at 1900+.
    // cardWidth() shares this count, so tiles grow with it consistently.
    final bump = w >= 1500 ? 1 : 0;
    if (w >= desktopBreakpoint) return (desktop ?? 5) + bump;
    if (w >= 600) return tablet ?? 4;
    return mobile ?? 2;
  }

  /// Column count for dense tool grids (table pickers / transfer) whose tiles
  /// carry fixed-size content and would be squeezed by the desktop count on an
  /// iPad. Laptop and up keep the full desktop count; iPads (740-1099) keep
  /// the roomier tablet count so the fixed tiles never clip - the page still
  /// uses the shared desktop sizes and layout.
  static int safeGridColumns(BuildContext context,
      {required int desktop, required int tablet, required int mobile}) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return desktop;
    if (w >= 600) return tablet;
    return mobile;
  }

  static double fontSize(BuildContext context,
      {double? desktop, double? tablet, double? mobile}) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return desktop ?? 16;
    if (w >= 600) return tablet ?? 14;
    return mobile ?? 12;
  }

  static double cardWidth(BuildContext context,
      {double min = 60, double max = 120}) {
    final w = MediaQuery.sizeOf(context).width;
    final columns = gridColumns(context) * 1.0;
    final available = (w - 32 - (columns - 1) * 8) / columns;
    return available.clamp(min, max);
  }

  static EdgeInsets screenPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return const EdgeInsets.all(24);
    if (w >= 600) return const EdgeInsets.all(16);
    if (w < 360) return const EdgeInsets.all(6);
    return const EdgeInsets.all(8);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= desktopBreakpoint) {
          return desktop;
        } else if (constraints.maxWidth >= 600) {
          return tablet ?? desktop;
        } else {
          return mobile;
        }
      },
    );
  }
}

class ScrollableAppBarActions extends StatelessWidget {
  final List<Widget> children;
  const ScrollableAppBarActions({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    // The strip is horizontally scrollable, so nothing is ever lost - but a
    // cut button only hints at the rest if enough of the strip is on screen.
    // The old 45% on a phone (~256px) hid most of the cashier's actions
    // behind an invisible scroll; half the width makes the cut obvious.
    final maxActions = screenWidth >= Responsive.desktopBreakpoint
        ? screenWidth - 260
        : (screenWidth >= 600 ? screenWidth * 0.60 : screenWidth * 0.50);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxActions),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final double spacing;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class SafeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const SafeText(this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

class ResponsiveGridView extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final double? childAspectRatio;
  final double spacing;
  final double runSpacing;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final int? desktopColumns;
  final int? tabletColumns;
  final int? mobileColumns;

  const ResponsiveGridView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.childAspectRatio = 1.0,
    this.spacing = 12,
    this.runSpacing = 12,
    this.physics,
    this.shrinkWrap = false,
    this.desktopColumns,
    this.tabletColumns,
    this.mobileColumns,
  });

  @override
  Widget build(BuildContext context) {
    // The column count comes from MediaQuery, NOT from a LayoutBuilder: an
    // AlertDialog (and anything else that sizes itself with IntrinsicWidth /
    // intrinsic heights) asks its content for intrinsic dimensions, and
    // LayoutBuilder cannot answer that - it throws
    // "LayoutBuilder does not support returning intrinsic dimensions", the
    // dialog's layout collapses and the grid never appears (the tap that opened
    // it then looks like it did nothing). MediaQuery is available everywhere
    // and every call site of this widget is full-width anyway.
    final crossAxisCount = Responsive.gridColumns(
      context,
      desktop: desktopColumns,
      tablet: tabletColumns,
      mobile: mobileColumns,
    );
    return GridView.builder(
      itemCount: itemCount,
      shrinkWrap: shrinkWrap,
      physics: physics ?? (shrinkWrap ? const NeverScrollableScrollPhysics() : null),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: runSpacing,
        childAspectRatio: childAspectRatio ?? (crossAxisCount >= 4 ? 0.85 : 1.0),
      ),
      itemBuilder: (context, index) => RepaintBoundary(
        // One boundary per tile: when one card repaints - a status change, an
        // entrance animation, a scroll pass - the grid composites that card in
        // isolation instead of re-rasterising every card behind it. Deliberately
        // no key: the tile slots themselves are the cache keys, so adding or
        // deleting one table moves the boundaries by a slot rather than
        // remounting the whole floor.
        child: itemBuilder(context, index),
      ),
    );
  }
}
