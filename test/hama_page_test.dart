import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/page/login/hama_page.dart';
import 'package:ramyar_pos/page/login/pin_login_page.dart';
import 'package:ramyar_pos/services/owner_access.dart';

/// Wraps a page the way the app builds it: RTL and [AppState] so every visible
/// string goes through `context.tr`.
Widget _wrap(Widget child) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: AppState(
      currentLanguage: AppLanguage.kurdish,
      onLanguageChanged: (_) {},
      child: MaterialApp(home: child),
    ),
  );
}

void main() {
  // The gate lives in a static, so reset it before every test.
  setUp(OwnerAccess.lock);

  testWidgets('hama shows the meaningless hint in the box', (tester) async {
    await tester.pumpWidget(_wrap(const HamaPage()));
    // The decoy prompt: a harmless-looking company-name hint, so nobody
    // browsing the screen learns that there is anything to connect to. The
    // secret itself stays in _code and is never shown.
    expect(find.text('ناوی کۆمپانیاکەت بنووسە ڕامیار'), findsOneWidget);
    expect(find.text('کۆنێکت'), findsOneWidget);
  });

  testWidgets('hama accepts ++ and reports connected', (tester) async {
    await tester.pumpWidget(_wrap(const HamaPage()));
    await tester.enterText(find.byType(TextField), '++');
    await tester.tap(find.text('کۆنێکت'));
    await tester.pump();
    expect(find.text('کۆنێکت کرا'), findsOneWidget);
    expect(OwnerAccess.isUnlocked, isTrue);
    // Let the "connected" delay fire and the snack bar dismiss. An explicit
    // pump is used instead of pumpAndSettle because the busy spinner is an
    // indeterminate animation that never settles on its own.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('hama rejects a wrong code', (tester) async {
    await tester.pumpWidget(_wrap(const HamaPage()));
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('کۆنێکت'));
    await tester.pump();
    expect(find.text('هەڵەیە'), findsOneWidget);
    expect(find.text('کۆنێکت کرا'), findsNothing);
    expect(OwnerAccess.isUnlocked, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('the login page hides an invisible hama target that opens it',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const ProviderScope(child: PinLoginPage())),
    );
    final target = find.byKey(const ValueKey('hama_hidden_button'));
    expect(target, findsOneWidget);
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(HamaPage), findsOneWidget);
  });
}
