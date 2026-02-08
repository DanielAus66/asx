import 'package:flutter/material.dart';

class AppTheme {
  static const Color backgroundColor = Color(0xFF0D0D0D);
  static const Color surfaceColor = Color(0xFF1A1A1A);
  static const Color cardColor = Color(0xFF242424);
  static const Color dividerColor = Color(0xFF2E2E2E);
  static const Color accentColor = Color(0xFFFF9500);
  static const Color accentColorLight = Color(0xFFFFAB40);
  static const Color successColor = Color(0xFF34C759);
  static const Color errorColor = Color(0xFFFF3B30);
  static const Color warningColor = Color(0xFFFFCC00);
  static const Color textPrimaryColor = Color(0xFFFFFFFF);
  static const Color textSecondaryColor = Color(0xFF8E8E93);
  static const Color textTertiaryColor = Color(0xFF636366);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: accentColor,
      colorScheme: const ColorScheme.dark(
        primary: accentColor,
        secondary: accentColorLight,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimaryColor,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: textPrimaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: accentColor,
        unselectedItemColor: textTertiaryColor,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textTertiaryColor),
      ),
    );
  }
}
