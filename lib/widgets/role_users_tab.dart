import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/colors.dart';
import '../core/constants.dart';
import '../core/digits.dart';
import '../core/responsive.dart';
import '../services/app_localizations.dart';
import '../database/local_db.dart';
import '../models/user_model.dart';

/// Role-scoped user management panel: add-account form plus a live list of
/// that role's accounts showing name, 5-digit PIN, table range and IP code.
/// Every created user is written through [LocalDatabase.addUser] which
/// broadcasts a `USER_CREATED` sync mutation to all connected nodes so the
/// registry reaches every device instantly.
class RoleUsersTab extends ConsumerStatefulWidget {
  final UserRole role;

  const RoleUsersTab({super.key, required this.role});

  @override
  ConsumerState<RoleUsersTab> createState() => _RoleUsersTabState();
}

class _RoleUsersTabState extends ConsumerState<RoleUsersTab> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isAdding = false;
  LocalDatabase? _db;

  /// The user list query, created once per refresh instead of on every build.
  ///
  /// It used to be `ref.read(...).getUsersByRole(...)` inline in `build`, so
  /// every keystroke in the PIN field started a new query and each rebuild that
  /// landed before it resolved flashed "هیچ بەکارهێنەرێک نییە".
  Future<List<UserModel>>? _usersFuture;

  /// True while «دروستکردنی نوێ» is writing a fresh access code, so a double
  /// tap cannot run two writes and pop the dialog twice.
  bool _regeneratingCode = false;

  @override
  void initState() {
    super.initState();
    // Live-update: refresh the user list on this tab whenever users change on
    // any connected device (works even when the hosting page builds this tab
    // as a const child by wiring the revision listener here directly).
    final db = ref.read(localDbProvider);
    _db = db;
    _usersFuture = db.getUsersByRole(widget.role);
    db.usersRevision.addListener(_onUsersChanged);
  }

  @override
  void didUpdateWidget(covariant RoleUsersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role) {
      _usersFuture = ref.read(localDbProvider).getUsersByRole(widget.role);
    }
  }

  void _onUsersChanged() {
    if (!mounted) return;
    setState(() {
      _usersFuture = ref.read(localDbProvider).getUsersByRole(widget.role);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    // Never touch ref after dispose - Riverpod forbids it (throws
    // "Cannot use ref after the widget was disposed"). Use the cached
    // database reference captured in initState instead.
    _db?.usersRevision.removeListener(_onUsersChanged);
    super.dispose();
  }

  /// A PIN is exactly five ASCII digits, after normalising the localized
  /// Arabic-Indic / Persian / fullwidth forms a regional keyboard produces.
  bool _isValidPin(String pin) => _isFiveDigitPin(pin);

  Future<void> _showChangePinDialog(UserModel user) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePinDialog(user: user),
    );
    if (changed == true && mounted) setState(() {});
  }

  String _generateUniqueCode(List<String> existing) {
    final used = existing.map((c) => c.trim()).toSet();
    final r = Random();
    for (int attempt = 0; attempt < 300; attempt++) {
      final x = 1 + r.nextInt(254);
      final y = 1 + r.nextInt(254);
      final code = '192.168.$x.$y';
      if (!used.contains(code)) return code;
    }
    final n = DateTime.now().millisecondsSinceEpoch % 9000 + 1000;
    return '192.168.${n ~/ 256}.${n % 256}';
  }

  Future<void> _addUser() async {
    final name = _nameController.text.trim();
    // Store the ASCII form so the PIN matches what the login keypad submits.
    final pin = toLatinDigits(_pinController.text.trim());
    if (name.isEmpty) {
      _showSnack(context.tr('ناو پێویستە'), AppColors.danger);
      return;
    }
    if (!_isValidPin(pin)) {
      _showSnack(context.tr('وشەی نهێنی دەبێت ٥ ژمارە بێت'), AppColors.danger);
      return;
    }
    if (_isAdding) return;
    setState(() => _isAdding = true);
    try {
      final db = ref.read(localDbProvider);
      final existingCodes = await db.getAllAccessCodes();
      final accessCode = _generateUniqueCode(existingCodes);
      final saved = await db.addUser(name, pin, widget.role, accessCode: accessCode);
      if (!mounted) return;
      if (saved) {
        _nameController.clear();
        _pinController.clear();
        _showSnack(
          context.trp('{name} بە سەرکەوتوویی زیاد کرا (IP: {code})', {'name': name, 'code': accessCode}),
          AppColors.success,
        );
      } else {
        _showSnack(context.tr('هەڵەیەک ڕوویدا لە زیادکردندا'), AppColors.danger);
      }
    } catch (_) {
      // A failed/locked write used to leave `_isAdding` stuck at true, which
      // disabled the Add button for the rest of the session with no explanation.
      if (mounted) {
        _showSnack(context.tr('هەڵەیەک ڕوویدا لە زیادکردندا'), AppColors.danger);
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteUser(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('سڕینەوەی بەکارهێنەر')),
        content: Text(context.trp('دڵنیایت دەتەوێت {name} بسڕیتەوە؟', {'name': user.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('ڕەتکردنەوە'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('سڕینەوە'))),
        ],
      ),
    );
    if (confirm == true) {
      final db = ref.read(localDbProvider);
      await db.deleteUser(user.id);
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _showAssignTablesDialog(UserModel waiter) async {
    final db = ref.read(localDbProvider);
    final allTables = await db.getAllTables();
    final assignedIds = await db.getWaiterTableIds(waiter.id);
    final selectedIds = List<int>.from(assignedIds);

    if (!mounted) return;
    // A plain `Dialog` is used here instead of `AlertDialog`, on purpose.
    // `AlertDialog` wraps its content in `IntrinsicWidth` so the dialog can
    // shrink-wrap around the title text, and *no* viewport (GridView / ListView)
    // can answer an intrinsic-dimension query - it throws "RenderViewport does
    // not support returning intrinsic dimensions". That exception aborts the
    // dialog's layout, so the table grid was never painted and tapping
    // "دیاریکردنی مێز" looked completely dead. `Dialog` runs no intrinsic
    // pass, so a real scrollable grid works here.
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = min(500.0, max(220.0, screen.width - 80));
    final dialogHeight = min(500.0, max(160.0, screen.height - 80));
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.trp('دیاریکردنی مێز بۆ {name}', {'name': waiter.name}),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.darkText),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(context.tr('مێزە دیاریکراوەکان'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.darkText)),
                        ),
                        const Spacer(),
                        Text('${selectedIds.length}/${allTables.length}', style: const TextStyle(color: AppColors.softText)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      // Expanded (not a fixed height) so the grid takes exactly
                      // the space the dialog has left and scrolls - on a phone
                      // in landscape the dialog is only ~190px tall.
                      child: allTables.isEmpty
                          ? Center(child: Text(context.tr('هیچ مێزێک نییە'), style: const TextStyle(color: AppColors.softText)))
                          : ResponsiveGridView(
                              desktopColumns: 5,
                              tabletColumns: 4,
                              mobileColumns: 3,
                              spacing: 8,
                              runSpacing: 8,
                              childAspectRatio: 1.4,
                              itemCount: allTables.length,
                              itemBuilder: (context, index) {
                                final table = allTables[index];
                                final isSelected = selectedIds.contains(table.id);
                                return InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      if (isSelected) {
                                        selectedIds.remove(table.id);
                                      } else {
                                        selectedIds.add(table.id);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.background,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? AppColors.primary : AppColors.borderSide,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Text(
                                          table.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? AppColors.primary : AppColors.darkText,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    // Wrap, not Row: on a narrow dialog (or with a bigger
                    // system font) two buttons side by side can push past the
                    // edge and get clipped; wrapping stacks them instead.
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          // «گەڕاندنەوە بۆ ئاسایی»: the same single reset the
                          // range dialog uses. The numeric range and the picked
                          // tables are two halves of one scope, so this clears
                          // BOTH - otherwise resetting here would leave a range
                          // still in force and the account would not be normal.
                          onPressed: () async {
                            await db.resetWaiterScope(waiter.id);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            setState(() {});
                          },
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(context.tr('گەڕاندنەوە بۆ ئاسایی')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(context.tr('ڕەتکردنەوە')),
                        ),
                        FilledButton(
                          onPressed: () async {
                            await db.assignTablesToWaiter(waiter.id, selectedIds);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            setState(() {});
                          },
                          child: Text(context.tr('پاشەکەوتکردن')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showRangeDialog(UserModel waiter) async {
    final db = ref.read(localDbProvider);
    // The dialog owns its TextEditingControllers (see `_TableRangeDialog`).
    // They used to be created here and disposed immediately after
    // `showDialog` returned - but the route is still animating out at that
    // point, so its TextFields kept using the disposed controllers and the
    // frame threw "A TextEditingController was used after being disposed".
    // That aborted the very repaint that shows the freshly saved مەودا, so
    // pressing پاشەکەوتکردن looked like it did nothing at all.
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TableRangeDialog(waiter: waiter, db: db),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _showIpDialog(UserModel user) async {
    final db = ref.read(localDbProvider);
    final existing = await db.getAllAccessCodes();
    var code = (user.accessCode ?? '').trim();
    if (code.isEmpty) {
      code = _generateUniqueCode(existing);
      await db.setUserAccessCode(user.id, code);
    }
    if (!mounted) return;
    setState(() {});
    await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final current = (user.accessCode ?? '').trim().isEmpty ? code : (user.accessCode ?? '');
          return AlertDialog(
            title: Text(context.trp('نیشانەی IP بۆ {name}', {'name': user.name})),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('بەکارهێنەرەکە ئەم نیشانەیە لە سیاتینگەکانی خۆیدا دادەنێت؛ بۆ سینککردن پێویستە دروست بێت.'),
                    style: const TextStyle(color: AppColors.softText, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Flexible + FittedBox: a long access code in a narrow
                          // dialog used to throw a right-side overflow stripe.
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SelectableText(
                                current,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 20),
                            tooltip: context.tr('کۆپی'),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: current));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(context.tr('کۆپی کرا')), backgroundColor: AppColors.success, duration: const Duration(seconds: 1)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: Text(context.tr('داخستن'))),
              TextButton.icon(
                onPressed: _regeneratingCode
                    ? null
                    : () async {
                        setDialogState(() => _regeneratingCode = true);
                        try {
                          final newCode = _generateUniqueCode(existing.where((c) => c != current).toList());
                          await db.setUserAccessCode(user.id, newCode);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx, 'regenerate');
                          setState(() {});
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => _regeneratingCode = false);
                          }
                        }
                      },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.tr('دروستکردنی نوێ')),
              ),
            ],
          );
        },
      ),
    );
  }

  /// فۆڕمی زیادکردنی بەکارهێنەر.
  ///
  /// لەسەر شاشەی بەرز (portrait ـی موبایل) فێڵدەکانی ناو و PIN پڕ-پانی
  /// شاشەن و لەژێر یەکتردا دەنیشێن، بۆ ئەوەی لەیبڵە درێژەکان (وەک
  /// «وشەی نهێنی (٥ ژمارە)») نەبڕدرێن و «تێکستی نامۆ» دەرنەکەوێت.
  /// لەسەر شاشەی ڕاستەکی (landscape) یان پانتر ڕیزە (Row) دەبێت.
  Widget _buildAddUserForm({required bool stackForm}) {
    final nameField = TextField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: context.tr('ناو'),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
    final pinField = TextField(
      controller: _pinController,
      keyboardType: TextInputType.number,
      maxLength: 5,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: context.tr('وشەی نهێنی (٥ ژمارە)'),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        counterText: '',
      ),
    );
    final addButton = FilledButton.icon(
      onPressed: _isAdding ? null : () => _addUser(),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(context.tr('زیادکردن')),
    );

    if (stackForm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          nameField,
          const SizedBox(height: 12),
          pinField,
          const SizedBox(height: 12),
          addButton,
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(width: 180, child: nameField),
          const SizedBox(width: 12),
          SizedBox(width: 210, child: pinField),
          const SizedBox(width: 12),
          addButton,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UserModel>>(
      future: _usersFuture ??= ref.read(localDbProvider).getUsersByRole(widget.role),
      builder: (context, snapshot) {
        final users = snapshot.data ?? [];
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(AppConstants.paddingMedium),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  _buildAddUserForm(
                    // ستوون تەنها کاتێک شاشەکە بەرزە (portrait)؛ لە دیمەنی
                    // ڕاستەکی کورت (landscape) ڕیزە (Row) باشترە تا
                    // فۆڕمەکە لە بەرزایی شاشەکە زیاد نەبێت.
                    stackForm: MediaQuery.sizeOf(context).height >= 480,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('هەر بەکارهێنەرێکی نوێ دەستبەجێ بۆ هەموو ئامێرەکانی تۆڕەکە دەنێردرێت'),
                    style: const TextStyle(color: AppColors.softText, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: snapshot.hasError
                  ? Center(
                      child: Text(
                        context.tr('هەڵەیەک ڕوویدا لە خوێندنەوە'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.softText),
                      ),
                    )
                  : snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : users.isEmpty
                          ? Center(child: Text(context.tr('هیچ بەکارهێنەرێک نییە'), style: TextStyle(color: AppColors.softText)))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium),
                              itemCount: users.length,
                              itemBuilder: (context, index) {
                                final user = users[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Five action icons beside the name need ~220px;
                              // on a 320px phone that left the name column ~40px
                              // and painted a red overflow stripe. Below 560px
                              // the actions drop to their own row instead.
                              final compact = constraints.maxWidth < 560;
                              final actions = <Widget>[
                                IconButton(
                                  icon: const Icon(Icons.router_rounded, color: AppColors.blue, size: 20),
                                  tooltip: context.tr('نیشانەی IP'),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero),
                                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                  onPressed: () => _showIpDialog(user),
                                ),
                                if (widget.role == UserRole.waiter)
                                  IconButton(
                                    icon: const Icon(Icons.filter_alt_rounded, color: AppColors.blue, size: 20),
                                    tooltip: context.tr('دیاریکردنی مەودای مێز'),
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero),
                                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                    onPressed: () => _showRangeDialog(user),
                                  ),
                                if (widget.role == UserRole.waiter)
                                  IconButton(
                                    icon: const Icon(Icons.table_restaurant_rounded, color: AppColors.success, size: 20),
                                    tooltip: context.tr('دیاریکردنی مێز'),
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero),
                                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                    onPressed: () => _showAssignTablesDialog(user),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 20),
                                  tooltip: context.tr('گۆڕینی وشەی نهێنی'),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero),
                                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                  onPressed: () => _showChangePinDialog(user),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                                  tooltip: context.tr('سڕینەوە'),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: EdgeInsets.zero),
                                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                  onPressed: () => _deleteUser(user),
                                ),
                              ];
                              final identity = Row(
                                children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(child: Text('${user.id}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary))),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkText)),
                                        Text(user.hasRange
                                            ? 'PIN: ${user.pin}  •  ${context.tr('مەودا')}: ${user.rangeStart}-${user.rangeEnd}'
                                            : 'PIN: ${user.pin}', style: const TextStyle(color: AppColors.softText, fontSize: 13)),
                                        if ((user.accessCode ?? '').trim().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'IP: ${user.accessCode!.trim()}',
                                              style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                              if (!compact) {
                                return Row(children: [...identity.children, ...actions]);
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  identity,
                                  const SizedBox(height: 4),
                                  Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// «دیاریکردنی مەودای مێز» for one captain.
///
/// A real [StatefulWidget] rather than a [StatefulBuilder] so the two
/// [TextEditingController]s are owned by a widget and disposed only when the
/// dialog route is actually removed from the tree. Disposing them the moment
/// `showDialog` resolved used to crash the exit-animation frame (the TextFields
/// still held the controllers), and because that frame is the one that repaints
/// the owner's list, a saved مەودا never appeared - the button looked like pure
/// decoration. Typing here calls `setState`, so the description line and the
/// پاشەکەوتکردن button update live, exactly like the pick-tables dialog.
class _TableRangeDialog extends StatefulWidget {
  final UserModel waiter;
  final LocalDatabase db;

  const _TableRangeDialog({required this.waiter, required this.db});

  @override
  State<_TableRangeDialog> createState() => _TableRangeDialogState();
}

class _TableRangeDialogState extends State<_TableRangeDialog> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  /// True while a save/reset write is in flight, so a double tap cannot run the
  /// write twice or pop the route beneath the dialog.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: widget.waiter.rangeStart?.toString() ?? '');
    _endController = TextEditingController(text: widget.waiter.rangeEnd?.toString() ?? '');
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Normalise Arabic-Indic/Persian digits: `int.tryParse('٥')` is null, so a
    // captain typing ٥..١٠ used to see the Save button stay disabled.
    final start = int.tryParse(toLatinDigits(_startController.text.trim()));
    final end = int.tryParse(toLatinDigits(_endController.text.trim()));
    final valid = start != null && end != null && start <= end;
    return AlertDialog(
      title: Text(context.trp('دیاریکردنی مەودای مێز بۆ {name}', {'name': widget.waiter.name})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.trp('وەیتەرەکە تەنها ئەو مێزانە دەبینێت کە لە نێوان مەوداکەدان (لە {start} بۆ {end})', {
              'start': start?.toString() ?? '؟',
              'end': end?.toString() ?? '؟',
            }), style: const TextStyle(color: AppColors.softText, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('لە مێزی'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('بۆ مێزی'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        // Same single reset as the pick-tables dialog: clears the range
        // AND the picked tables, so one press is genuinely "normal".
        TextButton.icon(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.db.resetWaiterScope(widget.waiter.id);
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                },
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: Text(context.tr('گەڕاندنەوە بۆ ئاسایی')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('ڕەتکردنەوە')),
        ),
        FilledButton(
          onPressed: valid
              ? () async {
                  if (_saving) return;
                  setState(() => _saving = true);
                  await widget.db.updateUserRange(widget.waiter.id, start, end);
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                }
              : null,
          child: Text(context.tr('پاشەکەوتکردن')),
        ),
      ],
    );
  }
}

/// True when [pin] is exactly five ASCII digits.
///
/// Normalises first: a PIN typed on an Arabic/Persian keyboard arrives as ٠-٩ /
/// ۰-۹ and a raw code-unit range check rejected it even though it was a
/// perfectly good five-digit PIN.
bool _isFiveDigitPin(String pin) {
  final trimmed = toLatinDigits(pin.trim());
  if (trimmed.length != 5) return false;
  for (final ch in trimmed.split('')) {
    if (ch.codeUnitAt(0) < 48 || ch.codeUnitAt(0) > 57) return false;
  }
  return true;
}

/// «گۆڕینی وشەی نهێنی» for one account.
///
/// A real [ConsumerStatefulWidget] rather than a `StatefulBuilder` so the PIN
/// controller is disposed with the route (it used to leak on every open) and a
/// `_saving` flag so a double tap cannot run two writes and pop the page behind
/// the dialog.
class _ChangePinDialog extends ConsumerStatefulWidget {
  const _ChangePinDialog({required this.user});

  final UserModel user;

  @override
  ConsumerState<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends ConsumerState<_ChangePinDialog> {
  final _pinController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final newPin = toLatinDigits(_pinController.text.trim());
    if (!_isFiveDigitPin(newPin)) {
      setState(() => _error = context.tr('وشەی نهێنی دەبێت ٥ ژمارە بێت'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(localDbProvider).updateUserPin(widget.user.id, newPin);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = context.tr('هەڵەیەک ڕوویدا لە زیادکردندا');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('گۆڕینی وشەی نهێنی')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.trp('وشەی نهێنی نوێ بۆ {name}',
                  {'name': widget.user.name}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 5,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: context.tr('وشەی نهێنی (٥ ژمارە)'),
                errorText: _error,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(context.tr('ڕەتکردنەوە')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(context.tr('گۆڕین')),
        ),
      ],
    );
  }
}
