import '../data/backend_api.dart';
import '../theme/app_theme.dart';
import '../models/receipt_details.dart';
import 'package:flutter/material.dart';
import '../services/analytics_report.dart';
import '../state/expense_store.dart';
import '../widgets/analytics_charts.dart';
import '../widgets/expense_list_tile.dart';
import 'receipt_scanner_screen.dart';

const _ink = AppColors.ink;
const _muted = AppColors.muted;

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.today});

  /// Optional deterministic clock for report previews and tests.
  final DateTime? today;
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsPeriod _period = AnalyticsPeriod.thisMonth;
  String? _currency;
  String? _remoteKey;
  Future<AnalyticsReport>? _remoteReport;

  @override
  Widget build(BuildContext context) {
    final expenses = ExpenseScope.of(context).expenses;
    final currencies =
        expenses.map((expense) => expense.details.currency).toSet().toList()
          ..sort();
    final currency = currencies.contains(_currency)
        ? _currency!
        : currencies.contains('USD')
        ? 'USD'
        : currencies.firstOrNull ?? 'USD';
    final store = ExpenseScope.of(context);
    if (store.api != null) {
      final key = '${store.revision}|${_period.name}|$currency';
      if (_remoteKey != key) {
        _remoteKey = key;
        _remoteReport = store.api!.analytics(_period, currency);
      }
      return FutureBuilder<AnalyticsReport>(
        future: _remoteReport,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Scaffold(
              appBar: AppBar(title: const Text('Analytics')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Analytics')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        apiErrorMessage(snapshot.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() => _remoteKey = null),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return _reportView(
            context,
            expenses,
            snapshot.data!,
            currency,
            currencies,
          );
        },
      );
    }
    return _reportView(
      context,
      expenses,
      calculateAnalytics(
        expenses,
        period: _period,
        currency: currency,
        now: widget.today ?? DateTime.now(),
      ),
      currency,
      currencies,
    );
  }

  Widget _reportView(
    BuildContext context,
    List<SavedReceiptExpense> expenses,
    AnalyticsReport report,
    String currency,
    List<String> currencies,
  ) {
    final change = report.percentageChange;
    final comparison = change == null
        ? 'No previous period data'
        : change == 0
        ? 'Unchanged from the previous period'
        : '${change.abs().toStringAsFixed(1)}% ${change < 0 ? 'less' : 'more'} than previous period';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Analytics',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 22),
            child: Icon(Icons.insights_rounded, size: 23),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Understand where your money goes',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final period in AnalyticsPeriod.values)
                        ChoiceChip(
                          label: Text(
                            period.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _period == period,
                          showCheckmark: false,
                          selectedColor: _ink,
                          backgroundColor: Colors.white,
                          side: BorderSide.none,
                          labelStyle: TextStyle(
                            color: _period == period ? Colors.white : _ink,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onSelected: (_) => setState(() => _period = period),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: _muted,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          analyticsRangeLabel(context, report.range),
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ),
                      if (currencies.length > 1)
                        DropdownButton<String>(
                          value: currency,
                          underline: const SizedBox.shrink(),
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          items: [
                            for (final code in currencies)
                              DropdownMenuItem(
                                value: code,
                                child: Text(
                                  code,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _currency = value),
                        ),
                    ],
                  ),
                  if (currencies.length > 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'One currency at a time. No exchange conversions.',
                        style: TextStyle(fontSize: 10, color: _muted),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (expenses.isEmpty)
                    _AnalyticsEmpty(
                      noData: true,
                      onScan: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ReceiptScannerScreen(),
                        ),
                      ),
                    )
                  else if (report.transactionCount == 0)
                    const _AnalyticsEmpty(noData: false)
                  else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(23),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDEEBA),
                        borderRadius: BorderRadius.circular(27),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total spending',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              analyticsMoney(
                                context,
                                currency,
                                report.totalInCents,
                              ),
                              key: const ValueKey('analytics-total'),
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                change == null || change == 0
                                    ? Icons.remove_rounded
                                    : change < 0
                                    ? Icons.south_east_rounded
                                    : Icons.north_east_rounded,
                                size: 17,
                                color: const Color(0xFF42634B),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  comparison,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF42634B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1, color: Color(0xFFC6D7A4)),
                          const SizedBox(height: 14),
                          Text(
                            '${report.transactionCount} ${report.transactionCount == 1 ? 'transaction' : 'transactions'} · ${report.currency}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF526840),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Compared with ${analyticsRangeLabel(context, report.range.preceding)} · ${report.range.days} days each',
                      style: const TextStyle(fontSize: 10, color: _muted),
                    ),
                    const SizedBox(height: 22),
                    SpendingTrendChart(report: report),
                    const SizedBox(height: 18),
                    CategoryBreakdownChart(report: report),
                    const SizedBox(height: 18),
                    _TopCategories(report: report),
                    const SizedBox(height: 18),
                    AnalyticsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 21,
                                color: Color(0xFF42634B),
                              ),
                              SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Spending Insights',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _Insight(
                            text:
                                '${report.categories.first.name} is your largest spending category, at ${(report.categories.first.share * 100).toStringAsFixed(1)}% of your total.',
                          ),
                          _Insight(
                            text: change == null
                                ? 'There is no previous-period spending to compare yet.'
                                : '$comparison.',
                          ),
                          _Insight(
                            text:
                                'You recorded ${report.transactionCount} ${report.transactionCount == 1 ? 'expense' : 'expenses'} in ${report.currency} during this period.',
                          ),
                          _Insight(
                            text:
                                'Your average expense is ${analyticsMoney(context, currency, report.averageInCents)}.',
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Calculated from your recorded expenses',
                            style: TextStyle(fontSize: 10, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      'Session data only · resets when the app restarts',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopCategories extends StatelessWidget {
  const _TopCategories({required this.report});
  final AnalyticsReport report;
  @override
  Widget build(BuildContext context) => AnalyticsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top spending categories',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 8),
        for (final (index, category) in report.categories.take(3).indexed)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 37,
                      height: 37,
                      decoration: BoxDecoration(
                        color: analyticsCategoryColor(
                          category.name,
                        ).withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        expenseCategoryIcon(category.name),
                        size: 19,
                        color: analyticsCategoryColor(category.name),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}. ${category.name}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${(category.share * 100).toStringAsFixed(1)}% of total',
                            style: const TextStyle(fontSize: 10, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        analyticsMoney(
                          context,
                          report.currency,
                          category.amountInCents,
                        ),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: category.share,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: const Color(0xFFF0F2EB),
                  color: analyticsCategoryColor(category.name),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Insight extends StatelessWidget {
  const _Insight({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 5, color: Color(0xFF75945D)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Color(0xFF52604D),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AnalyticsEmpty extends StatelessWidget {
  const _AnalyticsEmpty({required this.noData, this.onScan});
  final bool noData;
  final VoidCallback? onScan;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 55),
    child: Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: Color(0xFFE8EEDC),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bar_chart_rounded,
              size: 36,
              color: Color(0xFF42634B),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            noData ? 'No spending data yet' : 'No expenses for this period',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            noData
                ? 'Scan your first receipt to unlock your spending insights.'
                : 'Try selecting another time range.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.6, color: _muted),
          ),
          if (noData)
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: FilledButton.icon(
                onPressed: onScan,
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  minimumSize: const Size(160, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.document_scanner_outlined, size: 20),
                label: const Text('Scan Receipt'),
              ),
            ),
        ],
      ),
    ),
  );
}
