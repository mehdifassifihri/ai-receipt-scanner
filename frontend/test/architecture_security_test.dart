import 'dart:async';
import 'dart:convert';
import 'package:ai_receipt_scanner/data/app_configuration.dart';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/services/auth/secure_auth_storage.dart';
import 'package:ai_receipt_scanner/services/auth/profile_name.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:ai_receipt_scanner/services/analytics_report.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LegacySession extends LocalStorage {
  String? value;
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<void> persistSession(String persistSessionString) async {
    value = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    value = null;
  }
}

class LegacyPkce extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class FailingStorage extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw PlatformException(code: 'storage-unavailable');
  }
}

Map<String, dynamic> expenseRow(String id) => {
  'id': id,
  'receipt_id': null,
  'merchant': 'Market',
  'transaction_date': '2026-10-01',
  'amount_in_cents': 2000,
  'currency': 'CAD',
  'category': 'Groceries',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'Session and PKCE migrate securely, retain newest value, and logout cannot be overwritten by a pending write',
    () async {
      final legacy = LegacySession()..value = 'legacy-session';
      final pkce = LegacyPkce()..values['verifier'] = 'legacy-verifier';
      final storage = SecureAuthStorage(
        namespace: 'project',
        legacySession: legacy,
        legacyPkce: pkce,
      );
      await storage.initialize();
      expect(await storage.accessToken(), 'legacy-session');
      expect(legacy.value, isNull);
      expect(await storage.getItem(key: 'verifier'), 'legacy-verifier');
      expect(pkce.values, isEmpty);
      await Future.wait([
        storage.persistSession('refreshed-session'),
        storage.removePersistedSession(),
      ]);
      expect(await storage.hasAccessToken(), isFalse);
      await storage.removeItem(key: 'verifier');
      expect(await storage.getItem(key: 'verifier'), isNull);
    },
  );
  test(
    'Failed migration preserves legacy session and never falls back to plaintext writes',
    () async {
      final legacy = LegacySession()..value = 'old-session';
      final storage = SecureAuthStorage(
        namespace: 'project',
        storage: FailingStorage(),
        legacySession: legacy,
        legacyPkce: LegacyPkce(),
      );
      await expectLater(
        storage.initialize(),
        throwsA(isA<PlatformException>()),
      );
      expect(legacy.value, 'old-session');
    },
  );
  test(
    'Existing secure session wins over stale preferences and projects stay isolated',
    () async {
      FlutterSecureStorage.setMockInitialValues({'a.secure-session': 'newest'});
      final legacy = LegacySession()..value = 'stale';
      final a = SecureAuthStorage(
        namespace: 'a',
        legacySession: legacy,
        legacyPkce: LegacyPkce(),
      );
      final b = SecureAuthStorage(
        namespace: 'b',
        legacySession: LegacySession(),
        legacyPkce: LegacyPkce(),
      );
      await a.initialize();
      await b.initialize();
      expect(await a.accessToken(), 'newest');
      expect(await b.accessToken(), isNull);
      expect(legacy.value, isNull);
    },
  );
  test(
    'Production rejects HTTP, URL credentials, and privileged configuration keys',
    () {
      void validate(String api, String key, {bool development = false}) =>
          AppConfiguration.validate(
            supabaseUrl: 'https://project.supabase.co',
            publishableKey: key,
            apiBaseUrl: api,
            allowDevelopmentHttp: development,
          );
      validate('https://api.example.com', 'sb_publishable_test');
      validate(
        'http://127.0.0.1:8000',
        'sb_publishable_test',
        development: true,
      );
      expect(
        () => validate('http://api.example.com', 'sb_publishable_test'),
        throwsFormatException,
      );
      expect(
        () => validate(
          'https://user:password@api.example.com',
          'sb_publishable_test',
        ),
        throwsFormatException,
      );
      expect(
        () => validate('https://api.example.com?key=x', 'sb_publishable_test'),
        throwsFormatException,
      );
      expect(
        () => validate('https://api.example.com', 'sb_secret_test'),
        throwsFormatException,
      );
      final privileged =
          'header.${base64Url.encode(utf8.encode(jsonEncode({'role': 'service_role'})))}.signature';
      expect(AppConfiguration.isPublicKey(privileged), isFalse);
    },
  );
  test(
    'Closed account cannot send after waiting for a token or consume an old response',
    () async {
      final token = Completer<String>();
      var sent = 0;
      final api = BackendApi(
        baseUrl: 'https://api.test',
        accessToken: () => token.future,
        client: MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        }),
      );
      final pending = api.request('GET', '/expenses');
      api.close();
      token.complete('old-token');
      await expectLater(pending, throwsA(isA<ApiException>()));
      expect(sent, 0);
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final other = BackendApi(
        baseUrl: 'https://api.test',
        accessToken: () async => 'old-token',
        client: MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final inFlight = other.request('GET', '/expenses');
      await started.future;
      other.close();
      response.complete(http.Response('{}', 200));
      await expectLater(inFlight, throwsA(isA<ApiException>()));
    },
  );
  test(
    'Pagination rejects changed totals and repeated IDs instead of corrupting totals',
    () async {
      for (final duplicate in [false, true]) {
        var calls = 0;
        final api = BackendApi(
          baseUrl: 'https://api.test',
          accessToken: () async => 'test',
          client: MockClient((_) async {
            calls++;
            return http.Response(
              jsonEncode({
                'items': [expenseRow(duplicate ? 'same' : '$calls')],
                'total': calls == 1 || duplicate ? 2 : 3,
              }),
              200,
            );
          }),
        );
        await expectLater(api.expenses(), throwsA(isA<ApiException>()));
        expect(calls, 2);
        api.close();
      }
    },
  );
  test(
    'Unexpected successful JSON is sanitized and API errors preserve useful messages',
    () async {
      for (final body in ['[]', 'null', '"private stack trace"']) {
        final api = BackendApi(
          baseUrl: 'https://api.test',
          accessToken: () async => 'test',
          client: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(
          api.request('GET', '/expenses'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'safe message',
              'The server returned an unexpected response.',
            ),
          ),
        );
        api.close();
      }
    },
  );
  test(
    'Store invalidation clears account data, ignores late loads and invalidates cached reports',
    () async {
      final result = Completer<http.Response>();
      final store = ExpenseStore(
        api: BackendApi(
          baseUrl: 'https://api.test',
          accessToken: () async => 'test',
          client: MockClient((_) => result.future),
        ),
      );
      store.add(BackendApi.decodeExpense(expenseRow('saved')));
      final before = store.report(
        period: AnalyticsPeriod.thisMonth,
        currency: 'CAD',
        now: DateTime(2026, 10, 20),
      );
      expect(
        identical(
          before,
          store.report(
            period: AnalyticsPeriod.thisMonth,
            currency: 'CAD',
            now: DateTime(2026, 10, 20),
          ),
        ),
        isTrue,
      );
      store.delete('saved');
      expect(
        store
            .report(
              period: AnalyticsPeriod.thisMonth,
              currency: 'CAD',
              now: DateTime(2026, 10, 20),
            )
            .totalInCents,
        0,
      );
      final load = store.refresh();
      store.invalidateSession();
      result.complete(
        http.Response(
          jsonEncode({
            'items': [expenseRow('late')],
            'total': 1,
          }),
          200,
        ),
      );
      await load;
      store.add(BackendApi.decodeExpense(expenseRow('stale')));
      expect(store.expenses, isEmpty);
      expect(store.active, isFalse);
      store.dispose();
    },
  );
  test('Profile greeting retains metadata precedence and safe fallback', () {
    expect(
      profileFirstName({'first_name': ' mEHDI '}, 'other@example.com'),
      'Mehdi',
    );
    expect(profileFirstName({}, 'alex.smith@example.com'), 'Alex');
    expect(profileFirstName(null, null), isNull);
  });
}
