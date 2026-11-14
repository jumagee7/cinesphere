// No-op stub for platforms that don't support dart:html (Android, iOS, Windows,
// macOS, Linux). This file is loaded by the conditional import in
// [VideoPlayerScreen] when `dart.library.js_interop` is not available, and the
// public API below is never actually called on non-web platforms (the call
// site always checks `kIsWeb` first).

Future<void> requestFullscreen() async {}
void exitFullscreen() {}
