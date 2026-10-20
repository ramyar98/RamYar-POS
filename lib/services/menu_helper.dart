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

  /// A human-readable label for an icon key.
  ///
  /// The admin's icon dropdown used to render the raw key (`lunch_dining`,
  /// `fastfood`, ...) as the visible text. Where the app already has a word for
  /// the icon in all six languages we use it; otherwise the key is turned into
  /// words («lunch_dining» -> «lunch dining») so at least no identifier leaks
  /// into the UI.
  static String labelForIcon(String name, String Function(String) tr) {
    switch (name) {
      case 'grid_view_rounded':
        return tr('هەموو');
      case 'lunch_dining':
      case 'restaurant':
      case 'set_meal':
      case 'tapas':
        return tr('خواردن');
      case 'local_pizza':
      case 'fastfood':
        return tr('فاست فوود');
      case 'kebab_dining':
        return tr('برژاو');
      case 'rice_bowl':
        return tr('برنج');
      case 'cake':
      case 'bakery_dining':
        return tr('کێک');
      case 'local_drink':
      case 'water_drop':
        return tr('خواردنەوە');
      case 'soup_kitchen':
      case 'ramen_dining':
        return tr('شۆربە');
      case 'icecream':
        return tr('ئایسکریم');
      case 'coffee':
        return tr('قاوە');
      case 'egg':
        return tr('هێلکە');
      case 'eco':
        return tr('سەوزە');
      default:
        return name.replaceAll('_', ' ');
    }
  }
}
