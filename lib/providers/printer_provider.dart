import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/local_db.dart';
import '../models/printer_model.dart';

class PrinterProviderState {
  final List<PrinterConfig> printers;
  final Map<String, PrinterType> categoryMappings;
  final Map<String, PrinterType> itemOverrides;
  final Map<String, List<PrinterType>> itemPrinterAssignments;

  const PrinterProviderState({
    this.printers = const [],
    this.categoryMappings = const {},
    this.itemOverrides = const {},
    this.itemPrinterAssignments = const {},
  });
}

class PrinterNotifier extends StateNotifier<PrinterProviderState> {
  final LocalDatabase _db;

  PrinterNotifier(this._db) : super(const PrinterProviderState());

  Future<void> load() async {
    final printers = await _db.getAllPrinters();
    final categoryMappings = await _db.getCategoryPrinterMappings();
    final itemOverrides = await _db.getItemPrinterOverrides();
    final itemPrinterAssignments = await _db.getAllItemPrinterAssignments();

    state = PrinterProviderState(
      printers: printers,
      categoryMappings: categoryMappings,
      itemOverrides: itemOverrides,
      itemPrinterAssignments: itemPrinterAssignments,
    );
  }

  Future<void> addPrinter(PrinterConfig config) async {
    await _db.addPrinter(config);
    await load();
  }

  Future<void> updatePrinter(PrinterConfig config) async {
    await _db.updatePrinter(config);
    await load();
  }

  Future<void> deletePrinter(int id) async {
    await _db.deletePrinter(id);
    await load();
  }

  Future<void> setCategoryMapping(String category, int printerConfigId) async {
    await _db.setCategoryPrinterMapping(category, printerConfigId);
    await load();
  }

  Future<void> removeCategoryMapping(String category) async {
    await _db.removeCategoryPrinterMapping(category);
    await load();
  }

  Future<void> setItemOverride(String itemName, int printerConfigId) async {
    await _db.setItemPrinterOverride(itemName, printerConfigId);
    await load();
  }

  Future<void> removeItemOverride(String itemName) async {
    await _db.removeItemPrinterOverride(itemName);
    await load();
  }

  Future<void> setItemPrinterAssignments(String itemName, List<PrinterType> types) async {
    await _db.setItemPrinterAssignments(itemName, types);
    await load();
  }
}

final printerProvider = StateNotifierProvider<PrinterNotifier, PrinterProviderState>((ref) {
  final db = ref.read(localDbProvider);
  return PrinterNotifier(db);
});
