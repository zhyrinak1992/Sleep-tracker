import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF090D25);
  static const surface = Color(0xFF171B3B);
  static const surfaceLight = Color(0xFF28234F);
  static const teal = Color(0xFFD5A5F4);
  static const muted = Color(0xFFB7B2D1);

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: teal,
      secondary: Color(0xFFFFC6D9),
      surface: surface,
      error: Color(0xFFFF8A8A),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0A1029),
      indicatorColor: teal.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    useMaterial3: true,
  );
}
