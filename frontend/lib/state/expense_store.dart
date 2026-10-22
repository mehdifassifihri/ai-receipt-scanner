import 'package:flutter/material.dart';
import '../data/backend_api.dart';
import '../models/receipt_details.dart';
import '../models/receipt_selection.dart';
import '../services/analytics_report.dart';

/// Server-backed when an API is supplied; isolated local mode supports previews.
class ExpenseStore extends ChangeNotifier {
  ExpenseStore({this.api});
  final BackendApi? api;
  bool get connected => api != null;
  final List<SavedReceiptExpense> _expenses = [];
  List<SavedReceiptExpense>? _snapshot;
  List<SavedReceiptExpense> get expenses =>
      _snapshot ??= List.unmodifiable(_expenses);
  final _reports = <(AnalyticsPeriod, String, DateTime), AnalyticsReport>{};

  /// Évite de retrier et recalculer le même rapport à chaque rebuild du widget.
  AnalyticsReport report({
    required AnalyticsPeriod period,
    required String currency,
    required DateTime now,
  }) {
    final key = (period, currency, analyticsDay(now));
    if (_reports.length >= 16 && !_reports.containsKey(key)) _reports.clear();
    return _reports.putIfAbsent(
      key,
      () => calculateAnalytics(
        expenses,
        period: period,
        currency: currency,
        now: now,
      ),
    );
  }

  bool loading = false;
  String? error;
  bool _disposed = false;
  bool _sessionActive = true;
  bool get active => !_disposed && _sessionActive;
  Future<void>? _refresh;
  int _revision = 0;
  int get revision => _revision;
  void _notify() {
    _snapshot = null;
    _reports.clear();
    if (active) notifyListeners();
  }

  /// Coupe immédiatement l’ancien compte avant que son arbre soit démonté.
  void invalidateSession() {
    _sessionActive = false;
    api?.close();
    _expenses.clear();
    _snapshot = null;
    _reports.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    invalidateSession();
    super.dispose();
  }

  Future<void> refresh() => !active
      ? Future.value()
      : _refresh ??= _load().whenComplete(() => _refresh = null);
  Future<void> _load() async {
    if (api == null) return;
    loading = true;
    error = null;
    _notify();
    final revision = _revision;
    try {
      final entries = await api!.expenses();
      if (!active) return;
      // Do not overwrite a write that finished while this snapshot was loading.
      if (revision == _revision) {
        _expenses
          ..clear()
          ..addAll(entries);
        _revision++;
      }
    } catch (e) {
      if (active) error = apiErrorMessage(e);
    } finally {
      loading = false;
      _notify();
    }
  }

  SavedReceiptExpense? find(String id) {
    for (final expense in _expenses) {
      if (expense.id == id) return expense;
    }
    return null;
  }

  bool update(String id, SavedReceiptExpense expense) {
    if (!active) return false;
    final index = _expenses.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    _expenses[index] = SavedReceiptExpense(
      id: id,
      details: expense.details,
      receipt: expense.receipt,
      receiptId: expense.receiptId ?? _expenses[index].receiptId,
    );
    _revision++;
    _notify();
    return true;
  }

  void delete(String id) {
    if (!active) return;
    _expenses.removeWhere((e) => e.id == id);
    _revision++;
    _notify();
  }

  void add(SavedReceiptExpense expense) {
    if (!active) return;
    _expenses.insert(0, expense);
    _revision++;
    _notify();
  }

  Future<void> persist(
    SavedReceiptExpense expense, {
    String? id,
    required String key,
  }) async {
    if (!active) throw const ApiException('Please sign in again.', status: 401);
    final saved = api == null
        ? expense
        : await api!.save(expense, id: id, key: key);
    if (!active) return;
    if (id != null) {
      if (!update(id, saved)) {
        throw const ApiException('This expense is no longer available.');
      }
    } else {
      // A retried idempotent create can return an already loaded entry.
      _expenses.removeWhere((e) => e.id == saved.id);
      add(saved);
    }
  }

  Future<SavedReceiptExpense> loadExpense(String id) async {
    if (!active || api == null) {
      throw const ApiException('Please sign in again.', status: 401);
    }
    final expense = await api!.expense(id);
    if (!active) throw const ApiException('Please sign in again.', status: 401);
    if (find(expense.id) == null) {
      add(expense);
    } else {
      update(expense.id, expense);
    }
    return expense;
  }

  Future<void> remove(String id) async {
    if (!active) throw const ApiException('Please sign in again.', status: 401);
    if (api != null) await api!.request('DELETE', '/expenses/$id');
    if (active) delete(id);
  }

  Future<ReceiptSelection?> receiptImage(SavedReceiptExpense expense) async =>
      expense.receipt ??
      (expense.receiptId != null && api != null
          ? await api!.image(expense.receiptId!)
          : null);
}

class ExpenseScope extends InheritedNotifier<ExpenseStore> {
  const ExpenseScope({
    super.key,
    required ExpenseStore store,
    required super.child,
  }) : super(notifier: store);
  static ExpenseStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ExpenseScope>()!.notifier!;
}
