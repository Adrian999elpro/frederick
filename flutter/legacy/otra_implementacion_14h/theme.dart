import 'package:flutter/material.dart';

/// Paleta institucional FWT (la misma de la web): negro, rojo y dorado.
class FwtColors {
  static const ink = Color(0xFF0E1117);
  static const brand = Color(0xFFA81717);
  static const brandDeep = Color(0xFF7A1313);
  static const accent = Color(0xFFE00E0E);
  static const gold = Color(0xFFF59E0B);
  static const silver = Color(0xFF94A3B8);
  static const bronze = Color(0xFFB45309);
  static const brandOnDark = Color(0xFFF87171);

  static const lightBg = Color(0xFFF6F7FB);
  static const darkBg = Color(0xFF0B0E14);
  static const darkSurface = Color(0xFF151A24);

  static const ok = Color(0xFF15803D);
  static const okOnDark = Color(0xFF4ADE80);
  static const danger = Color(0xFFDC2626);
  static const warn = Color(0xFFB45309);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, brandDeep, brand],
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: FwtColors.brand, brightness: brightness);
  final scheme = base.copyWith(
    primary: dark ? FwtColors.brandOnDark : FwtColors.brand,
    onPrimary: dark ? const Color(0xFF2B0A0A) : Colors.white,
    secondary: FwtColors.accent,
    surface: dark ? FwtColors.darkSurface : Colors.white,
    onSurface: dark ? const Color(0xFFE6E9F0) : const Color(0xFF0F172A),
    outlineVariant: dark ? const Color(0xFF2A3342) : const Color(0xFFE2E8F0),
    error: FwtColors.danger,
  );
  final radius12 = BorderRadius.circular(12);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? FwtColors.darkBg : FwtColors.lightBg,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? FwtColors.darkBg : FwtColors.lightBg,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? FwtColors.darkSurface : Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FwtColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: scheme.primary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1B2230) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.primary, width: 2)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius12),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
  );
}
