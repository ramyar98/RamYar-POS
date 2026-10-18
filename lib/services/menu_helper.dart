import 'package:flutter/material.dart';

class MenuHelper {
  static IconData iconFromString(String name) {
    switch (name) {
      case 'grid_view_rounded': return Icons.grid_view_rounded;
      case 'lunch_dining': return Icons.lunch_dining;
      case 'local_pizza': return Icons.local_pizza;
      case 'set_meal': return Icons.set_meal;
      case 'rice_bowl': return Icons.rice_bowl;
      case 'kebab_dining': return Icons.kebab_dining;
      case 'cake': return Icons.cake;
      case 'local_drink': return Icons.local_drink;
      case 'soup_kitchen': return Icons.soup_kitchen;
      case 'eco': return Icons.eco;
      case 'restaurant': return Icons.restaurant;
      case 'fastfood': return Icons.fastfood;
      case 'egg': return Icons.egg;
      case 'bakery_dining': return Icons.bakery_dining;
      case 'ramen_dining': return Icons.ramen_dining;
      case 'tapas': return Icons.tapas;
      case 'icecream': return Icons.icecream;
      case 'coffee': return Icons.coffee;
      case 'water_drop': return Icons.water_drop;
      default: return Icons.restaurant;
    }
  }
}
