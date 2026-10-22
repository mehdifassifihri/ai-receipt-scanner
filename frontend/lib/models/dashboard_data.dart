import 'package:flutter/material.dart';

class SpendingCategory {
  const SpendingCategory(this.name, this.percent, this.color);
  final String name;
  final int percent;
  final Color color;
}

const spendingCategories = [
  SpendingCategory('Food', 40, Color(0xFF75945D)),
  SpendingCategory('Shopping', 25, Color(0xFFB7A4DC)),
  SpendingCategory('Transport', 20, Color(0xFFD7ED9B)),
  SpendingCategory('Others', 15, Color(0xFFF0C9A7)),
];

class Expense {
  const Expense(
    this.merchant,
    this.category,
    this.date,
    this.amount,
    this.icon,
    this.color,
  );
  final String merchant;
  final String category;
  final String date;
  final String amount;
  final IconData icon;
  final Color color;
}

const recentExpenses = [
  Expense(
    'Whole Foods Market',
    'Food',
    'Today, Oct 18',
    '86.42',
    Icons.shopping_basket_outlined,
    Color(0xFFEAF0DF),
  ),
  Expense(
    'Nike Store',
    'Shopping',
    'Yesterday, Oct 17',
    '129.00',
    Icons.shopping_bag_outlined,
    Color(0xFFEEE9F7),
  ),
  Expense(
    'Uber',
    'Transport',
    'Oct 16, 2026',
    '24.80',
    Icons.directions_car_outlined,
    Color(0xFFE9EDE8),
  ),
  Expense(
    'Blue Bottle Coffee',
    'Food',
    'Oct 15, 2026',
    '12.50',
    Icons.local_cafe_outlined,
    Color(0xFFF8ECDF),
  ),
];
