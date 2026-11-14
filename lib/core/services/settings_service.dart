import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_form.dart';
import 'trakt_service.dart';

enum VideoQuality { auto, uhd4k, fullHd1080, hd720, sd480, highest }

/// Order the quality pickers list their options in.
///
/// [VideoQuality.highest] is appended to the enum rather than slotted in after
/// `auto`, because the pickers persist `index` to SharedPreferences — reshuffling
/// the existing members would silently change what a saved setting means.
const List<VideoQuality> videoQualityChoices = [
  VideoQuality.auto,
  VideoQuality.highest,
  VideoQuality.uhd4k,
  VideoQuality.fullHd1080,
  VideoQuality.hd720,
  VideoQuality.sd480,
];

enum SubtitleSize { small, medium, large }

/// What the download queue does about video quality.
///
/// [ask] is the default: the app shows the quality sheet each time a download
/// is started and uses what was picked. Every other member pins the quality so
/// downloads begin without a dialog.
enum DownloadQuality { ask, highest, uhd4k, fullHd1080, hd720, sd480 }

const List<DownloadQuality> downloadQualityChoices = [
  DownloadQuality.ask,
  DownloadQuality.highest,
  DownloadQuality.uhd4k,
  DownloadQuality.fullHd1080,
  DownloadQuality.hd720,
  DownloadQuality.sd480,
];

extension DownloadQualityX on DownloadQuality {
  String get label {
    switch (this) {
      case DownloadQuality.ask:
        return 'Ask first';
      case DownloadQuality.highest:
        return 'Highest available';
      case DownloadQuality.uhd4k:
        return '4K UHD';
      case DownloadQuality.fullHd1080:
        return '1080p Full HD';
      case DownloadQuality.hd720:
        return '720p HD';
      case DownloadQuality.sd480:
        return '480p SD';
    }
  }

  bool get asksFirst => this == DownloadQuality.ask;

  /// Encoder target for this pin. [ask] still needs a fallback for the paths
  /// that cannot show a sheet (auto-download of the next episode while
  /// playing), so it lands on 1080p.
  VideoQuality get videoQuality {
    switch (this) {
      case DownloadQuality.ask:
      case DownloadQuality.fullHd1080:
        return VideoQuality.fullHd1080;
      case DownloadQuality.highest:
        return VideoQuality.highest;
      case DownloadQuality.uhd4k:
        return VideoQuality.uhd4k;
      case DownloadQuality.hd720:
        return VideoQuality.hd720;
      case DownloadQuality.sd480:
        return VideoQuality.sd480;
    }
  }
}

enum AppLanguage { english, spanish, french, german, japanese }

extension VideoQualityX on VideoQuality {
  String get label {
    switch (this) {
      case VideoQuality.auto:
        return 'Auto';
      case VideoQuality.highest:
        return 'Highest available';
      case VideoQuality.uhd4k:
        return '4K UHD';
      case VideoQuality.fullHd1080:
        return '1080p Full HD';
      case VideoQuality.hd720:
        return '720p HD';
      case VideoQuality.sd480:
        return '480p SD';
    }
  }
}

extension SubtitleSizeX on SubtitleSize {
  String get label {
    switch (this) {
      case SubtitleSize.small:
        return 'Small';
      case SubtitleSize.medium:
        return 'Medium';
      case SubtitleSize.large:
        return 'Large';
    }
  }
}

class SettingsService extends ChangeNotifier {
  SharedPreferences? _prefs;

  // ── Playback ─────────────────────────────────────────────────────────────
  VideoQuality _streamQuality = VideoQuality.auto;
  DownloadQuality _downloadQuality = DownloadQuality.ask;
  bool _autoPlay = true;
  bool _skipIntro = true;
  bool _autoNextEpisode = true;
  bool _useExternalPlayer = false;
  double _playbackSpeed = 1.0;
  bool _quickPlay = true;
  int _parallelSourceCount = 2;
  bool _enablePip = true;

  // ── Subtitles ────────────────────────────────────────────────────────────
  bool _subtitlesEnabled = false;
  String _subtitleLanguage = 'English';
  SubtitleSize _subtitleSize = SubtitleSize.medium;

  /// Preferred audio rendition language code (e.g. "en"). Empty = auto.
  String _audioLanguage = '';

  // ── Downloads ────────────────────────────────────────────────────────────
  bool _downloadOnWifiOnly = true;
  bool _autoDownloadNextEpisode = false;
  bool _sequentialDownloads = false;
  int _maxStorageGB = 8;

  // ── Notifications ────────────────────────────────────────────────────────
  bool _notificationsEnabled = true;
  bool _notifyNewEpisodes = true;
  bool _notifyNewMovies = true;
  bool _notifyPremiere = true;
  bool _notifyDownloads = true;
  bool _notifyWatchlist = true;
  bool _notifyContinueWatching = true;

  // ── Trakt Sync ───────────────────────────────────────────────────────────
  bool _syncWatchHistory = true;
  bool _syncWatchlist = true;
  bool _scrobbleAutomatically = true;

  // ── Display / Theme ──────────────────────────────────────────────────────
  bool _useOledBlack = false;
  bool _showBadges = true;
  bool _showRatings = true;
  bool _showRuntime = true;
  String _contentLanguage = 'English';
  double _playerBrightness = 0.40;
  double _densityLevel = 0;
  double _posterRadius = 16;

  // ── Layout ───────────────────────────────────────────────────────────────
  /// 'auto' until the first-launch prompt is answered, then 'phone' / 'tablet'
  /// / 'tv'. The single source of truth for the shell, card sizing and D-pad
  /// bindings — the old `useTvLayout` switch is just `== 'tv'`.
  String _layoutChoice = 'auto';

  // ── Privacy ──────────────────────────────────────────────────────────────
  bool _crashReportingEnabled = true;
  bool _personalizedRecommendations = true;

  // ── Trakt API Credentials ────────────────────────────────────────────────
  String _traktClientId = '';
  String _traktClientSecret = '';

  // Getters
  VideoQuality get streamQuality => _streamQuality;
  DownloadQuality get downloadQuality => _downloadQuality;
  bool get autoPlay => _autoPlay;
  bool get skipIntro => _skipIntro;
  bool get autoNextEpisode => _autoNextEpisode;
  bool get useExternalPlayer => _useExternalPlayer;
  double get playbackSpeed => _playbackSpeed;
  bool get quickPlay => _quickPlay;
  int get parallelSourceCount => _parallelSourceCount;
  bool get enablePip => _enablePip;
  bool get subtitlesEnabled => _subtitlesEnabled;
  String get subtitleLanguage => _subtitleLanguage;
  SubtitleSize get subtitleSize => _subtitleSize;
  String get audioLanguage => _audioLanguage;
  bool get downloadOnWifiOnly => _downloadOnWifiOnly;
  bool get autoDownloadNextEpisode => _autoDownloadNextEpisode;
  bool get sequentialDownloads => _sequentialDownloads;
  int get maxStorageGB => _maxStorageGB;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get notifyNewEpisodes => _notifyNewEpisodes;
  bool get notifyNewMovies => _notifyNewMovies;
  bool get notifyPremiere => _notifyPremiere;
  bool get notifyDownloads => _notifyDownloads;
  bool get notifyWatchlist => _notifyWatchlist;
  bool get notifyContinueWatching => _notifyContinueWatching;
  bool get syncWatchHistory => _syncWatchHistory;
  bool get syncWatchlist => _syncWatchlist;
  bool get scrobbleAutomatically => _scrobbleAutomatically;
  bool get useOledBlack => _useOledBlack;
  bool get showBadges => _showBadges;
  bool get showRatings => _showRatings;
  bool get showRuntime => _showRuntime;
  String get contentLanguage => _contentLanguage;
  double get playerBrightness => _playerBrightness;
  double get densityLevel => _densityLevel;
  double get posterRadius => _posterRadius;
  bool get useTvLayout => _layoutChoice == 'tv';
  String get layoutChoice => _layoutChoice;

  /// True once the first-launch prompt has been answered, so it never asks
  /// again — including for someone who picked the option auto-detect would have
  /// picked anyway.
  bool get hasChosenLayout => _layoutChoice != 'auto';

  /// The form factor the user pinned, or `null` to leave it to the canvas.
  DeviceForm? get forcedLayout => deviceFormFromName(_layoutChoice);
  bool get crashReportingEnabled => _crashReportingEnabled;
  bool get personalizedRecommendations => _personalizedRecommendations;
  String get traktClientId => _traktClientId;
  String get traktClientSecret => _traktClientSecret;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _loadAll();
  }

  /// Reads a double tolerantly. Older builds dispatched persistence on runtime
  /// type, so a whole-number double (e.g. 16.0) could have been stored via
  /// setInt on web. Fall back to the int representation when getDouble is null.
  double _readDouble(SharedPreferences p, String key, double fallback) {
    final d = p.getDouble(key);
    if (d != null) return d;
    final i = p.getInt(key);
    return i != null ? i.toDouble() : fallback;
  }

  /// Downloads used to store a bare [VideoQuality] index, including `auto`
  /// (index 0) which no longer exists as a download mode. Map a legacy value
  /// across instead of resetting the user's pin.
  DownloadQuality _readDownloadQuality(SharedPreferences p) {
    final mode = p.getInt('downloadQualityMode');
    if (mode != null && mode >= 0 && mode < DownloadQuality.values.length) {
      return DownloadQuality.values[mode];
    }
    final legacy = p.getInt('downloadQuality');
    if (legacy == null || legacy < 0 || legacy >= VideoQuality.values.length) {
      return DownloadQuality.ask;
    }
    switch (VideoQuality.values[legacy]) {
      case VideoQuality.auto:
        return DownloadQuality.ask;
      case VideoQuality.uhd4k:
        return DownloadQuality.uhd4k;
      case VideoQuality.fullHd1080:
        return DownloadQuality.fullHd1080;
      case VideoQuality.hd720:
        return DownloadQuality.hd720;
      case VideoQuality.sd480:
        return DownloadQuality.sd480;
      case VideoQuality.highest:
        return DownloadQuality.highest;
    }
  }

  void _loadAll() {
    final p = _prefs!;
    _streamQuality = VideoQuality.values[p.getInt('streamQuality') ?? 0];
    _downloadQuality = _readDownloadQuality(p);
    _autoPlay = p.getBool('autoPlay') ?? true;
    _skipIntro = p.getBool('skipIntro') ?? true;
    _autoNextEpisode = p.getBool('autoNextEpisode') ?? true;
    _useExternalPlayer = p.getBool('useExternalPlayer') ?? false;
    _playbackSpeed = _readDouble(p, 'playbackSpeed', 1.0);
    _quickPlay = p.getBool('quickPlay') ?? true;
    _parallelSourceCount = p.getInt('parallelSourceCount') ?? 2;
    _enablePip = p.getBool('enablePip') ?? true;
    _subtitlesEnabled = p.getBool('subtitlesEnabled') ?? false;
    _subtitleLanguage = p.getString('subtitleLanguage') ?? 'English';
    _subtitleSize = SubtitleSize.values[p.getInt('subtitleSize') ?? 1];
    _audioLanguage = p.getString('audioLanguage') ?? '';
    _downloadOnWifiOnly = p.getBool('downloadOnWifiOnly') ?? true;
    _autoDownloadNextEpisode = p.getBool('autoDownloadNextEpisode') ?? false;
    _sequentialDownloads = p.getBool('sequentialDownloads') ?? false;
    _maxStorageGB = p.getInt('maxStorageGB') ?? 8;
    _notificationsEnabled = p.getBool('notificationsEnabled') ?? true;
    _notifyNewEpisodes = p.getBool('notifyNewEpisodes') ?? true;
    _notifyNewMovies = p.getBool('notifyNewMovies') ?? true;
    _notifyPremiere = p.getBool('notifyPremiere') ?? true;
    _notifyDownloads = p.getBool('notifyDownloads') ?? true;
    _notifyWatchlist = p.getBool('notifyWatchlist') ?? true;
    _notifyContinueWatching = p.getBool('notifyContinueWatching') ?? true;
    _syncWatchHistory = p.getBool('syncWatchHistory') ?? true;
    _syncWatchlist = p.getBool('syncWatchlist') ?? true;
    _scrobbleAutomatically = p.getBool('scrobbleAutomatically') ?? true;
    _useOledBlack = p.getBool('useOledBlack') ?? false;
    _showBadges = p.getBool('showBadges') ?? true;
    _showRatings = p.getBool('showRatings') ?? true;
    _showRuntime = p.getBool('showRuntime') ?? true;
    _contentLanguage = p.getString('contentLanguage') ?? 'English';
    _playerBrightness = _readDouble(p, 'playerBrightness', 0.40);
    _densityLevel = _readDouble(p, 'densityLevel', 0);
    _posterRadius = _readDouble(p, 'posterRadius', 16);
    // An install made before the chooser only ever had the couch switch, so
    // carry it across as that choice instead of re-asking.
    _layoutChoice = p.getString('layoutChoice') ??
        ((p.getBool('useTvLayout') ?? false) ? 'tv' : 'auto');
    forceDeviceForm(forcedLayout);
    _crashReportingEnabled = p.getBool('crashReportingEnabled') ?? true;
    _personalizedRecommendations =
        p.getBool('personalizedRecommendations') ?? true;
    _traktClientId = p.getString('traktClientId') ?? '';
    _traktClientSecret = p.getString('traktClientSecret') ?? '';
    if (_traktClientId.isNotEmpty) TraktService.customClientId = _traktClientId;
    if (_traktClientSecret.isNotEmpty) {
      TraktService.customClientSecret = _traktClientSecret;
    }
    notifyListeners();
  }

  // Typed persist helpers. Using explicit types (instead of a single dynamic
  // dispatcher) avoids the web/dart2js int-vs-double ambiguity, where a whole
  // number like 16.0 satisfies `is int` and would be stored via setInt, then
  // read back as null by getDouble. Each helper notifies immediately for a
  // responsive UI, then awaits the disk write and logs failures.
  void _persistBool(String key, bool value) {
    notifyListeners();
    _write(() => _prefs?.setBool(key, value), key);
  }

  void _persistInt(String key, int value) {
    notifyListeners();
    _write(() => _prefs?.setInt(key, value), key);
  }

  void _persistDouble(String key, double value) {
    notifyListeners();
    _write(() => _prefs?.setDouble(key, value), key);
  }

  void _persistString(String key, String value) {
    notifyListeners();
    _write(() => _prefs?.setString(key, value), key);
  }

  Future<void> _write(Future<bool>? Function() op, String key) async {
    if (_prefs == null) return;
    try {
      await op();
    } catch (e) {
      debugPrint('SettingsService: failed to save $key: $e');
    }
  }

  // Setters
  void setStreamQuality(VideoQuality v) {
    _streamQuality = v;
    _persistInt('streamQuality', v.index);
  }

  void setDownloadQuality(DownloadQuality v) {
    _downloadQuality = v;
    _persistInt('downloadQualityMode', v.index);
  }

  void setAutoPlay(bool v) {
    _autoPlay = v;
    _persistBool('autoPlay', v);
  }

  void setSkipIntro(bool v) {
    _skipIntro = v;
    _persistBool('skipIntro', v);
  }

  void setAutoNextEpisode(bool v) {
    _autoNextEpisode = v;
    _persistBool('autoNextEpisode', v);
  }

  void setUseExternalPlayer(bool v) {
    _useExternalPlayer = v;
    _persistBool('useExternalPlayer', v);
  }

  void setPlaybackSpeed(double v) {
    _playbackSpeed = v;
    _persistDouble('playbackSpeed', v);
  }

  void setQuickPlay(bool v) {
    _quickPlay = v;
    _persistBool('quickPlay', v);
  }

  void setParallelSourceCount(int v) {
    _parallelSourceCount = v.clamp(1, 5);
    _persistInt('parallelSourceCount', _parallelSourceCount);
  }

  void setEnablePip(bool v) {
    _enablePip = v;
    _persistBool('enablePip', v);
  }

  void setSubtitlesEnabled(bool v) {
    _subtitlesEnabled = v;
    _persistBool('subtitlesEnabled', v);
  }

  void setSubtitleLanguage(String v) {
    _subtitleLanguage = v;
    _persistString('subtitleLanguage', v);
  }

  void setSubtitleSize(SubtitleSize v) {
    _subtitleSize = v;
    _persistInt('subtitleSize', v.index);
  }

  void setAudioLanguage(String v) {
    _audioLanguage = v;
    _persistString('audioLanguage', v);
  }

  void setDownloadOnWifiOnly(bool v) {
    _downloadOnWifiOnly = v;
    _persistBool('downloadOnWifiOnly', v);
  }

  void setAutoDownloadNextEpisode(bool v) {
    _autoDownloadNextEpisode = v;
    _persistBool('autoDownloadNextEpisode', v);
  }

  void setSequentialDownloads(bool v) {
    _sequentialDownloads = v;
    _persistBool('sequentialDownloads', v);
  }

  void setMaxStorageGB(int v) {
    _maxStorageGB = v;
    _persistInt('maxStorageGB', v);
  }

  void setNotificationsEnabled(bool v) {
    _notificationsEnabled = v;
    _persistBool('notificationsEnabled', v);
  }

  void setNotifyNewEpisodes(bool v) {
    _notifyNewEpisodes = v;
    _persistBool('notifyNewEpisodes', v);
  }

  void setNotifyNewMovies(bool v) {
    _notifyNewMovies = v;
    _persistBool('notifyNewMovies', v);
  }

  void setNotifyPremiere(bool v) {
    _notifyPremiere = v;
    _persistBool('notifyPremiere', v);
  }

  void setNotifyDownloads(bool v) {
    _notifyDownloads = v;
    _persistBool('notifyDownloads', v);
  }

  void setNotifyWatchlist(bool v) {
    _notifyWatchlist = v;
    _persistBool('notifyWatchlist', v);
  }

  void setNotifyContinueWatching(bool v) {
    _notifyContinueWatching = v;
    _persistBool('notifyContinueWatching', v);
  }

  void setSyncWatchHistory(bool v) {
    _syncWatchHistory = v;
    _persistBool('syncWatchHistory', v);
  }

  void setSyncWatchlist(bool v) {
    _syncWatchlist = v;
    _persistBool('syncWatchlist', v);
  }

  void setScrobbleAutomatically(bool v) {
    _scrobbleAutomatically = v;
    _persistBool('scrobbleAutomatically', v);
  }

  void setUseOledBlack(bool v) {
    _useOledBlack = v;
    _persistBool('useOledBlack', v);
  }

  void setShowBadges(bool v) {
    _showBadges = v;
    _persistBool('showBadges', v);
  }

  void setShowRatings(bool v) {
    _showRatings = v;
    _persistBool('showRatings', v);
  }

  void setShowRuntime(bool v) {
    _showRuntime = v;
    _persistBool('showRuntime', v);
  }

  void setContentLanguage(String v) {
    _contentLanguage = v;
    _persistString('contentLanguage', v);
  }

  void setPlayerBrightness(double v) {
    _playerBrightness = v.clamp(0.05, 1.0);
    _persistDouble('playerBrightness', _playerBrightness);
  }

  void setDensityLevel(double v) {
    _densityLevel = v;
    _persistDouble('densityLevel', v);
  }

  void setPosterRadius(double v) {
    _posterRadius = v;
    _persistDouble('posterRadius', v);
  }

  /// Pin the interface to a form factor, or pass `null` to let the canvas
  /// decide again. Takes effect immediately: the shell, the card metrics and
  /// the D-pad bindings all read this.
  void chooseLayout(DeviceForm? form) {
    final next = form?.name ?? 'auto';
    if (_layoutChoice == next) return;
    _layoutChoice = next;
    forceDeviceForm(form);
    _persistString('layoutChoice', next);
  }

  void setCrashReportingEnabled(bool v) {
    _crashReportingEnabled = v;
    _persistBool('crashReportingEnabled', v);
  }

  void setPersonalizedRecommendations(bool v) {
    _personalizedRecommendations = v;
    _persistBool('personalizedRecommendations', v);
  }

  void setTraktClientId(String v) {
    _traktClientId = v;
    TraktService.customClientId = v;
    _persistString('traktClientId', v);
  }

  void setTraktClientSecret(String v) {
    _traktClientSecret = v;
    TraktService.customClientSecret = v;
    _persistString('traktClientSecret', v);
  }

  Future<void> resetAll() async {
    await _prefs?.clear();
    _loadAll();
  }
}
