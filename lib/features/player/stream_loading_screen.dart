import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/models/movie.dart';
import '../../core/services/media_delivery_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/video_service.dart';
import '../../core/services/diagnostic_service.dart';
import '../settings/diagnostics_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/tv_focus.dart';
import 'video_player_screen.dart';

class StreamLoadingScreen extends StatefulWidget {
  final Movie movie;
  final int? season;
  final int? episode;
  final bool isTrailer;

  const StreamLoadingScreen({
    super.key,
    required this.movie,
    this.season,
    this.episode,
    this.isTrailer = false,
  });

  @override
  State<StreamLoadingScreen> createState() => _StreamLoadingScreenState();
}

class _StreamLoadingScreenState extends State<StreamLoadingScreen> {
  bool _hasError = false;
  String? _error;
  String _statusText = 'Preparing stream…';
  int _providerIndex = 0;

  static const List<String> _providerNames = [
    'Source 1',
    'Source 2',
    'Source 3',
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _error = null;
      _providerIndex = 0;
      _statusText = 'Preparing stream…';
    });

    _log('Starting stream resolution for "${widget.movie.title}" '
        'tmdbId=${widget.movie.tmdbId}');

    // Rotate the status text every ~8 s so users know progress.
    final ticker = _startStatusTicker();

    try {
      final delivery = context.read<MediaDeliveryService>();
      final source = await delivery.resolveStream(
        widget.movie,
        season: widget.season,
        episode: widget.episode,
      );

      ticker.cancel();
      _log('✅ Stream resolved: url=${source.url} assetPath=${source.assetPath} '
          'isOffline=${source.isOffline} cdn=${source.cdn}');

      if (!mounted) return;
      if (source.cdn != null) {
        setState(() => _statusText = 'Connected to ${source.cdn}');
      }
      final settings = context.read<SettingsService>();

      // ── External player handoff ──────────────────────────────────────────
      if (settings.useExternalPlayer && source.url != null && source.url!.isNotEmpty) {
        _log('📤 Handing off to external player: ${source.url}');
        final hdrs = source.headers;
        final launched = await VideoService.openInExternalPlayer(
          source.url!,
          headers: (hdrs?.isNotEmpty ?? false) ? hdrs : null,
          title: widget.movie.title,
        );
        if (!mounted) return;
        if (launched) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Opening "${widget.movie.title}" in your media player…',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (source.cdn != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Server: ${source.cdn}',
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          _log('⚠️ External player launch failed — falling back to CinePlayer.');
          _pushVideoPlayerScreen(settings, source);
        }
        return;
      }

      _pushVideoPlayerScreen(settings, source);
    } catch (e, st) {
      ticker.cancel();
      _log('❌ Stream resolution failed: $e', level: LogLevel.error);
      DiagnosticService.instance.error(
        'StreamLoading',
        'Stream resolution failed for "${widget.movie.title}" (tmdbId=${widget.movie.tmdbId})',
        e,
        st,
      );
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _error = e.toString();
      });
    }
  }

  void _pushVideoPlayerScreen(SettingsService settings, PlayableSource source) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => VideoPlayerScreen(
          movie: widget.movie,
          videoUrl: source.url,
          assetPath: source.assetPath,
          headers: source.headers,
          cdn: source.cdn,
          season: widget.season,
          episode: widget.episode,
          subtitles: source.subtitles,
          audioTracks: source.audioTracks,
          masterPlaylist: source.masterPlaylist,
          isTrailer: widget.isTrailer,
          theme: CinePlayerTheme(
            autoPlay: settings.autoPlay,
            defaultSpeed: settings.playbackSpeed,
            subtitlesOn: settings.subtitlesEnabled,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  _Cancellable _startStatusTicker() {
    final c = _Cancellable();
    _advanceStatus(c);
    return c;
  }

  Future<void> _advanceStatus(_Cancellable c) async {
    final steps = [
      (5, 'Connecting to source…'),
      (10, 'Loading player…'),
      (18, 'Intercepting stream…'),
      (25, 'Trying next source…'),
      (32, 'Almost there…'),
    ];
    for (final step in steps) {
      await Future<void>.delayed(Duration(seconds: step.$1));
      if (c.cancelled || !mounted) return;
      setState(() {
        _statusText = step.$2;
        _providerIndex =
            (steps.indexOf(step) ~/ 2).clamp(0, _providerNames.length - 1);
      });
      _log('Status → ${step.$2}');
    }
  }

  void _log(String msg, {LogLevel level = LogLevel.info}) {
    DiagnosticService.instance.log('StreamLoading', msg, level: level);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop
          if (movie.backdropUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: movie.backdropUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Scrim
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.96),
                  ],
                ),
              ),
            ),
          ),
          // Back button
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: TvFocusable(
                autofocus: true,
                onSelect: () => Navigator.of(context).pop(),
                semanticLabel: 'Go back',
                scale: 1.06,
                borderRadius: 20,
                child: _BackBtn(onTap: () => Navigator.of(context).pop()),
              ),
            ),
          ),
          // Content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _hasError ? _buildError() : _buildLoading(movie),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(Movie movie) {
    return Column(
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
        const SizedBox(height: 20),
        // Live status line
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            _statusText,
            key: ValueKey(_statusText),
            style: AppTheme.metadata.copyWith(
              color: AppColors.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Provider indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_providerNames.length, (i) {
            final active = i == _providerIndex;
            final done = i < _providerIndex;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: active ? 20 : 8,
                height: 4,
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : active
                          ? AppColors.secondary
                          : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            color: AppColors.secondary, size: 56),
        const SizedBox(height: 20),
        Text(
          'Playback Failed',
          style: AppTheme.heroTitle.copyWith(fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _error != null && _error!.isNotEmpty
              ? _error!
              : 'Could not load a playable stream for this title.',
          style: AppTheme.metadata.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Go Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _resolve,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DiagnosticsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.bug_report_rounded,
                  size: 16, color: AppColors.secondary),
              label: const Text(
                'View Diagnostic Logs',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () =>
                  DiagnosticService.instance.copyReportToClipboard(context),
              icon: const Icon(Icons.copy_rounded,
                  size: 16, color: Colors.white70),
              label: const Text(
                'Copy Logs',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Cancellable {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class _BackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _BackBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onTap,
      semanticLabel: 'Back',
      scale: 1.1,
      borderRadius: 20,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.15), width: 1),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
