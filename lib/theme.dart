import 'package:flutter/material.dart';

/// App-wide dark theme. Terminals use their own palette (see terminal_pane).
class AppTheme {
  static const Color bg = Color(0xFF0B0E14);
  static const Color surface = Color(0xFF151A23);
  static const Color surfaceAlt = Color(0xFF1C222D);
  static const Color border = Color(0xFF2A313D);
  static const Color accent = Color(0xFF4F8CFF);
  static const Color textDim = Color(0xFF8B94A6);
  static const Color danger = Color(0xFFFF5C5C);
  static const Color ok = Color(0xFF43D17C);

  static const String monoFont =
      'monospace'; // falls back to platform mono on Android/iOS

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      surface: surface,
      error: danger,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: textDim,
        textColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: const TextStyle(color: textDim),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceAlt,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
