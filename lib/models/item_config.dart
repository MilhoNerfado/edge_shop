import 'package:flutter/material.dart';

enum IconType { defaultIcon, material, image }

const curatedItemIcons = [
  Icons.card_giftcard,
  Icons.fastfood,
  Icons.local_drink,
  Icons.coffee,
  Icons.icecream,
  Icons.cake,
  Icons.cookie,
  Icons.lunch_dining,
  Icons.local_pizza,
  Icons.ramen_dining,
  Icons.set_meal,
  Icons.wine_bar,
  Icons.sports_esports,
  Icons.toys,
  Icons.checkroom,
  Icons.face,
  Icons.spa,
  Icons.self_improvement,
  Icons.shopping_bag,
  Icons.redeem,
];

final curatedItemIconsByCodePoint = {
  for (final icon in curatedItemIcons) icon.codePoint: icon,
};

IconData resolveCuratedItemIcon(int? codePoint) {
  return curatedItemIconsByCodePoint[codePoint] ?? Icons.card_giftcard;
}

class ItemConfig {
  final String? customName;
  final IconType iconType;
  final int? materialIconCode;
  final String? imagePath;
  final String? description;

  const ItemConfig({
    this.customName,
    this.iconType = IconType.defaultIcon,
    this.materialIconCode,
    this.imagePath,
    this.description,
  });

  static const ItemConfig defaults = ItemConfig();
}
