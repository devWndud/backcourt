import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF090909);
  static const surface = Color(0xFF141414);
  static const surfaceHigh = Color(0xFF1C1C1C);
  static const nav = Color(0xFF1A1A1A);
  static const line = Color(0xFF2B2B2B);
  static const muted = Color(0xFFA8A8A8);
  static const soft = Color(0xFFD4D4D4);
  static const accent = Color(0xFFFF633F);
  static const accentSoft = Color(0xFFFFE0D8);
  static const success = Color(0xFFBAF86A);
}

abstract final class AppTheme {
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: colorScheme,
      splashColor: Colors.white.withValues(alpha: .06),
      highlightColor: Colors.transparent,
      dividerColor: AppColors.line,
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: Colors.white,
          fontSize: 40,
          height: 1.05,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.8,
        ),
        headlineLarge: TextStyle(
          color: Colors.white,
          fontSize: 30,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
        ),
        headlineMedium: TextStyle(
          color: Colors.white,
          fontSize: 23,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
        ),
        titleLarge: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -.25,
        ),
        titleMedium: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(
          color: AppColors.soft,
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          color: AppColors.soft,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        prefixIconColor: AppColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: .07)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        labelStyle: const TextStyle(
          color: AppColors.soft,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
