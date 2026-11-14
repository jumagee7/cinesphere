import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'stream_resolver_service.dart';
import 'diagnostic_service.dart';

/// Direct HTTP extractor for VixSrc.to
///
/// VixSrc provides direct high-speed HLS (.m3u8) streams with multi-language
/// audio and subtitle tracks for movies and TV series by TMDB ID.
/// Does not depend on WebView rendering, bypasses Cloudflare challenges,
/// and returns in ~500ms.
class VixsrcResolverService {
  static const String _baseUrl = 'https://vixsrc.to';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Referer': '$_baseUrl/',
    'Origin': _baseUrl,
  };

  /// Resolves a playable HLS master playlist URL for [tmdbId].
  static Future<ResolvedStream?> resolve({
    required int tmdbId,
    bool isTV = false,
    int season = 1,
    int episode = 1,
  }) async {
    final client = http.Client();
    try {
      final apiUrl = isTV
          ? '$_baseUrl/api/tv/$tmdbId/$season/$episode'
          : '$_baseUrl/api/movie/$tmdbId';

      _log('Resolving VixSrc: $apiUrl');

      // Step 1: Call API endpoint to get the embed sub-path
      final res1 = await client
          .get(Uri.parse(apiUrl), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (res1.statusCode != 200) {
        _log('VixSrc API returned HTTP ${res1.statusCode}', level: LogLevel.warning);
        return null;
      }

      final Map<String, dynamic> data = jsonDecode(res1.body) as Map<String, dynamic>;
      final src = data['src'] as String?;
      if (src == null || src.isEmpty) {
        _log('VixSrc API returned no src attribute', level: LogLevel.warning);
        return null;
      }

      // Step 2: Fetch embed page to extract session token, expires, and playlist base
      final embedUrl = '$_baseUrl$src';
      final res2 = await client.get(
        Uri.parse(embedUrl),
        headers: {
          ..._headers,
          'Accept': 'text/html,application/xhtml+xml,*/*',
        },
      ).timeout(const Duration(seconds: 8));

      if (res2.statusCode != 200) {
        _log('VixSrc embed page returned HTTP ${res2.statusCode}', level: LogLevel.warning);
        return null;
      }

      final html = res2.body;
      final token = RegExp(r'''token["']\s*:\s*["']([^"']+)''').firstMatch(html)?.group(1);
      final expires = RegExp(r'''expires["']\s*:\s*["']([^"']+)''').firstMatch(html)?.group(1);
      final playlist = RegExp(r'''url\s*:\s*["']([^"']+)''').firstMatch(html)?.group(1);

      if (token == null || expires == null || playlist == null) {
        _log('VixSrc failed to parse token/expires/playlist tokens', level: LogLevel.warning);
        return null;
      }

      final sep = playlist.contains('?') ? '&' : '?';
      final masterUrl = '$playlist${sep}token=$token&expires=$expires&h=1';

      _log('VixSrc resolved master stream: $masterUrl', level: LogLevel.success);

      // Extract audio/subtitle tracks from the master playlist. The same
      // response is handed to the player so its local proxy doesn't have to
      // fetch the master again.
      final List<SubtitleTrack> subtitles = [];
      final List<AudioTrackOption> audioTracks = [];
      String? masterPlaylist;
      try {
        final res3 = await client.get(
          Uri.parse(masterUrl),
          headers: {
            ..._headers,
            'Referer': apiUrl,
          },
        ).timeout(const Duration(seconds: 5));

        if (res3.statusCode == 200) {
          masterPlaylist = res3.body;
          for (final line in res3.body.split('\n')) {
            if (line.startsWith('#EXT-X-MEDIA:TYPE=SUBTITLES')) {
              final name = RegExp(r'''NAME="([^"]+)"''').firstMatch(line)?.group(1);
              final lang = RegExp(r'''LANGUAGE="([^"]+)"''').firstMatch(line)?.group(1) ?? 'en';
              final rawUri = RegExp(r'''URI="([^"]+)"''').firstMatch(line)?.group(1);
              if (name != null && rawUri != null) {
                final fullUri = Uri.parse(masterUrl).resolve(rawUri).toString();
                subtitles.add(SubtitleTrack(
                  label: name,
                  language: lang,
                  url: fullUri,
                ));
              }
            } else if (line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
              final rawUri = RegExp(r'''URI="([^"]+)"''').firstMatch(line)?.group(1);
              if (rawUri == null || rawUri.isEmpty) continue;
              final name = RegExp(r'''NAME="([^"]+)"''').firstMatch(line)?.group(1) ?? 'Audio';
              final lang = RegExp(r'''LANGUAGE="([^"]+)"''').firstMatch(line)?.group(1) ?? '';
              audioTracks.add(AudioTrackOption(
                label: name,
                language: lang,
                isDefault: line.contains('DEFAULT=YES'),
              ));
            }
          }
          if (subtitles.isNotEmpty) {
            _log('Discovered ${subtitles.length} subtitle tracks from VixSrc');
          }
          if (audioTracks.length > 1) {
            _log('Discovered ${audioTracks.length} audio tracks from VixSrc');
          }
        }
      } catch (subErr) {
        _log('Track extraction skipped: $subErr');
      }

      return ResolvedStream(
        url: masterUrl,
        referer: apiUrl,
        origin: _baseUrl,
        subtitles: subtitles,
        audioTracks: audioTracks,
        masterPlaylist: masterPlaylist,
      );
    } catch (e) {
      _log('VixSrc resolver error: $e', level: LogLevel.warning);
      return null;
    } finally {
      client.close();
    }
  }

  static void _log(String msg, {LogLevel level = LogLevel.info}) {
    DiagnosticService.instance.log('VixSrc', msg, level: level);
  }
}

