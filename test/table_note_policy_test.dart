import 'package:flutter_test/flutter_test.dart';
import 'package:ramyar_pos/models/user_model.dart';
import 'package:ramyar_pos/services/table_note_policy.dart';

void main() {
  test('cashier can edit admin notes', () {
    expect(TableNotePolicy.canEditAdminNote(UserRole.cashier), isTrue);
  });

  test('captain and waiter cannot edit admin notes', () {
    expect(TableNotePolicy.canEditAdminNote(UserRole.waiter), isFalse);
    expect(TableNotePolicy.canEditAdminNote(UserRole.admin), isFalse);
  });
}
