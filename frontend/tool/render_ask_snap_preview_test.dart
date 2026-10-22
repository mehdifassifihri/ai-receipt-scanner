// Run explicitly: flutter test tool/render_ask_snap_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_receipt_scanner/app.dart';
import 'package:ai_receipt_scanner/data/backend_api.dart';
import 'package:ai_receipt_scanner/screens/ask_snap_screen.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Render Ask Snap empty and grounded answer previews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loader = FontLoader('Poppins');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final store = ExpenseStore(
      api: BackendApi(
        baseUrl: 'https://preview.test',
        accessToken: () async => 'preview',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'answer':
                  'Circle K: CAD 20.00, dated 2019-02-18. It falls outside this period, so it is excluded from its total.\n\nTotals use the saved transaction date. Open the expense to review its date if it looks incorrect.',
              'scope': '2026-10-01 to 2026-10-20 · CAD · Saved expenses only',
              'matched_count': 1,
              'suggestions': <String>[],
              'references': [
                {
                  'id': 'preview',
                  'merchant': 'Circle K',
                  'transaction_date': '2019-02-18',
                  'amount_in_cents': 2000,
                  'currency': 'CAD',
                  'category': 'Food & Drinks',
                },
              ],
            }),
            200,
          ),
        ),
      ),
    );
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: SnapExpenseApp(store: store, destination: const AskSnapScreen()),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/ask-snap-$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpAndSettle();
    await capture('welcome');
    await tester.enterText(
      find.byType(TextField),
      'Why is my Circle K receipt missing from this month?',
    );
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    await capture('answer');
    debugDisableShadows = oldShadows;
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
