import 'package:flutter/material.dart';

/// VYRO brand palette.
///
/// A vivid streaming green (#00E676) on near-black (#0B0B0B), with cards on
/// charcoal (#1A1A1A). Surfaces are neutral greys — no green tint — so the
/// accent is the only green on screen. Light mint is reserved for active
/// states and highlights.
class AppColors {
  // Brand
  static const Color obsidian = Color(0xFF0B0B0B);
  static const Color deepForest = Color(0xFF0C2016);
  static const Color emeraldDeep = Color(0xFF00A854);
  static const Color emerald = Color(0xFF00E676);
  static const Color mint = Color(0xFF7CFFB2);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color mutedSilver = Color(0xFFA3A3A3);
  static const Color surfaceCharcoal = Color(0xFF1A1A1A);

  // Surfaces — neutral blacks and charcoals
  static const Color background = obsidian;
  static const Color surfaceDim = Color(0xFF101010);
  static const Color surfaceContainerLowest = Color(0xFF050505);
  static const Color surfaceContainerLow = Color(0xFF141414);
  static const Color surfaceContainer = surfaceCharcoal;
  static const Color surfaceContainerHigh = Color(0xFF222222);
  static const Color surfaceContainerHighest = Color(0xFF2B2B2B);
  static const Color surfaceBright = Color(0xFF343434);

  // On-surface
  static const Color onSurface = pureWhite;
  static const Color onSurfaceVariant = mutedSilver;
  static const Color onSurfaceMuted = Color(0x72FFFFFF);
  static const Color onSurfaceDisabled = Color(0x44FFFFFF);

  // Primary — streaming green
  static const Color primary = emerald;
  static const Color primaryLight = mint;
  static const Color primaryContainer = deepForest;
  static const Color onPrimary = Color(0xFF0A0A0A);
  static const Color primaryGlow = Color(0x2200E676);

  // Secondary — the same green carries the CTAs; active text uses mint
  static const Color secondary = emerald;
  static const Color secondaryDark = emeraldDeep;
  static const Color onSecondary = onPrimary;

  // Outline
  static const Color outline = Color(0xFF8E8E8E);
  static const Color outlineVariant = Color(0xFF2E2E2E);

  // Tertiary
  static const Color tertiary = mint;

  // Error
  static const Color error = Color(0xFFFFB4AB);

  // Utility
  static const Color white = pureWhite;
  static const Color transparent = Colors.transparent;

  /// Background used by nav highlights and active pills: a green wash, not a
  /// solid fill.
  static const Color accentTint = Color(0x2E00E676);
  static const Color accentBorder = Color(0x7300E676);

  // Gradients
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x000B0B0B),
      Color(0x590B0B0B),
      Color(0xC70B0B0B),
      Color(0xFF0B0B0B),
    ],
    stops: [0.0, 0.35, 0.72, 1.0],
  );

  static const LinearGradient posterGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      Color(0xCC000000),
    ],
    stops: [0.45, 1.0],
  );

  /// Brand primary: #00A854 → #00E676.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [emeraldDeep, emerald],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Brand highlight: #00E676 → #7CFFB2.
  static const LinearGradient highlightGradient = LinearGradient(
    colors: [emerald, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background: near-black → charcoal.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [obsidian, Color(0xFF151515)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient exclusiveGradient = LinearGradient(
    colors: [Color(0xFF202020), Color(0xFF0D0D0D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
