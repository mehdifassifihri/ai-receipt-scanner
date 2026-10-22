import '../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../models/receipt_details.dart';
import '../models/demo_expenses.dart';
import '../state/expense_store.dart';
import '../widgets/expense_list_tile.dart';
import 'expense_details_screen.dart';
import 'receipt_scanner_screen.dart';

const _ink = AppColors.ink;
const _muted = AppColors.muted;

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _search = TextEditingController();
  final _demoStore = ExpenseStore();
  String _category = 'All';
  bool _demo = false;
  String? _currency;

  @override
  void initState() {
    super.initState();
    for (final expense in createDemoExpenses(DateTime.now())) {
      _demoStore.add(expense);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _demoStore.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _search.clear();
      _category = 'All';
    });
  }

  String _group(DateTime date, DateTime now) {
    if (DateUtils.isSameDay(date, now)) return 'Today';
    if (DateUtils.isSameDay(date, DateTime(now.year, now.month, now.day - 1))) {
      return 'Yesterday';
    }
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context) {
    final userStore = ExpenseScope.of(context);
    final store = _demo ? _demoStore : userStore;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final expenses = store.expenses.toList()
          ..sort((a, b) => b.details.date.compareTo(a.details.date));
        final filtered = expenses
            .where(
              (expense) =>
                  expense.details.merchant.toLowerCase().contains(
                    _search.text.trim().toLowerCase(),
                  ) &&
                  (_category == 'All' || expense.details.category == _category),
            )
            .toList();
        final entries = <({String? heading, SavedReceiptExpense? expense})>[];
        String? lastGroup;
        for (final expense in filtered) {
          final group = _group(expense.details.date, now);
          if (group != lastGroup) {
            entries.add((heading: group, expense: null));
            lastGroup = group;
          }
          entries.add((heading: null, expense: expense));
        }
        final currencies =
            expenses.map((expense) => expense.details.currency).toSet().toList()
              ..sort();
        final currency = currencies.contains(_currency)
            ? _currency!
            : (currencies.contains('USD')
                  ? 'USD'
                  : currencies.firstOrNull ?? 'USD');
        int totalFor(DateTime month) => expenses
            .where(
              (expense) =>
                  expense.details.currency == currency &&
                  expense.details.date.year == month.year &&
                  expense.details.date.month == month.month,
            )
            .fold(0, (sum, expense) => sum + expense.details.amountInCents);
        final total = totalFor(now);
        final previous = totalFor(DateTime(now.year, now.month - 1));
        final totalDetails = ReceiptDetails(
          merchant: '',
          date: now,
          amountInCents: total,
          currency: currency,
          category: 'Other',
        );
        final comparison = previous > 0
            ? '${total >= previous ? '+' : ''}${((total - previous) / previous * 100).toStringAsFixed(1)}% vs. last month'
            : 'No previous-month comparison';
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            title: const Text(
              'My Expenses',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 20),
                child: Icon(Icons.history_rounded, size: 23),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 568),
                child: ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  itemCount: 2 + (entries.isEmpty ? 1 : entries.length),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Track and manage your spending',
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                          const SizedBox(height: 22),
                          if (_demo)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEE8F7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'DEMO DATA',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Sample expenses, separate from your receipts.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _clear();
                                      setState(() {
                                        _demo = false;
                                        _currency = null;
                                      });
                                    },
                                    child: const Text('Return to my expenses'),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.all(21),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDDEEBA),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'This month',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (currencies.length > 1)
                                      DropdownButton<String>(
                                        value: currency,
                                        underline: const SizedBox.shrink(),
                                        isDense: true,
                                        icon: const Icon(
                                          Icons.expand_more_rounded,
                                          size: 18,
                                        ),
                                        items: [
                                          for (final code in currencies)
                                            DropdownMenuItem(
                                              value: code,
                                              child: Text(
                                                code,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                        ],
                                        onChanged: (value) =>
                                            setState(() => _currency = value),
                                      )
                                    else
                                      Text(
                                        currency,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    formatExpenseAmount(context, totalDetails),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${expenses.length} saved expenses · ${_demo
                                      ? 'demo'
                                      : userStore.connected
                                      ? 'synced'
                                      : 'this session'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF526840),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  comparison,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF526840),
                                  ),
                                ),
                                if (currencies.length > 1)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Totals shown per currency. No conversion applied.',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF526840),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'In-memory only · resets when the app restarts',
                            style: TextStyle(color: _muted, fontSize: 10),
                          ),
                          const SizedBox(height: 22),
                        ],
                      );
                    }
                    if (index == 1) {
                      return Column(
                        children: [
                          TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Search expenses...',
                              hintStyle: const TextStyle(
                                fontSize: 13,
                                color: _muted,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 21,
                              ),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () => setState(_search.clear),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 19,
                                      ),
                                    ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(17),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 48,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: receiptCategories.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final category = index == 0
                                    ? 'All'
                                    : receiptCategories[index - 1];
                                return ChoiceChip(
                                  label: Text(
                                    category,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  selected: _category == category,
                                  showCheckmark: false,
                                  selectedColor: _ink,
                                  backgroundColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: _category == category
                                        ? Colors.white
                                        : _ink,
                                  ),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _category = category),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    if (entries.isEmpty) {
                      return _EmptyExpenses(
                        noExpenses: expenses.isEmpty,
                        onClear: _clear,
                        onScan: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ReceiptScannerScreen(),
                          ),
                        ),
                        onDemo: !_demo && expenses.isEmpty
                            ? () {
                                _clear();
                                setState(() {
                                  _demo = true;
                                  _currency = null;
                                });
                              }
                            : null,
                      );
                    }
                    final entry = entries[index - 2];
                    if (entry.heading != null) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(2, 16, 0, 10),
                        child: Text(
                          entry.heading!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: ExpenseListTile(
                        expense: entry.expense!,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ExpenseDetailsScreen(
                              store: store,
                              expenseId: entry.expense!.id,
                              isDemo: _demo,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({
    required this.noExpenses,
    required this.onClear,
    required this.onScan,
    this.onDemo,
  });
  final bool noExpenses;
  final VoidCallback onClear, onScan;
  final VoidCallback? onDemo;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 35),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFFE8EEDC),
            shape: BoxShape.circle,
          ),
          child: Icon(
            noExpenses ? Icons.receipt_long_outlined : Icons.search_off_rounded,
            size: 32,
            color: const Color(0xFF42634B),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          noExpenses ? 'No expenses yet' : 'No matching expenses',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          noExpenses
              ? 'Scan your first receipt to start tracking expenses.'
              : 'Try another search or category.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: _muted, height: 1.6),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: noExpenses ? onScan : onClear,
          style: FilledButton.styleFrom(
            backgroundColor: _ink,
            minimumSize: const Size(160, 48),
          ),
          child: Text(noExpenses ? 'Scan Receipt' : 'Clear Filters'),
        ),
        if (onDemo != null)
          TextButton(
            onPressed: onDemo,
            child: const Text('View demo expenses'),
          ),
      ],
    ),
  );
}
