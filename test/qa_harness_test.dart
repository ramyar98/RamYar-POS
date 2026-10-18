import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/core/qa_harness.dart';

void main() {
  testWidgets('screen digest finds labels and places them correctly',
      (tester) async {
    final handle = WidgetsBinding.instance.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('سەرەتا'),
              ElevatedButton(
                  onPressed: () {}, child: const Text('دوگمە')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final labels = QaHarness.collectVisibleLabels();
    // ignore: avoid_print
    print('FOUND ${labels.length}: $labels');

    final button = find.text('دوگمە');
    final buttonCentre = tester.getCenter(button);
    final digestEntry = labels.firstWhere((l) => l.text == 'دوگمە');
    expect(
      (digestEntry.cx - buttonCentre.dx).abs(),
      lessThan(2),
      reason: 'digest x for دوگمە should match the real button centre',
    );
    expect(
      (digestEntry.cy - buttonCentre.dy).abs(),
      lessThan(2),
      reason: 'digest y for دوگمە should match the real button centre',
    );

    final header = labels.firstWhere((l) => l.text == 'سەرەتا');
    final headerCentre = tester.getCenter(find.text('سەرەتا'));
    expect((header.cx - headerCentre.dx).abs(), lessThan(2));
    expect((header.cy - headerCentre.dy).abs(), lessThan(2));

    handle.dispose();
  });
}
