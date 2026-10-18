import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/core/fmt.dart';
import 'package:ramyar_pos/widgets/amount_input_formatter.dart';
import 'package:ramyar_pos/widgets/cash_calculator_dialog.dart';

/// Money fields accept comma-grouped whole dinars the way the shop writes
/// them ("5,000", "125,000") and the cash calculator's suggestions always
/// lead with the exact bill, so a cashier never has to type it by hand.
void main() {
  group('AmountInputFormatter', () {
    const formatter = AmountInputFormatter();

    TextEditingValue apply(String text, {int? maxValue}) {
      final f = maxValue == null
          ? formatter
          : AmountInputFormatter(maxValue: maxValue);
      return f.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
    }

    test('groups whole dinars with comma thousands separators', () {
      expect(apply('5000').text, '5,000');
      expect(apply('125000').text, '125,000');
      expect(apply('1200000').text, '1,200,000');
      expect(apply('7').text, '7');
    });

    test('a typed comma does not double up', () {
      expect(apply('5,000').text, '5,000');
      expect(apply('125,000').text, '125,000');
    });

    test('drops letters, symbols and localized digits are normalized', () {
      expect(apply('A-1 b2.3').text, '123');
      expect(apply('١٢٣٤٥').text, '12,345');
      expect(apply('۱۲۳').text, '123');
      expect(apply('no money here').text, '');
    });

    test('keeps the caret behind the digit being edited', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '5000',
          selection: TextSelection.collapsed(offset: 1),
        ),
        const TextEditingValue(
          text: '15000',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(result.text, '15,000');
      expect(result.selection.baseOffset, 2);
    });

    test('maxValue clamps to the ceiling (a discount < the bill)', () {
      expect(apply('999999', maxValue: 25000).text, '25,000');
      expect(apply('12000', maxValue: 25000).text, '12,000');
    });
  });

  group('parseAmount', () {
    test('reduces comma-grouped and localized input to a plain int', () {
      expect(parseAmount('5,000'), 5000);
      expect(parseAmount('125,000'), 125000);
      expect(parseAmount('١٢٣٤٥'), 12345);
      expect(parseAmount('۹۹'), 99);
      expect(parseAmount(''), 0);
      expect(parseAmount('abc'), 0);
    });
  });

  group('CashCalculatorDialog suggestions', () {
    Future<void> pumpDialog(
      WidgetTester tester, {
      double totalDue = 30000,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CashCalculatorDialog(
            totalDue: totalDue,
            tableName: 'مێز 1',
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the exact bill amount is the first suggestion', (tester) async {
      await pumpDialog(tester);

      // "30,000 IQD" is the bill readout; the raw "30,000" is its chip.
      expect(find.text('30,000 IQD'), findsOneWidget);
      expect(find.text('30,000'), findsOneWidget);

      final chipLabels = tester
          .widgetList<Text>(
            find.descendant(of: find.byType(Wrap), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(chipLabels.first, '30,000',
          reason: 'the exact bill must lead the quick amounts');
      expect(chipLabels, contains('25,000'));
    });

    testWidgets('a non-round bill also leads the suggestions', (tester) async {
      await pumpDialog(tester, totalDue: 14250);
      expect(find.text('14,250'), findsOneWidget);
      final chipLabels = tester
          .widgetList<Text>(
            find.descendant(of: find.byType(Wrap), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(chipLabels.first, '14,250');
    });

    testWidgets(
        'tapping the exact-bill chip fills the field and enables confirm',
        (tester) async {
      await pumpDialog(tester);

      expect(find.text('بڕی پارە تەواو نیە'), findsOneWidget);

      await tester.tap(find.text('30,000'));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '30,000',
          reason: 'the chip must fill the cash field comma-formatted');
      expect(find.text('واسڵ کردن'), findsOneWidget,
          reason: 'covering the bill exactly must enable settlement');
    });

    testWidgets('the cash field formats typed digits as it goes',
        (tester) async {
      await pumpDialog(tester);
      await tester.enterText(
        find.byType(TextField).last,
        '125000',
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byType(TextField).last,
      );
      expect(field.controller!.text, '125,000');
    });
  });
}