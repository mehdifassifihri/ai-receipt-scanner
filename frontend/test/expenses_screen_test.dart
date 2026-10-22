import 'package:ai_receipt_scanner/models/receipt_details.dart';
import 'package:ai_receipt_scanner/screens/expenses_screen.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
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

  Future<void> mount(WidgetTester tester, ExpenseStore store) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ExpenseScope(
        store: store,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Poppins',
            scaffoldBackgroundColor: const Color(0xFFF6F7F4),
          ),
          home: const ExpensesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SavedReceiptExpense expense(
    String merchant,
    String category,
    int cents,
    String currency,
    DateTime date,
  ) => SavedReceiptExpense(
    details: ReceiptDetails(
      merchant: merchant,
      category: category,
      amountInCents: cents,
      currency: currency,
      date: date,
    ),
  );

  testWidgets('Search and category combine; currency totals never combine', (
    tester,
  ) async {
    final store = ExpenseStore();
    addTearDown(store.dispose);
    final now = DateTime.now();
    store.add(expense('Starbucks', 'Food & Drinks', 2450, 'USD', now));
    store.add(expense('Carrefour', 'Groceries', 4580, 'USD', now));
    store.add(
      expense(
        'Amazon',
        'Shopping',
        8999,
        'EUR',
        DateTime(now.year, now.month, now.day - 1),
      ),
    );
    store.add(
      expense(
        'Old Coffee',
        'Food & Drinks',
        1000,
        'USD',
        DateTime(now.year, now.month - 1, 10),
      ),
    );
    await mount(tester, store);
    expect(find.text('USD 70.30'), findsOneWidget);
    expect(find.text('4 saved expenses · this session'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'STAR');
    await tester.pumpAndSettle();
    expect(find.text('Starbucks'), findsOneWidget);
    expect(find.text('Carrefour'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Shopping'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('No matching expenses'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No matching expenses'), findsOneWidget);
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Starbucks'),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Starbucks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editing preserves identity and deleting needs confirmation', (
    tester,
  ) async {
    final store = ExpenseStore();
    addTearDown(store.dispose);
    final original = expense(
      'Starbucks',
      'Food & Drinks',
      2450,
      'USD',
      DateTime.now(),
    );
    store.add(original);
    await mount(tester, store);
    await tester.scrollUntilVisible(
      find.text('Starbucks'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Starbucks'));
    await tester.pumpAndSettle();
    expect(find.text('Expense details'), findsOneWidget);
    await tester.tap(find.text('Edit Expense'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Expense'), findsOneWidget);
    expect(find.text('Demo details ready for review'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('merchant')));
    await tester.enterText(
      find.byKey(const ValueKey('merchant')),
      'Updated Coffee Shop',
    );
    await tester.enterText(find.byKey(const ValueKey('amount')), '40.00');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(store.expenses.length, 1);
    expect(store.expenses.single.id, original.id);
    expect(store.expenses.single.details.amountInCents, 4000);
    expect(find.text('Updated Coffee Shop'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 saved expenses · this session'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('USD 40.00'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Updated Coffee Shop'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Updated Coffee Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.expenses.length, 1);
    await tester.tap(find.text('Delete Expense'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This action cannot be undone.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.expenses, isEmpty);
    await tester.scrollUntilVisible(
      find.text('No expenses yet'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No expenses yet'), findsOneWidget);
    expect(find.text('USD 0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Demo data is opt-in and isolated from user expenses', (
    tester,
  ) async {
    final store = ExpenseStore();
    addTearDown(store.dispose);
    await mount(tester, store);
    await tester.scrollUntilVisible(
      find.text('View demo expenses'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View demo expenses'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('DEMO DATA'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('DEMO DATA'), findsOneWidget);
    expect(store.expenses, isEmpty);
    await tester.tap(find.text('Return to my expenses'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('No expenses yet'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No expenses yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
