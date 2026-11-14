import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import 'stream_resolver_service.dart';
import 'diagnostic_service.dart';

// ─── AppBridge ────────────────────────────────────────────────────────────────
// HTTP + DOM utility layer used by JsScraperBridge.
// Makes plain HTTP requests and parses HTML — no WebView, no Arabic sites.

class AppBridge {
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Mobile Safari/537.36';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    followRedirects: true,
    maxRedirects: 5,
    headers: {
      'User-Agent': _ua,
      'Accept': '*/*',
    },
  ));

  static Future<String> fetch(String url, {Map<String, String>? headers}) async {
    try {
      final resp = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: {
            ...?headers,
            'User-Agent': _ua,
          },
          responseType: ResponseType.plain,
        ),
      );
      final data = resp.data;
      return data is String ? data : '';
    } catch (e) {
      _dlog('fetch failed [$url]: $e', level: LogLevel.warning);
      return '';
    }
  }

  /// Scans raw HTML/JS text for any .m3u8 or .mp4 URL.
  static List<String> extractStreamUrls(String text) {
    if (text.isEmpty) return [];

    // Unescape forward-slash escaping common in JSON-embedded JS
    final unescaped = text.replaceAll(r'\/', '/');

    final pattern = RegExp(
      "https?://[^\\s\"'\\\\<>{}[\\]|^`]+(?:\\.m3u8|\\.mp4)[^\\s\"'\\\\<>{}[\\]|^`]*",
      caseSensitive: false,
    );

    final seen = <String>{};
    final out = <String>[];
    for (final m in pattern.allMatches(unescaped)) {
      var url = m.group(0)!;
      // Strip trailing junk characters
      url = url.replaceAll(RegExp(r'[;,\)\}\]]+$'), '');
      if (url.isNotEmpty && seen.add(url)) out.add(url);
    }
    return out;
  }

  /// Decode Dean Edwards p,a,c,k,e,d JavaScript obfuscation.
  static String unpackJs(String script) {
    try {
      final reg = RegExp(
        r"}\s*\(\s*'(.*?)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'([^']*)'\.split\('\|'\)",
        dotAll: true,
      );
      final match = reg.firstMatch(script);
      if (match == null) return script;

      final payload = match.group(1)!;
      final radix = int.parse(match.group(2)!);
      final count = int.parse(match.group(3)!);
      final symtab = match.group(4)!.split('|');

      String decodeWord(int c, int a) {
        final prefix = c >= a ? decodeWord(c ~/ a, a) : '';
        final rem = c % a;
        final char = rem > 35
            ? String.fromCharCode(rem + 29)
            : rem.toRadixString(36);
        return prefix + char;
      }

      final lookup = <String, String>{};
      for (int i = 0; i < count; i++) {
        final key = decodeWord(i, radix);
        final val = i < symtab.length && symtab[i].isNotEmpty
            ? symtab[i]
            : key;
        lookup[key] = val;
      }

      return payload.replaceAllMapped(RegExp(r'\b\w+\b'), (m) {
        final word = m.group(0)!;
        return lookup[word] ?? word;
      });
    } catch (_) {
      return script;
    }
  }

  static void _dlog(String msg, {LogLevel level = LogLevel.info}) =>
      DiagnosticService.instance.log('AppBridge', msg, level: level);
}

// ─── JsScraperBridge ─────────────────────────────────────────────────────────
// HTTP-based stream extractor that works on English titles via TMDB ids.
// Uses the same provider URLs as StreamResolverService but fetches their embed
// pages directly over HTTP and parses the response for stream URLs — no WebView
// required. This serves as the fallback when the WebView interceptor returns
// nothing (e.g. on web, or when all providers time out).

class JsScraperBridge {
  // English-content providers indexed by TMDB id (same as StreamResolverService)
  static const List<String> _movieTargets = [
    'https://vidsrc.to/embed/movie/',
    'https://autoembed.co/movie/tmdb/',
    'https://vidlink.pro/movie/',
    'https://vidsrc.net/embed/movie/',
    'https://vidsrc.pm/embed/movie/',
    'https://vidsrc.me/embed/movie?tmdb=',
    'https://multiembed.mov/directstream.php?video_id=',
  ];

  static const List<String> _tvTargets = [
    'https://vidsrc.to/embed/tv/',
    'https://autoembed.co/tv/tmdb/',
    'https://vidlink.pro/tv/',
    'https://vidsrc.net/embed/tv/',
    'https://vidsrc.pm/embed/tv/',
    'https://vidsrc.me/embed/tv?tmdb=',
  ];

  // Domains that serve real stream files — detected in extracted URLs
  static const List<String> _cdnHosts = [
    'vidsrc.stream', 'playit.buzz', 'filemoon', 'moonplayer',
    'vidplay', 'vipstream', 'fastcdn', 'vidmoly', 'vidhide',
    'voe.sx', 'streamwish', 'streamtape', 'conversionfocusedstudio',
    'nextgencloudfabric', 'rabbitstream', 'megacloud', 'dokicloud',
    'streamlare', 'mixdrop', 'upstream', 'doodstream', 'streamcrypt',
    'cloudflarestorage',
  ];

  static const List<String> _blacklistedTerms = [
    'exoclick', 'adsterra', 'popcash', 'propeller', 'juicyads',
    'trafficjunky', 'ero', 'porn', 'cam', 'adult', 'sex', 'tube',
    'dating', 'bet', 'casino', 'strip', 'cams', 'livejasmin',
    'chaturbate', 'bongacams', 'doubleclick', 'googleads', 'adnxs',
    'moatads', 'criteo', 'outbrain', 'histats', 'tagivi',
    'createlouisville', 'gussiessmutchy', 'preroll', 'midroll',
    'vast', 'vpaid', 'banner', 'adserver', 'popunder', 'popup',
    'adcontent', 'syndication',
  ];

  static bool get isLoaded => true; // HTTP-based; no asset loading needed.

  /// Stub kept for API compatibility — nothing to load.
  static Future<bool> loadPlugin({String path = ''}) async => true;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Resolves playable streams for [tmdbId] via direct HTTP extraction.
  /// Uses English-content providers indexed by TMDB id — works globally.
  static Future<List<ResolvedStream>> getStreams(
    int tmdbId, {
    bool isTV = false,
    int season = 1,
    int episode = 1,
    String? title,
  }) async {
    if (tmdbId <= 0) return [];

    _dlog('getStreams tmdbId=$tmdbId isTV=$isTV S${season}E$episode');

    final targets = isTV ? _tvTargets : _movieTargets;
    final streams = <ResolvedStream>[];
    final seen = <String>{};

    for (final base in targets) {
      final embedUrl = _buildUrl(base, tmdbId, isTV, season, episode);
      _dlog('Trying HTTP extraction: $embedUrl');

      try {
        final resolved = await _extractFromEmbed(embedUrl);
        for (final s in resolved) {
          if (seen.add(s.url)) {
            streams.add(s);
            _dlog('✅ Found stream: ${s.url}', level: LogLevel.success);
          }
        }
      } catch (e) {
        _dlog('HTTP extraction failed for $embedUrl: $e', level: LogLevel.warning);
      }

      if (streams.isNotEmpty) break;
    }

    _dlog(streams.isEmpty
        ? '❌ No streams found for tmdbId=$tmdbId'
        : '✅ ${streams.length} stream(s) found for tmdbId=$tmdbId');

    return streams;
  }

  /// Returns direct download URL candidates (MP4 preferred, HLS fallback).
  static Future<List<String>> getDownloadLinks(
    int tmdbId, {
    bool isTV = false,
    int season = 1,
    int episode = 1,
    String? title,
  }) async {
    final streams = await getStreams(
      tmdbId,
      isTV: isTV,
      season: season,
      episode: episode,
      title: title,
    );

    // Prefer MP4 for downloads; HLS as last resort
    final mp4 = streams.where((s) => s.url.toLowerCase().contains('.mp4'));
    if (mp4.isNotEmpty) return mp4.map((s) => s.url).toList();
    return streams.map((s) => s.url).toList();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static String _buildUrl(
      String base, int tmdbId, bool isTV, int season, int episode) {
    if (base.contains('autoembed.co')) {
      return isTV ? '$base$tmdbId-$season-$episode' : '$base$tmdbId';
    }
    if (base.contains('vidlink.pro')) {
      return isTV ? '$base$tmdbId/$season/$episode' : '$base$tmdbId';
    }
    if (base.contains('multiembed.mov')) {
      return isTV
          ? '$base$tmdbId&s=$season&e=$episode'
          : '$base$tmdbId';
    }
    if (base.contains('?tmdb=')) {
      // vidsrc.me style
      return isTV
          ? '$base$tmdbId&season=$season&episode=$episode'
          : '$base$tmdbId';
    }
    // vidsrc.to / vidsrc.net / vidsrc.pm path style
    return isTV ? '$base$tmdbId/$season-$episode' : '$base$tmdbId';
  }

  /// Fetches an embed page and extracts any stream URLs from the HTML/JS.
  static Future<List<ResolvedStream>> _extractFromEmbed(
      String embedUrl) async {
    final uri = Uri.tryParse(embedUrl);
    if (uri == null) return [];

    final origin = '${uri.scheme}://${uri.host}';
    final referer = '$origin/';

    // Step 1: fetch the embed page itself
    final html = await AppBridge.fetch(embedUrl, headers: {
      'Referer': referer,
      'Origin': origin,
    });
    if (html.isEmpty) return [];

    final unpacked = AppBridge.unpackJs(html);
    final combined = '$html\n$unpacked';

    // Step 2: scan for direct stream URLs in the page source
    final directUrls = AppBridge.extractStreamUrls(combined);
    if (directUrls.isNotEmpty) {
      return _toResolvedStreams(directUrls, referer, origin);
    }

    // Step 3: follow iframes one level deep
    final doc = html_parser.parse(html);
    final iframes = doc.querySelectorAll('iframe[src]');
    for (final iframe in iframes) {
      var iframeSrc = iframe.attributes['src'] ?? '';
      if (iframeSrc.isEmpty) continue;
      if (iframeSrc.startsWith('//')) iframeSrc = 'https:$iframeSrc';
      if (!iframeSrc.startsWith('http')) continue;

      // Skip embed pages — only follow CDN/player frames
      if (_looksLikeEmbedPage(iframeSrc)) continue;

      _dlog('Following iframe: $iframeSrc');
      final iframeHtml = await AppBridge.fetch(iframeSrc, headers: {
        'Referer': embedUrl,
        'Origin': origin,
      });
      if (iframeHtml.isEmpty) continue;

      final iframeUnpacked = AppBridge.unpackJs(iframeHtml);
      final iframeCombined = '$iframeHtml\n$iframeUnpacked';
      final iframeUrls = AppBridge.extractStreamUrls(iframeCombined);
      if (iframeUrls.isNotEmpty) {
        return _toResolvedStreams(iframeUrls, iframeSrc, origin);
      }

      // Step 4: try JSON API endpoints commonly found in embed pages
      final apiUrls = _findApiEndpoints(iframeHtml, iframeSrc);
      for (final apiUrl in apiUrls) {
        _dlog('Trying API endpoint: $apiUrl');
        final apiBody = await AppBridge.fetch(apiUrl, headers: {
          'Referer': iframeSrc,
          'Origin': origin,
          'Accept': 'application/json, */*',
          'X-Requested-With': 'XMLHttpRequest',
        });
        if (apiBody.isEmpty) continue;

        final apiUrls2 = AppBridge.extractStreamUrls(apiBody);
        if (apiUrls2.isNotEmpty) {
          return _toResolvedStreams(apiUrls2, iframeSrc, origin);
        }

        // Try decoding as JSON
        try {
          final json = jsonDecode(apiBody);
          final fromJson = _extractUrlsFromJson(json);
          if (fromJson.isNotEmpty) {
            return _toResolvedStreams(fromJson, iframeSrc, origin);
          }
        } catch (_) {}
      }
    }

    return [];
  }

  /// Recursively walks a JSON tree pulling out any .m3u8 / .mp4 string values.
  static List<String> _extractUrlsFromJson(dynamic node) {
    final out = <String>[];
    if (node is String) {
      if (node.contains('.m3u8') || node.contains('.mp4')) out.add(node);
    } else if (node is List) {
      for (final item in node) {
        out.addAll(_extractUrlsFromJson(item));
      }
    } else if (node is Map) {
      for (final value in node.values) {
        out.addAll(_extractUrlsFromJson(value));
      }
    }
    return out;
  }

  /// Finds JSON API endpoint patterns commonly used by embed players
  /// (e.g. `/api/getSources?id=…`, `/sources?id=…`).
  static List<String> _findApiEndpoints(String html, String pageUrl) {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null) return [];
    final base = '${uri.scheme}://${uri.host}';

    final patterns = [
      RegExp(r'''(?:fetch|ajax|get)\s*\(['"]((?:/[^\s'"]+)+)['"]'''),
      RegExp(r'''"((?:/api/|/source|/getSources|/stream)[^\s'"]+)"'''),
    ];

    final out = <String>[];
    final seen = <String>{};
    for (final pat in patterns) {
      for (final m in pat.allMatches(html)) {
        final path = m.group(1)!;
        final full = path.startsWith('http') ? path : '$base$path';
        if (seen.add(full)) out.add(full);
      }
    }
    return out.take(3).toList(); // cap to avoid runaway requests
  }

  static bool _looksLikeEmbedPage(String url) {
    final lower = url.toLowerCase();
    const embedHosts = [
      'autoembed.co', 'vidsrc.to', 'vidsrc.me', 'vidsrc.net',
      'vidsrc.pm', 'vidlink.pro', 'multiembed.mov',
    ];
    for (final h in embedHosts) {
      if (lower.contains(h)) return true;
    }
    return false;
  }

  static bool _looksLikeStream(String url) {
    final lower = url.toLowerCase();
    for (final bad in _blacklistedTerms) {
      if (lower.contains(bad)) return false;
    }
    if (lower.contains('.m3u8')) return true;
    if (lower.contains('/hls/') || lower.contains('/playlist')) return true;
    if (lower.contains('.mp4')) {
      for (final cdn in _cdnHosts) {
        if (lower.contains(cdn)) return true;
      }
      return false;
    }
    return false;
  }

  static List<ResolvedStream> _toResolvedStreams(
      List<String> urls, String referer, String origin) {
    return urls
        .where(_looksLikeStream)
        .map((u) => ResolvedStream(url: u, referer: referer, origin: origin))
        .toList();
  }

  static void _dlog(String msg, {LogLevel level = LogLevel.info}) =>
      DiagnosticService.instance.log('JsScraperBridge', msg, level: level);
}
