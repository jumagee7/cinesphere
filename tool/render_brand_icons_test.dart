// One-off asset renderer: paints the VYRO mark into launcher / web icons.
// Run with: flutter test tool/render_brand_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cinesphere/core/theme/app_colors.dart';
import 'package:cinesphere/shared/widgets/vyro_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _render(
  String path,
  int size, {
  bool rounded = true,
  bool transparent = false,
  double markScale = 0.62,
  bool monochrome = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();
  final rect = Rect.fromLTWH(0, 0, s, s);
  final bgShape = rounded
      ? RRect.fromRectAndRadius(rect, Radius.circular(s * 0.22))
      : RRect.fromRectAndRadius(rect, Radius.zero);

  if (!transparent) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.deepForest, AppColors.obsidian],
      ).createShader(rect);
    canvas.drawRRect(bgShape, bg);
    final bloom = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.emerald.withValues(alpha: 0.42),
          AppColors.deepForest.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 0.8],
      ).createShader(Rect.fromCircle(center: rect.center, radius: s * 0.62));
    canvas.drawRRect(bgShape, bloom);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.006
      ..color = Colors.white.withValues(alpha: 0.07);
    canvas.drawRRect(bgShape, edge);
  }

  final markSize = s * markScale;
  canvas.save();
  canvas.translate((s - markSize) / 2, (s - markSize) / 2);
  VyroMarkPainter(
    monochrome: monochrome,
    monochromeColor: Colors.white,
  ).paint(canvas, Size(markSize, markSize));
  canvas.restore();

  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  debugPrint('wrote $path ($size)');
}

void main() {
  test('render Vyro brand icons', () async {
    const android = 'android/app/src/main/res';
    final launchers = {
      '$android/mipmap-mdpi/ic_launcher.png': 48,
      '$android/mipmap-hdpi/ic_launcher.png': 72,
      '$android/mipmap-xhdpi/ic_launcher.png': 96,
      '$android/mipmap-xxhdpi/ic_launcher.png': 144,
      '$android/mipmap-xxxhdpi/ic_launcher.png': 192,
    };
    for (final e in launchers.entries) {
      await _render(e.key, e.value);
    }

    // In-app fallback art + the mono mark used wherever colour is not available.
    await _render('assets/images/app_icon.png', 512);
    await _render('assets/images/vyro_logo.png', 512);
    await _render('assets/images/vyro_mark_mono.png', 512,
        transparent: true, markScale: 0.72, monochrome: true);

    // Web: favicon + install icons. Maskable art keeps the mark in the safe zone.
    await _render('web/favicon.png', 64);
    await _render('web/icons/Icon-192.png', 192);
    await _render('web/icons/Icon-512.png', 512);
    await _render('web/icons/Icon-maskable-192.png', 192,
        rounded: false, markScale: 0.52);
    await _render('web/icons/Icon-maskable-512.png', 512,
        rounded: false, markScale: 0.52);

    // Native Android launch frame.
    await _render('$android/drawable/launch_image.png', 288,
        transparent: true, markScale: 0.9);
    await _render('$android/drawable-v21/launch_image.png', 288,
        transparent: true, markScale: 0.9);
  });
}
