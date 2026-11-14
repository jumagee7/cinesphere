// Web-only clipboard copy. The async Clipboard API (`navigator.clipboard`)
// requires a secure context (https/localhost) and transient user activation;
// over plain http it throws or is undefined. When it isn't available we fall
// back to a hidden <textarea> + `document.execCommand('copy')`, which works in
// non-secure contexts and still counts as a user-initiated copy.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> copyToClipboard(String text) async {
  final clipboard = web.window.navigator.clipboard;
  // ignore: unnecessary_null_comparison — clipboard can be JS undefined/null
  if (clipboard != null) {
    try {
      await clipboard.writeText(text).toDart;
      return true;
    } catch (_) {
      // Fall through to the legacy path below.
    }
  }

  final area = web.HTMLTextAreaElement()
    ..value = text
    ..setAttribute('readonly', '')
    ..style.position = 'fixed'
    ..style.top = '-1000px'
    ..style.opacity = '0';
  web.document.body?.append(area);
  area.select();
  area.setSelectionRange(0, text.length);
  bool ok = false;
  try {
    ok = web.document.execCommand('copy');
  } catch (_) {
    ok = false;
  }
  area.remove();
  return ok;
}
