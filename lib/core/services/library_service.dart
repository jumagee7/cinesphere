import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import '../models/profile.dart';
import 'trakt_service.dart';
import 'tmdb_service.dart';

/// Manages user's personal library: watchlist, favorites, and watch history.
/// Storage is scoped per local profile so each profile in the app has its
/// own independent lists.
class LibraryService extends ChangeNotifier {
  SharedPreferences? _prefs;
  String _profileId = 'default';

  // ── Watchlist ─────────────────────────────────────────────────────────────
  List<Movie> _watchlist = [];
  List<Movie> get watchlist => _watchlist;
  bool get hasWatchlist => _watchlist.isNotEmpty;

  // ── Favorites ─────────────────────────────────────────────────────────────
  List<Movie> _favorites = [];
  List<Movie> get favorites => _favorites;
  bool get hasFavorites => _favorites.isNotEmpty;

  // ── Watch History ─────────────────────────────────────────────────────────
  List<Movie> _history = [];
  List<Movie> get history => _history;
  bool get hasHistory => _history.isNotEmpty;

  // ── Continue Watching (with progress) ───────────────────────────────────────
  List<Movie> _continueWatching = [];
  List<Movie> get continueWatching => _continueWatching;
  bool get hasContinueWatching => _continueWatching.isNotEmpty;

  String _key(String suffix) => 'library_${_profileId}_$suffix';

  /// Mirrors local watchlist mutations to Trakt. Installed by `main` so this
  /// service stays free of auth/settings dependencies.
  Future<void> Function(Movie movie, {required bool added})? onWatchlistChanged;

  Future<void> _mirrorWatchlistChange(Movie movie, bool added) async {
    try {
      await onWatchlistChanged?.call(movie, added: added);
    } catch (_) {
      // Trakt mirroring is best-effort; the local list is the source of truth.
    }
  }

  Future<void> initialize({String profileId = 'default'}) async {
    _prefs = await SharedPreferences.getInstance();
    _profileId = profileId;
    await _loadAll();
  }

  /// Rebind the service to a different profile and reload its lists.
  /// Called when the user switches profiles.
  Future<void> bindToProfile(String profileId) async {
    if (_profileId == profileId) return;
    _profileId = profileId;
    _watchlist = [];
    _favorites = [];
    _history = [];
    _continueWatching = [];
    await _loadAll();
  }

  Future<void> _loadAll() async {
    final p = _prefs;
    if (p == null) return;

    _watchlist = _readList(p.getString(_key('watchlist')));
    _favorites = _readList(p.getString(_key('favorites')));
    _history = _readList(p.getString(_key('history')));
    _continueWatching = _readList(p.getString(_key('continue_watching')));

    notifyListeners();
  }

  List<Movie> _readList(String? raw) {
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((j) => Movie.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveWatchlist() async {
    await _prefs?.setString(
      _key('watchlist'),
      jsonEncode(_watchlist.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _saveFavorites() async {
    await _prefs?.setString(
      _key('favorites'),
      jsonEncode(_favorites.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _saveHistory() async {
    await _prefs?.setString(
      _key('history'),
      jsonEncode(_history.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _saveContinueWatching() async {
    await _prefs?.setString(
      _key('continue_watching'),
      jsonEncode(_continueWatching.map((m) => m.toJson()).toList()),
    );
  }

  // ── Watchlist methods ───────────────────────────────────────────────────────

  bool isInWatchlist(Movie movie) {
    return _watchlist.any((m) => m.id == movie.id);
  }

  Future<void> addToWatchlist(Movie movie) async {
    if (!isInWatchlist(movie)) {
      _watchlist.add(movie);
      await _saveWatchlist();
      notifyListeners();
      unawaited(_mirrorWatchlistChange(movie, true));
    }
  }

  Future<void> removeFromWatchlist(Movie movie) async {
    final wasListed = isInWatchlist(movie);
    _watchlist.removeWhere((m) => m.id == movie.id);
    await _saveWatchlist();
    notifyListeners();
    if (wasListed) unawaited(_mirrorWatchlistChange(movie, false));
  }

  Future<void> toggleWatchlist(Movie movie) async {
    if (isInWatchlist(movie)) {
      await removeFromWatchlist(movie);
    } else {
      await addToWatchlist(movie);
    }
  }

  // ── Favorites methods ───────────────────────────────────────────────────────

  bool isFavorite(Movie movie) {
    return _favorites.any((m) => m.id == movie.id);
  }

  Future<void> addToFavorites(Movie movie) async {
    if (!isFavorite(movie)) {
      _favorites.add(movie);
      await _saveFavorites();
      notifyListeners();
    }
  }

  Future<void> removeFromFavorites(Movie movie) async {
    _favorites.removeWhere((m) => m.id == movie.id);
    await _saveFavorites();
    notifyListeners();
  }

  Future<void> toggleFavorite(Movie movie) async {
    if (isFavorite(movie)) {
      await removeFromFavorites(movie);
    } else {
      await addToFavorites(movie);
    }
  }

  // ── History methods ──────────────────────────────────────────────────────────

  Future<void> addToHistory(Movie movie) async {
    _history.removeWhere((m) => m.id == movie.id);
    _history.insert(0, movie);
    if (_history.length > 50) {
      _history = _history.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  // ── Continue Watching methods ───────────────────────────────────────────────

  Future<void> updateWatchProgress(Movie movie, double progress) async {
    final existingIndex = _continueWatching.indexWhere((m) {
      if (m.id == movie.id) return true;
      if (movie.tmdbId > 0 && m.tmdbId == movie.tmdbId) {
        if (movie is TVShow && m is TVShow) {
          return m.season == movie.season && m.episode == movie.episode;
        }
        return true;
      }
      return false;
    });
    final updated = movie.withProgress(progress);
    if (existingIndex != -1) {
      _continueWatching[existingIndex] = updated;
      _continueWatching.removeAt(existingIndex);
      _continueWatching.insert(0, updated);
    } else {
      _continueWatching.insert(0, updated);
    }
    if (_continueWatching.length > 20) {
      _continueWatching = _continueWatching.sublist(0, 20);
    }
    await _saveContinueWatching();
    notifyListeners();
  }

  double? getWatchProgress(Movie movie, {int? season, int? episode}) {
    if (movie.watchProgress != null && movie.watchProgress! > 0) {
      return movie.watchProgress;
    }
    final match = _continueWatching.where((m) {
      final matchesId =
          m.id == movie.id || (movie.tmdbId > 0 && m.tmdbId == movie.tmdbId);
      if (!matchesId) return false;
      if (season != null && episode != null && m is TVShow) {
        return m.season == season && m.episode == episode;
      }
      return true;
    }).firstOrNull;
    return match?.watchProgress;
  }

  Future<void> removeFromContinueWatching(Movie movie) async {
    _continueWatching.removeWhere((m) => m.id == movie.id);
    await _saveContinueWatching();
    notifyListeners();
  }

  Future<void> clearContinueWatching() async {
    _continueWatching.clear();
    await _saveContinueWatching();
    notifyListeners();
  }

  // ── Sync from Trakt ─────────────────────────────────────────────────────────

  /// Fetches the user's paused / in-progress watches from Trakt and merges them
  /// into the local continueWatching list, enriched with TMDB posters/backdrops.
  /// Each half of the merge is opt-in so the Sync Watch History and Sync
  /// Watchlist switches control their own data.
  Future<void> syncFromTrakt(
    String token, {
    bool history = true,
    bool watchlist = false,
  }) async {
    try {
      if (history) {
        final playback = await TraktService.getPlaybackProgress(token);
        final traktActiveIds = <String>{};

        for (final item in playback) {
          final double prog =
              (((item['progress'] as num?)?.toDouble() ?? 0.0) / 100.0)
                  .clamp(0.0, 1.0);
          final type = item['type'] as String?;

          if (type == 'movie' && item['movie'] != null) {
            final m = item['movie'] as Map<String, dynamic>;
            final tmdbId = m['ids']?['tmdb'] as int? ?? 0;
            final imdb = m['ids']?['imdb'] as String?;
            final title = m['title'] as String? ?? 'Untitled';
            final year = m['year'] as int? ?? 0;
            final id = tmdbId > 0 ? '$tmdbId' : title;
            traktActiveIds.add(id);

            final existing =
                _continueWatching.where((x) => x.id == id).firstOrNull;
            if (existing != null) {
              await updateWatchProgress(existing, prog);
            } else {
              String posterUrl = '';
              String backdropUrl = '';
              if (tmdbId > 0) {
                try {
                  final details = await TmdbService.getMovieDetails(tmdbId);
                  if (details != null) {
                    posterUrl =
                        TmdbService.poster(details['poster_path'] as String?);
                    backdropUrl = TmdbService.backdrop(
                        details['backdrop_path'] as String?);
                  }
                } catch (_) {}
              }
              final movie = Movie(
                id: id,
                tmdbId: tmdbId,
                imdbId: imdb,
                title: title,
                description: m['overview'] as String? ?? '',
                imageUrl: posterUrl,
                backdropUrl: backdropUrl,
                rating: (m['rating'] as num?)?.toDouble() ?? 0.0,
                duration: '',
                genres:
                    (m['genres'] as List?)?.map((e) => e.toString()).toList() ??
                        [],
                badges: ['Trakt'],
                year: year,
                ageRating: '',
                watchProgress: prog,
              );
              await updateWatchProgress(movie, prog);
            }
          } else if (type == 'episode' && item['show'] != null) {
            final show = item['show'] as Map<String, dynamic>;
            final ep = item['episode'] as Map<String, dynamic>?;
            final int seasonNum = ep?['season'] as int? ?? 1;
            final int epNum = ep?['number'] as int? ?? 1;
            final String epTitle = ep?['title'] as String? ?? 'Episode $epNum';
            final tmdbId = show['ids']?['tmdb'] as int? ?? 0;
            final imdb = show['ids']?['imdb'] as String?;
            final title = show['title'] as String? ?? 'Untitled Show';
            final year = show['year'] as int? ?? 0;
            final id = tmdbId > 0 ? '$tmdbId' : title;
            traktActiveIds.add(id);

            final existing = _continueWatching.where((x) {
              if (x.id != id) return false;
              if (x is TVShow) {
                return x.season == seasonNum && x.episode == epNum;
              }
              return true;
            }).firstOrNull;

            if (existing != null) {
              await updateWatchProgress(existing, prog);
            } else {
              String posterUrl = '';
              String backdropUrl = '';
              if (tmdbId > 0) {
                try {
                  final details = await TmdbService.getTVDetails(tmdbId);
                  if (details != null) {
                    posterUrl =
                        TmdbService.poster(details['poster_path'] as String?);
                    backdropUrl = TmdbService.backdrop(
                        details['backdrop_path'] as String?);
                  }
                } catch (_) {}
              }
              final tvShow = TVShow(
                id: id,
                tmdbId: tmdbId,
                imdbId: imdb,
                title: title,
                description: show['overview'] as String? ?? '',
                imageUrl: posterUrl,
                backdropUrl: backdropUrl,
                rating: (show['rating'] as num?)?.toDouble() ?? 0.0,
                duration: '',
                genres: (show['genres'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [],
                badges: ['Trakt', 'TV', 'S$seasonNum:E$epNum'],
                year: year,
                ageRating: '',
                watchProgress: prog,
                season: seasonNum,
                episode: epNum,
                episodeTitle: epTitle,
              );
              await updateWatchProgress(tvShow, prog);
            }
          }
        }

        // If Trakt has 0 items or some items were finished/cleared on Trakt,
        // prune Trakt-synced continue-watching items that are no longer in active playback:
        _continueWatching.removeWhere((m) =>
            m.badges.contains('Trakt') && !traktActiveIds.contains(m.id));
        await _saveContinueWatching();
        notifyListeners();

        // Continue-watching only covers paused items, so a phone watch that
        // ran to the end exists only in Trakt's history. Pull that too, or the
        // History tab on a second device never sees it.
        await _pullTraktHistory(token);
      }
      if (watchlist) await _pullTraktWatchlist(token);
    } catch (e) {
      debugPrint('Error syncing Trakt playback: $e');
    }
  }

  /// Imports Trakt's watched history into the local History tab. Entries
  /// already on this device keep their place and their artwork; only new ones
  /// are enriched through TMDB, so repeat syncs cost nothing.
  Future<void> _pullTraktHistory(String token) async {
    final remote = <Movie>[];
    var enrichBudget = 20;

    Future<void> collect(Map<String, dynamic> item, bool isShow) async {
      final data =
          (isShow ? item['show'] : item['movie']) as Map<String, dynamic>?;
      if (data == null) return;
      final ids = (data['ids'] as Map?)?.cast<String, dynamic>() ?? const {};
      final tmdbId = (ids['tmdb'] as num?)?.toInt() ?? 0;
      final imdbId = ids['imdb'] as String?;
      final title = data['title'] as String? ?? 'Untitled';
      final id = tmdbId > 0 ? '$tmdbId' : title;
      if (remote.any((m) => m.id == id)) return;

      final local = _history.where((m) => m.id == id).firstOrNull;
      var posterUrl = local?.imageUrl ?? '';
      var backdropUrl = local?.backdropUrl ?? '';
      if (local == null && tmdbId > 0 && enrichBudget > 0) {
        enrichBudget--;
        try {
          final details = isShow
              ? await TmdbService.getTVDetails(tmdbId)
              : await TmdbService.getMovieDetails(tmdbId);
          if (details != null) {
            posterUrl = TmdbService.poster(details['poster_path'] as String?);
            backdropUrl =
                TmdbService.backdrop(details['backdrop_path'] as String?);
          }
        } catch (_) {}
      }

      final episode = (item['episode'] as Map<String, dynamic>?);
      final genres =
          (data['genres'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
      final year = (data['year'] as num?)?.toInt() ?? 0;
      final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
      if (isShow) {
        final seasonNum = (episode?['season'] as num?)?.toInt() ?? 1;
        final epNum = (episode?['number'] as num?)?.toInt() ?? 1;
        remote.add(TVShow(
          id: id,
          tmdbId: tmdbId,
          imdbId: imdbId,
          title: title,
          description: data['overview'] as String? ?? '',
          imageUrl: posterUrl,
          backdropUrl: backdropUrl,
          rating: rating,
          duration: '',
          genres: genres,
          badges: const ['Trakt'],
          year: year,
          ageRating: '',
          season: seasonNum,
          episode: epNum,
          episodeTitle: episode?['title'] as String? ?? '',
        ));
      } else {
        remote.add(Movie(
          id: id,
          tmdbId: tmdbId,
          imdbId: imdbId,
          title: title,
          description: data['overview'] as String? ?? '',
          imageUrl: posterUrl,
          backdropUrl: backdropUrl,
          rating: rating,
          duration: '',
          genres: genres,
          badges: const ['Trakt'],
          year: year,
          ageRating: '',
        ));
      }
    }

    for (final raw in await TraktService.getWatchHistory(token, limit: 20)) {
      if (raw is Map) await collect(raw.cast<String, dynamic>(), false);
    }
    for (final raw
        in await TraktService.getWatchHistoryShows(token, limit: 20)) {
      if (raw is Map) await collect(raw.cast<String, dynamic>(), true);
    }

    final known = _history.map((m) => m.id).toSet();
    final incoming = remote.where((m) => !known.contains(m.id)).toList();
    if (incoming.isEmpty) return;
    _history = [..._history, ...incoming];
    if (_history.length > 50) _history = _history.sublist(0, 50);
    await _saveHistory();
    notifyListeners();
  }

  /// Imports the user's Trakt watchlist, skipping anything already saved.
  /// Local entries that Trakt does not know about are left alone — removal is
  /// mirrored as it happens, so absence here is not proof of deletion.
  Future<void> _pullTraktWatchlist(String token) async {
    final remote = <Movie>[];
    for (final type in const ['movies', 'shows']) {
      final entries = await TraktService.getWatchlist(token, type: type);
      for (final raw in entries) {
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final data = (type == 'movies' ? item['movie'] : item['show'])
            as Map<String, dynamic>?;
        if (data == null) continue;

        final ids = (data['ids'] as Map?)?.cast<String, dynamic>() ?? const {};
        final tmdbId = (ids['tmdb'] as num?)?.toInt() ?? 0;
        final imdbId = ids['imdb'] as String?;
        final title = data['title'] as String? ?? 'Untitled';
        final year = (data['year'] as num?)?.toInt() ?? 0;
        final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final genres =
            (data['genres'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        final id = tmdbId > 0 ? '$tmdbId' : title;

        var posterUrl = '';
        var backdropUrl = '';
        var duration = '';
        if (tmdbId > 0) {
          try {
            final details = type == 'movies'
                ? await TmdbService.getMovieDetails(tmdbId)
                : await TmdbService.getTVDetails(tmdbId);
            if (details != null) {
              posterUrl = TmdbService.poster(details['poster_path'] as String?);
              backdropUrl =
                  TmdbService.backdrop(details['backdrop_path'] as String?);
              final runtime = details['runtime'];
              if (runtime is int && runtime > 0) duration = '${runtime}m';
            }
          } catch (_) {}
        }

        remote.add(type == 'movies'
            ? Movie(
                id: id,
                tmdbId: tmdbId,
                imdbId: imdbId,
                title: title,
                description: data['overview'] as String? ?? '',
                imageUrl: posterUrl,
                backdropUrl: backdropUrl,
                rating: rating,
                duration: duration,
                genres: genres,
                badges: const ['Trakt'],
                year: year,
                ageRating: '',
              )
            : TVShow(
                id: id,
                tmdbId: tmdbId,
                imdbId: imdbId,
                title: title,
                description: data['overview'] as String? ?? '',
                imageUrl: posterUrl,
                backdropUrl: backdropUrl,
                rating: rating,
                duration: duration,
                genres: genres,
                badges: const ['Trakt', 'TV'],
                year: year,
                ageRating: '',
                season: 1,
                episode: 1,
                episodeTitle: '',
              ));
      }
    }

    var changed = false;
    for (final movie in remote) {
      if (!isInWatchlist(movie)) {
        _watchlist.add(movie);
        changed = true;
      }
    }
    if (changed) {
      await _saveWatchlist();
      notifyListeners();
    }
  }

  // ── Clear all (scoped to the active profile) ─────────────────────────────

  Future<void> clearAll() async {
    _watchlist.clear();
    _favorites.clear();
    _history.clear();
    _continueWatching.clear();

    final p = _prefs;
    if (p != null) {
      await p.remove(_key('watchlist'));
      await p.remove(_key('favorites'));
      await p.remove(_key('history'));
      await p.remove(_key('continue_watching'));
    }

    notifyListeners();
  }

  // ── Personalization helpers ─────────────────────────────────────────────

  /// Genre frequency for the active profile, most-watched first. Used to
  /// reorder the personalized feed.
  List<String> get topGenres {
    final counts = <String, int>{};
    void bump(Movie m, int weight) {
      for (final g in m.genres) {
        counts[g] = (counts[g] ?? 0) + weight;
      }
    }

    for (final m in _history) {
      bump(m, 1);
    }
    for (final m in _favorites) {
      bump(m, 3);
    }
    for (final m in _watchlist) {
      bump(m, 2);
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  /// Reorders [movies] so titles whose genres overlap this profile's top
  /// genres come first. Ties preserve the input order.
  ///
  /// When [profile] is supplied, the list is first filtered through the
  /// profile's blocked genres / maturity cap, and any explicitly preferred
  /// genres are boosted ahead of the organic top-genre signal.
  List<Movie> personalize(List<Movie> movies, {Profile? profile}) {
    var pool = movies;
    if (profile != null) {
      pool = profile.filter(pool);
      if (pool.isEmpty) return const [];
    }

    // Explicit preferences outrank organic history.
    final preferred = profile?.preferredGenres ?? const <String>[];
    final organic = topGenres;
    final ranked = <String>[
      ...preferred,
      ...organic.where((g) => !preferred.contains(g)),
    ];

    if (ranked.isEmpty) return pool;

    int score(Movie m) {
      var s = 0;
      for (var i = 0; i < m.genres.length; i++) {
        final rank = ranked.indexOf(m.genres[i]);
        if (rank >= 0) s += (ranked.length - rank) * (m.genres.length - i);
      }
      return s;
    }

    final scored = pool.map((m) => MapEntry(m, score(m))).toList();
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }
}
