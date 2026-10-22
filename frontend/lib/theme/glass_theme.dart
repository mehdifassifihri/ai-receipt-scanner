import 'package:flutter/material.dart';

/// Toutes les valeurs optiques restent réglables sans toucher aux écrans.
@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  const GlassTheme({
    required this.tint,
    required this.solidColor,
    required this.foreground,
    required this.textScrim,
    this.blur = 24,
    this.borderOpacity = .72,
    this.pressScale = 1.05,
    this.duration = const Duration(milliseconds: 250),
  });
  static const light = GlassTheme(
    tint: Color(0x1FFFFFFF),
    solidColor: Color(0xFFF2F5ED),
    foreground: Color(0xFF20251F),
    textScrim: Color(0xEFFFFFFF),
  );
  static const dark = GlassTheme(
    tint: Color(0x1FFFFFFF),
    solidColor: Color(0xFF252B28),
    foreground: Colors.white,
    textScrim: Color(0xE619211D),
  );

  /// Même finition que les contrôles caméra sur un fond de conversation clair.
  static final darkPanel = dark.copyWith(tint: const Color(0xF0202823));

  final Color tint, solidColor, foreground, textScrim;
  final double blur, borderOpacity, pressScale;
  final Duration duration;
  static GlassTheme of(BuildContext context) =>
      Theme.of(context).extension<GlassTheme>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  @override
  GlassTheme copyWith({
    Color? tint,
    Color? solidColor,
    Color? foreground,
    Color? textScrim,
    double? blur,
    double? borderOpacity,
    double? pressScale,
    Duration? duration,
  }) => GlassTheme(
    tint: tint ?? this.tint,
    solidColor: solidColor ?? this.solidColor,
    foreground: foreground ?? this.foreground,
    textScrim: textScrim ?? this.textScrim,
    blur: blur ?? this.blur,
    borderOpacity: borderOpacity ?? this.borderOpacity,
    pressScale: pressScale ?? this.pressScale,
    duration: duration ?? this.duration,
  );
  @override
  GlassTheme lerp(covariant GlassTheme? other, double t) {
    if (other == null) return this;
    double mix(double a, double b) => a + (b - a) * t;
    return GlassTheme(
      tint: Color.lerp(tint, other.tint, t)!,
      solidColor: Color.lerp(solidColor, other.solidColor, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      textScrim: Color.lerp(textScrim, other.textScrim, t)!,
      blur: mix(blur, other.blur),
      borderOpacity: mix(borderOpacity, other.borderOpacity),
      pressScale: mix(pressScale, other.pressScale),
      duration: Duration(
        milliseconds: mix(
          duration.inMilliseconds.toDouble(),
          other.duration.inMilliseconds.toDouble(),
        ).round(),
      ),
    );
  }
}
