// Physical-device profiling only. No backend, Supabase or paid AI calls.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_receipt_scanner/app.dart';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _GlassProfileApp());
}

class _GlassProfileApp extends StatefulWidget {
  const _GlassProfileApp();
  @override
  State<_GlassProfileApp> createState() => _GlassProfileAppState();
}

class _GlassProfileAppState extends State<_GlassProfileApp> {
  late final _store = ExpenseStore(
    api: BackendApi(
      baseUrl: 'https://profile.invalid',
      accessToken: () async => 'synthetic-profile-token',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/ask-snap')) {
          return http.Response(
            jsonEncode({
              'answer':
                  'Profile fixture: CAD 10.60 in saved expenses. This is synthetic text for measuring scrolling, keyboard and glass controls.',
              'scope': 'Synthetic profile fixture only',
              'references': [],
              'matched_count': 1,
              'suggestions': [
                'Show my spending',
                'Find my largest expense',
                'Compare last month',
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/expenses')) {
          return http.Response('{"items":[],"total":0}', 200);
        }
        return http.Response(
          '{"error":{"message":"Profile fixture: this server action is disabled."}}',
          501,
        );
      }),
    ),
  );
  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Banner(
    message: 'PROFILE FIXTURE',
    location: BannerLocation.topEnd,
    textDirection: TextDirection.ltr,
    child: SnapExpenseApp(store: _store),
  );
}
