import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/tmdb_key.local.dart';

/// TMDB API v3 service — free read-only access.
/// Get your own free key at: https://www.themoviedb.org/settings/api
class TmdbService {
  static String _apiKey = tmdbApiKey;
  static void setApiKey(String key) => _apiKey = key;

  static const String _base = 'https://api.themoviedb.org/3';
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  // ─── Image helpers ────────────────────────────────────────────────────────
  static String poster(String? path, {String size = 'w500'}) =>
      (path != null && path.isNotEmpty) ? '$_imgBase/$size$path' : '';

  static String backdrop(String? path, {String size = 'w1280'}) =>
      (path != null && path.isNotEmpty) ? '$_imgBase/$size$path' : '';

  static String profile(String? path, {String size = 'w185'}) =>
      (path != null && path.isNotEmpty) ? '$_imgBase/$size$path' : '';

  // ─── HTTP helpers ─────────────────────────────────────────────────────────
  static Uri _uri(String path, [Map<String, String>? extra]) {
    return Uri.parse('$_base$path').replace(
      queryParameters: {'api_key': _apiKey, 'language': 'en-US', ...?extra},
    );
  }

  static Future<Map<String, dynamic>?> _get(String path,
      [Map<String, String>? extra]) async {
    try {
      final res = await http
          .get(_uri(path, extra))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static Future<List<dynamic>> _getList(String path,
      [Map<String, String>? extra]) async {
    final data = await _get(path, extra);
    return (data?['results'] as List?) ?? [];
  }

  // ─── Movies: lists ────────────────────────────────────────────────────────
  static Future<List<dynamic>> getTrending({int page = 1}) =>
      _getList('/trending/movie/week', {'page': '$page'});

  static Future<List<dynamic>> getNowPlaying({int page = 1}) =>
      _getList('/movie/now_playing', {'page': '$page'});

  static Future<List<dynamic>> getPopular({int page = 1}) =>
      _getList('/movie/popular', {'page': '$page'});

  static Future<List<dynamic>> getTopRated({int page = 1}) =>
      _getList('/movie/top_rated', {'page': '$page'});

  static Future<List<dynamic>> getUpcoming({int page = 1}) =>
      _getList('/movie/upcoming', {'page': '$page'});

  // ─── Movie: detail ────────────────────────────────────────────────────────

  /// Resolves the IMDb id (e.g. "tt38672588") for a movie or TV show.
  static Future<String?> getImdbId(int id, {bool isTV = false}) async {
    final path = isTV ? '/tv/$id/external_ids' : '/movie/$id/external_ids';
    final data = await _get(path);
    final imdb = data?['imdb_id'] as String?;
    return (imdb != null && imdb.isNotEmpty) ? imdb : null;
  }

  /// Full detail with credits, recommendations, external_ids, videos, and
  /// release_dates (for certification/age-rating) appended in one request.
  static Future<Map<String, dynamic>?> getMovieDetails(int id) => _get(
        '/movie/$id',
        {
          'append_to_response':
              'credits,recommendations,external_ids,videos,release_dates,similar',
        },
      );

  // ─── Movie: videos ────────────────────────────────────────────────────────
  static Future<List<dynamic>> getMovieVideos(int id) async {
    final data = await _get('/movie/$id/videos');
    return (data?['results'] as List?) ?? [];
  }

  // ─── Movie: similar + recommendations ────────────────────────────────────
  static Future<List<dynamic>> getSimilarMovies(int id, {int page = 1}) =>
      _getList('/movie/$id/similar', {'page': '$page'});

  static Future<List<dynamic>> getMovieRecommendations(int id,
          {int page = 1}) =>
      _getList('/movie/$id/recommendations', {'page': '$page'});

  // ─── TV: similar + recommendations ───────────────────────────────────────
  static Future<List<dynamic>> getSimilarTV(int id, {int page = 1}) =>
      _getList('/tv/$id/similar', {'page': '$page'});

  static Future<List<dynamic>> getTVRecommendations(int id, {int page = 1}) =>
      _getList('/tv/$id/recommendations', {'page': '$page'});

  // ─── TV: lists ────────────────────────────────────────────────────────────
  static Future<List<dynamic>> getTrendingTV({int page = 1}) =>
      _getList('/trending/tv/week', {'page': '$page'});

  static Future<List<dynamic>> getPopularTV({int page = 1}) =>
      _getList('/tv/popular', {'page': '$page'});

  static Future<List<dynamic>> getTopRatedTV({int page = 1}) =>
      _getList('/tv/top_rated', {'page': '$page'});

  // ─── TV: detail ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getTVDetails(int id) => _get(
        '/tv/$id',
        {
          'append_to_response':
              'credits,recommendations,external_ids,videos,similar',
        },
      );

  // ─── TV: season + episodes ────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getTVSeason(
          int showId, int seasonNumber) =>
      _get('/tv/$showId/season/$seasonNumber');

  // ─── TV: videos ───────────────────────────────────────────────────────────
  static Future<List<dynamic>> getTVVideos(int id) async {
    final data = await _get('/tv/$id/videos');
    return (data?['results'] as List?) ?? [];
  }

  // ─── Search ───────────────────────────────────────────────────────────────
  static Future<List<dynamic>> searchMovies(String query,
      {int page = 1}) async {
    if (query.trim().isEmpty) return [];
    return _getList('/search/movie',
        {'query': query.trim(), 'page': '$page', 'include_adult': 'false'});
  }

  static Future<List<dynamic>> searchMulti(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];
    final data = await _get('/search/multi',
        {'query': query.trim(), 'page': '$page', 'include_adult': 'false'});
    final results = (data?['results'] as List?) ?? [];
    return results
        .where((r) => r['media_type'] == 'movie' || r['media_type'] == 'tv')
        .toList();
  }

  // ─── Genres / Discover ────────────────────────────────────────────────────
  static Future<List<dynamic>> discoverByGenre(int genreId, {int page = 1}) =>
      _getList('/discover/movie', {
        'with_genres': '$genreId',
        'sort_by': 'popularity.desc',
        'page': '$page',
        'include_adult': 'false',
      });

  // ─── Trakt-style: popular + trending (no auth) ───────────────────────────
  // These mirror TraktService endpoints but pull from TMDB directly.

  // ─── Genre name → TMDB genre id ──────────────────────────────────────────
  static const Map<String, int> genreNameToId = {
    'Action': 28,
    'Adventure': 12,
    'Animation': 16,
    'Comedy': 35,
    'Crime': 80,
    'Documentary': 99,
    'Drama': 18,
    'Family': 10751,
    'Fantasy': 14,
    'History': 36,
    'Horror': 27,
    'Music': 10402,
    'Mystery': 9648,
    'Romance': 10749,
    'Sci-Fi': 878,
    'Thriller': 53,
    'War': 10752,
    'Western': 37,
  };
}
