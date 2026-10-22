import 'package:ai_receipt_scanner/models/receipt_details.dart';
import 'package:ai_receipt_scanner/services/analytics_report.dart';
import 'package:flutter_test/flutter_test.dart';

SavedReceiptExpense record(
  int cents,
  DateTime date, {
  String category = 'Food & Drinks',
  String currency = 'USD',
}) => SavedReceiptExpense(
  details: ReceiptDetails(
    merchant: 'Merchant',
    date: date,
    amountInCents: cents,
    currency: currency,
    category: category,
  ),
);

void main() {
  final now = DateTime(2026, 10, 18);
  test(
    'Month-to-date and its preceding range have equal calendar-day duration',
    () {
      final range = rangeForPeriod(AnalyticsPeriod.thisMonth, now);
      expect(range.start, DateTime.utc(2026, 10, 1));
      expect(range.endExclusive, DateTime.utc(2026, 10, 19));
      expect(range.days, 18);
      expect(range.preceding.start, DateTime.utc(2026, 9, 13));
      expect(range.preceding.endExclusive, range.start);
      expect(range.preceding.days, range.days);
      expect(range.contains(DateTime(2026, 10, 18, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 10, 19)), isFalse);
    },
  );
  test('Calendar periods handle leap days and year boundaries', () {
    final lastMonth = rangeForPeriod(
      AnalyticsPeriod.lastMonth,
      DateTime(2024, 3, 10),
    );
    expect(lastMonth.start, DateTime.utc(2024, 2));
    expect(lastMonth.days, 29);
    expect(lastMonth.preceding.days, 29);
    final three = rangeForPeriod(
      AnalyticsPeriod.lastThreeMonths,
      DateTime(2026, 1, 5),
    );
    expect(three.start, DateTime.utc(2025, 11));
    expect(three.lastDay, DateTime.utc(2026, 1, 5));
    final year = rangeForPeriod(
      AnalyticsPeriod.thisYear,
      DateTime(2024, 2, 29),
    );
    expect(year.days, 60);
    expect(year.preceding.days, 60);
  });
  test(
    'Aggregation separates currencies, filters boundaries, and calculates ratios',
    () {
      final report = calculateAnalytics(
        [
          record(6000, DateTime(2026, 10, 1)),
          record(4000, DateTime(2026, 10, 18, 23), category: 'Shopping'),
          record(20000, DateTime(2026, 9, 13)),
          record(99999, DateTime(2026, 9, 12)),
          record(99999, DateTime(2026, 10, 19)),
          record(99999, now, currency: 'EUR'),
        ],
        period: AnalyticsPeriod.thisMonth,
        currency: 'USD',
        now: now,
      );
      expect(report.totalInCents, 10000);
      expect(report.previousTotalInCents, 20000);
      expect(report.transactionCount, 2);
      expect(report.percentageChange, -50);
      expect(report.averageInCents, 5000);
      expect(report.categories.map((category) => category.name), [
        'Food & Drinks',
        'Shopping',
      ]);
      expect(report.categories.map((category) => category.share), [.6, .4]);
      expect(
        report.categories.fold<double>(
          0,
          (sum, category) => sum + category.share,
        ),
        closeTo(1, 1e-10),
      );
      expect(report.buckets.length, 18);
      expect(report.buckets.first.amountInCents, 6000);
      expect(report.buckets.last.amountInCents, 4000);
      expect(report.buckets[1].amountInCents, 0);
      expect(
        report.buckets.fold<int>(
          0,
          (sum, bucket) => sum + bucket.amountInCents,
        ),
        report.totalInCents,
      );
    },
  );
  test(
    'Monthly buckets fill missing months and clip the current month to today',
    () {
      final report = calculateAnalytics(
        [
          record(100, DateTime(2026, 8, 1)),
          record(200, DateTime(2026, 10, 18)),
          record(99999, DateTime(2026, 7, 31)),
        ],
        period: AnalyticsPeriod.lastThreeMonths,
        currency: 'USD',
        now: now,
      );
      expect(report.buckets.map((bucket) => bucket.amountInCents), [
        100,
        0,
        200,
      ]);
      expect(report.buckets.last.endExclusive, DateTime.utc(2026, 10, 19));
      expect(report.totalInCents, 300);
    },
  );
  test(
    'No baseline never invents a comparison; cents and tiny amounts stay exact',
    () {
      final report = calculateAnalytics(
        [record(1, now), record(2, now)],
        period: AnalyticsPeriod.thisMonth,
        currency: 'USD',
        now: now,
      );
      expect(report.totalInCents, 3);
      expect(report.averageInCents, 2);
      expect(report.percentageChange, isNull);
      final empty = calculateAnalytics(
        [],
        period: AnalyticsPeriod.thisMonth,
        currency: 'USD',
        now: now,
      );
      expect(empty.totalInCents, 0);
      expect(empty.categories, isEmpty);
      expect(empty.averageInCents, 0);
      expect(empty.percentageChange, isNull);
    },
  );
}
