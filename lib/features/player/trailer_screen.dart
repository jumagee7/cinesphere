import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/services/settings_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/tv_focus.dart';

/// Full-screen in-app trailer playback.
///
/// YouTube's native iframe chrome is suppressed ([YoutubePlayerParams
/// .showControls] = false) and the iframe is told to ignore pointer input
/// ([PointerEvents.none]) so this screen's own control layer is the only one
/// present and reliably receives taps/drags — including on web, where a
/// platform-view iframe would otherwise swallow them.
class TrailerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String? backdropUrl;

  const TrailerScreen({
    super.key,
    required this.videoId,
    required this.title,
    this.backdropUrl,
  });

  @override
  State<TrailerScreen> createState() => _TrailerScreenState();
}

class _TrailerScreenState extends State<TrailerScreen> {
  static const _hideDelay = Duration(milliseconds: 3200);
  static const _seekStep = Duration(seconds: 10);
  static const _rates = <double>[0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  late final YoutubePlayerController _controller;

  final List<StreamSubscription<dynamic>> _subs = [];

  PlayerState _state = PlayerState.unStarted;
  YoutubeError _error = YoutubeError.none;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _loadedFraction = 0;
  bool _isMuted = false;
  double _rate = 1.0;
  bool _isFullscreen = false;

  /// YouTube paints its own endscreen (channel logo + "More videos") over the
  /// iframe when a clip finishes, which no embed parameter reliably suppresses.
  /// We rewind + pause the moment it ends and show our own replay card instead.
  bool _ended = false;

  /// True once the clip has actually played, so a spurious load-time `ended`
  /// event can't stop the video.
  bool _didPlay = false;

  bool _showControls = true;
  final GlobalKey _chromeKey = GlobalKey();
  Timer? _hideTimer;

  /// YouTube's `controls=0` is only honored after the first few seconds: the
  /// embed opens with its own title bar, channel avatar, a large play/pause and
  /// a progress bar painted over the video, and they auto-dismiss on YouTube's
  /// own schedule. No pointer event reaches the iframe to rush that up, so the
  /// frame is covered with the clip's thumbnail until they're gone.
  bool _chromeCovered = true;
  Timer? _chromeTimer;
  static const _chromeGrace = Duration(milliseconds: 4500);

  /// Non-null while the user drags the progress bar; holds the previewed
  /// fraction so the thumb tracks the finger instead of the video clock.
  double? _scrubFraction;
  String? _seekFeedback;
  Timer? _seekFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: false,
        showControls: false,
        showFullscreenButton: false,
        enableKeyboard: false,
        pointerEvents: PointerEvents.none,
        playsInline: true,
        strictRelatedVideos: true,
        showVideoAnnotations: false,
      ),
    );

    _subs.add(_controller.stream.listen(_onValue));
    _subs.add(_controller.videoStateStream.listen(_onVideoState));
    // Arming here as well as on the first `playing` event means a lost or never
    // arriving state event can't leave the cover stuck over the video.
    _armChromeCover();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _chromeTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    // NOTE: _controller.dispose() is deliberately not called — the underlying
    // webview crashes on teardown for this plugin version.
    super.dispose();
  }

  void _onValue(YoutubePlayerValue value) {
    if (!mounted) return;
    if (value.playerState == PlayerState.playing) {
      _didPlay = true;
      _armChromeCover();
    }
    setState(() {
      _state = value.playerState;
      _error = value.error;
      _rate = value.playbackRate;
      final metaDuration = value.metaData.duration;
      if (metaDuration > Duration.zero) _duration = metaDuration;
    });
    // The plugin reads getDuration() exactly once, on the first `playing`
    // event, and YouTube returns 0 until the clip's metadata has loaded. Its
    // own "same video id" guard then blocks every later attempt, so the total
    // stays 0 forever and the progress bar has no range. Ask directly.
    if (_duration == Duration.zero && _error == YoutubeError.none) {
      _resolveDuration();
    }
    // The iframe API can report `ended` transiently during load, so only trust
    // it once the clip has genuinely started playing.
    if (_didPlay && value.playerState == PlayerState.ended && !_ended) {
      _ended = true;
      // stopVideo unloads the iframe back to its poster frame, which is the
      // only reliable way to clear YouTube's endscreen overlay.
      _controller.stopVideo();
      setState(() {
        _position = _duration;
        _showControls = true;
      });
      _hideTimer?.cancel();
    }
  }

  bool _resolvingDuration = false;

  Future<void> _resolveDuration() async {
    if (_resolvingDuration) return;
    _resolvingDuration = true;
    try {
      for (var attempt = 0; attempt < 20; attempt++) {
        if (!mounted || _duration > Duration.zero) return;
        final seconds = await _controller.duration;
        if (!mounted) return;
        if (seconds > 0) {
          setState(() => _duration = Duration(seconds: seconds.round()));
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } catch (_) {
      // A failed probe just means the bar stays range-less until the next
      // state change retries it.
    } finally {
      _resolvingDuration = false;
    }
  }

  void _onVideoState(YoutubeVideoState state) {
    if (!mounted) return;
    if (_scrubFraction != null) {
      setState(() => _loadedFraction = state.loadedFraction);
      return;
    }
    setState(() {
      _position = state.position;
      _loadedFraction = state.loadedFraction;
    });
  }

  // ── Control visibility ─────────────────────────────────────────────────────

  bool get _isPlaying => _state == PlayerState.playing;

  void _revealControls() {
    if (!_showControls) setState(() => _showControls = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_isPlaying) return;
    _hideTimer = Timer(_hideDelay, () {
      if (mounted &&
          _isPlaying &&
          _scrubFraction == null &&
          !_focusInChrome()) {
        setState(() => _showControls = false);
      }
    });
  }

  /// Auto-hiding while a remote's ring rests on a control would leave the
  /// ring on an invisible button — keep the chrome up while it has focus.
  bool _focusInChrome() {
    final focused = FocusManager.instance.primaryFocus?.context;
    final root = _chromeKey.currentContext;
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

  void _armChromeCover() {
    if (!_chromeCovered || _chromeTimer != null) return;
    _chromeTimer = Timer(_chromeGrace, () {
      _chromeTimer = null;
      if (!mounted) return;
      setState(() => _chromeCovered = false);
      _revealControls();
    });
  }

  Widget _buildChromeCover() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 450),
          opacity: _chromeCovered ? 1 : 0,
          child: ColoredBox(
            color: Colors.black,
            child: Image.network(
              YoutubePlayerController.getThumbnail(videoId: widget.videoId),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  void _togglePlay() {
    switch (_state) {
      case PlayerState.playing:
        _controller.pauseVideo();
      case PlayerState.ended:
        _restart();
      default:
        if (_ended) {
          _restart();
        } else {
          _controller.playVideo();
        }
    }
    _revealControls();
  }

  void _restart() {
    _ended = false;
    _didPlay = false;
    // loadVideoById reloads the iframe, so YouTube replays its intro chrome too.
    _chromeTimer?.cancel();
    _chromeTimer = null;
    setState(() {
      _position = Duration.zero;
      _chromeCovered = true;
    });
    _controller.loadVideoById(videoId: widget.videoId);
  }

  void _seekBy(Duration delta) {
    if (_ended) return;
    var target = _position + delta;
    if (target.isNegative) target = Duration.zero;
    final total = _duration.inMilliseconds;
    // Clamp to the clip only once its length is known; a still-resolving
    // duration must never turn the button into a no-op.
    if (total > 0 && target.inMilliseconds > total) {
      target = Duration(milliseconds: total);
    }
    _controller.seekTo(
      seconds: target.inMilliseconds / 1000.0,
      allowSeekAhead: true,
    );
    setState(() => _position = target);
    _flashSeek(delta.isNegative ? '-10s' : '+10s');
    _revealControls();
  }

  void _flashSeek(String label) {
    setState(() => _seekFeedback = label);
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _seekFeedback = null);
    });
  }

  void _commitScrub(double fraction) {
    final total = _duration.inMilliseconds;
    if (total > 0 && !_ended) {
      final target = Duration(milliseconds: (fraction * total).round());
      _controller.seekTo(
        seconds: target.inMilliseconds / 1000.0,
        allowSeekAhead: true,
      );
      setState(() => _position = target);
    }
  }

  void _toggleMute() {
    if (_isMuted) {
      _controller.unMute();
    } else {
      _controller.mute();
    }
    setState(() => _isMuted = !_isMuted);
    _revealControls();
  }

  Future<void> _pickRate() async {
    final chosen = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Playback speed',
                  style: AppTheme.cardTitle.copyWith(fontSize: 15)),
            ),
            for (final rate in _rates)
              ListTile(
                dense: true,
                onTap: () => Navigator.pop(sheetContext, rate),
                title: Text(
                  rate == 1.0 ? 'Normal' : '${rate}x',
                  style: AppTheme.cardTitle.copyWith(
                    fontSize: 14,
                    color: rate == _rate
                        ? AppColors.primaryLight
                        : AppColors.white,
                  ),
                ),
                trailing: rate == _rate
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.primaryLight, size: 20)
                    : null,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _controller.setPlaybackRate(chosen);
    _revealControls();
  }

  void _toggleFullscreen() {
    // Own the state instead of calling the plugin's enterFullScreen(): its
    // fullscreen path re-measures the iframe through YouTube's own chrome,
    // which is exactly the second control layer this screen removes.
    setState(() => _isFullscreen = !_isFullscreen);
    _revealControls();
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  /// [ratio] must match the box this player is placed in: the plugin wraps the
  /// iframe in an AspectRatio of its own, and a mismatch makes it letterbox or
  /// crop inside that box.
  Widget _buildPlayer(double ratio) {
    return YoutubePlayer(
      controller: _controller,
      aspectRatio: ratio,
      autoFullScreen: false,
      enableFullScreenOnVerticalDrag: false,
      backgroundColor: Colors.black,
      builder: (context, video, _) => KeyedSubtree(
        key: _chromeKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            video,
            _buildChromeCover(),
            // YouTube paints its endscreen (channel logo + related tiles)
            // inside the iframe and stopVideo() doesn't reliably clear it, so
            // cover the frame outright once the clip is over.
            if (_ended) Positioned.fill(child: _buildEndCard()),
            Positioned.fill(child: _buildGestureLayer()),
            if (_error != YoutubeError.none)
              _buildError()
            else if (_state == PlayerState.buffering)
              const Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Colors.white70,
                  ),
                ),
              ),
            _buildScrim(),
            _buildTopBar(),
            _buildCenterControls(),
            if (_seekFeedback != null) _buildSeekFeedback(),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // The tree shape never changes, only the size of the box. Wrapping the
      // player in different parents per mode used to re-parent the web platform
      // view, which disposes its HtmlElementView: the iframe came back
      // unstarted — black frame, YouTube logo, nothing playing.
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final area = constraints.biggest;
          final ratio = _isFullscreen && area.height > 0
              ? area.width / area.height
              : 16 / 9;
          var width = area.width;
          var height = width / ratio;
          if (height > area.height) {
            height = area.height;
            width = height * ratio;
          }
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: _buildPlayer(ratio),
            ),
          );
        }),
      ),
    );
  }

  /// Pinned to the top edge — a non-positioned Stack child would collapse
  /// toward the stack's alignment instead of hugging the edge.
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _showControls ? 1 : 0,
          child: ExcludeFocusTraversal(
            excluding: !_showControls,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
                child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                    tooltip: 'Close',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.cardTitle
                              .copyWith(fontSize: 15, color: Colors.white),
                        ),
                        Text(
                          'Official Trailer',
                          style: AppTheme.metadata.copyWith(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                  if (_error == YoutubeError.none)
                    IconButton(
                      onPressed: _toggleMute,
                      tooltip: _isMuted ? 'Unmute' : 'Mute',
                      icon: Icon(
                        _isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Single gesture surface: tap toggles the controls, double-tap on either
  /// half seeks ±10s. The iframe itself is pointer-event inert (see params).
  Widget _buildGestureLayer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (_showControls) {
              _showControls = false;
              _hideTimer?.cancel();
            } else {
              _showControls = true;
              _scheduleHide();
            }
          }),
          onDoubleTapDown: (details) {
            final dx = details.localPosition.dx;
            _seekBy(dx < width / 2 ? -_seekStep : _seekStep);
          },
          // Swallow the doubles that follow two quick taps so a pair of
          // single taps doesn't toggle the controls twice.
          onDoubleTap: () {},
        );
      },
    );
  }

  Widget _buildScrim() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: _showControls ? 1 : 0,
      child: IgnorePointer(
        ignoring: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.62),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0.94),
              ],
              stops: const [0, 0.42, 0.72, 1],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildEndCard() {
    final backdrop = widget.backdropUrl;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: backdrop == null
          ? const SizedBox.expand()
          : Image.network(
              backdrop,
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(0.3),
              errorBuilder: (_, __, ___) => const SizedBox.expand(),
            ),
    );
  }

  Widget _buildCenterControls() {
    final showBigPlay = !_isPlaying && _error == YoutubeError.none;
    return Center(
      child: AnimatedScale(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        scale: showBigPlay ? 1 : 0.6,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: showBigPlay ? 1 : 0,
          child: ExcludeFocusTraversal(
            excluding: !showBigPlay,
            child: IgnorePointer(
              ignoring: !showBigPlay,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvFocusable(
                    onSelect: _togglePlay,
                    semanticLabel: _ended ? 'Replay' : 'Play',
                    autofocus: showBigPlay &&
                        context.select((SettingsService s) => s.useTvLayout),
                    scale: 1.08,
                    borderRadius: 37,
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.2),
                        ),
                        child: Icon(
                          _ended
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  if (_ended) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Trailer finished — tap to watch again',
                      style: AppTheme.metadata.copyWith(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeekFeedback() {
    final backward = _seekFeedback!.startsWith('-');
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -0.45),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  backward
                      ? Icons.fast_rewind_rounded
                      : Icons.fast_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Text(_seekFeedback!,
                    style: AppTheme.badge.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: _showControls ? 1 : 0,
        child: ExcludeFocusTraversal(
          excluding: !_showControls,
          child: IgnorePointer(
            ignoring: !_showControls,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 6, 4),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProgressBar(),
                Row(
                  children: [
                    IconButton(
                      onPressed: _togglePlay,
                      autofocus:
                          context.select((SettingsService s) => s.useTvLayout),
                      tooltip: _isPlaying ? 'Pause' : 'Play',
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _seekBy(-_seekStep),
                      tooltip: 'Back 10 seconds',
                      icon: const Icon(Icons.replay_10_rounded,
                          color: Colors.white, size: 24),
                    ),
                    IconButton(
                      onPressed: () => _seekBy(_seekStep),
                      tooltip: 'Forward 10 seconds',
                      icon: const Icon(Icons.forward_10_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 2),
                    Text(
                        _format(_scrubFraction != null
                            ? Duration(
                                milliseconds:
                                    (_scrubFraction! * _duration.inMilliseconds)
                                        .round())
                            : _position),
                        style: _timeStyle),
                    Text(' / ',
                        style: _timeStyle.copyWith(color: Colors.white54)),
                    Text(_format(_duration), style: _timeStyle),
                    const Spacer(),
                    TextButton(
                      onPressed: _pickRate,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 38),
                      ),
                      child: Text(
                        _rate == 1.0 ? '1x' : '${_rate}x',
                        style: AppTheme.badge.copyWith(fontSize: 12.5),
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleMute,
                      tooltip: _isMuted ? 'Unmute' : 'Mute',
                      icon: Icon(
                        _isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleFullscreen,
                      tooltip:
                          _isFullscreen ? 'Exit full screen' : 'Full screen',
                      icon: Icon(
                        _isFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final total = _duration.inMilliseconds;
    final played = total == 0
        ? 0.0
        : (_scrubFraction ?? (_position.inMilliseconds / total).clamp(0.0, 1.0))
            .clamp(0.0, 1.0);

    return LayoutBuilder(
      key: const ValueKey('trailer_progress'),
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        void update(double dx) {
          final f = (dx / width).clamp(0.0, 1.0);
          setState(() => _scrubFraction = f);
        }

        return TvFocusable(
          semanticLabel: 'Progress',
          scale: 1.01,
          borderRadius: 8,
          onSelect: _togglePlay,
          // The bar is the one place a D-pad should scrub rather than walk the
          // focus ladder; the focused node wins the key before Shortcuts.
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (total > 0) _seekBy(-_seekStep);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (total > 0) _seekBy(_seekStep);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: total == 0 ? null : (d) => update(d.localPosition.dx),
          onTapUp: total == 0
              ? null
              : (_) {
                  _commitScrub(_scrubFraction ?? 0);
                  setState(() => _scrubFraction = null);
                  _revealControls();
                },
          onHorizontalDragStart: total == 0
              ? null
              : (d) {
                  update(d.localPosition.dx);
                  _hideTimer?.cancel();
                },
          onHorizontalDragUpdate:
              total == 0 ? null : (d) => update(d.localPosition.dx),
          onHorizontalDragEnd: total == 0
              ? null
              : (_) {
                  _commitScrub(_scrubFraction ?? 0);
                  setState(() => _scrubFraction = null);
                  _revealControls();
                },
          onHorizontalDragCancel:
              total == 0 ? null : () => setState(() => _scrubFraction = null),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(
              height: 16,
              child: CustomPaint(
                size: Size(width, 16),
                painter: _ProgressPainter(
                  played: played,
                  buffered: _loadedFraction.clamp(0.0, 1.0),
                  showThumb: _showControls || _scrubFraction != null,
                  expanded: _scrubFraction != null,
                ),
              ),
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white70, size: 34),
            const SizedBox(height: 12),
            Text(
              'This trailer cannot be played here.',
              style: AppTheme.cardTitle.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _error.name,
              style: AppTheme.metadata.copyWith(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  static final TextStyle _timeStyle = AppTheme.metadata.copyWith(
    fontSize: 12,
    color: Colors.white,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  String _format(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({
    required this.played,
    required this.buffered,
    required this.showThumb,
    required this.expanded,
  });

  final double played;
  final double buffered;
  final bool showThumb;
  final bool expanded;

  @override
  void paint(Canvas canvas, Size size) {
    final height = expanded ? 5.0 : 3.2;
    final y = size.height / 2;
    final radius = Radius.circular(height / 2);

    void bar(double width, Paint paint) {
      if (width <= 0) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - height / 2, width, height),
          radius,
        ),
        paint,
      );
    }

    bar(size.width, Paint()..color = Colors.white.withValues(alpha: 0.26));
    bar(size.width * buffered,
        Paint()..color = Colors.white.withValues(alpha: 0.45));
    bar(size.width * played, Paint()..color = const Color(0xFFED1C24));

    if (showThumb) {
      final cx = (size.width * played).clamp(0.0, size.width);
      canvas.drawCircle(
          Offset(cx, y), expanded ? 7 : 5.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.showThumb != showThumb ||
      old.expanded != expanded;
}
