import 'dart:convert';
import 'package:ai_receipt_scanner/data/app_connection.dart';
import 'package:ai_receipt_scanner/screens/password_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <http.Request>[];
  var reject = false;
  final user = {
    'id': '11111111-1111-4111-8111-111111111111',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'alex@example.com',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
  };
  setUp(() async {
    calls.clear();
    reject = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
      debug: false,
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: _MemoryAuthStorage(),
        persistSession: false,
        detectSessionInUri: false,
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: MockClient((request) async {
        calls.add(request);
        if (reject) {
          return http.Response(
            jsonEncode({
              'msg': 'Recovery is temporarily unavailable',
              'code': 'rate_limit',
            }),
            429,
          );
        }
        if (request.url.path.endsWith('/verify')) {
          return http.Response(
            jsonEncode({
              'access_token': 'test-access-token',
              'refresh_token': 'test-refresh-token',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': user,
            }),
            200,
          );
        }
        if (request.method == 'PUT') {
          return http.Response(jsonEncode(user), 200);
        }
        if (request.url.path.endsWith('/logout')) return http.Response('', 204);
        return http.Response('{}', 200);
      }),
    );
  });
  tearDown(() async => Supabase.instance.dispose());
  testWidgets(
    'Recovery sends email and redirects to the mobile callback without exposing account existence',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PasswordRecoveryScreen(initialEmail: 'alex@example.com'),
        ),
      );
      await tester.ensureVisible(find.text('Send reset link'));
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(calls.single.url.path, '/auth/v1/recover');
      expect(
        calls.single.url.queryParameters['redirect_to'],
        passwordRecoveryRedirect,
      );
      expect(jsonDecode(calls.single.body)['email'], 'alex@example.com');
      expect(find.text('Check your inbox.'), findsOneWidget);
      expect(find.textContaining('If an account exists'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Recovery provider errors preserve the form for retry', (
    tester,
  ) async {
    reject = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: PasswordRecoveryScreen(initialEmail: 'alex@example.com'),
      ),
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Recovery is temporarily unavailable'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Recovery session opens new password page, updates password, and returns to signed-out login',
    (tester) async {
      await tester.pumpWidget(
        const AppConnection(baseUrl: 'https://api.example.test'),
      );
      await tester.pumpAndSettle();
      await Supabase.instance.client.auth.verifyOTP(
        tokenHash: 'test-recovery-hash',
        type: OtpType.recovery,
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose a new password'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'new-secure-password',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'different-password',
      );
      await tester.ensureVisible(find.text('Update password'));
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords must match'), findsOneWidget);
      expect(calls.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'new-secure-password',
      );
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(
          calls.singleWhere((r) => r.method == 'PUT').body,
        )['password'],
        'new-secure-password',
      );
      expect(find.text('You’re all set.'), findsOneWidget);
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(Supabase.instance.client.auth.currentSession, isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Welcome\nback'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _MemoryAuthStorage extends GotrueAsyncStorage {
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
