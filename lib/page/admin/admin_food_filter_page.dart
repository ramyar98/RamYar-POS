import 'package:ramyar_pos/core/fmt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/app.dart';
import '../../core/responsive.dart';
import '../../services/app_localizations.dart';
import '../../services/menu_helper.dart';
import '../../services/food_localization.dart';
import '../../database/local_db.dart';
import '../../models/printer_model.dart';

class AdminFoodFilterPage extends ConsumerStatefulWidget {
  const AdminFoodFilterPage({super.key});

  @override
  ConsumerState<AdminFoodFilterPage> createState() =>
      _AdminFoodFilterPageState();
}

class _AdminFoodFilterPageState extends ConsumerState<AdminFoodFilterPage> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _items = [];
  Map<String, List<PrinterType>> _assignments = {};
  String? _selectedCategory;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(localDbProvider);
    _categories = await db.getFoodCategories();
    _items = await db.getFoodItems();
    _assignments = await db.getAllItemPrinterAssignments();
    if (_categories.isNotEmpty && _selectedCategory == null) {
      _selectedCategory = _categories.first['name'] as String;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showPrinterDialog(String itemName) async {
    final current = List<PrinterType>.from(_assignments[itemName] ?? []);
    final checkState = {
      PrinterType.bar: current.contains(PrinterType.bar),
      PrinterType.kitchen: current.contains(PrinterType.kitchen),
      PrinterType.hookah: current.contains(PrinterType.hookah),
      PrinterType.cashier: current.contains(PrinterType.cashier),
    };
    final result = await showDialog<Map<PrinterType, bool>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.tr('شوێنی چاپ')),
          content: Column(
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
                          color: _dotColor(type),
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
              Text(
                context.tr('بە هیچ پرێنتێک پەیوەست نەبێت بۆ مەتبەخ دەچێت'),
                style: TextStyle(color: AppColors.softText, fontSize: 11),
              ),
            ],
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
      if (!mounted) return;
      setState(() => _assignments = assignments);
    }
  }

  Color _dotColor(PrinterType type) {
    switch (type) {
      case PrinterType.kitchen:
        return const Color(0xFFE53935);
      case PrinterType.bar:
        return const Color(0xFF2D7DFF);
      case PrinterType.hookah:
        return const Color(0xFF7B1FA2);
      case PrinterType.cashier:
        return const Color(0xFF159A55);
    }
  }

  String _printerLabel(PrinterType type) {
    switch (type) {
      case PrinterType.kitchen:
        return context.tr('مەتبەخ');
      case PrinterType.bar:
        return context.tr('باڕ');
      case PrinterType.hookah:
        return context.tr('نێرگیلە');
      case PrinterType.cashier:
        return context.tr('کاشێر');
    }
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

  Widget _buildItemsGrid(int index) {
    final item = _items
        .where((i) => i['category'] == _selectedCategory)
        .toList()[index];
    final itemName = item['name'] as String;
    final iconStr = item['imageUrl'] as String? ?? 'fastfood';
    final types = _assignments[itemName] ?? [];
    return GestureDetector(
      onTap: () => _showPrinterDialog(itemName),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: types.isNotEmpty
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Icon(
                        MenuHelper.iconFromString(iconStr),
                        size: 38,
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                      if (types.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: types
                                .map(
                                  (t) => Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(left: 2),
                                    decoration: BoxDecoration(
                                      color: _dotColor(t),
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                FoodLocalization.localizedName(
                  item,
                  AppState.of(context).currentLanguage,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.darkText,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${context.tr('د.ع')} ${money((item['price'] as num))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (types.isEmpty)
              Text(
                context.tr('هیچ پرێنتێک'),
                style: TextStyle(color: AppColors.softText, fontSize: 10),
              ),
            if (types.isNotEmpty)
              Text(
                types.map((t) => _printerLabel(t)).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _dotColor(types.first),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
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
                  FoodLocalization.localizedName(
                    cat,
                    AppState.of(context).currentLanguage,
                  ),
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
            ],
          ),
        ),
      ),
    );
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
          context.tr('فلتەری خواردن بەپێی چاپکەر'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: context.tr('تازەکردنەوە'),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final isPhone = Responsive.isPhone(context);
                final itemsSection = _selectedCategory == null
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
                                  style: TextStyle(
                                    color: AppColors.softText,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Flexible(
                                  child: Text(
                                    context.tr('کلیک بکە بۆ شوێنی چاپ'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isPhone)
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(10),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 0.8,
                                  ),
                              itemCount: _items
                                  .where(
                                    (i) => i['category'] == _selectedCategory,
                                  )
                                  .length,
                              itemBuilder: (context, index) =>
                                  _buildItemsGrid(index),
                            )
                          else
                            Expanded(
                              child: GridView.builder(
                                padding: const EdgeInsets.all(10),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.85,
                                    ),
                                itemCount: _items
                                    .where(
                                      (i) => i['category'] == _selectedCategory,
                                    )
                                    .length,
                                itemBuilder: (context, index) =>
                                    _buildItemsGrid(index),
                              ),
                            ),
                        ],
                      );
                final sidebarSection = Container(
                  width: isPhone ? double.infinity : 220,
                  color: Colors.white,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.borderSide),
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
                      if (isPhone)
                        _categories.isEmpty
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Center(
                                  child: Text(
                                    context.tr('هیچ بەشێک نییە'),
                                    style: TextStyle(color: AppColors.softText),
                                  ),
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                children: _buildCategorySections(),
                              )
                      else
                        Expanded(
                          child: _categories.isEmpty
                              ? Center(
                                  child: Text(
                                    context.tr('هیچ بەشێک نییە'),
                                    style: TextStyle(color: AppColors.softText),
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
                );
                if (isPhone) {
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        itemsSection,
                        const SizedBox(height: 8),
                        sidebarSection,
                      ],
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: itemsSection),
                    sidebarSection,
                  ],
                );
              },
            ),
    );
  }
}
