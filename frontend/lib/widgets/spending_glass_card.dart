import 'dart:ui';
import 'package:flutter/material.dart';

/// A bounded frosted surface. Only the decoration is blurred, never the text.
class SpendingGlassCard extends StatelessWidget {
  const SpendingGlassCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1475945D),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE4F1CB),
                    Color(0xFFCFE5AE),
                    Color(0xFFE9E4F3),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            top: -65,
            right: -25,
            child: _Glow(color: Color(0xFFB1DB71), size: 220),
          ),
          const Positioned(
            bottom: -90,
            left: -40,
            child: _Glow(color: Color(0xFFBDA5E4), size: 180),
          ),
          const Positioned(
            top: -80,
            left: -45,
            child: _Glow(color: Color(0xCCFFFFFF), size: 160),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(23),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .7),
                  width: 1.2,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: .48),
                    Colors.white.withValues(alpha: .16),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}
