import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/movie.dart';
import '../../core/services/library_service.dart';
import '../../core/services/settings_service.dart';
import '../player/trailer_screen.dart';
import '../../core/services/media_delivery_service.dart';
import '../../core/services/media_orchestrator_service.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/cine_artwork.dart';
import '../../shared/widgets/tv_focus.dart';
import '../home/widgets/media_cards.dart';
import '../player/play_launcher.dart';

class MovieDetailScreen extends StatefulWidget {
  final Movie movie;
  const MovieDetailScreen({super.key, required this.movie});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  List<SeasonItem> _seasons = [];
  int _selectedSeasonNumber = 1;
  List<EpisodeItem> _episodes = [];
  bool _loadingSeasons = true;
  bool _loadingEpisodes = false;
  List<Movie> _moreLikeThis = [];

  static const double _backdropHeight = 340;
  static const double _barHeight = 60;
  static const double _titleStripHeight = 44;

  /// True once the backdrop has scrolled up behind the buttons, which is when
  /// the pinned title strip takes over from the hero artwork.
  bool _chromeCollapsed = false;

  @override
  void initState() {
    super.initState();
    if (widget.movie.isTV) {
      _loadSeasons();
    }
    _loadMoreLikeThis();
  }

  Future<void> _loadMoreLikeThis() async {
    final movie = widget.movie;
    if (movie.tmdbId <= 0) return;
    final orchestrator = context.read<MediaOrchestratorService>();
    try {
      final results = await Future.wait([
        orchestrator.fetchSimilar(movie.tmdbId, limit: 20, isTv: movie.isTV),
        orchestrator.fetchRecommendations(movie.tmdbId,
            limit: 20, isTv: movie.isTV),
      ]);
      final seen = <String>{movie.id};
      final out = <Movie>[];
      for (final m in [...results[0], ...results[1]]) {
        if (seen.add(m.id)) out.add(m);
      }
      if (!mounted) return;
      setState(() => _moreLikeThis = out.take(20).toList());
    } catch (_) {
      // Leave the section hidden on failure.
    }
  }

  Future<void> _loadSeasons() async {
    final orchestrator = context.read<MediaOrchestratorService>();
    final seasons = await orchestrator.fetchSeasons(widget.movie);
    if (!mounted) return;
    setState(() {
      _seasons = seasons;
      _loadingSeasons = false;
      if (seasons.isNotEmpty) {
        final initialSeason = widget.movie is TVShow
            ? (widget.movie as TVShow).season
            : seasons.first.seasonNumber;
        _selectedSeasonNumber =
            seasons.any((s) => s.seasonNumber == initialSeason)
                ? initialSeason
                : seasons.first.seasonNumber;
      }
    });
    if (seasons.isNotEmpty) {
      _loadEpisodes(_selectedSeasonNumber);
    }
  }

  Future<void> _loadEpisodes(int seasonNumber) async {
    setState(() {
      _selectedSeasonNumber = seasonNumber;
      _loadingEpisodes = true;
    });
    final orchestrator = context.read<MediaOrchestratorService>();
    final eps =
        await orchestrator.fetchSeasonEpisodes(widget.movie, seasonNumber);
    if (!mounted) return;
    setState(() {
      _episodes = eps;
      _loadingEpisodes = false;
    });
  }

  void _playEpisode(Movie movie, EpisodeItem ep) {
    final tvShow = TVShow(
      id: movie.id,
      tmdbId: movie.tmdbId,
      imdbId: movie.imdbId,
      title: movie.title,
      description: ep.overview.isNotEmpty ? ep.overview : movie.description,
      imageUrl: ep.stillUrl.isNotEmpty ? ep.stillUrl : movie.imageUrl,
      backdropUrl: ep.stillUrl.isNotEmpty ? ep.stillUrl : movie.backdropUrl,
      rating: ep.rating > 0 ? ep.rating : movie.rating,
      duration: ep.duration,
      genres: movie.genres,
      badges: movie.badges,
      year: movie.year,
      ageRating: movie.ageRating,
      isExclusive: movie.isExclusive,
      isTrending: movie.isTrending,
      season: ep.seasonNumber,
      episode: ep.episodeNumber,
      episodeTitle: ep.name,
    );
    context.read<LibraryService>().addToHistory(tvShow);
    launchPlayer(context, tvShow,
        season: ep.seasonNumber, episode: ep.episodeNumber);
  }

  /// Quality for a download that is about to be queued: the pinned setting
  /// when there is one, otherwise the picker. `null` means the sheet was
  /// dismissed, so the caller must abort.
  Future<VideoQuality?> _resolveDownloadQuality({
    required String title,
    required String subtitle,
    bool isTv = false,
    int episodeCount = 1,
  }) {
    final pinned = context.read<SettingsService>().downloadQuality;
    if (!pinned.asksFirst) return Future.value(pinned.videoQuality);
    return _showQualityPickerDialog(
      context: context,
      title: title,
      subtitle: subtitle,
      isTv: isTv,
      episodeCount: episodeCount,
    );
  }

  Future<VideoQuality?> _showQualityPickerDialog({
    required BuildContext context,
    required String title,
    required String subtitle,
    bool isTv = false,
    int episodeCount = 1,
  }) async {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<VideoQuality>(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final options = [
          (
            quality: VideoQuality.fullHd1080,
            label: '1080p Full HD',
            tag: 'Crisp image, best for tablets & big screens',
            icon: Icons.hd_rounded,
          ),
          (
            quality: VideoQuality.hd720,
            label: '720p HD',
            tag: 'Balanced quality & fast download',
            icon: Icons.video_settings_rounded,
          ),
          (
            quality: VideoQuality.sd480,
            label: '480p SD',
            tag: 'Saves storage, quicker transfer',
            icon: Icons.sd_rounded,
          ),
          (
            quality: VideoQuality.highest,
            label: 'Highest available',
            tag: 'Best rendition the source offers',
            icon: Icons.auto_awesome_rounded,
          ),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.download_for_offline_rounded,
                          color: AppColors.secondary, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style:
                                  AppTheme.sectionTitle.copyWith(fontSize: 18),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.metadata
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Download Quality',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...options.map((opt) {
                    final sizeMb = MediaDeliveryService.estimateSizeMb(
                          opt.quality,
                          isTv: isTv,
                        ) *
                        episodeCount;
                    final sizeStr = sizeMb >= 1024
                        ? '${(sizeMb / 1024).toStringAsFixed(1)} GB'
                        : '$sizeMb MB';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: AppColors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop(opt.quality),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(opt.icon,
                                      color: AppColors.secondary, size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        opt.label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        opt.tag,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '~$sizeStr',
                                    style: const TextStyle(
                                      color: AppColors.secondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
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
        );
      },
    );
  }

  Future<void> _downloadCurrentSeason(MediaDeliveryService delivery) async {
    if (_episodes.isEmpty) return;
    HapticFeedback.selectionClick();
    final quality = await _resolveDownloadQuality(
      title: 'Download Season $_selectedSeasonNumber',
      subtitle: '${widget.movie.title} • ${_episodes.length} episodes',
      isTv: true,
      episodeCount: _episodes.length,
    );
    if (quality == null || !mounted) return;

    final count = await delivery.downloadSeason(
      movie: widget.movie,
      seasonNumber: _selectedSeasonNumber,
      episodes: _episodes,
      quality: quality,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Queued $count episodes for Season $_selectedSeasonNumber (${quality.label})'
              : 'All episodes for Season $_selectedSeasonNumber are already in downloads',
          style: AppTheme.badge.copyWith(color: AppColors.white, fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHigh,
      ),
    );
  }

  Future<void> _downloadFullSeries(MediaDeliveryService delivery) async {
    HapticFeedback.selectionClick();
    final quality = await _resolveDownloadQuality(
      title: 'Download Full Series',
      subtitle: '${widget.movie.title} • ${_seasons.length} seasons',
      isTv: true,
      episodeCount: _seasons.length * 8,
    );
    if (quality == null || !mounted) return;

    final orchestrator = context.read<MediaOrchestratorService>();
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Text(
          'Starting full series download (${quality.label})…',
          style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHigh,
        duration: const Duration(seconds: 1),
      ),
    );

    // Load any seasons whose episodes aren't cached yet, then queue them all
    // in order so a sequential queue downloads S1E1 → S1E2 → … naturally.
    final seasonEpisodes = <int, List<EpisodeItem>>{};
    for (final s in _seasons) {
      List<EpisodeItem> eps = s.episodes;
      if (eps.isEmpty) {
        eps = await orchestrator.fetchSeasonEpisodes(
            widget.movie, s.seasonNumber);
      }
      seasonEpisodes[s.seasonNumber] = eps;
    }

    final totalQueued = await delivery.downloadSeries(
      movie: widget.movie,
      seasons: _seasons,
      seasonEpisodes: seasonEpisodes,
      quality: quality,
    );

    if (!mounted) return;
    scaffold.showSnackBar(
      SnackBar(
        content: Text(
          totalQueued > 0
              ? 'Queued $totalQueued episodes from ${_seasons.length} seasons'
              : 'All episodes for this series are already in downloads',
          style: AppTheme.badge.copyWith(color: AppColors.white, fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceContainerHigh,
      ),
    );
  }

  void _showTvDownloadOptionsSheet(Movie movie, MediaDeliveryService delivery) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        void downloadSeason() {
          Navigator.pop(ctx);
          _downloadCurrentSeason(delivery);
        }

        void downloadSeries() {
          Navigator.pop(ctx);
          _downloadFullSeries(delivery);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Download Options',
                    style: AppTheme.sectionTitle.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    movie.title,
                    style: AppTheme.metadata
                        .copyWith(color: AppColors.primaryLight),
                  ),
                  const SizedBox(height: 16),
                  TvButton(
                    autofocus: true,
                    onSelect: downloadSeason,
                    semanticLabel: 'Download season $_selectedSeasonNumber',
                    borderRadius: 12,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.download_rounded,
                            color: AppColors.primaryLight),
                      ),
                      title: Text('Download Season $_selectedSeasonNumber',
                          style: AppTheme.badge.copyWith(fontSize: 15)),
                      subtitle: Text(
                        '${_episodes.length} episodes ready to download',
                        style: AppTheme.metadata
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      onTap: downloadSeason,
                    ),
                  ),
                  const Divider(color: AppColors.outlineVariant, height: 20),
                  TvButton(
                    onSelect: downloadSeries,
                    semanticLabel: 'Download full series',
                    borderRadius: 12,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.video_library_rounded,
                            color: AppColors.secondary),
                      ),
                      title: const Text('Download Full Series',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 15)),
                      subtitle: Text(
                        'All ${_seasons.length} seasons for offline viewing',
                        style: AppTheme.metadata
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      onTap: downloadSeries,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final library = context.watch<LibraryService>();
    final isBookmarked = library.isInWatchlist(movie);
    final isFavorited = library.isFavorite(movie);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NotificationListener<ScrollUpdateNotification>(
        // depth 0 is this page's own scroll view; the cast and episode rows
        // nested inside it report their own offsets.
        onNotification: (n) {
          if (n.depth != 0) return false;
          final collapsed = n.metrics.pixels >= _backdropHeight - _barHeight;
          if (collapsed != _chromeCollapsed) {
            setState(() => _chromeCollapsed = collapsed);
          }
          return false;
        },
        child: CustomScrollView(
          // Directional focus can only move to children that are already
          // built, so TV layout keeps the rows further down alive.
          scrollCacheExtent: ScrollCacheExtent.pixels(
            context.select((SettingsService s) => s.useTvLayout) ? 2000 : 250,
          ),
          slivers: [
            _buildBackdrop(movie, isBookmarked, isFavorited, library),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TitleStripDelegate(
                title: movie.title,
                height: _titleStripHeight,
                visible: _chromeCollapsed,
              ),
            ),
            SliverToBoxAdapter(child: _buildDetails(movie)),
            SliverToBoxAdapter(child: _buildActions(movie, library)),
            if (movie.isTV)
              SliverToBoxAdapter(child: _buildSeasonsAndEpisodes(movie)),
            SliverToBoxAdapter(child: _buildCast()),
            SliverToBoxAdapter(child: _buildMoreLikeThis()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildBackdrop(Movie movie, bool isBookmarked, bool isFavorited,
      LibraryService library) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      snap: false,
      primary: true,
      backgroundColor: AppColors.background.withValues(alpha: 0.94),
      surfaceTintColor: AppColors.surfaceContainerHigh,
      scrolledUnderElevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.6),
      expandedHeight: _backdropHeight,
      collapsedHeight: _barHeight,
      toolbarHeight: _barHeight,
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      actions: [
        TvChrome(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFocusable(
                  onSelect: () => library.toggleFavorite(movie),
                  semanticLabel: 'Favourite',
                  scale: 1.1,
                  borderRadius: 18,
                  child: GestureDetector(
                    onTap: () => library.toggleFavorite(movie),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh
                            .withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isFavorited
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color:
                            isFavorited ? AppColors.secondary : AppColors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TvFocusable(
                  onSelect: () => library.toggleWatchlist(movie),
                  semanticLabel: 'Watchlist',
                  scale: 1.1,
                  borderRadius: 18,
                  child: GestureDetector(
                    onTap: () => library.toggleWatchlist(movie),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh
                            .withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isBookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: isBookmarked
                            ? AppColors.primaryLight
                            : AppColors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      leading: TvChrome(
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: TvFocusable(
            onSelect: () => Navigator.of(context).pop(),
            semanticLabel: 'Back',
            // A pushed route inherits no focus, so the new screen would open
            // with the ring still on the card behind it — invisible, and the
            // remote looks dead until a press happens to land here. The back
            // button is the one stop that is always on screen at the top, so
            // asking for it can't drag content out of view the way focusing a
            // mid-page card would.
            autofocus: context.select((SettingsService s) => s.useTvLayout),
            scale: 1.1,
            borderRadius: 18,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppColors.white, size: 18),
              ),
            ),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        // No title here: FlexibleSpaceBar parks one at the bottom of the
        // collapsed bar, which is exactly where the back / favourite /
        // watchlist buttons sit. The title gets its own pinned strip below.
        background: Stack(
          fit: StackFit.expand,
          children: [
            CineArtwork(
              imageUrl: movie.backdropUrl.isNotEmpty
                  ? movie.backdropUrl
                  : movie.imageUrl,
              fallbackUrl: movie.imageUrl,
              fit: BoxFit.cover,
              title: movie.title,
            ),
            Container(
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
            ),
            // Play button overlay (only visible in expanded state via flexibleSpace)
            Center(
              child: TvFocusable(
                semanticLabel: 'Play',
                borderRadius: 32,
                onSelect: () {
                  if (movie.isTV && _episodes.isNotEmpty) {
                    _playEpisode(movie, _episodes.first);
                  } else {
                    launchPlayer(context, movie);
                  }
                },
                child: GestureDetector(
                  onTap: () {
                    if (movie.isTV && _episodes.isNotEmpty) {
                      _playEpisode(movie, _episodes.first);
                    } else {
                      launchPlayer(context, movie);
                    }
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4), width: 2),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 40),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(Movie movie) {
    return Padding(
      // The pinned title strip already sits between the hero and this block,
      // so the old 20px gap would double up.
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...movie.badges.map((b) => TechBadge(label: b)),
              TechBadge(
                label: movie.ageRating,
                bgColor: AppColors.outlineVariant,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title
          Text(movie.title, style: AppTheme.heroTitle),
          const SizedBox(height: 8),
          // Metadata row
          Row(
            children: [
              StarRating(rating: movie.rating),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${movie.year}  •  ${movie.genreString}  •  ${movie.duration}',
                  style: AppTheme.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Description
          Text(
            movie.description,
            style: AppTheme.metadata.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildActions(Movie movie, LibraryService library) {
    final delivery = context.watch<MediaDeliveryService>();

    final bool isDownloading = movie.isTV
        ? delivery.getDownloadingEpisodesCount(
                movie.id, _selectedSeasonNumber) >
            0
        : delivery.isMovieDownloading(movie.id);
    final bool isDownloaded =
        !movie.isTV && delivery.isMovieDownloaded(movie.id);

    void watchNow() {
      if (movie.isTV && _episodes.isNotEmpty) {
        _playEpisode(movie, _episodes.first);
      } else {
        launchPlayer(context, movie);
      }
    }

    Future<void> showTrailer() async {
      HapticFeedback.lightImpact();
      final scaffold = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      scaffold.showSnackBar(
        const SnackBar(
          content: Text(
            'Finding official trailer…',
            style: TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );

      final orchestrator = context.read<MediaOrchestratorService>();
      final trailerKey =
          await orchestrator.fetchTrailer(movie.tmdbId, isTv: movie.isTV);

      if (trailerKey != null && trailerKey.isNotEmpty) {
        // In-app player covers mobile + web; other platforms
        // (desktop) fall back to the system browser.
        final supportsEmbed = kIsWeb ||
            defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
        if (supportsEmbed) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => TrailerScreen(
                videoId: trailerKey,
                title: movie.title,
                backdropUrl: movie.backdropUrl,
              ),
            ),
          );
        } else {
          final uri = Uri.parse('https://www.youtube.com/watch?v=$trailerKey');
          final launched =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!launched) {
            await launchUrl(uri, mode: LaunchMode.platformDefault);
          }
        }
      } else {
        scaffold.showSnackBar(
          SnackBar(
            content: Text(
              'No trailer available for "${movie.title}"',
              style:
                  AppTheme.badge.copyWith(color: AppColors.white, fontSize: 13),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    }

    Future<void> download() async {
      HapticFeedback.selectionClick();
      final scaffold = ScaffoldMessenger.of(context);
      if (movie.isTV) {
        _showTvDownloadOptionsSheet(movie, delivery);
        return;
      }
      if (isDownloading) return;
      final quality = await _resolveDownloadQuality(
        title: 'Download Movie',
        subtitle: movie.title,
        isTv: false,
      );
      if (quality == null || !mounted) return;

      final res = await delivery.downloadMovie(movie, quality: quality);
      if (!mounted) return;
      String msg;
      switch (res.reason) {
        case DownloadRejectReason.storageFull:
          msg = 'Not enough storage — raise the cap in Settings';
          break;
        case DownloadRejectReason.wifiRequired:
          msg = 'Downloads are Wi-Fi only — connect to Wi-Fi';
          break;
        case DownloadRejectReason.duplicate:
          msg = '"${movie.title}" is already in downloads';
          break;
        default:
          msg =
              'Downloading "${movie.title}" (${quality.label}) for offline viewing';
      }
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style:
                AppTheme.badge.copyWith(color: AppColors.white, fontSize: 13),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          // Watch Now button
          SizedBox(
            width: double.infinity,
            child: TvButton(
              onSelect: watchNow,
              semanticLabel: 'Watch now',
              child: FilledButton.icon(
                onPressed: watchNow,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(movie.isTV && _episodes.isNotEmpty
                    ? 'Watch S$_selectedSeasonNumber E${_episodes.first.episodeNumber}'
                    : 'Watch Now'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: AppTheme.badge
                      .copyWith(fontSize: 16, color: AppColors.white),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Trailer + Download buttons
          Row(
            children: [
              Expanded(
                child: TvButton(
                  onSelect: showTrailer,
                  semanticLabel: 'Trailer',
                  child: OutlinedButton.icon(
                    onPressed: showTrailer,
                    icon:
                        const Icon(Icons.play_circle_outline_rounded, size: 18),
                    label: const Text('Trailer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      side: const BorderSide(color: AppColors.outlineVariant),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TvButton(
                  onSelect: download,
                  semanticLabel: 'Download',
                  child: OutlinedButton.icon(
                    onPressed: download,
                    icon: isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(movie.isTV
                        ? (isDownloading ? 'Downloading…' : 'Download')
                        : (isDownloading
                            ? 'Downloading…'
                            : isDownloaded
                                ? 'Downloaded'
                                : 'Download')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      side: BorderSide(
                          color: isDownloaded
                              ? AppColors.primary
                              : AppColors.outlineVariant),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonsAndEpisodes(Movie movie) {
    final delivery = context.watch<MediaDeliveryService>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with quick action download buttons
          Row(
            children: [
              Text('Seasons & Episodes',
                  style: AppTheme.sectionTitle.copyWith(fontSize: 18)),
              const Spacer(),
              if (!_loadingSeasons && _seasons.isNotEmpty) ...[
                // Season download pill
                TvButton(
                  onSelect: () => _downloadCurrentSeason(delivery),
                  semanticLabel: 'Download season $_selectedSeasonNumber',
                  borderRadius: 20,
                  child: InkWell(
                    onTap: () => _downloadCurrentSeason(delivery),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.download_rounded,
                              size: 14, color: AppColors.primaryLight),
                          const SizedBox(width: 4),
                          Text(
                            'Season $_selectedSeasonNumber',
                            style: AppTheme.badge.copyWith(
                                fontSize: 11, color: AppColors.primaryLight),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Full series download pill
                TvButton(
                  onSelect: () => _downloadFullSeries(delivery),
                  semanticLabel: 'Download full series',
                  borderRadius: 20,
                  child: InkWell(
                    onTap: () => _downloadFullSeries(delivery),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.download_for_offline_rounded,
                              size: 14, color: AppColors.secondary),
                          const SizedBox(width: 4),
                          Text(
                            'Full Series',
                            style: AppTheme.badge.copyWith(
                                fontSize: 11, color: AppColors.secondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Season Chips Horizontal Row
          if (_loadingSeasons)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_seasons.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No season data found for this title.',
                style: AppTheme.metadata
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            )
          else ...[
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _seasons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final season = _seasons[i];
                  final isSelected =
                      season.seasonNumber == _selectedSeasonNumber;
                  final downloadedInSeason =
                      delivery.getDownloadedEpisodesCount(
                          movie.id, season.seasonNumber);
                  return TvFocusable(
                    onSelect: () {
                      if (!isSelected) {
                        HapticFeedback.selectionClick();
                        _loadEpisodes(season.seasonNumber);
                      }
                    },
                    semanticLabel: season.name,
                    scale: 1.05,
                    borderRadius: 20,
                    child: GestureDetector(
                      onTap: () {
                        if (!isSelected) {
                          HapticFeedback.selectionClick();
                          _loadEpisodes(season.seasonNumber);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.secondary
                              : AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.secondary
                                : AppColors.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              season.name,
                              style: AppTheme.badge.copyWith(
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.onSurfaceVariant,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (downloadedInSeason > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.black.withValues(alpha: 0.25)
                                      : AppColors.primaryLight
                                          .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$downloadedInSeason dl',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.primaryLight,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Episodes list
            if (_loadingEpisodes)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_episodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No episodes found for Season $_selectedSeasonNumber',
                  style: AppTheme.metadata
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              // Not a nested ListView: directional focus traversal only hops
              // between nodes that share the page's vertical Scrollable, so a
              // second scrollable hides every episode row from the remote.
              Column(
                children: [
                  for (final ep in _episodes) ...[
                    _episodeTile(movie, ep, delivery),
                    if (ep != _episodes.last) const SizedBox(height: 14),
                  ],
                ],
              )
          ],
        ],
      ),
    );
  }

  Widget _episodeTile(
      Movie movie, EpisodeItem ep, MediaDeliveryService delivery) {
    final isDownloaded = delivery.isEpisodeDownloaded(
        movie.id, ep.seasonNumber, ep.episodeNumber);
    final isDownloading = delivery.isEpisodeDownloading(
        movie.id, ep.seasonNumber, ep.episodeNumber);
    final downloadItem = delivery.getEpisodeDownload(
        movie.id, ep.seasonNumber, ep.episodeNumber);

    // One handler for the icon's tap and for the D-pad ring wrapped around it.
    final download = isDownloading
        ? null
        : () async {
            HapticFeedback.selectionClick();
            final scaffold = ScaffoldMessenger.of(context);
            if (isDownloaded) {
              scaffold.showSnackBar(
                SnackBar(
                  content: Text(
                    'S${ep.seasonNumber} E${ep.episodeNumber} is already downloaded',
                    style: AppTheme.badge
                        .copyWith(color: AppColors.white, fontSize: 13),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.surfaceContainerHigh,
                ),
              );
            } else {
              final quality = await _resolveDownloadQuality(
                title: 'Download S${ep.seasonNumber} E${ep.episodeNumber}',
                subtitle: ep.name,
                isTv: true,
              );
              if (quality == null || !mounted) return;
              await delivery.downloadEpisode(
                movie: movie,
                season: ep.seasonNumber,
                episode: ep.episodeNumber,
                episodeTitle: ep.name,
                stillUrl: ep.stillUrl,
                duration: ep.duration,
                quality: quality,
              );
              if (!mounted) return;
              scaffold.showSnackBar(
                SnackBar(
                  content: Text(
                    'Downloading S${ep.seasonNumber} E${ep.episodeNumber}: ${ep.name} (${quality.label})',
                    style: AppTheme.badge
                        .copyWith(color: AppColors.white, fontSize: 13),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.surfaceContainerHigh,
                ),
              );
            }
          };

    return Row(
      children: [
        Expanded(
          child: TvFocusable(
            onSelect: () => _playEpisode(movie, ep),
            semanticLabel: 'E${ep.episodeNumber} ${ep.name}',
            scale: 1.02,
            borderRadius: 16,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                // The ink response builds its own focus node above its
                // child, which would take the traversal stop away from
                // the ring wrapping the row.
                canRequestFocus: false,
                onTap: () => _playEpisode(movie, ep),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Episode Thumbnail (16:9)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 120,
                              height: 70,
                              child: CineArtwork(
                                imageUrl: ep.stillUrl.isNotEmpty
                                    ? ep.stillUrl
                                    : (movie.backdropUrl.isNotEmpty
                                        ? movie.backdropUrl
                                        : movie.imageUrl),
                                fallbackUrl: movie.imageUrl,
                                fit: BoxFit.cover,
                                title: ep.name,
                              ),
                            ),
                          ),
                          // Play icon badge
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      width: 1.5),
                                ),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                          // Duration badge
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ep.duration,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),

                      // Episode Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'E${ep.episodeNumber}',
                                  style: AppTheme.badge.copyWith(
                                    color: AppColors.primaryLight,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    ep.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.cardTitle
                                        .copyWith(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            if (ep.rating > 0 || ep.airDate.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (ep.rating > 0) ...[
                                    const Icon(Icons.star_rounded,
                                        size: 12, color: AppColors.secondary),
                                    const SizedBox(width: 2),
                                    Text(
                                      ep.rating.toStringAsFixed(1),
                                      style: AppTheme.metadata.copyWith(
                                          fontSize: 10,
                                          color: AppColors.secondary),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (ep.airDate.isNotEmpty)
                                    Text(
                                      ep.airDate,
                                      style: AppTheme.metadata
                                          .copyWith(fontSize: 10),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              ep.overview.isNotEmpty
                                  ? ep.overview
                                  : 'No overview available.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.metadata.copyWith(
                                fontSize: 11,
                                height: 1.3,
                                color: AppColors.onSurfaceVariant,
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
        ),
        const SizedBox(width: 8),

        // A sibling of the row rather than a child of it. Directional traversal is
        // purely geometric: an icon inside the row's own band wins every Down
        // press, so the walk never gets past the first row. Beside the row the
        // ladder is the episodes, and Right steps across to the icon.
        TvButton(
          onSelect: download,
          semanticLabel: 'Download episode',
          borderRadius: 12,
          child: IconButton(
            onPressed: download,
            icon: isDownloaded
                ? const Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryLight, size: 22)
                : isDownloading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: downloadItem?.progress,
                          color: AppColors.secondary,
                        ),
                      )
                    : const Icon(Icons.download_rounded,
                        color: AppColors.onSurfaceVariant, size: 22),
            tooltip: isDownloaded
                ? 'Downloaded'
                : isDownloading
                    ? 'Downloading…'
                    : 'Download episode',
          ),
        ),
      ],
    );
  }

  Widget _buildCast() {
    final cast = [
      {
        'name': 'Elena Vasquez',
        'role': 'Dr. Aria Kwan',
        'img':
            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&q=80'
      },
      {
        'name': 'Marcus Thorne',
        'role': 'Commander Rex',
        'img':
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&q=80'
      },
      {
        'name': 'Sofia Delacroix',
        'role': 'Agent Vale',
        'img':
            'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&q=80'
      },
      {
        'name': 'Jake Oduya',
        'role': 'Chief Morrow',
        'img':
            'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=100&q=80'
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SectionHeader(title: 'Cast'),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final c = cast[i];
              return Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.outlineVariant, width: 1.5),
                      image: DecorationImage(
                        image: NetworkImage(c['img']!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 65,
                    child: Text(
                      c['name']!,
                      style: AppTheme.badge.copyWith(fontSize: 10),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    c['role']!,
                    style: AppTheme.metadata.copyWith(fontSize: 9),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMoreLikeThis() {
    if (_moreLikeThis.isEmpty) return const SizedBox.shrink();
    final tv = context.select((SettingsService s) => s.useTvLayout);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SectionHeader(title: 'More Like This'),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 260,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _moreLikeThis.length,
            // A remote walking right can only land on built cards.
            scrollCacheExtent: ScrollCacheExtent.pixels(tv ? 900 : 250),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => PosterCard(
              movie: _moreLikeThis[i],
              width: 140,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MovieDetailScreen(movie: _moreLikeThis[i]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Pinned title strip ───────────────────────────────────────────────────────

/// The movie title parked *below* the app bar's buttons rather than sharing
/// their row, which is where FlexibleSpaceBar puts it. Transparent while the
/// hero is open, so it only takes over as the backdrop scrolls away.
class _TitleStripDelegate extends SliverPersistentHeaderDelegate {
  _TitleStripDelegate({
    required this.title,
    required this.height,
    required this.visible,
  });

  final String title;
  final double height;
  final bool visible;

  static const _fade = Duration(milliseconds: 160);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return AnimatedContainer(
      duration: _fade,
      color: visible ? AppColors.background : Colors.transparent,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedOpacity(
        duration: _fade,
        opacity: visible ? 1 : 0,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              AppTheme.sectionTitle.copyWith(fontSize: 16, letterSpacing: -0.2),
        ),
      ),
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _TitleStripDelegate oldDelegate) =>
      oldDelegate.visible != visible ||
      oldDelegate.title != title ||
      oldDelegate.height != height;
}
