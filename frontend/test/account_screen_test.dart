import 'dart:convert';
import 'package:ai_receipt_scanner/screens/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var reject = false;
  var signup = false;
  Map<String, dynamic>? credentials;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    reject = false;
    signup = false;
    credentials = null;
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        detectSessionInUri: false,
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: MockClient((request) async {
        credentials = jsonDecode(request.body) as Map<String, dynamic>;
        signup = request.url.path.endsWith('/signup');
        if (reject) {
          return http.Response(
            jsonEncode({
              'msg': 'Invalid login credentials',
              'code': 'invalid_credentials',
            }),
            400,
          );
        }
        final user = {
          'id': '11111111-1111-4111-8111-111111111111',
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'alex@example.com',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        };
        return http.Response(
          jsonEncode(
            signup
                ? user
                : {
                    'access_token': 'test-access-token',
                    'refresh_token': 'test-refresh-token',
                    'token_type': 'bearer',
                    'expires_in': 3600,
                    'user': user,
                  },
          ),
          200,
        );
      }),
    );
  });
  tearDown(() async => Supabase.instance.dispose());

  Future<void> fill(WidgetTester tester, {int offset = 0}) async {
    await tester.enterText(
      find.byType(TextFormField).at(offset),
      'alex@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(offset + 1),
      'test-password',
    );
  }

  testWidgets('Signs in with Supabase and receives a user session', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await fill(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(credentials!['email'], 'alex@example.com');
    expect(
      Supabase.instance.client.auth.currentSession?.user.email,
      'alex@example.com',
    );
    expect(signup, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Invalid login keeps the form and shows the provider error', (
    tester,
  ) async {
    reject = true;
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await fill(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid login credentials'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Signup without a session asks for email confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await tester.ensureVisible(find.text('Sign up here'));
    await tester.tap(find.text('Sign up here'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'alex');
    await tester.enterText(find.byType(TextFormField).at(1), 'MORGAN');
    await fill(tester, offset: 2);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(signup, isTrue);
    expect(credentials!['data']['first_name'], 'alex');
    expect(credentials!['data']['full_name'], 'alex MORGAN');
    expect(
      find.text('Check your email to confirm your account, then sign in.'),
      findsOneWidget,
    );
    expect(Supabase.instance.client.auth.currentSession, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Registration requires a first name and returns to login on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
      await tester.enterText(
        find.byType(TextFormField).first,
        'alex@example.com',
      );
      await tester.ensureVisible(find.text('Sign up here'));
      await tester.tap(find.text('Sign up here'));
      await tester.pumpAndSettle();
      await fill(tester, offset: 2);
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Create account'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your first name'), findsOneWidget);
      expect(credentials, isNull);
      await tester.ensureVisible(find.text('Log in here'));
      await tester.tap(find.text('Log in here'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome\nback'), findsOneWidget);
      expect(find.text('alex@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
