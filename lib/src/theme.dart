import 'package:flutter/material.dart';

class AppPalette {
  static const canvas = Color(0xFF111723);
  static const panel = Color(0xFF192131);
  static const panelRaised = Color(0xFF202B3F);
  static const accent = Color(0xFFD8874A);
  static const accentSoft = Color(0xFFF0C49B);
  static const ink = Color(0xFF192131);
  static const page = Color(0xFFFFFBF4);
  static const pageInk = Color(0xFF2B2218);
  static const textPrimary = Color(0xFFF6F0E9);
  static const textMuted = Color(0xFFB9C0CC);
  static const divider = Color(0xFF31425F);
  static const success = Color(0xFF58B88A);
  static const danger = Color(0xFFE0717A);
}

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);

  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppPalette.accent,
    onPrimary: Colors.white,
    secondary: AppPalette.accentSoft,
    onSecondary: AppPalette.ink,
    error: AppPalette.danger,
    onError: Colors.white,
    surface: AppPalette.panel,
    onSurface: AppPalette.textPrimary,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.canvas,
    dividerColor: AppPalette.divider,
    cardColor: AppPalette.panel,
    textTheme: base.textTheme
        .apply(
          bodyColor: AppPalette.textPrimary,
          displayColor: AppPalette.textPrimary,
        )
        .copyWith(
          displaySmall: const TextStyle(
            fontFamily: 'Cambria',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          headlineSmall: const TextStyle(
            fontFamily: 'Cambria',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Cambria',
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: const TextStyle(height: 1.35),
        ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppPalette.panelRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppPalette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppPalette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppPalette.accent, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppPalette.panelRaised,
      contentTextStyle: TextStyle(color: AppPalette.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
