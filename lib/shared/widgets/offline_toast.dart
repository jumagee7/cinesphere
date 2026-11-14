import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/movie_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// "The feed you are looking at is a cache" said as a message, not a wall.
///
/// This used to be a strip inside the home scroll view, which made a temporary
/// problem look like a permanent part of the page — and pushed every row down
/// for someone who cannot act on it. Here it pops over whatever screen is
/// showing, stays a few seconds, and gets out of the way. It reappears on the
/// next transition (radio dropped, feed failed again), not on a timer.
class OfflineToast extends StatefulWidget {
  const OfflineToast({super.key});

  @override
  State<OfflineToast> createState() => _OfflineToastState();
}

class _OfflineToastState extends State<OfflineToast> {
  static const _lifespan = Duration(seconds: 8);

  MovieProvider? _provider;
  bool _wasStalled = false;
  bool _visible = false;
  String _message = '';
  Timer? _hide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<MovieProvider>();
    if (identical(provider, _provider)) return;
    _provider?.removeListener(_onFeedChanged);
    _provider = provider;
    provider.addListener(_onFeedChanged);
    _onFeedChanged();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _provider?.removeListener(_onFeedChanged);
    super.dispose();
  }

  /// Only a *new* stall shows the message. Staying offline is the state the
  /// rows already reflect; announcing it every few seconds would be noise.
  void _onFeedChanged() {
    final provider = _provider;
    if (provider == null || !mounted) return;
    final stalled = provider.isOffline || provider.showingCachedFeed;
    final rising = stalled && !_wasStalled;
    _wasStalled = stalled;

    if (!stalled) {
      _hideTimer();
      setState(() => _visible = false);
      return;
    }
    if (!rising) return;

    final cachedAt = provider.cachedAt;
    _message = cachedAt == null
        ? 'Nothing has synced yet — titles will load once you reconnect.'
        : 'Showing titles synced ${_ago(cachedAt)}. New arrivals may be missing.';
    _hide?.cancel();
    _hide = Timer(_lifespan, () {
      if (mounted) setState(() => _visible = false);
    });
    setState(() => _visible = true);
  }

  void _hideTimer() {
    _hide?.cancel();
    _hide = null;
  }

  @override
  Widget build(BuildContext context) {
    // A transient message must not become a D-pad stop: it appears and
    // disappears on its own, and focus parked inside it would vanish with it.
    return ExcludeFocus(
      child: ExcludeFocusTraversal(
        child: IgnorePointer(
          ignoring: !_visible,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Align(
                alignment: Alignment.bottomCenter,
                // AnimatedOpacity would keep the message in the tree while
                // transparent; this one really leaves, so nothing invisible
                // sits under the finger or in the semantics tree.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: !_visible
                      ? const SizedBox.shrink()
                      : _card(key: const ValueKey('offlineToast')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Key key}) => Material(
        key: key,
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 20, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No internet connection',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _message,
                      style: AppTheme.metadata
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  // Forget the announcement so a retry that fails again is
                  // allowed to speak up a second time.
                  _wasStalled = false;
                  _hideTimer();
                  setState(() => _visible = false);
                  context.read<MovieProvider>().refresh();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    if (d.inDays < 7) return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
    return '${at.day}/${at.month}';
  }
}
