import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class AppColors {
  static bool _light = false;

  static bool get isLight => _light;

  static Color get background =>
      _light ? const Color(0xFFF5F5F2) : const Color(0xFF090909);
  static Color get surface =>
      _light ? const Color(0xFFFFFFFF) : const Color(0xFF141414);
  static Color get surfaceHigh =>
      _light ? const Color(0xFFEDEDE9) : const Color(0xFF1C1C1C);
  static Color get nav =>
      _light ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A);
  static Color get line =>
      _light ? const Color(0xFFDEDED9) : const Color(0xFF2B2B2B);
  static Color get muted =>
      _light ? const Color(0xFF767676) : const Color(0xFFA8A8A8);
  static Color get soft =>
      _light ? const Color(0xFF4E4E4E) : const Color(0xFFD4D4D4);
  static Color get text =>
      _light ? const Color(0xFF101010) : const Color(0xFFFFFFFF);
  static Color get inverseText =>
      _light ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  static Color get subtleFill => _light
      ? const Color(0xFF101010).withValues(alpha: .045)
      : const Color(0xFFFFFFFF).withValues(alpha: .055);
  static Color get subtleBorder => _light
      ? const Color(0xFF101010).withValues(alpha: .09)
      : const Color(0xFFFFFFFF).withValues(alpha: .07);

  static const accent = Color(0xFFFF633F);
  static const accentSoft = Color(0xFFFFE0D8);
  static const success = Color(0xFF67B82E);
  static const onAccent = Color(0xFF080808);
  static const onMedia = Color(0xFFFFFFFF);

  static void useLight(bool value) => _light = value;
}

class BackcourtThemeController extends ChangeNotifier {
  BackcourtThemeController._();

  static final instance = BackcourtThemeController._();
  static const _preferenceKey = 'backcourt_theme_mode_v1';

  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;
  bool get isLight => _mode == ThemeMode.light;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    _mode = saved == 'light' ? ThemeMode.light : ThemeMode.dark;
    AppColors.useLight(isLight);
  }

  Future<void> setLight(bool value) async {
    final next = value ? ThemeMode.light : ThemeMode.dark;
    if (_mode == next) return;
    _mode = next;
    AppColors.useLight(value);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, value ? 'light' : 'dark');
  }
}

abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final background = light
        ? const Color(0xFFF5F5F2)
        : const Color(0xFF090909);
    final surface = light ? const Color(0xFFFFFFFF) : const Color(0xFF141414);
    final surfaceHigh = light
        ? const Color(0xFFEDEDE9)
        : const Color(0xFF1C1C1C);
    final text = light ? const Color(0xFF101010) : const Color(0xFFFFFFFF);
    final soft = light ? const Color(0xFF4E4E4E) : const Color(0xFFD4D4D4);
    final muted = light ? const Color(0xFF767676) : const Color(0xFFA8A8A8);
    final line = light ? const Color(0xFFDEDED9) : const Color(0xFF2B2B2B);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.onAccent,
          surface: surface,
          onSurface: text,
          outline: line,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      colorScheme: colorScheme,
      splashColor: text.withValues(alpha: .06),
      highlightColor: Colors.transparent,
      dividerColor: line,
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: light ? const Color(0xFF161616) : surfaceHigh,
        contentTextStyle: const TextStyle(color: Color(0xFFFFFFFF)),
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          color: text,
          fontSize: 40,
          height: 1.05,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.8,
        ),
        headlineLarge: TextStyle(
          color: text,
          fontSize: 30,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
        ),
        headlineMedium: TextStyle(
          color: text,
          fontSize: 23,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
        ),
        titleLarge: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -.25,
        ),
        titleMedium: TextStyle(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: text, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(color: soft, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(
          color: muted,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: TextStyle(
          color: text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          color: soft,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: TextStyle(color: muted, fontSize: 14),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: light ? const Color(0xFF111111) : AppColors.text,
          foregroundColor: light
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF000000),
          disabledBackgroundColor: surfaceHigh,
          disabledForegroundColor: muted,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: light ? const Color(0xFF111111) : AppColors.text,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        labelStyle: TextStyle(
          color: soft,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.accent : line,
        ),
      ),
    );
  }
}
