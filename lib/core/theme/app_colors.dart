import 'package:flutter/material.dart';

/// VYRO brand palette.
///
/// Signature colour is Emerald Green (#059669) on Obsidian Black (#07110D).
/// Mint is reserved for active states and highlights; surfaces stay dark and
/// carry a faint forest-green tint so they read as the same family as the
/// background.
class AppColors {
  // Brand
  static const Color obsidian = Color(0xFF07110D);
  static const Color deepForest = Color(0xFF10271C);
  static const Color emeraldDeep = Color(0xFF047857);
  static const Color emerald = Color(0xFF059669);
  static const Color mint = Color(0xFF34D399);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color mutedSilver = Color(0xFF94A3A0);
  static const Color surfaceCharcoal = Color(0xFF14201A);

  // Surfaces
  static const Color background = obsidian;
  static const Color surfaceDim = Color(0xFF0A1611);
  static const Color surfaceContainerLowest = Color(0xFF040C08);
  static const Color surfaceContainerLow = Color(0xFF0C1812);
  static const Color surfaceContainer = surfaceCharcoal;
  static const Color surfaceContainerHigh = Color(0xFF1B2B23);
  static const Color surfaceContainerHighest = Color(0xFF23372C);
  static const Color surfaceBright = Color(0xFF2E463A);

  // On-surface
  static const Color onSurface = pureWhite;
  static const Color onSurfaceVariant = mutedSilver;
  static const Color onSurfaceMuted = Color(0x72FFFFFF);
  static const Color onSurfaceDisabled = Color(0x44FFFFFF);

  // Primary — Emerald Green
  static const Color primary = emerald;
  static const Color primaryLight = mint;
  static const Color primaryContainer = deepForest;
  static const Color onPrimary = pureWhite;
  static const Color primaryGlow = Color(0x1F059669);

  // Secondary — Mint highlight
  static const Color secondary = mint;
  static const Color secondaryDark = deepForest;
  static const Color onSecondary = pureWhite;

  // Outline
  static const Color outline = mutedSilver;
  static const Color outlineVariant = Color(0xFF2A4136);

  // Tertiary
  static const Color tertiary = mint;

  // Error
  static const Color error = Color(0xFFFFB4AB);

  // Utility
  static const Color white = pureWhite;
  static const Color transparent = Colors.transparent;

  // Gradients
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x0007110D),
      Color(0x8807110D),
      obsidian,
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient posterGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      Color(0xCC000000),
    ],
    stops: [0.5, 1.0],
  );

  /// Brand primary: #047857 → #059669.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [emeraldDeep, emerald],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Brand highlight: #059669 → #34D399.
  static const LinearGradient highlightGradient = LinearGradient(
    colors: [emerald, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background: Obsidian Black → Surface Charcoal.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [obsidian, surfaceCharcoal],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient exclusiveGradient = LinearGradient(
    colors: [Color(0xFF0F2A20), Color(0xFF071A13)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
