import '../models/receipt_details.dart';

enum AnalyticsPeriod {
  thisMonth('This Month'),
  lastMonth('Last Month'),
  lastThreeMonths('Last 3 Months'),
  thisYear('This Year');

  const AnalyticsPeriod(this.label);
  final String label;
}

/// Calendar dates are normalized to UTC midnight to avoid DST changing day counts.
/// UTC is used for arithmetic only; transaction dates retain their calendar day.
DateTime analyticsDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

class AnalyticsRange {
  const AnalyticsRange(this.start, this.endExclusive);
  final DateTime start, endExclusive;
  int get days => endExclusive.difference(start).inDays;
  DateTime get lastDay => endExclusive.subtract(const Duration(days: 1));
  bool contains(DateTime date) {
    final day = analyticsDay(date);
    return !day.isBefore(start) && day.isBefore(endExclusive);
  }

  AnalyticsRange get preceding =>
      AnalyticsRange(start.subtract(Duration(days: days)), start);
}

AnalyticsRange rangeForPeriod(AnalyticsPeriod period, DateTime now) {
  final today = analyticsDay(now);
  final tomorrow = today.add(const Duration(days: 1));
  return switch (period) {
    AnalyticsPeriod.thisMonth => AnalyticsRange(
      DateTime.utc(now.year, now.month),
      tomorrow,
    ),
    AnalyticsPeriod.lastMonth => AnalyticsRange(
      DateTime.utc(now.year, now.month - 1),
      DateTime.utc(now.year, now.month),
    ),
    AnalyticsPeriod.lastThreeMonths => AnalyticsRange(
      DateTime.utc(now.year, now.month - 2),
      tomorrow,
    ),
    AnalyticsPeriod.thisYear => AnalyticsRange(
      DateTime.utc(now.year),
      tomorrow,
    ),
  };
}

class CategorySpending {
  const CategorySpending(this.name, this.amountInCents, this.share);
  final String name;
  final int amountInCents;
  final double share;
}

class TrendBucket {
  const TrendBucket(this.start, this.endExclusive, this.amountInCents);
  final DateTime start, endExclusive;
  final int amountInCents;
}

class AnalyticsReport {
  const AnalyticsReport({
    required this.period,
    required this.range,
    required this.currency,
    required this.totalInCents,
    required this.previousTotalInCents,
    required this.transactionCount,
    required this.categories,
    required this.buckets,
  });
  final AnalyticsPeriod period;
  final AnalyticsRange range;
  final String currency;
  final int totalInCents, previousTotalInCents, transactionCount;
  final List<CategorySpending> categories;
  final List<TrendBucket> buckets;
  double? get percentageChange => previousTotalInCents > 0
      ? (totalInCents - previousTotalInCents) / previousTotalInCents * 100
      : null;
  int get averageInCents =>
      transactionCount == 0 ? 0 : (totalInCents / transactionCount).round();
  bool get monthlyBuckets =>
      period == AnalyticsPeriod.lastThreeMonths ||
      period == AnalyticsPeriod.thisYear;
}

AnalyticsReport calculateAnalytics(
  Iterable<SavedReceiptExpense> expenses, {
  required AnalyticsPeriod period,
  required String currency,
  required DateTime now,
}) {
  final range = rangeForPeriod(period, now);
  final previous = range.preceding;
  final categoryTotals = <String, int>{};
  final bucketTotals = <DateTime, int>{};
  final monthly =
      period == AnalyticsPeriod.lastThreeMonths ||
      period == AnalyticsPeriod.thisYear;
  var total = 0, precedingTotal = 0, count = 0;
  for (final expense in expenses) {
    final details = expense.details;
    if (details.currency != currency || details.amountInCents <= 0) continue;
    if (previous.contains(details.date)) {
      precedingTotal += details.amountInCents;
    }
    if (!range.contains(details.date)) continue;
    total += details.amountInCents;
    count++;
    final category = receiptCategories.contains(details.category)
        ? details.category
        : 'Other';
    categoryTotals.update(
      category,
      (value) => value + details.amountInCents,
      ifAbsent: () => details.amountInCents,
    );
    final day = analyticsDay(details.date);
    final bucket = monthly ? DateTime.utc(day.year, day.month) : day;
    bucketTotals.update(
      bucket,
      (value) => value + details.amountInCents,
      ifAbsent: () => details.amountInCents,
    );
  }
  final categories =
      [
        for (final entry in categoryTotals.entries)
          CategorySpending(
            entry.key,
            entry.value,
            total > 0 ? entry.value / total : 0,
          ),
      ]..sort((a, b) {
        final byAmount = b.amountInCents.compareTo(a.amountInCents);
        return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
      });
  final buckets = <TrendBucket>[];
  var cursor = range.start;
  while (cursor.isBefore(range.endExclusive)) {
    final next = monthly
        ? DateTime.utc(cursor.year, cursor.month + 1)
        : cursor.add(const Duration(days: 1));
    buckets.add(
      TrendBucket(
        cursor,
        next.isAfter(range.endExclusive) ? range.endExclusive : next,
        bucketTotals[cursor] ?? 0,
      ),
    );
    cursor = next;
  }
  return AnalyticsReport(
    period: period,
    range: range,
    currency: currency,
    totalInCents: total,
    previousTotalInCents: precedingTotal,
    transactionCount: count,
    categories: List.unmodifiable(categories),
    buckets: List.unmodifiable(buckets),
  );
}
