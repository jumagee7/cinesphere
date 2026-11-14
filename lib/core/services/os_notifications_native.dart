import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// Native (Android) implementation of the OS notification facade, backed by
// flutter_local_notifications. On iOS the plugin API exists but this app has
// no iOS notification target configured, so behavior is Android-only.
class OsNotifications {
  static const _channelId = 'cinesphere_updates';
  static const _channelName = 'Vyro updates';
  static const _channelDesc =
      'New releases, episodes, premieres, downloads and watchlist activity.';

  static const _downloadChannelId = 'cinesphere_downloads';
  static const _downloadChannelName = 'Vyro downloads';
  static const _downloadChannelDesc = 'Ongoing media download progress.';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _details = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDesc,
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(''),
  );

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    // zonedSchedule needs the timezone database loaded before it can build a
    // TZDateTime. The absolute instant is what matters for an alarm, so the
    // default local location is fine and no device-zone lookup is needed.
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification_icon'),
      ),
    );
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    await impl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _downloadChannelId,
        _downloadChannelName,
        description: _downloadChannelDesc,
        importance: Importance.low,
        showBadge: false,
      ),
    );
    // Android 13+ runtime permission. No-op on older API levels where the
    // permission is granted at install.
    await impl?.requestNotificationsPermission();
  }

  static int _idFor(String key) => key.hashCode;

  static Future<void> show({
    required String key,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    // Stable per-item id so re-showing the same notification replaces it
    // instead of stacking duplicates.
    await _plugin.show(
      id: _idFor(key),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: _details),
    );
  }

  /// Displays or updates an ongoing Android notification showing a progress bar.
  static Future<void> showDownloadProgress({
    required String key,
    required String title,
    required int progress,
    String? body,
  }) async {
    if (!Platform.isAndroid) return;
    final downloadDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: _downloadChannelDesc,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progress.clamp(0, 100),
      ongoing: true,
      onlyAlertOnce: true,
      autoCancel: false,
    );

    await _plugin.show(
      id: _idFor('dl_$key'),
      title: title,
      body: body ?? '$progress% downloaded',
      notificationDetails: NotificationDetails(android: downloadDetails),
    );
  }

  /// Dismisses ongoing progress notification and shows a high-priority completion notification.
  static Future<void> showDownloadComplete({
    required String key,
    required String title,
    String? body,
  }) async {
    if (!Platform.isAndroid) return;
    await cancelDownload(key);

    const completeDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );

    await _plugin.show(
      id: _idFor('complete_$key'),
      title: 'Download complete',
      body: body ?? '"$title" is ready to watch offline',
      notificationDetails: const NotificationDetails(android: completeDetails),
    );
  }

  /// Cancels any active download progress notification for [key].
  static Future<void> cancelDownload(String key) async {
    if (!Platform.isAndroid) return;
    await _plugin.cancel(id: _idFor('dl_$key'));
  }

  /// Queues a notification with AlarmManager, which delivers it through the
  /// manifest receivers even when this process is gone.
  static Future<void> schedule({
    required String key,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    if (!Platform.isAndroid) return;
    if (!at.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: _idFor(key),
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(android: _details),
      // Inexact keeps us out of the SCHEDULE_EXACT_ALARM permission review;
      // the OS may defer it by minutes while dozing, which is acceptable for
      // an evening reminder.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Cancels both the banner and any queued alarm for [key].
  static Future<void> cancel(String key) async {
    if (!Platform.isAndroid) return;
    await _plugin.cancel(id: _idFor(key));
  }
}
