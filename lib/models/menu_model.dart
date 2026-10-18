class FoodCategory {
  final int id;
  final String name;
  final String icon;
  final int sortOrder;

  const FoodCategory({
    this.id = 0,
    required this.name,
    this.icon = 'restaurant',
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'icon': icon,
    'sortOrder': sortOrder,
  };

  factory FoodCategory.fromMap(Map<String, dynamic> map) => FoodCategory(
    id: map['id'] as int,
    name: map['name'] as String,
    icon: map['icon'] as String? ?? 'restaurant',
    sortOrder: map['sortOrder'] as int? ?? 0,
  );
}

class FoodItem {
  final int id;
  final String name;
  final double price;
  final String category;
  final int sortOrder;

  const FoodItem({
    this.id = 0,
    required this.name,
    required this.price,
    required this.category,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'price': price,
    'category': category,
    'sortOrder': sortOrder,
  };

  factory FoodItem.fromMap(Map<String, dynamic> map) => FoodItem(
    id: map['id'] as int,
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    category: map['category'] as String,
    sortOrder: map['sortOrder'] as int? ?? 0,
  );
}
