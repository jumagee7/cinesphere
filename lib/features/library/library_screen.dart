import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/screen_metrics.dart';
import '../../core/models/movie.dart';
import '../../core/services/library_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/settings_service.dart';
import '../../shared/widgets/profile_widgets.dart';
import '../../shared/widgets/cine_artwork.dart';
import '../../shared/widgets/tv_focus.dart';
import '../detail/movie_detail_screen.dart';
import '../player/play_launcher.dart';

// ─── Tab model ────────────────────────────────────────────────────────────────

enum _LibTab { watchlist, favorites, history, continueWatching }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Per-tab Movies/TV filter (null = all)
  final Map<_LibTab, bool?> _tvFilter = {
    for (final t in _LibTab.values) t: null,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _LibTab.values.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      final settings = context.read<SettingsService>();
      if (auth.isLoggedIn &&
          auth.accessToken != null &&
          (settings.syncWatchHistory || settings.syncWatchlist)) {
        context.read<LibraryService>().syncFromTrakt(
              auth.accessToken!,
              history: settings.syncWatchHistory,
              watchlist: settings.syncWatchlist,
            );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  _LibTab get _activeTab => _LibTab.values[_tabController.index];

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, innerBoxIsScrolled) => [
          _buildAppBar(),
          _buildTabBar(),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTab(_LibTab.watchlist, library.watchlist),
            _buildTab(_LibTab.favorites, library.favorites),
            _buildTab(_LibTab.history, library.history),
            _buildContinueWatchingTab(library.continueWatching),
          ],
        ),
      ),
    );
  }

  // ─── AppBar ─────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      primary: true,
      backgroundColor: AppColors.background.withValues(alpha: 0.96),
      surfaceTintColor: AppColors.surfaceContainerHigh,
      scrolledUnderElevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.6),
      toolbarHeight: 60,
      titleSpacing: 0,
      title: TvChrome(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                'My Library',
                style: AppTheme.sectionTitle.copyWith(
                  fontSize: 20,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              // Movies / TV toggle pill
              _TypeFilterPill(
                value: _tvFilter[_activeTab],
                onChanged: (v) => setState(() => _tvFilter[_activeTab] = v),
              ),
              const SizedBox(width: 10),
              const ProfileAvatarButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tab bar ────────────────────────────────────────────────────────────────

  SliverPersistentHeader _buildTabBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _LibraryTabBarDelegate(controller: _tabController),
    );
  }

  // ─── Generic movie/TV grid tab ──────────────────────────────────────────────

  Widget _buildTab(_LibTab tab, List<Movie> allItems) {
    final filter = _tvFilter[tab];
    final items = filter == null
        ? allItems
        : allItems.where((m) => m.isTV == filter).toList();

    if (allItems.isEmpty) {
      return _EmptyState(tab: tab);
    }

    if (items.isEmpty) {
      // Items exist but none match the active filter
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filter == true ? Icons.tv_rounded : Icons.movie_rounded,
              size: 56,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              filter == true ? 'No TV Shows here yet' : 'No Movies here yet',
              style:
                  AppTheme.metadata.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      // Directional focus can only reach built children, so TV layout keeps
      // more of the grid alive below the fold.
      scrollCacheExtent: ScrollCacheExtent.pixels(
        context.select((SettingsService s) => s.useTvLayout) ? 1200 : 250,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ScreenMetrics.of(context).tileColumns,
        childAspectRatio: 0.60,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _PosterGridItem(movie: items[i], index: i),
    );
  }

  // ─── Continue watching tab ───────────────────────────────────────────────────

  Widget _buildContinueWatchingTab(List<Movie> items) {
    if (items.isEmpty) {
      return const _EmptyState(tab: _LibTab.continueWatching);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      scrollCacheExtent: ScrollCacheExtent.pixels(
        context.select((SettingsService s) => s.useTvLayout) ? 1200 : 250,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, i) =>
          _ContinueWatchingListItem(movie: items[i], index: i),
    );
  }
}

// ─── Movies / TV filter pill ──────────────────────────────────────────────────

class _TypeFilterPill extends StatelessWidget {
  final bool? value; // null=All, false=Movies, true=TV
  final ValueChanged<bool?> onChanged;

  const _TypeFilterPill({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pill(
              label: 'All',
              active: value == null,
              onTap: () => onChanged(null)),
          _Pill(
              label: 'Movies',
              active: value == false,
              onTap: () => onChanged(false)),
          _Pill(
              label: 'TV', active: value == true, onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    void select() {
      HapticFeedback.selectionClick();
      onTap();
    }

    return TvFocusable(
      onSelect: select,
      semanticLabel: label,
      scale: 1.05,
      borderRadius: 14,
      child: GestureDetector(
        onTap: select,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: AppTheme.badge.copyWith(
              fontSize: 11,
              color: active ? AppColors.white : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tab bar delegate ─────────────────────────────────────────────────────────

class _LibraryTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;
  _LibraryTabBarDelegate({required this.controller});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.96),
      child: TabBar(
        controller: controller,
        labelColor: AppColors.primaryLight,
        unselectedLabelColor: AppColors.onSurfaceVariant,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: AppTheme.cardTitle.copyWith(fontSize: 13),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.only(left: 16),
        tabs: const [
          Tab(text: 'Watchlist'),
          Tab(text: 'Favorites'),
          Tab(text: 'History'),
          Tab(text: 'Continue Watching'),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 48;
  @override
  double get minExtent => 48;
  @override
  bool shouldRebuild(_LibraryTabBarDelegate old) =>
      old.controller != controller;
}

// ─── Poster grid item ─────────────────────────────────────────────────────────

/// Caption block under a grid poster. Fixed so the focus ring can stop at the
/// thumbnail's edge instead of drawing through the title.
const double _captionHeight = 36;

class _PosterGridItem extends StatelessWidget {
  final Movie movie;
  final int index;

  const _PosterGridItem({required this.movie, required this.index});

  @override
  Widget build(BuildContext context) {
    void open() {
      HapticFeedback.lightImpact();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
      );
    }

    return TvFocusable(
      onSelect: open,
      semanticLabel: movie.title,
      borderRadius: 12,
      ringBottomInset: _captionHeight,
      child: GestureDetector(
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CineArtwork(
                      imageUrl: movie.imageUrl,
                      fallbackUrl: movie.backdropUrl,
                      title: movie.title,
                      fit: BoxFit.cover,
                    ),
                    // Bottom gradient
                    Container(
                      decoration: const BoxDecoration(
                          gradient: AppColors.posterGradient),
                    ),
                    // TV badge
                    if (movie.isTV)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'TV',
                            style: AppTheme.badge.copyWith(fontSize: 9),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: _captionHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),
                  Text(
                    movie.title,
                    style: AppTheme.cardTitle.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    movie.year > 0 ? '${movie.year}' : movie.genreString,
                    style: AppTheme.metadata.copyWith(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 35));
  }
}

// ─── Continue Watching list item ──────────────────────────────────────────────

class _ContinueWatchingListItem extends StatelessWidget {
  final Movie movie;
  final int index;

  const _ContinueWatchingListItem({required this.movie, required this.index});

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryService>();
    void open() => launchPlayer(context, movie);

    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      // The row actions sit OUTSIDE the card's focus stop: a small focusable
      // nested inside a big one shares its band, so it would steal vertical
      // hops and never be reachable with Left/Right.
      child: Row(
        children: [
          Expanded(
            child: TvFocusable(
              onSelect: open,
              semanticLabel: movie.title,
              borderRadius: 16,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: open,
                child: Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      child: CineArtwork(
                        imageUrl: movie.backdropUrl.isNotEmpty
                            ? movie.backdropUrl
                            : movie.imageUrl,
                        fallbackUrl: movie.imageUrl,
                        title: movie.title,
                        width: 148,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Info
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  movie.title,
                                  style:
                                      AppTheme.cardTitle.copyWith(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  movie.genreString,
                                  style:
                                      AppTheme.metadata.copyWith(fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            // Progress
                            if (movie.hasProgress) ...[
                              LinearPercentIndicator(
                                padding: EdgeInsets.zero,
                                lineHeight: 3,
                                percent: movie.watchProgress!.clamp(0.0, 1.0),
                                backgroundColor:
                                    AppColors.surfaceContainerHighest,
                                progressColor: AppColors.secondary,
                                barRadius: const Radius.circular(2),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${(movie.watchProgress! * 100).round()}% watched',
                                style: AppTheme.metadata.copyWith(fontSize: 10),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Actions column
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TvButton(
                semanticLabel: 'Resume',
                borderRadius: 999,
                onSelect: open,
                child: IconButton(
                  icon: const Icon(Icons.play_circle_rounded,
                      color: AppColors.primaryLight),
                  iconSize: 28,
                  onPressed: open,
                ),
              ),
              TvButton(
                semanticLabel: 'Remove from Continue Watching',
                borderRadius: 999,
                onSelect: () {
                  HapticFeedback.selectionClick();
                  library.removeFromContinueWatching(movie);
                },
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.onSurfaceVariant, size: 18),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    library.removeFromContinueWatching(movie);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 50)).slideX(
          begin: 0.04,
          end: 0,
          duration: 300.ms,
        );
  }
}

// ─── Empty states ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final _LibTab tab;
  const _EmptyState({required this.tab});

  @override
  Widget build(BuildContext context) {
    final (icon, title, sub) = switch (tab) {
      _LibTab.watchlist => (
          Icons.bookmark_border_rounded,
          'Your Watchlist is empty',
          'Tap the bookmark icon on any title to save it here.',
        ),
      _LibTab.favorites => (
          Icons.favorite_border_rounded,
          'No Favorites yet',
          'Tap the heart icon on any title to add it to favorites.',
        ),
      _LibTab.history => (
          Icons.history_rounded,
          'No Watch History',
          'Titles you watch will appear here automatically.',
        ),
      _LibTab.continueWatching => (
          Icons.play_circle_outline_rounded,
          'Nothing in progress',
          'Start watching a title — it will appear here with your progress.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 72,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.25)),
            const SizedBox(height: 20),
            Text(
              title,
              style: AppTheme.sectionTitle.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              sub,
              style: AppTheme.metadata
                  .copyWith(color: AppColors.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }
}
