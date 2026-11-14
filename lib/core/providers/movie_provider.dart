import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie.dart';
import '../services/media_orchestrator_service.dart';

enum LoadState { idle, loading, loaded, error }

class MovieProvider extends ChangeNotifier {
  final MediaOrchestratorService _orchestrator;

  MovieProvider(this._orchestrator) {
    _watchConnection();
  }

  // ─── Home screen data ────────────────────────────────────────────────────────
  List<Movie> featured = []; // hero carousel  (trending)
  List<Movie> trending = []; // Trending Now row
  List<Movie> topRated = []; // Top Rated row
  List<Movie> nowPlaying = []; // Now Playing / New Releases row
  List<Movie> popular = []; // Popular row
  List<TVShow> continueWatching = []; // Continue Watching (trending TV)
  List<Movie> popularTV = []; // Popular TV shows
  List<Movie> trendingTV = []; // Trending TV shows

  // ─── Offline state ───────────────────────────────────────────────────────────

  /// True when the app cannot reach the network. The rows above then hold the
  /// [_cacheKey] snapshot from [cachedAt] instead of fresh titles, so the UI
  /// must say so rather than present stale art as current.
  bool isOffline = false;

  /// When the cached feed below was last fetched live.
  DateTime? cachedAt;

  static const _cacheKey = 'home_feed_v1';
  bool _hydrated = false;
  StreamSubscription<List<ConnectivityResult>>? _connection;

  /// Mirrors the platform radio into [isOffline] so a dropped connection shows
  /// the banner immediately, and a restored one re-syncs without a restart.
  void _watchConnection() {
    unawaited(_applyConnection());
    try {
      _connection = Connectivity().onConnectivityChanged.listen((results) {
        _setOffline(results.isEmpty ||
            results.every((r) => r == ConnectivityResult.none));
      });
    } catch (_) {
      // No connectivity channel on this platform — a failed fetch below still
      // reports offline, so the banner and cache behave the same.
    }
  }

  Future<void> _applyConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _setOffline(
          results.isEmpty || results.every((r) => r == ConnectivityResult.none));
    } catch (_) {
      // Unknown; loadHome's own failure path takes over.
    }
  }

  void _setOffline(bool value) {
    if (isOffline == value) return;
    isOffline = value;
    notifyListeners();
    if (!value && homeState != LoadState.loading) unawaited(loadHome());
  }

  // ─── Explore / search ────────────────────────────────────────────────────────
  List<Movie> searchResults = [];
  bool isSearching = false;
  String _lastQuery = '';
  Timer? _debounce;

  // ─── Genre browse ────────────────────────────────────────────────────────────
  List<Movie> genreResults = [];
  bool isLoadingGenre = false;

  // ─── Global load state ───────────────────────────────────────────────────────
  LoadState homeState = LoadState.idle;
  String? homeError;

  /// True when the rows on screen are the last synced snapshot rather than
  /// what the catalogue offers right now.
  bool get showingCachedFeed =>
      cachedAt != null && (isOffline || homeState == LoadState.error);

  // ─── Initial home load ───────────────────────────────────────────────────────

  Future<void> loadHome() async {
    if (homeState == LoadState.loading) return;
    homeState = LoadState.loading;
    homeError = null;
    await _hydrateFromCache();
    notifyListeners();

    try {
      // Fire ALL requests (TMDB + Trakt) in one parallel batch.
      // Each feed fails independently so a Trakt outage (or no login)
      // never wipes out the TMDB-sourced rows.
      final List<dynamic> results = await Future.wait([
        _orchestrator
            .fetchFeatured(limit: 10)
            .catchError((_) => <Movie>[]), // 0
        _orchestrator
            .fetchTrending(limit: 20, skipFeatured: true)
            .catchError((_) => <Movie>[]), // 1
        _orchestrator
            .fetchTopRated(limit: 20)
            .catchError((_) => <Movie>[]), // 2
        _orchestrator
            .fetchNowPlaying(limit: 20)
            .catchError((_) => <Movie>[]), // 3
        _orchestrator.fetchPopular(limit: 20).catchError((_) => <Movie>[]), // 4
        _orchestrator
            .fetchContinueWatching(limit: 8)
            .catchError((_) => <TVShow>[]), // 5
        _orchestrator
            .fetchPopularTV(limit: 20)
            .catchError((_) => <Movie>[]), // 6
        _orchestrator
            .fetchTrendingTV(limit: 20)
            .catchError((_) => <Movie>[]), // 7
        _orchestrator
            .fetchTraktTrendingAsMovies(limit: 20)
            .catchError((_) => <Movie>[]), // 8
        _orchestrator
            .fetchTraktPopularAsMovies(limit: 20)
            .catchError((_) => <Movie>[]), // 9
        _orchestrator
            .fetchTraktRecommendedAsMovies(limit: 20)
            .catchError((_) => <Movie>[]), // 10
        _orchestrator
            .fetchTraktTrendingShowsAsMovies(limit: 20)
            .catchError((_) => <Movie>[]), // 11
        _orchestrator
            .fetchTraktPopularShowsAsMovies(limit: 20)
            .catchError((_) => <Movie>[]), // 12
      ]);

      // Merge + deduplicate: primary list wins on duplicate TMDB id.
      List<Movie> merge(List<Movie> primary, List<Movie> secondary) {
        final seen = <String>{};
        final out = <Movie>[];
        for (final m in [...primary, ...secondary]) {
          if (seen.add(m.id)) out.add(m);
        }
        return out;
      }

      List<Movie> listAt(int i) => (results[i] as List).cast<Movie>();

      final traktTrending = listAt(8);
      final traktPopular = listAt(9);
      final traktRecommended = listAt(10);
      final traktTrendingShows = listAt(11);
      final traktPopularShows = listAt(12);

      final nextFeatured =
          merge((results[0] as List).cast<Movie>(), traktTrending);
      final nextTrending = merge(listAt(1), traktTrending);
      final nextTopRated = merge(listAt(2), traktRecommended);
      final nextNowPlaying = listAt(3);
      final nextPopular = merge(listAt(4), traktPopular);
      final nextPopularTV = merge(listAt(6), traktPopularShows);
      final nextTrendingTV = merge(listAt(7), traktTrendingShows);

      // Every feed answering with nothing is not an empty catalogue, it is no
      // connection. Keep the cached rows rather than replacing them with void.
      final live = nextFeatured.isNotEmpty ||
          nextTrending.isNotEmpty ||
          nextTopRated.isNotEmpty ||
          nextNowPlaying.isNotEmpty ||
          nextPopularTV.isNotEmpty ||
          nextTrendingTV.isNotEmpty;
      if (!live) {
        isOffline = true;
        homeState =
            cachedAt != null ? LoadState.loaded : LoadState.error;
        homeError = cachedAt != null ? null : 'No connection and nothing cached';
        notifyListeners();
        return;
      }

      featured = nextFeatured;
      trending = nextTrending;
      topRated = nextTopRated;
      nowPlaying = nextNowPlaying;
      popular = nextPopular;
      continueWatching = (results[5] as List).cast<TVShow>();
      popularTV = nextPopularTV;
      trendingTV = nextTrendingTV;

      isOffline = false;
      homeState = LoadState.loaded;
      unawaited(_persistCache());
    } catch (e) {
      isOffline = true;
      homeError = e.toString();
      homeState = cachedAt != null ? LoadState.loaded : LoadState.error;
    }
    notifyListeners();
  }

  // ─── Feed cache ──────────────────────────────────────────────────────────────

  /// Rows the home screen shows, keyed for the on-disk snapshot.
  Map<String, List<Movie>> get _feed => {
        'featured': featured,
        'trending': trending,
        'topRated': topRated,
        'nowPlaying': nowPlaying,
        'popular': popular,
        'popularTV': popularTV,
        'trendingTV': trendingTV,
      };

  /// Loads the last synced feed so a cold start — offline or not — paints real
  /// posters immediately instead of an empty grid.
  Future<void> _hydrateFromCache() async {
    if (_hydrated) return;
    _hydrated = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      List<Movie> read(String key) =>
          ((map[key] as List?) ?? []).whereType<Map<String, dynamic>>().map(
                (e) => Movie.fromJson(e),
              ).toList();
      if (featured.isEmpty) featured = read('featured');
      if (trending.isEmpty) trending = read('trending');
      if (topRated.isEmpty) topRated = read('topRated');
      if (nowPlaying.isEmpty) nowPlaying = read('nowPlaying');
      if (popular.isEmpty) popular = read('popular');
      if (popularTV.isEmpty) popularTV = read('popularTV');
      if (trendingTV.isEmpty) trendingTV = read('trendingTV');
      cachedAt = DateTime.tryParse('${map['at']}');
    } catch (_) {
      // Written by an older build — the next live load overwrites it.
    }
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'at': DateTime.now().toIso8601String(),
        for (final e in _feed.entries)
          e.key: e.value.map((m) => m.toJson()).toList(),
      };
      await prefs.setString(_cacheKey, jsonEncode(payload));
      cachedAt = DateTime.tryParse(payload['at'] as String);
    } catch (_) {
      // Caching is a convenience; a full or unavailable store just means the
      // next launch needs a connection.
    }
  }

  // ─── Search ──────────────────────────────────────────────────────────────────

  void search(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      searchResults = [];
      isSearching = false;
      _lastQuery = '';
      notifyListeners();
      return;
    }
    isSearching = true;
    notifyListeners();

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (query == _lastQuery) return;
      _lastQuery = query;
      try {
        searchResults = await _orchestrator.search(query, limit: 20);
      } catch (_) {
        searchResults = [];
      }
      isSearching = false;
      notifyListeners();
    });
  }

  void clearSearch() {
    _debounce?.cancel();
    searchResults = [];
    isSearching = false;
    _lastQuery = '';
    notifyListeners();
  }

  // ─── Genre browse ────────────────────────────────────────────────────────────

  Future<void> loadGenre(String genreName) async {
    isLoadingGenre = true;
    notifyListeners();

    try {
      genreResults = await _orchestrator.fetchByGenre(genreName, limit: 40);
    } catch (_) {
      genreResults = [];
    }

    isLoadingGenre = false;
    notifyListeners();
  }

  void clearGenre() {
    genreResults = [];
    notifyListeners();
  }

  // ─── Refresh ─────────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    homeState = LoadState.idle;
    return loadHome();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _connection?.cancel();
    super.dispose();
  }
}
