// Web / unsupported-platform no-op implementation of the OS notification
// facade. Notifications still land in the in-app center; the operating-system
// banner is simply skipped where there is no native support.
//
// Web is deliberately excluded: a browser notification that survives the tab
// being closed needs a hosted service worker plus a push service and VAPID
// keys, i.e. a server this app doesn't have.
class OsNotifications {
  static Future<void> initialize() async {}

  static Future<void> show({
    required String key,
    required String title,
    required String body,
  }) async {}

  static Future<void> schedule({
    required String key,
    required String title,
    required String body,
    required DateTime at,
  }) async {}

  static Future<void> showDownloadProgress({
    required String key,
    required String title,
    required int progress,
    String? body,
  }) async {}

  static Future<void> showDownloadComplete({
    required String key,
    required String title,
    String? body,
  }) async {}

  static Future<void> cancelDownload(String key) async {}

  static Future<void> cancel(String key) async {}
}
