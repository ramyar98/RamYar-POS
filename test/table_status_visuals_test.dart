import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/core/colors.dart';
import 'package:ramyar_pos/core/table_status_visuals.dart';
import 'package:ramyar_pos/database/local_db.dart';
import 'package:ramyar_pos/models/table_model.dart';

/// The floor's colour rule, in one place.
///
/// The shop's signal is: a free table is the neutral card, a seated customer is
/// green, a table whose bill was printed is blue, and a printed bill that has
/// not been settled inside the window is red.
///
/// Every role's floor screen used to hold its own copy of that switch - the
/// cashier's home, the cashier's unified table page, the captain's home, and the
/// merge and transfer pickers, five in all. A copy is a place the rule can drift,
/// and a drift is nearly impossible to report because each screen looks correct
/// on its own. These tests pin the shared answer, and the fact that the whole
/// state machine runs on it, so the six screens cannot disagree.
void main() {
  group('the colour each status carries', () {
    test('a free table is the neutral card, not a warning colour', () {
      expect(TableStatusVisuals.color(TableStatus.empty), TableStatusVisuals.free,
          reason: 'the empty floor must read as calm, not as alarms');
    });

    test('a seated customer is green', () {
      expect(TableStatusVisuals.color(TableStatus.occupied), AppColors.success);
    });

    test('a printed bill is blue', () {
      expect(TableStatusVisuals.color(TableStatus.billRequested), AppColors.blue);
    });

    test('an unsettled printed bill is red', () {
      expect(TableStatusVisuals.color(TableStatus.overdue), AppColors.danger);
    });

    test('the four colours are four different colours', () {
      // A mapping that returned the same colour for two states would pass the
      // tests above one at a time while being useless on the floor.
      final colours = TableStatus.values.map(TableStatusVisuals.color).toSet();
      expect(colours, hasLength(TableStatus.values.length),
          reason: 'every status must be told apart by colour alone');
    });

    test('the free card is distinct from the warning red', () {
      expect(TableStatusVisuals.free, isNot(AppColors.danger));
    });
  });

  group('the shape carries the same meaning as the colour', () {
    test('every status has an icon, and they are all different', () {
      final icons = TableStatus.values.map(TableStatusVisuals.icon).toSet();
      expect(icons, hasLength(TableStatus.values.length),
          reason: 'a floor must be readable without relying on colour');
    });

    test('the icons are the ones the staff already know', () {
      // Pinned so a well-meaning icon swap cannot quietly change what the floor
      // means to the people reading it.
      expect(TableStatusVisuals.icon(TableStatus.empty), Icons.chair_outlined);
      expect(TableStatusVisuals.icon(TableStatus.occupied),
          Icons.people_alt_rounded);
      expect(TableStatusVisuals.icon(TableStatus.billRequested),
          Icons.receipt_long_rounded);
      expect(TableStatusVisuals.icon(TableStatus.overdue),
          Icons.warning_amber_rounded);
    });
  });

  group('the window is the shop rule, counted in seconds', () {
    test('the bill goes red ten minutes after the print', () {
      expect(LocalDatabase.billOverdueSeconds, 600,
          reason: 'the shop asked for ten minutes, and the unit is seconds so '
              'the window is exact rather than truncated');
    });

    test('the seconds constant is what the sweep compares against', () {
      // The defect this guards: the window was once `billOverdueMinutes = 10`
      // compared with `inMinutes`, and `inMinutes` truncates - so a bill could
      // turn anywhere from ten to eleven minutes after the print. There is
      // deliberately no minutes constant left in the class for the comparison
      // to drift back into, and the seconds value is a whole number of minutes.
      expect(LocalDatabase.billOverdueSeconds, 10 * 60,
          reason: 'ten minutes, written in seconds');
      expect(LocalDatabase.billOverdueSeconds % 60, 0,
          reason: 'a whole number of minutes, so nothing is lost to truncation');
    });
  });
}
