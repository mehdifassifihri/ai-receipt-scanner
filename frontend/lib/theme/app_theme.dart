import 'package:flutter/material.dart';
import 'glass_theme.dart';

/// Tokens partagés existants ; les accents propres à chaque carte restent locaux.
abstract final class AppColors {
  static const ink = Color(0xFF20251F);
  static const muted = Color(0xFF777C73);
  static const background = Color(0xFFF6F7F4);
  static const seed = Color(0xFF42634B);
}

ThemeData snapExpenseTheme({Brightness brightness = Brightness.light}) =>
    ThemeData(
      brightness: brightness,
      useMaterial3: true,
      extensions: [
        brightness == Brightness.dark ? GlassTheme.dark : GlassTheme.light,
      ],
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF181E1A)
          : AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.seed,
        brightness: brightness,
      ),
      fontFamily: 'Poppins',
      textTheme: TextTheme(
        bodyMedium: TextStyle(
          color: brightness == Brightness.dark ? Colors.white : AppColors.ink,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
