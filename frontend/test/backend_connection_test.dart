import 'dart:convert';
import 'dart:typed_data';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/models/receipt_selection.dart';
import 'package:ai_receipt_scanner/screens/receipt_extraction_screen.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:ai_receipt_scanner/services/analytics_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> row(String id) => {
  'id': id,
  'receipt_id': 'receipt-1',
  'merchant': 'Local Market',
  'transaction_date': '2026-01-12',
  'amount_in_cents': 12345,
  'currency': 'MAD',
  'category': 'Groceries',
};
BackendApi apiFor(Future<http.Response> Function(http.Request) handler) =>
    BackendApi(
      baseUrl: 'https://api.example.test',
      accessToken: () async => 'user-session',
      client: MockClient(handler),
    );
http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'Loads every page with user auth and maps exact integer money',
    () async {
      final api = apiFor((request) async {
        expect(request.headers['Authorization'], 'Bearer user-session');
        expect(request.url.queryParameters['limit'], '100');
        final offset = int.parse(request.url.queryParameters['offset']!);
        return jsonResponse({
          'items': [
            for (var i = offset; i < (offset == 0 ? 100 : 101); i++) row('$i'),
          ],
          'total': 101,
        });
      });
      final store = ExpenseStore(api: api);
      await store.refresh();
      expect(store.error, isNull);
      expect(store.expenses.length, 101);
      expect(store.expenses.last.details.amountInCents, 12345);
      expect(store.expenses.last.receiptId, 'receipt-1');
      store.dispose();
    },
  );

  test(
    'Failed save preserves state; identical retry reuses request key; failed delete retains expense',
    () async {
      var attempts = 0;
      final keys = <String?>[];
      final api = apiFor((request) async {
        if (request.method == 'DELETE') {
          return jsonResponse({
            'error': {'message': 'Delete unavailable'},
          }, 503);
        }
        keys.add(request.headers['Idempotency-Key']);
        expect(jsonDecode(request.body)['amount_in_cents'], 12345);
        attempts++;
        return attempts == 1
            ? jsonResponse({
                'error': {'message': 'Try again'},
              }, 503)
            : jsonResponse(row('saved-1'), 201);
      });
      final store = ExpenseStore(api: api);
      final expense = BackendApi.decodeExpense(row('local'));
      final key = BackendApi.newKey();
      await expectLater(
        store.persist(expense, key: key),
        throwsA(isA<ApiException>()),
      );
      expect(store.expenses, isEmpty);
      await store.persist(expense, key: key);
      expect(keys, [key, key]);
      expect(store.expenses.single.id, 'saved-1');
      await expectLater(store.remove('saved-1'), throwsA(isA<ApiException>()));
      expect(store.expenses.length, 1);
      store.dispose();
    },
  );

  test(
    'Refresh errors retain previously loaded data and expose retry state',
    () async {
      var fail = false;
      final store = ExpenseStore(
        api: apiFor(
          (request) async => fail
              ? jsonResponse({
                  'error': {'message': 'Session expired'},
                }, 401)
              : jsonResponse({
                  'items': [row('saved')],
                  'total': 1,
                }),
        ),
      );
      await store.refresh();
      fail = true;
      await store.refresh();
      expect(store.error, 'Session expired');
      expect(store.loading, isFalse);
      expect(store.expenses.single.id, 'saved');
      store.dispose();
    },
  );

  test(
    'Upload rejects unsupported files before making an HTTP request',
    () async {
      final api = apiFor((_) async {
        fail('Unsupported file must not be sent');
      });
      await expectLater(
        api.upload(ReceiptSelection.fromBytes(Uint8List.fromList([1, 2, 3]))),
        throwsA(isA<ApiException>()),
      );
      api.close();
    },
  );

  test(
    'Analytics maps server ranges, currencies, categories and buckets',
    () async {
      final api = apiFor((request) async {
        expect(request.url.queryParameters, {
          'period': 'this_month',
          'currency': 'MAD',
        });
        return jsonResponse({
          'date_range': {'start': '2026-01-01', 'end_exclusive': '2026-01-13'},
          'total_in_cents': 12345,
          'previous_total_in_cents': 10000,
          'transaction_count': 1,
          'categories': [
            {
              'category': 'Groceries',
              'amount_in_cents': 12345,
              'percentage': 100,
            },
          ],
          'buckets': [
            {
              'start': '2026-01-12',
              'end_exclusive': '2026-01-13',
              'amount_in_cents': 12345,
            },
          ],
        });
      });
      final report = await api.analytics(AnalyticsPeriod.thisMonth, 'MAD');
      expect(report.totalInCents, 12345);
      expect(report.categories.single.share, 1);
      expect(report.range.days, 12);
      expect(report.buckets.single.amountInCents, 12345);
      api.close();
    },
  );

  testWidgets(
    'Upload and extraction populate review; expense is created only after confirmation',
    (tester) async {
      final calls = <String>[];
      final image = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aJ1kAAAAASUVORK5CYII=',
        ),
      );
      final api = apiFor((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/v1/receipts') {
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data'),
          );
          return jsonResponse({'id': 'receipt-1'}, 201);
        }
        if (request.url.path.endsWith('/extract')) {
          return jsonResponse({
            'job': {
              'status': 'completed',
              'result': {
                'fields': {
                  'merchant': 'Local Market',
                  'transaction_date': '2026-01-12',
                  'amount_in_cents': 12345,
                  'currency': 'MAD',
                  'category': 'Groceries',
                },
                'warnings': ['Verify the total.'],
                'requires_review': true,
              },
            },
            'cached': false,
          });
        }
        expect(request.url.path, '/v1/expenses');
        expect(jsonDecode(request.body)['receipt_id'], 'receipt-1');
        return jsonResponse(row('saved-1'), 201);
      });
      final store = ExpenseStore(api: api);
      await tester.pumpWidget(
        ExpenseScope(
          store: store,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReceiptExtractionScreen(
                        receipt: ReceiptSelection.fromBytes(image),
                        api: api,
                      ),
                    ),
                  ),
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt details ready for review'), findsOneWidget);
      expect(find.text('Local Market'), findsOneWidget);
      expect(find.text('123.45'), findsOneWidget);
      expect(calls, [
        'POST /v1/receipts',
        'POST /v1/receipts/receipt-1/extract',
      ]);
      expect(store.expenses, isEmpty);
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();
      expect(store.expenses.single.details.currency, 'MAD');
      expect(store.expenses.single.receiptId, 'receipt-1');
      expect(calls.last, 'POST /v1/expenses');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
