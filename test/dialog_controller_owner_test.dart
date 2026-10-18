import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramyar_pos/widgets/dialog_controller_owner.dart';

/// `addListener` throws a [FlutterError] once a [ChangeNotifier] has been
/// disposed, so it doubles as a cheap "is this controller still alive?" probe.
void _probeListener() {}

void main() {
  testWidgets('disposes its controllers when it leaves the tree', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello');

    await tester.pumpWidget(
      MaterialApp(
        home: DialogControllerOwner(
          controllers: [controller],
          child: const Text('child'),
        ),
      ),
    );
    expect(find.text('child'), findsOneWidget);
    expect(() => controller.addListener(_probeListener), returnsNormally);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(() => controller.addListener(_probeListener), throwsFlutterError);
  });

  testWidgets('keeps controllers alive after showDialog resolves, then '
      'disposes them once the route has gone', (tester) async {
    final controller = TextEditingController();
    bool? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                dialogResult = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => DialogControllerOwner(
                    controllers: [controller],
                    child: AlertDialog(
                      title: const Text('title'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('ok'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('title'), findsOneWidget);

    await tester.tap(find.text('ok'));
    // Flush the pop. `showDialog`'s future resolves now, but the route is still
    // animating out - the window in which disposing the controller crashed the
    // app with `_dependents.isEmpty`.
    await tester.pump();
    expect(dialogResult, isTrue);
    expect(() => controller.addListener(_probeListener), returnsNormally);

    // After the exit animation the route is disposed, and so are the
    // controllers it owned.
    await tester.pumpAndSettle();
    expect(() => controller.addListener(_probeListener), throwsFlutterError);
  });
}
