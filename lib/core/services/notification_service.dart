import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';
import '../models/movie.dart';
import '../providers/movie_provider.dart';
import 'library_service.dart';
import 'media_delivery_service.dart';
import 'media_orchestrator_service.dart';
import 'os_notifications.dart';
import 'settings_service.dart';

/// In-app notification center.
///
/// There is no OS push channel (no FCM on this app), so notifications are
/// generated locally from data the app already fetches:
///  - New Movie Releases  → the "New Releases" home row   (notifyNewMovies)
///  - New Episodes        → the "Trending TV Shows" row   (notifyNewEpisodes)
///  - Premiere Reminders  → TMDB upcoming releases        (notifyPremiere)
///  - Download Completed  → MediaDeliveryService hook     (notifyDownloads)
///  - Watchlist Updates   → LibraryService watchlist diff (notifyWatchlist)
///  - Jump Back In        → library continue-watching     (notifyContinueWatching)
///
/// Every entry has a stable id (type + entity id) so regenerating feeds never
/// duplicates it. The whole inbox is persisted to SharedPreferences and capped
/// at [_maxItems]; the master [SettingsService.notificationsEnabled] switch
/// gates every generator.
///
/// Two delivery paths: an immediate OS banner for events the user just caused,
/// and [_rescheduleUpcoming] handing a small set of reminders to the OS alarm
/// manager so they still arrive when the app process is closed.
class NotificationService extends ChangeNotifier {
  static const _prefsKey = 'notifications_v1';
  static const _maxItems = 40;

  final SettingsService _settings;
  final List<AppNotification> _items = [];
  SharedPreferences? _prefs;

  MovieProvider? _provider;
  LibraryService? _library;
  MediaOrchestratorService? _orchestrator;
  Set<String>? _watchlistIds;
  bool _homeFeedsDone = false;

  NotificationService(this._settings);

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.isRead).length;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final reminders = _prefs?.getString(_remindersKey);
    if (reminders != null) {
      try {
        final decoded = jsonDecode(reminders);
        if (decoded is Map) {
          _premiereReminders.addAll(
              decoded.map((k, v) => MapEntry('$k', '$v')));
        }
      } catch (_) {
        // Corrupt store — the button just starts unset.
      }
    }
    final raw = _prefs?.getString(_prefsKey);
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as List)) {
          _items.add(AppNotification.fromJson(e as Map<String, dynamic>));
        }
      } catch (_) {
        // Corrupt store — start fresh rather than crash the app.
        _items.clear();
      }
      _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  /// Binds the generators to the live services. Called once from main().
  void attach({
    required MovieProvider provider,
    required LibraryService library,
    required MediaOrchestratorService orchestrator,
  }) {
    _provider = provider;
    _library = library;
    _orchestrator = orchestrator;
    _watchlistIds = library.watchlist.map((m) => m.id).toSet();
    provider.addListener(_onProviderChanged);
    library.addListener(_onLibraryChanged);
    // The library may already hold items before any listener fires.
    _generateFromLibrary();
    _rescheduleUpcoming();
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    _library?.removeListener(_onLibraryChanged);
    super.dispose();
  }

  // ── Generators ─────────────────────────────────────────────────────────────

  void _onProviderChanged() {
    if (_homeFeedsDone ||
        _provider == null ||
        _provider!.homeState != LoadState.loaded) {
      return;
    }
    _homeFeedsDone = true;
    _generateFromHomeFeeds();
  }

  Future<void> _generateFromHomeFeeds() async {
    if (!_settings.notificationsEnabled || _provider == null) return;
    final p = _provider!;
    final now = DateTime.now();
    final fresh = <AppNotification>[];

    if (_settings.notifyNewMovies) {
      for (final m in p.nowPlaying.take(6)) {
        fresh.add(AppNotification(
          id: 'movie:${m.id}',
          type: AppNotificationType.newMovie,
          title: 'New release: ${m.title}',
          body: _blurb(m, fallback: 'Streaming now on Vyro.'),
          imageUrl: m.imageUrl,
          createdAt: now,
          movieJson: m.toJson(),
        ));
      }
    }

    if (_settings.notifyNewEpisodes) {
      for (final m in p.trendingTV.take(6)) {
        fresh.add(AppNotification(
          id: 'episode:${m.id}',
          type: AppNotificationType.newEpisode,
          title: 'New episodes: ${m.title}',
          body: m.isTrending
              ? 'A new season is drawing crowds — catch up now.'
              : 'New episodes are streaming now.',
          imageUrl: m.imageUrl,
          createdAt: now,
          movieJson: m.toJson(),
        ));
      }
    }

    if (_settings.notifyPremiere && _orchestrator != null) {
      try {
        final upcoming = await _orchestrator!.fetchUpcoming(limit: 6);
        for (final m in upcoming) {
          fresh.add(AppNotification(
            id: 'premiere:${m.id}',
            type: AppNotificationType.premiere,
            title: 'Coming soon: ${m.title}',
            body: m.year > 0
                ? 'Premiering ${m.year}. Add it to your watchlist so you don\'t miss it.'
                : 'Premiering soon. Add it to your watchlist so you don\'t miss it.',
            imageUrl: m.imageUrl,
            createdAt: now,
            movieJson: m.toJson(),
          ));
        }
      } catch (_) {
        // Upcoming feed is optional; the rest still lands.
      }
    }

    _addUnique(fresh, osCount: 3);
    _rescheduleUpcoming();
  }

  void _onLibraryChanged() {
    if (!_settings.notificationsEnabled || _library == null) return;
    final current = _library!.watchlist.map((m) => m.id).toSet();
    final prev = _watchlistIds;
    _watchlistIds = current;
    if (prev == null) return;

    final added =
        _library!.watchlist.where((m) => !prev.contains(m.id)).toList();
    // A wholesale change (profile switch / Trakt sync) is a resync, not news.
    if (_settings.notifyWatchlist && added.isNotEmpty && added.length <= 5) {
      final now = DateTime.now();
      _addUnique(
          added.take(3).map((m) => AppNotification(
                id: 'watchlist:${m.id}',
                type: AppNotificationType.watchlist,
                title: 'Added to your Watchlist',
                body: '${m.title} will be waiting for you in your watchlist.',
                imageUrl: m.imageUrl,
                createdAt: now,
                movieJson: m.toJson(),
              )),
          osCount: 3);
    }
    _generateFromLibrary();
    _rescheduleUpcoming();
  }

  void _generateFromLibrary() {
    if (!_settings.notificationsEnabled ||
        _library == null ||
        !_settings.notifyContinueWatching) {
      return;
    }
    final now = DateTime.now();
    final fresh = <AppNotification>[];
    for (final m in _library!.continueWatching.take(4)) {
      if ((m.watchProgress ?? 0) <= 0) continue;
      final pct = ((m.watchProgress ?? 0) * 100).round();
      fresh.add(AppNotification(
        id: 'resume:${m.id}',
        type: AppNotificationType.continueWatching,
        title: 'Jump back in: ${m.title}',
        body: 'You stopped at $pct% — pick up where you left off.',
        imageUrl: m.imageUrl,
        createdAt: now,
        movieJson: m.toJson(),
      ));
    }
    _addUnique(fresh, osCount: 2);
  }

  /// Hook registered on MediaDeliveryService.addOnCompleteCallback.
  /// The delivery service already gates this on SettingsService.notifyDownloads.
  void onDownloadComplete(DownloadItem item) {
    if (!_settings.notificationsEnabled) return;
    _addUnique([
      AppNotification(
        id: 'download:${item.id}',
        type: AppNotificationType.download,
        title: 'Download complete',
        body: '${item.title} (${item.size}) is ready to watch offline.',
        imageUrl: item.imageUrl,
        createdAt: DateTime.now(),
      ),
    ], osCount: 1);
  }

  // ── User premiere reminders ────────────────────────────────────────────────

  static const _remindersKey = 'premiere_reminders_v1';

  /// Movie ids the user tapped "Remind Me" on → the local slot handed to the OS
  /// alarm manager. Separate from [_plannedKey] on purpose: that map is rebuilt
  /// from generated drafts and cancels anything it doesn't recognise, which
  /// would silently drop a hand-picked reminder.
  final Map<String, String> _premiereReminders = {};

  bool hasPremiereReminder(Movie m) => _premiereReminders.containsKey(m.id);

  /// Schedules (or, when already set, cancels) the OS reminder for [m].
  Future<void> togglePremiereReminder(Movie m) async {
    final key = 'sched:premiere:${m.id}';
    if (_premiereReminders.remove(m.id) != null) {
      await OsNotifications.cancel(key);
      _persistReminders();
      // The receipt for setting it goes away with the reminder.
      _items.removeWhere((n) => n.id == _reminderNoteId(m));
      notifyListeners();
      _persist();
      return;
    }
    final at = _reminderSlotFor(m);
    _premiereReminders[m.id] = at.toIso8601String();
    await OsNotifications.schedule(
      key: key,
      title: 'Premiering tonight: ${m.title}',
      body: m.description.trim().isEmpty
          ? 'It just landed on Vyro.'
          : _blurb(m, fallback: 'It just landed on Vyro.'),
      at: at,
    );
    _persistReminders();
    // A reminder the user can't see anywhere but a button label reads as
    // unfinished, so the inbox keeps a receipt with the exact slot.
    _addUnique([
      AppNotification(
        id: _reminderNoteId(m),
        type: AppNotificationType.premiere,
        title: 'Reminder set: ${m.title}',
        body: 'We\'ll nudge you ${_formatSlot(at)} when it premieres.',
        imageUrl: m.imageUrl,
        createdAt: DateTime.now(),
        movieJson: m.toJson(),
      ),
    ]);
  }

  static String _reminderNoteId(Movie m) => 'premiere-reminder:${m.id}';

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String _formatSlot(DateTime at) {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final inDays = day.difference(today).inDays;
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final suffix = at.hour < 12 ? 'am' : 'pm';
    final when = inDays == 0
        ? 'tonight'
        : inDays == 1
            ? 'tomorrow'
            : inDays < 7
                ? _weekdays[day.weekday - 1]
                : '${_months[day.month - 1]} ${day.day}';
    return '$when at $hour$suffix';
  }

  /// 8pm on premiere day. TMDB dates are day-precision and the day itself is
  /// often already past by the time the user sees the card, so a slot that has
  /// gone falls through to the next evening.
  DateTime _reminderSlotFor(Movie m) {
    final now = DateTime.now();
    final day = m.releaseDate;
    var slot = day == null
        ? _nextEvening(now)
        : DateTime(day.year, day.month, day.day, _reminderHour);
    if (!slot.isAfter(now)) slot = _nextEvening(now);
    return slot;
  }

  DateTime _nextEvening(DateTime now) {
    final tonight = DateTime(now.year, now.month, now.day, _reminderHour);
    return tonight.isAfter(now) ? tonight : tonight.add(const Duration(days: 1));
  }

  void _persistReminders() {
    _prefs?.setString(_remindersKey, jsonEncode(_premiereReminders));
  }

  // ── App-closed reminders ───────────────────────────────────────────────────

  static const _plannedKey = 'notifications_planned_v1';

  /// Local hour the queued reminders land on.
  static const _reminderHour = 20;
  static const _maxScheduled = 3;

  bool _rescheduling = false;

  /// Hands the next few reminders to the OS alarm manager, which delivers them
  /// through the manifest receivers after this process is gone.
  ///
  /// The planned set is persisted so a launch doesn't push the same reminder
  /// forward forever: entries whose slot has passed are dropped and replaced,
  /// ones still pending are left alone.
  Future<void> _rescheduleUpcoming() async {
    if (_rescheduling) return;
    _rescheduling = true;
    try {
      final prefs = _prefs;
      if (prefs == null) return;
      final now = DateTime.now();
      final planned = _readPlanned();

      // A past slot means it already fired (or the device was off) — make room.
      planned.removeWhere((_, iso) {
        final at = DateTime.tryParse(iso);
        return at == null || !at.isAfter(now);
      });

      if (!_settings.notificationsEnabled) {
        for (final key in planned.keys) {
          await OsNotifications.cancel(key);
        }
        prefs.setString(_plannedKey, '{}');
        return;
      }

      // Content the user has since lost interest in shouldn't keep reminding.
      final drafts = _reminderDrafts();
      final wanted = drafts.map((d) => d.key).toSet();
      planned.removeWhere((key, _) {
        if (wanted.contains(key)) return false;
        OsNotifications.cancel(key);
        return true;
      });

      var dayOffset = 0;
      for (final draft in drafts) {
        if (planned.containsKey(draft.key)) continue;
        if (planned.length >= _maxScheduled) break;
        while (true) {
          final slot =
              DateTime(now.year, now.month, now.day + dayOffset, _reminderHour);
          dayOffset++;
          if (!slot.isAfter(now)) continue;
          if (planned.containsValue(slot.toIso8601String())) continue;
          await OsNotifications.schedule(
            key: draft.key,
            title: draft.title,
            body: draft.body,
            at: slot,
          );
          planned[draft.key] = slot.toIso8601String();
          break;
        }
      }
      prefs.setString(_plannedKey, jsonEncode(planned));
    } catch (_) {
      // Queuing is best-effort; the in-app inbox works regardless.
    } finally {
      _rescheduling = false;
    }
  }

  /// One reminder per notification type, most actionable first.
  List<({String key, String title, String body})> _reminderDrafts() {
    final drafts = <({String key, String title, String body})>[];
    final lib = _library;
    final p = _provider;

    if (lib != null && _settings.notifyContinueWatching) {
      for (final m in lib.continueWatching) {
        final progress = m.watchProgress ?? 0;
        if (progress <= 0) continue;
        drafts.add((
          key: 'sched:resume:${m.id}',
          title: 'Finish what you started',
          body: '${m.title} — you stopped at ${(progress * 100).round()}%.',
        ));
        break;
      }
    }
    if (lib != null && _settings.notifyWatchlist) {
      for (final m in lib.watchlist) {
        drafts.add((
          key: 'sched:watchlist:${m.id}',
          title: 'Still on your watchlist',
          body: '${m.title} is ready whenever you are.',
        ));
        break;
      }
    }
    if (p != null && _settings.notifyNewMovies) {
      for (final m in p.nowPlaying) {
        drafts.add((
          key: 'sched:new:${m.id}',
          title: 'Watch tonight',
          body: '${m.title} just landed on Vyro.',
        ));
        break;
      }
    }
    if (p != null && _settings.notifyNewEpisodes) {
      for (final m in p.trendingTV) {
        drafts.add((
          key: 'sched:episode:${m.id}',
          title: 'New episodes tonight',
          body: '${m.title} has fresh episodes waiting.',
        ));
        break;
      }
    }
    return drafts.take(_maxScheduled + 1).toList();
  }

  Map<String, String> _readPlanned() {
    final raw = _prefs?.getString(_plannedKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {
      // Corrupt store — requeue from scratch.
    }
    return {};
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void markAsRead(String id) {
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx == -1 || _items[idx].isRead) return;
    _items[idx] = _items[idx].copyWith(isRead: true);
    notifyListeners();
    _persist();
  }

  void markAllRead() {
    if (_items.every((n) => n.isRead)) return;
    for (var i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isRead: true);
    }
    notifyListeners();
    _persist();
  }

  void remove(String id) {
    final before = _items.length;
    _items.removeWhere((n) => n.id == id);
    if (_items.length == before) return;
    notifyListeners();
    _persist();
  }

  void clearAll() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    _persist();
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  String _blurb(Movie m, {required String fallback}) {
    if (m.description.isEmpty) return fallback;
    final t = m.description.trim();
    return t.length <= 90 ? t : '${t.substring(0, 90)}…';
  }

  void _addUnique(Iterable<AppNotification> incoming, {int osCount = 0}) {
    final existing = _items.map((n) => n.id).toSet();
    final added = <AppNotification>[];
    for (final n in incoming) {
      if (existing.contains(n.id) || n.id.isEmpty) continue;
      existing.add(n.id);
      _items.add(n);
      added.add(n);
    }
    if (added.isEmpty) return;
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
    notifyListeners();
    _persist();
    // Post the OS banner for the most relevant new items. [osCount] caps how
    // many so the first-run feed bootstrap (many items at once) doesn't spam
    // the shade; interactive events (download/watchlist) send their own.
    for (final n in added.take(osCount)) {
      OsNotifications.show(key: n.id, title: n.title, body: n.body);
    }
  }

  void _persist() {
    _prefs?.setString(
        _prefsKey, jsonEncode(_items.map((n) => n.toJson()).toList()));
  }
}
