// Run explicitly: flutter test --no-pub tool/render_pull_refresh_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_receipt_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Render the Dashboard artwork pull reveal', (tester) async {
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
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const SnapExpenseApp()),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/blurry_background.png'),
        tester.element(find.byType(CustomScrollView)),
      ),
    );
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(195, 170));
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump(const Duration(milliseconds: 100));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/snapexpense-pull-refresh.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
