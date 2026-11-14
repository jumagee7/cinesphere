import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie.dart';
import 'background_downloads.dart';
import 'settings_service.dart';
import 'stream_resolver_service.dart';
import 'streaming_service.dart';
import 'tmdb_service.dart';
import 'download_engine.dart';
import 'platform_media_channel.dart';
import 'os_notifications.dart';
import 'js_scraper_bridge.dart';
import 'diagnostic_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Media Delivery Models
// ═══════════════════════════════════════════════════════════════════════════

/// A resolved, ready-to-play source for the native video player.
class PlayableSource {
  final String? url;
  final String? assetPath;
  final String title;
  final VideoQuality quality;
  final bool isOffline;
  final Map<String, String>? headers;
  final String? cdn;
  final List<SubtitleTrack> subtitles;
  final List<AudioTrackOption> audioTracks;
  final String? masterPlaylist;

  const PlayableSource({
    this.url,
    this.assetPath,
    required this.title,
    this.quality = VideoQuality.auto,
    this.isOffline = false,
    this.headers,
    this.cdn,
    this.subtitles = const [],
    this.audioTracks = const [],
    this.masterPlaylist,
  });

  bool get isRemote => url != null && url!.isNotEmpty;
}

/// Lifecycle status of an offline download.
enum DownloadStatus { pending, downloading, paused, completed, failed }

/// Represents an item in the offline download queue.
class DownloadItem {
  final String id;
  final String movieId;
  final String title;
  final String imageUrl;
  final String genre;
  final String duration;
  final String badge;
  final DownloadStatus status;
  final double progress; // 0.0 – 1.0
  final String size;
  final int sizeMb;
  final int? season;
  final int? episode;
  final String? seriesName;
  final String? episodeTitle;
  final String? speed;
  final int downloadedBytes;
  final int totalBytes;
  final VideoQuality quality;

  const DownloadItem({
    required this.id,
    required this.movieId,
    required this.title,
    required this.imageUrl,
    required this.genre,
    required this.duration,
    required this.badge,
    required this.status,
    required this.progress,
    required this.size,
    this.sizeMb = 0,
    this.season,
    this.episode,
    this.seriesName,
    this.episodeTitle,
    this.speed,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.quality = VideoQuality.fullHd1080,
  });

  bool get isComplete => status == DownloadStatus.completed;
  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.pending;

  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    String? size,
    int? sizeMb,
    String? speed,
    int? downloadedBytes,
    int? totalBytes,
    VideoQuality? quality,
  }) =>
      DownloadItem(
        id: id,
        movieId: movieId,
        title: title,
        imageUrl: imageUrl,
        genre: genre,
        duration: duration,
        badge: badge,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        size: size ?? this.size,
        sizeMb: sizeMb ?? this.sizeMb,
        season: season,
        episode: episode,
        seriesName: seriesName,
        episodeTitle: episodeTitle,
        speed: speed ?? this.speed,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        quality: quality ?? this.quality,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'movieId': movieId,
        'title': title,
        'imageUrl': imageUrl,
        'genre': genre,
        'duration': duration,
        'badge': badge,
        'status': status.index,
        'progress': progress,
        'size': size,
        'sizeMb': sizeMb,
        'season': season,
        'episode': episode,
        'seriesName': seriesName,
        'episodeTitle': episodeTitle,
        'quality': quality.index,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) {
    final rawStatus = (j['status'] as num?)?.toInt() ?? 0;
    final status = rawStatus >= 0 && rawStatus < DownloadStatus.values.length
        ? DownloadStatus.values[rawStatus]
        : DownloadStatus.pending;
    final rawQuality = (j['quality'] as num?)?.toInt();
    final quality = (rawQuality != null &&
            rawQuality >= 0 &&
            rawQuality < VideoQuality.values.length)
        ? VideoQuality.values[rawQuality]
        : VideoQuality.fullHd1080;
    return DownloadItem(
      id: j['id'] as String? ?? j['movieId'] as String,
      movieId: j['movieId'] as String,
      title: j['title'] as String? ?? '',
      imageUrl: j['imageUrl'] as String? ?? '',
      genre: j['genre'] as String? ?? '',
      duration: j['duration'] as String? ?? '',
      badge: j['badge'] as String? ?? 'HD',
      status: status,
      progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
      size: j['size'] as String? ?? 'Calculating…',
      sizeMb: (j['sizeMb'] as num?)?.toInt() ?? 0,
      season: (j['season'] as num?)?.toInt(),
      episode: (j['episode'] as num?)?.toInt(),
      seriesName: j['seriesName'] as String?,
      episodeTitle: j['episodeTitle'] as String?,
      quality: quality,
    );
  }
}

/// Why a download request was rejected before enqueueing.
enum DownloadRejectReason { duplicate, storageFull, wifiRequired, unknown }

class DownloadRequest {
  final DownloadItem? item;
  final DownloadRejectReason? reason;
  const DownloadRequest.queued(this.item) : reason = null;
  const DownloadRequest.rejected(this.reason) : item = null;
  bool get ok => item != null;
}

// ═══════════════════════════════════════════════════════════════════════════
// MediaDeliveryService
// ═══════════════════════════════════════════════════════════════════════════

/// Central delivery coordinator for streaming and background offline downloading.
class MediaDeliveryService extends ChangeNotifier {
  final SettingsService _settings;
  final StreamingService _streamingService;

  MediaDeliveryService(this._settings)
      : _streamingService = StreamingService(_settings);

  static const String _keyDownloads = 'media_delivery_queue_v1';

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool get initialized => _initialized;

  final List<DownloadItem> _downloads = [];
  List<DownloadItem> get downloads => List.unmodifiable(_downloads);

  int get activeCount => _downloads.where((d) => d.isActive).length;
  int get completedCount => _downloads.where((d) => d.isComplete).length;
  double get usedStorageGb =>
      _downloads
          .where((d) => d.status != DownloadStatus.failed)
          .fold<int>(0, (sum, d) => sum + d.sizeMb) /
      1024.0;

  void pauseAll() {
    for (final d in List.of(_downloads.where((d) => d.isActive))) {
      pause(d.id);
    }
  }

  void resumeAll() {
    for (final d in List.of(
        _downloads.where((d) => d.status == DownloadStatus.paused))) {
      resume(d.id);
    }
  }

  final List<String> _pendingIds = [];
  final Set<String> _activeIds = {};

  int maxConcurrentDownloads = 3;
  bool isOnWifi = true;

  final List<void Function(DownloadItem)> _onCompleteCallbacks = [];

  // ── Init & Settings ────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _load();
    _initialized = true;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pump());
  }

  void applySettings() {
    _pump();
    notifyListeners();
  }

  bool get _sequential => _settings.sequentialDownloads;
  int get _concurrency => _sequential ? 1 : maxConcurrentDownloads;
  bool get useExternalPlayer => _settings.useExternalPlayer;

  // ── 1. Streaming ───────────────────────────────────────────────────────────

  /// Resolves a playable source (prioritizing offline download, falling back to remote stream).
  Future<PlayableSource> resolveStream(
    Movie movie, {
    int? season,
    int? episode,
    List<String> excludeUrls = const [],
    int startProviderIndex = 0,
  }) async {
    final title = _titleFor(movie, season, episode);
    final quality = _settings.streamQuality;
    _dlog(
        'resolveStream "$title" tmdbId=${movie.tmdbId} startIdx=$startProviderIndex exclude=${excludeUrls.length}');

    // 1. Offline download takes priority (unless switching streams)
    if (excludeUrls.isEmpty) {
      final offline = _findCompletedDownload(movie.id, season, episode);
      if (offline != null) {
        final path = offlineLocalPath(offline);
        if (path != null && path.isNotEmpty) {
          _dlog('✅ Using offline download: $path');
          return PlayableSource(
            url: path.startsWith('http') ? path : null,
            assetPath: path.startsWith('http') ? null : path,
            title: title,
            quality: quality,
            isOffline: true,
            cdn: 'Local Storage',
          );
        }
      }
    }

    // 2. Resolve remote stream via StreamingService
    _dlog('Resolving remote stream for tmdbId=${movie.tmdbId}');
    final licensed = await resolveLicensedStream(
      movie,
      quality: quality,
      season: season,
      episode: episode,
      excludeUrls: excludeUrls,
      startProviderIndex: startProviderIndex,
    );

    if (licensed != null && licensed.url.isNotEmpty) {
      _dlog('✅ Remote stream resolved: ${licensed.url}');
      final uri = Uri.tryParse(licensed.url);
      final cdnHost = (uri != null && uri.host.isNotEmpty) ? uri.host : null;
      return PlayableSource(
        url: licensed.url,
        title: title,
        quality: quality,
        headers: licensed.headers,
        cdn: cdnHost,
        subtitles: licensed.subtitles,
        audioTracks: licensed.audioTracks,
        masterPlaylist: licensed.masterPlaylist,
      );
    }

    throw Exception(
      'No stream source found for "${movie.title}".\n'
      'tmdbId=${movie.tmdbId} isTV=${movie.isTV}',
    );
  }

  /// Delegates to StreamingService to resolve the stream URL and headers.
  Future<ResolvedStream?> resolveLicensedStream(
    Movie movie, {
    required VideoQuality quality,
    int? season,
    int? episode,
    List<String> excludeUrls = const [],
    int startProviderIndex = 0,
  }) {
    return _streamingService.resolveLicensedStream(
      movie,
      quality: quality,
      season: season,
      episode: episode,
      excludeUrls: excludeUrls,
      startProviderIndex: startProviderIndex,
    );
  }

  String _titleFor(Movie movie, int? season, int? episode) {
    if (season != null && episode != null) {
      return '${movie.title} • S$season E$episode';
    }
    return movie.title;
  }

  // ── 2. Downloads (Queue & Controls) ─────────────────────────────────────────

  static String episodeDownloadId(String movieId, int season, int episode) =>
      '${movieId}_s${season}_e$episode';

  static String seasonPrefix(String movieId, int season) =>
      '${movieId}_s${season}_e';

  DownloadItem? _byId(String id) {
    for (final d in _downloads) {
      if (d.id == id) return d;
    }
    return null;
  }

  DownloadItem? _findCompletedDownload(String movieId, int? season, int? ep) {
    final id = (season != null && ep != null)
        ? episodeDownloadId(movieId, season, ep)
        : movieId;
    final d = _byId(id);
    return (d != null && d.isComplete) ? d : null;
  }

  String? offlineLocalPath(DownloadItem item) {
    if (!item.isComplete) return null;
    return _prefs?.getString('dl_path_${item.id}');
  }

  bool isEpisodeDownloaded(String movieId, int season, int episode) =>
      _byId(episodeDownloadId(movieId, season, episode))?.isComplete ?? false;

  bool isEpisodeDownloading(String movieId, int season, int episode) =>
      _byId(episodeDownloadId(movieId, season, episode))?.isActive ?? false;

  DownloadItem? getEpisodeDownload(String movieId, int season, int episode) =>
      _byId(episodeDownloadId(movieId, season, episode));

  DownloadItem? getMovieDownload(String movieId) => _byId(movieId);
  bool isMovieDownloaded(String movieId) => _byId(movieId)?.isComplete ?? false;
  bool isMovieDownloading(String movieId) => _byId(movieId)?.isActive ?? false;

  int getDownloadedEpisodesCount(String movieId, int season) {
    final prefix = seasonPrefix(movieId, season);
    return _downloads
        .where((d) => d.id.startsWith(prefix) && d.isComplete)
        .length;
  }

  int getDownloadingEpisodesCount(String movieId, int season) {
    final prefix = seasonPrefix(movieId, season);
    return _downloads
        .where((d) => d.id.startsWith(prefix) && d.isActive)
        .length;
  }

  Future<DownloadRequest> downloadMovie(Movie movie,
      {VideoQuality? quality}) async {
    return _enqueue(
      id: movie.id,
      movieId: movie.tmdbId.toString(),
      title: movie.title,
      imageUrl: movie.imageUrl,
      genre: movie.genreString,
      duration: movie.duration,
      badge: movie.badges.isNotEmpty ? movie.badges.first : 'HD',
      quality: quality,
    );
  }

  Future<DownloadRequest> downloadEpisode({
    required Movie movie,
    required int season,
    required int episode,
    required String episodeTitle,
    String? stillUrl,
    String? duration,
    VideoQuality? quality,
  }) {
    final id = episodeDownloadId(movie.id, season, episode);
    return _enqueue(
      id: id,
      movieId: movie.tmdbId.toString(),
      title: '${movie.title} • S$season E$episode: $episodeTitle',
      imageUrl:
          (stillUrl != null && stillUrl.isNotEmpty) ? stillUrl : movie.imageUrl,
      genre: movie.genreString,
      duration: (duration != null && duration.isNotEmpty) ? duration : '45m',
      badge: 'S$season:E$episode',
      season: season,
      episode: episode,
      seriesName: movie.title,
      episodeTitle: episodeTitle,
      quality: quality,
    );
  }

  Future<int> downloadSeason({
    required Movie movie,
    required int seasonNumber,
    required List<EpisodeItem> episodes,
    VideoQuality? quality,
  }) async {
    _rememberSeasonEpisodeMax(
      movie.tmdbId.toString(),
      seasonNumber,
      episodes,
    );
    int queued = 0;
    for (final ep in episodes) {
      final id = episodeDownloadId(movie.id, seasonNumber, ep.episodeNumber);
      if (_byId(id) != null) continue;
      final res = await downloadEpisode(
        movie: movie,
        season: seasonNumber,
        episode: ep.episodeNumber,
        episodeTitle: ep.name,
        stillUrl: ep.stillUrl,
        duration: ep.duration,
        quality: quality,
      );
      if (res.ok) queued++;
    }
    return queued;
  }

  Future<int> downloadSeries({
    required Movie movie,
    required List<SeasonItem> seasons,
    Map<int, List<EpisodeItem>>? seasonEpisodes,
    VideoQuality? quality,
  }) async {
    int queued = 0;
    for (final s in seasons) {
      final eps = seasonEpisodes?[s.seasonNumber] ?? s.episodes;
      if (eps.isEmpty) continue;
      queued += await downloadSeason(
        movie: movie,
        seasonNumber: s.seasonNumber,
        episodes: eps,
        quality: quality,
      );
    }
    return queued;
  }

  Future<DownloadRequest> _enqueue({
    required String id,
    required String movieId,
    required String title,
    required String imageUrl,
    required String genre,
    required String duration,
    required String badge,
    int? season,
    int? episode,
    String? seriesName,
    String? episodeTitle,
    VideoQuality? quality,
  }) async {
    if (_byId(id) != null) {
      return const DownloadRequest.rejected(DownloadRejectReason.duplicate);
    }
    if (_settings.downloadOnWifiOnly && !isOnWifi) {
      return const DownloadRequest.rejected(DownloadRejectReason.wifiRequired);
    }
    final effectiveQuality = quality ?? _settings.downloadQuality.videoQuality;
    final isTv = season != null || episode != null;
    final sizeMb = _estimatedSizeMb(effectiveQuality, isTv: isTv);
    if (_storageFull(sizeMb)) {
      return const DownloadRequest.rejected(DownloadRejectReason.storageFull);
    }

    final item = DownloadItem(
      id: id,
      movieId: movieId,
      title: title,
      imageUrl: imageUrl,
      genre: genre,
      duration: duration,
      badge: badge,
      status: DownloadStatus.pending,
      progress: 0.0,
      size: _formatMb(sizeMb),
      sizeMb: sizeMb,
      season: season,
      episode: episode,
      seriesName: seriesName,
      episodeTitle: episodeTitle,
      quality: effectiveQuality,
    );

    _downloads.add(item);
    _pendingIds.add(id);
    await _save();
    _pump();
    notifyListeners();
    return DownloadRequest.queued(item);
  }

  bool _storageFull(int incomingMb) {
    final capMb = _settings.maxStorageGB * 1024;
    if (capMb <= 0) return false;
    final usedMb = _downloads
        .where((d) => d.status != DownloadStatus.failed)
        .fold<int>(0, (sum, d) => sum + d.sizeMb);
    return usedMb + incomingMb > capMb;
  }

  void _pump() {
    while (_activeIds.length < _concurrency && _pendingIds.isNotEmpty) {
      final id = _pendingIds.removeAt(0);
      final item = _byId(id);
      if (item == null || item.status == DownloadStatus.paused) continue;
      _setStatus(id, DownloadStatus.downloading);
      _activeIds.add(id);
      _run(id);
    }
    _syncBackgroundService();
    _save();
  }

  int _backgroundActive = 0;

  /// Android suspends background network work unless a foreground service is
  /// running, so the first active item starts one and the last one stops it.
  void _syncBackgroundService() {
    final active = _activeIds.length;
    if (active == _backgroundActive) return;
    _backgroundActive = active;
    if (active == 0) {
      unawaited(BackgroundDownloads.stop());
      return;
    }
    unawaited(BackgroundDownloads.start(
      label: active == 1 ? 'Downloading 1 item…' : 'Downloading $active items…',
    ));
  }

  Future<void> _run(String id) async {
    try {
      await transferDownload(
        id,
        onProgress: (update) {
          final item = _byId(id);
          if (item == null || item.status == DownloadStatus.paused) return;
          _updateItem(
            id,
            item.copyWith(
              progress: update.progress.clamp(0.0, 1.0),
              speed: update.speedFormatted,
              size: update.sizeFormatted.isNotEmpty
                  ? update.sizeFormatted
                  : item.size,
              downloadedBytes: update.receivedBytes,
              totalBytes: update.totalBytes,
            ),
          );
        },
      );
      final item = _byId(id);
      if (item == null || item.status == DownloadStatus.paused) return;
      _updateItem(
        id,
        item.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          speed: null,
        ),
      );
      _fireComplete(item);
    } catch (e) {
      final item = _byId(id);
      if (item != null && item.status != DownloadStatus.paused) {
        _dlog('❌ Download "${item.title}" failed: $e', level: LogLevel.error);
        _updateItem(
            id, item.copyWith(status: DownloadStatus.failed, speed: null));
      }
    } finally {
      _activeIds.remove(id);
      _pump();
      notifyListeners();
    }
  }

  /// Resolves the stream and delegates byte downloading to DownloadEngine.
  Future<void> transferDownload(
    String id, {
    required void Function(DownloadProgressUpdate update) onProgress,
  }) async {
    final item = _byId(id);
    if (item == null) return;

    if (kIsWeb) {
      throw Exception('Downloads are not supported on web.');
    }

    final tmdbId = int.tryParse(item.movieId) ?? 0;
    if (tmdbId <= 0) {
      throw Exception('Cannot resolve stream: no TMDB id for "${item.title}"');
    }

    final isTv = item.season != null && item.episode != null;
    final movie = Movie(
      id: item.movieId,
      tmdbId: tmdbId,
      title: item.seriesName ?? item.title,
      description: '',
      imageUrl: item.imageUrl,
      backdropUrl: item.imageUrl,
      rating: 0,
      duration: item.duration,
      genres: const [],
      badges: const [],
      year: 0,
      ageRating: '',
      isTV: isTv,
    );

    // Resolve through the same pipeline playback uses (VixSrc → WebView → JS
    // scraper) so a download works wherever streaming does.
    ResolvedStream? stream = await _streamingService.resolveLicensedStream(
      movie,
      quality: item.quality,
      season: item.season ?? 1,
      episode: item.episode ?? 1,
    );

    // Legacy fallback: JS scraper if the shared path came back empty.
    if (stream == null || stream.url.isEmpty) {
      try {
        final scraperStreams = await JsScraperBridge.getStreams(
          tmdbId,
          title: item.title,
          isTV: isTv,
          season: item.season ?? 1,
          episode: item.episode ?? 1,
        );
        if (scraperStreams.isNotEmpty && scraperStreams.first.url.isNotEmpty) {
          stream = scraperStreams.first;
        }
      } catch (_) {}
    }

    if (stream == null || stream.url.isEmpty) {
      throw Exception('Stream resolution failed for "${item.title}"');
    }

    final streamUrl = stream.url;

    // The engine sniffs the response: HLS is staged, then folded into one
    // file so the download is a single playable video; everything else is
    // saved directly as a single file.
    final savedPath = await DownloadEngine.downloadStreamWithProgress(
      id: id,
      title: item.title,
      seriesName: item.seriesName,
      season: item.season,
      episode: item.episode,
      episodeTitle: item.episodeTitle,
      streamUrl: streamUrl,
      quality: item.quality,
      headers: stream.headers,
      onProgress: onProgress,
      isCancelledOrPaused: () {
        final check = _byId(id);
        return check == null || check.status == DownloadStatus.paused;
      },
      showNotification: _settings.notifyDownloads,
    );
    if (savedPath.isNotEmpty) {
      await _persistDownloadPath(id, savedPath);
    }
  }

  void pause(String id) {
    final item = _byId(id);
    if (item == null) return;
    if (item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.pending) {
      _pendingIds.remove(id);
      _activeIds.remove(id);
      _setStatus(id, DownloadStatus.paused);
      OsNotifications.cancelDownload(id);
      _pump();
      notifyListeners();
    }
  }

  void resume(String id) {
    final item = _byId(id);
    if (item == null || item.status != DownloadStatus.paused) return;
    _setStatus(id, DownloadStatus.pending);
    if (!_pendingIds.contains(id)) _pendingIds.add(id);
    _pump();
    notifyListeners();
  }

  void retry(String id) {
    final item = _byId(id);
    if (item == null || item.status != DownloadStatus.failed) return;
    _updateItem(
        id, item.copyWith(status: DownloadStatus.pending, progress: 0.0));
    if (!_pendingIds.contains(id)) _pendingIds.add(id);
    _pump();
    notifyListeners();
  }

  void cancel(String id) {
    _pendingIds.remove(id);
    _activeIds.remove(id);
    _downloads.removeWhere((d) => d.id == id);
    OsNotifications.cancelDownload(id);
    _save();
    _pump();
    notifyListeners();
  }

  void delete(String id) {
    cancel(id);
    _deleteFromDisk(id);
  }

  Future<void> _deleteFromDisk(String id) async {
    try {
      final savedPath = _prefs?.getString('dl_path_$id');
      await _prefs?.remove('dl_path_$id');
      if (savedPath != null && savedPath.isNotEmpty && !kIsWeb) {
        final f = io.File(savedPath);
        if (f.existsSync()) {
          f.deleteSync();
        }
        final d = io.Directory(savedPath);
        if (d.existsSync()) {
          d.deleteSync(recursive: true);
        }
        // If it was an index.m3u8, delete parent dir
        if (savedPath.endsWith('index.m3u8')) {
          final parent = f.parent;
          if (parent.existsSync()) {
            parent.deleteSync(recursive: true);
          }
        }
      }
    } catch (_) {}
  }

  void clearCompleted() {
    final cleared = _downloads.where((d) => d.isComplete).toList();
    _downloads.removeWhere((d) => d.status == DownloadStatus.completed);
    for (final item in cleared) {
      // The dialog promises freed storage; dropping only the list row would
      // leave every file behind.
      unawaited(_deleteFromDisk(item.id));
    }
    _save();
    notifyListeners();
  }

  void addOnCompleteCallback(void Function(DownloadItem) cb) =>
      _onCompleteCallbacks.add(cb);

  void removeOnCompleteCallback(void Function(DownloadItem) cb) =>
      _onCompleteCallbacks.remove(cb);

  void _fireComplete(DownloadItem item) {
    for (final cb in List.of(_onCompleteCallbacks)) {
      try {
        cb(item);
      } catch (_) {}
    }

    if (_settings.autoDownloadNextEpisode &&
        item.season != null &&
        item.episode != null) {
      unawaited(_autoQueueNextEpisode(item));
    }
  }

  /// Highest episode number known per `"<tmdbId>|<season>"`, filled from the
  /// episode lists the detail screen hands us and from TMDB lookups.
  final Map<String, int> _seasonEpisodeMax = {};

  void _rememberSeasonEpisodeMax(
    String movieId,
    int season,
    List<EpisodeItem> episodes,
  ) {
    var max = 0;
    for (final ep in episodes) {
      if (ep.episodeNumber > max) max = ep.episodeNumber;
    }
    if (max > 0) _seasonEpisodeMax['$movieId|$season'] = max;
  }

  Future<int?> _seasonEpisodeMaxFor(String movieId, int season) async {
    final key = '$movieId|$season';
    final known = _seasonEpisodeMax[key];
    if (known != null) return known;

    final tmdbId = int.tryParse(movieId);
    if (tmdbId == null || tmdbId <= 0) return null;
    final data = await TmdbService.getTVSeason(tmdbId, season);
    final episodes = (data?['episodes'] as List?) ?? const [];
    var max = 0;
    for (final raw in episodes) {
      if (raw is! Map) continue;
      final number = raw['episode_number'];
      if (number is int && number > max) max = number;
    }
    if (max == 0) return null;
    _seasonEpisodeMax[key] = max;
    return max;
  }

  /// Queues the next episode after [item] finishes, but only when the season
  /// is known to have one. Guessing used to invent episodes past the finale.
  Future<void> _autoQueueNextEpisode(DownloadItem item) async {
    final season = item.season!;
    final episode = item.episode!;
    final next = episode + 1;

    final maxEpisode = await _seasonEpisodeMaxFor(item.movieId, season);
    if (maxEpisode == null) {
      _dlog('Auto-next skipped: S$season episode list unavailable');
      return;
    }
    if (next > maxEpisode) {
      _dlog('Auto-next finished at S$season E$episode (season ends there)');
      return;
    }

    final nextEpId = episodeDownloadId(item.movieId, season, next);
    // Only queue if not already in the list (any status).
    if (_byId(nextEpId) != null) return;

    final nextItem = DownloadItem(
      id: nextEpId,
      movieId: item.movieId,
      title: _incrementEpisodeTitle(item.title, episode),
      imageUrl: item.imageUrl,
      genre: item.genre,
      duration: item.duration,
      badge: 'S$season:E$next',
      status: DownloadStatus.pending,
      progress: 0.0,
      size: item.size,
      sizeMb: item.sizeMb,
      season: season,
      episode: next,
    );
    _downloads.add(nextItem);
    _pendingIds.add(nextEpId);
    _save();
    _pump();
    notifyListeners();
    _dlog('Auto-queued next episode: $nextEpId');
  }

  /// Increments the episode number in a title string like "Show • S1 E3: Name"
  static String _incrementEpisodeTitle(String title, int currentEp) {
    final next = currentEp + 1;
    // Try to replace "E<n>" with "E<n+1>"
    final replaced = title.replaceFirst(RegExp('E$currentEp'), 'E$next');
    if (replaced != title) return replaced;
    // Fallback: just append the next episode number
    return title.replaceFirst(RegExp(r':\s*.+$'), ': Episode $next');
  }

  void _setStatus(String id, DownloadStatus status) {
    final item = _byId(id);
    if (item != null) _updateItem(id, item.copyWith(status: status));
  }

  void _updateItem(String id, DownloadItem updated) {
    final idx = _downloads.indexWhere((d) => d.id == id);
    if (idx != -1) {
      _downloads[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> _persistDownloadPath(String id, String pathOrUrl) async {
    await _prefs?.setString('dl_path_$id', pathOrUrl);
  }

  Future<void> _load() async {
    final raw = _prefs?.getString(_keyDownloads);
    _downloads.clear();
    _pendingIds.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final e in list) {
        var item = DownloadItem.fromJson(e as Map<String, dynamic>);
        // A transfer that was mid-flight when the process died comes back as
        // pending so the queue picks it up again on this launch. Without this
        // it would sit in `downloading` forever, with nothing driving it.
        if (item.status == DownloadStatus.downloading) {
          item = item.copyWith(status: DownloadStatus.pending);
        }
        _downloads.add(item);
        if (!kIsWeb && item.status == DownloadStatus.pending) {
          _pendingIds.add(item.id);
        }
      }
      _dlog('Restored ${_downloads.length} download(s), '
          '${_pendingIds.length} queued to resume');
    } catch (e) {
      _downloads.clear();
      _pendingIds.clear();
    }
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    final raw = jsonEncode(_downloads.map((d) => d.toJson()).toList());
    await p.setString(_keyDownloads, raw);
  }

  static int estimateSizeMb(VideoQuality quality, {bool isTv = false}) {
    final factor = isTv ? 0.42 : 1.0;
    switch (quality) {
      case VideoQuality.uhd4k:
        return (4200 * factor).round();
      case VideoQuality.fullHd1080:
      case VideoQuality.highest:
        return (1800 * factor).round();
      case VideoQuality.hd720:
        return (920 * factor).round();
      case VideoQuality.sd480:
        return (460 * factor).round();
      case VideoQuality.auto:
        return (1400 * factor).round();
    }
  }

  int _estimatedSizeMb(VideoQuality quality, {bool isTv = false}) {
    return estimateSizeMb(quality, isTv: isTv);
  }

  String _formatMb(int mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '$mb MB';
  }

  static void _dlog(String msg, {LogLevel level = LogLevel.info}) {
    DiagnosticService.instance.log('MediaDelivery', msg, level: level);
  }

  // ── 3. Platform Capabilities (Delegated to PlatformMediaChannel) ───────────

  Future<Uint8List?> getVideoThumbnail({
    required String videoPath,
    required int timeMs,
    int width = 180,
    int height = 100,
    Map<String, String>? headers,
  }) =>
      PlatformMediaChannel.getVideoThumbnail(
        videoPath: videoPath,
        timeMs: timeMs,
        width: width,
        height: height,
        headers: headers,
      );

  Future<int> getNetworkSpeed() => PlatformMediaChannel.getNetworkSpeed();

  Future<bool> enterPip({bool isPlaying = true}) =>
      PlatformMediaChannel.enterPip(
        isPlaying: isPlaying,
        enablePip: _settings.enablePip,
      );

  Future<bool> isPipSupported() => PlatformMediaChannel.isPipSupported();

  Future<void> updatePipPlayState({required bool isPlaying}) =>
      PlatformMediaChannel.updatePipPlayState(isPlaying: isPlaying);

  Future<void> setAutoPip({required bool enable}) =>
      PlatformMediaChannel.setAutoPip(
        enable: enable,
        enablePip: _settings.enablePip,
      );
}
