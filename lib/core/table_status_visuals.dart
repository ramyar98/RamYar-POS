import 'package:flutter/material.dart';

import '../models/table_model.dart';
import 'colors.dart';

/// The one place a table's status turns into a colour and an icon.
///
/// Every role's floor screen used to carry its own private copy of this switch:
/// the cashier's home grid, the cashier's unified table page, the captain's
/// home, and the merge and transfer pickers. Five copies of one rule is five
/// places for the rule to quietly drift, and a drift here is close to
/// undiagnosable - the cashier's grid and the captain's grid answer "is this
/// table free?" with different colours, and each screen looks perfectly correct
/// in isolation, so nobody can point at the one that is wrong.
///
/// The states themselves belong to the database and are shared by every role, so
/// the answer is defined once, here, and every screen asks this class. Adding a
/// fifth state means editing one function, not five.
///
/// The colours are the shop's floor signal:
///  * [TableStatus.empty]         - the neutral free-table card;
///  * [TableStatus.occupied]      - green: a customer is sitting there;
///  * [TableStatus.billRequested] - blue: the bill has been issued for the table;
///  * [TableStatus.overdue]       - red: the bill was printed and the customer
///                                  has not come back to pay.
///
/// The blue-to-red handover is the only time-based part, and it is the
/// database's clock, not this class's: the bill is stamped when the cashier
/// prints it and turns red after [LocalDatabase.billOverdueSeconds]. This class
/// only answers "what colour is this state".
class TableStatusVisuals {
  const TableStatusVisuals._();

  /// The neutral dark used for a free table, so an empty floor reads as calm
  /// rather than as a wall of warnings.
  static const Color free = Color(0xFF2C3539);

  /// The status's colour.
  static Color color(TableStatus status) {
    switch (status) {
      case TableStatus.empty:
        return free;
      case TableStatus.occupied:
        return AppColors.success;
      case TableStatus.billRequested:
        return AppColors.blue;
      case TableStatus.overdue:
        return AppColors.danger;
    }
  }

  /// The status's icon, so a table can be read by shape as well as by colour -
  /// which is what keeps the floor usable for a colour-blind member of staff and
  /// on a washed-out screen.
  static IconData icon(TableStatus status) {
    switch (status) {
      case TableStatus.empty:
        return Icons.chair_outlined;
      case TableStatus.occupied:
        return Icons.people_alt_rounded;
      case TableStatus.billRequested:
        return Icons.receipt_long_rounded;
      case TableStatus.overdue:
        return Icons.warning_amber_rounded;
    }
  }
}
