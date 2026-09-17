import 'package:flutter/material.dart';

/// Polished green-felt card-table theme shared across all screens.
class AppTheme {
  AppTheme._();

  // ------------------------------------------------------------- palette
  static const Color feltDark = Color(0xFF0B3D2E);
  static const Color felt = Color(0xFF14532D);
  static const Color feltLight = Color(0xFF166534);
  static const Color feltEdge = Color(0xFF022C22);

  static const Color gold = Color(0xFFF5C24B);
  static const Color goldDark = Color(0xFFB8860B);
  static const Color cream = Color(0xFFFAF6EC);
  static const Color ink = Color(0xFF1B1B1B);
  static const Color red = Color(0xFFDC2626);
  static const Color danger = Color(0xFFB91C1C);
  static const Color success = Color(0xFF22C55E);

  static const Color surface = Color(0xFF0F2E22);
  static const Color surfaceHigh = Color(0xFF17402F);
  static const Color textDim = Color(0xFFB7C9BE);

  /// Dark green-felt material theme.
  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        onPrimary: ink,
        secondary: gold,
        onSecondary: ink,
        surface: surface,
        onSurface: cream,
        error: red,
        onError: cream,
      ),
      scaffoldBackgroundColor: felt,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: cream,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: base.textTheme.apply(bodyColor: cream, displayColor: cream),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: ink,
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cream,
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: textDim, width: 1.4),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: gold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: const TextStyle(color: textDim),
        labelStyle: const TextStyle(color: cream),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: feltEdge, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: red, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: red, width: 1.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: cream,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: cream, fontSize: 15, height: 1.4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: cream, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: feltEdge, thickness: 1),
    );
  }
}
