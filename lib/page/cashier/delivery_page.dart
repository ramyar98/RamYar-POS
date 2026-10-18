import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter, TextInputType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../database/local_db.dart';
import '../../models/delivery_company_model.dart';
import '../../models/table_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/delivery_provider.dart';
import '../../services/app_localizations.dart';
import 'cashier_unified_table_page.dart';

/// Cashier delivery panel: one sub-tab per delivery company (تەلەبات / لیزۆ /
/// وادێ by default), each holding its own number of delivery table slots -
/// fifty to start with, and the cashier can raise or lower a company from the
/// panel when one branch is busier than another. A company can be added through
/// the icon-only "+" button (e.g. "Toters") and it stays in the local database
/// forever - synced to every device like the rest of the app - until it is
/// deleted with the trash button.
class DeliveryPage extends ConsumerStatefulWidget {
  const DeliveryPage({super.key});

  @override
  ConsumerState<DeliveryPage> createState() => _DeliveryPageState();
}

/// What the cashier chose to do about a company that still has food on it.
enum _BlockedChoice { cancel, open, voidRequest }

class _DeliveryPageState extends ConsumerState<DeliveryPage> {
  int? _selectedCompanyId;

  LocalDatabase? _db;

  @override
  void initState() {
    super.initState();
    _db = ref.read(localDbProvider);
    _db!.deliveryCompaniesRevision.addListener(_onCompaniesChanged);
  }

  @override
  void dispose() {
    _db?.deliveryCompaniesRevision.removeListener(_onCompaniesChanged);
    super.dispose();
  }

  /// Refetch the registry whenever companies change locally or sync in from
  /// another device (same live-update pattern used across the app).
  void _onCompaniesChanged() {
    if (!mounted) return;
    ref.invalidate(deliveryCompaniesProvider);
    setState(() {});
  }

  DeliveryCompany? _resolveSelected(List<DeliveryCompany> companies) {
    if (companies.isEmpty) return null;
    for (final company in companies) {
      if (company.id == _selectedCompanyId) return company;
    }
    return companies.first;
  }

  Future<void> _addCompany() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _PromptDialog(
        title: context.tr('زیادکردنی کۆمپانیا'),
        labelText: context.tr('ناوی کۆمپانیای دلیڤەری'),
        hintText: 'Toters',
        prefixIcon: Icons.delivery_dining_rounded,
        initialValue: '',
        confirmLabel: context.tr('زیادکردن'),
        fieldKey: const Key('delivery-company-name'),
        confirmKey: const Key('save-delivery-company'),
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final db = ref.read(localDbProvider);
    // Two chips with the same name would be a mystery on the bar and would
    // make the "open the right one" case impossible to reason about later.
    final alreadyThere = (await db.getDeliveryCompanies()).any(
      (company) => company.name.trim() == name.trim(),
    );
    if (!mounted) return;
    if (alreadyThere) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('ئەم ناوە پێشتر زیاد کراوە')),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final id = await db.addDeliveryCompany(name);
    if (mounted && id > 0) {
      // A company added now goes to the end of the bar, and the cashier lands
      // on it ready to ring the first order in.
      setState(() => _selectedCompanyId = id);
    }
  }

  /// Deletes a company - but never over food that has already been rung in.
  ///
  /// A company whose slots still carry an order is refused first. The dialog
  /// names those slots and what is on them, and offers the two ways a shop
  /// really clears a delivery: settle it, or throw the request out. Both leave
  /// a record - the settle in the day's accounts, the void on the discarded
  /// items page - so money rung in never disappears because a company was
  /// tidied away. Only once the company is empty does the ordinary
  /// confirmation run.
  Future<void> _deleteCompany(DeliveryCompany company) async {
    final db = ref.read(localDbProvider);
    final occupied = await db.getOccupiedDeliverySlots(company.id);
    if (!mounted) return;

    if (occupied.isNotEmpty) {
      final choice = await _showBlockedDialog(company, occupied);
      if (!mounted) return;
      if (choice == _BlockedChoice.cancel) return;
      if (choice == _BlockedChoice.open) {
        // Straight to the order so it can be settled or corrected there.
        await _openSlot(company, occupied.first.deliverySlot);
        return;
      }
      final user = ref.read(authProvider);
      for (final slot in occupied) {
        await db.voidTableOrder(
          slot.id,
          cancelledBy: user?.id ?? 0,
          cancelledByName: user?.name ?? '',
        );
      }
      ref.invalidate(deliverySlotsProvider(company.id));
      if (!mounted) return;
      // A till that rang something in during the void must not be silently
      // deleted out from under the cashier: say so instead.
      final stillBusy = await db.getOccupiedDeliverySlots(company.id);
      if (!mounted) return;
      if (stillBusy.isNotEmpty) {
        _notify(
          context.trp('{count} داواکاری نوێ هەڵگیرا، کۆمپانیا سڕ نەکرا', {
            'count': '${stillBusy.length}',
          }),
          AppColors.danger,
        );
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          context.tr('سڕینەوەی کۆمپانیا'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        content: Text(
          context.trp('دڵنیایت لە سڕینەوەی {name}؟', {'name': company.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.tr('ڕەتکردنەوە'),
              style: const TextStyle(color: AppColors.softText),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(context.tr('سڕینەوە')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (_selectedCompanyId == company.id) {
      setState(() => _selectedCompanyId = null);
    }
    // Guarded in the database too: anything that rang in between the check
    // above and this call stops the delete instead of eating the order.
    final deleted = await db.deleteDeliveryCompany(company.id);
    if (!deleted && mounted) {
      _notify(context.tr('سڕینەوە نەکرا - خواردنی تێدایە'), AppColors.danger);
    }
  }

  void _notify(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  /// "This company still has orders on it" - what is on them, and the two ways
  /// to get clear of them.
  Future<_BlockedChoice> _showBlockedDialog(
    DeliveryCompany company,
    List<TableModel> occupied,
  ) async {
    // A branch can have far more slots in use than fit on a 411-tall landscape
    // screen, so the list scrolls and only the first few are listed by name.
    const listed = 6;
    final choice = await showDialog<_BlockedChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('نەتوانرێت سڕبدرێتەوە'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 380),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.trp(
                    '{count} مێزی {name} خواردنی تێدایە. پێش سڕینەوە دەبێت هەریەکە ڕادەخرێت یان دەنرێتەوە.',
                    {'count': '${occupied.length}', 'name': company.name},
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 12),
                ...occupied
                    .take(listed)
                    .map(
                      (slot) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.receipt_long_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                slot.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.darkText,
                                ),
                              ),
                            ),
                            Text(
                              '${context.tr('د.ع')} ${money(slot.totalAmount)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (occupied.length > listed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      context.trp('و {count} مێزی تر...', {
                        'count': '${occupied.length - listed}',
                      }),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.softText,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  context.tr('بۆ سڕینەوە، یەکێک لەمانە بکە:'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _BlockedChoice.cancel),
            child: Text(
              context.tr('هەڵوەشاندنەوە'),
              style: const TextStyle(color: AppColors.softText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _BlockedChoice.open),
            child: Text(
              context.tr('بینینی'),
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
          FilledButton(
            key: const Key('void-delivery-request'),
            onPressed: () => Navigator.pop(ctx, _BlockedChoice.voidRequest),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(context.tr('ڕەتکردنەوەی داواکاری')),
          ),
        ],
      ),
    );
    return choice ?? _BlockedChoice.cancel;
  }

  /// Sets how many table slots this company offers.
  ///
  /// The floor is whatever the company has already used - a slot holding an
  /// order cannot be hidden off the grid - and the ceiling is what the slot
  /// numbering can address without colliding with the next company.
  Future<void> _editSlotCount(DeliveryCompany company) async {
    final db = ref.read(localDbProvider);
    final highestUsed = await db.getHighestUsedDeliverySlot(company.id);
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => _PromptDialog(
        title: context.tr('ژمارەی مێزەکان'),
        labelText: context.tr('ژمارەی مێز'),
        leading: context.trp('ژمارەی مێزەکانی {name}', {'name': company.name}),
        // The cashier is told the boundaries instead of having the number
        // silently clamped under their finger.
        footer: context.trp('لە نێوان {min} و {max} دەبێت بێت', {
          'min': '${highestUsed < 1 ? 1 : highestUsed}',
          'max': '${DeliveryCompany.maxSlotsPerCompany}',
        }),
        initialValue: '${company.slotCount}',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        confirmLabel: context.tr('پاشەکەوتکردن'),
        fieldKey: const Key('delivery-slot-count'),
        confirmKey: const Key('save-delivery-slot-count'),
      ),
    );
    if (text == null || !mounted) return;
    // An empty box is not "set it to nothing": the current count stands.
    final wanted = int.tryParse(text) ?? company.slotCount;
    final stored = await db.setDeliveryCompanySlotCount(company.id, wanted);
    ref.invalidate(deliverySlotsProvider(company.id));
    if (!mounted) return;
    if (stored != wanted) {
      _notify(
        context.trp('ژمارەکە بۆ {count} گۆڕدرا', {'count': '$stored'}),
        AppColors.danger,
      );
    }
  }

  Widget _buildCompanyBar(
    List<DeliveryCompany> companies,
    DeliveryCompany? selected,
  ) {
    return Container(
      key: const Key('delivery-company-bar'),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderSide)),
      ),
      child: Row(
        children: [
          Expanded(
            // Horizontal reorderable list: the companies sit left to right in
            // the shop's order and a chip is dragged into a new place. Sized
            // explicitly because a horizontal list has to be told how tall it
            // is, and given the drag handle's own insets on top of the chip.
            child: SizedBox(
              height: 46,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                buildDefaultDragHandles: false,
                itemCount: companies.length,
                onReorderItem: _onReorderCompany,
                itemBuilder: (context, index) {
                  final company = companies[index];
                  return Padding(
                    key: ValueKey('company-chip-${company.id}'),
                    padding: const EdgeInsets.only(right: 8),
                    child: ReorderableDragStartListener(
                      index: index,
                      child: _CompanyChip(
                        company: company,
                        selected: company.id == selected?.id,
                        onTap: () =>
                            setState(() => _selectedCompanyId = company.id),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Icon-only "+" button: tap it to add a custom delivery company
          // (for example "Toters") - no label, matches the requested design.
          IconButton(
            key: const Key('add-delivery-company'),
            onPressed: _addCompany,
            tooltip: context.tr('زیادکردنی کۆمپانیا'),
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            iconSize: 26,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
          ),
        ],
      ),
    );
  }

  /// Saves a chip's new place on the bar and pushes the order to every device.
  ///
  /// [newIndex] already accounts for the chip being lifted out, so it is the
  /// position it was dropped at. The list is read back from the database rather
  /// than taken from the widget that reported the drag: between the cashier
  /// starting the drag and letting go, a company can be added from another till,
  /// and that one has to end up on the bar too - at the end, not dropped.
  Future<void> _onReorderCompany(int oldIndex, int newIndex) async {
    final companies = await ref.read(localDbProvider).getDeliveryCompanies();
    if (oldIndex < 0 || oldIndex >= companies.length) return;
    if (newIndex < 0 || newIndex >= companies.length) return;
    final reordered = [...companies];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await ref.read(localDbProvider).reorderDeliveryCompanies([
      for (final c in reordered) c.id,
    ]);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delivery_dining_outlined,
              size: 64,
              color: AppColors.softText.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('هیچ کۆمپانیایەک نییە — زیاد بکە'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.softText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotsGrid(
    DeliveryCompany company,
    List<DeliveryCompany> companies,
  ) {
    final slotsAsync = ref.watch(deliverySlotsProvider(company.id));
    // Each company carries its own count, so a quiet branch is not made to
    // scroll through fifty slots and a busy one is not boxed in at twenty.
    final slotCount = company.slotCount;
    return Column(
      children: [
        // Company header: name + slot count + add-tables + delete button.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(
            children: [
              const Icon(
                Icons.delivery_dining_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  company.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                key: const Key('delivery-slot-count-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$slotCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              // Raise the company's slot count: the bar needs more room.
              IconButton(
                key: const Key('edit-delivery-slot-count'),
                onPressed: () => _editSlotCount(company),
                tooltip: context.tr('زیادکردنی مێز'),
                icon: const Icon(
                  Icons.add_box_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                key: const Key('delete-delivery-company'),
                onPressed: () => _deleteCompany(company),
                tooltip: context.tr('سڕینەوەی کۆمپانیا'),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: slotsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (slots) {
                // Slots exist as table rows only once they have been used, so
                // the grid is painted from whatever those rows say, up to the
                // count this company is set to.
                final byNumber = {
                  for (final slot in slots) slot.deliverySlot: slot,
                };
                return ResponsiveGridView(
                  desktopColumns: 5,
                  tabletColumns: 4,
                  mobileColumns: 2,
                  spacing: 12,
                  runSpacing: 12,
                  childAspectRatio: 1.1,
                  itemCount: slotCount,
                  itemBuilder: (context, index) {
                    final number = index + 1;
                    final slot = byNumber[number];
                    return _DeliverySlot(
                      key: Key('delivery-slot-$number'),
                      slot: slot,
                      number: number,
                      companyName: _shortName(company.name),
                      onTap: () => _openSlot(company, number),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Opens a delivery slot as an order: the cashier rings the food in on it the
  /// same way they do on a table, with the bill under it.
  ///
  /// The row behind the slot is made on the spot if this is the first order on
  /// it, so a shop that only ever uses three of the twenty slots holds three
  /// orders rather than twenty empty ones.
  Future<void> _openSlot(DeliveryCompany company, int slotNumber) async {
    final db = ref.read(localDbProvider);
    final table = await db.ensureDeliverySlot(
      company.id,
      company.name,
      slotNumber,
    );
    if (!mounted) return;
    ref.invalidate(deliverySlotsProvider(company.id));
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CashierUnifiedTablePage(
          tableNumber: table.id,
          isDelivery: true,
          deliveryTitle: table.name,
        ),
      ),
    );
    if (!mounted) return;
    // What happened on the slot has to be on the grid: an item added, the slot
    // now in use, or the bill settled and the slot free again.
    ref.invalidate(deliverySlotsProvider(company.id));
  }

  /// Short display name used inside each slot card (long custom names are
  /// truncated instead of overflowing the card).
  String _shortName(String name) {
    if (name.characters.length <= 10) return name;
    return '${name.characters.take(10)}…';
  }

  @override
  Widget build(BuildContext context) {
    final companiesAsync = ref.watch(deliveryCompaniesProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delivery_dining_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              context.tr('دلیڤەری'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: companiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (companies) {
          final selected = _resolveSelected(companies);
          return Column(
            children: [
              _buildCompanyBar(companies, selected),
              Expanded(
                child: selected == null
                    ? _buildEmptyState()
                    : _buildSlotsGrid(selected, companies),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A one-field dialog: the name of a new company, or the number of slots a
/// company has.
///
/// The text controller belongs to this widget rather than to the caller. A
/// controller disposed the moment `showDialog` returns is disposed while the
/// dialog is still fading out, and the field reattaches to it on the way -
/// "A TextEditingController was used after being disposed", which takes the
/// whole delivery panel down. Owning it here also means no caller can forget.
class _PromptDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String? leading;
  final String? hintText;
  final String? footer;
  final IconData? prefixIcon;
  final String initialValue;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String confirmLabel;
  final Key fieldKey;
  final Key confirmKey;

  const _PromptDialog({
    required this.title,
    required this.labelText,
    required this.initialValue,
    required this.confirmLabel,
    required this.fieldKey,
    required this.confirmKey,
    this.leading,
    this.hintText,
    this.footer,
    this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.darkText,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.leading != null) ...[
              Text(
                widget.leading!,
                style: const TextStyle(fontSize: 14, color: AppColors.darkText),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: widget.fieldKey,
              controller: _controller,
              autofocus: true,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: widget.prefixIcon == null
                    ? null
                    : Icon(widget.prefixIcon!, color: AppColors.primary),
              ),
            ),
            if (widget.footer != null) ...[
              const SizedBox(height: 10),
              Text(
                widget.footer!,
                style: const TextStyle(fontSize: 12, color: AppColors.softText),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.tr('ڕەتکردنەوە'),
            style: const TextStyle(color: AppColors.softText),
          ),
        ),
        FilledButton(
          key: widget.confirmKey,
          onPressed: _confirm,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _CompanyChip extends StatelessWidget {
  final DeliveryCompany company;
  final bool selected;
  final VoidCallback onTap;

  const _CompanyChip({
    required this.company,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderSide,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            company.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w600,
              color: selected ? Colors.white : AppColors.darkText,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliverySlot extends StatelessWidget {
  /// The table row behind this slot, or null while it has never been used.
  final TableModel? slot;
  final int number;
  final String companyName;
  final VoidCallback onTap;

  const _DeliverySlot({
    super.key,
    required this.slot,
    required this.number,
    required this.companyName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final table = slot;
    // A slot with an order on it has to be obvious from across the counter, or
    // the same delivery gets rung in twice.
    final inUse = table != null && table.status != TableStatus.empty;
    final total = table?.totalAmount ?? 0;
    final accent = inUse ? AppColors.success : AppColors.primary;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
            border: Border.all(
              color: inUse ? accent : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  inUse
                      ? Icons.receipt_long_rounded
                      : Icons.delivery_dining_rounded,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$companyName $number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
              ),
              if (inUse) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    // The amount on the slot, so the cashier can see what a
                    // delivery has on it without opening it.
                    '${context.tr('د.ع')} ${money(total)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
