import 'package:flutter/material.dart';

/// Paleta institucional FWT (la misma de la web).
class Fwt {
  static const ink = Color(0xFF0E1117);
  static const brand = Color(0xFFA81717);
  static const brandDeep = Color(0xFF7A1313);
  static const accent = Color(0xFFE00E0E);
  static const gold = Color(0xFFF59E0B);
  static const silver = Color(0xFF94A3B8);
  static const bronze = Color(0xFFB45309);
  static const ok = Color(0xFF15803D);
  static const brandOnDark = Color(0xFFF87171);

  static const lightBg = Color(0xFFF6F7FB);
  static const lightSurface = Colors.white;
  static const lightLine = Color(0xFFE2E8F0);
  static const lightMuted = Color(0xFF5A6A7F);
  static const darkBg = Color(0xFF0B0E14);
  static const darkSurface = Color(0xFF151A23);
  static const darkLine = Color(0xFF273041);
  static const darkMuted = Color(0xFF94A3B8);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A0A0C), brandDeep, brand],
  );
}

extension FwtContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get muted => isDark ? Fwt.darkMuted : Fwt.lightMuted;
  Color get line => isDark ? Fwt.darkLine : Fwt.lightLine;
  Color get surface => isDark ? Fwt.darkSurface : Fwt.lightSurface;
  Color get brandText => isDark ? Fwt.brandOnDark : Fwt.brand;
}

ThemeData fwtTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? Fwt.brandOnDark : Fwt.brand;
  final scheme = ColorScheme.fromSeed(
    seedColor: Fwt.brand,
    brightness: brightness,
    primary: primary,
    onPrimary: dark ? const Color(0xFF2B0A0A) : Colors.white,
    secondary: Fwt.accent,
    surface: dark ? Fwt.darkSurface : Fwt.lightSurface,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Fwt.darkBg : Fwt.lightBg,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: dark ? Colors.white : Fwt.ink,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: dark ? Colors.white : Fwt.ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? Fwt.darkSurface : Fwt.lightSurface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: dark ? Fwt.darkLine : Fwt.lightLine),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Fwt.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: primary, width: 1.5),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Fwt.darkSurface : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? Fwt.darkLine : Fwt.lightLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? Fwt.darkLine : Fwt.lightLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: dark ? Fwt.darkSurface : Colors.white,
      indicatorColor: primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
