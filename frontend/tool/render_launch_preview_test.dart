// Run explicitly: flutter test tool/render_launch_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_receipt_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Render launch preview frames', (tester) async {
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
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const SnapExpenseApp()),
    );
    final directory = Directory('/tmp/snapexpense-launch-preview');
    await tester.runAsync(() => directory.create(recursive: true));
    for (var index = 0; index <= 35; index++) {
      if (index > 0) await tester.pump(const Duration(milliseconds: 80));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${directory.path}/frame${index.toString().padLeft(3, '0')}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
}
