import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum NavGlyph { home, explore, add, heart, chat }

class NavDestination {
  const NavDestination(this.glyph, this.label, {this.badge = false});
  final NavGlyph glyph;
  final String label;
  final bool badge;
}

const _activeColor = Color(0xFF111111);
const _inactiveColor = Color(0xFFA8A8AD);
const _badgeColor = Color(0xFFFF3B30);

/// Frosted iOS-style tab bar; the warm glow follows the selected tab.
class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
  });
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final glowX = destinations.length == 1
        ? 0.0
        : -1 + 2 * selectedIndex / (destinations.length - 1);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: glowX),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, x, child) => DecoratedBox(
            decoration: BoxDecoration(
              border: const Border(
                top: BorderSide(color: Color(0x1F000000), width: 0.5),
              ),
              gradient: const LinearGradient(
                colors: [
                  Color(0xD9F1EFEC),
                  Color(0xD9ECEDF1),
                  Color(0xD9E7EAF3),
                ],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(x * 0.92, -0.35),
                  radius: 1.1,
                  colors: const [Color(0x66C7B8A8), Color(0x00C7B8A8)],
                ),
              ),
              child: child,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: 10, bottom: math.max(bottom, 12)),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _NavItem(
                      destination: destinations[i],
                      active: i == selectedIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.active,
    required this.onTap,
  });
  final NavDestination destination;
  final bool active;
  final VoidCallback onTap;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: SizedBox(
          height: 46,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.82 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.active ? 1 : 0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  size: const Size.square(31),
                  painter: _GlyphPainter(
                    glyph: widget.destination.glyph,
                    activeness: t,
                    badge: widget.destination.badge,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({
    required this.glyph,
    required this.activeness,
    required this.badge,
  });
  final NavGlyph glyph;
  final double activeness;
  final bool badge;

  static const _stroke = 2.1;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);
    final color = Color.lerp(_inactiveColor, _activeColor, activeness)!;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color.withValues(alpha: activeness)
      ..style = PaintingStyle.fill;
    final cut = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = Color.fromRGBO(0, 0, 0, activeness)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.saveLayer(Rect.fromLTWH(-2, -2, 28, 28), Paint());
    final shape = _shape();
    canvas.drawPath(shape, fill);
    canvas.drawPath(shape, outline);
    final detail = _detail();
    if (detail != null) {
      // Punched through the filled shape when active, drawn as lines when not.
      canvas.drawPath(detail, cut);
      canvas.drawPath(
        detail,
        outline..color = color.withValues(alpha: 1 - activeness),
      );
    }
    canvas.restore();

    if (badge) {
      final center = glyph == NavGlyph.heart
          ? const Offset(19.6, 4.6)
          : const Offset(20, 4);
      canvas.drawCircle(center, 3.4, Paint()..color = _badgeColor);
    }
    canvas.restore();
  }

  Path _shape() => switch (glyph) {
    NavGlyph.home =>
      Path()
        ..moveTo(10.6, 3.9)
        ..quadraticBezierTo(12, 2.9, 13.4, 3.9)
        ..lineTo(20.1, 9.0)
        ..quadraticBezierTo(21, 9.7, 21, 10.9)
        ..lineTo(21, 18)
        ..quadraticBezierTo(21, 21, 18, 21)
        ..lineTo(6, 21)
        ..quadraticBezierTo(3, 21, 3, 18)
        ..lineTo(3, 10.9)
        ..quadraticBezierTo(3, 9.7, 3.9, 9.0)
        ..close(),
    NavGlyph.explore || NavGlyph.add =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9.2)),
    NavGlyph.heart =>
      Path()
        ..moveTo(12, 20.3)
        ..cubicTo(12, 20.3, 3, 15.2, 3, 9)
        ..cubicTo(3, 6.1, 5.2, 4, 7.9, 4)
        ..cubicTo(9.7, 4, 11.1, 5, 12, 6.5)
        ..cubicTo(12.9, 5, 14.3, 4, 16.1, 4)
        ..cubicTo(18.8, 4, 21, 6.1, 21, 9)
        ..cubicTo(21, 15.2, 12, 20.3, 12, 20.3)
        ..close(),
    NavGlyph.chat => _chatBubble(),
  };

  Path? _detail() => switch (glyph) {
    NavGlyph.home =>
      Path()
        ..moveTo(9.2, 14.6)
        ..quadraticBezierTo(12, 17.6, 14.8, 14.6),
    NavGlyph.explore =>
      Path()
        ..moveTo(15.6, 8.4)
        ..lineTo(13.7, 13.7)
        ..lineTo(8.4, 15.6)
        ..lineTo(10.3, 10.3)
        ..close(),
    NavGlyph.add =>
      Path()
        ..moveTo(12, 8)
        ..lineTo(12, 16)
        ..moveTo(8, 12)
        ..lineTo(16, 12),
    NavGlyph.chat =>
      Path()
        ..moveTo(9.3, 12.6)
        ..quadraticBezierTo(12.6, 15.8, 15.9, 12.6),
    NavGlyph.heart => null,
  };

  Path _chatBubble() {
    const c = Offset(12.6, 11.4);
    const r = 8.6;
    const start = 2.9;
    const end = 1.95;
    final path = Path()
      ..arcTo(
        Rect.fromCircle(center: c, radius: r),
        start,
        2 * math.pi - (start - end),
        true,
      )
      ..quadraticBezierTo(7.4, 20.6, 4.6, 20.6)
      ..quadraticBezierTo(
        4.2,
        17.4,
        c.dx + r * math.cos(start),
        c.dy + r * math.sin(start),
      )
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.activeness != activeness || old.badge != badge;
}
