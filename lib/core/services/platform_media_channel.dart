import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel wrapper for native Android multimedia features (PiP, TrafficStats, Video Preview scrubbing).
class PlatformMediaChannel {
  static const MethodChannel _previewChannel =
      MethodChannel('cinesphere/video_preview');
  static const MethodChannel _statsChannel = MethodChannel('cinesphere/stats');
  static const MethodChannel _pipChannel = MethodChannel('pip_channel');

  /// Fetches a scrubbing preview thumbnail for a given video path and timestamp.
  static Future<Uint8List?> getVideoThumbnail({
    required String videoPath,
    required int timeMs,
    int width = 180,
    int height = 100,
    Map<String, String>? headers,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final res =
          await _previewChannel.invokeMethod<Uint8List>('getVideoThumbnail', {
        'videoPath': videoPath,
        'timeMs': timeMs,
        'width': width,
        'height': height,
        'headers': headers,
      });
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Fetches real-time download/stream bandwidth in bytes per second via Android TrafficStats.
  static Future<int> getNetworkSpeed() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 0;
    }
    try {
      final res = await _statsChannel.invokeMethod<num>('getNetworkSpeed');
      return res?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Enters Picture-in-Picture mode on Android (API 26+) with remote media actions.
  static Future<bool> enterPip(
      {bool isPlaying = true, bool enablePip = true}) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !enablePip) {
      return false;
    }
    try {
      final res = await _pipChannel
          .invokeMethod<bool>('enterPip', {'isPlaying': isPlaying});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> Function(String action)? _actionHandler;
  static ValueChanged<bool>? _modeHandler;

  /// Registers Dart handlers for PiP window remote controls (play / pause /
  /// rewind / forward) and for activity PiP mode changes.
  static void listen({
    required Future<void> Function(String action) onAction,
    ValueChanged<bool>? onModeChanged,
  }) {
    _actionHandler = onAction;
    _modeHandler = onModeChanged;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged') {
        final args = call.arguments;
        final isInPip = args is Map && args['isInPip'] == true;
        _modeHandler?.call(isInPip);
      } else {
        await _actionHandler?.call(call.method);
      }
    });
  }

  /// Removes the PiP handlers. Safe to call when nothing was registered.
  static void stopListening() {
    _actionHandler = null;
    _modeHandler = null;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _pipChannel.setMethodCallHandler(null);
  }

  /// Whether the activity is currently showing in a PiP window.
  static Future<bool> isInPip() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final res = await _pipChannel.invokeMethod<bool>('isInPip');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if Picture-in-Picture is supported on the current device.
  static Future<bool> isPipSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final res = await _pipChannel.invokeMethod<bool>('isPipSupported');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Updates current playback state for PiP notification controls.
  static Future<void> updatePipPlayState({required bool isPlaying}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _pipChannel
          .invokeMethod('updatePlayState', {'isPlaying': isPlaying});
    } catch (_) {}
  }

  /// Toggles automatic PiP entry when the user navigates away from the player.
  static Future<void> setAutoPip(
      {required bool enable, bool enablePip = true}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _pipChannel
          .invokeMethod('setAutoPip', {'enable': enable && enablePip});
    } catch (_) {}
  }

  static const MethodChannel _muxChannel =
      MethodChannel('cinesphere/media_mux');

  /// Remuxes concatenated MPEG-TS segments into a single MP4 file without
  /// re-encoding. Returns false when unsupported or when the codecs in the
  /// segments cannot be carried by an MP4 container.
  static Future<bool> muxTsToMp4({
    required String videoPath,
    String? audioPath,
    required String outputPath,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final res = await _muxChannel.invokeMethod<bool>('muxTsToMp4', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
