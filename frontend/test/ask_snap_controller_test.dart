import 'dart:async';
import 'dart:convert';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/state/ask_snap_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply() => http.Response(
  jsonEncode({
    'answer': 'CAD 20.00',
    'scope': 'Saved expenses',
    'references': [],
    'matched_count': 1,
    'suggestions': [],
  }),
  200,
);
void main() {
  test(
    'Conversation is bounded, history is bounded, and clear preserves selected currency',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final api = BackendApi(
        baseUrl: 'https://api.test',
        accessToken: () async => 'test',
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return reply();
        }),
      );
      final chat = AskSnapController(api)..selectCurrency('CAD');
      for (var i = 0; i < 23; i++) {
        await chat.send('Question $i');
      }
      expect(chat.exchanges.length, 20);
      expect(chat.exchanges.first.question, 'Question 3');
      expect(bodies.last['history'].length, 6);
      expect(bodies.last['currency'], 'CAD');
      chat.clear();
      expect(chat.exchanges, isEmpty);
      expect(chat.currency, 'CAD');
      chat.dispose();
      api.close();
    },
  );
  test(
    'Duplicate calls are ignored and disposal discards a late model response',
    () async {
      final result = Completer<http.Response>();
      var calls = 0, notifications = 0;
      final api = BackendApi(
        baseUrl: 'https://api.test',
        accessToken: () async => 'test',
        client: MockClient((_) {
          calls++;
          return result.future;
        }),
      );
      final chat = AskSnapController(api)..addListener(() => notifications++);
      final sending = chat.send('Total?');
      await chat.send('Duplicate?');
      chat.clear();
      chat.selectCurrency('USD');
      expect(chat.exchanges.length, 1);
      expect(chat.currency, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      chat.dispose();
      result.complete(reply());
      await sending;
      expect(chat.exchanges, isEmpty);
      expect(notifications, 1);
      api.close();
    },
  );
}
