import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:volume_controller/volume_controller.dart';

/// The system (hardware) volume, used by the video player while it is open.
///
/// The player takes ownership of the device's music stream: it reads the
/// current level as its starting volume, the vertical gesture moves the system
/// slider, and the entry level is written back when the player closes. Web has
/// no API for this, so callers fall back to the player's own volume there.
class DeviceVolume {
  DeviceVolume._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// The player draws its own volume HUD, so suppress the platform overlay
  /// while it is open; pass `false` to hand the overlay back on exit.
  static void configure({bool showSystemUI = false}) {
    if (!supported) return;
    try {
      VolumeController.instance.showSystemUI = showSystemUI;
    } catch (_) {}
  }

  static Future<double?> read() async {
    if (!supported) return null;
    try {
      final level = await VolumeController.instance.getVolume();
      return level.clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(double value) async {
    if (!supported) return;
    try {
      await VolumeController.instance.setVolume(value.clamp(0.0, 1.0));
    } catch (_) {}
  }

  /// Fires when the level changes outside the app (hardware keys, system UI).
  static StreamSubscription<double>? listen(void Function(double) onData) {
    if (!supported) return null;
    try {
      return VolumeController.instance.addListener(onData);
    } catch (_) {
      return null;
    }
  }

  static Future<void> stopListening() async {
    try {
      await VolumeController.instance.removeListener();
    } catch (_) {}
  }
}
