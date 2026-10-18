import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/colors.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../services/app_localizations.dart';
import '../../models/printer_model.dart';
import '../../providers/printer_provider.dart';
import '../../services/printer_discovery_service.dart';
import '../../database/local_db.dart';

class AdminPrinterScreen extends ConsumerStatefulWidget {
  const AdminPrinterScreen({super.key});

  @override
  ConsumerState<AdminPrinterScreen> createState() => _AdminPrinterScreenState();
}

class _AdminPrinterScreenState extends ConsumerState<AdminPrinterScreen> {
  bool _isScanning = false;
  List<DiscoveredPrinter> _discovered = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(printerProvider.notifier).load());
  }

  Future<void> _scanPrinters() async {
    setState(() => _isScanning = true);
    final printers = await PrinterDiscoveryService.discoverPrinters();
    if (!mounted) return;
    setState(() {
      _discovered = printers;
      _isScanning = false;
    });
  }

  void _assignPrinter(DiscoveredPrinter discovered, PrinterType type) {
    final existing = ref.read(printerProvider).printers.where((p) => p.printerType == type).toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('دەستنیشانکردنی چاپکەر')),
        content: Text(context.trp('چاپکەری {printer} بکە بە {type}؟', {
          'printer': discovered.name,
          'type': _typeName(type),
        })),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('ڕەتکردنەوە'))),
          FilledButton(onPressed: () async {
            if (existing.isNotEmpty) {
              await ref.read(printerProvider.notifier).deletePrinter(existing.first.id);
            }
            await ref.read(printerProvider.notifier).addPrinter(PrinterConfig(
              name: discovered.name,
              portName: discovered.portName,
              printerType: type,
              isDefault: true,
            ));
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
          }, child: Text(context.tr('دەستنیشانکردن'))),
        ],
      ),
    );
  }

  void _removePrinter(PrinterConfig config) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('لابردنی چاپکەر')),
        content: Text(context.trp('دڵنیایت دەتەوێت {printer} لابەریت؟', {'printer': config.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('ڕەتکردنەوە'))),
          FilledButton(onPressed: () {
            ref.read(printerProvider.notifier).deletePrinter(config.id);
            Navigator.pop(ctx);
          }, child: Text(context.tr('لابردن'))),
        ],
      ),
    );
  }

  Future<void> _showCategoryMapping() async {
    final existing = ref.read(printerProvider);
    final categories = await _getAllCategories();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('نەخشەکێشانی پۆل بۆ چاپکەر')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SizedBox(
            width: 500,
            child: ListView(
              shrinkWrap: true,
              children: categories.map((category) {
                final currentMapping = existing.categoryMappings[category];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(child: Text(category, style: const TextStyle(fontWeight: FontWeight.bold))),
                        const SizedBox(width: 12),
                        DropdownButton<int?>(
                          value: existing.printers.indexWhere((p) => p.printerType == currentMapping) < 0
                              ? null
                              : existing.printers.indexWhere((p) => p.printerType == currentMapping),
                          items: [
                            DropdownMenuItem(value: null, child: Text(context.tr('چاپکەر هەڵبژێرە'))),
                            ...existing.printers.asMap().entries.map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text('${_typeName(e.value.printerType)} (${e.value.name})'),
                            )),
                          ],
                          onChanged: (index) {
                            if (index != null && index >= 0 && index < existing.printers.length) {
                              ref.read(printerProvider.notifier).setCategoryMapping(
                                category,
                                existing.printers[index].id,
                              );
                              setDialogState(() {});
                            } else if (index == null) {
                              ref.read(printerProvider.notifier).removeCategoryMapping(category);
                              setDialogState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('داخستن'))),
          ],
        ),
      ),
    );
  }

  Future<void> _showItemOverrides() async {
    final existing = ref.read(printerProvider);
    final allItems = await _getAllMenuItems();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('نەخشەکێشانی خواردن بۆ چاپکەر')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SizedBox(
            width: 500,
            child: ListView(
              shrinkWrap: true,
              children: allItems.map((item) {
                final currentOverride = existing.itemOverrides[item.name];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(item.category, style: TextStyle(color: AppColors.softText, fontSize: 11)),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: DropdownButton<int?>(
                            value: currentOverride == null ||
                                    existing.printers.indexWhere((p) => p.printerType == currentOverride) < 0
                                ? null
                                : existing.printers.indexWhere((p) => p.printerType == currentOverride),
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(value: null, child: Text(context.tr('بەپێی پۆل'))),
                              ...existing.printers.asMap().entries.map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(_typeName(e.value.printerType), style: const TextStyle(fontSize: 13)),
                              )),
                            ],
                            onChanged: (index) {
                              if (index != null && index >= 0 && index < existing.printers.length) {
                                ref.read(printerProvider.notifier).setItemOverride(
                                  item.name,
                                  existing.printers[index].id,
                                );
                              } else {
                                ref.read(printerProvider.notifier).removeItemOverride(item.name);
                              }
                              setDialogState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('داخستن'))),
          ],
        ),
      ),
    );
  }

  Future<List<String>> _getAllCategories() async {
    final db = ref.read(localDbProvider);
    final cats = await db.getFoodCategories();
    return cats.map((c) => c['name'] as String).toList();
  }

  Future<List<_MenuItemInfo>> _getAllMenuItems() async {
    final db = ref.read(localDbProvider);
    final items = await db.getFoodItems();
    return items.map((i) => _MenuItemInfo(i['name'] as String, i['category'] as String)).toList();
  }

  String _typeName(PrinterType type) {
    switch (type) {
      case PrinterType.kitchen: return context.tr('چاپکەری چێشتخانە');
      case PrinterType.bar: return context.tr('چاپکەری بار');
      case PrinterType.hookah: return context.tr('چاپکەری قەلیان');
      case PrinterType.cashier: return context.tr('چاپکەری کاشێر');
    }
  }

  IconData _typeIcon(PrinterType type) {
    switch (type) {
      case PrinterType.kitchen: return Icons.restaurant_rounded;
      case PrinterType.bar: return Icons.local_bar_rounded;
      case PrinterType.hookah: return Icons.smoking_rooms_rounded;
      case PrinterType.cashier: return Icons.receipt_long_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final printerState = ref.watch(printerProvider);
    final isPhone = Responsive.isPhone(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(context.tr('ڕێکخستنی چاپکەر'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: isPhone
            ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildScannerCard(),
                    const SizedBox(height: 16),
                    _buildPrinterList(printerState, isPhone: true),
                    const SizedBox(height: 16),
                    _buildAssignPanel(printerState, isPhone: true),
                  ],
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _buildScannerCard(),
                        const SizedBox(height: 16),
                        Expanded(child: _buildPrinterList(printerState)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _buildAssignPanel(printerState),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildScannerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15)],
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_find_rounded, color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('چاپکەرەکان دەستنیشان بکە'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
                Text('${_discovered.length} ${context.tr('چاپکەر دۆزراوەتەوە')}',
                    style: TextStyle(color: AppColors.softText, fontSize: 13)),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _isScanning ? null : _scanPrinters,
            icon: _isScanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search_rounded),
            label: Text(context.tr('گەڕان')),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterList(PrinterProviderState state, {bool isPhone = false}) {
    if (state.printers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.print_disabled_rounded, size: 48, color: AppColors.softText.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(context.tr('هیچ چاپکەرێک ڕێکنەخراوە'), style: TextStyle(color: AppColors.softText)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        shrinkWrap: isPhone,
        physics: isPhone ? const NeverScrollableScrollPhysics() : null,
        itemCount: state.printers.length,
        itemBuilder: (context, index) {
          final printer = state.printers[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: Icon(_typeIcon(printer.printerType), color: AppColors.primary),
              title: Text(printer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${_typeName(printer.printerType)} • ${printer.portName}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                onPressed: () => _removePrinter(printer),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAssignPanel(PrinterProviderState state, {bool isPhone = false}) {
    final assignedTypes = state.printers.map((p) => p.printerType).toSet();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(context.tr('ڕێکخستنی چاپکەرەکان'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText)),
              ),
            ],
          ),
          const Divider(height: 24),
          if (isPhone)
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: _assignSections(assignedTypes, state),
            )
          else
            Expanded(
              child: ListView(
                children: _assignSections(assignedTypes, state),
              ),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showCategoryMapping,
                  icon: const Icon(Icons.category_rounded),
                  label: Text(context.tr('نەخشەکێشانی پۆل')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showItemOverrides,
                  icon: const Icon(Icons.food_bank_rounded),
                  label: Text(context.tr('نەخشەکێشانی خواردن')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _assignSections(Set<PrinterType> assignedTypes, PrinterProviderState state) {
    return [
      _assignSection(PrinterType.kitchen, Icons.restaurant_rounded, assignedTypes, state),
      _assignSection(PrinterType.bar, Icons.local_bar_rounded, assignedTypes, state),
      _assignSection(PrinterType.hookah, Icons.smoking_rooms_rounded, assignedTypes, state),
      _assignSection(PrinterType.cashier, Icons.receipt_long_rounded, assignedTypes, state),
    ];
  }

  Widget _assignSection(PrinterType type, IconData icon, Set<PrinterType> assigned, PrinterProviderState state) {
    final currentPrinter = state.printers.where((p) => p.printerType == type).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeName(type), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
                Text(currentPrinter?.name ?? context.tr('هەڵنەبژێردراوە'),
                    style: TextStyle(fontSize: 12, color: currentPrinter != null ? AppColors.success : AppColors.softText)),
              ],
            ),
          ),
          if (_discovered.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (name) {
                final printer = _discovered.where((d) => d.name == name).firstOrNull;
                if (printer != null) _assignPrinter(printer, type);
              },
              itemBuilder: (_) => _discovered.map((d) => PopupMenuItem(
                value: d.name,
                child: Text(d.name, style: const TextStyle(fontSize: 13)),
              )).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.tr('دەستنیشانکردن'), style: TextStyle(fontSize: 11, color: AppColors.primary)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppColors.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuItemInfo {
  final String name;
  final String category;
  const _MenuItemInfo(this.name, this.category);
}
