import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/receipt_details.dart';
import '../services/analytics_report.dart';
import 'expense_list_tile.dart';

const analyticsCategoryColors = [
  Color(0xFF426F55),
  Color(0xFFB7A4DC),
  Color(0xFF9CBE6D),
  Color(0xFFD7AD86),
  Color(0xFF78A9AE),
  Color(0xFF7990C8),
  Color(0xFFC48891),
  Color(0xFF91998B),
];
Color analyticsCategoryColor(String name) {
  final index = receiptCategories.indexOf(name);
  return analyticsCategoryColors[index < 0 ? 7 : index];
}

String analyticsMoney(BuildContext context, String currency, int cents) =>
    formatExpenseAmount(
      context,
      ReceiptDetails(
        merchant: '',
        date: DateTime(2000),
        amountInCents: cents,
        currency: currency,
        category: 'Other',
      ),
    );
String analyticsRangeLabel(BuildContext context, AnalyticsRange range) {
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatShortDate(range.start)} – ${locale.formatShortDate(range.lastDay)}';
}

String _compact(double value) {
  if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)}B';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  if (value < 1 && value > 0) return value.toStringAsFixed(2);
  return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}

class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(25),
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

class SpendingTrendChart extends StatefulWidget {
  const SpendingTrendChart({super.key, required this.report});
  final AnalyticsReport report;
  @override
  State<SpendingTrendChart> createState() => _SpendingTrendChartState();
}

class _SpendingTrendChartState extends State<SpendingTrendChart> {
  int? selected;
  @override
  void didUpdateWidget(covariant SpendingTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report != widget.report) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final buckets = report.buckets;
    final maxValue = buckets.fold<double>(
      0,
      (value, bucket) => math.max(value, bucket.amountInCents / 100),
    );
    final maximum = math.max(.04, (maxValue * 1.25 * 100 / 4).ceil() * 4 / 100);
    final axisStep = math.max(1, (buckets.length / 5).ceil());
    String bucketLabel(int index) => report.monthlyBuckets
        ? MaterialLocalizations.of(context)
              .formatShortMonthDay(buckets[index].start)
              .replaceAll(RegExp(r'\s+1$'), '')
        : '${buckets[index].start.day}';
    final active = selected == null ? null : buckets[selected!];
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spending trend',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${report.monthlyBuckets ? 'Monthly' : 'Daily'} totals · ${report.currency}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF777C73)),
          ),
          const SizedBox(height: 14),
          Text(
            active == null
                ? 'Tap a bar to explore your spending'
                : '${MaterialLocalizations.of(context).formatMediumDate(active.start)} · ${analyticsMoney(context, report.currency, active.amountInCents)}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF42634B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 23),
          Semantics(
            label:
                'Spending trend in ${report.currency}. ${buckets.map((bucket) => '${MaterialLocalizations.of(context).formatMediumDate(bucket.start)}: ${analyticsMoney(context, report.currency, bucket.amountInCents)}').join('; ')}',
            child: SizedBox(
              height: 195,
              child: LayoutBuilder(
                builder: (context, constraints) => BarChart(
                  duration: const Duration(milliseconds: 180),
                  BarChartData(
                    minY: 0,
                    maxY: maximum,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: maximum / 4,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0xFFEDF0E8),
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          interval: maximum / 4,
                          getTitlesWidget: (value, meta) => Text(
                            _compact(value),
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF777C73),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 ||
                                index >= buckets.length ||
                                index % axisStep != 0) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: Text(
                                bucketLabel(index),
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF777C73),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchCallback: (event, response) {
                        if (event is FlTapUpEvent) {
                          setState(
                            () =>
                                selected = response?.spot?.touchedBarGroupIndex,
                          );
                        }
                      },
                      touchTooltipData: BarTouchTooltipData(
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        maxContentWidth: 180,
                        getTooltipColor: (_) => const Color(0xFF20251F),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                            BarTooltipItem(
                              '${MaterialLocalizations.of(context).formatMediumDate(buckets[groupIndex].start)}\n${analyticsMoney(context, report.currency, buckets[groupIndex].amountInCents)}',
                              const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < buckets.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: buckets[i].amountInCents / 100,
                              width: math.max(
                                2.0,
                                math.min(
                                  16.0,
                                  (constraints.maxWidth - 48) /
                                      buckets.length *
                                      .65,
                                ),
                              ),
                              color: selected == i
                                  ? const Color(0xFF9CBE6D)
                                  : const Color(0xFF426F55),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryBreakdownChart extends StatefulWidget {
  const CategoryBreakdownChart({super.key, required this.report});
  final AnalyticsReport report;
  @override
  State<CategoryBreakdownChart> createState() => _CategoryBreakdownChartState();
}

class _CategoryBreakdownChartState extends State<CategoryBreakdownChart> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final active = report.categories
        .where((category) => category.name == selected)
        .firstOrNull;
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spending by category',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Tap a category to take a closer look',
            style: TextStyle(fontSize: 11, color: Color(0xFF777C73)),
          ),
          const SizedBox(height: 22),
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    duration: const Duration(milliseconds: 180),
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: report.categories.length == 1 ? 0 : 4,
                      centerSpaceRadius: 68,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          if (event is! FlTapUpEvent) return;
                          final index =
                              response?.touchedSection?.touchedSectionIndex ??
                              -1;
                          setState(
                            () => selected =
                                index >= 0 && index < report.categories.length
                                ? report.categories[index].name
                                : null,
                          );
                        },
                      ),
                      sections: [
                        for (final category in report.categories)
                          PieChartSectionData(
                            value: category.amountInCents.toDouble(),
                            color: analyticsCategoryColor(category.name),
                            radius: active?.name == category.name ? 29 : 23,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  IgnorePointer(
                    child: SizedBox(
                      width: 120,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            active?.name ?? 'Total spending',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF777C73),
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              analyticsMoney(
                                context,
                                report.currency,
                                active?.amountInCents ?? report.totalInCents,
                              ),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.6,
                              ),
                            ),
                          ),
                          if (active != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${(active.share * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF42634B),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 21),
          for (final category in report.categories)
            Semantics(
              selected: selected == category.name,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(
                  () => selected = selected == category.name
                      ? null
                      : category.name,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: analyticsCategoryColor(category.name),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          category.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected == category.name
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
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
                            const SizedBox(height: 3),
                            Text(
                              '${(category.share * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF777C73),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
