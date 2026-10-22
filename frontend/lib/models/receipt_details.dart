import 'receipt_selection.dart';

const receiptCurrencies = ['USD', 'EUR', 'MAD', 'CAD', 'GBP'];
const receiptCategories = [
  'Food & Drinks',
  'Shopping',
  'Transport',
  'Groceries',
  'Health',
  'Entertainment',
  'Utilities',
  'Other',
];

/// Demo values for isolated previews and tests. Connected scans use server drafts.
class ReceiptDetails {
  const ReceiptDetails({
    required this.merchant,
    required this.date,
    required this.amountInCents,
    required this.currency,
    required this.category,
  });
  factory ReceiptDetails.mock() => ReceiptDetails(
    merchant: 'Starbucks',
    date: DateTime(2026, 10, 18),
    amountInCents: 2450,
    currency: 'USD',
    category: 'Food & Drinks',
  );
  final String merchant;
  final DateTime date;
  final int amountInCents;
  final String currency;
  final String category;
  String get formattedAmount =>
      '${amountInCents ~/ 100}.${(amountInCents % 100).toString().padLeft(2, '0')}';
}

class SavedReceiptExpense {
  SavedReceiptExpense({
    String? id,
    required this.details,
    this.receipt,
    this.receiptId,
  }) : id = id ?? 'expense-${_nextId++}';
  static int _nextId = 0;
  final String id;
  final String? receiptId;
  final ReceiptDetails details;
  final ReceiptSelection? receipt;
}
