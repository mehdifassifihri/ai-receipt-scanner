// Run explicitly: flutter test tool/render_account_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_receipt_scanner/main.dart';
import 'package:ai_receipt_scanner/screens/login_screen.dart';
import 'package:ai_receipt_scanner/screens/registration_screen.dart';
import 'package:ai_receipt_scanner/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Render login, registration and glass dashboard previews', (
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
    final directory = Directory('/tmp/snapexpense-account-preview');
    await tester.runAsync(() => directory.create(recursive: true));
    for (final entry in <String, Widget>{
      'login': const LoginScreen(),
      'register': const RegistrationScreen(),
      'dashboard': const DashboardScreen(),
    }.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: SnapExpenseApp(
            key: ValueKey(entry.key),
            destination: entry.value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${directory.path}/${entry.key}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
}
