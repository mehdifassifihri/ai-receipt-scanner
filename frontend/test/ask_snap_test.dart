import 'dart:async';
import 'dart:convert';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/models/receipt_details.dart';
import 'package:ai_receipt_scanner/screens/ask_snap_screen.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> reply() => {
  'answer': 'CAD 20.00 across 1 saved expense(s).',
  'scope': '2026-10-01 to 2026-10-20 · CAD · Saved expenses only',
  'matched_count': 1,
  'suggestions': <String>[],
  'references': [
    {
      'id': 'expense-1',
      'merchant': 'Circle K',
      'transaction_date': '2019-02-18',
      'amount_in_cents': 2000,
      'currency': 'CAD',
      'category': 'Food & Drinks',
    },
  ],
};
http.Response response(Object json, [int status = 200]) => http.Response(
  jsonEncode(json),
  status,
  headers: {'content-type': 'application/json'},
);
ExpenseStore storeFor(Future<http.Response> Function(http.Request) handler) =>
    ExpenseStore(
      api: BackendApi(
        baseUrl: 'https://example.test',
        accessToken: () async => 'user-token',
        client: MockClient(handler),
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
        theme: ThemeData(useMaterial3: true),
        home: const AskSnapScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Messages stay above suggestions and composer with the keyboard open',
    (tester) async {
      final store = storeFor(
        (_) async => response({
          ...reply(),
          'answer': List.filled(30, 'Your spending summary.').join(' '),
          'suggestions': ['Find my largest expenses'],
        }),
      );
      await mount(tester, store);
      await tester.enterText(find.byType(TextField), 'Show my spending');
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final messages = find.byType(ListView).first;
      void expectSeparateViewports() {
        expect(
          tester.getBottomLeft(messages).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
        );
        expect(tester.takeException(), isNull);
      }

      expectSeparateViewports();
      expect(
        tester.getBottomLeft(messages).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Largest expenses')).dy),
      );
      await tester.ensureVisible(find.text('Circle K'));
      await tester.pumpAndSettle();
      expect(find.text('Circle K').hitTestable(), findsOneWidget);
      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(
        find.byType(TextField),
        'One line\nAnother line\nAnd another',
      );
      await tester.pumpAndSettle();
      expectSeparateViewports();
      await tester.ensureVisible(find.text('Circle K'));
      await tester.pumpAndSettle();
      expect(find.text('Circle K').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets(
    'Question uses user auth, renders verified scope, opens an authoritative expense, and preserves bounded context',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final store = storeFor((r) async {
        expect(r.headers['Authorization'], 'Bearer user-token');
        if (r.method == 'GET') {
          expect(r.url.path, '/v1/expenses/expense-1');
          return response({
            'id': 'expense-1',
            'receipt_id': null,
            'merchant': 'Circle K',
            'transaction_date': '2019-02-18',
            'amount_in_cents': 2000,
            'currency': 'CAD',
            'category': 'Food & Drinks',
          });
        }
        expect(r.url.path, '/v1/ask-snap');
        requests.add(jsonDecode(r.body) as Map<String, dynamic>);
        return response(reply());
      });
      await mount(tester, store);
      await tester.enterText(find.byType(TextField), 'How much did I spend?');
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(find.text('CAD 20.00 across 1 saved expense(s).'), findsOneWidget);
      expect(find.textContaining('Saved expenses only'), findsOneWidget);
      expect(requests.single['history'], isEmpty);
      await tester.ensureVisible(find.text('Circle K'));
      await tester.tap(find.text('Circle K'));
      await tester.pumpAndSettle();
      expect(find.text('Expense details'), findsOneWidget);
      expect(store.expenses.single.details.amountInCents, 2000);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'And last month?');
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect((requests.last['history'] as List).length, 2);
      expect((requests.last['history'] as List).first['role'], 'user');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets(
    'One question at a time, provider errors can retry without duplicating the user message',
    (tester) async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final store = storeFor((r) async {
        calls++;
        if (calls == 1) return pending.future;
        return response(reply());
      });
      await mount(tester, store);
      await tester.enterText(find.byType(TextField), 'Find receipts');
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Send question',
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete(
        response({
          'error': {'message': 'Please retry later'},
        }, 503),
      );
      await tester.pumpAndSettle();
      expect(find.text('Please retry later'), findsOneWidget);
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Find receipts'), findsOneWidget);
      expect(find.text('CAD 20.00 across 1 saved expense(s).'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets(
    'Disconnected preview cannot send sample expenses and input handles the keyboard on narrow phones',
    (tester) async {
      final store = ExpenseStore();
      store.add(SavedReceiptExpense(details: ReceiptDetails.mock()));
      await mount(tester, store);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.scrollUntilVisible(
        find.textContaining('Sample expenses are never sent'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Sample expenses are never sent'),
        findsOneWidget,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
