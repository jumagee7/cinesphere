import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Paints the VYRO "V" mark. One stroke, one ink — it degrades cleanly to
/// monochrome and stays legible down to launcher-icon sizes.
///
/// The same chevron is the silhouette of a play arrow when turned on its side,
/// so the mark carries the streaming cue without extra glyphs.
class VyroMarkPainter extends CustomPainter {
  /// Stroke reveal for the V, 0 (nothing) → 1 (full mark).
  final double draw;

  /// Light sweep across the stroke, 0 (hidden) → 1 (passed).
  final double sweep;

  /// Render in a single ink (white by default) for mono contexts.
  final bool monochrome;
  final Color monochromeColor;

  VyroMarkPainter({
    this.draw = 1,
    this.sweep = 0,
    this.monochrome = false,
    this.monochromeColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final vPath = Path()
      ..moveTo(0.23 * s, 0.23 * s)
      ..lineTo(0.50 * s, 0.79 * s)
      ..lineTo(0.77 * s, 0.23 * s);

    final shader = monochrome
        ? null
        : const LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [
              AppColors.emerald,
              AppColors.mint,
            ],
          ).createShader(Rect.fromLTWH(0, 0, s, s));
    final ink = monochrome ? monochromeColor : null;

    // Soft bloom under the stroke, like a projector lamp warming up.
    if (draw > 0) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.15 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = (ink ?? AppColors.emerald).withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.07 * s);
      canvas.drawPath(_revealed(vPath, draw), glowPaint);
    }

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.135 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = shader
      ..color = ink ?? Colors.white;
    canvas.drawPath(_revealed(vPath, draw), strokePaint);

    if (sweep > 0 && sweep < 1 && !monochrome) {
      final band = 0.42 * s;
      final left = -band + sweep * (s + band * 2);
      final sweepPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.135 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset(left, 0),
          Offset(left + band, 0),
          [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.85),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawPath(vPath, sweepPaint);
    }
  }

  Path _revealed(Path path, double progress) {
    if (progress >= 1) return path;
    if (progress <= 0) return Path();
    final metrics = path.computeMetrics().first;
    return metrics.extractPath(0, metrics.length * progress);
  }

  @override
  bool shouldRepaint(VyroMarkPainter old) =>
      old.draw != draw ||
      old.sweep != sweep ||
      old.monochrome != monochrome ||
      old.monochromeColor != monochromeColor;
}

/// Bare V mark, sized by [size].
class VyroMark extends StatelessWidget {
  final double size;
  final bool monochrome;
  final Color monochromeColor;
  final double draw;
  final double sweep;

  const VyroMark({
    super.key,
    required this.size,
    this.monochrome = false,
    this.monochromeColor = Colors.white,
    this.draw = 1,
    this.sweep = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: VyroMarkPainter(
          draw: draw,
          sweep: sweep,
          monochrome: monochrome,
          monochromeColor: monochromeColor,
        ),
      ),
    );
  }
}

/// App-logo lockup: the V mark on a charcoal tile, used in headers and auth.
class VyroLogo extends StatelessWidget {
  final double size;

  /// Single-ink rendering for contexts where brand colour is unavailable.
  final bool monochrome;
  final Color monochromeColor;

  /// Rounded tile behind the mark. Off for bare placements.
  final bool badge;

  const VyroLogo({
    super.key,
    this.size = 40,
    this.monochrome = false,
    this.monochromeColor = Colors.white,
    this.badge = true,
  });

  @override
  Widget build(BuildContext context) {
    final mark = VyroMark(
      size: size,
      monochrome: monochrome,
      monochromeColor: monochromeColor,
    );
    if (!badge) {
      return Semantics(label: 'Vyro', image: true, child: mark);
    }
    return Semantics(
      label: 'Vyro',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: monochrome
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.deepForest, AppColors.obsidian],
                ),
          color: monochrome ? monochromeColor.withValues(alpha: 0.08) : null,
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: monochrome
              ? null
              : [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.35),
                    blurRadius: size * 0.42,
                    offset: Offset(0, size * 0.08),
                  ),
                ],
        ),
        padding: EdgeInsets.all(size * 0.18),
        child: mark,
      ),
    );
  }
}
