// Web-only wrapper for the Fullscreen API. Loaded by the conditional import in
// [VideoPlayerScreen] only when `dart.library.js_interop` is available.

import 'package:web/web.dart' as web;

Future<void> requestFullscreen() async {
  web.document.documentElement?.requestFullscreen();
}

void exitFullscreen() {
  web.document.exitFullscreen();
}
