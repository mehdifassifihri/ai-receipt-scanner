import 'package:ai_receipt_scanner/models/receipt_details.dart';
import 'package:ai_receipt_scanner/screens/analytics_screen.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Poppins');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await loader.load();
  });
  final now = DateTime(2026, 10, 18);
  SavedReceiptExpense record(
    int cents,
    DateTime date, {
    String currency = 'USD',
    String category = 'Food & Drinks',
  }) => SavedReceiptExpense(
    details: ReceiptDetails(
      merchant: 'Coffee Shop',
      date: date,
      amountInCents: cents,
      currency: currency,
      category: category,
    ),
  );
  Future<void> mount(WidgetTester tester, ExpenseStore store) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ExpenseScope(
        store: store,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, fontFamily: 'Poppins'),
          home: AnalyticsScreen(today: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Periods and currency recalculate all charts; category taps highlight',
    (tester) async {
      final store = ExpenseStore();
      addTearDown(store.dispose);
      store.add(record(6000, now));
      store.add(record(4000, now, category: 'Shopping'));
      store.add(record(2000, DateTime(2026, 9, 14)));
      store.add(record(500, now, currency: 'EUR'));
      await mount(tester, store);
      expect(find.text('USD 100.00'), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Last Month'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('analytics-total'))).data,
        'USD 20.00',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'This Month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('analytics-total'))).data,
        'EUR 5.00',
      );
      await tester.ensureVisible(find.byType(BarChart));
      await tester.pumpAndSettle();
      final bars = tester
          .widget<BarChart>(find.byType(BarChart))
          .data
          .barGroups;
      expect(
        bars.map((group) => group.barRods.first.toY).reduce((a, b) => a + b),
        5,
      );
      await tester.ensureVisible(find.byType(PieChart));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PieChart>(find.byType(PieChart))
            .data
            .sections
            .single
            .value,
        500,
      );
      await tester.ensureVisible(find.text('Food & Drinks').first);
      await tester.tap(find.text('Food & Drinks').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PieChart>(find.byType(PieChart))
            .data
            .sections
            .single
            .radius,
        29,
      );
      await tester.ensureVisible(find.text('Spending Insights'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your average expense is EUR 5.00.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Shared store changes update totals, deletion and period empty states',
    (tester) async {
      final store = ExpenseStore();
      addTearDown(store.dispose);
      final first = record(1000, now);
      store.add(first);
      await mount(tester, store);
      store.add(record(2000, now));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('analytics-total'))).data,
        'USD 30.00',
      );
      store.update(first.id, record(4000, now));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('analytics-total'))).data,
        'USD 60.00',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Last Month'));
      await tester.pumpAndSettle();
      expect(find.text('No expenses for this period'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
      for (final expense in store.expenses) {
        store.delete(expense.id);
      }
      await tester.pumpAndSettle();
      expect(find.text('No spending data yet'), findsOneWidget);
      expect(find.text('Scan Receipt'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Tiny and large amounts render without chart or text overflow', (
    tester,
  ) async {
    final store = ExpenseStore();
    addTearDown(store.dispose);
    store.add(record(1, now));
    await mount(tester, store);
    await tester.ensureVisible(find.byType(BarChart));
    await tester.pumpAndSettle();
    final tiny = tester.widget<BarChart>(find.byType(BarChart));
    expect(tiny.data.maxY, .04);
    store.add(record(99999999999, now, category: 'Entertainment'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(PieChart));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PieChart>(find.byType(PieChart)).data.sections.length,
      2,
    );
    await tester.ensureVisible(find.text('Top spending categories'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
