// Run explicitly: flutter test tool/generate_launch_assets_test.dart
// Uses the same Flutter painter as the animation, avoiding native artwork drift.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:ai_receipt_scanner/widgets/snapexpense_mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Generate monochrome iOS launch artwork', () async {
    for (var scale = 1; scale <= 3; scale++) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(scale.toDouble());
      const SnapExpenseMarkPainter(
        colored: false,
      ).paint(canvas, const ui.Size(104, 104));
      final picture = recorder.endRecording();
      final image = await picture.toImage(104 * scale, 104 * scale);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final suffix = scale == 1 ? '' : '@${scale}x';
      await File(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage$suffix.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    }
  });
}
