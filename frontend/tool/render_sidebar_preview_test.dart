import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
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
    tester.view.physicalSize = const Size(390, 844);
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
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final key = GlobalKey();
    final store = ExpenseStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: SnapExpenseApp(store: store, destination: const HomeShell()),
      ),
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
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/snap-sidebar.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('A little clarity.'));
    await tester.pumpAndSettle();
    expect(find.text('A little clarity.\nJust ask.'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
