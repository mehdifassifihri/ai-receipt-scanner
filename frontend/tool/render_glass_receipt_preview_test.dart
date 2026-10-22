// Explicit visual check only: flutter test tool/render_glass_receipt_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_receipt_scanner/app.dart';
import 'package:ai_receipt_scanner/screens/receipt_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Render glass controls over a synthetic captured receipt', (
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
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final file = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('snap_glass_');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 480, 640),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF9AA78B), Color(0xFF485A50), Color(0xFFB9ACC8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(const Rect.fromLTWH(0, 0, 480, 640)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(77, 45, 326, 545),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFFF9F7EE),
      );
      void line(String text, double y, {double size = 17, bool bold = false}) {
        final paragraph =
            (ui.ParagraphBuilder(
                    ui.ParagraphStyle(
                      fontFamily: 'Poppins',
                      fontSize: size,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                    ),
                  )
                  ..pushStyle(ui.TextStyle(color: const Color(0xFF242C26)))
                  ..addText(text))
                .build()
              ..layout(const ui.ParagraphConstraints(width: 270));
        canvas.drawParagraph(paragraph, Offset(102, y));
      }

      line('SNAP CAFE', 82, size: 28, bold: true);
      line('Small moments. Good coffee.', 128, size: 12);
      line('20 OCT 2026   •   10:42', 184, size: 12);
      canvas.drawLine(
        const Offset(102, 222),
        const Offset(375, 222),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 1,
      );
      line('Flat white                  4.50', 247);
      line('Almond croissant      5.00', 292);
      line('Tax                            1.10', 358);
      canvas.drawLine(
        const Offset(102, 403),
        const Offset(375, 403),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 1,
      );
      line('TOTAL    CAD 10.60', 430, size: 22, bold: true);
      line('Thank you. See you soon!', 515, size: 13);
      final picture = recorder.endRecording();
      final image = await picture.toImage(480, 640);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${directory.path}/synthetic.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      return file;
    });
    addTearDown(() => file!.parent.delete(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera'),
      (call) async => call.method == 'availableCameras' ? [] : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => call.method == 'pickImage' ? file!.path : null,
    );
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const SnapExpenseApp(destination: ReceiptScannerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Upload from Gallery'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    expect(find.text('Looking good?'), findsOneWidget);
    final imageWidget = tester.widget<Image>(find.byType(Image));
    await tester.runAsync(
      () =>
          precacheImage(imageWidget.image, tester.element(find.byType(Image))),
    );
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/snap-glass-receipt.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    debugDisableShadows = oldShadows;
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
