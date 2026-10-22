import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/glass_theme.dart';
import 'glass_accessibility.dart';

/// Un filtre partagé par les surfaces adjacentes, jamais par des formes superposées.
/// La frontière de repaint isole les contrôles de la texture caméra.
class GlassGroup extends StatefulWidget {
  const GlassGroup({super.key, required this.child});
  final Widget child;
  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup> {
  final _backdropKey = BackdropKey();
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: BackdropGroup(backdropKey: _backdropKey, child: widget.child),
  );
}

/// Verre dépoli portable. Les gradients simulent le bord d’une lentille :
/// il n’y a pas de réfraction optique réelle dans ce chemin sans shader GPU.
class GlassContainer extends StatefulWidget {
  const GlassContainer({
    super.key,
    this.blur,
    this.tint,
    this.borderRadius = 24,
    this.interactive = false,
    this.showShadow = true,
    this.onTap,
    required this.child,
  });
  final double? blur;
  final Color? tint;
  final double borderRadius;
  final bool interactive;
  final bool showShadow;
  final VoidCallback? onTap;
  final Widget child;
  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final solid =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context) ||
        GlassAccessibility.reduceTransparencyOf(context);
    final radius = BorderRadius.circular(widget.borderRadius);
    final duration = solid ? Duration.zero : theme.duration;
    final tint = widget.tint ?? theme.tint;
    Widget surface = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: solid ? theme.solidColor : tint,
      ),
      // Deux couches : un shader de gradient remplace sinon la couleur du Paint.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: solid
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: _pressed ? .24 : .12),
                    Colors.white.withValues(alpha: .025),
                    Colors.white.withValues(alpha: .075),
                  ],
                  stops: const [0, .55, 1],
                ),
        ),
        child: widget.child,
      ),
    );
    if (!solid && (widget.blur ?? theme.blur) > 0) {
      final filter = ui.ImageFilter.blur(
        sigmaX: widget.blur ?? theme.blur,
        sigmaY: widget.blur ?? theme.blur,
      );
      surface = BackdropGroup.of(context) == null
          ? BackdropFilter(filter: filter, child: surface)
          : BackdropFilter.grouped(filter: filter, child: surface);
    }
    surface = TweenAnimationBuilder<double>(
      tween: Tween(end: widget.borderRadius),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: surface,
      builder: (context, animatedRadius, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(animatedRadius),
          boxShadow: solid || !widget.showShadow
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .12),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(animatedRadius),
          child: CustomPaint(
            foregroundPainter: _SpecularBorder(
              radius: animatedRadius,
              opacity: solid ? .2 : theme.borderOpacity,
              pressed: _pressed,
            ),
            child: child,
          ),
        ),
      ),
    );
    return AnimatedScale(
      scale: _pressed && !solid ? theme.pressScale : 1,
      duration: duration,
      curve: Curves.easeOutBack,
      child: Listener(
        onPointerDown: widget.interactive
            ? (_) {
                HapticFeedback.lightImpact();
                setState(() => _pressed = true);
              }
            : null,
        onPointerUp: (_) {
          if (_pressed) setState(() => _pressed = false);
        },
        onPointerCancel: (_) {
          if (_pressed) setState(() => _pressed = false);
        },
        child: widget.onTap == null
            ? surface
            : Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: surface,
                ),
              ),
      ),
    );
  }
}

class _SpecularBorder extends CustomPainter {
  const _SpecularBorder({
    required this.radius,
    required this.opacity,
    required this.pressed,
  });
  final double radius, opacity;
  final bool pressed;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(.5);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular((radius - .5).clamp(0, double.infinity)),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: pressed ? 1 : opacity),
            Colors.white.withValues(alpha: .12),
            Colors.white.withValues(alpha: .28),
          ],
          stops: const [0, .65, 1],
        ).createShader(rect),
    );
    // Un second reflet à rayon concentrique suggère l’épaisseur du bord.
    final inner = rect.deflate(2);
    if (!inner.isEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          inner,
          Radius.circular((radius - 2.5).clamp(0, double.infinity)),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: pressed ? .14 : .065),
      );
    }
  }

  @override
  bool shouldRepaint(_SpecularBorder oldDelegate) =>
      radius != oldDelegate.radius ||
      opacity != oldDelegate.opacity ||
      pressed != oldDelegate.pressed;
}
