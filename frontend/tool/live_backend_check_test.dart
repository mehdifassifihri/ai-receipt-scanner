// Opt-in only. Run through backend/scripts/live_flutter_check.py.
import 'dart:io';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/models/receipt_details.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RealNetwork extends HttpOverrides {}

class _MemoryStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

void main() {
  testWidgets(
    'Live Flutter client authenticates and reloads durable expenses after discarding all local store state',
    (tester) async {
      const email = String.fromEnvironment('LIVE_TEST_EMAIL');
      const password = String.fromEnvironment('LIVE_TEST_PASSWORD');
      expect(
        email.isNotEmpty && password.isNotEmpty,
        isTrue,
        reason: 'Run via the disposable-user backend helper.',
      );
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          await Supabase.initialize(
            url: const String.fromEnvironment('SUPABASE_URL'),
            publishableKey: const String.fromEnvironment(
              'SUPABASE_PUBLISHABLE_KEY',
            ),
            debug: false,
            authOptions: FlutterAuthClientOptions(
              persistSession: false,
              detectSessionInUri: false,
              autoRefreshToken: false,
              pkceAsyncStorage: _MemoryStorage(),
            ),
          );
          ExpenseStore? store;
          ExpenseStore freshStore() => ExpenseStore(
            api: BackendApi(
              baseUrl: const String.fromEnvironment('API_BASE_URL'),
              accessToken: () async =>
                  Supabase.instance.client.auth.currentSession!.accessToken,
            ),
          );
          try {
            final auth = Supabase.instance.client.auth;
            await auth.signInWithPassword(email: email, password: password);
            expect(auth.currentSession, isNotNull);
            store = freshStore();
            final details = ReceiptDetails(
              merchant: 'Flutter Live Smoke Test',
              date: DateTime.now().toUtc(),
              amountInCents: 12345,
              currency: 'MAD',
              category: 'Groceries',
            );
            await store.persist(
              SavedReceiptExpense(details: details),
              key: BackendApi.newKey(),
            );
            final id = store.expenses.single.id;
            store.dispose();
            store = null;
            // Discard notifier and HTTP client, sign out, then establish a new session.
            await auth.signOut(scope: SignOutScope.local);
            await auth.signInWithPassword(email: email, password: password);
            store = freshStore();
            expect(store.expenses, isEmpty);
            await store.refresh();
            expect(store.error, isNull);
            expect(store.find(id)?.details.amountInCents, 12345);
            await store.persist(
              SavedReceiptExpense(
                details: ReceiptDetails(
                  merchant: details.merchant,
                  date: details.date,
                  amountInCents: 12500,
                  currency: 'MAD',
                  category: 'Groceries',
                ),
              ),
              id: id,
              key: BackendApi.newKey(),
            );
            store.dispose();
            store = freshStore();
            await store.refresh();
            expect(store.error, isNull);
            expect(store.find(id)?.details.amountInCents, 12500);
            await store.remove(id);
            store.dispose();
            store = freshStore();
            await store.refresh();
            expect(store.error, isNull);
            expect(store.expenses, isEmpty);
            await auth.signOut(scope: SignOutScope.local);
            expect(auth.currentSession, isNull);
          } finally {
            store?.dispose();
            await Supabase.instance.dispose();
          }
        }, _RealNetwork()),
      );
    },
  );
}
