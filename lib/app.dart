import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/services/auth_service.dart';
import 'core/services/device_form.dart';
import 'core/services/settings_service.dart';
import 'core/services/update_service.dart';
import 'features/auth/trakt_onboarding_prompt.dart';
import 'features/home/home_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/library/library_screen.dart';
import 'features/settings/layout_choice_prompt.dart';
import 'shared/widgets/offline_toast.dart';
import 'shared/widgets/tv_focus.dart';
import 'shared/widgets/update_dialog.dart';

import 'features/splash/splash_screen.dart';

class VyroApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  const VyroApp({super.key, this.navigatorKey});

  @override
  State<VyroApp> createState() => _VyroAppState();
}

class _VyroAppState extends State<VyroApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // A TV's canvas never changes, but a desktop browser or a foldable can be
    // resized into or out of the 10-foot band, and the platform's own answer
    // can land after the first frame.
    WidgetsBinding.instance.addObserver(this);
    nativeTv.addListener(_onSignalChanged);
  }

  void _onSignalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    nativeTv.removeListener(_onSignalChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This context sits above MaterialApp, so there is no MediaQuery here yet —
    // the root view is the equivalent measurement. A maximised desktop browser
    // measures like a TV, so on web the D-pad bindings stay a deliberate choice
    // (`useTvLayout`) instead of an inference.
    final onTvHardware =
        deviceFormOfRootView().isTv && (nativeTvDetected || !kIsWeb);

    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        final useOled = settings.useOledBlack;
        return MaterialApp(
          title: 'Vyro',
          debugShowCheckedModeBanner: false,
          navigatorKey: widget.navigatorKey,
          // D-pad bindings follow the *hardware*, not the layout choice: a TV
          // remote has no other way to reach a button, so the sign-in and
          // Trakt screens stay operable even when the phone layout is on. The
          // unanswered layout question counts too — it is the one screen the
          // answer to is decided with a remote.
          shortcuts: (settings.useTvLayout ||
                  onTvHardware ||
                  nativeTvDetected ||
                  !settings.hasChosenLayout)
              ? tvShortcuts
              : null,
          theme: AppTheme.buildTheme(useOledBlack: useOled),
          // The pinned bars opt out of traversal while their page is scrolled
          // (see [TvChrome]); this gives the D-pad a way back to them.
          builder: (context, child) => TvFocusLadder(child: child!),
          home: const SplashScreen(),
        );
      },
    );
  }
}

/// Wraps MainNavigation in a Stack so the first-launch layout question and the
/// Trakt onboarding prompt can sit on top of the normal app UI without
/// disturbing navigation state.
class AuthenticatedAppShell extends StatefulWidget {
  const AuthenticatedAppShell({super.key});

  @override
  State<AuthenticatedAppShell> createState() => _AuthenticatedAppShellState();
}

/// One launch check per process: signing out and back in must not re-prompt.
bool _updateCheckStarted = false;

class _AuthenticatedAppShellState extends State<AuthenticatedAppShell> {
  @override
  void initState() {
    super.initState();
    if (!_updateCheckStarted) {
      _updateCheckStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    // Let the shell settle first, then ask GitHub quietly in the background.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final update = await UpdateService.check();
    if (!mounted || update == null) return;

    // Never stack the prompt over the first-run asks or another route.
    final settings = context.read<SettingsService>();
    final auth = context.read<AuthService>();
    final firstRunAsksUp = !settings.hasChosenLayout ||
        (!auth.isTraktConnected && !auth.hasDismissedTraktPrompt);
    if (firstRunAsksUp) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;

    await showAppUpdateDialog(context, update);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final auth = context.watch<AuthService>();
    final overlayUp = !settings.hasChosenLayout ||
        (!auth.isTraktConnected && !auth.hasDismissedTraktPrompt);

    return Stack(
      children: [
        // While one of the asks is up, the D-pad belongs to it alone. Left in
        // the running, the rail behind the scrim keeps taking focus and a
        // remote can walk straight out of a card that has no way to be
        // dismissed by pointer either.
        ExcludeFocusTraversal(
          excluding: overlayUp,
          child: const MainNavigation(),
        ),
        const OfflineToast(),
        const TraktOnboardingPrompt(),
        const LayoutChoicePrompt(),
      ],
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  // Highest tab index ever opened. Tabs are built lazily on first visit and
  // then kept alive (IndexedStack) so switching back never destroys state —
  // artwork, scroll positions and loaded feeds persist across tab switches.
  int _maxVisitedIndex = 0;
  late AnimationController _navAnimController;
  bool? _lastTvLayout;

  /// One focus scope per tab. IndexedStack keeps every visited page laid out,
  /// so without a scope each, the D-pad walks into cards on a page nobody is
  /// looking at — which is what makes the focus ring seem to disappear when the
  /// page changes.
  final Map<int, FocusScopeNode> _tabScopes = {};

  /// Whether the last build used the couch layout; focus has to follow the tab
  /// there, because a remote has no other way onto the new page.
  bool _couch = false;

  /// A scope isolates its page, and by default that wall is solid: directional
  /// traversal stops at the page's edge, so the rail becomes unreachable.
  /// `parentScope` lets the D-pad escalate to the shell when it runs out of
  /// cards in the direction it was going.
  FocusScopeNode _scopeFor(int i) => _tabScopes.putIfAbsent(
        i,
        () => FocusScopeNode(
          debugLabel: 'Tab $i',
          directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
        ),
      );

  /// The rail item for a tab, held so the shell can aim the ring at it: see
  /// [_onPageArrowKey].
  final Map<int, FocusNode> _railNodes = {};

  FocusNode _railNodeFor(int i) =>
      _railNodes.putIfAbsent(i, () => FocusNode(debugLabel: 'Rail $i'));

  /// Height of the TV tabs' `SliverAppBar` (home, library and downloads all use
  /// it), so the rail can start its buttons below the bar's icons.
  static const double _kTvAppBarHeight = 60;

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.explore_rounded, label: 'Explore'),
    _NavItem(icon: Icons.download_rounded, label: 'Downloads'),
    _NavItem(icon: Icons.video_library_rounded, label: 'Library'),
  ];

  /// Downloads browses folders and swallows system back while nested, so it is
  /// told whether its tab is showing — a hidden page must not intercept back.
  Widget _screenFor(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const ExploreScreen(),
        2 => DownloadsScreen(active: _currentIndex == i),
        _ => const LibraryScreen(),
      };

  @override
  void initState() {
    super.initState();
    _navAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surfaceContainerHigh,
    ));
  }

  void _syncOrientation(bool tvLayout) {
    if (_lastTvLayout == tvLayout) return;
    _lastTvLayout = tvLayout;
    SystemChrome.setPreferredOrientations(
      tvLayout
          ? [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : DeviceOrientation.values,
    );
  }

  @override
  void dispose() {
    for (final scope in _tabScopes.values) {
      scope.dispose();
    }
    for (final node in _railNodes.values) {
      node.dispose();
    }
    _navAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvLayout = context.select((SettingsService s) => s.useTvLayout);
    _couch = tvLayout;
    _syncOrientation(tvLayout);
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: !tvLayout,
      body: tvLayout ? _buildTvBody() : _buildPhoneBody(),
      bottomNavigationBar: tvLayout ? null : _buildBottomNav(),
    );
  }

  Widget _buildPhoneBody() {
    return _buildTabBody();
  }

  /// Tab content kept alive across switches: each screen is built on first
  /// visit and retained in an IndexedStack, so returning to a tab never
  /// re-triggers image loads or feed fetches.
  Widget _buildTabBody() {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onPageArrowKey,
      child: IndexedStack(
        index: _currentIndex,
        children: List.generate(
          _navItems.length,
          (i) => i <= _maxVisitedIndex
              ? FocusScope(
                  node: _scopeFor(i),
                  child: FocusTraversalGroup(
                    // Only the visible page takes part in focus: the others stay
                    // mounted for their scroll position and artwork, not for the
                    // D-pad.
                    descendantsAreFocusable: i == _currentIndex,
                    child: _screenFor(i),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  /// Walking left out of a page lands on the rail, which is the point — but
  /// plain directional traversal has no idea which tab is showing. Every rail
  /// item sits at the same distance and the same height as a row of cards, so
  /// the tie breaks in favour of the last one, and the ring ends up on Library
  /// while Home is on screen. A TV sidebar returns to the tab that is actually
  /// showing, so nudge the ring there once the traversal has finished.
  ///
  /// The traversal itself is left alone on purpose: it owns the back-and-forth
  /// memory that decides where an edge press goes, and re-implementing the call
  /// here loses it.
  KeyEventResult _onPageArrowKey(FocusNode node, KeyEvent event) {
    if (!_couch || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final scope = _scopeFor(_currentIndex);
    if (scope.focusedChild == null) return KeyEventResult.ignored;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _aimRailAtActiveTab(scope));
    return KeyEventResult.ignored;
  }

  void _aimRailAtActiveTab(FocusScopeNode scope) {
    if (scope.context == null) return;
    final dest = FocusManager.instance.primaryFocus;
    if (dest == null || dest.ancestors.contains(scope)) return;
    _railNodeFor(_currentIndex).requestFocus();
  }

  void _selectTab(int i) {
    if (i == _currentIndex) return;
    setState(() {
      _currentIndex = i;
      if (i > _maxVisitedIndex) _maxVisitedIndex = i;
    });
    if (!_couch) return;
    // A pointer tap brings no focus of its own, so hand the ring to the page the
    // user just opened — but only a page that remembers a card; pulling focus
    // into an empty one leaves the ring on screen nowhere at all.
    //
    // A D-pad activation is different: the ring is already on this rail item,
    // and moving it into the page makes the navigation buttons stop answering
    // the remote — the next Up/Down walks cards instead of tabs, so the rail
    // looks dead until you press Left to get back out.
    if (_railNodes.values.any((node) => node.hasFocus)) return;
    final scope = _scopeFor(i);
    if (scope.focusedChild != null) scope.requestFocus();
  }

  Widget _buildTvBody() {
    return Row(
      // Stretch, not the default centre: the rail shrink-wraps to its buttons,
      // so a centred Row floats the whole strip into the middle of the canvas
      // and leaves dead bands of background above and below it.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSideRail(),
        const VerticalDivider(
            width: 1, thickness: 1, color: AppColors.outlineVariant),
        Expanded(
          child: _buildTabBody(),
        ),
      ],
    );
  }

  Widget _buildSideRail() {
    return Container(
      width: 96,
      color: AppColors.surfaceContainerHigh,
      child: SafeArea(
        right: false,
        // The rail has to fit the canvas it is handed, and that canvas ranges
        // from ~270 logical pixels on a 480p box to ten times that on a desktop
        // window. Fixed spacing either overflows the short one — and a tab that
        // scrolls off the bottom has no ring to show, so the nav looks dead —
        // or leaves the buttons stranded in a tall one. So the column is laid
        // out at its natural size, pinned to the top, and scaled down only when
        // the canvas cannot fit it.
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 96,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Start the buttons level with the page's content, not with its
                  // bar. Directional traversal filters a candidate out of "up"
                  // unless its centre is above the focused node's *top edge*
                  // (`node.rect.center.dy <= target.top`), so a first button that
                  // sits higher than the app bar's icons leaves nothing above it
                  // and the bar — the profile avatar, which is the only way into
                  // Settings — can never be reached from the rail.
                  const SizedBox(height: _kTvAppBarHeight),
                  ...List.generate(_navItems.length, (i) {
                    final item = _navItems[i];
                    final isActive = _currentIndex == i;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Material(
                        color: Colors.transparent,
                        // The card inside owns the focus: an InkWell is itself a focus
                        // stop, and the D-pad would land on it instead — which shows a
                        // grey ink wash where the ring should be.
                        child: InkWell(
                          canRequestFocus: false,
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _selectTab(i);
                          },
                          child: TvFocusable(
                            focusNode: _railNodeFor(i),
                            autofocus: i == 0,
                            onSelect: () => _selectTab(i),
                            semanticLabel: item.label,
                            scale: 1.0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.icon,
                                    color: isActive
                                        ? AppColors.primaryLight
                                        : AppColors.white
                                            .withValues(alpha: 0.6),
                                    size: 26,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.label,
                                    style: AppTheme.badge.copyWith(
                                      fontSize: 10,
                                      color: isActive
                                          ? AppColors.primaryLight
                                          : AppColors.white
                                              .withValues(alpha: 0.6),
                                      fontWeight: isActive
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              _navItems.length,
              (i) => _NavBarItem(
                item: _navItems[i],
                isActive: _currentIndex == i,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _selectTab(i);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _NavBarItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: EdgeInsets.symmetric(
                  horizontal: isActive ? 16 : 0,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  item.icon,
                  color: isActive
                      ? AppColors.primaryLight
                      : AppColors.white.withValues(alpha: 0.5),
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: AppTheme.badge.copyWith(
                  fontSize: 10,
                  color: isActive
                      ? AppColors.primaryLight
                      : AppColors.white.withValues(alpha: 0.5),
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
