import 'package:flutter/material.dart';

class NcstColors {
  // Official NCST Core Brand Colors
  static const Color navy = Color(0xFF1A3B8B);
  static const Color navyDark = Color(0xFF0F265C);
  static const Color navyLight = Color(0xFF2B4EA2);

  static const Color gold = Color(0xFFF5B800);
  static const Color goldLight = Color(0xFFFFD54F);
  static const Color goldDark = Color(0xFFC69200);

  static const Color crimson = Color(0xFFD92128);
  static const Color crimsonLight = Color(0xFFFEE2E2);

  // Status & Semantic Colors
  static const Color green = Color(0xFF16A34A);
  static const Color greenLight = Color(0xFFDCFCE7);

  // Neutrals & Surfaces
  static const Color white = Color(0xFFFFFFFF);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);
}

class NcstTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: NcstColors.slate50,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: NcstColors.navy,
        onPrimary: NcstColors.white,
        primaryContainer: Color(0xFFE0E7FF),
        onPrimaryContainer: NcstColors.navyDark,
        secondary: NcstColors.gold,
        onSecondary: NcstColors.navyDark,
        secondaryContainer: Color(0xFFFEF3C7),
        onSecondaryContainer: NcstColors.goldDark,
        error: NcstColors.crimson,
        onError: NcstColors.white,
        surface: NcstColors.white,
        onSurface: NcstColors.slate800,
        outline: NcstColors.slate200,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NcstColors.navy,
        foregroundColor: NcstColors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: NcstColors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: NcstColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: NcstColors.slate200, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: NcstColors.slate200,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
