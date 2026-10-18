enum PrinterType { kitchen, bar, hookah, cashier }

class PrinterConfig {
  final int id;
  final String name;
  final String portName;
  final PrinterType printerType;
  final bool isDefault;

  const PrinterConfig({
    this.id = 0,
    required this.name,
    required this.portName,
    required this.printerType,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'portName': portName,
    'printerType': printerType.index,
    'isDefault': isDefault ? 1 : 0,
  };

  factory PrinterConfig.fromMap(Map<String, dynamic> map) => PrinterConfig(
    id: map['id'] as int,
    name: map['name'] as String,
    portName: map['portName'] as String,
    printerType: PrinterType.values[map['printerType'] as int],
    isDefault: map['isDefault'] == 1,
  );

  PrinterConfig copyWith({
    int? id,
    String? name,
    String? portName,
    PrinterType? printerType,
    bool? isDefault,
  }) => PrinterConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    portName: portName ?? this.portName,
    printerType: printerType ?? this.printerType,
    isDefault: isDefault ?? this.isDefault,
  );
}

class CategoryPrinterMapping {
  final String category;
  final int printerConfigId;

  const CategoryPrinterMapping({
    required this.category,
    required this.printerConfigId,
  });

  Map<String, dynamic> toMap() => {
    'category': category,
    'printerConfigId': printerConfigId,
  };

  factory CategoryPrinterMapping.fromMap(Map<String, dynamic> map) => CategoryPrinterMapping(
    category: map['category'] as String,
    printerConfigId: map['printerConfigId'] as int,
  );
}

class ItemPrinterOverride {
  final String itemName;
  final int printerConfigId;

  const ItemPrinterOverride({
    required this.itemName,
    required this.printerConfigId,
  });

  Map<String, dynamic> toMap() => {
    'itemName': itemName,
    'printerConfigId': printerConfigId,
  };

  factory ItemPrinterOverride.fromMap(Map<String, dynamic> map) => ItemPrinterOverride(
    itemName: map['itemName'] as String,
    printerConfigId: map['printerConfigId'] as int,
  );
}

class DiscoveredPrinter {
  final String name;
  final String portName;

  const DiscoveredPrinter({required this.name, required this.portName});
}

class PrintJob {
  final List<PrintJobItem> items;
  final PrinterType printerType;
  final String printerName;
  final String printerPort;

  const PrintJob({
    required this.items,
    required this.printerType,
    required this.printerName,
    required this.printerPort,
  });
}

class PrintJobItem {
  final String name;
  final int quantity;
  final String category;
  final String notes;
  final String waiterName;
  final int tableNumber;

  /// What the ticket should call this order, when the number on its own is not
  /// something anybody in the kitchen can use.
  ///
  /// A delivery slot's number is derived from its company, so printing
  /// "مێز: 100104" tells the kitchen nothing. When this is set it is printed
  /// instead - "تەلەبات 4". Empty for real tables, which keeps their numbers.
  final String tableLabel;

  final double price;

  const PrintJobItem({
    required this.name,
    required this.quantity,
    this.category = '',
    this.notes = '',
    this.waiterName = '',
    this.tableNumber = 0,
    this.tableLabel = '',
    this.price = 0.0,
  });
}
