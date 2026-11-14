import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/screen_metrics.dart';

import '../../core/models/movie.dart';
import '../../core/providers/movie_provider.dart';
import '../../core/services/library_service.dart';
import '../../core/services/settings_service.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/cine_artwork.dart';
import '../../shared/widgets/tv_focus.dart';
import '../detail/movie_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  final bool autoFocusSearch;
  final String initialCategory;
  const ExploreScreen({
    super.key,
    this.autoFocusSearch = false,
    this.initialCategory = 'All',
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  String _query = '';
  late String _activeCategory;

  // Every name here must exist in TmdbService.genreNameToId, otherwise
  // MovieProvider.loadGenre resolves to no TMDB genre id and shows an empty
  // grid.
  final List<String> _categories = [
    'All',
    'Movies',
    'TV Shows',
    'Action',
    'Adventure',
    'Animation',
    'Sci-Fi',
    'Drama',
    'Thriller',
    'Mystery',
    'Horror',
    'Fantasy',
    'Comedy',
    'Family',
    'Romance',
    'Crime',
    'Documentary',
  ];

  final List<Map<String, dynamic>> _genres = [
    {
      'name': 'Action',
      'icon': Icons.bolt_rounded,
      'color': const Color(0xFFFF6E6C)
    },
    {
      'name': 'Adventure',
      'icon': Icons.explore_rounded,
      'color': const Color(0xFF039BE5)
    },
    {
      'name': 'Animation',
      'icon': Icons.animation_rounded,
      'color': const Color(0xFFF57C00)
    },
    {
      'name': 'Sci-Fi',
      'icon': Icons.rocket_launch_rounded,
      'color': const Color(0xFF7C4DFF)
    },
    {
      'name': 'Drama',
      'icon': Icons.theater_comedy_rounded,
      'color': const Color(0xFFFFB300)
    },
    {
      'name': 'Thriller',
      'icon': Icons.warning_amber_rounded,
      'color': const Color(0xFF26C6DA)
    },
    {
      'name': 'Mystery',
      'icon': Icons.help_outline_rounded,
      'color': const Color(0xFF9C27B0)
    },
    {
      'name': 'Horror',
      'icon': Icons.local_fire_department_rounded,
      'color': const Color(0xFFE53935)
    },
    {
      'name': 'Fantasy',
      'icon': Icons.auto_awesome_rounded,
      'color': const Color(0xFF43A047)
    },
    {
      'name': 'Comedy',
      'icon': Icons.sentiment_very_satisfied_rounded,
      'color': const Color(0xFF546E7A)
    },
    {
      'name': 'Family',
      'icon': Icons.family_restroom_rounded,
      'color': const Color(0xFF9E9D24)
    },
    {
      'name': 'Romance',
      'icon': Icons.favorite_rounded,
      'color': const Color(0xFFC2185B)
    },
    {
      'name': 'Crime',
      'icon': Icons.gavel_rounded,
      'color': const Color(0xFF795548)
    },
    {
      'name': 'Documentary',
      'icon': Icons.video_library_rounded,
      'color': const Color(0xFF00897B)
    },
  ];

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.initialCategory;
    _searchFocusNode = FocusNode()
      ..onKeyEvent = _onSearchArrow
      ..addListener(_onSearchFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoFocusSearch) _searchFocusNode.requestFocus();
      if (!_specialCategories.contains(_activeCategory)) {
        context.read<MovieProvider>().loadGenre(_activeCategory);
      }
    });
  }

  /// The search bar is a text field, not a card, so it has no focus ring of its
  /// own — on a TV the caret alone is invisible and the D-pad looks like it lost
  /// its way. Rebuild so the outline below can light up with it.
  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
    // On TV the virtual keyboard needs app focus released so it can capture
    // key events. We unfocus the field, let the OS IME open (which is what
    // actually takes input), and re-request focus once the keyboard is gone.
    if (_searchFocusNode.hasFocus &&
        context.read<SettingsService>().useTvLayout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Release focus so the OS IME can own the keyboard.
        _searchFocusNode.unfocus();
        _showTvKeyboard();
        // Watch for the keyboard to dismiss and re-claim focus then.
        _listenForKeyboardDismiss();
      });
    }
  }

  /// Polls `MediaQuery.viewInsets.bottom` once a frame until the keyboard has
  /// closed, then gives focus back to the search field so D-pad arrows work.
  void _listenForKeyboardDismiss() {
    bool keyboardWasOpen = false;
    void check(Duration _) {
      if (!mounted) return;
      final keyboardOpen =
          MediaQuery.of(context).viewInsets.bottom > 50;
      if (keyboardOpen) {
        keyboardWasOpen = true;
      } else if (keyboardWasOpen) {
        // Keyboard just closed — take focus back for arrow-key navigation.
        if (!_searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
        }
        return; // stop scheduling
      }
      WidgetsBinding.instance.addPostFrameCallback(check);
    }

    WidgetsBinding.instance.addPostFrameCallback(check);
  }

  void _showTvKeyboard() {
    if (!mounted) return;
    unawaited(
      SystemChannels.textInput.invokeMethod<void>('TextInput.show').catchError(
            (_) {},
          ),
    );
  }

  /// A text field answers the arrow keys itself — they move the caret — and it
  /// answers them before any app-level shortcut runs, so a remote pressed at
  /// the search bar could never leave it. Handled on the node so the D-pad
  /// wins once there's nothing left to edit.
  KeyEventResult _onSearchArrow(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // OK on a remote arrives as `select`, which the app maps to ActivateIntent —
    // an intent the text field has no action for, so the press would vanish.
    // Use it to (re)raise the IME; that is the only "start typing" gesture a
    // D-pad has.
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      _showTvKeyboard();
      return KeyEventResult.handled;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;

    if (direction == TraversalDirection.left ||
        direction == TraversalDirection.right) {
      // Left/right stay with the caret while there is text to walk through.
      final text = _searchController.text;
      final selection = _searchController.selection;
      final atEdge = text.isEmpty ||
          (direction == TraversalDirection.left
              ? !selection.isValid || selection.baseOffset <= 0
              : !selection.isValid || selection.baseOffset >= text.length);
      if (!atEdge) return KeyEventResult.ignored;
    }

    final policy =
        FocusTraversalGroup.maybeOf(context) ?? ReadingOrderTraversalPolicy();
    policy.inDirection(node, direction);
    return KeyEventResult.handled;
  }

  static const Set<String> _specialCategories = {'All', 'Movies', 'TV Shows'};
  bool get _isGenreCategory => !_specialCategories.contains(_activeCategory);

  final Map<String, FocusNode> _categoryNodes = {};

  FocusNode _categoryNode(String category) => _categoryNodes.putIfAbsent(
      category, () => FocusNode(debugLabel: 'Category $category'));

  /// [fromGrid] means the ring is currently on a genre card that this very
  /// selection unmounts. Focus that dies with its widget leaves the remote with
  /// no highlight at all, so hand it to the chip that took the grid's place.
  void _selectCategory(String category, {bool fromGrid = false}) {
    setState(() {
      _activeCategory = category;
      _query = '';
      _searchController.clear();
    });
    final provider = context.read<MovieProvider>();
    provider.search('');
    if (_specialCategories.contains(category)) {
      provider.clearGenre();
    } else {
      provider.loadGenre(category);
    }
    if (!fromGrid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _categoryNode(category).requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    for (final node in _categoryNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  List<Movie> get _filteredMovies {
    final provider = context.watch<MovieProvider>();

    // Genre categories use the live TMDB discover feed, which works
    // without Trakt auth. The client-filtered catalog below is the
    // fallback while discover is loading or empty.
    if (_query.isEmpty &&
        _isGenreCategory &&
        provider.genreResults.isNotEmpty) {
      return provider.genreResults;
    }

    List<Movie> base;
    if (_query.isNotEmpty && provider.searchResults.isNotEmpty) {
      base = provider.searchResults;
    } else {
      // Gather the catalogue from the home feeds, deduplicated by ID. When
      // offline these are the cached rows, so browse keeps working.
      final Set<String> seenIds = {};
      final List<Movie> combined = [];
      void addAll(Iterable<Movie> list) {
        for (final m in list) {
          if (seenIds.add(m.id)) {
            combined.add(m);
          }
        }
      }

      addAll(provider.trending);
      addAll(provider.popular);
      addAll(provider.topRated);
      addAll(provider.nowPlaying);
      addAll(provider.featured);
      addAll(provider.popularTV);
      addAll(provider.trendingTV);

      if (_query.trim().isEmpty) {
        base = combined;
      } else {
        final q = _query.toLowerCase().trim();
        base = combined.where((m) {
          return m.title.toLowerCase().contains(q) ||
              m.genres.any((g) => g.toLowerCase().contains(q));
        }).toList();
      }
    }

    // Apply category filter
    if (_activeCategory == 'All') {
      return base;
    } else if (_activeCategory == 'Movies') {
      return base.where((m) => !m.isTV).toList();
    } else if (_activeCategory == 'TV Shows') {
      return base.where((m) => m.isTV).toList();
    } else {
      return base
          .where((m) => m.genres
              .any((g) => g.toLowerCase() == _activeCategory.toLowerCase()))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final movies = _filteredMovies;
    final showGenreGrid = _query.isEmpty && _activeCategory == 'All';
    final isLoadingGenre =
        context.watch<MovieProvider>().isLoadingGenre && movies.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        // Directional focus only reaches children that are already built, so
        // TV layout keeps the rows further down the page alive.
        scrollCacheExtent: ScrollCacheExtent.pixels(
          context.select((SettingsService s) => s.useTvLayout) ? 1500 : 250,
        ),
        slivers: [
          _buildSearchHeader(),
          SliverToBoxAdapter(child: _buildCategories()),
          if (showGenreGrid) ..._genreGridSlivers(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Text(
                    _query.isNotEmpty
                        ? 'Search Results'
                        : (_activeCategory != 'All'
                            ? _activeCategory
                            : 'Explore Catalog'),
                    style: AppTheme.sectionTitle.copyWith(fontSize: 18),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${movies.length} titles',
                      style: AppTheme.metadata.copyWith(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (movies.isEmpty)
            SliverToBoxAdapter(
              child: isLoadingGenre
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.movie_filter_rounded,
                              size: 56, color: AppColors.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No matching titles found',
                            style: AppTheme.cardTitle
                                .copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Try adjusting your search query or choosing another category.',
                            textAlign: TextAlign.center,
                            style: AppTheme.metadata
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _SearchResultCard(movie: movies[i]),
                  childCount: movies.length,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: ScreenMetrics.of(context).posterColumns,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      primary: true,
      // The circle button in [title] is the only one. Leaving the implied
      // leading on stacks a second chevron next to it.
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.background.withValues(alpha: 0.94),
      surfaceTintColor: AppColors.surfaceContainerHigh,
      scrolledUnderElevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.6),
      toolbarHeight: 76,
      titleSpacing: 0,
      title: TvChrome(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (Navigator.canPop(context)) ...[
                TvFocusable(
                  onSelect: () => Navigator.pop(context),
                  semanticLabel: 'Back',
                  scale: 1.1,
                  borderRadius: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.white, size: 18),
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _searchFocusNode.hasFocus
                          ? AppColors.white
                          : _query.isNotEmpty
                              ? AppColors.primary
                              : Colors.transparent,
                      width: _searchFocusNode.hasFocus ? 3 : 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Icon(Icons.search_rounded,
                          color: AppColors.onSurfaceVariant, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (v) {
                            setState(() => _query = v);
                            context.read<MovieProvider>().search(v);
                          },
                          style: AppTheme.metadata
                              .copyWith(color: AppColors.white),
                          decoration: InputDecoration(
                            hintText: 'Search movies, shows, genres...',
                            hintStyle: AppTheme.metadata,
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        TvFocusable(
                          semanticLabel: 'Clear search',
                          borderRadius: 999,
                          onSelect: () {
                            _searchController.clear();
                            setState(() => _query = '');
                            context.read<MovieProvider>().search('');
                          },
                          child: GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _query = '');
                              context.read<MovieProvider>().search('');
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: AppColors.outlineVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 12, color: AppColors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Directional traversal only reaches built children, and a genre card
        // hands the ring to a chip that may be far off to the right — so keep
        // the whole short list alive.
        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => TvFocusable(
          focusNode: _categoryNode(_categories[i]),
          onSelect: () => _selectCategory(_categories[i]),
          semanticLabel: _categories[i],
          scale: 1.06,
          borderRadius: 20,
          child: FilterChipWidget(
            label: _categories[i],
            isActive: _activeCategory == _categories[i],
            onTap: () => _selectCategory(_categories[i]),
          ),
        ),
      ),
    );
  }

  /// Genre cards as slivers of the page, not as a nested GridView: directional
  /// focus only hops between nodes that share the focused node's vertical
  /// Scrollable, so a second scrollable here hides the whole grid from the
  /// remote.
  List<Widget> _genreGridSlivers() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Text('Browse by Genre', style: AppTheme.sectionTitle),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ScreenMetrics.of(context).genreColumns,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final g = _genres[i];
              return TvFocusable(
                onSelect: () =>
                    _selectCategory(g['name'] as String, fromGrid: true),
                semanticLabel: g['name'] as String,
                child: _GenreCard(
                  name: g['name'] as String,
                  icon: g['icon'] as IconData,
                  color: g['color'] as Color,
                  onTap: () => _selectCategory(g['name'] as String),
                ),
              );
            },
            childCount: _genres.length,
          ),
        ),
      ),
    ];
  }
}

class _GenreCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GenreCard({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.1)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              name,
              style: AppTheme.cardTitle.copyWith(color: AppColors.white),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: const Duration(milliseconds: 50 * 0))
        .slideY(begin: 0.1, end: 0);
  }
}

class _SearchResultCard extends StatelessWidget {
  final Movie movie;
  const _SearchResultCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    void open() {
      HapticFeedback.selectionClick();
      context.read<LibraryService>().addToHistory(movie);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(movie: movie),
        ),
      );
    }

    return TvFocusable(
      onSelect: open,
      semanticLabel: movie.title,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(16),
            onTap: open,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CineArtwork(
                  imageUrl: movie.imageUrl,
                  fallbackUrl: movie.backdropUrl,
                  fit: BoxFit.cover,
                  title: movie.title,
                ),
                // Gradient overlay
                Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.posterGradient,
                  ),
                ),
                // TV Series badge
                if (movie.isTV)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Text(
                        'TV SERIES',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                // Metadata overlay
                Positioned(
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        movie.title,
                        style: AppTheme.cardTitle.copyWith(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${movie.genreString}${movie.duration.isNotEmpty ? ' • ${movie.duration}' : ''}',
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
        ),
      ),
    );
  }
}
