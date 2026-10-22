import '../theme/app_theme.dart';
import '../widgets/spending_glass_card.dart';
import '../state/account_scope.dart';
import '../services/analytics_report.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/dashboard_data.dart';
import 'receipt_scanner_screen.dart';
import 'expenses_screen.dart';
import 'analytics_screen.dart';
import 'ask_snap_screen.dart';
import '../state/expense_store.dart';
import '../widgets/artwork_refresh_scroll_view.dart';

const _ink = AppColors.ink;
const _muted = AppColors.muted;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenMenu});
  final VoidCallback? onOpenMenu;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _currency;

  String _welcomeTitle(bool connected) {
    // Supabase is only initialized in connected mode.
    if (!connected) return 'Welcome back';
    final name = AccountScope.maybeOf(context)?.firstName;
    return name == null ? 'Welcome back' : 'Welcome back, $name';
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseScope.of(context);
    final saved = store.expenses;
    final currencies = saved.map((e) => e.details.currency).toSet().toList()
      ..sort();
    final currency = currencies.contains(_currency)
        ? _currency!
        : currencies.firstOrNull ?? 'USD';
    final report = store.report(
      period: AnalyticsPeriod.thisMonth,
      currency: currency,
      now: DateTime.now().toUtc(),
    );
    final categories = [
      for (var i = 0; i < report.categories.length; i++)
        SpendingCategory(
          report.categories[i].name,
          (report.categories[i].share * 100).round(),
          spendingCategories[i % spendingCategories.length].color,
        ),
    ];
    final displayedExpenses = [
      for (final expense in saved)
        Expense(
          expense.details.merchant,
          expense.details.category,
          '${expense.details.date.month}/${expense.details.date.day}/${expense.details.date.year}',
          '${expense.details.currency} ${expense.details.formattedAmount}',
          Icons.receipt_long_outlined,
          const Color(0xFFE5EDDF),
        ),
      if (!store.connected) ...recentExpenses,
    ].take(4).toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Row(
                    children: [
                      if (widget.onOpenMenu != null)
                        IconButton(
                          tooltip: 'Open menu',
                          onPressed: widget.onOpenMenu,
                          icon: const Icon(Icons.menu_rounded),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 44,
                          ),
                        ),
                      if (widget.onOpenMenu == null)
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _ink,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.document_scanner_outlined,
                            color: Color(0xFFD9EFA7),
                            size: 21,
                          ),
                        ),
                      const SizedBox(width: 9),
                      const Text(
                        'snapexpense',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5EADB),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ArtworkRefreshScrollView(
                onRefresh: () async {
                  await store.refresh();
                  if (context.mounted && store.error != null) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(store.error!)));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _welcomeTitle(store.connected),
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'A little clarity for every penny.',
                            style: TextStyle(color: _muted, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          if (store.loading)
                            const LinearProgressIndicator(
                              color: Color(0xFF75945D),
                            ),
                          if (store.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(store.error!),
                                  TextButton(
                                    onPressed: store.loading
                                        ? null
                                        : store.refresh,
                                    child: const Text('Retry sync'),
                                  ),
                                ],
                              ),
                            ),
                          if (store.connected) ...[
                            _LiveSummary(
                              report: report,
                              currencies: currencies,
                              onCurrencyChanged: (value) =>
                                  setState(() => _currency = value),
                            ),
                          ] else
                            const _SummaryCard(),
                          const SizedBox(height: 12),
                          Material(
                            color: const Color(0xFFEEE8F7),
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AskSnapScreen(),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(18),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      color: Color(0xFF68577F),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Ask Snap',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            'Your expenses, explained.',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_outward_rounded,
                                      size: 19,
                                      color: Color(0xFF68577F),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  value: store.connected
                                      ? '${saved.where((e) => e.receiptId != null).length}'
                                      : '24',
                                  label: store.connected
                                      ? 'Saved receipts'
                                      : 'Receipts scanned',
                                  icon: Icons.receipt_long_outlined,
                                  color: Color(0xFFEEE8F7),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  value: store.connected
                                      ? '${saved.map((e) => e.details.category).toSet().length}'
                                      : '5',
                                  label: 'Expense categories',
                                  icon: Icons.grid_view_rounded,
                                  color: Color(0xFFE5EDDF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ReceiptScannerScreen(),
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _ink,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(19),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.document_scanner_outlined,
                                    size: 23,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Scan Receipt',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Icon(Icons.arrow_outward_rounded, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _BreakdownCard(
                            categories: store.connected
                                ? categories
                                : spendingCategories,
                          ),
                          const SizedBox(height: 25),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Recent expenses',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const ExpensesScreen(),
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: _muted,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('See All'),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_outward_rounded, size: 14),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _Surface(
                            child: Column(
                              children: [
                                if (displayedExpenses.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      'Your first receipt starts the story. Scan one to get started.',
                                    ),
                                  ),
                                for (
                                  var i = 0;
                                  i < displayedExpenses.length;
                                  i++
                                ) ...[
                                  _ExpenseRow(expense: displayedExpenses[i]),
                                  if (i < displayedExpenses.length - 1)
                                    const Divider(
                                      height: 1,
                                      indent: 66,
                                      color: Color(0xFFF0F1EC),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 23),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.auto_awesome_outlined,
                                size: 14,
                                color: _muted,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Small scans. Smarter spending.',
                                style: TextStyle(fontSize: 12, color: _muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();
  @override
  Widget build(BuildContext context) => SpendingGlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Monthly spending',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Oct 2026',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            '\$2,450.75',
            style: TextStyle(
              fontSize: 43,
              fontWeight: FontWeight.w600,
              letterSpacing: -2.3,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 17),
        const Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            _ComparisonBadge(),
            Text(
              'vs. last month',
              style: TextStyle(fontSize: 12, color: Color(0xFF59674C)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Divider(height: 1, color: Color(0xFFC6D7A4)),
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(
              Icons.trending_down_rounded,
              size: 17,
              color: Color(0xFF48643A),
            ),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'A lighter month. Looking good!',
                style: TextStyle(fontSize: 12, color: Color(0xFF48643A)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ComparisonBadge extends StatelessWidget {
  const _ComparisonBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.south_east_rounded, size: 14, color: Color(0xFF426139)),
        SizedBox(width: 4),
        Text(
          '12.8%',
          style: TextStyle(
            color: Color(0xFF426139),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value, label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(23),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
              ),
            ),
            Icon(icon, size: 23, color: _ink),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF62645E)),
        ),
      ],
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x04000000),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class _BreakdownCard extends StatefulWidget {
  const _BreakdownCard({this.categories = spendingCategories});
  final List<SpendingCategory> categories;
  @override
  State<_BreakdownCard> createState() => _BreakdownCardState();
}

class _BreakdownCardState extends State<_BreakdownCard> {
  int? selected;
  @override
  void didUpdateWidget(covariant _BreakdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    selected = null;
  }

  @override
  Widget build(BuildContext context) => widget.categories.isEmpty
      ? const _Surface(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Spending breakdown will appear after your first expense this month.',
            ),
          ),
        )
      : _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Spending breakdown',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open Analytics',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AnalyticsScreen(),
                      ),
                    ),
                    icon: const Icon(
                      Icons.insights_rounded,
                      color: _muted,
                      size: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Where your money goes',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final chart = SizedBox(
                    width: 152,
                    height: 152,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            startDegreeOffset: -90,
                            sectionsSpace: 5,
                            centerSpaceRadius: 53,
                            pieTouchData: PieTouchData(
                              touchCallback: (event, response) {
                                final index =
                                    response
                                        ?.touchedSection
                                        ?.touchedSectionIndex ??
                                    -1;
                                if (event is FlTapUpEvent) {
                                  setState(
                                    () => selected = index >= 0 ? index : null,
                                  );
                                }
                              },
                            ),
                            sections: [
                              for (var i = 0; i < widget.categories.length; i++)
                                PieChartSectionData(
                                  value: widget.categories[i].percent
                                      .toDouble(),
                                  color: widget.categories[i].color,
                                  radius: selected == i ? 22 : 17,
                                  showTitle: false,
                                ),
                            ],
                          ),
                        ),
                        IgnorePointer(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selected == null
                                    ? '100%'
                                    : '${widget.categories[selected!].percent}%',
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                selected == null
                                    ? 'this month'
                                    : widget.categories[selected!].name,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                  final legend = Column(
                    children: [
                      for (var i = 0; i < widget.categories.length; i++)
                        Semantics(
                          button: true,
                          selected: selected == i,
                          label:
                              '${widget.categories[i].name}, ${widget.categories[i].percent} percent',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(
                              () => selected = selected == i ? null : i,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 9,
                                horizontal: 4,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: widget.categories[i].color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      widget.categories[i].name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: selected == i
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${widget.categories[i].percent}%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                  if (constraints.maxWidth < 290) {
                    return Column(
                      children: [
                        Center(child: chart),
                        const SizedBox(height: 18),
                        legend,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      chart,
                      const SizedBox(width: 20),
                      Expanded(child: legend),
                    ],
                  );
                },
              ),
            ],
          ),
        );
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final Expense expense;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: expense.color,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(expense.icon, size: 22, color: _ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense.merchant,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                expense.category,
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              expense.amount.contains(' ')
                  ? '-${expense.amount}'
                  : '-\$${expense.amount}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              expense.date,
              style: const TextStyle(fontSize: 10, color: _muted),
            ),
          ],
        ),
      ],
    ),
  );
}

const _currencyInfo = {
  'CAD': ('\$', 'Canadian dollar'),
  'USD': ('\$', 'US dollar'),
  'EUR': ('€', 'Euro'),
  'GBP': ('£', 'British pound'),
  'JPY': ('¥', 'Japanese yen'),
  'CNY': ('¥', 'Chinese yuan'),
  'AUD': ('\$', 'Australian dollar'),
  'CHF': ('Fr', 'Swiss franc'),
  'INR': ('₹', 'Indian rupee'),
  'MXN': ('\$', 'Mexican peso'),
  'MAD': ('DH', 'Moroccan dirham'),
};

class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker({
    required this.selected,
    required this.currencies,
    required this.onChanged,
  });
  final String selected;
  final List<String> currencies;
  final ValueChanged<String> onChanged;
  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Currency',
      offset: const Offset(0, 40),
      elevation: 10,
      shadowColor: _ink.withValues(alpha: 0.25),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 260),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE8ECE2)),
      ),
      menuPadding: const EdgeInsets.all(8),
      popUpAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 280),
      ),
      onOpened: () => setState(() => _open = true),
      onCanceled: () => setState(() => _open = false),
      onSelected: (value) {
        setState(() => _open = false);
        widget.onChanged(value);
      },
      itemBuilder: (_) => [
        for (final code in widget.currencies)
          PopupMenuItem(
            value: code,
            height: 0,
            padding: EdgeInsets.zero,
            child: _CurrencyOption(
              code: code,
              selected: code == widget.selected,
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: _ink.withValues(alpha: _open ? 0.25 : 0.12),
              blurRadius: _open ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFD9EFA7),
                shape: BoxShape.circle,
              ),
              child: Text(
                _currencyInfo[widget.selected]?.$1 ?? widget.selected[0],
                style: const TextStyle(
                  color: _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              widget.selected,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 220),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFFD9EFA7),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyOption extends StatelessWidget {
  const _CurrencyOption({required this.code, required this.selected});
  final String code;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final info = _currencyInfo[code];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFF5E4) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? const [Color(0xFFD9EFA7), Color(0xFFB9D98A)]
                    : const [Color(0xFFF1EEF6), Color(0xFFE6DFF0)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              info?.$1 ?? code[0],
              style: const TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                if (info != null)
                  Text(
                    info.$2,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
              ],
            ),
          ),
          AnimatedScale(
            scale: selected ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: _ink,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFFD9EFA7),
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveSummary extends StatelessWidget {
  const _LiveSummary({
    required this.report,
    required this.currencies,
    required this.onCurrencyChanged,
  });
  final AnalyticsReport report;
  final List<String> currencies;
  final ValueChanged<String> onCurrencyChanged;
  @override
  Widget build(BuildContext context) {
    final amount = report.totalInCents;
    final change = report.percentageChange;
    return SpendingGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Monthly spending',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              if (currencies.length > 1)
                _CurrencyPicker(
                  selected: report.currency,
                  currencies: currencies,
                  onChanged: onCurrencyChanged,
                ),
            ],
          ),
          const SizedBox(height: 22),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${report.currency} ${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                change == null || change <= 0
                    ? Icons.south_east_rounded
                    : Icons.north_east_rounded,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  change == null
                      ? 'No previous period data'
                      : '${change.abs().toStringAsFixed(1)}% ${change <= 0 ? 'less' : 'more'} than previous period',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFC6D7A4)),
          Text(
            '${report.transactionCount} expenses this month · ${report.currency}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
