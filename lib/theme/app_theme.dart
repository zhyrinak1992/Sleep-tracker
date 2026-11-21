import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF071426);
  static const surface = Color(0xFF10243B);
  static const surfaceLight = Color(0xFF17344D);
  static const teal = Color(0xFF55D6C2);
  static const muted = Color(0xFF9CB2C8);

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: teal,
      secondary: Color(0xFF8BC7E8),
      surface: surface,
      error: Color(0xFFFF8A8A),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF091A2D),
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
