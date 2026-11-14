import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'diagnostic_service.dart';

/// Subtitle track descriptor (label + language + url or vtt content).
class SubtitleTrack {
  final String label;
  final String language;
  final String url;

  const SubtitleTrack({
    required this.label,
    required this.language,
    required this.url,
  });
}

/// Audio rendition advertised by an HLS master playlist
/// (`#EXT-X-MEDIA:TYPE=AUDIO`). Switching tracks restarts the stream through
/// the local proxy with this language selected.
class AudioTrackOption {
  final String label;
  final String language;
  final bool isDefault;

  const AudioTrackOption({
    required this.label,
    required this.language,
    this.isDefault = false,
  });

  bool matches(String language) =>
      this.language.toLowerCase().startsWith(language.toLowerCase());
}

/// Container for a resolved stream URL and its HTTP headers
/// (specifically Referer, Origin, and Cookie) required to bypass CDN/Cloudflare hotlink protection.
class ResolvedStream {
  final String url;
  final String? origin;
  final String? referer;
  /// Raw cookie string captured from the WebView session (e.g. "name=val; name2=val2").
  /// Passed as the `Cookie` header so ExoPlayer can replay the stream with the same session.
  final String? cookies;
  /// Subtitle tracks discovered in the media manifest or API response.
  final List<SubtitleTrack> subtitles;
  /// Audio renditions discovered in the HLS master playlist.
  final List<AudioTrackOption> audioTracks;
  /// The master playlist body, when it was already fetched during resolution.
  /// The player's local proxy serves it for the first manifest request instead
  /// of paying for another round trip.
  final String? masterPlaylist;

  const ResolvedStream({
    required this.url,
    this.origin,
    this.referer,
    this.cookies,
    this.subtitles = const [],
    this.audioTracks = const [],
    this.masterPlaylist,
  });

  Map<String, String> get headers {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';

    String? ref = referer;
    String? orig = origin;

    // Known CDN mappings: conversionfocusedstudio.site and nextgencloudfabric
    // require Referer from nextgencloudfabric.com or player.autoembed.co.
    if (host.contains('conversionfocusedstudio.site') || host.contains('nextgencloudfabric')) {
      ref ??= 'https://nextgencloudfabric.com/';
      orig ??= 'https://nextgencloudfabric.com';
    }

    if (ref == null || ref.isEmpty) {
      if (uri != null) {
        ref = '${uri.scheme}://${uri.host}/';
      }
    }
    if (orig == null || orig.isEmpty) {
      if (ref != null && ref.isNotEmpty) {
        final refUri = Uri.tryParse(ref);
        if (refUri != null && refUri.hasScheme && refUri.hasAuthority) {
          orig = '${refUri.scheme}://${refUri.host}';
        }
      }
    }

    return {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      if (ref != null && ref.isNotEmpty) 'Referer': ref,
      if (orig != null && orig.isNotEmpty) 'Origin': orig,
      if (cookies != null && cookies!.isNotEmpty) 'Cookie': cookies!,
      'Accept': '*/*',
    };
  }

  @override
  String toString() => url;
}

/// Resolves a direct playable stream URL via a hidden WebView interceptor.
class StreamResolverService {
  static const List<String> _movieProviders = [
    'https://vidsrc.me/embed/movie?tmdb=',
    'https://autoembed.co/movie/tmdb/',
    'https://2embed.cc/embed/',
    'https://vidlink.pro/movie/',
    'https://vidsrc.to/embed/movie/',
    'https://vidsrc.net/embed/movie/',
    'https://vidsrc.pm/embed/movie/',
  ];
  static const List<String> _tvProviders = [
    'https://vidsrc.me/embed/tv?tmdb=',
    'https://autoembed.co/tv/tmdb/',
    'https://2embed.cc/embedtv/',
    'https://vidlink.pro/tv/',
    'https://vidsrc.to/embed/tv/',
    'https://vidsrc.net/embed/tv/',
    'https://vidsrc.pm/embed/tv/',
  ];
  static const List<String> _embedPagePatterns = [
    'autoembed.co', 'autoembed.me', 'vidsrc.to', 'vidsrc.sh', 'vidsrc.me', 'vsembed.ru',
    'vidsrc.net', 'histats.com', 'cloudflareinsights.com', 'disable-devtool',
    '.js', '.css', '.svg', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.woff', '.woff2', '.ttf',
  ];
  static const List<String> _blockedDomains = [
    'doubleclick.net', 'googlesyndication.com', 'googletagmanager.com',
    'facebook.com', 'amazon-adsystem.com', 'moatads.com', 'adnxs.com',
    'criteo.com', 'outbrain.com', 'histats.com', 'gtcinfight.cfd', 'disable-devtool',
  ];
  static const List<String> _skipDomains = [
    'youtube.com', 'youtu.be', 'vimeo.com', 'dailymotion.com',
  ];
  static const List<String> _allowedNavigationHosts = [
    'autoembed', 'vidsrc', 'vidlink', 'multiembed', '2embed', 'superembed',
    'playit', 'filemoon', 'moonplayer', 'vidplay', 'vipstream', 'fastcdn',
    'vidmoly', 'vidhide', 'voe', 'streamwish', 'streamtape', 'rabbitstream',
    'megacloud', 'dokicloud', 'streamlare', 'mixdrop', 'upstream', 'doodstream',
    'streamcrypt', 'conversionfocusedstudio', 'nextgencloudfabric', 'birchandbloom',
    'stellarconductornexus', 'cloudflarestorage',
  ];
  static const List<String> _validCdnKeywords = [
    'vidsrc', 'autoembed', 'playit', 'filemoon', 'moonplayer',
    'vidplay', 'vipstream', 'fastcdn', 'vidmoly', 'vidhide',
    'voe', 'streamwish', 'streamtape', 'rabbitstream', 'megacloud',
    'dokicloud', 'streamlare', 'mixdrop', 'upstream', 'doodstream',
    'streamcrypt', 'cloudflarestorage', 'vidlink', 'multiembed',
    'jwplayer', '2embed', 'superembed', 'embed', 'birchandbloom',
    'stellarconductornexus', 'nextgencloudfabric', 'conversionfocusedstudio',
    'shadowlands', 'neonstream', 'streamtape', 'videoview',
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
  static const Duration _perProviderTimeout = Duration(seconds: 22);
  static GlobalKey<NavigatorState>? _navigatorKey;
  static set navigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    _log('navigatorKey registered');
  }

  static Future<ResolvedStream?> resolve({
    required int tmdbId,
    String? imdbId,
    bool isTV = false,
    int season = 1,
    int episode = 1,
    bool quickPlay = true,
    int parallelCount = 2,
    List<String> excludeUrls = const [],
    int startProviderIndex = 0,
  }) async {
    _log('resolve() tmdbId=$tmdbId imdbId=$imdbId isTV=$isTV S${season}E$episode quickPlay=$quickPlay parallel=$parallelCount startIdx=$startProviderIndex exclude=${excludeUrls.length}', level: LogLevel.info);
    final rawProviders = isTV ? _tvProviders : _movieProviders;
    final List<String> providers;
    if (startProviderIndex > 0 && rawProviders.isNotEmpty) {
      final shift = startProviderIndex % rawProviders.length;
      providers = [...rawProviders.sublist(shift), ...rawProviders.sublist(0, shift)];
    } else {
      providers = List.of(rawProviders);
    }

    bool isCandidateValid(ResolvedStream? res) {
      if (res == null || res.url.isEmpty) return false;
      if (excludeUrls.contains(res.url)) {
        _log('Skipping previously tried stream: ${res.url}');
        return false;
      }
      return true;
    }

    if (quickPlay && parallelCount > 1) {
      for (int i = 0; i < providers.length; i += parallelCount) {
        final end = (i + parallelCount < providers.length) ? i + parallelCount : providers.length;
        final batch = providers.sublist(i, end);
        _log('⚡ Quick Play: racing batch ${i ~/ parallelCount + 1} (${batch.length} providers)');

        final completer = Completer<ResolvedStream?>();
        int completedCount = 0;

        for (final p in batch) {
          final embedUrl = _buildUrl(base: p, tmdbId: tmdbId, imdbId: imdbId, isTV: isTV, season: season, episode: episode);
          _runInterceptor(embedUrl).then((res) {
            if (isCandidateValid(res) && !completer.isCompleted) {
              _log('⚡ Quick Play winner: ${res!.url}', level: LogLevel.success);
              completer.complete(res);
            }
          }).catchError((_) => null).whenComplete(() {
            completedCount++;
            if (completedCount == batch.length && !completer.isCompleted) {
              completer.complete(null);
            }
          });
        }

        final best = await completer.future;
        if (best != null && best.url.isNotEmpty) {
          return best;
        }
      }
    } else {
      for (int i = 0; i < providers.length; i++) {
        final embedUrl = _buildUrl(base: providers[i], tmdbId: tmdbId, imdbId: imdbId, isTV: isTV, season: season, episode: episode);
        _log('Trying provider ${i+1}/${providers.length}: $embedUrl');
        final sw = Stopwatch()..start();
        final result = await _runInterceptor(embedUrl);
        sw.stop();
        if (isCandidateValid(result)) {
          _log('Stream resolved via provider ${i+1} (${sw.elapsedMilliseconds}ms): ${result!.url}', level: LogLevel.success);
          return result;
        }
        _log('Provider ${i+1} failed after ${sw.elapsedMilliseconds}ms', level: LogLevel.warning);
      }
    }

    _log('All providers exhausted for tmdbId=$tmdbId', level: LogLevel.error);
    return null;
  }

  static String _buildUrl({
    required String base,
    required int tmdbId,
    String? imdbId,
    required bool isTV,
    required int season,
    required int episode,
  }) {
    final hasImdb = imdbId != null && imdbId.isNotEmpty;
    if (base.contains('autoembed.co')) {
      if (hasImdb && !isTV) {
        return 'https://autoembed.co/movie/imdb/$imdbId';
      }
      return isTV ? '$base$tmdbId-$season-$episode' : '$base$tmdbId';
    }
    if (base.contains('2embed.cc')) {
      final id = hasImdb ? imdbId : '$tmdbId';
      return isTV ? '$base$id&s=$season&e=$episode' : '$base$id';
    }
    if (base.contains('vidlink.pro')) {
      return isTV ? '$base$tmdbId/$season/$episode' : '$base$tmdbId';
    }
    if (base.contains('?tmdb=')) {
      if (hasImdb) {
        final imdbBase = base.replaceFirst('?tmdb=', '?imdb=');
        return isTV ? '$imdbBase$imdbId&season=$season&episode=$episode' : '$imdbBase$imdbId';
      }
      return isTV ? '$base$tmdbId&season=$season&episode=$episode' : '$base$tmdbId';
    }
    final id = (hasImdb && !base.contains('tmdb')) ? imdbId : '$tmdbId';
    return isTV ? '$base$id/$season-$episode' : '$base$id';
  }


  static Future<ResolvedStream?> _runInterceptor(String embedUrl) async {
    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) { _log('navigatorKey overlay is null'); return null; }
    final sc = StreamController<ResolvedStream?>();
    OverlayEntry? entry;
    Timer? timeoutTimer;
    void finish(ResolvedStream? stream) {
      if (sc.isClosed) return;
      sc.add(stream); sc.close();
      SchedulerBinding.instance.addPostFrameCallback((_) { try { entry?.remove(); entry = null; } catch (_) {} });
    }
    timeoutTimer = Timer(_perProviderTimeout, () { _log('Timeout: $embedUrl'); finish(null); });
    entry = OverlayEntry(builder: (_) => _HiddenWebViewHost(
      url: embedUrl,
      onStreamFound: (stream) { timeoutTimer?.cancel(); finish(stream); },
      onFatalError: (msg) { timeoutTimer?.cancel(); _log('Fatal: $msg'); finish(null); },
    ));
    overlay.insert(entry!);
    _log('WebView overlay inserted: $embedUrl');
    return sc.stream.first.catchError((_) => null as ResolvedStream?);
  }

  static bool isStream(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();

    // 1. Immediately drop any ad, adult, or tracker URL
    for (final bad in _blacklistedTerms) {
      if (lower.contains(bad)) return false;
    }

    if (lower.contains('/embed/')) return false;
    for (final d in _blockedDomains) { if (lower.contains(d)) return false; }
    for (final d in _skipDomains) { if (lower.contains(d)) return false; }
    for (final p in _embedPagePatterns) { if (lower.contains(p)) return false; }

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // 2. Legitimate media container / playlist checks
    final path = uri.path.toLowerCase();
    final isHls = lower.contains('.m3u8') ||
        path.contains('/hls/') ||
        path.contains('/hlsstream') ||
        path.contains('/playlist');

    final isTs = path.endsWith('.ts') || lower.contains('.ts?');
    final isMp4 = path.endsWith('.mp4') && path.length > 10;

    if (!isHls && !isTs && !isMp4) return false;

    // 3. For MP4s, video ads on embed sites are almost always MP4 files.
    // Require MP4 streams to come from verified streaming CDNs.
    if (isMp4) {
      final host = uri.host.toLowerCase();
      final fromValidCdn = _validCdnKeywords.any((k) => host.contains(k));
      if (!fromValidCdn) return false;
    }

    return true;
  }

  static void _log(String msg, {LogLevel level = LogLevel.info}) =>
      DiagnosticService.instance.log('StreamResolver', msg, level: level);
}

class _HiddenWebViewHost extends StatefulWidget {
  final String url;
  final ValueChanged<ResolvedStream> onStreamFound;
  final ValueChanged<String> onFatalError;
  const _HiddenWebViewHost({required this.url, required this.onStreamFound, required this.onFatalError});
  @override
  State<_HiddenWebViewHost> createState() => _HiddenWebViewHostState();
}

class _HiddenWebViewHostState extends State<_HiddenWebViewHost> {
  InAppWebViewController? _ctrl;
  bool _done = false;

  /// Captures cookies for [streamUrl] from the WebView's cookie store,
  /// then fires [onStreamFound].
  Future<void> _found(ResolvedStream stream) async {
    if (_done) return;
    _done = true;
    _log('Stream found: ${stream.url}', level: LogLevel.success);
    // Try to grab cookies so ExoPlayer can replay the stream with the same session.
    String? cookieHeader;
    try {
      final uri = Uri.tryParse(stream.url);
      if (uri != null) {
        final mgr = CookieManager.instance();
        final cookies = await mgr.getCookies(url: WebUri(stream.url));
        if (cookies.isNotEmpty) {
          cookieHeader = cookies.map((c) => '${c.name}=${c.value}').join('; ');
          _log('Cookies captured (${cookies.length}): $cookieHeader');
        }
        // Also check cookies for the embed page host (they're often set there).
        if ((cookieHeader == null || cookieHeader.isEmpty) && _ctrl != null) {
          final embedUri = Uri.tryParse(widget.url);
          if (embedUri != null && embedUri.host != uri.host) {
            final embedCookies = await mgr.getCookies(url: WebUri(widget.url));
            if (embedCookies.isNotEmpty) {
              cookieHeader = embedCookies.map((c) => '${c.name}=${c.value}').join('; ');
              _log('Embed cookies captured (${embedCookies.length}): $cookieHeader');
            }
          }
        }
      }
    } catch (e) {
      _log('Cookie capture failed: $e', level: LogLevel.warning);
    }
    widget.onStreamFound(ResolvedStream(
      url: stream.url,
      origin: stream.origin,
      referer: stream.referer,
      cookies: cookieHeader,
    ));
  }

  void _fatalError(String msg) {
    if (_done) return;
    _done = true;
    _log('Fatal: $msg', level: LogLevel.error);
    widget.onFatalError(msg);
  }

  static const String _bridgeScript = r'''
(function() {
  const _seen = new Set();
  const CDN_HOSTS = [
    'vidsrc.stream','playit.buzz','filemoon','moonplayer',
    'vidplay.online','vidplay.site','vidplay.cc',
    'vipstream','fastcdn','vidmoly','vidhide','voe.sx','streamwish','streamtape',
    'conversionfocusedstudio.site','nextgencloudfabric','rabbitstream','megacloud',
    'dokicloud','kisskh','akwam','faselhd','arabseed','wecima','streamlare',
    'mixdrop','upstream','doodstream','streamcrypt','cloudflarestorage',
    'vidlink','autoembed','multiembed','birchandbloom','stellarconductornexus'
  ];
  const EMBED_HOSTS = [
    'autoembed.co','autoembed.me','vidsrc.to','vidsrc.sh','vidsrc.me','vsembed.ru',
    'histats.com','cloudflareinsights','disable-devtool',
    '.js','.css','.svg','.png','.jpg','.jpeg','.gif','.ico','.woff','.woff2','.ttf',
  ];
  const BLACKLIST = [
    'exoclick','adsterra','popcash','propeller','juicyads','trafficjunky',
    'ero','porn','cam','adult','sex','tube','dating','bet','casino','strip',
    'cams','livejasmin','chaturbate','bongacams','doubleclick','googleads',
    'adnxs','moatads','criteo','outbrain','histats','tagivi','createlouisville',
    'gussiessmutchy','preroll','midroll','vast','vpaid','banner','adserver','popunder','popup',
    'adcontent','syndication'
  ];

  // Block popups and ad scripts from hijacking window
  try {
    window.open = function() { return null; };
    window.alert = function() {};
    window.confirm = function() { return true; };
    window.prompt = function() { return null; };
  } catch(e) {}

  function looksLikeStream(url) {
    try {
      if (!url || !url.startsWith('http')) return false;
      const lower = url.toLowerCase();
      for (const b of BLACKLIST) { if (lower.includes(b)) return false; }
      if (lower.includes('/embed/')) return false;
      for (const h of EMBED_HOSTS) { if (lower.includes(h)) return false; }
      if (lower.includes('.m3u8')) return true;
      if (lower.includes('/hls/') || lower.includes('/hlsstream') || lower.includes('/playlist')) return true;
      try {
        const p = new URL(url).pathname.toLowerCase();
        if (p.endsWith('.ts') || lower.includes('.ts?')) return true;
        if (p.endsWith('.mp4') && p.length > 10) {
          const host = new URL(url).hostname.toLowerCase();
          for (const c of CDN_HOSTS) { if (host.includes(c)) return true; }
          return false;
        }
      } catch(e) {}
      return false;
    } catch(e) { return false; }
  }

  function notifyStream(url) {
    try {
      if (!looksLikeStream(url)) return;
      const u = ('' + url).trim();
      if (_seen.has(u)) return;
      _seen.add(u);
      let origin = '';
      let referer = '';
      try {
        origin = window.location.origin || '';
        referer = window.location.href || '';
      } catch(e) {}
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler)
        window.flutter_inappwebview.callHandler('onStreamCandidate', u, origin, referer);
    } catch(e) {}
  }

  function scanText(text) {
    try {
      if (!text || typeof text !== 'string' || text.length < 8) return;
      const unescaped = text.replace(/\\\//g, '/');
      const lower = unescaped.toLowerCase();
      for (const b of BLACKLIST) { if (lower.includes(b)) return; }
      if (!lower.includes('.m3u8') && !lower.includes('filemoon') &&
          !lower.includes('playit.buzz') && !lower.includes('vidsrc.stream') &&
          !lower.includes('vidplay') && !lower.includes('streamwish') &&
          !lower.includes('.mp4') && !lower.includes('/hls') && !lower.includes('birchandbloom')) return;
      const re = /https?:\/\/[^\s'\\<>{}|\[\]^\r\n]+/g;
      let m;
      while ((m = re.exec(unescaped)) !== null) notifyStream(m[0].replace(/[;,)\}\]']+$/, ''));
    } catch(e) {}
  }

  try {
    const _oo = XMLHttpRequest.prototype.open, _os = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) { this.__url = url; notifyStream(url); return _oo.apply(this, arguments); };
    XMLHttpRequest.prototype.send = function() { this.addEventListener('load', function() { try { scanText(this.responseText); } catch(e) {} }); return _os.apply(this, arguments); };
  } catch(e) {}

  try {
    const _of = window.fetch;
    if (_of) window.fetch = function(input, init) {
      const u = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      notifyStream(u);
      const p = _of.apply(this, arguments);
      p.then(function(r) { try { r.clone().text().then(scanText).catch(function(){}); } catch(e) {} return r; }).catch(function(){});
      return p;
    };
  } catch(e) {}

  function patchSrc(proto) {
    try {
      const d = Object.getOwnPropertyDescriptor(proto, 'src');
      if (d && d.set) Object.defineProperty(proto, 'src', { set: function(v) { if (looksLikeStream(v)) notifyStream(v); return d.set.call(this, v); }, get: d.get, configurable: true });
    } catch(e) {}
  }
  patchSrc(HTMLVideoElement.prototype);
  patchSrc(HTMLSourceElement.prototype);

  try {
    const _osa = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function(name, value) { if (name === 'src' || name === 'data-src') { if (looksLikeStream(value)) notifyStream(value); } return _osa.apply(this, arguments); };
  } catch(e) {}

  // Auto-click play button on player if present
  function tryClickPlay() {
    try {
      const selectors = [
        '#play', '.play', '.play-btn', '#play-button', '.jw-display-icon-container',
        'button[aria-label="Play"]', '.vjs-big-play-button', '#player', '.player-container'
      ];
      for (const sel of selectors) {
        const el = document.querySelector(sel);
        if (el) { el.click(); break; }
      }
    } catch(e) {}
  }
  setInterval(tryClickPlay, 1000);
})();
''';

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: -500, top: -500, width: 400, height: 400,
      child: Material(
        type: MaterialType.transparency,
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialUserScripts: UnmodifiableListView([
            UserScript(source: _bridgeScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: false,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            transparentBackground: true,
            disableContextMenu: true,
            supportZoom: false,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            cacheEnabled: true,
            useShouldInterceptRequest: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
            useShouldOverrideUrlLoading: true,
            userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
          ),
          onCreateWindow: (ctrl, request) async {
            _log('Blocked ad popup window');
            return false;
          },
          onWebViewCreated: (ctrl) {
            _ctrl = ctrl;
            _log('WebView created: ${widget.url}');
            ctrl.addJavaScriptHandler(
              handlerName: 'onStreamCandidate',
              callback: (args) {
                if (args.isNotEmpty && args[0] != null) {
                  final candidate = args[0].toString();
                  final origin = args.length > 1 && args[1] != null && args[1].toString().isNotEmpty
                      ? args[1].toString()
                      : null;
                  final referer = args.length > 2 && args[2] != null && args[2].toString().isNotEmpty
                      ? args[2].toString()
                      : null;
                  _log('JS candidate: $candidate (origin: $origin, ref: $referer)');
                  if (StreamResolverService.isStream(candidate)) {
                    _log('JS Bridge confirmed: $candidate', level: LogLevel.success);
                    unawaited(_found(ResolvedStream(
                      url: candidate,
                      origin: origin,
                      referer: referer,
                    )));
                  } else {
                    _log('JS candidate rejected: $candidate');
                  }
                }
              },
            );
          },
          onLoadStart: (ctrl, url) => _log('loadStart: $url'),
          onLoadStop: (ctrl, url) async {
            _log('loadStop: $url');
            if (defaultTargetPlatform != TargetPlatform.android) {
              try {
                await ctrl.evaluateJavascript(source: _bridgeScript);
              } catch (_) {}
            }
          },
          shouldInterceptRequest: (ctrl, request) async {
            final url = request.url.toString();
            final lower = url.toLowerCase();

            // Block ad networks, trackers, and adult promo endpoints
            for (final d in StreamResolverService._blockedDomains) {
              if (lower.contains(d)) {
                return WebResourceResponse(statusCode: 403, data: null);
              }
            }
            for (final bad in StreamResolverService._blacklistedTerms) {
              if (lower.contains(bad)) {
                return WebResourceResponse(statusCode: 403, data: null);
              }
            }

            if (!_done && StreamResolverService.isStream(url)) {
              final reqHeaders = request.headers;
              final referer = reqHeaders?['Referer'] ?? reqHeaders?['referer'];
              final origin = reqHeaders?['Origin'] ?? reqHeaders?['origin'];
              _log('Network stream intercepted: $url (origin=$origin ref=$referer)', level: LogLevel.success);
              await _found(ResolvedStream(
                url: url,
                origin: origin,
                referer: referer,
              ));
              return WebResourceResponse(statusCode: 200, data: null);
            }
            if (url.contains('.m3u8') || url.contains('.mp4') || url.contains('getSources') || url.contains('api.php')) {
              _log('Inspected: $url');
            }
            return null;
          },
          shouldOverrideUrlLoading: (ctrl, action) async {
            final url = action.request.url.toString();

            // Block any navigation redirect away from the embed provider or known players
            final uri = action.request.url?.uriValue;
            if (uri != null && uri.host.isNotEmpty) {
              final host = uri.host.toLowerCase();
              final isAllowed = StreamResolverService._allowedNavigationHosts.any((h) => host.contains(h));
              if (!isAllowed) {
                _log('Blocked external ad redirect: $url');
                return NavigationActionPolicy.CANCEL;
              }
            }

            if (!_done && StreamResolverService.isStream(url)) {
              final reqHeaders = action.request.headers;
              final referer = reqHeaders?['Referer'] ?? reqHeaders?['referer'];
              final origin = reqHeaders?['Origin'] ?? reqHeaders?['origin'];
              _log('Nav stream: $url', level: LogLevel.success);
              _found(ResolvedStream(
                url: url,
                origin: origin,
                referer: referer,
              ));
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
          onReceivedHttpError: (ctrl, request, response) {
            _log('HTTP ${response.statusCode} on ${request.url}', level: LogLevel.warning);
          },
          onReceivedError: (ctrl, request, error) {
            _log('Network error: ${error.description} on ${request.url}', level: LogLevel.error);
            if (request.isForMainFrame == true) { _fatalError('${error.description} (${error.type})'); }
          },
          onConsoleMessage: (ctrl, msg) {
            final text = msg.message;
            if (text.toLowerCase().contains('error') || text.toLowerCase().contains('fail') || text.toLowerCase().contains('blocked')) {
              _log('Console: $text', level: LogLevel.warning);
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() { _ctrl?.stopLoading(); super.dispose(); }

  static void _log(String msg, {LogLevel level = LogLevel.info}) =>
      DiagnosticService.instance.log('WebView', msg, level: level);
}
