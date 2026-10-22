import '../data/backend_api.dart';
import 'package:flutter/material.dart';
import '../state/expense_store.dart';
import '../widgets/expense_list_tile.dart';
import '../widgets/receipt_image_preview.dart';
import 'receipt_review_screen.dart';

class ExpenseDetailsScreen extends StatelessWidget {
  const ExpenseDetailsScreen({
    super.key,
    required this.store,
    required this.expenseId,
    this.isDemo = false,
  });
  final ExpenseStore store;
  final String expenseId;
  final bool isDemo;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text(
          'This expense will be permanently deleted. This action cannot be undone. Other expenses and their receipts will stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB33F3F),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.remove(expenseId);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(isDemo ? 'Demo expense deleted.' : 'Expense deleted.'),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final expense = store.find(expenseId);
    if (expense == null) return;
    final result = await Navigator.of(context).push<ReceiptReviewResult>(
      MaterialPageRoute(
        builder: (_) => ExpenseScope(
          store: store,
          child: ReceiptReviewScreen(editingExpense: expense),
        ),
      ),
    );
    if (context.mounted && result == ReceiptReviewResult.saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDemo ? 'Demo expense updated.' : 'Expense updated.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final expense = store.find(expenseId);
      if (expense == null) {
        return const Scaffold(
          body: Center(child: Text('Expense no longer available.')),
        );
      }
      final details = expense.details;
      final receipt = expense.receipt;
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Expense details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isDemo)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'DEMO EXPENSE · separate sample data',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF777C73),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      Center(
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: const Color(0xFFDDEEBA),
                          child: Icon(
                            expenseCategoryIcon(details.category),
                            color: const Color(0xFF42634B),
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        details.merchant,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        formatExpenseAmount(context, details),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 25),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(23),
                        ),
                        child: Column(
                          children: [
                            _DetailRow(
                              label: 'Transaction date',
                              value: MaterialLocalizations.of(
                                context,
                              ).formatFullDate(details.date),
                            ),
                            const Divider(height: 28, color: Color(0xFFF0F1EC)),
                            _DetailRow(
                              label: 'Category',
                              value: details.category,
                            ),
                            const Divider(height: 28, color: Color(0xFFF0F1EC)),
                            _DetailRow(
                              label: 'Currency',
                              value: details.currency,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (receipt == null && expense.receiptId != null)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('View receipt'),
                          onPressed: () async {
                            try {
                              final image = await store.receiptImage(expense);
                              if (context.mounted && image != null) {
                                await showReceiptImagePreview(context, image);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(apiErrorMessage(e))),
                                );
                              }
                            }
                          },
                        ),
                      if (receipt != null)
                        Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(23),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () =>
                                showReceiptImagePreview(context, receipt),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 180,
                                    width: double.infinity,
                                    child: Image.memory(
                                      receipt.bytes,
                                      fit: BoxFit.contain,
                                      cacheWidth: 1200,
                                      semanticLabel: 'Expense receipt',
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Text(
                                          'Receipt image unavailable',
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.zoom_in_rounded, size: 18),
                                      SizedBox(width: 7),
                                      Text(
                                        'View full receipt',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'No receipt image attached',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF777C73),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _edit(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF20251F),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        label: const Text('Edit Expense'),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () => _delete(context),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB33F3F),
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                        ),
                        label: const Text('Delete Expense'),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Stored in memory for this session only',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF777C73),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF777C73)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}
