// Cross-platform clipboard copy. On non-web platforms this delegates to
// Flutter's [Clipboard]. The web build swaps in the `_web.dart` variant via the
// conditional import at each call site (guarded by `dart.library.js_interop`).

import 'package:flutter/services.dart';

/// Copies [text] to the clipboard. Returns true only if the write is believed
/// to have succeeded.
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}
