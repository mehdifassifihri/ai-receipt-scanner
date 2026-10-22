import 'receipt_details.dart';

/// Development samples live in their own store; never inserted into user data.
List<SavedReceiptExpense> createDemoExpenses(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final samples = [
    ('Starbucks', 'Food & Drinks', 2450, 'USD', today),
    ('Uber', 'Transport', 1800, 'USD', today),
    (
      'Amazon',
      'Shopping',
      8999,
      'USD',
      today.subtract(const Duration(days: 1)),
    ),
    (
      'Carrefour',
      'Groceries',
      4580,
      'EUR',
      today.subtract(const Duration(days: 3)),
    ),
    (
      'City Pharmacy',
      'Health',
      6500,
      'MAD',
      today.subtract(const Duration(days: 5)),
    ),
    (
      'Electric Company',
      'Utilities',
      7200,
      'USD',
      DateTime(now.year, now.month - 1, 12),
    ),
  ];
  return [
    for (final item in samples)
      SavedReceiptExpense(
        details: ReceiptDetails(
          merchant: item.$1,
          category: item.$2,
          amountInCents: item.$3,
          currency: item.$4,
          date: item.$5,
        ),
      ),
  ];
}
