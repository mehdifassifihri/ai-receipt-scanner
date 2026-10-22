import 'dart:async';
import 'package:ai_receipt_scanner/widgets/artwork_refresh_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<void> Function() refresh, {
    double height = 900,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(
                height: 60,
                child: Center(child: Text('Fixed header')),
              ),
              Expanded(
                child: ArtworkRefreshScrollView(
                  onRefresh: refresh,
                  child: SizedBox(
                    height: height,
                    child: const Align(
                      alignment: Alignment.topCenter,
                      child: Text('Dashboard content'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Pull reveals artwork, keeps header fixed, and refreshes once', (
    tester,
  ) async {
    var calls = 0;
    final refresh = Completer<void>();
    await mount(tester, () {
      calls++;
      return refresh.future;
    });
    final headerPosition = tester.getTopLeft(find.text('Fixed header'));
    final contentPosition = tester.getTopLeft(find.text('Dashboard content'));
    final gesture = await tester.startGesture(const Offset(300, 150));
    await gesture.moveBy(const Offset(0, 360));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.getTopLeft(find.text('Fixed header')), headerPosition);
    expect(
      tester.getTopLeft(find.text('Dashboard content')).dy,
      greaterThan(contentPosition.dy),
    );
    expect(calls, lessThanOrEqualTo(1));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    refresh.complete();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester.getTopLeft(find.text('Dashboard content')).dy,
      closeTo(contentPosition.dy, 1),
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small pulls and scrolling away from the top do not refresh', (
    tester,
  ) async {
    var calls = 0;
    await mount(tester, () async {
      calls++;
    }, height: 1800);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 35));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
