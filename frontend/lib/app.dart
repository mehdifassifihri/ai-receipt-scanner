import 'package:flutter/material.dart';
import 'screens/launch_screen.dart';
import 'state/expense_store.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_accessibility.dart';

class SnapExpenseApp extends StatefulWidget {
  const SnapExpenseApp({super.key, this.store, this.destination});
  final ExpenseStore? store;
  final Widget? destination;

  @override
  State<SnapExpenseApp> createState() => _SnapExpenseAppState();
}

class _SnapExpenseAppState extends State<SnapExpenseApp> {
  late final _expenses = widget.store ?? ExpenseStore();
  @override
  void dispose() {
    if (widget.store == null) _expenses.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpenseScope(
    store: _expenses,
    child: MaterialApp(
      title: 'SnapExpense AI',
      debugShowCheckedModeBanner: false,
      theme: snapExpenseTheme(),
      builder: (context, child) =>
          GlassAccessibility(child: child ?? const SizedBox.shrink()),
      home: LaunchScreen(destination: widget.destination),
    ),
  );
}
