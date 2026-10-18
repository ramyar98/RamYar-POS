import '../models/user_model.dart';

/// The two halves of a table's note, packed into the one `tables.note` column.
///
/// A captain writes the first half; the cashier writes the second. The marker
/// separates them, so a note with no cashier line is just the captain's text and
/// reads back unchanged. One codec, so the captain's page, the cashier's page,
/// the admin's «تێبینیی مێزەکان» list and the shift report all fold and unfold
/// the same string the same way.
class TableNote {
  static const String marker = '__ADMIN_NOTE__';

  static Map<String, String> decode(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return {'captain': '', 'admin': ''};
    final split = normalized.split(marker);
    if (split.length == 1) {
      return {'captain': normalized, 'admin': ''};
    }
    return {
      'captain': split.first.trim(),
      'admin': split.sublist(1).join(marker).trim(),
    };
  }

  static String encode({required String captain, required String admin}) {
    final parts = <String>[];
    final captainTrim = captain.trim();
    final adminTrim = admin.trim();
    if (captainTrim.isNotEmpty) parts.add(captainTrim);
    if (adminTrim.isNotEmpty) {
      parts.add(marker);
      parts.add(adminTrim);
    }
    return parts.join('\n');
  }
}

class TableNotePolicy {
  static bool canEditAdminNote(UserRole? role) => role == UserRole.cashier;

  static String effectiveAdminNote({
    required bool canEdit,
    required String editedAdmin,
    required String existingAdmin,
  }) {
    return canEdit ? editedAdmin.trim() : existingAdmin.trim();
  }
}
