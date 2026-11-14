// Platform-facing OS notification helper.
//
// The web build has no `dart:io` and flutter_local_notifications' Android API
// is native-only, so this facade swaps implementations at compile time:
//  - native (Android/iOS/etc, `dart.library.io`) → an OsNotifications backed
//    by flutter_local_notifications.
//  - web → a no-op stub, so the plugin is never linked into the web bundle.
//
// Callers just use `OsNotifications.initialize()` / `.show(...)` and the
// correct implementation is selected automatically.
export 'os_notifications_stub.dart'
    if (dart.library.io) 'os_notifications_native.dart';
