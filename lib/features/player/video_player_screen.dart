import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:subtitle/subtitle.dart' as sub_pkg;
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../../core/models/movie.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/device_volume.dart';
import '../../core/services/library_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/media_delivery_service.dart';
import '../../core/services/platform_media_channel.dart';
import '../../core/services/stream_resolver_service.dart'
    show AudioTrackOption, SubtitleTrack;
import '../../core/services/tmdb_service.dart';
import '../../core/services/trakt_service.dart';
import '../../core/services/video_service.dart';
import '../../core/services/stream_proxy_service.dart';
import '../../core/services/diagnostic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/tv_focus.dart';
import '../settings/diagnostics_screen.dart';
import '../../core/utils/file_player_helper_native.dart'
    if (dart.library.html) '../../core/utils/file_player_helper_web.dart'
    as file_player;
import '../../core/utils/web_fullscreen_stub.dart'
    if (dart.library.js_interop) '../../core/utils/web_fullscreen_web.dart'
    as web_fullscreen;

/// Theming / behaviour knobs for [VideoPlayerScreen]. Everything has a
/// sensible default, so callers can pass a partially-configured instance.
class CinePlayerTheme {
  final Color accent;
  final Color trackColor;
  final Color bufferedColor;
  final Color controlsBackground;
  final Color iconColor;
  final double iconSize;
  final double seekBarHeight;
  final double seekBarThumb;
  final Duration controlsAutoHide;
  final Duration controlsAnimDuration;
  final Curve controlsAnimCurve;
  final Duration skipStep;
  final List<double> playbackSpeeds;
  final bool showSkipButtons;
  final bool showSpeedButton;
  final bool showVolumeButton;
  final bool showFullscreenButton;
  final bool showFitButton;
  final bool showCastButton;
  final bool showSubtitleButton;
  final bool showRotationLockButton;
  final bool showMoreButton;
  final bool enableDoubleTapSkip;
  final bool enableLongPressBoost;
  final double longPressBoostSpeed;
  final bool autoPlay;
  final bool loop;

  /// Default playback speed applied on first play. Mirrors [SettingsService.playbackSpeed].
  final double defaultSpeed;

  /// Whether subtitles start enabled. Mirrors [SettingsService.subtitlesEnabled].
  final bool subtitlesOn;

  const CinePlayerTheme({
    this.accent = AppColors.secondary,
    this.trackColor = const Color(0x55FFFFFF),
    this.bufferedColor = const Color(0x88FFFFFF),
    this.controlsBackground = const Color(0xB3000000),
    this.iconColor = Colors.white,
    this.iconSize = 26,
    this.seekBarHeight = 4,
    this.seekBarThumb = 14,
    this.controlsAutoHide = const Duration(seconds: 3),
    this.controlsAnimDuration = const Duration(milliseconds: 260),
    this.controlsAnimCurve = Curves.easeOutCubic,
    this.skipStep = const Duration(seconds: 10),
    this.playbackSpeeds = const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
    this.showSkipButtons = true,
    this.showSpeedButton = true,
    this.showVolumeButton = true,
    this.showFullscreenButton = true,
    this.showFitButton = true,
    this.showCastButton = true,
    this.showSubtitleButton = true,
    this.showRotationLockButton = true,
    this.showMoreButton = true,
    this.enableDoubleTapSkip = true,
    this.enableLongPressBoost = true,
    this.longPressBoostSpeed = 2.0,
    this.autoPlay = true,
    this.loop = false,
    this.defaultSpeed = 1.0,
    this.subtitlesOn = false,
  });

  static const CinePlayerTheme defaults = CinePlayerTheme();
}

/// Fully custom in-app video player. Plays the bundled demo asset by default
/// so every card in the catalog has something to show; pass [videoUrl] or
/// [assetPath] to override.
class VideoPlayerScreen extends StatefulWidget {
  final Movie movie;
  final String? videoUrl;
  final String? assetPath;
  final bool isTrailer;
  final CinePlayerTheme theme;
  final Map<String, String>? headers;
  final String? cdn;
  final int? season;
  final int? episode;
  final List<SubtitleTrack> subtitles;
  final List<AudioTrackOption> audioTracks;

  /// Master playlist body already fetched during resolution; the local proxy
  /// serves it for the first manifest request to shave a round trip.
  final String? masterPlaylist;

  /// Offline playlist playback (downloads): prev/next stay inside the caller's
  /// list and never fall back to resolving a network stream.
  final bool downloadPlayback;
  final VoidCallback? onPlayNext;
  final VoidCallback? onPlayPrevious;

  const VideoPlayerScreen({
    super.key,
    required this.movie,
    this.videoUrl,
    this.assetPath,
    this.isTrailer = false,
    this.theme = CinePlayerTheme.defaults,
    this.headers,
    this.cdn,
    this.season,
    this.episode,
    this.subtitles = const [],
    this.audioTracks = const [],
    this.masterPlaylist,
    this.downloadPlayback = false,
    this.onPlayNext,
    this.onPlayPrevious,
  });

  /// Convenience constructor for playing a raw HTTP/HTTPS URL (e.g. a licensed
  /// stream resolved by [MediaDeliveryService]) without a full [Movie] object.
  /// Creates a minimal stub Movie unless [movie] is supplied.
  factory VideoPlayerScreen.fromUrl({
    required String url,
    required String title,
    Movie? movie,
    CinePlayerTheme theme = CinePlayerTheme.defaults,
    Map<String, String>? headers,
    String? cdn,
    int? season,
    int? episode,
    List<AudioTrackOption> audioTracks = const [],
    String? masterPlaylist,
    bool downloadPlayback = false,
    VoidCallback? onPlayNext,
    VoidCallback? onPlayPrevious,
  }) {
    final target = movie ??
        Movie(
          id: '__standalone__',
          tmdbId: 0,
          title: title,
          description: '',
          imageUrl: '',
          backdropUrl: '',
          rating: 0,
          duration: '',
          genres: [],
          badges: [],
          year: 0,
          ageRating: '',
        );
    return VideoPlayerScreen(
      movie: target,
      videoUrl: url,
      theme: theme,
      headers: headers,
      cdn: cdn,
      season: season,
      episode: episode,
      audioTracks: audioTracks,
      masterPlaylist: masterPlaylist,
      downloadPlayback: downloadPlayback,
      onPlayNext: onPlayNext,
      onPlayPrevious: onPlayPrevious,
    );
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;

  MediaDeliveryService? _delivery;
  bool _pipEnabled = false;
  bool _pipSupported = false;
  bool _inPip = false;
  bool? _lastReportedPlaying;

  String? get _resolvedCdn {
    if (_activeCdn != null && _activeCdn!.isNotEmpty) return _activeCdn;
    if (_activeUrl != null && _activeUrl!.isNotEmpty) {
      final uri = Uri.tryParse(_activeUrl!);
      if (uri != null && uri.host.isNotEmpty) {
        if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
          final orig =
              _activeHeaders?['X-Original-Host'] ?? _activeHeaders?['Referer'];
          if (orig != null) {
            final origUri = Uri.tryParse(orig);
            if (origUri != null && origUri.host.isNotEmpty) return origUri.host;
          }
        } else {
          return uri.host;
        }
      }
    }
    if (_activeAsset != null && _activeAsset!.isNotEmpty) {
      return 'Bundled Asset';
    }
    return null;
  }

  bool _controlsVisible = true;
  final GlobalKey _controlsKey = GlobalKey();
  Timer? _hideTimer;
  bool _isFullscreen = false;
  bool _isScrubbing = false;
  double _dragPositionSeconds = 0;
  double _volume = 1.0;
  bool _muted = false;
  double _speed = 1.0;

  /// While true the player follows the system volume: the gesture writes the
  /// device level and the stream itself stays at full scale.
  bool _deviceVolumeMode = false;

  /// Level the device had when the player opened, restored on exit.
  double? _volumeOnEnter;
  StreamSubscription<double>? _deviceVolumeSubscription;

  PlayerFitMode _fitMode = PlayerFitMode.contain;
  final double _customZoomScale = 1.0;
  bool _rotationLocked = false;
  bool _subtitlesOn = false;
  String _currentSubtitleText = '';
  sub_pkg.SubtitleController? _subtitleController;
  SubtitleTrack? _selectedSubtitleTrack;
  bool _boostActive = false;
  double? _lastNonBoostSpeed;
  bool _tvLayout = false;

  int _rippleId = 0;
  _RippleSide? _rippleSide;

  Timer? _scrobbleTimer;
  bool _traktStopSent = false;
  Timer? _tapDebounceTimer;
  static const int _kDebounceMs = 220;

  // ── Skip Intro / Auto-next state ────────────────────────────────────────
  bool _showSkipIntro = false;
  bool _skipIntroDismissed = false;
  bool _autoIntroSkipped = false;
  bool _showNextEpisode = false;
  int _nextEpisodeCountdown = 5;
  Timer? _nextEpisodeTimer;
  bool _preloadedNextEpisode = false;
  PlayableSource? _preloadedNextSource;
  int? _seasonEpisodeMax;
  Future<int?>? _seasonEpisodeMaxFuture;

  // ── In-place source switching ───────────────────────────────────────────
  // The source and episode currently loaded. Starting from the widget values,
  // they move when next/previous or a server change swaps the media, so the
  // route (and its landscape/fullscreen state) is never rebuilt.
  String? _activeUrl;
  String? _activeAsset;
  Map<String, String>? _activeHeaders;
  String? _activeCdn;
  List<SubtitleTrack> _activeSubtitles = const [];
  int? _seasonOverride;
  int? _episodeOverride;
  String? _episodeTitleOverride;
  bool _swappingSource = false;

  int _currentProviderIndex = 0;
  final List<String> _triedStreamUrls = [];
  bool _isSwitchingStream = false;

  // ── Gesture Controls (Brightness & Volume) ──────────────────────────────
  double _brightness = 1.0;
  bool _showGestureHud = false;
  Timer? _gestureHudTimer;
  _GestureKind _activeGestureKind = _GestureKind.brightness;
  double _gestureValue = 1.0;

  // ── Quality Selection & Network Adaptation ──────────────────────────────
  static const List<VideoQuality> _qualityLadder = [
    VideoQuality.sd480,
    VideoQuality.hd720,
    VideoQuality.fullHd1080,
    VideoQuality.uhd4k,
  ];

  VideoQuality _quality = VideoQuality.auto; // user preference
  VideoQuality _linkQuality = VideoQuality.fullHd1080; // ceiling from link type
  VideoQuality _servedQuality = VideoQuality.fullHd1080; // variant served now
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _qualitySampleTimer;
  DateTime? _lastQualitySampleAt;
  DateTime? _bufferingSince;
  DateTime _qualityGraceUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastQualitySwitch = DateTime.fromMillisecondsSinceEpoch(0);
  int _slowSamples = 0;
  int _fastSamples = 0;

  // ── Audio track selection ────────────────────────────────────────────────
  List<AudioTrackOption> _audioTracks = const [];

  /// Language code of the chosen audio rendition; '' = automatic.
  String _audioLanguage = '';

  // ── Playback intent & stall recovery ─────────────────────────────────────
  /// What the user asked for, independent of ExoPlayer's buffering state.
  bool _wantsPlayback = false;
  Timer? _stallWatchdogTimer;
  Duration _lastStallPosition = Duration.zero;
  DateTime _lastStallProgressAt = DateTime.now();
  int _stallNudges = 0;
  DateTime _lastStallReload = DateTime.fromMillisecondsSinceEpoch(0);

  /// Master playlist handed over by the resolver, consumed by the first proxy
  /// start only — reloads fetch fresh so a rotated playlist is picked up.
  String? _pendingManifest;

  VideoQuality get _preferredQuality =>
      _quality == VideoQuality.auto ? _linkQuality : _quality;

  /// Quality adaptation only applies to network streams — local files and
  /// bundled assets can't be re-fetched at a lower bitrate.
  bool get _isNetworkPlayback {
    final url = _activeUrl;
    return url != null &&
        (url.startsWith('http://') || url.startsWith('https://'));
  }

  static int _rungOf(VideoQuality q) {
    switch (q) {
      case VideoQuality.sd480:
        return 0;
      case VideoQuality.hd720:
        return 1;
      case VideoQuality.uhd4k:
        return 3;
      case VideoQuality.auto:
      case VideoQuality.fullHd1080:
      case VideoQuality.highest:
        return 2;
    }
  }

  static VideoQuality _qualityAtRung(int rung) =>
      _qualityLadder[rung.clamp(0, _qualityLadder.length - 1)];

  /// Rough download rate (bytes/sec) a variant needs to play without stalling.
  static int _bitrateOf(VideoQuality q) {
    switch (_rungOf(q)) {
      case 0:
        return 150000;
      case 1:
        return 350000;
      case 3:
        return 2000000;
      default:
        return 800000;
    }
  }

  /// Switches the variant the proxy serves, then reloads playback at the
  /// current position so the change takes effect without losing the place.
  void _setServedQuality(VideoQuality next, {String? note}) {
    if (_rungOf(next) == _rungOf(_servedQuality)) return;
    setState(() => _servedQuality = next);
    StreamProxyService.instance.setQualityTarget(next);
    _slowSamples = 0;
    _fastSamples = 0;
    _lastQualitySwitch = DateTime.now();
    _qualityGraceUntil = DateTime.now().add(const Duration(seconds: 8));
    DiagnosticService.instance.info(
      'VideoPlayer',
      'Quality switched to ${next.name}${note != null ? ' ($note)' : ''}',
    );
    // Deferred: this can be reached from the controller's own listener.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reloadAtCurrentPosition();
    });
    if (note != null) {
      _showQualityNote('$note — ${_qualityShortName(next)}');
    }
  }

  void _showQualityNote(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHigh,
      ),
    );
  }

  void _reloadAtCurrentPosition() {
    final c = _controller;
    if (!_isNetworkPlayback) return;
    // Not ready yet: the proxy already has the new target, and the manifest
    // fetch during startup will honor it — no need to force a restart.
    if (c == null || !c.value.isInitialized) return;
    final currentPos = c.value.position;
    final wasPlaying = _wantsPlayback;
    c.removeListener(_onTick);
    c.pause();
    c.dispose();
    _controller = null;
    _lastStallPosition = currentPos;
    _lastStallProgressAt = DateTime.now();
    _initController();
    _restoreAfterReload(currentPos, wasPlaying);
  }

  /// Reapplies position/play state once the replacement controller for a
  /// quality switch has finished initializing (avoids a fixed-delay race).
  Future<void> _restoreAfterReload(Duration position, bool wasPlaying) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final c = _controller;
      if (c != null && c.value.isInitialized) {
        try {
          await c.seekTo(position);
          if (wasPlaying) await c.play();
        } catch (_) {}
        return;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (!mounted) return;
    VideoQuality linkQuality;
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      linkQuality = VideoQuality.fullHd1080;
    } else if (results.contains(ConnectivityResult.mobile)) {
      linkQuality = VideoQuality.hd720;
    } else {
      linkQuality = VideoQuality.sd480;
    }
    if (linkQuality == _linkQuality) return;
    setState(() => _linkQuality = linkQuality);
    _slowSamples = 0;
    _fastSamples = 0;
    // 'none' is usually a momentary drop-out: don't yank quality mid-playback,
    // the stall detector will react if playback actually breaks.
    if (_quality == VideoQuality.auto &&
        _isNetworkPlayback &&
        linkQuality != VideoQuality.sd480) {
      _setServedQuality(linkQuality);
    }
  }

  void _startQualitySampling() {
    _qualitySampleTimer?.cancel();
    if (!_isNetworkPlayback) return;
    StreamProxyService.instance.takeRelayedBytes();
    _lastQualitySampleAt = null;
    _qualitySampleTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _sampleThroughput());
  }

  /// Samples real media throughput and walks the quality ladder down when the
  /// link can't keep up, back up when it recovers. Downgrades are also driven
  /// by rebuffering stalls (see [_trackPlaybackHealth]) so a link that jitters
  /// around the bitrate still settles on a playable variant.
  Future<void> _sampleThroughput() async {
    final relayed = StreamProxyService.instance.takeRelayedBytes();
    final now = DateTime.now();
    final since = _lastQualitySampleAt;
    _lastQualitySampleAt = now;
    final elapsedSec =
        since == null ? 3.0 : now.difference(since).inMilliseconds / 1000.0;
    if (!mounted) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    if (_isScrubbing || now.isBefore(_qualityGraceUntil) || elapsedSec < 1) {
      return;
    }

    int bytesPerSec;
    if (StreamProxyService.instance.isRunning) {
      if (relayed <= 0) return; // buffered ahead; no fresh evidence
      bytesPerSec = (relayed / elapsedSec).round();
    } else {
      bytesPerSec = await PlatformMediaChannel.getNetworkSpeed();
      if (!mounted || bytesPerSec <= 0) return;
    }

    final rung = _rungOf(_servedQuality);
    final bitrate = _bitrateOf(_servedQuality);
    if (bytesPerSec < bitrate * 0.6) {
      _fastSamples = 0;
      _slowSamples++;
      if (_slowSamples >= 3 && rung > 0) {
        _setServedQuality(_qualityAtRung(rung - 1), note: 'Low network');
      }
    } else if (bytesPerSec >= bitrate * 1.8) {
      _slowSamples = 0;
      _fastSamples++;
      if (_fastSamples >= 3 && rung < _rungOf(_preferredQuality)) {
        _setServedQuality(_qualityAtRung(rung + 1));
      }
    } else {
      _slowSamples = 0;
      _fastSamples = 0;
    }
  }

  void _trackPlaybackHealth(VideoPlayerValue value) {
    final now = DateTime.now();
    // isPlaying is false while buffering (playWhenReady && state==READY), so
    // the user's intent — not value.isPlaying — decides whether a stall counts.
    if (!_isNetworkPlayback ||
        !_wantsPlayback ||
        !value.isBuffering ||
        _isScrubbing ||
        now.isBefore(_qualityGraceUntil)) {
      _bufferingSince = null;
      return;
    }
    _bufferingSince ??= now;
    if (now.difference(_bufferingSince!) < const Duration(milliseconds: 2500)) {
      return;
    }
    _bufferingSince = null;
    if (now.difference(_lastQualitySwitch) < const Duration(seconds: 20)) {
      return;
    }
    final rung = _rungOf(_servedQuality);
    if (rung == 0) return;
    _setServedQuality(_qualityAtRung(rung - 1), note: 'Slow network');
  }

  // ── Stall watchdog ───────────────────────────────────────────────────────

  /// Some streams keep ExoPlayer in a permanent rebuffer where a manual
  /// pause/play is the only way to un-stick it. Watch the position while the
  /// user wants playback and nudge (then reload) when it stops advancing.
  void _startStallWatchdog() {
    _stallWatchdogTimer?.cancel();
    if (!_isNetworkPlayback) return;
    _lastStallPosition = Duration.zero;
    _lastStallProgressAt = DateTime.now();
    _stallNudges = 0;
    _stallWatchdogTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _checkForStall());
  }

  void _checkForStall() {
    if (!mounted) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      _lastStallProgressAt = DateTime.now();
      return;
    }
    final v = c.value;
    final now = DateTime.now();
    if (!_wantsPlayback || v.isPlaying || _isScrubbing || v.hasError) {
      _lastStallPosition = v.position;
      _lastStallProgressAt = now;
      return;
    }
    if (v.position != _lastStallPosition) {
      _lastStallPosition = v.position;
      _lastStallProgressAt = now;
      return;
    }
    final stalledFor = now.difference(_lastStallProgressAt);
    if (stalledFor < const Duration(seconds: 6)) return;
    if (now.difference(_lastStallReload) < const Duration(seconds: 20)) return;

    _lastStallProgressAt = now;
    _stallNudges++;
    if (_stallNudges.isOdd) {
      DiagnosticService.instance.warning(
        'VideoPlayer',
        'Playback stalled ${stalledFor.inSeconds}s while buffering — nudging pause/play',
      );
      c.pause();
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted || _controller != c || !_wantsPlayback) return;
        c.play();
      });
      return;
    }

    _stallNudges = 0;
    _lastStallReload = now;
    DiagnosticService.instance.warning(
      'VideoPlayer',
      'Playback stuck ${stalledFor.inSeconds}s — reloading stream at current position',
    );
    _reloadAtCurrentPosition();
  }

  /// One-shot kick after startup: if the stream initialized but never started
  /// on its own, a pause/play cycle reliably gets ExoPlayer going.
  void _schedulePlaybackKick(VideoPlayerController c) {
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!mounted || _controller != c || !_wantsPlayback) return;
      final v = c.value;
      if (!v.isInitialized || v.hasError || v.isPlaying) return;
      DiagnosticService.instance.info(
        'VideoPlayer',
        'Playback did not auto-start — sending pause/play kick',
      );
      try {
        await c.pause();
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted || _controller != c || !_wantsPlayback) return;
        await c.play();
      } catch (_) {}
    });
  }

  /// Adopts the system volume as the player's starting level and keeps the
  /// two in sync. Falls back silently to player-only volume where the
  /// platform exposes no system volume (web).
  Future<void> _bindDeviceVolume() async {
    if (!DeviceVolume.supported) return;
    DeviceVolume.configure();
    final entry = await DeviceVolume.read();
    if (!mounted) return;
    if (entry == null) return;
    _volumeOnEnter = entry;
    _deviceVolumeMode = true;
    _deviceVolumeSubscription = DeviceVolume.listen(_onDeviceVolumeChanged);
    setState(() {
      _volume = entry;
      _muted = entry == 0;
      _gestureValue = entry;
    });
    _applyControllerVolume();
  }

  void _onDeviceVolumeChanged(double level) {
    if (!mounted) return;
    setState(() {
      _volume = level.clamp(0.0, 1.0);
      _muted = _volume == 0;
      if (_showGestureHud && _activeGestureKind == _GestureKind.volume) {
        _gestureValue = _volume;
      }
    });
  }

  /// Pushes [_volume]/[_muted] to the stream. In device mode the stream stays
  /// at full scale — the system mixer owns the loudness — so mute is the only
  /// thing that still touches the controller.
  void _applyControllerVolume([VideoPlayerController? target]) {
    final c = target ?? _controller;
    if (c == null) return;
    if (_deviceVolumeMode) {
      c.setVolume(_muted ? 0 : 1.0);
    } else {
      c.setVolume(_muted ? 0 : _volume);
    }
  }

  Future<void> _applyBrightness(double value) async {
    final clamped = value.clamp(0.05, 1.0);
    setState(() {
      _brightness = clamped;
      _gestureValue = clamped;
    });
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(clamped);
      if (mounted) {
        context.read<SettingsService>().setPlayerBrightness(clamped);
      }
    } catch (_) {}
  }

  void _onVerticalDragStart(
    DragStartDetails details,
    double screenWidth,
    double screenHeight,
  ) {
    _gestureHudTimer?.cancel();
    final isLeft = details.globalPosition.dx < screenWidth / 2;
    setState(() {
      _activeGestureKind =
          isLeft ? _GestureKind.brightness : _GestureKind.volume;
      _gestureValue = isLeft ? _brightness : _volume;
      _showGestureHud = true;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenHeight) {
    final sensitivity = screenHeight * 0.7;
    final delta = -details.primaryDelta! / sensitivity;

    if (_activeGestureKind == _GestureKind.brightness) {
      _applyBrightness(_brightness + delta);
    } else {
      final newVol = (_volume + delta).clamp(0.0, 1.0);
      _setVolume(newVol);
      setState(() => _gestureValue = newVol);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _gestureHudTimer?.cancel();
    _gestureHudTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showGestureHud = false);
      }
    });
  }

  String get _qualityPillLabel {
    if (_quality == VideoQuality.auto) {
      return 'Auto (${_qualityShortName(_servedQuality)})';
    }
    if (_rungOf(_servedQuality) < _rungOf(_quality)) {
      return '${_qualityShortName(_quality)} → ${_qualityShortName(_servedQuality)}';
    }
    return _qualityShortName(_quality);
  }

  static String _qualityShortName(VideoQuality q) {
    switch (q) {
      case VideoQuality.uhd4k:
        return '4K';
      case VideoQuality.fullHd1080:
      case VideoQuality.highest:
        return '1080p';
      case VideoQuality.hd720:
        return '720p';
      case VideoQuality.sd480:
        return '480p';
      case VideoQuality.auto:
        return 'Auto';
    }
  }

  // ── Audio tracks ─────────────────────────────────────────────────────────

  static String _audioKey(AudioTrackOption track) =>
      (track.language.isNotEmpty ? track.language : track.label).toLowerCase();

  /// Picks the rendition to start with: saved preference → English → the
  /// manifest default → the first track advertised.
  String _initialAudioLanguage(String saved) {
    if (_audioTracks.isEmpty) return '';
    final savedKey = saved.toLowerCase();
    if (savedKey.isNotEmpty) {
      for (final t in _audioTracks) {
        if (_audioKey(t) == savedKey) return _audioKey(t);
      }
    }
    for (final t in _audioTracks) {
      final label = t.label.toLowerCase();
      if ((t.language.isNotEmpty && (t.matches('en') || t.matches('eng'))) ||
          label.contains('english')) {
        return _audioKey(t);
      }
    }
    for (final t in _audioTracks) {
      if (t.isDefault) return _audioKey(t);
    }
    return _audioKey(_audioTracks.first);
  }

  AudioTrackOption? get _selectedAudioTrack {
    if (_audioTracks.isEmpty || _audioLanguage.isEmpty) return null;
    final key = _audioLanguage.toLowerCase();
    for (final t in _audioTracks) {
      if (_audioKey(t) == key) return t;
    }
    return null;
  }

  String? get _proxyAudioLanguage =>
      _audioLanguage.isEmpty ? null : _audioLanguage;

  String get _audioPillLabel {
    final track = _selectedAudioTrack;
    if (track == null) return 'Audio';
    final label = track.label.isNotEmpty ? track.label : track.language;
    if (label.length <= 12) return label;
    return '${label.substring(0, 11)}…';
  }

  bool get _canPickAudio => _isNetworkPlayback && _audioTracks.length > 1;

  /// Restarts the stream with the proxy pinned to [track]'s rendition, then
  /// resumes at the same position (video_player has no track-selection API).
  void _selectAudioTrack(AudioTrackOption track) {
    final key = _audioKey(track);
    if (key == _audioLanguage) return;
    setState(() => _audioLanguage = key);
    context.read<SettingsService>().setAudioLanguage(key);
    StreamProxyService.instance.setAudioTarget(_proxyAudioLanguage);
    _qualityGraceUntil = DateTime.now().add(const Duration(seconds: 8));
    DiagnosticService.instance.info(
      'VideoPlayer',
      'Audio track switched to ${track.label.isEmpty ? key : track.label} ($key)',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reloadAtCurrentPosition();
    });
  }

  Future<void> _pickAudio() async {
    if (_audioTracks.isEmpty) return;
    _hideTimer?.cancel();
    final selected = await showModalBottomSheet<AudioTrackOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.graphic_eq_rounded,
                          color: AppColors.secondary, size: 22),
                      const SizedBox(width: 10),
                      Text('Audio Track',
                          style: AppTheme.cardTitle
                              .copyWith(color: AppColors.white)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ..._audioTracks.map((track) {
                  final isSelected = _audioKey(track) == _audioLanguage;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected ? _theme.accent : Colors.white54,
                      size: 20,
                    ),
                    title: Text(
                      track.label.isNotEmpty ? track.label : track.language,
                      style: TextStyle(
                        color: isSelected ? _theme.accent : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    subtitle: track.language.isEmpty
                        ? null
                        : Text(
                            track.language.toUpperCase(),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11),
                          ),
                    onTap: () => Navigator.pop(ctx, track),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );

    if (selected != null) _selectAudioTrack(selected);
    _showControls();
  }

  double get _subtitleFontSize {
    try {
      final size = context.read<SettingsService>().subtitleSize;
      switch (size) {
        case SubtitleSize.small:
          return 13.0;
        case SubtitleSize.medium:
          return 16.0;
        case SubtitleSize.large:
          return 20.0;
      }
    } catch (_) {
      return 15.0;
    }
  }

  Future<void> _initPip() async {
    if (!_pipEnabled) return;
    final supported = await _delivery?.isPipSupported() ?? false;
    if (!supported || !mounted) return;
    _pipSupported = true;
    PlatformMediaChannel.listen(
      onAction: _onPipAction,
      onModeChanged: _onPipModeChanged,
    );
    await _delivery?.setAutoPip(enable: true);
    _syncPipState();
  }

  Future<void> _onPipAction(String action) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    switch (action) {
      case 'play':
        _wantsPlayback = true;
        await c.play();
      case 'pause':
        _wantsPlayback = false;
        await c.pause();
      case 'rewind':
        await c.seekTo(_clampSeek(c.value.position - _theme.skipStep));
      case 'forward':
        await c.seekTo(_clampSeek(c.value.position + _theme.skipStep));
    }
    _syncPipState();
  }

  Duration _clampSeek(Duration target) {
    final dur = _controller?.value.duration ?? Duration.zero;
    if (target < Duration.zero) return Duration.zero;
    if (dur > Duration.zero && target > dur) return dur;
    return target;
  }

  void _onPipModeChanged(bool inPip) {
    if (!mounted || _inPip == inPip) return;
    setState(() {
      _inPip = inPip;
      _hideTimer?.cancel();
      _controlsVisible = !inPip;
    });
  }

  void _syncPipState() {
    if (!_pipEnabled || !_pipSupported) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final playing = c.value.isPlaying;
    if (_lastReportedPlaying == playing) return;
    _lastReportedPlaying = playing;
    _delivery?.updatePipPlayState(isPlaying: playing);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pauseIfHidden();
  }

  /// Stops audio when the app leaves the screen without a PiP window. When PiP
  /// is available the system has a moment to move the activity into the
  /// floating window first; if it didn't, playback must not continue unseen.
  Future<void> _pauseIfHidden() async {
    final c = _controller;
    if (c == null || (!c.value.isPlaying && !_wantsPlayback)) return;
    if (!_pipSupported) {
      _wantsPlayback = false;
      await c.pause();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final inPip = await PlatformMediaChannel.isInPip();
    if (!inPip && mounted) {
      _wantsPlayback = false;
      await _controller?.pause();
    }
  }

  void _exitPlayer() {
    _controlsVisible = false;
    _wantsPlayback = false;
    _controller?.pause();
    _delivery?.setAutoPip(enable: false);
    if (!_tvLayout) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  Future<void> _switchStream() async {
    if (_isSwitchingStream || _swappingSource) return;
    final curUrl = _activeUrl;
    if (curUrl != null &&
        curUrl.isNotEmpty &&
        !_triedStreamUrls.contains(curUrl)) {
      _triedStreamUrls.add(curUrl);
    }
    setState(() => _isSwitchingStream = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final delivery = context.read<MediaDeliveryService>();
      _currentProviderIndex++;
      final nextSource = await delivery.resolveStream(
        widget.movie,
        season: _seasonNumber,
        episode: _episodeNumber,
        excludeUrls: _triedStreamUrls,
        startProviderIndex: _currentProviderIndex,
      );

      if (!mounted) return;
      if (nextSource.url == null || nextSource.url == curUrl) {
        throw Exception('No alternative stream found');
      }

      await _swapToSource(
        nextSource,
        season: _seasonNumber ?? 1,
        episode: _episodeNumber ?? 1,
        providerIndex: _currentProviderIndex,
        resetStreamHistory: false,
      );
      if (!mounted) return;
      setState(() => _isSwitchingStream = false);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Switched to ${nextSource.cdn ?? "Next Server"}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSwitchingStream = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not find an alternative stream: $e',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }
  }

  CinePlayerTheme get _theme => widget.theme;

  String _sessionId = '';

  @override
  void initState() {
    super.initState();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    final settingsService = context.read<SettingsService>();
    _delivery = context.read<MediaDeliveryService>();
    _tvLayout = settingsService.useTvLayout;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addObserver(this);
      _pipEnabled = settingsService.enablePip;
      _initPip();
    }
    _speed = _theme.defaultSpeed.clamp(0.25, 4.0);
    _subtitlesOn = _theme.subtitlesOn;
    _quality = settingsService.streamQuality;
    _servedQuality = _quality == VideoQuality.auto ? _linkQuality : _quality;
    StreamProxyService.instance.setQualityTarget(_servedQuality);
    _audioTracks = widget.audioTracks;
    _audioLanguage = _initialAudioLanguage(settingsService.audioLanguage);
    StreamProxyService.instance.setAudioTarget(_proxyAudioLanguage);
    _wantsPlayback = _theme.autoPlay;
    _activeUrl = widget.videoUrl;
    _activeAsset = widget.assetPath;
    _activeHeaders = widget.headers;
    _activeCdn = widget.cdn;
    _activeSubtitles = widget.subtitles;
    _pendingManifest = widget.masterPlaylist;

    // Start in landscape orientation & fullscreen mode
    _isFullscreen = true;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Initialize brightness with saved device preference (defaults to 40% = 0.40)
    final savedBrightness = settingsService.playerBrightness;
    _brightness = savedBrightness;
    _gestureValue = savedBrightness;
    try {
      ScreenBrightness.instance.setApplicationScreenBrightness(savedBrightness);
    } catch (_) {}

    // Watch connectivity to adapt stream quality dynamically in Auto mode
    try {
      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
      Connectivity().checkConnectivity().then(_onConnectivityChanged);
    } catch (_) {}

    _setupInitialSubtitles();

    _bindDeviceVolume();
    _initController();
    _startQualitySampling();
    _startStallWatchdog();

    if (_isSeriesPlayback && !widget.downloadPlayback) {
      unawaited(_loadSeasonEpisodeMax());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only log watch history for real movie objects
      if (widget.movie.id != '__standalone__') {
        context.read<LibraryService>().addToHistory(widget.movie);
      }
    });
  }

  int _initRetryCount = 0;

  static Map<String, String> _buildHeadersForUrl(
    String url, [
    Map<String, String>? customHeaders,
  ]) {
    final uri = Uri.tryParse(url);
    if (uri == null) return const {};
    final host = uri.host.toLowerCase();
    if (customHeaders != null && customHeaders.isNotEmpty) {
      return customHeaders;
    }
    String referer = '${uri.scheme}://${uri.host}/';
    String origin = '${uri.scheme}://${uri.host}';
    if (host.contains('conversionfocusedstudio.site') ||
        host.contains('nextgencloudfabric')) {
      referer = 'https://nextgencloudfabric.com/';
      origin = 'https://nextgencloudfabric.com';
    }
    return {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      'Referer': referer,
      'Origin': origin,
      'Accept': '*/*',
    };
  }

  void _initController() {
    setState(() => _error = null);

    final String? networkUrl = _activeUrl;
    final String? assetPath = _activeAsset;

    DiagnosticService.instance.info(
      'VideoPlayer',
      'Initializing player (attempt ${_initRetryCount + 1}). networkUrl=$networkUrl assetPath=$assetPath',
    );

    // ── Local offline file playback check ─────────────────────────────────
    VideoPlayerController? fileController;
    if (networkUrl != null &&
        !networkUrl.startsWith('http://') &&
        !networkUrl.startsWith('https://')) {
      fileController = file_player.createLocalFilePlayerController(networkUrl);
    }
    if (fileController == null && assetPath != null) {
      fileController = file_player.createLocalFilePlayerController(assetPath);
    }

    if (fileController != null) {
      DiagnosticService.instance.info(
        'VideoPlayer',
        'Playing local offline media: ${networkUrl ?? assetPath}',
      );
      _controller = fileController;
      _attachController(fileController, null);
      return;
    }

    final VideoPlayerController controller;
    if (networkUrl != null) {
      final lower = networkUrl.toLowerCase();
      final isHls = lower.contains('.m3u8') || lower.contains('/hls');
      final headers = _buildHeadersForUrl(networkUrl, _activeHeaders);

      DiagnosticService.instance.info(
        'VideoPlayer',
        'Stream headers applied: Referer=${headers['Referer']} Origin=${headers['Origin']}',
      );

      // ── Local proxy ──────────────────────────────────────────────────────
      // Route the stream through a local HTTP proxy so that ExoPlayer sends
      // the required headers (Referer, Origin, Cookie, User-Agent) on EVERY
      // request — including HLS segment and key-file fetches, not just the
      // manifest. If proxy fails or on retry, falls back to direct playback.
      if (headers.isNotEmpty && _initRetryCount == 0) {
        final cachedManifest = _pendingManifest;
        _pendingManifest = null;
        StreamProxyService.instance
            .start(
          networkUrl,
          headers,
          sessionId: _sessionId,
          initialManifest: cachedManifest,
        )
            .then((proxyUrl) {
          if (!mounted) return;
          DiagnosticService.instance.info(
            'VideoPlayer',
            'Proxy started → $proxyUrl',
          );
          final uri = Uri.parse(proxyUrl);
          final proxyController = VideoPlayerController.networkUrl(
            uri,
            formatHint: isHls ? VideoFormat.hls : null,
          );
          _controller = proxyController;
          _attachController(proxyController, networkUrl);
        }).catchError((Object e) {
          DiagnosticService.instance.warning(
            'VideoPlayer',
            'Proxy start failed ($e) — falling back to direct playback',
          );
          if (!mounted) return;
          final uri =
              Uri.tryParse(networkUrl) ?? Uri.parse(Uri.encodeFull(networkUrl));
          final fallback = VideoPlayerController.networkUrl(
            uri,
            formatHint: isHls ? VideoFormat.hls : null,
            httpHeaders: headers,
          );
          _controller = fallback;
          _attachController(fallback, networkUrl);
        });
        return; // async path — _attachController will handle the rest
      }

      // Direct playback with headers (attempt 2+ or when no headers).
      final uri =
          Uri.tryParse(networkUrl) ?? Uri.parse(Uri.encodeFull(networkUrl));
      controller = VideoPlayerController.networkUrl(
        uri,
        formatHint: isHls ? VideoFormat.hls : null,
        httpHeaders: headers,
      );
    } else {
      controller = VideoPlayerController.asset(
        _activeAsset ?? VideoService.localDemoAsset,
      );
    }

    _controller = controller;
    _attachController(controller, networkUrl);
  }

  void _attachController(VideoPlayerController controller, String? networkUrl) {
    // Don't treat the initial buffer as a stall.
    final grace = DateTime.now().add(const Duration(seconds: 5));
    if (grace.isAfter(_qualityGraceUntil)) _qualityGraceUntil = grace;
    controller.initialize().then((_) {
      if (!mounted) return;
      _initRetryCount = 0;
      DiagnosticService.instance.success(
        'VideoPlayer',
        'Player initialized successfully. Duration: ${controller.value.duration}',
      );
      controller.setLooping(_theme.loop);
      _applyControllerVolume(controller);
      controller.setPlaybackSpeed(_speed);
      controller.addListener(_onTick);

      // Resume from saved position if available (from Trakt or local watch
      // history). The model's own progress only describes the episode it was
      // launched with, so an in-place switch must not reuse it.
      final modelMatchesActive =
          (widget.season == null || widget.season == _seasonNumber) &&
              (widget.episode == null || widget.episode == _episodeNumber);
      final savedProgress =
          (modelMatchesActive ? widget.movie.watchProgress : null) ??
              context.read<LibraryService>().getWatchProgress(
                    widget.movie,
                    season: _seasonNumber,
                    episode: _episodeNumber,
                  );
      if (savedProgress != null &&
          savedProgress > 0.02 &&
          savedProgress < 0.95) {
        final totalMs = controller.value.duration.inMilliseconds;
        if (totalMs > 10000) {
          final seekMs = (totalMs * savedProgress).round();
          final seekPos = Duration(milliseconds: seekMs);
          controller.seekTo(seekPos);
          DiagnosticService.instance.info(
            'VideoPlayer',
            'Resumed playback from ${(savedProgress * 100).toStringAsFixed(0)}% (${seekPos.inMinutes}m ${seekPos.inSeconds % 60}s)',
          );
        }
      }

      if (_wantsPlayback) {
        controller.play();
        _schedulePlaybackKick(controller);
      }
      _scheduleHide();
      _startScrobbling();
    }).catchError((Object err) {
      if (!mounted) return;
      DiagnosticService.instance.error(
        'VideoPlayer',
        'VideoPlayer initialization error (attempt ${_initRetryCount + 1}): $err',
        err,
      );
      debugPrint('VideoPlayer error: $err');

      // Retry automatically up to 2 times with a 1.2s delay before giving up.
      if (_initRetryCount < 2 && networkUrl != null) {
        _initRetryCount++;
        DiagnosticService.instance.warning(
          'VideoPlayer',
          'Source error — retrying in 1.2s (attempt $_initRetryCount/2)…',
        );
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            _controller?.dispose();
            _controller = null;
            StreamProxyService.instance.stop();
            _initController();
          }
        });
        return;
      }

      setState(() => _error = err.toString());
    });
  }

  void _onTick() {
    if (!mounted) return;
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      _syncPipState();
      _trackPlaybackHealth(c.value);
      final settings = context.read<SettingsService>();
      final pos = c.value.position;
      final dur = c.value.duration;
      final posMs = pos.inMilliseconds;
      final durMs = dur.inMilliseconds;

      // ── Skip Intro (first 90 s of TV episode content) ─────────────────────
      // The switch auto-skips once per episode; the button stays available
      // when it is off (or when the seek already happened).
      final isTvShow = widget.movie.isTV || widget.season != null;
      if (isTvShow && !widget.isTrailer) {
        final inIntroWindow = posMs >= 5000 && posMs < 90000 && durMs > 180000;
        if (inIntroWindow &&
            settings.skipIntro &&
            !_autoIntroSkipped &&
            !_skipIntroDismissed) {
          _autoIntroSkipped = true;
          c.seekTo(const Duration(seconds: 90));
        }
        final showButton =
            inIntroWindow && !_skipIntroDismissed && !_autoIntroSkipped;
        if (showButton != _showSkipIntro) _showSkipIntro = showButton;
      } else if (_showSkipIntro) {
        _showSkipIntro = false;
      }

      // ── Auto-next episode countdown (ending detection: last 35 s or credits) ───────────
      final remainingMs = durMs - posMs;
      final isEnding = (remainingMs <= 35000 && remainingMs > 0) ||
          (durMs > 600000 && posMs >= (durMs * 0.985));

      // ── Background Preload & Auto-Download Next Episode at 60% mark ─────────
      if (!widget.downloadPlayback &&
          isTvShow &&
          !widget.isTrailer &&
          !_preloadedNextEpisode &&
          posMs >= (durMs * 0.60)) {
        _preloadedNextEpisode = true;
        unawaited(_prepareNextEpisode());
      }

      if (settings.autoNextEpisode &&
          isTvShow &&
          !widget.isTrailer &&
          _canGoNext &&
          durMs > 30000 &&
          posMs > 0 &&
          isEnding &&
          !c.value.isBuffering) {
        if (!_showNextEpisode) {
          _showNextEpisode = true;
          _nextEpisodeCountdown = 8;
          _nextEpisodeTimer?.cancel();
          _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            setState(() {
              _nextEpisodeCountdown--;
              if (_nextEpisodeCountdown <= 0) {
                t.cancel();
                _showNextEpisode = false;
                _playNextEpisode();
              }
            });
          });
        }
      } else if (_showNextEpisode && (!isEnding || !c.value.isPlaying)) {
        _nextEpisodeTimer?.cancel();
        _showNextEpisode = false;
      }

      // ── Subtitle Synchronization ─────────────────────────────────────────
      if (_subtitlesOn && _subtitleController != null) {
        try {
          final sub = _subtitleController!.durationSearch(pos);
          final rawText = sub?.data ?? '';
          final text = rawText
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll('&nbsp;', ' ')
              .trim();
          if (text != _currentSubtitleText) {
            _currentSubtitleText = text;
          }
        } catch (_) {}
      } else if (!_subtitlesOn && _currentSubtitleText.isNotEmpty) {
        _currentSubtitleText = '';
      }
    }
    setState(() {});
  }

  Future<void> _prepareNextEpisode() async {
    final movie = widget.movie;
    final curSeason = _seasonNumber ?? 1;
    final curEpisode = _episodeNumber ?? 1;
    final nextEp = curEpisode + 1;

    final maxEpisode = await _loadSeasonEpisodeMax();
    if (!mounted) return;
    // Without the season's episode list there is no way to tell a real next
    // episode from one past the finale, so don't queue anything at all.
    if (maxEpisode == null) {
      DiagnosticService.instance.warning(
        'VideoPlayer',
        'Next episode skipped: S$curSeason episode list unavailable',
      );
      return;
    }
    if (nextEp > maxEpisode) {
      DiagnosticService.instance.info(
        'VideoPlayer',
        'No next episode: S$curSeason ends at E$maxEpisode',
      );
      return;
    }

    final settings = context.read<SettingsService>();
    final delivery = context.read<MediaDeliveryService>();

    // 1. Auto-download next episode if user setting enabled
    if (settings.autoDownloadNextEpisode) {
      if (!delivery.isEpisodeDownloaded(movie.id, curSeason, nextEp) &&
          !delivery.isEpisodeDownloading(movie.id, curSeason, nextEp)) {
        delivery.downloadEpisode(
          movie: movie,
          season: curSeason,
          episode: nextEp,
          episodeTitle: 'Episode $nextEp',
        );
        DiagnosticService.instance.info(
          'VideoPlayer',
          'Auto-download queued for next episode: S$curSeason E$nextEp',
        );
      }
    }

    // 2. Preload next episode stream ahead of time for instant playback
    delivery
        .resolveStream(
      movie,
      season: curSeason,
      episode: nextEp,
    )
        .then((source) {
      if (mounted) {
        _preloadedNextSource = source;
        DiagnosticService.instance.success(
          'VideoPlayer',
          'Preloaded next episode stream (${source.cdn ?? "CDN"})',
        );
      }
    }).catchError((e) {
      DiagnosticService.instance.warning(
        'VideoPlayer',
        'Preload next episode stream failed (will resolve on demand): $e',
      );
    });
  }

  void _startScrobbling() {
    _scrobbleTimer?.cancel();
    _scrobbleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final c = _controller;
      if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
      final dur = c.value.duration.inMilliseconds;
      if (dur == 0) return;
      final progress = (c.value.position.inMilliseconds / dur).clamp(0.0, 1.0);
      _scrobble(progress);
    });
  }

  /// The title to record progress against: the model itself, or the model's
  /// show re-tagged with whichever episode is actually loaded. An in-place
  /// episode switch keeps the original widget, so `widget.movie` alone would
  /// keep reporting the episode it was launched with.
  Movie? get _progressTarget {
    final movie = widget.movie;
    if (movie.id == '__standalone__') return null;
    final season = _seasonNumber;
    final episode = _episodeNumber;
    if (season == null || episode == null) return movie;
    if (movie is TVShow && movie.season == season && movie.episode == episode) {
      return movie;
    }
    return TVShow(
      id: movie.id,
      tmdbId: movie.tmdbId,
      imdbId: movie.imdbId,
      title: movie.title,
      description: movie.description,
      imageUrl: movie.imageUrl,
      backdropUrl: movie.backdropUrl,
      rating: movie.rating,
      duration: movie.duration,
      genres: movie.genres,
      badges: movie.badges,
      year: movie.year,
      ageRating: movie.ageRating,
      season: season,
      episode: episode,
      episodeTitle: _episodeTitle ?? 'S$season E$episode',
    );
  }

  void _persistProgress(VideoPlayerController? c) {
    try {
      if (c == null || !c.value.isInitialized) return;
      final dur = c.value.duration.inMilliseconds;
      if (dur <= 0) return;
      final progress = (c.value.position.inMilliseconds / dur).clamp(0.0, 1.0);
      if (progress <= 0.02) return;
      final target = _progressTarget;
      if (target == null) return;
      if (progress >= 0.95) {
        context.read<LibraryService>().removeFromContinueWatching(target);
      } else {
        context.read<LibraryService>().updateWatchProgress(target, progress);
      }
    } catch (_) {
      // Progress persistence must never prevent a source swap or teardown.
    }
  }

  Future<void> _scrobble(double progress) async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final targetMovie = _progressTarget;
    if (targetMovie != null) {
      if (progress >= 0.95) {
        context.read<LibraryService>().removeFromContinueWatching(targetMovie);
      } else {
        context
            .read<LibraryService>()
            .updateWatchProgress(targetMovie, progress);
      }
    }
    if (!settings.scrobbleAutomatically) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn || auth.accessToken == null) return;
    final season = targetMovie is TVShow ? targetMovie.season : null;
    final episode = targetMovie is TVShow ? targetMovie.episode : null;
    try {
      if (progress >= 0.95) {
        // One stop per title: the 30s tick keeps firing past the 95% mark,
        // and Trakt would record a new play for every call.
        if (_traktStopSent) return;
        _traktStopSent = true;
        await TraktService.scrobbleStop(
          auth.accessToken!,
          title: widget.movie.title,
          imdbId: widget.movie.imdbId,
          tmdbId: widget.movie.tmdbId,
          season: season,
          episode: episode,
        );
      } else {
        await TraktService.pausePlayback(
          auth.accessToken!,
          title: widget.movie.title,
          imdbId: widget.movie.imdbId,
          tmdbId: widget.movie.tmdbId,
          season: season,
          episode: episode,
          progress: progress * 100,
        );
      }
    } catch (_) {
      // Scrobbling is best-effort.
    }
  }

  /// True while a remote / keyboard ring sits on one of the player controls.
  /// Auto-hiding then would leave the ring on an invisible button.
  bool _focusInControls() {
    final focused = FocusManager.instance.primaryFocus?.context;
    final root = _controlsKey.currentContext;
    if (focused == null || root == null) return false;
    if (identical(focused, root)) return true;
    var inside = false;
    focused.visitAncestorElements((element) {
      if (identical(element, root)) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_controller?.value.isPlaying != true) return;
    _hideTimer = Timer(_theme.controlsAutoHide, () {
      if (mounted &&
          _controller?.value.isPlaying == true &&
          !_isScrubbing &&
          !_boostActive &&
          !_focusInControls()) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _debouncedToggleControls() {
    _cancelDebouncedToggle();
    _tapDebounceTimer = Timer(const Duration(milliseconds: _kDebounceMs), () {
      if (mounted) _toggleControls();
    });
  }

  void _cancelDebouncedToggle() {
    _tapDebounceTimer?.cancel();
    _tapDebounceTimer = null;
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    if (_wantsPlayback) {
      _wantsPlayback = false;
      c.pause();
      _hideTimer?.cancel();
      setState(() => _controlsVisible = true);
    } else {
      _wantsPlayback = true;
      c.play();
      _showControls();
    }
  }

  void _skip(Duration delta) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    final target = c.value.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target);
    c.seekTo(clamped);
    _showControls();
  }

  void _seekTo(Duration position) {
    _controller?.seekTo(position);
    _showControls();
  }

  void _skipIntro() {
    HapticFeedback.selectionClick();
    _controller?.seekTo(const Duration(seconds: 90));
    setState(() {
      _showSkipIntro = false;
      _skipIntroDismissed = true;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Intro skipped',
            style: TextStyle(color: Colors.white, fontSize: 13)),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHigh,
      ),
    );
  }

  void _setVolume(double v) {
    final level = v.clamp(0.0, 1.0);
    setState(() {
      _volume = level;
      _muted = level == 0;
    });
    if (_deviceVolumeMode) DeviceVolume.write(level);
    _applyControllerVolume();
    _showControls();
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      // Unmuting from silence needs a level to come back to.
      if (!_muted && _volume == 0) _volume = 0.5;
    });
    if (!_muted && _deviceVolumeMode) DeviceVolume.write(_volume);
    _applyControllerVolume();
    HapticFeedback.selectionClick();
    _showControls();
  }

  IconData get _fitModeIcon {
    switch (_fitMode) {
      case PlayerFitMode.contain:
        return Icons.aspect_ratio_rounded;
      case PlayerFitMode.cover:
        return Icons.crop_original_rounded;
      case PlayerFitMode.zoom:
        return Icons.zoom_in_map_rounded;
      case PlayerFitMode.stretch16x9:
        return Icons.fit_screen_rounded;
      case PlayerFitMode.stretch4x3:
        return Icons.crop_3_2_rounded;
      case PlayerFitMode.fitWidth:
        return Icons.unfold_less_rounded;
      case PlayerFitMode.fitHeight:
        return Icons.unfold_more_rounded;
      case PlayerFitMode.original:
        return Icons.crop_free_rounded;
      case PlayerFitMode.zoom150:
        return Icons.zoom_in_rounded;
      case PlayerFitMode.zoom200:
        return Icons.zoom_out_map_rounded;
      case PlayerFitMode.customZoom:
        return Icons.tune_rounded;
    }
  }

  String get _fitModeLabel {
    switch (_fitMode) {
      case PlayerFitMode.contain:
        return 'Fit';
      case PlayerFitMode.cover:
        return 'Fill';
      case PlayerFitMode.zoom:
        return 'Zoom 120%';
      case PlayerFitMode.stretch16x9:
        return 'Stretch 16:9';
      case PlayerFitMode.stretch4x3:
        return 'Stretch 4:3';
      case PlayerFitMode.fitWidth:
        return 'Fit Width';
      case PlayerFitMode.fitHeight:
        return 'Fit Height';
      case PlayerFitMode.original:
        return '1:1 Original';
      case PlayerFitMode.zoom150:
        return 'Zoom 150%';
      case PlayerFitMode.zoom200:
        return 'Zoom 200%';
      case PlayerFitMode.customZoom:
        return 'Custom ${(_customZoomScale * 100).toStringAsFixed(0)}%';
    }
  }

  static const List<PlayerFitMode> _fitCycle = [
    PlayerFitMode.contain,
    PlayerFitMode.cover,
    PlayerFitMode.zoom,
    PlayerFitMode.stretch16x9,
    PlayerFitMode.stretch4x3,
    PlayerFitMode.fitWidth,
    PlayerFitMode.fitHeight,
    PlayerFitMode.original,
    PlayerFitMode.zoom150,
    PlayerFitMode.zoom200,
  ];

  void _toggleFit() {
    HapticFeedback.selectionClick();
    final idx = _fitCycle.indexOf(_fitMode);
    final next = _fitCycle[(idx + 1) % _fitCycle.length];
    setState(() => _fitMode = next);
    _showFitToast();
    _showControls();
  }

  void _showFitToast() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _fitModeLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          duration: const Duration(milliseconds: 900),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHighest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  void _toggleRotationLock() {
    HapticFeedback.selectionClick();
    final wasLocked = _rotationLocked;
    setState(() => _rotationLocked = !wasLocked);
    if (_rotationLocked) {
      final size = MediaQuery.of(context).size;
      SystemChrome.setPreferredOrientations([
        size.width > size.height
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.portraitUp,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(_isFullscreen
          ? [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : DeviceOrientation.values);
    }
    _showControls();
  }

  void _setupInitialSubtitles() {
    if (_activeSubtitles.isEmpty) return;
    final settings = context.read<SettingsService>();
    final prefLang = settings.subtitleLanguage.toLowerCase();

    // Find preferred match or first english/available track
    final track = _activeSubtitles.firstWhere(
      (s) =>
          s.language.toLowerCase().contains(prefLang) ||
          s.label.toLowerCase().contains(prefLang),
      orElse: () => _activeSubtitles.firstWhere(
        (s) =>
            s.language.toLowerCase().contains('en') ||
            s.label.toLowerCase().contains('eng'),
        orElse: () => _activeSubtitles.first,
      ),
    );
    _loadSubtitleTrack(track);
  }

  Future<void> _loadSubtitleTrack(SubtitleTrack track) async {
    _selectedSubtitleTrack = track;
    try {
      final client = http.Client();
      final uri = Uri.parse(track.url);
      final res = await client.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        if (_activeHeaders != null) ..._activeHeaders!,
      }).timeout(const Duration(seconds: 8));

      String vttContent = '';
      if (res.statusCode == 200) {
        if (res.body.contains('WEBVTT')) {
          vttContent = res.body;
        } else {
          // Playlist containing .vtt segment chunks or sub-playlist
          final lines = res.body.split('\n').map((l) => l.trim()).toList();
          final vttUris =
              lines.where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
          if (vttUris.isNotEmpty) {
            final cuesBuffer = StringBuffer('WEBVTT\n\n');
            // Download segments in parallel or first chunk
            for (final vLine in vttUris.take(15)) {
              try {
                final targetUri = uri.resolve(vLine);
                final vttRes = await client.get(
                  targetUri,
                  headers: {
                    'User-Agent':
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    if (_activeHeaders != null) ..._activeHeaders!,
                  },
                ).timeout(const Duration(seconds: 6));
                if (vttRes.statusCode == 200) {
                  final text =
                      vttRes.body.replaceFirst(RegExp(r'^WEBVTT[^\n]*\n+'), '');
                  cuesBuffer.writeln(text);
                }
              } catch (_) {}
            }
            vttContent = cuesBuffer.toString();
          }
        }
      }
      client.close();

      if (vttContent.isNotEmpty && mounted) {
        final ctrl = sub_pkg.SubtitleController(
          provider: sub_pkg.SubtitleProvider.fromString(
            data: vttContent,
            type: sub_pkg.SubtitleType.vtt,
          ),
        );
        // Important: SubtitleController MUST be initialized to parse cues
        await ctrl.initial();
        setState(() {
          _subtitleController = ctrl;
        });
        DiagnosticService.instance.success(
          'Subtitles',
          'Loaded subtitle track: ${track.label} (${track.language})',
        );
      }
    } catch (e) {
      DiagnosticService.instance.warning(
        'Subtitles',
        'Failed to load subtitle track: $e',
      );
    }
  }

  void _showSubtitleSheet() {
    HapticFeedback.selectionClick();
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.subtitles_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Subtitles / Captions',
                      style: AppTheme.cardTitle
                          .copyWith(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: Icon(
                  !_subtitlesOn
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: !_subtitlesOn
                      ? _theme.accent
                      : AppColors.onSurfaceVariant,
                ),
                title: const Text('Off', style: TextStyle(color: Colors.white)),
                onTap: () {
                  setState(() => _subtitlesOn = false);
                  Navigator.pop(ctx);
                },
              ),
              if (_activeSubtitles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    'No embedded subtitle tracks found in stream.',
                    style: TextStyle(
                        color: AppColors.onSurfaceVariant, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _activeSubtitles.length,
                    itemBuilder: (_, index) {
                      final track = _activeSubtitles[index];
                      final isSelected = _subtitlesOn &&
                          _selectedSubtitleTrack?.url == track.url;
                      final label = track.label.isNotEmpty
                          ? track.label
                          : (track.language.isNotEmpty
                              ? track.language
                              : 'Track ${index + 1}');
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: isSelected
                              ? _theme.accent
                              : AppColors.onSurfaceVariant,
                        ),
                        title: Text(label,
                            style: const TextStyle(color: Colors.white)),
                        subtitle:
                            track.language.isNotEmpty && track.language != label
                                ? Text(track.language,
                                    style: const TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 12))
                                : null,
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _subtitlesOn = true);
                          _loadSubtitleTrack(track);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleSubtitles() {
    HapticFeedback.selectionClick();
    final next = !_subtitlesOn;
    setState(() => _subtitlesOn = next);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Subtitles enabled (${_selectedSubtitleTrack?.label ?? context.read<SettingsService>().subtitleLanguage})'
              : 'Subtitles disabled',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHigh,
      ),
    );
    _showControls();
  }

  void _showCastSheet() {
    HapticFeedback.selectionClick();
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cast to device',
                  style: AppTheme.cardTitle.copyWith(color: Colors.white)),
              const SizedBox(height: 12),
              Text(
                'No nearby devices found. Chromecast, AirPlay and DLNA discovery is not wired up yet.',
                style: AppTheme.metadata
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(foregroundColor: _theme.accent),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _showControls());
  }

  Future<void> _pickSpeed() async {
    _hideTimer?.cancel();
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Playback speed',
                style: AppTheme.cardTitle.copyWith(color: AppColors.white)),
            const SizedBox(height: 8),
            ..._theme.playbackSpeeds.map(
              (s) => ListTile(
                dense: true,
                title: Text(
                  '${s.toStringAsFixed(s.truncateToDouble() == s ? 1 : 2)}x',
                  style: AppTheme.metadata.copyWith(
                    color: s == _speed ? _theme.accent : AppColors.onSurface,
                    fontWeight: s == _speed ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                trailing: s == _speed
                    ? Icon(Icons.check_rounded, color: _theme.accent, size: 20)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() => _speed = result);
      _controller?.setPlaybackSpeed(result);
    }
    _showControls();
  }

  Future<void> _pickQuality() async {
    _hideTimer?.cancel();
    final settingsService = context.read<SettingsService>();
    final result = await showModalBottomSheet<VideoQuality>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.82,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.high_quality_rounded,
                          color: AppColors.secondary, size: 22),
                      const SizedBox(width: 10),
                      Text('Video Quality',
                          style: AppTheme.cardTitle
                              .copyWith(color: AppColors.white)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: Icon(
                    _quality == VideoQuality.auto
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: _quality == VideoQuality.auto
                        ? _theme.accent
                        : Colors.white54,
                    size: 20,
                  ),
                  title: Text(
                    'Auto (Network Adaptive)',
                    style: TextStyle(
                      color: _quality == VideoQuality.auto
                          ? _theme.accent
                          : Colors.white,
                      fontWeight: _quality == VideoQuality.auto
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    'Adapts to real network speed • Currently ${_qualityShortName(_servedQuality)}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(ctx, VideoQuality.auto),
                ),
                const Divider(color: Colors.white12, height: 1),
                ...[
                  VideoQuality.uhd4k,
                  VideoQuality.fullHd1080,
                  VideoQuality.hd720,
                  VideoQuality.sd480,
                ].map(
                  (q) => ListTile(
                    dense: true,
                    leading: Icon(
                      _quality == q
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: _quality == q ? _theme.accent : Colors.white54,
                      size: 20,
                    ),
                    title: Text(
                      q.label,
                      style: TextStyle(
                        color: q == _quality ? _theme.accent : Colors.white,
                        fontWeight:
                            q == _quality ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    subtitle: Text(
                      q == VideoQuality.uhd4k
                          ? 'Ultra High Definition • Highest quality'
                          : (q == VideoQuality.fullHd1080
                              ? 'High definition • Crisp detail'
                              : (q == VideoQuality.hd720
                                  ? 'Standard HD • Smooth streaming'
                                  : 'Standard definition • Lower data usage')),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11),
                    ),
                    onTap: () => Navigator.pop(ctx, q),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null && result != _quality) {
      setState(() => _quality = result);
      settingsService.setStreamQuality(result);
      _slowSamples = 0;
      _fastSamples = 0;
      final target = result == VideoQuality.auto ? _linkQuality : result;
      if (_rungOf(target) != _rungOf(_servedQuality)) {
        _setServedQuality(target);
      } else {
        StreamProxyService.instance.setQualityTarget(_servedQuality);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result == VideoQuality.auto
                  ? 'Quality set to Auto (${_qualityShortName(_servedQuality)} via network)'
                  : 'Quality set to ${result.label}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    }
    _showControls();
  }

  void _showMoreMenu() {
    HapticFeedback.selectionClick();
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text('More options',
                    style: AppTheme.cardTitle.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                if (_resolvedCdn != null) ...[
                  ListTile(
                    leading: const Icon(Icons.cloud_done_rounded,
                        color: AppColors.secondary),
                    title: const Text('Stream Server / CDN',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      _resolvedCdn!,
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          color: Colors.white54, size: 18),
                      tooltip: 'Copy stream URL',
                      onPressed: () {
                        final copyText = _activeUrl ?? _resolvedCdn!;
                        Clipboard.setData(ClipboardData(text: copyText));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Stream URL copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded,
                      color: AppColors.secondary),
                  title: const Text('Switch stream / server',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _resolvedCdn != null
                        ? 'Current: $_resolvedCdn • Tap to cycle server'
                        : 'Try alternative stream source',
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _switchStream();
                  },
                ),
                if (_showEpisodeNav) ...[
                  ListTile(
                    leading: const Icon(Icons.skip_previous_rounded,
                        color: Colors.white),
                    title: Text(
                        _isSeriesPlayback
                            ? 'Previous episode'
                            : 'Previous title',
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      _isSeriesPlayback
                          ? (_hasPreviousEpisode
                              ? 'Season $_seasonNumber • Episode ${(_episodeNumber ?? 1) - 1}'
                              : 'First episode of this season')
                          : 'Back in this download list',
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                    enabled: _canGoPrevious,
                    onTap: _canGoPrevious
                        ? () {
                            Navigator.pop(ctx);
                            _playPreviousEpisode();
                          }
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.skip_next_rounded,
                        color: Colors.white),
                    title: Text(
                        _isSeriesPlayback ? 'Next episode' : 'Next title',
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      _isSeriesPlayback
                          ? 'Season $_seasonNumber • Episode ${(_episodeNumber ?? 0) + 1}'
                          : 'Forward in this download list',
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                    enabled: _canGoNext,
                    onTap: _canGoNext
                        ? () {
                            Navigator.pop(ctx);
                            _playNextEpisode();
                          }
                        : null,
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.high_quality_rounded,
                      color: Colors.white),
                  title: const Text('Video Quality',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _qualityPillLabel,
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickQuality();
                  },
                ),
                if (_canPickAudio)
                  ListTile(
                    leading: const Icon(Icons.graphic_eq_rounded,
                        color: Colors.white),
                    title: const Text('Audio Track',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      _audioPillLabel,
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAudio();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.speed_rounded, color: Colors.white),
                  title: const Text('Playback speed',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${_speed.toStringAsFixed(_speed.truncateToDouble() == _speed ? 1 : 2)}x',
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickSpeed();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.aspect_ratio_rounded,
                      color: Colors.white),
                  title: const Text('Aspect ratio',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _fitModeLabel,
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleFit();
                  },
                ),
                ListTile(
                  leading: Icon(
                    _subtitlesOn
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                    color: _subtitlesOn ? _theme.accent : Colors.white,
                  ),
                  title: const Text('Subtitles',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _subtitlesOn
                        ? '${_selectedSubtitleTrack?.label ?? context.read<SettingsService>().subtitleLanguage} (On)'
                        : 'Off',
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_activeSubtitles.length > 1) {
                      _showSubtitleSheet();
                    } else {
                      _toggleSubtitles();
                    }
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.bedtime_outlined, color: Colors.white),
                  title: const Text('Sleep timer',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Not configured',
                      style: TextStyle(color: AppColors.onSurfaceVariant)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Sleep timer coming soon',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.surfaceContainerHigh,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => _showControls());
  }

  Future<void> _toggleFullscreen() async {
    HapticFeedback.selectionClick();
    final bool next = !_isFullscreen;
    setState(() => _isFullscreen = next);
    try {
      if (kIsWeb) {
        if (next) {
          await web_fullscreen.requestFullscreen();
        } else {
          web_fullscreen.exitFullscreen();
        }
      } else if (!_rotationLocked) {
        if (next) {
          await SystemChrome.setEnabledSystemUIMode(
              SystemUiMode.immersiveSticky);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          await SystemChrome.setPreferredOrientations(
            _tvLayout
                ? [
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]
                : [
                    DeviceOrientation.portraitUp,
                  ],
          );
        }
      }
    } catch (_) {
      // Some platforms don't support programmatic fullscreen.
    }
    _showControls();
  }

  /// Navigates to the next episode. Called automatically by the countdown
  /// or immediately when the user taps "Next Episode".
  void _playNextEpisode() {
    unawaited(_playNextEpisodeAsync());
  }

  Future<void> _playNextEpisodeAsync() async {
    if (!mounted || _swappingSource) return;
    _nextEpisodeTimer?.cancel();
    if (widget.downloadPlayback) {
      _controller?.pause();
      _wantsPlayback = false;
      widget.onPlayNext?.call();
      return;
    }
    if (_isSeriesPlayback && !_hasNextEpisode) {
      await _loadSeasonEpisodeMax();
      if (!mounted || !_hasNextEpisode) return;
    }
    final currentSeason = _seasonNumber ?? 1;
    final nextEpisode = (_episodeNumber ?? 1) + 1;

    setState(() => _swappingSource = true);
    try {
      final preloaded = _preloadedNextSource;
      final source = (preloaded != null &&
              ((preloaded.url?.isNotEmpty ?? false) ||
                  (preloaded.assetPath?.isNotEmpty ?? false)))
          ? preloaded
          : await context.read<MediaDeliveryService>().resolveStream(
                widget.movie,
                season: currentSeason,
                episode: nextEpisode,
              );
      if (!mounted) return;
      await _swapToSource(
        source,
        season: currentSeason,
        episode: nextEpisode,
      );
    } catch (e) {
      if (!mounted) return;
      DiagnosticService.instance.error(
        'VideoPlayer',
        'Could not load S$currentSeason E$nextEpisode: $e',
      );
      _showQualityNote('Could not load S$currentSeason E$nextEpisode');
    } finally {
      if (mounted) setState(() => _swappingSource = false);
    }
  }

  /// Loads [source] into this player instead of pushing a new route.
  ///
  /// The surface, controls state and landscape/fullscreen orientation all
  /// survive, so moving between episodes or servers never drops back to the
  /// resolver screen or to portrait.
  Future<void> _swapToSource(
    PlayableSource source, {
    required int season,
    required int episode,
    int? providerIndex,
    bool resetStreamHistory = true,
  }) async {
    if (!mounted) return;
    final previousEpisode = _episodeNumber;
    final old = _controller;
    _persistProgress(old);
    _controller = null;
    old?.removeListener(_onTick);
    try {
      await old?.pause();
    } catch (_) {}
    await old?.dispose();
    if (!mounted) return;

    _seasonOverride = season;
    _episodeOverride = episode;
    if (episode != previousEpisode) _episodeTitleOverride = null;
    _activeUrl = source.url;
    _activeAsset = source.assetPath;
    _activeHeaders = source.headers;
    _activeCdn = source.cdn;
    _activeSubtitles = source.subtitles;
    _pendingManifest = source.masterPlaylist;
    _audioTracks = source.audioTracks;
    _audioLanguage =
        _initialAudioLanguage(context.read<SettingsService>().audioLanguage);
    StreamProxyService.instance.setAudioTarget(_proxyAudioLanguage);
    if (resetStreamHistory) {
      _triedStreamUrls.clear();
      _currentProviderIndex = 0;
    } else if (providerIndex != null) {
      _currentProviderIndex = providerIndex;
    }

    _showSkipIntro = false;
    _skipIntroDismissed = false;
    _autoIntroSkipped = false;
    _showNextEpisode = false;
    _nextEpisodeTimer?.cancel();
    _preloadedNextEpisode = false;
    _preloadedNextSource = null;
    _traktStopSent = false;
    _stallNudges = 0;
    _lastStallPosition = Duration.zero;
    _lastStallProgressAt = DateTime.now();
    _bufferingSince = null;
    _initRetryCount = 0;
    _error = null;
    _currentSubtitleText = '';
    _selectedSubtitleTrack = null;
    _subtitleController = null;

    if (!mounted) return;
    setState(() {});
    _setupInitialSubtitles();
    _initController();
    _startQualitySampling();
    _showControls();
  }

  int? get _seasonNumber =>
      _seasonOverride ??
      widget.season ??
      (widget.movie is TVShow ? (widget.movie as TVShow).season : null);

  int? get _episodeNumber =>
      _episodeOverride ??
      widget.episode ??
      (widget.movie is TVShow ? (widget.movie as TVShow).episode : null);

  /// Name of the episode being played, when the model describes this exact
  /// season/episode. Placeholder labels ("S1 E2") are skipped because the
  /// metadata line already spells them out.
  String? get _episodeTitle {
    if (_episodeTitleOverride != null) return _episodeTitleOverride;
    final movie = widget.movie;
    if (movie is! TVShow || !_isSeriesPlayback) return null;
    if (movie.season != _seasonNumber) return null;
    if (movie.episode != _episodeNumber) return null;
    final title = movie.episodeTitle.trim();
    if (title.isEmpty) return null;
    if (RegExp(r'^S\d+\s*E\d+$', caseSensitive: false).hasMatch(title)) {
      return null;
    }
    return title;
  }

  /// True when the current item belongs to a season — drives the episode
  /// navigation controls (streaming and downloaded episodes alike).
  bool get _isSeriesPlayback =>
      !widget.isTrailer && widget.movie.isTV && _episodeNumber != null;

  bool get _hasPreviousEpisode => (_episodeNumber ?? 1) > 1;

  /// Whether a further episode exists in this season. Unknown until TMDB
  /// answers, so an unresolved max keeps the old optimistic behaviour.
  bool get _hasNextEpisode {
    final episode = _episodeNumber;
    if (episode == null) return true;
    final max = _seasonEpisodeMax;
    return max == null || episode < max;
  }

  Future<int?> _loadSeasonEpisodeMax() {
    final known = _seasonEpisodeMax;
    if (known != null) return Future.value(known);
    return _seasonEpisodeMaxFuture ??= _fetchSeasonEpisodeMax();
  }

  Future<int?> _fetchSeasonEpisodeMax() async {
    final season = _seasonNumber;
    final tmdbId = widget.movie.tmdbId;
    if (season == null || tmdbId <= 0) return null;
    try {
      final data = await TmdbService.getTVSeason(tmdbId, season);
      var max = 0;
      for (final raw in (data?['episodes'] as List?) ?? const []) {
        if (raw is! Map) continue;
        final number = raw['episode_number'];
        if (number is int && number > max) max = number;
      }
      if (max == 0) return null;
      _seasonEpisodeMax = max;
      if (mounted) setState(() {});
      return max;
    } finally {
      if (_seasonEpisodeMax == null) _seasonEpisodeMaxFuture = null;
    }
  }

  bool get _canGoPrevious =>
      widget.onPlayPrevious != null ||
      (!widget.downloadPlayback && _isSeriesPlayback && _hasPreviousEpisode);

  bool get _canGoNext =>
      widget.onPlayNext != null ||
      (!widget.downloadPlayback && _isSeriesPlayback && _hasNextEpisode);

  /// Prev/next controls: a season context, or the caller's own playlist.
  bool get _showEpisodeNav =>
      !widget.isTrailer && (_canGoPrevious || _canGoNext);

  /// Navigates to the previous episode, mirroring [_playNextEpisode].
  void _playPreviousEpisode() {
    if (!mounted || _swappingSource) return;
    _nextEpisodeTimer?.cancel();
    if (widget.downloadPlayback) {
      _controller?.pause();
      _wantsPlayback = false;
      widget.onPlayPrevious?.call();
      return;
    }
    if (!_hasPreviousEpisode) return;
    final currentSeason = _seasonNumber ?? 1;
    final previousEpisode = (_episodeNumber ?? 1) - 1;
    unawaited(_playEpisodeInPlace(currentSeason, previousEpisode));
  }

  Future<void> _playEpisodeInPlace(int season, int episode) async {
    setState(() => _swappingSource = true);
    try {
      final source = await context.read<MediaDeliveryService>().resolveStream(
            widget.movie,
            season: season,
            episode: episode,
          );
      if (!mounted) return;
      await _swapToSource(source, season: season, episode: episode);
    } catch (e) {
      if (!mounted) return;
      DiagnosticService.instance.error(
        'VideoPlayer',
        'Could not load S$season E$episode: $e',
      );
      _showQualityNote('Could not load S$season E$episode');
    } finally {
      if (mounted) setState(() => _swappingSource = false);
    }
  }

  void _onDoubleTapDown(TapDownDetails details, double screenWidth) {
    if (!_theme.enableDoubleTapSkip) return;
    _cancelDebouncedToggle();
    final side = details.globalPosition.dx < screenWidth / 2
        ? _RippleSide.left
        : _RippleSide.right;
    _skip(side == _RippleSide.left ? -_theme.skipStep : _theme.skipStep);
    HapticFeedback.mediumImpact();
    setState(() {
      _rippleSide = side;
      _rippleId++;
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _rippleSide = null);
    });
  }

  void _onLongPressStart() {
    if (!_theme.enableLongPressBoost) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _hideTimer?.cancel();
    _lastNonBoostSpeed = _speed;
    setState(() => _boostActive = true);
    c.setPlaybackSpeed(_theme.longPressBoostSpeed);
    HapticFeedback.mediumImpact();
  }

  void _onLongPressEnd() {
    if (!_boostActive) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    c.setPlaybackSpeed(_lastNonBoostSpeed ?? _speed);
    setState(() => _boostActive = false);
    _showControls();
  }

  @override
  void dispose() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.removeObserver(this);
      PlatformMediaChannel.stopListening();
      _delivery?.setAutoPip(enable: false);
    }
    _hideTimer?.cancel();
    _scrobbleTimer?.cancel();
    _tapDebounceTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _gestureHudTimer?.cancel();
    _qualitySampleTimer?.cancel();
    _stallWatchdogTimer?.cancel();
    _connectivitySubscription?.cancel();
    try {
      ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
    _persistProgress(_controller);
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _controller = null;
    _deviceVolumeSubscription?.cancel();
    if (_deviceVolumeMode && _volumeOnEnter != null) {
      DeviceVolume.write(_volumeOnEnter!);
      DeviceVolume.configure(showSystemUI: true);
    }
    StreamProxyService.instance.stop(sessionId: _sessionId);
    // Offline playlists replace this route with another player; resetting the
    // orientation here would flash portrait between two full-screen players.
    // Leaving the player entirely goes through _exitPlayer/PopScope, which
    // always restores portrait.
    if (!widget.downloadPlayback) {
      SystemChrome.setPreferredOrientations(
        _tvLayout
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [
                DeviceOrientation.portraitUp,
              ],
      );
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) return;
          _controller?.pause();
          _delivery?.setAutoPip(enable: false);
          if (!_tvLayout) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]);
          }
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: LayoutBuilder(builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildVideoSurface(),
                // Software brightness dimmer overlay for uniform cross-platform dimming
                if (!_inPip)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(
                          alpha: (1.0 - _brightness).clamp(0.0, 0.85),
                        ),
                      ),
                    ),
                  ),
                if (_rippleSide != null)
                  _SkipRipple(
                    key: ValueKey('ripple-$_rippleId'),
                    side: _rippleSide!,
                    seconds: _theme.skipStep.inSeconds,
                    accent: _theme.accent,
                  ),
                if (_boostActive) _buildBoostIndicator(),
                if (_error != null) _buildError(),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _theme.enableDoubleTapSkip
                        ? _toggleControls
                        : _debouncedToggleControls,
                    onDoubleTapDown: _theme.enableDoubleTapSkip
                        ? (d) => _onDoubleTapDown(d, screenWidth)
                        : null,
                    onLongPressStart: _theme.enableLongPressBoost
                        ? (_) => _onLongPressStart()
                        : null,
                    onLongPressEnd: _theme.enableLongPressBoost
                        ? (_) => _onLongPressEnd()
                        : null,
                    onLongPressCancel:
                        _theme.enableLongPressBoost ? _onLongPressEnd : null,
                    onVerticalDragStart: (d) =>
                        _onVerticalDragStart(d, screenWidth, screenHeight),
                    onVerticalDragUpdate: (d) =>
                        _onVerticalDragUpdate(d, screenHeight),
                    onVerticalDragEnd: _onVerticalDragEnd,
                  ),
                ),
                if (_showGestureHud) _buildGestureHud(),
                if (_isBuffering) _buildBufferingIndicator(),
                if (_error == null && !_inPip) _buildControlsOverlay(),
              ],
            );
          }),
        ));
  }

  /// True while the decoder is starved: the last frame stays on screen and a
  /// spinner sits over it, instead of blanking the surface.
  bool get _isBuffering {
    final c = _controller;
    return _error == null &&
        !_isSwitchingStream &&
        !_swappingSource &&
        c != null &&
        c.value.isInitialized &&
        c.value.isBuffering;
  }

  Widget _buildBufferingIndicator() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.movie.backdropUrl.isNotEmpty ||
              widget.movie.imageUrl.isNotEmpty)
            Positioned.fill(
              // Reuse the loading screen's image cache entry so the hand-off
              // doesn't trigger a second full-size download + decode.
              child: CachedNetworkImage(
                imageUrl: widget.movie.backdropUrl.isNotEmpty
                    ? widget.movie.backdropUrl
                    : widget.movie.imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: Colors.black),
              ),
            ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Loading video…',
                  textAlign: TextAlign.center,
                  style: AppTheme.cardTitle.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final size = c.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const SizedBox.shrink(),
      );
    }
    final videoWidget = SizedBox(
      width: size.width,
      height: size.height,
      child: VideoPlayer(c),
    );
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _applyFitMode(videoWidget, size),
    );
  }

  Widget _applyFitMode(Widget videoWidget, Size videoSize) {
    switch (_fitMode) {
      case PlayerFitMode.contain:
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: videoWidget,
          ),
        );
      case PlayerFitMode.cover:
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: videoWidget,
          ),
        );
      case PlayerFitMode.zoom:
        return ClipRect(
          child: SizedBox.expand(
            child: Transform.scale(
              scale: 1.2,
              child: FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: videoWidget,
              ),
            ),
          ),
        );
      case PlayerFitMode.zoom150:
        return ClipRect(
          child: SizedBox.expand(
            child: Transform.scale(
              scale: 1.5,
              child: FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: videoWidget,
              ),
            ),
          ),
        );
      case PlayerFitMode.zoom200:
        return ClipRect(
          child: SizedBox.expand(
            child: Transform.scale(
              scale: 2.0,
              child: FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: videoWidget,
              ),
            ),
          ),
        );
      case PlayerFitMode.customZoom:
        return ClipRect(
          child: SizedBox.expand(
            child: Transform.scale(
              scale: _customZoomScale,
              child: FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: videoWidget,
              ),
            ),
          ),
        );
      case PlayerFitMode.stretch16x9:
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: videoSize.width,
              height: videoSize.width * 9 / 16,
              child: videoWidget,
            ),
          ),
        );
      case PlayerFitMode.stretch4x3:
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: videoSize.width,
              height: videoSize.width * 3 / 4,
              child: videoWidget,
            ),
          ),
        );
      case PlayerFitMode.fitWidth:
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fitWidth,
            child: videoWidget,
          ),
        );
      case PlayerFitMode.fitHeight:
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fitHeight,
            child: videoWidget,
          ),
        );
      case PlayerFitMode.original:
        return SizedBox.expand(
          child: Align(
            alignment: Alignment.center,
            child: SizedBox.fromSize(
              size: videoSize,
              child: videoWidget,
            ),
          ),
        );
    }
  }

  Widget _buildBoostIndicator() {
    return Positioned(
      top: 90,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (_, v, __) => Opacity(
              opacity: v,
              child: Transform.scale(
                scale: v,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: _theme.accent.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: _theme.accent.withValues(alpha: 0.5),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fast_forward_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${_theme.longPressBoostSpeed.toStringAsFixed(1)}x speed',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGestureHud() {
    if (!_showGestureHud) return const SizedBox.shrink();

    final isBrightness = _activeGestureKind == _GestureKind.brightness;
    final pct = (_gestureValue * 100).round();
    final IconData icon;
    if (isBrightness) {
      icon = _brightness > 0.65
          ? Icons.brightness_7_rounded
          : (_brightness > 0.3
              ? Icons.brightness_6_rounded
              : Icons.brightness_4_rounded);
    } else {
      icon = _muted || _volume == 0
          ? Icons.volume_off_rounded
          : (_volume < 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded);
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment:
              isBrightness ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              builder: (_, scale, __) => Transform.scale(
                scale: scale,
                child: Container(
                  width: 48,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white70, size: 20),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 90,
                        width: 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: LinearProgressIndicator(
                              value: _gestureValue.clamp(0.0, 1.0),
                              backgroundColor: Colors.white24,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(_theme.accent),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final c = _controller;
    final isReady = c != null && c.value.isInitialized;

    final visible = _controlsVisible || !isReady;
    final dur = _theme.controlsAnimDuration;
    final curve = _theme.controlsAnimCurve;

    return KeyedSubtree(
      key: _controlsKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: dur,
              curve: curve,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _theme.controlsBackground.withValues(alpha: 0.85),
                      Colors.transparent,
                      Colors.transparent,
                      _theme.controlsBackground,
                    ],
                    stops: const [0.0, 0.25, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.45,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _buildTopBar(),
              ),
            ),
          ),
          if (isReady) ...[
            Center(
              child: AnimatedScale(
                scale: visible ? 1 : 0.82,
                duration: dur,
                curve: curve,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: dur,
                  curve: curve,
                  child: ExcludeFocusTraversal(
                    excluding: !visible,
                    child: IgnorePointer(
                      ignoring: !visible,
                      child: _buildCenterControls(),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, 1),
                  duration: dur,
                  curve: curve,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: dur,
                    curve: curve,
                    child: ExcludeFocusTraversal(
                      excluding: !visible,
                      child: IgnorePointer(
                        ignoring: !visible,
                        child: _buildBottomBar(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (_subtitlesOn &&
              ((_controller?.value.caption.text.isNotEmpty ?? false) ||
                  _currentSubtitleText.isNotEmpty))
            AnimatedPositioned(
              duration: dur,
              curve: curve,
              left: 24,
              right: 24,
              bottom: visible ? 96 : 32,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currentSubtitleText.isNotEmpty
                          ? _currentSubtitleText
                          : (_controller?.value.caption.text ?? ''),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: _subtitleFontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        shadows: const [
                          Shadow(
                              color: Colors.black,
                              blurRadius: 4,
                              offset: Offset(1, 1)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Skip Intro button ─────────────────────────────────────────────
          if (_showSkipIntro)
            Positioned(
              bottom: visible ? 120 : 32,
              right: 24,
              child: AnimatedOpacity(
                opacity: _showSkipIntro ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: ExcludeFocusTraversal(
                  excluding: !visible,
                  child: TvButton(
                    semanticLabel: 'Skip Intro',
                    borderRadius: 999,
                    onSelect: _skipIntro,
                    child: OutlinedButton.icon(
                      onPressed: _skipIntro,
                      icon: const Icon(Icons.fast_forward_rounded, size: 16),
                      label: const Text('Skip Intro'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.6)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Auto-next Episode overlay ──────────────────────────────────────
          if (_showNextEpisode)
            Positioned(
              bottom: visible ? 120 : 32,
              right: 24,
              child: ExcludeFocusTraversal(
                excluding: !visible,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _theme.accent.withValues(alpha: 0.7),
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Next Episode in $_nextEpisodeCountdown s',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Playing next episode automatically',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Row(
                        children: [
                          TvFocusable(
                            semanticLabel: 'Cancel next episode',
                            borderRadius: 999,
                            onSelect: () {
                              _nextEpisodeTimer?.cancel();
                              setState(() => _showNextEpisode = false);
                            },
                            child: GestureDetector(
                              onTap: () {
                                _nextEpisodeTimer?.cancel();
                                setState(() => _showNextEpisode = false);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 6),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                      fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          TvFocusable(
                            semanticLabel: 'Play next episode now',
                            borderRadius: 999,
                            onSelect: () {
                              _nextEpisodeTimer?.cancel();
                              setState(() => _showNextEpisode = false);
                              _playNextEpisode();
                            },
                            child: GestureDetector(
                              onTap: () {
                                _nextEpisodeTimer?.cancel();
                                setState(() => _showNextEpisode = false);
                                _playNextEpisode();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _theme.accent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Play Now',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_isSwitchingStream)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(AppColors.secondary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Switching to next server…',
                    style: AppTheme.cardTitle
                        .copyWith(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Connecting to alternative stream provider',
                    style: AppTheme.metadata.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          _CircleIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            size: _theme.iconSize - 6,
            color: _theme.iconColor,
            semanticLabel: 'Back',
            onTap: _exitPlayer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.cardTitle.copyWith(color: Colors.white),
                ),
                if (_episodeTitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    _episodeTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.metadata.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        [
                          if (_isSeriesPlayback)
                            'S$_seasonNumber  •  E$_episodeNumber',
                          if (widget.movie.year > 0) '${widget.movie.year}',
                          if (widget.movie.genreString.isNotEmpty)
                            widget.movie.genreString,
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.metadata.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (_resolvedCdn != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.45),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_done_rounded,
                              size: 11,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _resolvedCdn!,
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_theme.showRotationLockButton)
            _CircleIconButton(
              icon: _rotationLocked
                  ? Icons.screen_lock_rotation_rounded
                  : Icons.screen_rotation_rounded,
              size: _theme.iconSize - 6,
              color: _rotationLocked ? _theme.accent : _theme.iconColor,
              semanticLabel:
                  _rotationLocked ? 'Unlock rotation' : 'Lock rotation',
              onTap: _toggleRotationLock,
            ),
          if (_theme.showCastButton)
            _CircleIconButton(
              icon: Icons.cast_rounded,
              size: _theme.iconSize - 6,
              color: _theme.iconColor,
              semanticLabel: 'Cast',
              onTap: _showCastSheet,
            ),
          if (_theme.showMoreButton)
            _CircleIconButton(
              icon: Icons.more_vert_rounded,
              size: _theme.iconSize - 6,
              color: _theme.iconColor,
              semanticLabel: 'More options',
              onTap: _showMoreMenu,
            ),
        ],
      ),
    );
  }

  Widget _buildCenterControls() {
    final playing = _controller?.value.isPlaying ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_theme.showSkipButtons)
          _CircleIconButton(
            icon: Icons.replay_10_rounded,
            size: _theme.iconSize + 4,
            color: _theme.iconColor,
            semanticLabel: 'Rewind',
            onTap: () => _skip(-_theme.skipStep),
          ),
        const SizedBox(width: 28),
        TvFocusable(
          onSelect: _togglePlay,
          semanticLabel: playing ? 'Pause' : 'Play',
          autofocus: _tvLayout,
          scale: 1.08,
          borderRadius: 36,
          child: GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _theme.accent.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _theme.accent.withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 28),
        if (_theme.showSkipButtons)
          _CircleIconButton(
            icon: Icons.forward_10_rounded,
            size: _theme.iconSize + 4,
            color: _theme.iconColor,
            semanticLabel: 'Fast forward',
            onTap: () => _skip(_theme.skipStep),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final v = _controller!.value;
    final position = _isScrubbing
        ? Duration(seconds: _dragPositionSeconds.round())
        : v.position;
    final duration = v.duration;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SeekBar(
            position: position,
            duration: duration,
            buffered: v.buffered.isEmpty ? Duration.zero : v.buffered.last.end,
            theme: _theme,
            onScrubStart: () {
              _isScrubbing = true;
              _dragPositionSeconds = position.inSeconds.toDouble();
              _hideTimer?.cancel();
            },
            onScrubUpdate: (seconds) {
              setState(() => _dragPositionSeconds = seconds);
            },
            onScrubEnd: (seconds) {
              _isScrubbing = false;
              _seekTo(Duration(seconds: seconds.round()));
            },
            onTogglePlay: _togglePlay,
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            final compact = w < 420;
            final tiny = w < 340;

            final time = Flexible(
              child: Text(
                '${_fmt(position)} / ${_fmt(duration)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _timeStyle,
              ),
            );

            final episodeNav = <Widget>[
              if (_showEpisodeNav && !tiny) ...[
                if (_canGoPrevious) ...[
                  _CircleIconButton(
                    icon: Icons.skip_previous_rounded,
                    size: _theme.iconSize - 2,
                    color: _theme.iconColor,
                    semanticLabel: _isSeriesPlayback
                        ? 'Previous episode'
                        : 'Previous title',
                    onTap: _playPreviousEpisode,
                  ),
                  const SizedBox(width: 4),
                ],
                if (_canGoNext)
                  _CircleIconButton(
                    icon: Icons.skip_next_rounded,
                    size: _theme.iconSize - 2,
                    color: _theme.iconColor,
                    semanticLabel:
                        _isSeriesPlayback ? 'Next episode' : 'Next title',
                    onTap: _playNextEpisode,
                  ),
                const SizedBox(width: 6),
              ],
            ];

            final utilities = <Widget>[
              if (_theme.showSubtitleButton && !tiny)
                GestureDetector(
                  onLongPress:
                      _activeSubtitles.length > 1 ? _showSubtitleSheet : null,
                  child: _CircleIconButton(
                    icon: _subtitlesOn
                        ? Icons.closed_caption_rounded
                        : Icons.closed_caption_off_rounded,
                    size: _theme.iconSize - 6,
                    color: _subtitlesOn ? _theme.accent : _theme.iconColor,
                    semanticLabel:
                        _subtitlesOn ? 'Subtitles on' : 'Subtitles off',
                    onTap: () {
                      if (_activeSubtitles.length > 1 && !_subtitlesOn) {
                        _showSubtitleSheet();
                      } else {
                        _toggleSubtitles();
                      }
                    },
                  ),
                ),
              if (_theme.showFitButton && !compact) ...[
                const SizedBox(width: 6),
                _CircleIconButton(
                  icon: _fitModeIcon,
                  size: _theme.iconSize - 6,
                  color: _theme.iconColor,
                  semanticLabel: 'Aspect ratio',
                  onTap: _toggleFit,
                ),
              ],
              if (_theme.showVolumeButton) ...[
                const SizedBox(width: 6),
                _CircleIconButton(
                  icon: _muted || _volume == 0
                      ? Icons.volume_off_rounded
                      : _volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  size: _theme.iconSize - 4,
                  color: _theme.iconColor,
                  semanticLabel: _muted || _volume == 0 ? 'Unmute' : 'Mute',
                  onTap: _toggleMute,
                ),
                if (!compact && w >= 560) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 90,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: _theme.accent,
                        inactiveTrackColor:
                            Colors.white.withValues(alpha: 0.25),
                        thumbColor: _theme.accent,
                        overlayColor: _theme.accent.withValues(alpha: 0.2),
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _muted ? 0 : _volume,
                        onChanged: _setVolume,
                      ),
                    ),
                  ),
                ],
              ],
              if (!tiny) ...[
                const SizedBox(width: 8),
                _PillButton(
                  label: _qualityPillLabel,
                  color: _theme.iconColor,
                  onTap: _pickQuality,
                ),
              ],
              if (_canPickAudio && !compact) ...[
                const SizedBox(width: 8),
                _PillButton(
                  label: _audioPillLabel,
                  color: _theme.iconColor,
                  onTap: _pickAudio,
                ),
              ],
              if (_theme.showSpeedButton && !tiny) ...[
                const SizedBox(width: 8),
                _PillButton(
                  label:
                      '${_speed.toStringAsFixed(_speed.truncateToDouble() == _speed ? 1 : 2)}x',
                  color: _theme.iconColor,
                  onTap: _pickSpeed,
                ),
              ],
            ];

            final fullscreen = <Widget>[
              if (_theme.showFullscreenButton) ...[
                const SizedBox(width: 8),
                _CircleIconButton(
                  icon: _isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  size: _theme.iconSize,
                  color: _theme.iconColor,
                  semanticLabel:
                      _isFullscreen ? 'Exit full screen' : 'Full screen',
                  onTap: _toggleFullscreen,
                ),
              ],
            ];

            // The full strip needs ~660px with every control out; past that it
            // is one row. Below it the utilities move to their own wrapped line
            // so a phone width never overflows — a plain Row cannot shrink
            // fixed-size circles, and the ring/labels are what matters.
            if (w >= 720) {
              return Row(
                children: [
                  time,
                  const Spacer(),
                  ...episodeNav,
                  ...utilities,
                  ...fullscreen,
                ],
              );
            }
            // Narrow: the timer gets its own line and every control sits in the
            // wrapped cluster below it, with prev/next at its trailing edge —
            // beside the clock they read as a stray glyph, not a transport.
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [time]),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 6,
                    children: [...utilities, ...episodeNav, ...fullscreen],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  static const _timeStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w500,
  );

  static String _fmt(Duration d) {
    if (d.inMilliseconds < 0) return '0:00';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 56),
            const SizedBox(height: 16),
            Text('Playback error', style: AppTheme.sectionTitle),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: AppTheme.metadata,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
                FilledButton.icon(
                  onPressed: () {
                    _initRetryCount = 0;
                    _controller?.removeListener(_onTick);
                    _controller?.dispose();
                    _controller = null;
                    _initController();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bug_report_rounded, size: 18),
                  label: const Text('View Logs'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Double-tap skip ripple ─────────────────────────────────────────────────

enum PlayerFitMode {
  contain,
  cover,
  zoom,
  stretch16x9,
  stretch4x3,
  fitWidth,
  fitHeight,
  original,
  zoom150,
  zoom200,
  customZoom,
}

enum _RippleSide { left, right }

enum _GestureKind { brightness, volume }

class _SkipRipple extends StatefulWidget {
  final _RippleSide side;
  final int seconds;
  final Color accent;

  const _SkipRipple({
    super.key,
    required this.side,
    required this.seconds,
    required this.accent,
  });

  @override
  State<_SkipRipple> createState() => _SkipRippleState();
}

class _SkipRippleState extends State<_SkipRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLeft = widget.side == _RippleSide.left;
    return IgnorePointer(
      child: Align(
        alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = Curves.easeOut.transform(_c.value);
            final opacity = (1 - _c.value).clamp(0.0, 1.0);
            return Container(
              width: 140 + t * 40,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
                  end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                  colors: [
                    widget.accent.withValues(alpha: 0.35 * opacity),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Center(
                child: Opacity(
                  opacity: opacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLeft
                            ? Icons.fast_rewind_rounded
                            : Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.seconds}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Custom seek bar with buffered range ────────────────────────────────────

class _SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final CinePlayerTheme theme;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;
  final VoidCallback onTogglePlay;

  const _SeekBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.theme,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onTogglePlay,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  bool _dragging = false;
  double _dragFraction = 0;

  double get _progressFraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    final pos = _dragging
        ? (_dragFraction * total).round()
        : widget.position.inMilliseconds;
    return (pos / total).clamp(0.0, 1.0);
  }

  double get _bufferFraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.buffered.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return TvFocusable(
        semanticLabel: 'Seek',
        scale: 1.02,
        borderRadius: 8,
        onSelect: widget.onTogglePlay,
        // Arrows are otherwise global DirectionalFocusIntent shortcuts; the
        // focused node sees the key first, so the bar can scrub instead of
        // handing the remote's left/right to focus traversal.
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final int direction;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            direction = -1;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            direction = 1;
          } else {
            return KeyEventResult.ignored;
          }
          final total = widget.duration;
          if (total <= Duration.zero) return KeyEventResult.handled;
          var target = widget.position + widget.theme.skipStep * direction;
          if (target < Duration.zero) target = Duration.zero;
          if (target > total) target = total;
          widget.onScrubEnd(target.inSeconds.toDouble());
          return KeyEventResult.handled;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            setState(() {
              _dragging = true;
              _dragFraction = (d.localPosition.dx / width).clamp(0.0, 1.0);
            });
            widget.onScrubStart();
          },
          onHorizontalDragUpdate: (d) {
            setState(() {
              _dragFraction = (d.localPosition.dx / width).clamp(0.0, 1.0);
            });
            widget.onScrubUpdate(
              _dragFraction * widget.duration.inSeconds.toDouble(),
            );
          },
          onHorizontalDragEnd: (_) {
            widget.onScrubEnd(
                _dragFraction * widget.duration.inSeconds.toDouble());
            setState(() => _dragging = false);
          },
          onTapDown: (d) {
            final f = (d.localPosition.dx / width).clamp(0.0, 1.0);
            widget.onScrubStart();
            widget.onScrubEnd(f * widget.duration.inSeconds.toDouble());
          },
          child: SizedBox(
            height: 28,
            child: Center(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: widget.theme.seekBarHeight,
                    decoration: BoxDecoration(
                      color: widget.theme.trackColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: _bufferFraction,
                    child: Container(
                      height: widget.theme.seekBarHeight,
                      decoration: BoxDecoration(
                        color: widget.theme.bufferedColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: _progressFraction,
                    child: Container(
                      height: widget.theme.seekBarHeight + (_dragging ? 2 : 0),
                      decoration: BoxDecoration(
                        color: widget.theme.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (width * _progressFraction) -
                        widget.theme.seekBarThumb / 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: widget.theme.seekBarThumb * (_dragging ? 1.4 : 1),
                      height: widget.theme.seekBarThumb * (_dragging ? 1.4 : 1),
                      decoration: BoxDecoration(
                        color: widget.theme.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.theme.accent.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ─── Small UI helpers ───────────────────────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;

  const _CircleIconButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onTap,
      semanticLabel: semanticLabel,
      scale: 1.12,
      borderRadius: (size + 16) / 2,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size + 16,
          height: size + 16,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: size),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onTap,
      semanticLabel: label,
      scale: 1.08,
      borderRadius: 999,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
