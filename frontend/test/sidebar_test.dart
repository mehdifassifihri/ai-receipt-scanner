import 'dart:async';
import 'package:ai_receipt_scanner/widgets/snap_sidebar.dart';
import 'package:ai_receipt_scanner/app.dart';
import 'package:flutter/services.dart';
import 'package:ai_receipt_scanner/screens/home_shell.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Sidebar navigates to Ask Snap and supports a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final store = ExpenseStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      SnapExpenseApp(store: store, destination: const HomeShell()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    for (final label in [
      'Home',
      'Expense history',
      'Analytics',
      'Ask Snap',
      'Scan receipt',
    ]) {
      expect(
        find.descendant(of: find.byType(Drawer), matching: find.text(label)),
        findsNothing,
      );
    }
    await tester.tap(find.text('A little clarity.'));
    await tester.pumpAndSettle();
    expect(find.text('A little clarity.\nJust ask.'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Sidebar logout blocks double taps and allows retry after a failure',
    (tester) async {
      final result = Completer<void>();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SnapSidebar(
              connected: true,
              email: 'test@example.com',
              onSelect: (_) {},
              onLogout: () {
                attempts++;
                return result.future;
              },
            ),
          ),
        ),
      );
      final button = find.text('Log out');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(attempts, 1);
      result.completeError(Exception('synthetic failure'));
      await tester.pumpAndSettle();
      expect(find.text('Could not log out. Please retry.'), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Log out'),
      );
      expect(tile.enabled, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
