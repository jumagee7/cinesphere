import 'dart:async';

import '../models/movie.dart';
import 'settings_service.dart';
import 'stream_resolver_service.dart';
import 'vixsrc_resolver_service.dart';
import 'js_scraper_bridge.dart';
import 'diagnostic_service.dart';
import 'tmdb_service.dart';

/// Service responsible for resolving remote streaming sources for movies & TV series.
class StreamingService {
  final SettingsService _settings;

  /// Recent resolutions, so reopening the same title (or resuming after a
  /// hiccup) skips the resolver round trips. Signed URLs stay valid well past
  /// this window, and switching servers bypasses the cache entirely.
  static final Map<String, _CachedResolution> _cache = {};
  static const Duration _cacheTtl = Duration(minutes: 10);

  StreamingService(this._settings) {
    // Ensure the JS scraper plugin is linked and ready (fetching omitted)
    JsScraperBridge.loadPlugin();
  }

  static String _cacheKey(Movie movie, int? season, int? episode) =>
      '${movie.tmdbId}|${movie.isTV ? 'tv' : 'movie'}|${season ?? 0}|${episode ?? 0}';

  static ResolvedStream _remember(
    bool useCache,
    String key,
    ResolvedStream stream,
  ) {
    if (useCache) {
      _cache[key] = _CachedResolution(
        stream,
        DateTime.now().add(_cacheTtl),
      );
    }
    return stream;
  }

  /// Resolves a playable stream for [movie], optionally scoped to [season] and [episode].
  Future<ResolvedStream?> resolveLicensedStream(
    Movie movie, {
    required VideoQuality quality,
    int? season,
    int? episode,
    List<String> excludeUrls = const [],
    int startProviderIndex = 0,
  }) async {
    if (movie.tmdbId <= 0) {
      _dlog('⚠️ tmdbId is 0 for "${movie.title}"');
      return null;
    }

    final useCache = excludeUrls.isEmpty && startProviderIndex == 0;
    final cacheKey = _cacheKey(movie, season, episode);
    if (useCache) {
      final hit = _cache[cacheKey];
      if (hit != null && DateTime.now().isBefore(hit.expiresAt)) {
        _dlog('♻️ Reusing cached stream resolution: ${hit.stream.url}',
            level: LogLevel.success);
        return hit.stream;
      }
      _cache.remove(cacheKey);
    }

    // 1. Direct high-speed HTTP resolver (VixSrc) — resolves instantly in ~500ms
    // without WebView overhead, without ad popups, across all platforms (Android/TV/Web/Desktop).
    try {
      final directStream = await VixsrcResolverService.resolve(
        tmdbId: movie.tmdbId,
        isTV: movie.isTV,
        season: season ?? 1,
        episode: episode ?? 1,
      );
      if (directStream != null &&
          directStream.url.isNotEmpty &&
          !excludeUrls.contains(directStream.url)) {
        _dlog('⚡ Stream resolved via VixSrc direct resolver: ${directStream.url}',
            level: LogLevel.success);
        return _remember(useCache, cacheKey, directStream);
      }
    } catch (e) {
      _dlog('VixSrc direct resolver failed, trying fallback: $e',
          level: LogLevel.warning);
    }

    // Resolve the IMDb id only for the WebView fallback — VixSrc keys off the
    // TMDB id, so the extra details round trip is skipped on the fast path.
    String? imdbId = movie.imdbId;
    if (imdbId == null || imdbId.isEmpty) {
      try {
        final details = movie.isTV
            ? await TmdbService.getTVDetails(movie.tmdbId)
            : await TmdbService.getMovieDetails(movie.tmdbId);
        imdbId = (details?['imdb_id'] ?? details?['external_ids']?['imdb_id']) as String?;
      } catch (_) {}
    }

    // 2. WebView interceptor — fallback for titles not in VixSrc catalog.
    _dlog('Calling StreamResolverService for tmdbId=${movie.tmdbId} imdbId=$imdbId startIdx=$startProviderIndex');
    final stream = await StreamResolverService.resolve(
      tmdbId: movie.tmdbId,
      imdbId: imdbId,
      isTV: movie.isTV,
      season: season ?? 1,
      episode: episode ?? 1,
      quickPlay: _settings.quickPlay,
      parallelCount: _settings.parallelSourceCount,
      excludeUrls: excludeUrls,
      startProviderIndex: startProviderIndex,
    );
    if (stream != null && stream.url.isNotEmpty) {
      _dlog('⚡ Stream resolved via WebView interceptor: ${stream.url}', level: LogLevel.success);
      return _remember(useCache, cacheKey, stream);
    }

    // 3. JS Scraper fallback — used when WebView finds nothing (web platform,
    //    region-blocked providers, or all providers timed out).
    try {
      final scraperStreams = await JsScraperBridge.getStreams(
        movie.tmdbId,
        title: movie.title,
        isTV: movie.isTV,
        season: season ?? 1,
        episode: episode ?? 1,
      );
      for (final s in scraperStreams) {
        if (s.url.isNotEmpty && !excludeUrls.contains(s.url)) {
          _dlog('⚡ Stream resolved via JS Scraper fallback: ${s.url}', level: LogLevel.success);
          return _remember(useCache, cacheKey, s);
        }
      }
    } catch (e) {
      _dlog('JS Scraper fallback skipped: $e');
    }

    return null;
  }

  static void _dlog(String msg, {LogLevel level = LogLevel.info}) {
    DiagnosticService.instance.log('StreamingService', msg, level: level);
  }
}

class _CachedResolution {
  final ResolvedStream stream;
  final DateTime expiresAt;

  const _CachedResolution(this.stream, this.expiresAt);
}
