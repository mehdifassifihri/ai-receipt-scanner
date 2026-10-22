import 'dart:ui' as ui;
import 'dart:io';
import 'package:ai_receipt_scanner/main.dart';
import 'package:ai_receipt_scanner/state/expense_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Receipt flow validates, protects edits, saves to memory, and returns home',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'),
            (call) async => call.method == 'availableCameras' ? [] : null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async => null,
          );
      tester.view.physicalSize = const Size(320, 740);
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
      await tester.pumpWidget(const SnapExpenseApp());
      await tester.pumpAndSettle();
      expect(find.text('\$2,450.75'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Scan Receipt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan Receipt'));
      await tester.pumpAndSettle();
      expect(
        find.text('Capture your receipt and let AI handle the rest.'),
        findsOneWidget,
      );
      expect(find.text('Let’s get your receipt'), findsOneWidget);
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('receipt_test_'),
      );
      final image = File('${directory!.path}/receipt.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final picture = recorder.endRecording();
        final bitmap = await picture.toImage(40, 80);
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        await image.writeAsBytes(bytes!.buffer.asUint8List());
        bitmap.dispose();
        picture.dispose();
      });
      addTearDown(() => directory.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async => call.method == 'pickImage' ? image.path : null,
          );
      await tester.ensureVisible(find.text('Upload from Gallery'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Upload from Gallery'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      expect(find.text('Looking good?'), findsOneWidget);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Review Receipt'), findsOneWidget);
      expect(find.text('Demo details ready for review'), findsOneWidget);
      await tester.tap(find.text('Tap to view full receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to Scanner'));
      await tester.pumpAndSettle();
      expect(find.text('Looking good?'), findsOneWidget);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('merchant')));
      await tester.enterText(find.byKey(const ValueKey('merchant')), '');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a merchant name.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('merchant')),
        'Starbucks Downtown',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('amount')));
      await tester.enterText(find.byKey(const ValueKey('amount')), '0');
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an amount above zero, with up to 2 decimals.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const ValueKey('amount')), '31,25');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Save Expense').hitTestable(), findsOneWidget);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdowns.first);
      await tester.tap(dropdowns.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CAD').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(dropdowns.last);
      await tester.tap(dropdowns.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to Scanner'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your edits?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Expense saved for this session.'),
        findsOneWidget,
      );
      final store = ExpenseScope.of(tester.element(find.text('Welcome back')));
      expect(store.expenses.length, 1);
      expect(store.expenses.single.details.amountInCents, 3125);
      expect(store.expenses.single.details.currency, 'CAD');
      expect(store.expenses.single.details.category, 'Groceries');
      expect(store.expenses.single.details.merchant, 'Starbucks Downtown');
      await tester.ensureVisible(find.text('Spending breakdown'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping').first);
      await tester.pumpAndSettle();
      expect(find.text('25%'), findsNWidgets(2));
      await tester.ensureVisible(find.text('See All'));
      await tester.tap(find.text('See All'));
      await tester.pumpAndSettle();
      expect(find.text('My Expenses'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Starbucks Downtown'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Starbucks Downtown'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View full receipt'));
      await tester.tap(find.text('View full receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Close preview'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
