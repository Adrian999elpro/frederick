import 'package:flutter/material.dart';

/// Tokens de diseño institucional FWT (frederickwinslowtaylor.com)
class FwtColors {
  static const navDark = Color(0xFF0E0E0E);
  static const brand = Color(0xFFA81717);       // Rojo principal FWT
  static const brandDeep = Color(0xFF7A1313);   // Rojo oscuro degradado
  static const accent = Color(0xFFE00E0E);      // Rojo brillante interactivo
  static const accentGold = Color(0xFFF59E0B);  // Dorado podio / estrellas
  static const brandOnDark = Color(0xFFF87171); // Rojo legible sobre fondos oscuros (6.4:1)
  static const surface = Colors.white;
  static const background = Color(0xFFF3F4F6);  // Gray-100
}

ThemeData fwtTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: FwtColors.brand,
    brightness: brightness,
    primary: isDark ? FwtColors.brandOnDark : FwtColors.brand,
    onPrimary: isDark ? const Color(0xFF2B0A0A) : Colors.white,
    secondary: FwtColors.accent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0B0F19) : FwtColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: FwtColors.navDark,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w800,
        fontSize: 18,
        letterSpacing: 0.5,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: FwtColors.brand,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: const StadiumBorder(), // Pill button como el sitio web
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? FwtColors.brandOnDark : FwtColors.brand,
        side: BorderSide(color: isDark ? FwtColors.brandOnDark : FwtColors.brand, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const StadiumBorder(),
      ),
    ),
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF151D2D) : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? FwtColors.brandOnDark : FwtColors.brand, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
