import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// Arrow-key bindings for TV layout, passed to `MaterialApp.shortcuts`.
///
/// Flutter's *web* defaults route the arrow keys to [ScrollIntent] so the page
/// scrolls and focus never moves, which makes a remote's D-pad look dead in
/// the browser build. Directional focus traversal is what a 10-foot interface
/// needs; the focused card then scrolls itself into view.
final Map<ShortcutActivator, Intent> tvShortcuts = <ShortcutActivator, Intent>{
  // Start from the platform defaults so Tab / Enter / Escape keep working,
  // then override only the four D-pad directions.
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.arrowUp):
      const DirectionalFocusIntent(TraversalDirection.up),
  const SingleActivator(LogicalKeyboardKey.arrowDown):
      const DirectionalFocusIntent(TraversalDirection.down),
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const DirectionalFocusIntent(TraversalDirection.left),
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const DirectionalFocusIntent(TraversalDirection.right),
  // A remote's OK arrives as `select`, not `enter`, and Material's default
  // activators do not list it — so a focused button would highlight but never
  // fire. Cards work around this by handling the key themselves; plain buttons
  // need the binding.
  const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
      const ActivateIntent(),
  // Back / Escape exits the current route (mirrors Android Back)
  const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
  const SingleActivator(LogicalKeyboardKey.goBack): const DismissIntent(),
};

/// A focus-driven activation wrapper for remote / keyboard (10-foot) use.
///
/// ### Key fixes over a bare [Focus]:
/// - **ExcludeSemantics on non-TV**: on non-TV builds the extra Semantics node
///   is redundant; it doubles screen-reader announcements.
/// - **Traversal order**: uses [FocusTraversalOrder] + [NumericFocusOrder] when
///   an explicit [order] is provided, giving the screen full control of the
///   D-pad sequence rather than relying on geometry alone — the right fix when
///   cards are in a horizontal [ListView] whose viewport clips the others.
/// - **ensureVisible on both axes**: scrolls the card into view horizontally
///   *and* vertically so cards in nested rows are always reachable.
/// - **skipTraversal guard**: when [enabled] is false the node is excluded from
///   the D-pad entirely (useful for loading placeholders or empty states).
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.focusNode,
    this.onSelect,
    this.autofocus = false,
    this.semanticLabel,
    this.scale = 1.05,
    this.borderRadius = 16,
    this.ringBottomInset = 0,
    this.order,
    this.enabled = true,
    this.onKeyEvent,
    this.ringOnlyWhenPrimary = false,
  });

  final Widget child;

  /// The node this card focuses with, when somebody outside the widget needs to
  /// drive it — the shell hands each side-rail item a node so it can put the
  /// ring back on the tab that is actually showing. Leave null to let the card
  /// own its node.
  final FocusNode? focusNode;
  final VoidCallback? onSelect;
  final bool autofocus;
  final String? semanticLabel;
  final double scale;
  final double borderRadius;

  /// Pixels of the child's bottom edge the ring leaves out.
  ///
  /// Media cards put the title and metadata under the thumbnail, and a ring
  /// around the whole card draws straight through that text. Passing the
  /// caption's height keeps the outline on the artwork, which is what a
  /// 10-foot interface highlights anyway.
  final double ringBottomInset;

  /// When non-null, the card joins [FocusTraversalOrder] traversal with this
  /// priority. Lower numbers come first. Pass to override the default
  /// geometry-based ordering in horizontal lists where items are partially
  /// off-screen and geometry gives the wrong answer.
  final double? order;

  /// Whether this focusable participates in D-pad traversal at all.
  /// Set to false for skeleton/loading placeholders.
  final bool enabled;

  /// Extra key handling while focused, running before the activate keys.
  /// Used by controls that are one widget but need directional behaviour
  /// (the player's seek bar seeks left/right instead of leaving the bar).
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  /// Draw the ring only while this node is the primary focus, not while one of
  /// its nested controls is. Rows that carry their own action buttons need
  /// this so the card outline doesn't stack with the button's ring.
  final bool ringOnlyWhenPrimary;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable>
    with SingleTickerProviderStateMixin {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  late final bool _ownsNode = widget.focusNode == null;
  bool _focused = false;

  /// Rings only belong on a 10-foot experience. Flutter reports the last input
  /// mode through [FocusManager], so a phone tap drops the ring while a D-pad
  /// press brings it back — without any per-screen platform checks.
  bool _keyboardFocus =
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  bool get _showFocus => _focused && _keyboardFocus;

  /// Remote "OK" plus the keyboard keys that stand in for it. `mediaPlayPause`
  /// is included because several TV remotes map their select button to it.
  static final Set<LogicalKeyboardKey> _activateKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.mediaPlayPause,
  };

  @override
  void initState() {
    super.initState();
    // Cards own their node, so the semantic label doubles as the debug label —
    // it is what shows up in a focus dump and in the browser's a11y tree.
    _node.debugLabel ??= widget.semanticLabel;
    _node.addListener(_onFocusChanged);
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _node.removeListener(_onFocusChanged);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (!mounted) return;
    final keyboard = mode == FocusHighlightMode.traditional;
    if (keyboard != _keyboardFocus) setState(() => _keyboardFocus = keyboard);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final focused =
        widget.ringOnlyWhenPrimary ? _node.hasPrimaryFocus : _node.hasFocus;
    if (focused != _focused) setState(() => _focused = focused);
    if (!focused) return;
    // Scroll focused card into view on BOTH axes — horizontal rows need
    // horizontal scrolling; the main page scroller needs vertical scrolling.
    // Using addPostFrameCallback ensures the render object is positioned.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Vertical scroll first (the page scroller)
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final custom = widget.onKeyEvent?.call(node, event);
    if (custom != null && custom != KeyEventResult.ignored) return custom;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_activateKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    widget.onSelect?.call();
    return KeyEventResult.handled;
  }

  Widget _buildRing() => Positioned(
        left: 0,
        right: 0,
        top: 0,
        bottom: widget.ringBottomInset,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.55),
                  blurRadius: 16,
                  spreadRadius: -14,
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget core = Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      // skipTraversal blocks the D-pad from even seeing this node when
      // the widget is disabled (loading state, invisible, etc.).
      skipTraversal: !widget.enabled,
      canRequestFocus: widget.enabled,
      child: Semantics(
        button: true,
        focused: _focused,
        label: widget.semanticLabel,
        onTap: widget.onSelect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            scale: _showFocus ? widget.scale : 1,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                widget.child,
                if (_showFocus) _buildRing(),
              ],
            ),
          ),
        ),
      ),
    );

    // Wrap with FocusTraversalOrder when the caller provides an explicit order
    // so adjacent items in clipped lists don't get geometry-sorted wrong.
    if (widget.order != null) {
      core = FocusTraversalOrder(
        order: NumericFocusOrder(widget.order!),
        child: core,
      );
    }

    return core;
  }
}

/// A Material button wearing the same focus ring the cards use.
///
/// ### What this fixes vs the old version:
/// - [ExcludeFocus] is replaced with [ExcludeFocusTraversal]: the inner button
///   node stays alive for semantics / ink responses, but is skipped by the
///   D-pad so the ring is the sole traversal stop.
/// - Wraps the child in [ExcludeFocusTraversal] rather than [ExcludeFocus] —
///   ExcludeFocus is heavier (it disconnects the subtree from the focus system
///   entirely, which kills ink responses on Android TV).
/// - Adds `focusColor: Colors.transparent` so FilledButton / TextButton
///   children don't paint a second overlay when they still catch a pointer.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.onSelect,
    required this.child,
    this.autofocus = false,
    this.semanticLabel,
    this.borderRadius = 999,
    this.order,
    this.enabled = true,
  });

  final VoidCallback? onSelect;
  final Widget child;
  final bool autofocus;
  final String? semanticLabel;
  final double borderRadius;
  final double? order;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TvFocusable(
        autofocus: autofocus,
        onSelect: onSelect,
        semanticLabel: semanticLabel,
        scale: 1.02,
        borderRadius: borderRadius,
        order: order,
        enabled: enabled,
        // ExcludeFocusTraversal removes ONLY traversal, not the node itself —
        // ink / ripple still work, but the D-pad's stop is the outer ring.
        child: ExcludeFocusTraversal(excluding: true, child: child),
      );
}

/// Keeps a D-pad page climbable when its chrome has stepped out of traversal.
///
/// [TvChrome] hides the pinned bar while the page is scrolled, so up walks the
/// rows instead of jumping out of the page — but that also leaves the top row
/// with nothing above it, and a remote has no other way to scroll. Wrapping the
/// app in this widget makes the dead press bring the page home, which returns
/// the chrome to the ladder for the next one.
///
/// It sits above every route (as `MaterialApp.builder` does) so pushed screens
/// get the same rescue as the tabs.
///
/// ### Improvement over old version:
/// Also handles **down-arrow when focus is in the chrome** — scrolls to the
/// first row of content if the page is already at the top. Previously Down from
/// the app bar would do nothing until a card was already in view.
class TvFocusLadder extends StatefulWidget {
  const TvFocusLadder({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusLadder> createState() => _TvFocusLadderState();
}

class _TvFocusLadderState extends State<TvFocusLadder> {
  static final Set<LogicalKeyboardKey> _directionKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  FocusScopeNode? _seenScope;
  int _seenDescendants = -1;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onDirectionKey,
      child: widget.child,
    );
  }

  /// Drops stale hop memory when the focus tree changes so new rows are
  /// reachable without the traversal skipping over them.
  void _forgetStaleHops() {
    final FocusNode? focus = FocusManager.instance.primaryFocus;
    final FocusScopeNode? scope = focus?.nearestScope;
    if (focus == null || scope == null) return;
    final int count = scope.traversalDescendants.length;
    if (scope != _seenScope) {
      _seenScope = scope;
      _seenDescendants = count;
      return;
    }
    if (count == _seenDescendants) return;
    _seenDescendants = count;
    FocusTraversalGroup.maybeOfNode(focus)?.invalidateScopeData(scope);
  }

  KeyEventResult _onDirectionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_directionKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    _forgetStaleHops();

    final source = FocusManager.instance.primaryFocus;
    final ctx = source?.context;
    if (ctx == null) return KeyEventResult.ignored;

    // ── Up: scroll page back to top so chrome becomes reachable ──────────
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final scrollable = Scrollable.maybeOf(ctx, axis: Axis.vertical);
      if (scrollable == null || scrollable.position.pixels <= 4) {
        return KeyEventResult.ignored;
      }
      // The hop itself can land *after* this handler returns, so the "did the
      // ring move?" test has to run at the end of the frame rather than in a
      // microtask: a microtask sees the old focus, yanks the page home, and the
      // row that was about to take the ring is evicted with it — the page jumps
      // to the hero with nothing highlighted. A press that moves nothing
      // schedules no frame, so ask for one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollable.mounted) return;
        if (!identical(FocusManager.instance.primaryFocus, source)) return;
        if (scrollable.position.pixels <= 4) return;
        scrollable.position.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }
}

/// Wraps a screen's AppBar content so it steps out of D-pad traversal while the
/// page is scrolled.
///
/// Directional traversal is pure geometry: `_findNextFocusInDirection` ranks
/// the candidates above the source by distance from its centre, and a pinned
/// bar sits at y=0 whatever the scroll offset. TV rows are ~400px apart and
/// [TvFocusable] parks the focused card at 45% of the viewport, so from any row
/// below the first the bar measures closer than the row above it and every Up
/// press leaves the page for the top bar. Excluding the bar while the page is
/// scrolled makes Up climb one row at a time again.
///
/// A remote cannot scroll by itself, so this is paired with [TvFocusLadder]: an
/// Up press that finds nothing above brings the page back to the top, and the
/// next press reaches the chrome.
///
/// The offset is read from the page's own vertical [Scrollable] — a
/// `SliverAppBar` title lives inside the same viewport as the cards, which is
/// exactly the scroll position the exclusion has to track.
class TvChrome extends StatefulWidget {
  const TvChrome({super.key, required this.child});

  final Widget child;

  @override
  State<TvChrome> createState() => _TvChromeState();
}

class _TvChromeState extends State<TvChrome> {
  ScrollPosition? _position;
  bool _scrolled = false;

  // Dead-band: a few pixels of overscroll on a remote must not flicker the bar
  // in and out of traversal.
  static const double _scrollThreshold = 4;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_onScroll);
      _position = next;
      _position?.addListener(_onScroll);
    }
    _sync();
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() => _sync();

  void _sync() {
    final scrolled = (_position?.pixels ?? 0) > _scrollThreshold;
    if (!mounted || scrolled == _scrolled) return;
    setState(() => _scrolled = scrolled);
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeFocusTraversal(excluding: _scrolled, child: widget.child);
  }
}

/// Groups a horizontal row of [TvFocusable] items inside a
/// [FocusTraversalGroup] that uses [ReadingOrderTraversalPolicy], so left/right
/// within the row is always strictly ordered, and up/down from any card in the
/// row escapes the row's group cleanly.
///
/// ### Why this matters:
/// Without an explicit group, the traversal policy is shared with the whole
/// page's vertical scroll, so pressing Right from the last card in a row can
/// jump to the first card of the NEXT row instead of wrapping inside the row or
/// falling out to the next group.
///
/// Wrap every horizontal [ListView] of media cards with this widget.
class TvRowGroup extends StatelessWidget {
  const TvRowGroup({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: child,
    );
  }
}
