import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/core/app.dart';
import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/services/app_localizations.dart';
import 'package:ramyar_pos/widgets/table_note_dialog.dart';

/// The table-note editor is reached from the captain's table page and the
/// cashier's unified table page. It used to build two TextEditingControllers in
/// the caller and dispose them once `showDialog` returned, which crashed
/// ("A TextEditingController was used after being disposed") because the route
/// is still animating out while the keyboard closes. These tests pin the fixed
/// behaviour.
void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    required ValueChanged<TableNoteResult?> onResult,
    String captain = '',
    String admin = '',
    bool showAdminField = true,
  }) async {
    await tester.pumpWidget(
      AppState(
        currentLanguage: AppLanguage.kurdish,
        onLanguageChanged: (_) {},
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showDialog<TableNoteResult>(
                      context: context,
                      builder: (ctx) => TableNoteDialog(
                        title: ctx.tr('تێبینی'),
                        captainText: captain,
                        adminText: admin,
                        showAdminField: showAdminField,
                      ),
                    );
                    onResult(result);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('editing both notes returns the trimmed text', (tester) async {
    TableNoteResult? result;
    await openDialog(tester, onResult: (r) => result = r);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '  دوو بەرگر  ');
    await tester.enterText(fields.at(1), ' داشکاندن پێویستە ');

    await tester.tap(find.text('پاشەکەوتکردن'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.captain, 'دوو بەرگر');
    expect(result!.admin, 'داشکاندن پێویستە');
  });

  testWidgets('a captain sees only their own field', (tester) async {
    await openDialog(tester, onResult: (_) {}, showAdminField: false);
    expect(find.text('تێبینیی کاپتن'), findsOneWidget);
    expect(find.text('تێبینی بۆ ئادمێن'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('dismissing reports no result and leaves nothing behind', (
    tester,
  ) async {
    TableNoteResult? result;
    var closed = false;
    await openDialog(
      tester,
      onResult: (r) {
        result = r;
        closed = true;
      },
      captain: 'شاردراو',
    );
    await tester.tap(find.text('ڕەتکردنەوە'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
    expect(find.byType(TableNoteDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved note does not touch a disposed controller', (
    tester,
  ) async {
    TableNoteResult? result;
    await openDialog(
      tester,
      onResult: (r) => result = r,
      captain: 'کۆن',
    );
    await tester.enterText(find.byType(TextField).first, 'نوێ');
    await tester.tap(find.text('پاشەکەوتکردن'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TableNoteDialog), findsNothing);
    expect(result?.captain, 'نوێ');
  });
}
