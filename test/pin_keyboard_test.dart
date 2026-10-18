import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/page/login/pin_login_page.dart';

/// The login PIN must be typable from a REAL keyboard everywhere:
///   * the physical keyboard on the Windows/laptop cashier, and
///   * the phone's own soft keyboard on Android (in ANY layout).
/// The on-screen dialer stays as a second way to enter the same PIN.
void main() {
  const fieldKey = ValueKey('pin_keyboard_input');
  const keypadKey = ValueKey('keypad');
  const dotsKey = ValueKey('pin_dots_tap_target');

  Future<PinKeypadState> pumpKeypad(
    WidgetTester tester, {
    ValueChanged<String>? onComplete,
    int pinLength = 5,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Constrain the keypad to a phone-like width and scroll so the grid
          // never overflows the default 800x600 test surface.
          body: Center(
            child: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: PinKeypad(
                  key: keypadKey,
                  pinLength: pinLength,
                  onChanged: (_) {},
                  onComplete: onComplete ?? (_) {},
                  onBackspace: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<PinKeypadState>(find.byKey(keypadKey));
  }

  group('PinKeypad device keyboard', () {
    testWidgets('exposes a real (hidden) input and opens it from the dots',
        (tester) async {
      final state = await pumpKeypad(tester);
      expect(find.byKey(fieldKey, skipOffstage: false), findsOneWidget,
          reason: 'device-keyboard input missing');
      expect(state.keyboardFocusNode.hasFocus, isFalse);

      await tester.tap(find.byKey(dotsKey));
      await tester.pump();
      expect(state.keyboardFocusNode.hasFocus, isTrue,
          reason: 'tapping the dots must arm the device keyboard');
    });

    testWidgets('accepts Latin digits typed on the keyboard', (tester) async {
      final state = await pumpKeypad(tester);
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '123');
      await tester.pump();
      expect(state.pin, '123');
    });

    testWidgets('normalizes Arabic-Indic digits to Latin', (tester) async {
      final state = await pumpKeypad(tester);
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '١٢٣٤٥');
      await tester.pump();
      expect(state.pin, '12345');
      for (final unit in state.pin.codeUnits) {
        expect(unit >= 0x30 && unit <= 0x39, isTrue,
            reason: 'a non-Latin digit leaked into the PIN');
      }
    });

    testWidgets('normalizes Persian digits to Latin', (tester) async {
      final state = await pumpKeypad(tester);
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '۱۲۳');
      await tester.pump();
      expect(state.pin, '123');
    });

    testWidgets('ignores letters and symbols from any keyboard style',
        (tester) async {
      final state = await pumpKeypad(tester);
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), 'A-1 b2.3');
      await tester.pump();
      expect(state.pin, '123');
    });

    testWidgets('backspace deletes the last digit', (tester) async {
      final state = await pumpKeypad(tester);
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '123');
      await tester.pump();
      expect(state.pin, '123');

      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '12');
      await tester.pump();
      expect(state.pin, '12');

      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '');
      await tester.pump();
      expect(state.pin, '');
    });

    testWidgets('auto-submits once the full PIN is typed', (tester) async {
      String? submitted;
      await pumpKeypad(tester, onComplete: (pin) => submitted = pin);
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '54321');
      await tester.pump();
      expect(submitted, '54321');
    });

    testWidgets('never exceeds the PIN length', (tester) async {
      final state = await pumpKeypad(tester, pinLength: 5);
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '123456789');
      await tester.pump();
      expect(state.pin, '12345');
    });

    testWidgets('the on-screen dialer still works and shares the same PIN',
        (tester) async {
      final state = await pumpKeypad(tester);
      await tester.tap(find.text('7'));
      await tester.pump();
      await tester.tap(find.text('8'));
      await tester.pump();
      expect(state.pin, '78');

      // A value typed on the device keyboard lands in the same controller.
      await tester.enterText(find.byKey(fieldKey, skipOffstage: false), '789');
      await tester.pump();
      expect(state.pin, '789');
    });
  });
}
