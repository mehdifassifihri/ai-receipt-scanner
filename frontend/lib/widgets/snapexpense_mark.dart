import 'package:flutter/material.dart';

/// Resolution-independent brand mark, shared by both phases of the launch reveal.
class SnapExpenseMark extends StatelessWidget {
  const SnapExpenseMark({super.key, this.colored = true, this.size = 104});
  final bool colored;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: SnapExpenseMarkPainter(colored: colored)),
  );
}

class SnapExpenseMarkPainter extends CustomPainter {
  const SnapExpenseMarkPainter({required this.colored});
  final bool colored;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 104, size.height / 104);
    canvas.drawCircle(
      const Offset(52, 52),
      50,
      Paint()
        ..color = colored ? const Color(0xFFE3EBCF) : const Color(0xFFE5E7E3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final tile = RRect.fromRectAndRadius(
      const Rect.fromLTWH(25, 25, 54, 54),
      const Radius.circular(18),
    );
    final fill = Paint()..color = const Color(0xFF20251F);
    if (colored) {
      fill.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE1F1BB), Color(0xFFB3D77F)],
      ).createShader(tile.outerRect);
    }
    canvas.drawRRect(tile, fill);
    final stroke = Paint()
      ..color = colored ? const Color(0xFF42634B) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Four scan corners surround a small receipt with two text lines.
    for (final offset in [
      const Offset(36, 36),
      const Offset(68, 36),
      const Offset(36, 68),
      const Offset(68, 68),
    ]) {
      final dx = offset.dx < 52 ? 1.0 : -1.0;
      final dy = offset.dy < 52 ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(offset.dx, offset.dy + dy * 6)
          ..lineTo(offset.dx, offset.dy + dy * 2)
          ..quadraticBezierTo(
            offset.dx,
            offset.dy,
            offset.dx + dx * 2,
            offset.dy,
          )
          ..lineTo(offset.dx + dx * 6, offset.dy),
        stroke,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(44, 41)
        ..lineTo(60, 41)
        ..lineTo(60, 63)
        ..lineTo(56, 60)
        ..lineTo(52, 63)
        ..lineTo(48, 60)
        ..lineTo(44, 63)
        ..close(),
      stroke,
    );
    canvas.drawLine(const Offset(48, 48), const Offset(56, 48), stroke);
    canvas.drawLine(const Offset(48, 53), const Offset(54, 53), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SnapExpenseMarkPainter oldDelegate) =>
      oldDelegate.colored != colored;
}
