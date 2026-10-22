import 'package:flutter/material.dart';
import '../models/receipt_details.dart';

String formatExpenseAmount(BuildContext context, ReceiptDetails details) =>
    '${details.currency} ${MaterialLocalizations.of(context).formatDecimal(details.amountInCents ~/ 100)}.${(details.amountInCents % 100).toString().padLeft(2, '0')}';

IconData expenseCategoryIcon(String category) => switch (category) {
  'Food & Drinks' => Icons.local_cafe_outlined,
  'Shopping' => Icons.shopping_bag_outlined,
  'Transport' => Icons.directions_car_outlined,
  'Groceries' => Icons.shopping_basket_outlined,
  'Health' => Icons.local_pharmacy_outlined,
  'Entertainment' => Icons.movie_outlined,
  'Utilities' => Icons.bolt_outlined,
  _ => Icons.receipt_long_outlined,
};

class ExpenseListTile extends StatelessWidget {
  const ExpenseListTile({
    super.key,
    required this.expense,
    required this.onTap,
  });
  final SavedReceiptExpense expense;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final details = expense.details;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EEDC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  expenseCategoryIcon(details.category),
                  size: 21,
                  color: const Color(0xFF42634B),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details.merchant,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details.category,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777C73),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(details.date),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF777C73),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatExpenseAmount(context, details),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: Color(0xFF93988D),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
