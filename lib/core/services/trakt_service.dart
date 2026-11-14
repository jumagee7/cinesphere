import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Vyro's Trakt API integration — PKCE-first.
///
/// All auth flows require **only** the Client ID — the client secret is never
/// transmitted or persisted. For browser-based sign-in we use the
/// Authorization Code + PKCE flow (RFC 7636, recommended), and fall back to
/// Device Code Flow (also secret-free for public/native clients) on devices
/// without a browser.
///
/// To use your own credentials, set your Trakt Client ID in
/// Settings → Trakt → API Credentials, or replace the default below with
/// your app's values from https://trakt.tv/oauth/applications
class TraktService {
  // ── Credentials ─────────────────────────────────────────────────────────
  static String customClientId = '';

  /// Legacy — kept for backward compat with SettingsService storage pipeline.
  /// PKCE and all auth flows never transmit a client secret.
  static String customClientSecret = '';

  static const String defaultClientId =
      'wRn8vwoOxNZ9T9dJ07--ZIu8BB4NQmL6D4JAprxDWS0';

  static String get clientId =>
      customClientId.isNotEmpty ? customClientId : defaultClientId;
  // ────────────────────────────────────────────────────────────────────────

  static const String _baseUrl = 'https://api.trakt.tv';
  static const String _authorizeUrl = 'https://trakt.tv/oauth/authorize';
  static const String _tokenUrl = '$_baseUrl/oauth/token';
  static const String _apiVersion = '2';

  /// Default redirect URI. Register this (or another URI) on your Trakt app
  /// settings. `urn:ietf:wg:oauth:2.0:oob` shows the code inline and lets
  /// the user copy-paste it, which works well with an InAppWebView flow.
  static const String defaultRedirectUri = 'https://trakt.tv/activate';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'trakt-api-version': _apiVersion,
        'trakt-api-key': clientId,
      };

  static Map<String, String> _authHeaders(String token) => {
        ..._headers,
        'Authorization': 'Bearer $token',
      };

  // ─── PKCE (Authorization Code + Proof Key) ─────────────────────────────
  // This is the RECOMMENDED flow — no client secret, proof against code
  // interception via the code_challenge/code_verifier pair.

  /// Holds the PKCE pair generated before each auth attempt.
  /// The verifier MUST be kept in memory (never persisted) until the code
  /// has been exchanged for a token.
  static String? _lastPkceVerifier;
  static String? get lastPkceVerifier => _lastPkceVerifier;

  /// Generates a cryptographically random code_verifier (43–128 chars of
  /// unreserved URI chars) and its matching code_challenge using S256.
  static Map<String, String> generatePkcePair() {
    final random = Random.secure();
    const unreserved =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final verifier =
        List.generate(64, (i) => unreserved[random.nextInt(unreserved.length)])
            .join();

    final challengeBytes = sha256.convert(ascii.encode(verifier)).bytes;
    final challenge = base64Url.encode(challengeBytes).replaceAll('=', '');

    _lastPkceVerifier = verifier;
    return {'code_verifier': verifier, 'code_challenge': challenge};
  }

  /// Builds the URL to open in a browser / WebView for the PKCE auth step.
  /// Pass the `code_challenge` value obtained from [generatePkcePair].
  static String buildPkceAuthorizeUrl({
    required String codeChallenge,
    String redirectUri = defaultRedirectUri,
    String? state,
  }) {
    final params = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': codeChallenge,
    };
    if (state != null && state.isNotEmpty) params['state'] = state;
    return Uri.parse(_authorizeUrl).replace(queryParameters: params).toString();
  }

  /// Step 3 of PKCE: exchange the authorization code for tokens using the
  /// original code_verifier. Requires NO client secret.
  static Future<Map<String, dynamic>> exchangePkceCode({
    required String code,
    required String codeVerifier,
    String redirectUri = defaultRedirectUri,
  }) async {
    final res = await http.post(
      Uri.parse(_tokenUrl),
      headers: _headers,
      body: jsonEncode({
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      }),
    );
    if (res.statusCode == 200) {
      _lastPkceVerifier = null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('PKCE code exchange failed: ${res.statusCode} ${res.body}');
  }

  // ─── Device Auth (fallback, still secret-free) ─────────────────────────

  /// Step 1: Request a device code. Returns map with device_code, user_code,
  /// verification_url, expires_in, interval.
  static Future<Map<String, dynamic>> requestDeviceCode() async {
    final res = await http.post(
      Uri.parse('$_baseUrl/oauth/device/code'),
      headers: _headers,
      body: jsonEncode({'client_id': clientId}),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to request device code: ${res.statusCode}');
  }

  /// Step 2: Poll for the access token. Returns token map if authorized,
  /// null if still pending (400), throws on denied/expired.
  /// NOTE: Native/public apps authenticate with Client ID only.
  static Future<Map<String, dynamic>?> pollDeviceToken(
      String deviceCode) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/oauth/device/token'),
      headers: _headers,
      body: jsonEncode({
        'code': deviceCode,
        'client_id': clientId,
      }),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    if (res.statusCode == 400) return null; // still waiting
    throw Exception('Token poll failed: ${res.statusCode}');
  }

  /// Revoke an access token on sign-out. Client-ID only — no secret.
  static Future<void> revokeToken(String token) async {
    await http.post(
      Uri.parse('$_baseUrl/oauth/revoke'),
      headers: _headers,
      body: jsonEncode({
        'token': token,
        'client_id': clientId,
      }),
    );
  }

  // ─── User Profile ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUserProfile(String token) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me?extended=full'),
      headers: _authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  static Future<Map<String, dynamic>?> getUserStats(String token) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me/stats'),
      headers: _authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  // ─── Watch History ────────────────────────────────────────────────────────

  static Future<List<dynamic>> getWatchHistory(String token,
      {int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me/history/movies?limit=$limit&extended=full'),
      headers: _authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  static Future<List<dynamic>> getWatchHistoryShows(String token,
      {int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me/history/shows?limit=$limit&extended=full'),
      headers: _authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  // ─── Watchlist ────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getWatchlist(String token,
      {String type = 'movies'}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me/watchlist/$type?extended=full'),
      headers: _authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  static Map<String, dynamic> _watchlistBody(
      {String? imdbId, String? title, String type = 'movies'}) {
    final entry = {
      'title': title,
      'ids': {'imdb': imdbId}
    };
    return type == 'movies'
        ? {
            'movies': [entry]
          }
        : {
            'shows': [entry]
          };
  }

  static Future<bool> addToWatchlist(String token,
      {String? imdbId, String? title, String type = 'movies'}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/sync/watchlist'),
      headers: _authHeaders(token),
      body:
          jsonEncode(_watchlistBody(imdbId: imdbId, title: title, type: type)),
    );
    return res.statusCode == 201;
  }

  /// Removes [title] from the user's Trakt watchlist. Trakt answers 200 with
  /// per-item counts, so anything below 300 means the request was accepted.
  static Future<bool> removeFromWatchlist(String token,
      {String? imdbId, String? title, String type = 'movies'}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/sync/watchlist/remove'),
      headers: _authHeaders(token),
      body:
          jsonEncode(_watchlistBody(imdbId: imdbId, title: title, type: type)),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  // ─── Playback / Continue Watching ─────────────────────────────────────────

  /// Fetches items currently in progress (paused/incomplete watches) from Trakt.
  static Future<List<dynamic>> getPlaybackProgress(String token,
      {int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/sync/playback?limit=$limit&extended=full'),
      headers: _authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  /// Update playback progress on Trakt (scrobble pause / checkpoint).
  static Future<bool> pausePlayback(String token,
      {required String title,
      String? imdbId,
      int? tmdbId,
      required double progress}) async {
    final body = {
      'movie': {
        'title': title,
        'ids': {
          if (imdbId != null) 'imdb': imdbId,
          if (tmdbId != null && tmdbId > 0) 'tmdb': tmdbId,
        },
      },
      'progress': progress,
      'app_version': '1.0',
    };
    final res = await http.post(
      Uri.parse('$_baseUrl/scrobble/pause'),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    );
    return res.statusCode == 201 || res.statusCode == 200;
  }

  // ─── Scrobble / Check-in ─────────────────────────────────────────────────

  /// Scrobble a movie watch (call at end of video).
  static Future<bool> scrobbleMovie(String token,
      {required String title, String? imdbId, double progress = 100.0}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/scrobble/stop'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'movie': {
          'title': title,
          'ids': {'imdb': imdbId}
        },
        'progress': progress,
        'app_version': '1.0',
      }),
    );
    return res.statusCode == 201 || res.statusCode == 200;
  }

  // ─── Ratings ─────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getRatings(String token,
      {String type = 'movies'}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/users/me/ratings/$type?extended=full'),
      headers: _authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  static Future<bool> rateMovie(String token,
      {required String title, String? imdbId, required int rating}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/sync/ratings'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'movies': [
          {
            'rating': rating,
            'title': title,
            'ids': {'imdb': imdbId}
          }
        ]
      }),
    );
    return res.statusCode == 201;
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  static Future<List<dynamic>> searchMovies(String query,
      {int limit = 20}) async {
    final encoded = Uri.encodeComponent(query);
    final res = await http.get(
      Uri.parse(
          '$_baseUrl/search/movie?query=$encoded&limit=$limit&extended=full'),
      headers: _headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  // ─── Trending ────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getTrendingMovies({int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/movies/trending?limit=$limit&extended=full'),
      headers: _headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  static Future<List<dynamic>> getPopularMovies({int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/movies/popular?limit=$limit&extended=full'),
      headers: _headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  static Future<List<dynamic>> getRecommendedMovies({int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/movies/recommended?limit=$limit&extended=full'),
      headers: _headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  static Future<List<dynamic>> getTrendingShows({int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/shows/trending?limit=$limit&extended=full'),
      headers: _headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  static Future<List<dynamic>> getPopularShows({int limit = 20}) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/shows/popular?limit=$limit&extended=full'),
      headers: _headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }
}
