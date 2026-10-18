import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'app_log.dart';

/// On-device QA instrumentation for RAMYAR POS.
///
/// Off unless the app is launched with `--dart-define=RAMYAR_QA=true`, so a
/// normal build carries none of the cost. When it IS on it gives an automated
/// test agent three things it cannot otherwise get from outside the process:
///
///  * **Every framework error, captured.** `FlutterError.onError` and
///    `PlatformDispatcher.onError` are wrapped (the previous handlers are still
///    called, so the usual red error box and console output are unchanged) and
///    every captured error is echoed as one `[QA-ERROR]` line. RenderFlex and
///    RenderBox overflows are reported through exactly this channel, so a
///    striped/yellow-and-black layout bug shows up in a log instead of only as
///    a picture.
///  * **A screen digest on a timer.** The semantics tree is force-enabled and
///    re-dumped every [digestInterval] as one `[QA-SCREEN]` line holding every
///    visible label with its global rect. That is enough to know what is on
///    screen and where to tap, without a human looking at it.
///  * **A running error ledger** retrievable with [takeRecordedErrors], for
///    tests that want to assert on it.
///
/// Everything is printed through [debugPrint] so it lands in `flutter run`
/// output, `adb logcat` and the release log file alike.
class QaHarness {
  QaHarness._();

  static final QaHarness instance = QaHarness._();

  /// Compiled in only for QA launches. `const` so the tree-shaker can drop the
  /// whole file from an ordinary release build.
  static const bool enabled = bool.fromEnvironment('RAMYAR_QA');

  /// How often the screen digest is polled.
  static const Duration digestInterval = Duration(milliseconds: 700);

  /// Idle polls to tolerate before describing an unchanged screen again.
  static const int idleTicksBeforeHeartbeat = 12;

  /// Cap on how many labels one digest carries. Enough to drive a screen, and
  /// bounded so a 400-item menu cannot flood the log.
  static const int maxDigestLabels = 90;

  /// How many errors are kept for [takeRecordedErrors] before the oldest are
  /// dropped. An unbounded ledger is a memory leak in a long shift.
  static const int maxRecordedErrors = 200;

  final Queue<String> _errors = Queue<String>();
  Timer? _digestTimer;
  SemanticsHandle? _semantics;
  bool _installed = false;
  String _screen = '';
  int _digestCount = 0;
  int? _lastSignature;
  int _idleTicks = 0;
  String _lastView = '';

  /// Number of framework errors captured since launch. A test can watch this to
  /// fail a run that rendered something broken without noticing.
  int get errorCount => _errors.length;

  bool get isInstalled => _installed;

  /// Installs the harness. Safe to call more than once; only the first call does
  /// anything.
  void install() {
    if (!enabled || _installed) return;
    _installed = true;

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _record(
        details.exceptionAsString(),
        details.library,
        details.context?.toDescription(),
      );
      // Keep the stock behaviour (console dump + the on-screen error box) so the
      // harness never hides a bug from a human who is also looking.
      previousFlutterHandler?.call(details);
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _record('$error', 'platform', null);
      // `true` means "handled": the message is already in the ledger and in the
      // log, so the engine must not also tear the isolate down for it.
      if (previousPlatformHandler != null) {
        return previousPlatformHandler(error, stack);
      }
      return true;
    };

    // The semantics tree is what makes the screen digest readable. Nothing in
    // the app asks for it on a normal run, so it is off and the digest would be
    // empty without this.
    _semantics = WidgetsBinding.instance.ensureSemantics();

    developer.log('RAMYAR QA harness installed', name: 'qa');

    _digestTimer = Timer.periodic(digestInterval, (_) => _tick());
  }

  /// A one-line description of the window the app is drawing into: logical size,
  /// pixel ratio and pixel size. Everything else in the digest is in logical
  /// pixels of this view, so a driver converting to device coordinates needs
  /// these three numbers and nothing else.
  static String describeView() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 'no-view';
    final view = views.first;
    final size = view.physicalSize;
    final ratio = view.devicePixelRatio;
    return 'logical=${(size.width / ratio).round()}x${(size.height / ratio).round()} '
        'physical=${size.width.round()}x${size.height.round()} ratio=$ratio';
  }

  /// Where the harness writes its findings. `log` keeps them in the standard
  /// stream that `adb logcat` and `flutter run` both show.
  static void _log(String message) {
    appLog(message);
  }

  void _record(String message, String? library, String? context) {
    final text = message.replaceAll('\n', ' \\n ');
    if (text.length > 900) {
      _record(text.substring(0, 900), library, context);
      return;
    }
    _errors.add(text);
    while (_errors.length > maxRecordedErrors) {
      _errors.removeFirst();
    }
    _log('[QA-ERROR] lib=$library ctx=$context :: $text');
  }

  /// Returns the captured errors and clears the ledger.
  List<String> takeRecordedErrors() {
    final copy = _errors.toList(growable: false);
    _errors.clear();
    return copy;
  }

  /// A stable name for whatever route is on top, so a digest line says WHICH
  /// screen it is describing.
  ///
  /// Prefers the name pushed by [QaNavigatorObserver]; falls back to a depth
  /// first walk that finds the last `ModalRoute` in the tree, which is the
  /// topmost one for a normal `Navigator`.
  static String describeRoute(Element? root) {
    final pushed = _pushedRoute;
    if (pushed != null && pushed.isNotEmpty) return pushed;
    var found = 'no-route';
    void visit(Element? element) {
      if (element == null) return;
      final widget = element.widget;
      if (widget is ModalRoute) found = '${widget.runtimeType}';
      element.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  static String? _pushedRoute;

  @visibleForTesting
  static void reportPushedRoute(String? name) => _pushedRoute = name;

  void _emitDigest() {
    _digestCount++;
    _screen = describeRoute(WidgetsBinding.instance.rootElement);
    final labels = collectVisibleLabels();
    final buffer = StringBuffer('[QA-SCREEN] #$_digestCount route=$_screen n=${labels.length}');
    for (final label in labels) {
      buffer.write(' |${_escape(label.text)}@${label.cx},${label.cy}');
    }
    _log(buffer.toString());
  }

  /// Emits a digest only when the screen actually changed, plus a slow heartbeat
  /// so a screen that is still but broken still gets described.
  ///
  /// Polling on a timer alone would either be too slow to be useful or flood the
  /// log with identical lines. Comparing a signature of what is on screen means
  /// the log has one entry per thing the operator actually did, in order.
  void _tick() {
    // The window's size is not known until the first frame, and it changes again
    // on rotation, a resize or a desktop window drag - so it is announced from
    // the same loop as the screens rather than once at startup.
    final view = describeView();
    if (view != _lastView) {
      _lastView = view;
      _log('[QA-VIEW] $view');
    }
    final labels = collectVisibleLabels();
    final signature = Object.hashAll(<Object?>[
      describeRoute(WidgetsBinding.instance.rootElement),
      for (final label in labels) '${label.text}@${label.cx},${label.cy}',
    ]);
    if (signature == _lastSignature) {
      if (++_idleTicks >= idleTicksBeforeHeartbeat) {
        _idleTicks = 0;
        _emitDigest();
      }
      return;
    }
    _idleTicks = 0;
    _lastSignature = signature;
    _emitDigest();
  }

  static String _escape(String value) =>
      value.replaceAll('|', '/').replaceAll('\n', ' ').trim();

  /// Every visible semantics label with the global centre of its box, in LOGICAL
  /// pixels - the same coordinate space widget tests use, so a number read out
  /// of a digest line can be compared against a `getCenter` without rescaling.
  ///
  /// Walks the compiled semantics tree - the same tree a screen reader sees -
  /// rather than the render tree: a plain `Text` carries its label in the
  /// semantics tree, not on the render object, so a render-tree walk finds
  /// nothing on an ordinary screen. Node rects are lifted into view
  /// coordinates by accumulating each node's parent-relative transform.
  static List<QaLabel> collectVisibleLabels({int limit = maxDigestLabels}) {
    final out = <QaLabel>[];
    // The semantics tree of the render view we are actually drawing into. Not
    // `RendererBinding.instance.pipelineOwner`: that is the deprecated primary
    // owner and a secondary view would be missed.
    SemanticsNode? root;
    for (final view in RendererBinding.instance.renderViews) {
      root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) break;
    }
    if (root == null) return out;
    // The semantics tree is in physical pixels of the view; the digest speaks
    // logical pixels.
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return out;
    final view = views.first;
    final ratio = view.devicePixelRatio.toDouble().clamp(0.01, 8.0);
    try {
      _walkSemantics(root, Matrix4.identity(), view, ratio, out, limit);
    } catch (_) {
      // A tree being rebuilt mid-frame is not a finding.
    }
    return out;
  }

  static void _walkSemantics(
    SemanticsNode node,
    Matrix4 parentTransform,
    FlutterView view,
    double ratio,
    List<QaLabel> out,
    int limit,
  ) {
    if (out.length >= limit) return;
    final own = node.transform;
    final transform =
        own == null ? parentTransform : parentTransform.multiplied(own);
    final label = node.getSemanticsData().label.trim();
    if (label.isNotEmpty && !node.isInvisible) {
      try {
        final raw = MatrixUtils.transformRect(transform, node.rect);
        // The semantics tree is in physical pixels; compare in the same units it
        // was built in, then report logical. Mixing the two silently drops
        // everything below the fold (or keeps the whole page).
        if (raw.width > 0 && raw.height > 0 && !_isOffScreen(raw, view)) {
          out.add(QaLabel(
            text: label,
            cx: ((raw.left + raw.width / 2) / ratio).round(),
            cy: ((raw.top + raw.height / 2) / ratio).round(),
            w: (raw.width / ratio).round(),
            h: (raw.height / ratio).round(),
          ));
        }
      } catch (_) {
        // A node detaching during the walk cannot produce a rect.
      }
    }
    node.visitChildren((child) {
      _walkSemantics(child, transform, view, ratio, out, limit);
      return out.length < limit;
    });
  }

  /// Drops anything scrolled fully out of the viewport, keeping the digest about
  /// what the operator can actually see. [physical] must be in the same units as
  /// [view] (physical pixels of that view).
  static bool _isOffScreen(Rect physical, FlutterView view) {
    return physical.bottom <= 0 ||
        physical.right <= 0 ||
        physical.top >= view.physicalSize.height ||
        physical.left >= view.physicalSize.width;
  }

  /// The screen name captured at the last digest.
  String get currentScreen => _screen;

  @visibleForTesting
  void dispose() {
    _digestTimer?.cancel();
    _digestTimer = null;
    _semantics?.dispose();
    _semantics = null;
    _installed = false;
  }
}

/// One readable thing on screen plus where it is.
class QaLabel {
  final String text;
  final int cx;
  final int cy;
  final int w;
  final int h;

  const QaLabel({
    required this.text,
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
  });

  @override
  String toString() => '$text@$cx,$cy';
}

/// True when the framework error [message] describes a layout overflow.
///
/// Overflow is the one failure mode that is silent in a release build - the
/// stripes and the clipped text are drawn, nothing throws - so a QA sweep has to
/// recognise the word for it explicitly.
bool isLayoutOverflowMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('overflowed by') ||
      (lower.contains('overflow') &&
          (lower.contains('renderflex') || lower.contains('renderbox')));
}

/// The single instance to hand to `MaterialApp.navigatorObservers`. One object,
/// because a `Navigator` keeps the list identity and an observer built fresh on
/// every rebuild would churn.
final QaNavigatorObserver qaNavigatorObserver = QaNavigatorObserver();

/// Installs [QaHarness] when the build was launched for QA. One call from
/// `main()`; returns immediately in a normal build.
void installQaHarnessIfEnabled() {
  if (!QaHarness.enabled) return;
  QaHarness.instance.install();
}

/// Reports the top route name to [QaHarness].
///
/// Give this to the app's `MaterialApp.navigatorObservers`. It does nothing at
/// all when QA is off, so it is safe to leave in the shipping app.
class QaNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    QaHarness.reportPushedRoute(_name(route));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    QaHarness.reportPushedRoute(
        previousRoute == null ? null : _name(previousRoute));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    QaHarness.reportPushedRoute(
        previousRoute == null ? null : _name(previousRoute));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    QaHarness.reportPushedRoute(newRoute == null ? null : _name(newRoute));
  }

  static String _name(Route<dynamic> route) {
    final named = route.settings.name ?? '';
    if (named.isNotEmpty) return named;
    return route.runtimeType.toString();
  }
}

/// Forces a scheduler frame so pending error reports are flushed right now
/// rather than at the next tick. Used by tests that check [QaHarness] output.
void qaFlushFrame() {
  SchedulerBinding.instance.scheduleFrame();
  SchedulerBinding.instance.handleBeginFrame(null);
  SchedulerBinding.instance.handleDrawFrame();
}
