import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'diagnostic_service.dart';
import 'settings_service.dart';

/// A local HTTP reverse-proxy that injects the required HTTP headers
/// (Referer, Origin, Cookie, User-Agent) on every request on behalf of
/// the native video player.
///
/// ExoPlayer (video_player) does NOT forward custom headers to HLS segment
/// requests — only to the manifest.  By routing ALL traffic through this proxy
/// (127.0.0.1) every request gets the correct headers, so the CDN never sees
/// a bare/unauthorised request.
///
/// Usage:
///   final proxyUrl = await StreamProxyService.instance.start(realUrl, headers);
///   // pass proxyUrl to VideoPlayerController instead of realUrl
///   ...
///   await StreamProxyService.instance.stop(); // in dispose()
class StreamProxyService {
  StreamProxyService._();
  static final StreamProxyService instance = StreamProxyService._();

  HttpServer? _server;
  String? _targetUrl;
  Map<String, String> _headers = {};
  int _port = 0;
  final http.Client _client = http.Client();
  VideoQuality _qualityTarget = VideoQuality.auto;
  String? _audioTargetLanguage;
  String? _initialManifest;
  String? _activeSessionId;
  int _relayedBytes = 0;

  bool get isRunning => _server != null;

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Configures target quality for HLS streams (e.g. 1080p, 720p, 480p, auto).
  void setQualityTarget(VideoQuality quality) {
    _qualityTarget = quality;
    _log('StreamProxy quality target set to: ${quality.name}');
  }

  /// Restricts audio renditions to [language] (e.g. "en"). Pass null/'' to
  /// fall back to the built-in English-preference heuristics.
  void setAudioTarget(String? language) {
    _audioTargetLanguage =
        (language == null || language.trim().isEmpty) ? null : language.trim();
    _log('StreamProxy audio target: ${_audioTargetLanguage ?? "auto"}');
  }

  /// Bytes relayed to the player since the previous call. Lets the player
  /// measure real media throughput without counting other apps' traffic.
  int takeRelayedBytes() {
    final bytes = _relayedBytes;
    _relayedBytes = 0;
    return bytes;
  }

  /// Starts (or restarts) the proxy for [url] with [headers].
  /// Returns the localhost URL to hand to the video player.
  ///
  /// [initialManifest] lets the caller hand over an already-fetched master
  /// playlist body so the player's first request doesn't pay for another
  /// network round trip.
  Future<String> start(
    String url,
    Map<String, String> headers, {
    String? sessionId,
    String? initialManifest,
  }) async {
    await stop();
    _activeSessionId = sessionId;
    _targetUrl = url;
    _headers = Map.unmodifiable(headers);
    _initialManifest = initialManifest;
    _relayedBytes = 0;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _log('Proxy started on port $_port (session=$sessionId) → $url');
    _serve(_server!);

    // ExoPlayer needs the .m3u8 extension to pick the HLS extractor.
    final lower = url.toLowerCase();
    final ext = lower.contains('.mp4')
        ? '.mp4'
        : '.m3u8'; // Default to HLS manifest
    return 'http://127.0.0.1:$_port/stream$ext';
  }

  Future<void> stop({String? sessionId}) async {
    // If a specific session is stopping, don't stop if a newer session took over
    if (sessionId != null && _activeSessionId != null && sessionId != _activeSessionId) {
      _log('Proxy stop ignored for superseded session $sessionId (active: $_activeSessionId)');
      return;
    }
    final s = _server;
    _server = null;
    _activeSessionId = null;
    _initialManifest = null;
    try {
      await s?.close(force: true);
    } catch (_) {}
    _log('Proxy stopped');
  }

  // ─── Internal ───────────────────────────────────────────────────────────────

  void _serve(HttpServer server) {
    server.listen((req) async {
      try {
        await _handle(req);
      } catch (e) {
        _log('Handler error: $e', level: LogLevel.error);
        try {
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> _handle(HttpRequest req) async {
    if (req.method == 'OPTIONS') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set('access-control-allow-origin', '*')
        ..headers.set('access-control-allow-methods', 'GET, HEAD, OPTIONS')
        ..headers.set('access-control-allow-headers', '*');
      await req.response.close();
      return;
    }

    final targetUrl = _targetUrl;
    if (targetUrl == null) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      await req.response.close();
      return;
    }

    final fetchUrl = _resolveUrl(req.uri, targetUrl);
    _log('→ $fetchUrl');

    // Serve the pre-fetched master playlist for the entry request so the
    // player starts without waiting on another upstream round trip.
    final cached = _initialManifest;
    if (cached != null &&
        _isEntryPath(req.uri.path) &&
        !req.uri.path.endsWith('.mp4')) {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set('access-control-allow-origin', '*')
        ..headers.set('content-type', 'application/vnd.apple.mpegurl');
      req.response.write(_rewriteM3u8(cached, fetchUrl));
      await req.response.close();
      return;
    }

    // Build the upstream request (preserving Range for MP4 seeks).
    final upstreamReq = http.Request('GET', Uri.parse(fetchUrl))
      ..headers.addAll(_headers)
      ..followRedirects = true
      ..maxRedirects = 5;

    final rangeHeader = req.headers.value('range');
    if (rangeHeader != null) {
      upstreamReq.headers['Range'] = rangeHeader;
    }

    final streamed = await _client
        .send(upstreamReq)
        .timeout(const Duration(seconds: 30));

    final contentType = streamed.headers['content-type'] ?? '';
    final isM3u8 = fetchUrl.toLowerCase().contains('.m3u8') ||
        contentType.contains('mpegurl') ||
        fetchUrl.endsWith('/stream.m3u8');

    req.response.statusCode = streamed.statusCode;
    req.response.headers
      ..set('access-control-allow-origin', '*')
      ..set('accept-ranges', 'bytes');

    if (isM3u8) {
      req.response.headers.set('content-type', 'application/vnd.apple.mpegurl');
    } else if (contentType.isNotEmpty) {
      req.response.headers.set('content-type', contentType);
    }

    final cl = streamed.headers['content-length'];
    if (cl != null && !isM3u8) {
      req.response.headers.set('content-length', cl);
    }

    if (streamed.statusCode == HttpStatus.partialContent) {
      final cr = streamed.headers['content-range'];
      if (cr != null) req.response.headers.set('content-range', cr);
    }

    if (isM3u8) {
      // Buffer the manifest, rewrite segment URLs, then send.
      final body = await streamed.stream
          .transform(const SystemEncoding().decoder)
          .join();
      final rewritten = _rewriteM3u8(body, fetchUrl);
      req.response.write(rewritten);
    } else {
      // Stream bytes directly — avoids buffering large segments in memory.
      await req.response.addStream(streamed.stream.map((chunk) {
        _relayedBytes += chunk.length;
        return chunk;
      }));
    }

    await req.response.close();
  }

  /// Determines the real CDN URL for an incoming proxy request.
  String _resolveUrl(Uri proxyUri, String originalUrl) {
    final path = proxyUri.path;

    // The entry-point path (/stream, /stream.m3u8, /stream.mp4) → original URL.
    if (_isEntryPath(path)) {
      return originalUrl;
    }

    // All other paths are segment / sub-manifest requests that were rewritten
    // from the original manifest.  Reconstruct against the CDN base.
    final base = Uri.parse(originalUrl);
    final query =
        proxyUri.query.isNotEmpty ? '?${proxyUri.query}' : '';
    // If the path starts with /http or /https it was originally an absolute URL
    // that we stripped the scheme+host from.
    if (path.startsWith('/https/') || path.startsWith('/http/')) {
      final scheme = path.startsWith('/https/') ? 'https' : 'http';
      final remainder = path.substring(scheme == 'https' ? 7 : 6);
      return '$scheme://$remainder$query';
    }
    return base.resolve('$path$query').toString();
  }

  bool _isEntryPath(String path) =>
      path == '/stream' || path == '/stream.m3u8' || path == '/stream.mp4';

  // ─── HLS manifest rewriting ─────────────────────────────────────────────────

  /// Rewrites every URL in an HLS manifest so that segment and sub-manifest
  /// requests go through the local proxy (preserving all original parameters).
  String _rewriteM3u8(String m3u8, String baseUrl) {
    final base = Uri.parse(baseUrl);
    final pinned = _applyAudioTarget(m3u8);
    final manifest = pinned ?? m3u8;

    // If master playlist with variants and quality target is explicitly fixed (not auto), prioritize matching variant
    if (manifest.contains('#EXT-X-STREAM-INF') &&
        _qualityTarget != VideoQuality.auto) {
      return _rewriteMasterPlaylistWithQuality(
        manifest,
        base,
        audioPinned: pinned != null,
      );
    }

    final sb = StringBuffer();
    for (final raw in manifest.split('\n')) {
      final line = raw.trimRight(); // keep leading spaces, strip trailing \r
      if (line.isEmpty) {
        sb.writeln();
        continue;
      }
      if (line.startsWith('#')) {
        // Handle audio tracks: prioritize English as default and autoselect.
        // Skipped when the user pinned a specific track — that line is already
        // marked DEFAULT=YES by _applyAudioTarget.
        String rewritten = line;
        if (pinned == null && line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
          rewritten = _normalizeAudioTrackLine(rewritten);
        }
        // Rewrite URI="…" attributes inside tags (#EXT-X-KEY, #EXT-X-MAP, #EXT-X-MEDIA, etc.)
        sb.writeln(_rewriteTagUris(rewritten, base));
      } else {
        // Segment or sub-manifest URL (relative or absolute).
        sb.writeln(_proxyUrl(line.trim(), base));
      }
    }
    return sb.toString();
  }

  /// Keeps only the audio rendition matching the user's chosen language and
  /// marks it as the default. Returns null when nothing was pinned (target
  /// unset, no renditions, no match) so callers keep the default heuristics.
  String? _applyAudioTarget(String m3u8) {
    final target = _audioTargetLanguage;
    if (target == null || !m3u8.contains('#EXT-X-MEDIA:TYPE=AUDIO')) {
      return null;
    }

    final audioLines = <String>[];
    for (final raw in m3u8.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) audioLines.add(line);
    }
    if (audioLines.isEmpty) return null;

    int picked = audioLines.indexWhere((l) => _audioLineMatches(l, target));
    if (picked < 0) {
      // No exact match — accept any rendition whose language starts with the
      // target code (e.g. "en" ↔ "en-US").
      final t = target.toLowerCase();
      picked = audioLines.indexWhere((l) {
        final lang = _attr(l, 'LANGUAGE').toLowerCase();
        return lang.isNotEmpty && (lang.startsWith(t) || t.startsWith(lang));
      });
    }
    if (picked < 0) {
      // A lone rendition is the only choice regardless of its language tag;
      // with several, fall back to the English-preference heuristics.
      if (audioLines.length > 1) {
        _log('Audio target "$target" not found; using default track',
            level: LogLevel.warning);
        return null;
      }
      picked = 0;
    }

    final chosen = audioLines[picked];
    final sb = StringBuffer();
    var audioIndex = 0;
    for (final raw in m3u8.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
        if (audioIndex++ == picked) sb.writeln(_forceDefault(chosen));
        continue;
      }
      sb.writeln(line);
    }
    return sb.toString();
  }

  bool _audioLineMatches(String line, String target) {
    final t = target.toLowerCase();
    final lang = _attr(line, 'LANGUAGE').toLowerCase();
    final name = _attr(line, 'NAME').toLowerCase();
    if (lang == t || name == t) return true;
    const codes = {
      'en': ['en', 'eng', 'english'],
      'es': ['es', 'spa', 'spanish'],
      'fr': ['fr', 'fra', 'fre', 'french'],
      'de': ['de', 'deu', 'ger', 'german'],
      'it': ['it', 'ita', 'italian'],
      'pt': ['pt', 'por', 'portuguese'],
      'hi': ['hi', 'hin', 'hindi'],
      'ja': ['ja', 'jpn', 'japanese'],
      'ko': ['ko', 'kor', 'korean'],
      'ar': ['ar', 'ara', 'arabic'],
      'ru': ['ru', 'rus', 'russian'],
    };
    for (final entry in codes.entries) {
      final family = entry.value;
      if (family.contains(t) &&
          (family.contains(lang) || family.contains(name))) {
        return true;
      }
    }
    return false;
  }

  String _attr(String line, String name) =>
      RegExp('$name="([^"]*)"', caseSensitive: false).firstMatch(line)?.group(1) ??
      '';

  String _forceDefault(String line) {
    var modified = line;
    if (modified.contains('DEFAULT=NO')) {
      modified = modified.replaceFirst('DEFAULT=NO', 'DEFAULT=YES');
    } else if (!modified.contains('DEFAULT=')) {
      modified += ',DEFAULT=YES';
    }
    if (modified.contains('AUTOSELECT=NO')) {
      modified = modified.replaceFirst('AUTOSELECT=NO', 'AUTOSELECT=YES');
    } else if (!modified.contains('AUTOSELECT=')) {
      modified += ',AUTOSELECT=YES';
    }
    return modified;
  }

  /// Ensures English audio tracks are marked as DEFAULT=YES and AUTOSELECT=YES,
  /// while non-English tracks with DEFAULT=YES have it cleared so ExoPlayer
  /// defaults to English audio instead of foreign language dubs.
  String _normalizeAudioTrackLine(String line) {
    final lower = line.toLowerCase();
    final isEnglish = lower.contains('language="eng"') ||
        lower.contains('language="en"') ||
        lower.contains('name="english"');

    if (isEnglish) {
      String modified = line;
      if (modified.contains('DEFAULT=NO')) {
        modified = modified.replaceFirst('DEFAULT=NO', 'DEFAULT=YES');
      } else if (!modified.contains('DEFAULT=')) {
        modified += ',DEFAULT=YES';
      }
      if (modified.contains('AUTOSELECT=NO')) {
        modified = modified.replaceFirst('AUTOSELECT=NO', 'AUTOSELECT=YES');
      } else if (!modified.contains('AUTOSELECT=')) {
        modified += ',AUTOSELECT=YES';
      }
      return modified;
    } else {
      // Non-English track: remove DEFAULT=YES and AUTOSELECT=YES
      String modified = line;
      if (modified.contains('DEFAULT=YES')) {
        modified = modified.replaceFirst('DEFAULT=YES', 'DEFAULT=NO');
      }
      if (modified.contains('AUTOSELECT=YES')) {
        modified = modified.replaceFirst('AUTOSELECT=YES', 'AUTOSELECT=NO');
      }
      return modified;
    }
  }

  String _rewriteMasterPlaylistWithQuality(
    String m3u8,
    Uri base, {
    bool audioPinned = false,
  }) {
    final lines = m3u8.split('\n');
    final headerLines = <String>[];
    final mediaLines = <String>[];
    final variants = <_VariantEntry>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        int height = 0;
        final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
        if (resMatch != null) height = int.tryParse(resMatch.group(1)!) ?? 0;

        String? streamUrl;
        for (int j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isNotEmpty && !next.startsWith('#')) {
            streamUrl = next;
            i = j;
            break;
          }
        }
        if (streamUrl != null) {
          variants.add(_VariantEntry(
            tag: _rewriteTagUris(line, base),
            url: _proxyUrl(streamUrl, base),
            height: height,
          ));
        }
      } else if (line.startsWith('#EXT-X-MEDIA:')) {
        String mediaLine = line;
        if (!audioPinned && line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')) {
          mediaLine = _normalizeAudioTrackLine(mediaLine);
        }
        mediaLines.add(_rewriteTagUris(mediaLine, base));
      } else if (line.startsWith('#EXTM3U') || line.startsWith('#EXT-X-VERSION')) {
        headerLines.add(_rewriteTagUris(line, base));
      } else if (variants.isEmpty) {
        headerLines.add(_rewriteTagUris(line, base));
      }
    }

    if (variants.isEmpty) {
      return m3u8;
    }

    int targetHeight = 1080;
    switch (_qualityTarget) {
      case VideoQuality.uhd4k:
        targetHeight = 2160;
        break;
      case VideoQuality.fullHd1080:
      case VideoQuality.highest:
        targetHeight = 1080;
        break;
      case VideoQuality.hd720:
        targetHeight = 720;
        break;
      case VideoQuality.sd480:
        targetHeight = 480;
        break;
      case VideoQuality.auto:
        targetHeight = 1080;
        break;
    }

    variants.sort((a, b) {
      final diffA = (a.height - targetHeight).abs();
      final diffB = (b.height - targetHeight).abs();
      return diffA.compareTo(diffB);
    });

    final sb = StringBuffer();
    for (final h in headerLines) {
      sb.writeln(h);
    }
    for (final m in mediaLines) {
      sb.writeln(m);
    }
    // Only emit the best matched variant so ExoPlayer doesn't auto-switch away from user's chosen quality
    final bestVariant = variants.first;
    sb.writeln(bestVariant.tag);
    sb.writeln(bestVariant.url);
    return sb.toString();
  }

  String _rewriteTagUris(String tag, Uri base) {
    return tag.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
      return 'URI="${_proxyUrl(m.group(1)!, base)}"';
    });
  }

  /// Converts a CDN URL (absolute or relative) to a proxy URL.
  String _proxyUrl(String url, Uri base) {
    final Uri resolved;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      resolved = Uri.parse(url);
    } else {
      resolved = base.resolve(url);
    }

    // Encode the scheme and host into the path so the proxy can reconstruct it.
    final scheme = resolved.scheme; // http or https
    final encodedPath =
        '/$scheme/${resolved.host}${resolved.path}';
    final query =
        resolved.query.isNotEmpty ? '?${resolved.query}' : '';
    return 'http://127.0.0.1:$_port$encodedPath$query';
  }

  static void _log(String msg, {LogLevel level = LogLevel.info}) =>
      DiagnosticService.instance.log('StreamProxy', msg, level: level);
}

class _VariantEntry {
  final String tag;
  final String url;
  final int height;

  const _VariantEntry({
    required this.tag,
    required this.url,
    required this.height,
  });
}


