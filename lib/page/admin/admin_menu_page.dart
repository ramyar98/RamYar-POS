import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/app.dart';
import '../../core/responsive.dart';
import '../../widgets/amount_input_formatter.dart';
import '../../widgets/dialog_controller_owner.dart';
import '../../services/app_localizations.dart';
import '../../services/menu_helper.dart';
import '../../services/food_localization.dart';
import '../../database/local_db.dart';
import '../../models/printer_model.dart';

class AdminMenuPage extends ConsumerStatefulWidget {
  const AdminMenuPage({super.key});

  @override
  ConsumerState<AdminMenuPage> createState() => _AdminMenuPageState();
}

class _AdminMenuPageState extends ConsumerState<AdminMenuPage> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _items = [];
  String? _selectedCategory;
  bool _loading = true;

  bool _printerMode = false;
  Map<String, List<PrinterType>> _printerAssignments = {};
  final Set<String> _selectedItems = {};
  final Map<PrinterType, bool> _printerCheckState = {
    PrinterType.bar: false,
    PrinterType.kitchen: false,
    PrinterType.hookah: false,
    PrinterType.cashier: false,
  };

  final List<String> _iconOptions = [
    'lunch_dining',
    'local_pizza',
    'set_meal',
    'rice_bowl',
    'kebab_dining',
    'cake',
    'local_drink',
    'soup_kitchen',
    'eco',
    'restaurant',
    'fastfood',
    'egg',
    'bakery_dining',
    'ramen_dining',
    'tapas',
    'icecream',
    'coffee',
    'water_drop',
  ];

  final List<String> _sectionOptions = ['گەرمی', 'ساردی', 'شیرینی', 'کێک'];

  @override
  void initState() {
    super.initState();
    // Keep the db reference for the dispose() cleanup - `ref` must not be
    // touched after the widget is disposed.
    _db = ref.read(localDbProvider);
    _loadMenu();
    // Live menu refresh: a menu change pushed from the admin device (or any
    // synced-in remote change) appears here without re-navigating.
    _db.foodMenuRevision.addListener(_onMenuChanged);
  }

  @override
  void dispose() {
    _db.foodMenuRevision.removeListener(_onMenuChanged);
    super.dispose();
  }

  late final LocalDatabase _db;

  void _onMenuChanged() {
    if (mounted) _loadMenu();
  }

  Future<void> _loadMenu() async {
    final db = ref.read(localDbProvider);
    _categories = await db.getFoodCategories();
    _items = await db.getFoodItems();
    if (_selectedCategory == null && _categories.isNotEmpty) {
      _selectedCategory = _categories.first['name'] as String;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _togglePrinterMode() async {
    if (!_printerMode) {
      final db = ref.read(localDbProvider);
      final assignments = await db.getAllItemPrinterAssignments();
      if (!mounted) return;
      setState(() {
        _printerAssignments = assignments;
        _selectedItems.clear();
        _printerCheckState.updateAll((_, _) => false);
        _printerMode = true;
      });
    } else {
      setState(() {
        _printerMode = false;
        _selectedItems.clear();
      });
    }
  }

  Color _printerDotColor(PrinterType type) {
    switch (type) {
      case PrinterType.bar:
        return Colors.blue;
      case PrinterType.kitchen:
        return Colors.orange;
      case PrinterType.hookah:
        return Colors.purple;
      case PrinterType.cashier:
        return Colors.green;
    }
  }

  String _printerLabel(PrinterType type) {
    switch (type) {
      case PrinterType.bar:
        return context.tr('باڕ');
      case PrinterType.kitchen:
        return context.tr('مەتبەخ');
      case PrinterType.hookah:
        return context.tr('نێرگیلە');
      case PrinterType.cashier:
        return context.tr('کاشێر');
    }
  }

  Future<void> _savePrinterAssignments() async {
    if (_selectedItems.isEmpty) return;
    final checkedTypes = _printerCheckState.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (checkedTypes.isEmpty) return;
    final db = ref.read(localDbProvider);
    for (final itemName in _selectedItems) {
      await db.setItemPrinterAssignments(itemName, checkedTypes);
    }
    await _togglePrinterMode();
  }

  Future<void> _showItemPrinterDialog(String itemName) async {
    final currentAssignments = List<PrinterType>.from(
      _printerAssignments[itemName] ?? [],
    );
    final checkState = {
      PrinterType.bar: currentAssignments.contains(PrinterType.bar),
      PrinterType.kitchen: currentAssignments.contains(PrinterType.kitchen),
      PrinterType.hookah: currentAssignments.contains(PrinterType.hookah),
      PrinterType.cashier: currentAssignments.contains(PrinterType.cashier),
    };
    final result = await showDialog<Map<PrinterType, bool>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.tr('شوێنی چاپ')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  itemName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                ...PrinterType.values.map(
                  (type) => CheckboxListTile(
                    value: checkState[type] ?? false,
                    onChanged: (v) =>
                        setDialogState(() => checkState[type] = v ?? false),
                    title: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _printerDotColor(type),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(_printerLabel(type)),
                      ],
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(context.tr('ڕەتکردنەوە')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, checkState),
              child: Text(context.tr('پاشەکەوت')),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      final types = result.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();
      final db = ref.read(localDbProvider);
      await db.setItemPrinterAssignments(itemName, types);
      final assignments = await db.getAllItemPrinterAssignments();
      setState(() => _printerAssignments = assignments);
    }
  }

  Widget _buildPrinterBottomPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  context.tr('شوێنی چاپ'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _selectedItems.isEmpty
                        ? AppColors.softText.withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_selectedItems.length} ${context.tr('هەڵبژێردراو')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _selectedItems.isEmpty
                          ? AppColors.softText
                          : AppColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedItems.clear()),
                  icon: const Icon(Icons.clear, size: 16),
                  label: Text(
                    context.tr('لابردن'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.softText,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: PrinterType.values
                  .map(
                    (type) => Expanded(
                      child: InkWell(
                        onTap: () => setState(
                          () => _printerCheckState[type] =
                              !(_printerCheckState[type] ?? false),
                        ),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: (_printerCheckState[type] ?? false)
                                ? _printerDotColor(type).withValues(alpha: 0.12)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (_printerCheckState[type] ?? false)
                                  ? _printerDotColor(type)
                                  : AppColors.borderSide,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.print_rounded,
                                size: 18,
                                color: (_printerCheckState[type] ?? false)
                                    ? _printerDotColor(type)
                                    : AppColors.softText,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _printerLabel(type),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: (_printerCheckState[type] ?? false)
                                      ? _printerDotColor(type)
                                      : AppColors.softText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selectedItems.isEmpty
                    ? null
                    : _savePrinterAssignments,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(context.tr('جێبەجێکردن')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCategory() async {
    final nameCtrl = TextEditingController();
    String selectedIcon = _iconOptions.first;
    String selectedSection = _sectionOptions.first;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogControllerOwner(
        controllers: [nameCtrl],
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(context.tr('زیادکردنی بەش')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: context.tr('ناوی بەش'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSection,
                    decoration: InputDecoration(
                      labelText: context.tr('بەشی سەرەکی'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _sectionOptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(context.tr(s)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(
                      () => selectedSection = v ?? _sectionOptions.first,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedIcon,
                    decoration: InputDecoration(
                      labelText: context.tr('ئایکۆن'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _iconOptions
                        .map(
                          (icon) => DropdownMenuItem(
                            value: icon,
                            child: Row(
                              children: [
                                Icon(MenuHelper.iconFromString(icon), size: 20),
                                const SizedBox(width: 8),
                                // Translated label, not the internal key: the
                                // dropdown used to print «lunch_dining» and
                                // «fastfood» straight at the admin.
                                Expanded(
                                  child: Text(
                                    MenuHelper.labelForIcon(icon, context.tr),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(
                      () => selectedIcon = v ?? _iconOptions.first,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('ڕەتکردنەوە')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.tr('زیادکردن')),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      await ref
          .read(localDbProvider)
          .addFoodCategory(
            nameCtrl.text.trim(),
            selectedIcon,
            section: selectedSection,
          );
      await _loadMenu();
    }
  }

  Future<void> _editCategory(Map<String, dynamic> cat) async {
    final nameCtrl = TextEditingController(text: cat['name'] as String);
    String selectedIcon = cat['icon'] as String;
    String selectedSection = cat['section'] as String? ?? '';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogControllerOwner(
        controllers: [nameCtrl],
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(context.tr('گۆڕینی بەش')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: context.tr('ناوی بەش'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSection,
                    decoration: InputDecoration(
                      labelText: context.tr('بەشی سەرەکی'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _sectionOptions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(context.tr(s)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedSection = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedIcon,
                    decoration: InputDecoration(
                      labelText: context.tr('ئایکۆن'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _iconOptions
                        .map(
                          (icon) => DropdownMenuItem(
                            value: icon,
                            child: Row(
                              children: [
                                Icon(MenuHelper.iconFromString(icon), size: 20),
                                const SizedBox(width: 8),
                                // Translated label, not the internal key: the
                                // dropdown used to print «lunch_dining» and
                                // «fastfood» straight at the admin.
                                Expanded(
                                  child: Text(
                                    MenuHelper.labelForIcon(icon, context.tr),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(
                      () => selectedIcon = v ?? _iconOptions.first,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('ڕەتکردنەوە')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.tr('گۆڕین')),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      await ref
          .read(localDbProvider)
          .updateFoodCategory(
            cat['id'] as int,
            nameCtrl.text.trim(),
            selectedIcon,
            section: selectedSection,
          );
      await _loadMenu();
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> cat) async {
    final itemCount = _items.where((i) => i['category'] == cat['name']).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('سڕینەوەی بەش')),
        content: Text(
          context.trp(
            'دڵنیایت دەتەوێت بەشی {name} بسڕیتەوە؟ {count} خواردنیش دەسڕێتەوە.',
            {'name': cat['name'] as String, 'count': '$itemCount'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('ڕەتکردنەوە')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('سڕینەوە')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref
          .read(localDbProvider)
          .deleteFoodCategory(cat['id'] as int, cat['name'] as String);
      await _loadMenu();
    }
  }

  Future<void> _addItem() async {
    final ctrlKu = TextEditingController();
    final ctrlAr = TextEditingController();
    final ctrlFa = TextEditingController();
    final ctrlEn = TextEditingController();
    final ctrlTr = TextEditingController();
    final priceCtrl = TextEditingController();
    String? selectedCat =
        _selectedCategory ??
        (_categories.isNotEmpty ? _categories.first['name'] as String : null);
    String selectedIcon = _iconOptions[_iconOptions.length ~/ 2];
    if (selectedCat == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogControllerOwner(
        controllers: [ctrlKu, ctrlAr, ctrlFa, ctrlEn, ctrlTr, priceCtrl],
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(context.tr('زیادکردنی خواردن')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _langField(
                    ctrlKu,
                    context.tr('کوردی'),
                    context.tr('ناوی خواردن'),
                  ),
                  const SizedBox(height: 8),
                  _langField(ctrlAr, 'العربية', 'الاسم'),
                  const SizedBox(height: 8),
                  _langField(ctrlFa, 'فارسی', 'نام'),
                  const SizedBox(height: 8),
                  _langField(ctrlEn, 'English', 'Name'),
                  const SizedBox(height: 8),
                  _langField(ctrlTr, 'Türkçe', 'İsim'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [AmountInputFormatter()],
                    decoration: InputDecoration(
                      labelText: '${context.tr('نرخ')} (${context.tr('د.ع')})',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCat,
                    decoration: InputDecoration(
                      labelText: context.tr('بەش'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['name'] as String,
                            child: Text(c['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedCat = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedIcon,
                    decoration: InputDecoration(
                      labelText: context.tr('وێنە/ئایکۆن'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _iconOptions
                        .map(
                          (icon) => DropdownMenuItem(
                            value: icon,
                            child: Row(
                              children: [
                                Icon(MenuHelper.iconFromString(icon), size: 20),
                                const SizedBox(width: 8),
                                // Translated label, not the internal key: the
                                // dropdown used to print «lunch_dining» and
                                // «fastfood» straight at the admin.
                                Expanded(
                                  child: Text(
                                    MenuHelper.labelForIcon(icon, context.tr),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(
                      () => selectedIcon = v ?? _iconOptions.first,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('ڕەتکردنەوە')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.tr('زیادکردن')),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true &&
        ctrlKu.text.trim().isNotEmpty &&
        selectedCat != null) {
      final price = parseAmount(priceCtrl.text).toDouble();
      if (price > 0) {
        await ref
            .read(localDbProvider)
            .addFoodItem(
              ctrlKu.text.trim(),
              price,
              selectedCat!,
              imageUrl: selectedIcon,
              nameAr: ctrlAr.text.trim(),
              nameFa: ctrlFa.text.trim(),
              nameEn: ctrlEn.text.trim(),
              nameTr: ctrlTr.text.trim(),
            );
        await _loadMenu();
      }
    }
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    final ctrlKu = TextEditingController(text: item['name'] as String);
    final ctrlAr = TextEditingController(
      text: item['name_ar'] as String? ?? '',
    );
    final ctrlFa = TextEditingController(
      text: item['name_fa'] as String? ?? '',
    );
    final ctrlEn = TextEditingController(
      text: item['name_en'] as String? ?? '',
    );
    final ctrlTr = TextEditingController(
      text: item['name_tr'] as String? ?? '',
    );
    final priceCtrl = TextEditingController(
      text: money((item['price'] as num).toInt()),
    );
    String selectedCat = item['category'] as String;
    String selectedIcon = item['imageUrl'] as String? ?? _iconOptions.first;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => DialogControllerOwner(
        controllers: [ctrlKu, ctrlAr, ctrlFa, ctrlEn, ctrlTr, priceCtrl],
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(context.tr('گۆڕینی خواردن')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _langField(
                    ctrlKu,
                    context.tr('کوردی'),
                    context.tr('ناوی خواردن'),
                  ),
                  const SizedBox(height: 8),
                  _langField(ctrlAr, 'العربية', 'الاسم'),
                  const SizedBox(height: 8),
                  _langField(ctrlFa, 'فارسی', 'نام'),
                  const SizedBox(height: 8),
                  _langField(ctrlEn, 'English', 'Name'),
                  const SizedBox(height: 8),
                  _langField(ctrlTr, 'Türkçe', 'İsim'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [AmountInputFormatter()],
                    decoration: InputDecoration(
                      labelText: '${context.tr('نرخ')} (${context.tr('د.ع')})',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCat,
                    decoration: InputDecoration(
                      labelText: context.tr('بەش'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['name'] as String,
                            child: Text(c['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedCat = v ?? selectedCat),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedIcon,
                    decoration: InputDecoration(
                      labelText: context.tr('وێنە/ئایکۆن'),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _iconOptions
                        .map(
                          (icon) => DropdownMenuItem(
                            value: icon,
                            child: Row(
                              children: [
                                Icon(MenuHelper.iconFromString(icon), size: 20),
                                const SizedBox(width: 8),
                                // Translated label, not the internal key: the
                                // dropdown used to print «lunch_dining» and
                                // «fastfood» straight at the admin.
                                Expanded(
                                  child: Text(
                                    MenuHelper.labelForIcon(icon, context.tr),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedIcon = v ?? selectedIcon),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('ڕەتکردنەوە')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.tr('گۆڕین')),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true && ctrlKu.text.trim().isNotEmpty) {
      final price = parseAmount(priceCtrl.text).toDouble();
      if (price > 0) {
        await ref
            .read(localDbProvider)
            .updateFoodItem(
              item['id'] as int,
              ctrlKu.text.trim(),
              price,
              selectedCat,
              imageUrl: selectedIcon,
              nameAr: ctrlAr.text.trim(),
              nameFa: ctrlFa.text.trim(),
              nameEn: ctrlEn.text.trim(),
              nameTr: ctrlTr.text.trim(),
            );
        await _loadMenu();
      }
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('سڕینەوەی خواردن')),
        content: Text(
          context.trp('دڵنیایت دەتەوێت {name} بسڕیتەوە؟', {
            'name': item['name'] as String,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('ڕەتکردنەوە')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('سڕینەوە')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(localDbProvider).deleteFoodItem(item['id'] as int);
      await _loadMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.tr('بەڕێوەبردنی مێنیو'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _printerMode ? Icons.close : Icons.print_rounded,
              color: _printerMode ? AppColors.danger : AppColors.primary,
            ),
            tooltip: context.tr('شوێنی چاپ'),
            onPressed: _togglePrinterMode,
          ),
          if (!_printerMode) ...[
            IconButton(
              icon: const Icon(
                Icons.add_circle_rounded,
                color: AppColors.primary,
              ),
              tooltip: context.tr('زیادکردنی خواردن'),
              onPressed: _addItem,
            ),
            IconButton(
              icon: const Icon(Icons.folder_rounded, color: AppColors.primary),
              tooltip: context.tr('زیادکردنی بەش'),
              onPressed: _addCategory,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                // 600, the app-wide phone/tablet breakpoint (was 700, which
                // left 600-699 without the category sidebar that every
                // other tablet-size page shows).
                final isNarrow = constraints.maxWidth < 600;
                return Row(
                  children: [
                    // ======= ITEMS PANEL (LEFT) =======
                    Expanded(
                      flex: 3,
                      child: _selectedCategory == null
                          ? Center(
                              child: Text(
                                context.tr('بەشێک هەڵبژێرە'),
                                style: TextStyle(color: AppColors.softText),
                              ),
                            )
                          : Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  color: Colors.white,
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _selectedCategory!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        ' (${_items.where((i) => i['category'] == _selectedCategory).length})',
                                        style: const TextStyle(
                                          color: AppColors.softText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child:
                                      _items
                                          .where(
                                            (i) =>
                                                i['category'] ==
                                                _selectedCategory,
                                          )
                                          .isEmpty
                                      ? Center(
                                          child: Text(
                                            context.tr('هیچ خواردنێک نییە'),
                                            style: TextStyle(
                                              color: AppColors.softText,
                                            ),
                                          ),
                                        )
                                      : ResponsiveGridView(
                                          desktopColumns: 4,
                                          tabletColumns: 3,
                                          mobileColumns: 2,
                                          spacing: 12,
                                          runSpacing: 12,
                                          childAspectRatio: 0.85,
                                          itemCount: _items
                                              .where(
                                                (i) =>
                                                    i['category'] ==
                                                    _selectedCategory,
                                              )
                                              .length,
                                          itemBuilder: (context, index) {
                                            final item = _items
                                                .where(
                                                  (i) =>
                                                      i['category'] ==
                                                      _selectedCategory,
                                                )
                                                .toList()[index];
                                            final itemName =
                                                item['name'] as String;
                                            final iconStr =
                                                item['imageUrl'] as String? ??
                                                'fastfood';
                                            final isSelected = _selectedItems
                                                .contains(itemName);
                                            final printerTypes =
                                                _printerAssignments[itemName] ??
                                                [];
                                            return GestureDetector(
                                              onTap: _printerMode
                                                  ? () => setState(() {
                                                      if (isSelected) {
                                                        _selectedItems.remove(
                                                          itemName,
                                                        );
                                                      } else {
                                                        _selectedItems.add(
                                                          itemName,
                                                        );
                                                      }
                                                    })
                                                  : null,
                                              onLongPress: _printerMode
                                                  ? () =>
                                                        _showItemPrinterDialog(
                                                          itemName,
                                                        )
                                                  : null,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  border:
                                                      _printerMode && isSelected
                                                      ? Border.all(
                                                          color:
                                                              AppColors.primary,
                                                          width: 2.5,
                                                        )
                                                      : null,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.04,
                                                          ),
                                                      blurRadius: 10,
                                                      offset: const Offset(
                                                        0,
                                                        4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: Column(
                                                  children: [
                                                    Expanded(
                                                      child: Container(
                                                        margin:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: AppColors
                                                              .background,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                        ),
                                                        child: Center(
                                                          child: Stack(
                                                            alignment: Alignment
                                                                .bottomRight,
                                                            children: [
                                                              Icon(
                                                                MenuHelper.iconFromString(
                                                                  iconStr,
                                                                ),
                                                                size: 38,
                                                                color: AppColors
                                                                    .primary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.6,
                                                                    ),
                                                              ),
                                                              if (_printerMode &&
                                                                  printerTypes
                                                                      .isNotEmpty)
                                                                Padding(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        4,
                                                                      ),
                                                                  child: Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: printerTypes
                                                                        .map(
                                                                          (
                                                                            t,
                                                                          ) => Container(
                                                                            width:
                                                                                8,
                                                                            height:
                                                                                8,
                                                                            margin: const EdgeInsets.only(
                                                                              left: 2,
                                                                            ),
                                                                            decoration: BoxDecoration(
                                                                              color: _printerDotColor(
                                                                                t,
                                                                              ),
                                                                              shape: BoxShape.circle,
                                                                            ),
                                                                          ),
                                                                        )
                                                                        .toList(),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                          ),
                                                      child: Text(
                                                        _localItemName(item),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 12,
                                                          color: AppColors
                                                              .darkText,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        '${context.tr('د.ع')} ${money((item['price'] as num))}',
                                                        style: const TextStyle(
                                                          color:
                                                              AppColors.primary,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    if (!_printerMode)
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          _smallButton(
                                                            Icons.edit_rounded,
                                                            AppColors.primary,
                                                            () =>
                                                                _editItem(item),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          _smallButton(
                                                            Icons
                                                                .delete_outline_rounded,
                                                            AppColors.danger,
                                                            () => _deleteItem(
                                                              item,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    if (!_printerMode)
                                                      const SizedBox(height: 8),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                if (_printerMode) _buildPrinterBottomPanel(),
                              ],
                            ),
                    ),
                    // ======= CATEGORIES SIDEBAR (RIGHT) =======
                    if (!isNarrow)
                      Container(
                        // Up to 280 on a wide screen: the old 220 cap left the
                        // sidebar looking like a narrow strip at 1920 while the
                        // items panel beside it ran to ~1500px.
                        width: (constraints.maxWidth * 0.22).clamp(160, 280),
                        color: Colors.white,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: AppColors.borderSide,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.folder_rounded,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.tr('بەشەکان'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _categories.isEmpty
                                  ? Center(
                                      child: Text(
                                        context.tr('هیچ بەشێک نییە'),
                                        style: TextStyle(
                                          color: AppColors.softText,
                                        ),
                                      ),
                                    )
                                  : ListView(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      children: _buildCategorySections(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  List<Widget> _buildCategorySections() {
    final sections = <String>[];
    final uncategorized = <Map<String, dynamic>>[];
    for (final cat in _categories) {
      final section = cat['section'] as String? ?? '';
      if (section.isEmpty) {
        uncategorized.add(cat);
      } else if (!sections.contains(section)) {
        sections.add(section);
      }
    }

    final widgets = <Widget>[];
    for (final section in sections) {
      final cats = _categories
          .where((c) => (c['section'] as String? ?? '') == section)
          .toList();
      widgets.add(_buildSectionHeader(section));
      for (final cat in cats) {
        widgets.add(_buildCategoryTile(cat));
      }
    }
    if (uncategorized.isNotEmpty) {
      if (sections.isNotEmpty) widgets.add(const SizedBox(height: 4));
      for (final cat in uncategorized) {
        widgets.add(_buildCategoryTile(cat));
      }
    }
    return widgets;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.darkText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> cat) {
    final itemCount = _items.where((i) => i['category'] == cat['name']).length;
    final isSelected = _selectedCategory == cat['name'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selectedCategory = cat['name'] as String),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.08)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                MenuHelper.iconFromString(cat['icon'] as String),
                size: 18,
                color: isSelected ? AppColors.primary : AppColors.softText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cat['name'] as String,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? AppColors.primary : AppColors.darkText,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '$itemCount',
                style: TextStyle(color: AppColors.softText, fontSize: 11),
              ),
              const SizedBox(width: 2),
              // The edit/delete pair used to be bare 14px icons with 2px of
              // padding - an 18px target. A 32x40 constrained box keeps the
              // dense sidebar layout but gives a thumb something to hit.
              InkWell(
                onTap: () => _editCategory(cat),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 40,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.edit_rounded,
                      size: 15,
                      color: AppColors.softText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              InkWell(
                onTap: () => _deleteCategory(cat),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 40,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localItemName(Map<String, dynamic> item) {
    return FoodLocalization.localizedName(
      item,
      AppState.of(context).currentLanguage,
    );
  }

  Widget _langField(TextEditingController ctrl, String langLabel, String hint) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            langLabel,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.darkText,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
