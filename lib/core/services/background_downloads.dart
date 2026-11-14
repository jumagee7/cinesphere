import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps transfers running while Vyro is backgrounded.
///
/// Android throttles and freezes network work of a backgrounded app unless a
/// data-sync foreground service is running. This wrapper starts exactly such a
/// service (plus a partial wake lock) for as long as the download queue has an
/// active item, so the Dart isolate and its sockets stay alive with the screen
/// off. Everywhere else it is a no-op.
class BackgroundDownloads {
  BackgroundDownloads._();

  static const MethodChannel _channel = MethodChannel('cinesphere/downloads');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Starts the keep-alive service, or refreshes its label when it already
  /// runs. Safe to call repeatedly.
  static Future<void> start({String label = 'Downloading media…'}) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('start', {'label': label});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
