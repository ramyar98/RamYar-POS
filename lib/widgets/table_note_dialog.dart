import 'package:flutter/material.dart';

import '../core/colors.dart';
import '../services/app_localizations.dart';

/// What the user typed in the table-note dialog. `null` (the dialog's result
/// when it is dismissed) means "nothing to save".
class TableNoteResult {
  final String captain;
  final String admin;

  const TableNoteResult({required this.captain, required this.admin});
}

/// The «تێبینی» editor, shared by the captain's table page and the cashier's
/// unified table page.
///
/// It is a [StatefulWidget] on purpose: it owns its two
/// [TextEditingController]s, so they are disposed together with the dialog.
/// Disposing them in the caller once `showDialog` returns is a bug - the route
/// is still animating out and its [TextField]s rebuild while the soft keyboard
/// closes, which threw "A TextEditingController was used after being disposed".
///
/// The layout is built for a landscape phone, where the on-screen keyboard can
/// eat three fifths of the screen: the dialog reserves only a thin frame
/// ([insetPadding]/[contentPadding]) and keeps the heading inside the scrollable
/// body instead of in [AlertDialog.title], so the text fields get almost all of
/// the height that is left. A plain title + content Column overflowed here, and
/// the fields ended up clipped to a sliver.
class TableNoteDialog extends StatefulWidget {
  /// Heading, e.g. «تێبینی» (captain) or «تێبینی بۆ مێز» (cashier).
  final String title;

  final String captainText;
  final String adminText;

  /// A captain may only write their own note; the admin field is then hidden
  /// and [TableNoteResult.admin] comes back empty.
  final bool showAdminField;

  const TableNoteDialog({
    super.key,
    required this.title,
    this.captainText = '',
    this.adminText = '',
    this.showAdminField = true,
  });

  @override
  State<TableNoteDialog> createState() => _TableNoteDialogState();
}

class _TableNoteDialogState extends State<TableNoteDialog> {
  late final TextEditingController _captainCtrl;
  late final TextEditingController _adminCtrl;

  @override
  void initState() {
    super.initState();
    _captainCtrl = TextEditingController(text: widget.captainText);
    _adminCtrl = TextEditingController(text: widget.adminText);
  }

  @override
  void dispose() {
    _captainCtrl.dispose();
    _adminCtrl.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      TableNoteResult(
        captain: _captainCtrl.text.trim(),
        admin: _adminCtrl.text.trim(),
      ),
    );
  }

  /// The label rides inside the field ([InputDecoration.labelText]) instead of
  /// sitting above it: a separate label row costs ~26dp of the ~170dp that are
  /// left on a landscape phone once the keyboard is up, and the field used to be
  /// pushed out of view.
  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        isDense: true,
        labelText: context.tr(label),
        hintText: context.tr(hint),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      // Keeps the dialog usable when the keyboard leaves it a few dozen pixels.
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.note_alt_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(
              controller: _captainCtrl,
              label: 'تێبینیی کاپتن',
              hint: 'بۆ کاشێر/ئادمێن بنوسە...',
            ),
            if (widget.showAdminField) ...[
              const SizedBox(height: 8),
              _field(
                controller: _adminCtrl,
                label: 'تێبینی بۆ ئادمێن',
                hint: 'ئادمێن بزانێت...',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('ڕەتکردنەوە')),
        ),
        FilledButton(onPressed: _save, child: Text(context.tr('پاشەکەوتکردن'))),
      ],
    );
  }
}
