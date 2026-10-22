import 'dart:async';
import 'dart:convert';
import 'package:ai_receipt_scanner/data/app_connection.dart';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/screens/home_shell.dart';
import 'package:ai_receipt_scanner/services/auth/session_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String jwt(String owner, {bool expired = false}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': owner, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + (expired ? -120 : 3600)})}.test';
}

Map<String, dynamic> session(String owner, {bool expired = false}) => {
  'access_token': jwt(owner, expired: expired),
  'refresh_token': 'refresh-$owner',
  'token_type': 'bearer',
  'expires_in': expired ? -120 : 3600,
  'user': {
    'id': owner,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': '$owner@example.com',
    'app_metadata': <String, dynamic>{},
    'user_metadata': {'first_name': owner},
    'created_at': '2026-01-01T00:00:00Z',
  },
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
BackendApi emptyApi(String url, Future<String> Function() token) => BackendApi(
  baseUrl: url,
  accessToken: token,
  client: MockClient((_) async => response({'items': [], 'total': 0})),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Poppins');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await fonts.load();
  });
  test(
    'Concurrent token requests share SDK refresh and reject revoked or switched sessions',
    () async {
      final refreshed = Completer<http.Response>();
      var requests = 0;
      final auth = GoTrueClient(
        url: 'https://auth.test',
        autoRefreshToken: false,
        httpClient: MockClient((_) {
          requests++;
          return refreshed.future;
        }),
      );
      addTearDown(auth.dispose);
      await auth.setInitialSession(jsonEncode(session('alex', expired: true)));
      final access = SessionAccess(auth, 'alex');
      final one = access.token();
      final two = access.token();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      refreshed.complete(response(session('alex')));
      expect(await one, jwt('alex'));
      expect(await two, jwt('alex'));
      await auth.setInitialSession(jsonEncode(session('sam')));
      await expectLater(access.token(), throwsA(isA<ApiException>()));
      expect(await SessionAccess(auth, 'sam').token(), jwt('sam'));
    },
  );
  test('Rejected refresh clears SDK session and exposes safe error', () async {
    final auth = GoTrueClient(
      url: 'https://auth.test',
      autoRefreshToken: false,
      httpClient: MockClient(
        (_) async => response({
          'msg': 'Revoked refresh token',
          'code': 'refresh_token_not_found',
        }, 400),
      ),
    );
    addTearDown(auth.dispose);
    await auth.setInitialSession(jsonEncode(session('alex', expired: true)));
    await expectLater(
      SessionAccess(auth, 'alex').token(),
      throwsA(isA<ApiException>()),
    );
    expect(auth.currentSession, isNull);
  });
  testWidgets('Expired startup never reveals protected Home before renewal', (
    tester,
  ) async {
    final refreshed = Completer<http.Response>();
    final auth = GoTrueClient(
      url: 'https://auth.test',
      autoRefreshToken: false,
      httpClient: MockClient((_) => refreshed.future),
    );
    await auth.setInitialSession(jsonEncode(session('alex', expired: true)));
    await tester.pumpWidget(
      AppConnection(
        baseUrl: 'https://api.test',
        auth: auth,
        apiFactory: emptyApi,
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byType(HomeShell), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    refreshed.complete(response(session('alex')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Welcome back, Alex'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets(
    'Logout resets private route history and a new account starts with fresh navigation',
    (tester) async {
      final auth = GoTrueClient(
        url: 'https://auth.test',
        autoRefreshToken: false,
        httpClient: MockClient((_) async => http.Response('', 204)),
      );
      await auth.setInitialSession(jsonEncode(session('alex')));
      await tester.pumpWidget(
        AppConnection(
          baseUrl: 'https://api.test',
          auth: auth,
          apiFactory: emptyApi,
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        Navigator.of(tester.element(find.byType(HomeShell))).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('Private account A route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private account A route'), findsOneWidget);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Private account A route'), findsNothing);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('Welcome\nback'), findsOneWidget);
      await auth.setInitialSession(jsonEncode(session('sam')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back, Sam'), findsOneWidget);
      expect(find.text('Private account A route'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
}
