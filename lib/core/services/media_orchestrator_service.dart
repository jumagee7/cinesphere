import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/trakt_service.dart';
import '../services/video_service.dart';
import '../services/settings_service.dart';
import '../services/media_delivery_service.dart';

enum MediaCategory {
  featured,
  trending,
  topRated,
  popular,
  nowPlaying,
  upcoming,
  continueWatching,
  search,
  genre,
  similar,
  recommendations,
  details,
  trailer,
  cast,
}

class CategoryMeta {
  final MediaCategory id;
  final String label;
  final IconData icon;
  final int defaultLimit;
  final String sortKey;
  const CategoryMeta({
    required this.id,
    required this.label,
    required this.icon,
    required this.defaultLimit,
    required this.sortKey,
  });
}

/// Unified orchestrator — sits between UI and the service layer.
/// All streaming goes through [MediaDeliveryService.resolveStream] which
/// uses [StreamResolverService] to intercept a real URL from VidSrc and
/// hand it to the custom [VideoPlayerScreen].
class MediaOrchestratorService {
  final SettingsService _settings;
  final MediaDeliveryService _delivery;

  MediaOrchestratorService(this._settings, this._delivery);

  // ────────────────────────────────────────────────────────────────────────
  // 1. Category metadata
  // ────────────────────────────────────────────────────────────────────────
  static const List<CategoryMeta> categories = [
    CategoryMeta(
        id: MediaCategory.featured,
        label: 'Featured',
        icon: IconData(0xe313, fontFamily: 'MaterialIcons'),
        defaultLimit: 5,
        sortKey: 'trending_desc'),
    CategoryMeta(
        id: MediaCategory.trending,
        label: 'Trending Now',
        icon: IconData(0xe2f5, fontFamily: 'MaterialIcons'),
        defaultLimit: 10,
        sortKey: 'trending_desc'),
    CategoryMeta(
        id: MediaCategory.topRated,
        label: 'Top Rated',
        icon: IconData(0xe5c8, fontFamily: 'MaterialIcons'),
        defaultLimit: 10,
        sortKey: 'rating_desc'),
    CategoryMeta(
        id: MediaCategory.popular,
        label: 'Popular',
        icon: IconData(0xe57f, fontFamily: 'MaterialIcons'),
        defaultLimit: 10,
        sortKey: 'popularity_desc'),
    CategoryMeta(
        id: MediaCategory.nowPlaying,
        label: 'New Releases',
        icon: IconData(0xe06a, fontFamily: 'MaterialIcons'),
        defaultLimit: 10,
        sortKey: 'release_desc'),
    CategoryMeta(
        id: MediaCategory.upcoming,
        label: 'Upcoming',
        icon: IconData(0xe0c8, fontFamily: 'MaterialIcons'),
        defaultLimit: 10,
        sortKey: 'release_asc'),
    CategoryMeta(
        id: MediaCategory.continueWatching,
        label: 'Continue Watching',
        icon: IconData(0xe037, fontFamily: 'MaterialIcons'),
        defaultLimit: 5,
        sortKey: 'progress_desc'),
    CategoryMeta(
        id: MediaCategory.search,
        label: 'Search Results',
        icon: IconData(0xe0d4, fontFamily: 'MaterialIcons'),
        defaultLimit: 20,
        sortKey: 'relevance'),
    CategoryMeta(
        id: MediaCategory.genre,
        label: 'Browse by Genre',
        icon: IconData(0xe37a, fontFamily: 'MaterialIcons'),
        defaultLimit: 20,
        sortKey: 'popularity_desc'),
    CategoryMeta(
        id: MediaCategory.similar,
        label: 'More Like This',
        icon: IconData(0xe7ef, fontFamily: 'MaterialIcons'),
        defaultLimit: 10,
        sortKey: 'similarity_desc'),
    CategoryMeta(
        id: MediaCategory.recommendations,
        label: 'Recommended',
        icon: IconData(0xe0e4, fontFamily: 'MaterialIcons'),
        defaultLimit: 10,
        sortKey: 'relevance'),
    CategoryMeta(
        id: MediaCategory.cast,
        label: 'Cast',
        icon: IconData(0xe491, fontFamily: 'MaterialIcons'),
        defaultLimit: 8,
        sortKey: 'billing'),
  ];

  // ────────────────────────────────────────────────────────────────────────
  // 2. TMDB fetch helpers
  // ────────────────────────────────────────────────────────────────────────
  Future<List<Movie>> fetchFeatured({int limit = 5}) async =>
      transformTmdbList(await TmdbService.getTrending(),
          trending: true, take: limit);

  Future<List<Movie>> fetchTrending(
      {int limit = 10, bool skipFeatured = true}) async {
    final raw = await TmdbService.getTrending();
    return transformTmdbList(raw.skip(skipFeatured ? 5 : 0).toList(),
        trending: true, take: limit);
  }

  Future<List<Movie>> fetchTopRated({int limit = 10}) async =>
      transformTmdbList(await TmdbService.getTopRated(), take: limit);

  Future<List<Movie>> fetchPopular({int limit = 10}) async =>
      transformTmdbList(await TmdbService.getPopular(), take: limit);

  Future<List<Movie>> fetchNowPlaying({int limit = 10}) async =>
      transformTmdbList(await TmdbService.getNowPlaying(), take: limit);

  Future<List<Movie>> fetchNewReleases({int limit = 10}) =>
      fetchNowPlaying(limit: limit);

  Future<List<Movie>> fetchUpcoming({int limit = 10}) async =>
      transformTmdbList(await TmdbService.getUpcoming(), take: limit);

  Future<List<TVShow>> fetchContinueWatching({int limit = 5}) async =>
      transformContinueWatching(
          (await TmdbService.getTrendingTV()).take(limit).toList());

  Future<List<Movie>> fetchPopularTV({int limit = 10}) async =>
      transformTmdbList(await TmdbService.getPopularTV(), take: limit);

  Future<List<Movie>> fetchTrendingTV({int limit = 10}) async =>
      transformTmdbList(await TmdbService.getTrendingTV(),
          trending: true, take: limit);

  Future<List<Movie>> fetchByGenre(String genreName, {int limit = 20}) async {
    final genreId = TmdbService.genreNameToId[genreName];
    if (genreId == null) return [];
    return transformTmdbList(await TmdbService.discoverByGenre(genreId),
        take: limit);
  }

  Future<List<Movie>> search(String query, {int limit = 20}) async =>
      transformTmdbList(await TmdbService.searchMulti(query), take: limit);

  Future<Movie?> fetchDetails(int tmdbId, {bool isTv = false}) async {
    final raw = isTv
        ? await TmdbService.getTVDetails(tmdbId)
        : await TmdbService.getMovieDetails(tmdbId);
    if (raw == null) return null;
    final movie = Movie.fromTmdb(raw);
    final imdbId =
        raw['imdb_id'] as String? ?? raw['external_ids']?['imdb_id'] as String?;
    return (imdbId != null && imdbId.isNotEmpty)
        ? movie.withImdbId(imdbId)
        : movie;
  }

  Future<List<Movie>> fetchSimilar(int tmdbId,
          {int limit = 10, bool isTv = false}) async =>
      transformTmdbList(
          await (isTv
              ? TmdbService.getSimilarTV(tmdbId)
              : TmdbService.getSimilarMovies(tmdbId)),
          take: limit);

  Future<List<Movie>> fetchRecommendations(int tmdbId,
          {int limit = 10, bool isTv = false}) async =>
      transformTmdbList(
          await (isTv
              ? TmdbService.getTVRecommendations(tmdbId)
              : TmdbService.getMovieRecommendations(tmdbId)),
          take: limit);

  Future<String?> fetchTrailer(int tmdbId, {bool isTv = false}) async {
    final raw = isTv
        ? await TmdbService.getTVVideos(tmdbId)
        : await TmdbService.getMovieVideos(tmdbId);
    final candidates = raw
        .whereType<Map<String, dynamic>>()
        .where((v) =>
            v['site'] == 'YouTube' && (v['key'] as String? ?? '').isNotEmpty)
        .where((v) => v['type'] == 'Trailer' || v['type'] == 'Teaser')
        .toList();
    if (candidates.isEmpty) return null;
    // TMDB returns videos newest-first, and studios now flood that front of the
    // list with vertical Shorts teasers, so "first Trailer/Teaser match" used to
    // hand back a 15s 9:16 clip. Rank instead: real trailers before teasers,
    // then studio-official, then the highest native resolution.
    candidates.sort(_trailerRank);
    return candidates.first['key'] as String;
  }

  static int _trailerRank(Map<String, dynamic> a, Map<String, dynamic> b) {
    int typeRank(Map<String, dynamic> v) => v['type'] == 'Trailer' ? 0 : 1;
    int officialRank(Map<String, dynamic> v) => v['official'] == true ? 0 : 1;

    // max_resolution: a Shorts-style upload caps at 1080, a theatrical trailer
    // is usually 2160, so this pushes the landscape one up.
    int resolution(Map<String, dynamic> v) => (v['size'] as num? ?? 0).toInt();
    String published(Map<String, dynamic> v) =>
        v['published_at'] as String? ?? '';

    final byType = typeRank(a).compareTo(typeRank(b));
    if (byType != 0) return byType;
    final byOfficial = officialRank(a).compareTo(officialRank(b));
    if (byOfficial != 0) return byOfficial;
    final byResolution = resolution(b).compareTo(resolution(a));
    if (byResolution != 0) return byResolution;
    return published(b).compareTo(published(a));
  }

  Future<List<CastMember>> fetchCast(int tmdbId, {int limit = 8}) async {
    final details = await TmdbService.getMovieDetails(tmdbId);
    return ((details?['credits']?['cast'] as List?) ?? [])
        .take(limit)
        .map((c) => CastMember.fromTmdb(c as Map<String, dynamic>))
        .where((cm) => cm.name.isNotEmpty)
        .toList();
  }

  Future<List<SeasonItem>> fetchSeasons(Movie movie) async {
    if (movie.tmdbId > 0) {
      try {
        final details = await TmdbService.getTVDetails(movie.tmdbId);
        if (details != null && details['seasons'] is List) {
          final list = (details['seasons'] as List)
              .map((s) => SeasonItem.fromTmdb(s as Map<String, dynamic>))
              .where((s) => s.seasonNumber > 0 && s.episodeCount > 0)
              .toList();
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }
    return [
      SeasonItem(
          id: 101,
          seasonNumber: 1,
          name: 'Season 1',
          overview: '',
          posterUrl: movie.imageUrl,
          episodeCount: 8),
      SeasonItem(
          id: 102,
          seasonNumber: 2,
          name: 'Season 2',
          overview: '',
          posterUrl: movie.imageUrl,
          episodeCount: 10),
    ];
  }

  Future<List<EpisodeItem>> fetchSeasonEpisodes(
      Movie movie, int seasonNumber) async {
    if (movie.tmdbId > 0) {
      try {
        final data = await TmdbService.getTVSeason(movie.tmdbId, seasonNumber);
        if (data != null && data['episodes'] is List) {
          final list = (data['episodes'] as List)
              .map((e) => EpisodeItem.fromTmdb(e as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }
    return List.generate(
        8,
        (i) => EpisodeItem(
              id: seasonNumber * 100 + i + 1,
              episodeNumber: i + 1,
              seasonNumber: seasonNumber,
              name: 'Episode ${i + 1}',
              overview: '',
              stillUrl: movie.backdropUrl.isNotEmpty
                  ? movie.backdropUrl
                  : movie.imageUrl,
              duration: '45m',
              rating: 8.0,
              airDate: '',
            ));
  }

  // ─── Trakt public wrappers ────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchTraktTrendingMovies(
          {int limit = 20}) async =>
      (await TraktService.getTrendingMovies(limit: limit))
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> fetchTraktPopularMovies(
          {int limit = 20}) async =>
      (await TraktService.getPopularMovies(limit: limit))
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> fetchTraktSearchMovies(String query,
          {int limit = 20}) async =>
      (await TraktService.searchMovies(query, limit: limit))
          .cast<Map<String, dynamic>>();

  // ─── Trakt → Movie conversion ─────────────────────────────────────────────
  // Trakt extended=full feeds embed images (poster/fanart), genres, rating,
  // runtime and ids — rows render with zero TMDB calls, so they keep working
  // even when the TMDB key is dead or absent.
  // Trending returns [{watchers, movie|show:{...}}]; popular/recommended
  // return the objects directly.

  List<Movie> _traktToList(List<dynamic> raw,
      {required bool isWrapped, required bool isTv, bool trending = false}) {
    final seen = <String>{};
    final out = <Movie>[];
    for (final item in raw) {
      final map = item as Map<String, dynamic>;
      final entity = isWrapped
          ? ((isTv ? map['show'] : map['movie']) as Map<String, dynamic>?)
          : map;
      if (entity == null) continue;
      final movie = Movie.fromTrakt(entity, isTv: isTv, trending: trending);
      if (movie.imageUrl.isEmpty) continue;
      if (seen.add(movie.id)) out.add(movie);
    }
    return out;
  }

  /// media.trakt.tv sends no Access-Control-Allow-Origin header, so its image
  /// URLs can never load in the web build (native platforms are unaffected).
  /// Re-point artwork at image.tmdb.org for items that carry a TMDB id, and
  /// strip any Trakt URL that survives (no TMDB id, or lookup failed) so the
  /// card shows the placeholder instead of firing requests that always fail.
  ///
  /// Kept deliberately light: results are cached across feeds (Trakt rows
  /// overlap heavily — cached items cost no network) and lookups run in small
  /// batches so we don't saturate image.tmdb.org / api.themoviedb.org and
  /// trigger HTTP/2 resets.
  static final Map<String, _Artwork> _artworkCache = {};

  Future<List<Movie>> _webArtworkFix(List<Movie> movies) async {
    if (!kIsWeb) return movies;
    final targets = <int>[];
    for (var i = 0; i < movies.length; i++) {
      if (movies[i].tmdbId > 0 && movies[i].imageUrl.contains('trakt.tv')) {
        targets.add(i);
      }
    }

    Future<void> resolve(int idx) async {
      final m = movies[idx];
      final key = '${m.isTV ? 't' : 'm'}${m.tmdbId}';
      var art = _artworkCache[key];
      if (art == null) {
        try {
          final details = m.isTV
              ? await TmdbService.getTVDetails(m.tmdbId)
              : await TmdbService.getMovieDetails(m.tmdbId);
          if (details == null) return;
          final poster = TmdbService.poster(details['poster_path'] as String?);
          if (poster.isEmpty) return;
          art = _Artwork(
            poster,
            TmdbService.backdrop(details['backdrop_path'] as String?),
          );
          _artworkCache[key] = art;
        } catch (_) {
          return;
        }
      }
      movies[idx] = m.withArtwork(
        imageUrl: art.poster,
        backdropUrl: art.backdrop.isNotEmpty ? art.backdrop : m.backdropUrl,
      );
    }

    const batchSize = 3;
    for (var i = 0; i < targets.length; i += batchSize) {
      final batch = targets.sublist(
          i, i + batchSize > targets.length ? targets.length : i + batchSize);
      await Future.wait(batch.map(resolve));
    }
    for (var i = 0; i < movies.length; i++) {
      final m = movies[i];
      if (m.imageUrl.contains('trakt.tv') ||
          m.backdropUrl.contains('trakt.tv')) {
        movies[i] = m.withArtwork(
          imageUrl: m.imageUrl.contains('trakt.tv') ? '' : m.imageUrl,
          backdropUrl: m.backdropUrl.contains('trakt.tv') ? '' : m.backdropUrl,
        );
      }
    }
    return movies;
  }

  Future<List<Movie>> fetchTraktTrendingAsMovies({int limit = 20}) async {
    try {
      final raw = await TraktService.getTrendingMovies(limit: limit);
      return await _webArtworkFix(
          _traktToList(raw, isWrapped: true, isTv: false, trending: true));
    } catch (_) {
      return [];
    }
  }

  Future<List<Movie>> fetchTraktPopularAsMovies({int limit = 20}) async {
    try {
      final raw = await TraktService.getPopularMovies(limit: limit);
      return await _webArtworkFix(
          _traktToList(raw, isWrapped: false, isTv: false));
    } catch (_) {
      return [];
    }
  }

  Future<List<Movie>> fetchTraktRecommendedAsMovies({int limit = 20}) async {
    try {
      final raw = await TraktService.getRecommendedMovies(limit: limit);
      return await _webArtworkFix(
          _traktToList(raw, isWrapped: false, isTv: false));
    } catch (_) {
      return [];
    }
  }

  Future<List<Movie>> fetchTraktTrendingShowsAsMovies({int limit = 20}) async {
    try {
      final raw = await TraktService.getTrendingShows(limit: limit);
      return await _webArtworkFix(
          _traktToList(raw, isWrapped: true, isTv: true, trending: true));
    } catch (_) {
      return [];
    }
  }

  Future<List<Movie>> fetchTraktPopularShowsAsMovies({int limit = 20}) async {
    try {
      final raw = await TraktService.getPopularShows(limit: limit);
      return await _webArtworkFix(
          _traktToList(raw, isWrapped: false, isTv: true));
    } catch (_) {
      return [];
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // 3. Display helpers
  // ────────────────────────────────────────────────────────────────────────
  List<Movie> transformTmdbList(List<dynamic> raw,
      {bool trending = false, int? take}) {
    Iterable<dynamic> src = raw;
    if (take != null) src = src.take(take);
    return src
        .map((j) =>
            Movie.fromTmdb(j as Map<String, dynamic>, trending: trending))
        .where((m) => m.imageUrl.isNotEmpty)
        .toList();
  }

  List<TVShow> transformContinueWatching(List<dynamic> rawTv) {
    const prog = <double>[0.38, 0.65, 0.22, 0.55, 0.80];
    return rawTv
        .asMap()
        .entries
        .map((e) {
          final base = TVShow.fromTmdb(e.value as Map<String, dynamic>,
              season: 1,
              episode: e.key + 1,
              episodeTitle: 'Episode ${e.key + 1}');
          return TVShow(
            id: base.id,
            tmdbId: base.tmdbId,
            imdbId: base.imdbId,
            title: base.title,
            description: base.description,
            imageUrl: base.imageUrl,
            backdropUrl: base.backdropUrl,
            rating: base.rating,
            duration: base.duration,
            genres: base.genres,
            badges: base.badges,
            year: base.year,
            ageRating: base.ageRating,
            isTrending: true,
            watchProgress: prog[e.key % prog.length],
            season: base.season,
            episode: base.episode,
            episodeTitle: base.episodeTitle,
          );
        })
        .where((s) => s.imageUrl.isNotEmpty)
        .toList();
  }

  String buildMetadataLine(Movie m,
      {required bool showRuntime, required String contentLanguage}) {
    final parts = <String>[m.genreString];
    if (showRuntime && m.duration.isNotEmpty) parts.add(m.duration);
    return parts.join(' • ');
  }

  // ────────────────────────────────────────────────────────────────────────
  // 4. Streaming — goes through MediaDeliveryService → StreamResolverService
  // ────────────────────────────────────────────────────────────────────────

  /// Resolves a direct playable URL for [m] via VidSrc interception.
  /// Returns a [PlayableSource] whose [url] or [assetPath] can be passed
  /// directly to [VideoPlayerScreen].
  Future<PlayableSource> resolveStream(Movie m, {int? season, int? episode}) =>
      _delivery.resolveStream(m, season: season, episode: episode);

  bool isYouTube(String url) => VideoService.isYouTube(url);
  String? extractYouTubeId(String url) => VideoService.extractYouTubeId(url);
  Future<bool> openExternal(String url) =>
      VideoService.openInExternalPlayer(url);
  Future<String?> resolveTrailerKey(Movie m) =>
      fetchTrailer(m.tmdbId, isTv: m.isTV);

  // ────────────────────────────────────────────────────────────────────────
  // 5. Settings read-through
  // ────────────────────────────────────────────────────────────────────────
  VideoQuality get streamQuality => _settings.streamQuality;
  DownloadQuality get downloadQuality => _settings.downloadQuality;
  bool get autoPlay => _settings.autoPlay;
  bool get skipIntro => _settings.skipIntro;
  bool get autoNextEpisode => _settings.autoNextEpisode;
  bool get useExternalPlayer => _settings.useExternalPlayer;
  double get playbackSpeed => _settings.playbackSpeed;
  bool get subtitlesEnabled => _settings.subtitlesEnabled;
  String get subtitleLanguage => _settings.subtitleLanguage;
  SubtitleSize get subtitleSize => _settings.subtitleSize;
  bool get downloadOnWifiOnly => _settings.downloadOnWifiOnly;
  bool get autoDownloadNextEpisode => _settings.autoDownloadNextEpisode;
  bool get sequentialDownloads => _settings.sequentialDownloads;
  int get maxStorageGB => _settings.maxStorageGB;
  bool get notifyNewEpisodes => _settings.notifyNewEpisodes;
  bool get notifyNewMovies => _settings.notifyNewMovies;
  bool get notifyPremiere => _settings.notifyPremiere;
  bool get notifyDownloads => _settings.notifyDownloads;
  bool get syncWatchHistory => _settings.syncWatchHistory;
  bool get syncWatchlist => _settings.syncWatchlist;
  bool get scrobbleAutomatically => _settings.scrobbleAutomatically;
  bool get useOledBlack => _settings.useOledBlack;
  bool get showBadges => _settings.showBadges;
  bool get showRatings => _settings.showRatings;
  bool get showRuntime => _settings.showRuntime;
  String get contentLanguage => _settings.contentLanguage;
  double get densityLevel => _settings.densityLevel;
  double get posterRadius => _settings.posterRadius;
  bool get crashReportingEnabled => _settings.crashReportingEnabled;
  bool get personalizedRecommendations => _settings.personalizedRecommendations;
  String get traktClientId => _settings.traktClientId;
  String get traktClientSecret => _settings.traktClientSecret;
}

/// Cached TMDB artwork pair for re-pointing Trakt images on web.
class _Artwork {
  final String poster;
  final String backdrop;
  const _Artwork(this.poster, this.backdrop);
}
