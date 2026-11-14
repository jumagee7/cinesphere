import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get darkTheme => buildTheme(useOledBlack: false);

  static ThemeData buildTheme({required bool useOledBlack}) {
    final background =
        useOledBlack ? const Color(0xFF000000) : AppColors.background;
    final surfaceContainer =
        useOledBlack ? const Color(0xFF121212) : AppColors.surfaceContainer;
    final surfaceContainerLow =
        useOledBlack ? const Color(0xFF0D0D0D) : AppColors.surfaceContainerLow;
    final surfaceContainerHigh =
        useOledBlack ? const Color(0xFF191919) : AppColors.surfaceContainerHigh;
    final surfaceContainerHighest = useOledBlack
        ? const Color(0xFF202020)
        : AppColors.surfaceContainerHighest;
    final bottomNavBg =
        useOledBlack ? const Color(0xFF000000) : AppColors.surfaceContainerHigh;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        surface: surfaceContainer,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
      ).copyWith(
        surfaceContainerLowest: useOledBlack
            ? const Color(0xFF000000)
            : AppColors.surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
      ),
      textTheme: GoogleFonts.montserratTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: AppColors.white,
          ),
          headlineLarge: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.white,
          ),
          headlineMedium: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: AppColors.white,
          ),
          headlineSmall: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.white,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.16,
            color: AppColors.onSurfaceVariant,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.14,
            color: AppColors.onSurfaceVariant,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.24,
            color: AppColors.onSurfaceMuted,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.14,
            color: AppColors.white,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.36,
            color: AppColors.white,
          ),
          labelSmall: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.white),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bottomNavBg,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.onSurfaceMuted,
        type: BottomNavigationBarType.fixed,
      ),
      iconTheme: const IconThemeData(color: AppColors.onSurface),
      dividerColor: AppColors.outlineVariant,
      // ── SnackBar theme — white text on dark surface everywhere ──────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        contentTextStyle: GoogleFonts.montserrat(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.white,
          letterSpacing: 0.1,
        ),
        actionTextColor: AppColors.primaryLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
    );
  }

  // Text style helpers
  static TextStyle get heroTitle => GoogleFonts.montserrat(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: AppColors.white,
      );

  static TextStyle get sectionTitle => GoogleFonts.montserrat(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: AppColors.white,
      );

  static TextStyle get cardTitle => GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: AppColors.white,
      );

  static TextStyle get badge => GoogleFonts.montserrat(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.white,
      );

  static TextStyle get metadata => GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: AppColors.onSurfaceVariant,
      );
}
