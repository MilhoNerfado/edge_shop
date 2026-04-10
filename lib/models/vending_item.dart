import 'package:flutter/material.dart';

class VendingItem {
  final String slot;
  final int giftIndex;
  final double price;
  final int gpioChannel;
  final Color color;
  final IconData icon;

  const VendingItem({
    required this.slot,
    required this.giftIndex,
    required this.price,
    required this.gpioChannel,
    required this.color,
    required this.icon,
  });
}

const List<VendingItem> vendingItems = [
  VendingItem(
    slot: 'A1',
    giftIndex: 1,
    price: 1.50,
    gpioChannel: 0,
    color: Color(0xFFE53935),
    icon: Icons.card_giftcard,
  ),
  VendingItem(
    slot: 'A2',
    giftIndex: 2,
    price: 1.00,
    gpioChannel: 1,
    color: Color(0xFF1E88E5),
    icon: Icons.card_giftcard,
  ),
  VendingItem(
    slot: 'B1',
    giftIndex: 3,
    price: 2.00,
    gpioChannel: 2,
    color: Color(0xFFFB8C00),
    icon: Icons.card_giftcard,
  ),
];

