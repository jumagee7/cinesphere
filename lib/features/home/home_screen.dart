import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/screen_metrics.dart';
import '../../core/services/media_orchestrator_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/library_service.dart';
import '../../core/services/profile_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/models/movie.dart';
import '../../core/providers/movie_provider.dart' show MovieProvider, LoadState;
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/cine_artwork.dart';
import '../../shared/widgets/profile_widgets.dart';
import '../../shared/widgets/tv_focus.dart';
import '../../shared/widgets/vyro_logo.dart';
import 'widgets/media_cards.dart';
import '../detail/movie_detail_screen.dart';
import '../player/play_launcher.dart';
import '../explore/explore_screen.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _heroController = PageController();
  Timer? _heroAutoScrollTimer;

  /// Subtree handle for the hero carousel: its `hasFocus` is true whenever a
  /// remote is parked on anything inside, which is what stops auto-rotation.
  final FocusNode _heroFocusNode = FocusNode(
    // The node itself never takes focus; the cards inside it do.
    canRequestFocus: false,
    skipTraversal: true,
  );

  String _activeFilter = 'All';
  final List<String> _filters = [
    'All',
    'Movies',
    'TV Shows',
    'Action',
    'Sci-Fi',
    'Drama',
    'Thriller'
  ];

  static const Set<String> _nonGenreFilters = {'All', 'Movies', 'TV Shows'};
  bool get _isGenreFilter => !_nonGenreFilters.contains(_activeFilter);

  void _selectFilter(String filter) {
    setState(() => _activeFilter = filter);
    final provider = context.read<MovieProvider>();
    if (_nonGenreFilters.contains(filter)) {
      provider.clearGenre();
    } else {
      provider.loadGenre(filter);
    }
  }

  @override
  void initState() {
    super.initState();
    _startHeroAutoScroll();
    // Load data from provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MovieProvider>().loadHome();
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

  void _startHeroAutoScroll() {
    _heroAutoScrollTimer?.cancel();
    _heroAutoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_heroController.hasClients) return;
      // Do not auto-scroll while user is actively dragging or interacting
      if (_heroController.position.isScrollingNotifier.value) return;
      // A remote parked on a hero button would otherwise have its target
      // animated away mid-selection.
      if (_heroFocusNode.hasFocus) return;

      final provider = context.read<MovieProvider>();
      final movies = provider.featured;
      if (movies.length <= 1) return;

      final currentPage = _heroController.page?.round() ?? 0;
      final nextPage = (currentPage + 1) % movies.length;

      _heroController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _heroAutoScrollTimer?.cancel();
    _heroController.dispose();
    _heroFocusNode.dispose();
    super.dispose();
  }

  void _navigateToExploreCategory(String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExploreScreen(initialCategory: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final density = context.select((SettingsService s) => s.densityLevel);
    final mult = 1 + density * 0.3;
    final profile = context.select((ProfileService s) => s.current);
    final profileName = profile.name;
    final personalize =
        context.select((SettingsService s) => s.personalizedRecommendations);

    final isTVFilter = _activeFilter == 'TV Shows';
    final isMovieFilter = _activeFilter == 'Movies';
    final isGenreFilter = _isGenreFilter;

    final library = context.watch<LibraryService>();
    final provider = context.watch<MovieProvider>();
    final continueWatchingList = library.continueWatching;
    final tvContinueWatching =
        continueWatchingList.where((m) => m.isTV).toList();

    // Directional focus can only move to children that are already built, so
    // the page itself must keep more rows alive in TV layout.
    final tvLayout = context.select((SettingsService s) => s.useTvLayout);

    final topRated = personalize
        ? library.personalize(provider.topRated, profile: profile)
        : provider.topRated;
    final trending = _pick(provider.trending, provider.popular);
    final newReleases = provider.nowPlaying;
    final popularTV = _pick(provider.popularTV, provider.trendingTV);
    final trendingTV = _pick(provider.trendingTV, provider.popularTV);
    final genreItems = provider.genreResults.isNotEmpty
        ? provider.genreResults
        : _fallbackGenreMovies(provider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        scrollCacheExtent: ScrollCacheExtent.pixels(tvLayout ? 1500 : 250),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildFilterChips()),
          // Hero carousel
          SliverToBoxAdapter(child: _buildHeroCarousel()),

          if (isTVFilter) ...[
            // ── TV Shows Filter View ──────────────────────────────
            ..._section(
              title: 'Popular TV Series',
              items: popularTV,
              onAction: () => _navigateToExploreCategory('TV Shows'),
            ),
            ..._section(
              title: 'Trending TV Shows',
              items: trendingTV,
              onAction: () => _navigateToExploreCategory('TV Shows'),
            ),
            if (tvContinueWatching.isNotEmpty) ...[
              SliverToBoxAdapter(child: SizedBox(height: 32 * mult)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Continue Watching TV',
                  actionLabel: 'History',
                  onAction: () {},
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 16 * mult)),
              SliverToBoxAdapter(
                  child: _buildContinueWatching(items: tvContinueWatching)),
            ],
          ] else if (isMovieFilter) ...[
            // ── Movies Filter View ────────────────────────────────
            ..._section(
              title: 'Trending Movies',
              items: trending,
              onAction: () => _navigateToExploreCategory('Movies'),
            ),
            ..._section(
              title: 'Top Rated Movies',
              actionLabel: personalize ? 'Personalized' : 'See All',
              items: topRated,
              onAction: () => _navigateToExploreCategory('Movies'),
            ),
            ..._section(
              title: 'New Movie Releases',
              items: newReleases,
              onAction: () => _navigateToExploreCategory('Movies'),
            ),
          ] else if (isGenreFilter) ...[
            // ── Genre Filter View (live TMDB discover, no Trakt needed) ──
            if (genreItems.isEmpty && provider.isLoadingGenre)
              const SliverToBoxAdapter(child: _GenreLoadingStrip()),
            ..._section(
              title: '$_activeFilter Picks',
              items: genreItems,
              onAction: () => _navigateToExploreCategory(_activeFilter),
            ),
            ..._section(
              title: 'Trending Now',
              items: trending,
              onAction: () => _navigateToExploreCategory('Movies'),
            ),
          ] else ...[
            // ── Full Home View (Includes TV Shows & Movies) ───────
            // Continue Watching (hidden if empty from Trakt / library)
            if (continueWatchingList.isNotEmpty) ...[
              SliverToBoxAdapter(child: SizedBox(height: 32 * mult)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Continue Watching',
                  actionLabel: 'History',
                  onAction: () {},
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 16 * mult)),
              SliverToBoxAdapter(
                  child: _buildContinueWatching(items: continueWatchingList)),
            ],

            ..._section(
              title: 'Popular TV Series',
              items: popularTV,
              onAction: () => _navigateToExploreCategory('TV Shows'),
            ),

            // Upcoming premiere promo
            //
            // A section-level focus stop with no section above it reads as a
            // broken D-pad: while the feeds are still arriving the poster rows
            // are absent (an empty `_section` renders nothing), so Up from here
            // has nothing to climb and lands at the top of the page. It appears
            // once the row above it does.
            if (provider.homeState != LoadState.loading) ...[
              SliverToBoxAdapter(child: SizedBox(height: 24 * mult)),
              const SliverToBoxAdapter(child: _PremiereBanner()),
            ],

            ..._section(
              title: personalize ? 'For $profileName' : 'Top Rated',
              actionLabel: personalize ? 'Personalized' : 'See All',
              items: topRated,
              onAction: () => _navigateToExploreCategory('All'),
            ),
            ..._section(
              title: 'Trending Now',
              items: trending,
              onAction: () => _navigateToExploreCategory('Movies'),
            ),
            ..._section(
              title: 'Trending TV Shows',
              items: trendingTV,
              onAction: () => _navigateToExploreCategory('TV Shows'),
            ),
            ..._section(
              title: 'New Releases',
              items: newReleases,
              onAction: () => _navigateToExploreCategory('Movies'),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: 100 * mult)),
        ],
      ),
    );
  }

  /// Falls back to a neighbouring feed when one of the parallel TMDB/Trakt
  /// rows comes back empty, so a partial response doesn't drop a section.
  List<Movie> _pick(List<Movie> primary, List<Movie> secondary) =>
      primary.isNotEmpty ? primary : secondary;

  /// Header + poster row as one unit. A title with nothing under it reads as a
  /// broken app, so an empty section is skipped entirely — offline that leaves
  /// a short, honest page instead of a column of holes.
  List<Widget> _section({
    required String title,
    required List<Movie> items,
    String actionLabel = 'See All',
    VoidCallback? onAction,
  }) {
    if (items.isEmpty) return const [];
    final density = context.select((SettingsService s) => s.densityLevel);
    final mult = 1 + density * 0.3;
    return [
      SliverToBoxAdapter(child: SizedBox(height: 32 * mult)),
      SliverToBoxAdapter(
        child: SectionHeader(
          title: title,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
      SliverToBoxAdapter(child: SizedBox(height: 16 * mult)),
      SliverToBoxAdapter(child: _posterRow(items)),
    ];
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      primary: true,
      backgroundColor: AppColors.background.withValues(alpha: 0.94),
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
              const VyroLogo(size: 34),
              const SizedBox(width: 10),
              Text(
                'VYRO',
                style: AppTheme.sectionTitle.copyWith(
                  fontSize: 20,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              _appBarIcon(Icons.cast_rounded),
              const SizedBox(width: 8),
              _appBarIcon(
                Icons.search_rounded,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const ExploreScreen(autoFocusSearch: true),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              const NotificationBell(),
              const SizedBox(width: 10),
              const ProfileAvatarButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBarIcon(IconData icon, {VoidCallback? onTap}) {
    return TvFocusable(
      onSelect: onTap,
      semanticLabel: 'Vyro action',
      scale: 1.1,
      borderRadius: 18,
      child: GestureDetector(
        onTap: onTap ?? () {},
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLow,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => TvFocusable(
          onSelect: () => _selectFilter(_filters[i]),
          semanticLabel: _filters[i],
          scale: 1.06,
          borderRadius: 20,
          child: FilterChipWidget(
            label: _filters[i],
            isActive: _activeFilter == _filters[i],
            onTap: () => _selectFilter(_filters[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCarousel() {
    final provider = context.watch<MovieProvider>();
    final movies = provider.featured;
    final heroHeight = ScreenMetrics.of(context).heroHeight;

    if (provider.homeState == LoadState.loading && movies.isEmpty) {
      return SizedBox(
        height: heroHeight,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Offline with nothing cached: the [OfflineToast] has just said so, and an
    // empty hero would just be a hole in the page.
    if (movies.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: heroHeight,
          child: Focus(
            focusNode: _heroFocusNode,
            child: PageView.builder(
              controller: _heroController,
              itemCount: movies.length,
              itemBuilder: (_, i) => _HeroCard(movie: movies[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContinueWatching({List<Movie>? items}) {
    final library = context.watch<LibraryService>();
    final m = ScreenMetrics.of(context);
    final w = m.landscapeWidth;

    final userItems = items ?? library.continueWatching;

    if (userItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: _landscapeRowHeight(w),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: userItems.length,
        // Built-but-offscreen children are what directional focus traversal
        // can move to, so a TV row must keep its neighbours alive.
        scrollCacheExtent: ScrollCacheExtent.pixels(m.scrollCacheExtent),
        separatorBuilder: (_, __) => SizedBox(width: m.rowGap),
        itemBuilder: (_, i) =>
            LandscapeCardFromMovie(movie: userItems[i], width: w),
      ),
    );
  }

  /// Landscape card is 16:9 plus progress bar and two text lines (~64px).
  static double _landscapeRowHeight(double cardWidth) =>
      cardWidth * 9 / 16 + 64;

  Widget _posterRow(List<Movie> movies) {
    final m = ScreenMetrics.of(context);
    final w = m.posterWidth;

    return SizedBox(
      height: _posterRowHeight(w),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: movies.length,
        // Built-but-offscreen children are what directional focus traversal
        // can move to, so a TV row must keep its neighbours alive.
        scrollCacheExtent: ScrollCacheExtent.pixels(m.scrollCacheExtent),
        separatorBuilder: (_, __) => SizedBox(width: m.rowGap),
        itemBuilder: (_, i) => PosterCard(
          movie: movies[i],
          width: w,
        ),
      ),
    );
  }

  // Fallback: filter the already-loaded TMDB rows while discover is
  // loading or if it failed.
  List<Movie> _fallbackGenreMovies(MovieProvider provider) {
    final seen = <String>{};
    final genre = _activeFilter.toLowerCase();
    final out = <Movie>[];
    for (final m in [
      ...provider.trending,
      ...provider.popular,
      ...provider.topRated,
      ...provider.nowPlaying,
      ...provider.featured,
    ]) {
      if (!seen.add(m.id)) continue;
      if (m.genres.any((g) => g.toLowerCase() == genre)) out.add(m);
    }
    return out;
  }

  /// Poster card is 2:3 plus ~48px of title/genre text below.
  static double _posterRowHeight(double posterWidth) => posterWidth * 1.5 + 48;
}

class _GenreLoadingStrip extends StatelessWidget {
  const _GenreLoadingStrip();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
}

// Hero banner card
class _HeroCard extends StatelessWidget {
  final Movie movie;

  const _HeroCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    final showBadges = context.select((SettingsService s) => s.showBadges);
    final showRatings = context.select((SettingsService s) => s.showRatings);
    final showRuntime = context.select((SettingsService s) => s.showRuntime);
    final heroHeight = ScreenMetrics.of(context).heroHeight;
    final contentLang =
        context.select((SettingsService s) => s.contentLanguage);
    final library = context.watch<LibraryService>();
    final inWatchlist = library.isInWatchlist(movie);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Backdrop
            CineArtwork(
              imageUrl: movie.backdropUrl.isNotEmpty
                  ? movie.backdropUrl
                  : movie.imageUrl,
              fallbackUrl: movie.imageUrl,
              width: double.infinity,
              height: heroHeight,
              fit: BoxFit.cover,
              title: movie.title,
            ),
            // Gradient overlay
            Container(
              height: heroHeight,
              decoration: const BoxDecoration(
                gradient: AppColors.heroGradient,
              ),
            ),
            // Video Quality / Tech Badges positioned elegantly at Top Right
            if (showBadges && movie.badges.isNotEmpty)
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: movie.badges
                      .take(2)
                      .map((b) => Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                b,
                                style: AppTheme.badge.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            // Content
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trending badge
                    if (movie.isTrending) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department_rounded,
                                color: AppColors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'TRENDING #1 TODAY',
                              style: AppTheme.badge.copyWith(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Rating + genres + duration (+ optional Content Language)
                    Row(
                      children: [
                        if (showRatings) ...[
                          StarRating(rating: movie.rating),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            _buildMetadataLine(movie.genreString,
                                movie.duration, contentLang, showRuntime),
                            style: AppTheme.metadata,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Title
                    Text(movie.title, style: AppTheme.heroTitle),
                    const SizedBox(height: 6),
                    // Description
                    Text(
                      movie.description,
                      style: AppTheme.metadata.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: _WatchNowButton(movie: movie),
                        ),
                        const SizedBox(width: 10),
                        TvFocusable(
                          scale: 1.12,
                          borderRadius: 24,
                          semanticLabel: inWatchlist
                              ? 'Remove from watchlist'
                              : 'Add to watchlist',
                          onSelect: () => library.toggleWatchlist(movie),
                          child: _CircleActionButton(
                            icon: inWatchlist
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            iconColor: inWatchlist
                                ? AppColors.primaryLight
                                : AppColors.white,
                            onTap: () => library.toggleWatchlist(movie),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TvFocusable(
                          scale: 1.12,
                          borderRadius: 24,
                          semanticLabel: 'More info',
                          onSelect: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MovieDetailScreen(movie: movie),
                              ),
                            );
                          },
                          child: _CircleActionButton(
                            icon: Icons.info_outline_rounded,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MovieDetailScreen(movie: movie),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  static String _buildMetadataLine(
      String genres, String duration, String contentLang, bool showRuntime) {
    final langCode = contentLang.length >= 2
        ? contentLang.substring(0, 2).toUpperCase()
        : contentLang.toUpperCase();
    final parts = <String>[genres];
    if (showRuntime) parts.add(duration);
    parts.add(langCode);
    return parts.join(' • ');
  }
}

class _WatchNowButton extends StatelessWidget {
  final Movie movie;
  const _WatchNowButton({required this.movie});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: () => launchPlayer(context, movie),
      semanticLabel: 'Watch ${movie.title}',
      borderRadius: 999,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          onTap: () => launchPlayer(context, movie),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.play_arrow_rounded,
                    color: AppColors.white, size: 20),
                const SizedBox(width: 6),
                Text(
                  'Watch Now',
                  style: AppTheme.badge.copyWith(
                    fontSize: 14,
                    color: AppColors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _CircleActionButton({
    required this.icon,
    this.iconColor = AppColors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.outlineVariant,
            width: 1,
          ),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }
}

/// The home premiere promo: what to come back for next, and when.
///
/// Shows the soonest dated TMDB release rather than a fixed card, so the
/// countdown, artwork, synopsis and title all belong to a real film, and
/// "Remind Me" hands an actual alarm to [NotificationService] instead of being
/// decorative. Renders nothing when nothing is scheduled ahead.
class _PremiereBanner extends StatefulWidget {
  const _PremiereBanner();

  @override
  State<_PremiereBanner> createState() => _PremiereBannerState();
}

class _PremiereBannerState extends State<_PremiereBanner> {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  Movie? _movie;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orchestrator = context.read<MediaOrchestratorService>();
    Movie? picked;
    try {
      final now = DateTime.now();
      final upcoming = await orchestrator.fetchUpcoming(limit: 12);
      // Undated entries can't carry a countdown, so they can't headline.
      final pending = upcoming
          .where((m) =>
              m.releaseDate != null &&
              m.releaseDate!.isAfter(now) &&
              m.title.isNotEmpty)
          .toList()
        ..sort((a, b) => a.releaseDate!.compareTo(b.releaseDate!));
      picked = pending.isNotEmpty ? pending.first : null;
    } catch (_) {
      picked = null;
    }
    if (!mounted) return;
    setState(() => _movie = picked);
  }

  String _premiereLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final inDays = day.difference(today).inDays;
    if (inDays == 0) return 'Premieres tonight';
    if (inDays == 1) return 'Premieres tomorrow';
    // Under a week out, the weekday is the useful fact; past that it repeats.
    if (inDays < 7) return 'Premieres ${_weekdays[day.weekday - 1]}';
    final stamped = '${_months[day.month - 1]} ${day.day}';
    return day.year == now.year
        ? 'Premieres $stamped'
        : 'Premieres $stamped, ${day.year}';
  }

  void _openDetails(Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = _movie;
    final date = movie?.releaseDate;
    if (movie == null || date == null) return const SizedBox.shrink();

    final tv = context.select((SettingsService s) => s.useTvLayout);
    final notifications = context.watch<NotificationService>();
    final reminded = notifications.hasPremiereReminder(movie);
    final meta = [
      if (movie.year > 0) '${movie.year}',
      if (movie.genreString.isNotEmpty) movie.genreString,
      if (movie.duration.isNotEmpty) movie.duration,
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TvFocusable(
        semanticLabel: '${movie.title}, ${_premiereLabel(date)}',
        onSelect: () => _openDetails(movie),
        // TvFocusable only reacts to the D-pad; a finger needs its own tap
        // target. The nested Remind Me button still wins the gesture arena,
        // because hit-testing reaches the innermost recogniser first.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetails(movie),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: tv ? 212 : 176,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CineArtwork(
                    imageUrl: movie.backdropUrl.isNotEmpty
                        ? movie.backdropUrl
                        : movie.imageUrl,
                    fallbackUrl: movie.imageUrl,
                    title: movie.title,
                  ),
                  // Studio backdrops vary wildly in brightness, so the card keeps
                  // its own tint under the scrim that carries the text.
                  const DecoratedBox(
                      decoration:
                          BoxDecoration(gradient: AppColors.exclusiveGradient)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xF0000000),
                          Color(0xB3000000),
                          Color(0x26000000)
                        ],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      movie.isExclusive
                                          ? 'EXCLUSIVE'
                                          : 'COMING SOON',
                                      style:
                                          AppTheme.badge.copyWith(fontSize: 9),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _premiereLabel(date),
                                      style: AppTheme.metadata.copyWith(
                                        color: AppColors.primaryLight,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                movie.title,
                                style:
                                    AppTheme.heroTitle.copyWith(fontSize: 20),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (meta.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  meta,
                                  style: AppTheme.metadata.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 11.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (movie.description.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  movie.description.trim(),
                                  style: AppTheme.metadata.copyWith(
                                    color: AppColors.onSurface,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        TvFocusable(
                          scale: 1.06,
                          borderRadius: 22,
                          semanticLabel: reminded
                              ? 'Cancel reminder for ${movie.title}'
                              : 'Remind me when ${movie.title} premieres',
                          onSelect: () =>
                              notifications.togglePremiereReminder(movie),
                          child: FilledButton.icon(
                            onPressed: () =>
                                notifications.togglePremiereReminder(movie),
                            icon: Icon(
                              reminded
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_none_rounded,
                              size: 16,
                            ),
                            label:
                                Text(reminded ? 'Reminder set' : 'Remind Me'),
                            style: FilledButton.styleFrom(
                              backgroundColor: reminded
                                  ? AppColors.primary
                                  : AppColors.surfaceContainerHighest,
                              foregroundColor: AppColors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
