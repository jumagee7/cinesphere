import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/models/movie.dart';
import '../../core/services/library_service.dart';
import '../../core/services/media_delivery_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/video_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/tv_focus.dart';
import '../player/video_player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, this.active = true});

  /// Whether this tab is the visible one. Hidden tabs stay mounted, and only
  /// the visible page may intercept the system back button.
  final bool active;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

/// Where the downloads browser currently sits: the library root, the Movies
/// folder, the Series list, one show, or one season of that show.
enum _BrowseLevel { root, movies, series, show, season }

class _DownloadsScreenState extends State<DownloadsScreen> {
  late final MediaDeliveryService _delivery;
  late final void Function(DownloadItem) _onComplete;
  final ScrollController _scroll = ScrollController();

  _BrowseLevel _level = _BrowseLevel.root;
  String? _showName;
  int? _seasonNumber;

  @override
  void initState() {
    super.initState();
    _delivery = context.read<MediaDeliveryService>();
    _onComplete = _handleCompletion;
    _delivery.addOnCompleteCallback(_onComplete);
  }

  @override
  void dispose() {
    _delivery.removeOnCompleteCallback(_onComplete);
    _scroll.dispose();
    super.dispose();
  }

  bool get _atRoot => _level == _BrowseLevel.root;

  void _openMovies() => _enter(_BrowseLevel.movies);

  void _openSeries() => _enter(_BrowseLevel.series);

  void _openShow(String show) {
    _enter(_BrowseLevel.show, show: show);
  }

  void _openSeason(String show, int season) {
    _enter(_BrowseLevel.season, show: show, season: season);
  }

  void _enter(_BrowseLevel level, {String? show, int? season}) {
    setState(() {
      _level = level;
      _showName = show;
      _seasonNumber = season;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _restoreFocusIfLost();
  }

  void _goUp() {
    setState(() {
      switch (_level) {
        case _BrowseLevel.season:
          _level = _BrowseLevel.show;
          _seasonNumber = null;
        case _BrowseLevel.show:
          _level = _BrowseLevel.series;
          _showName = null;
        case _BrowseLevel.series:
        case _BrowseLevel.movies:
          _level = _BrowseLevel.root;
        case _BrowseLevel.root:
          break;
      }
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _restoreFocusIfLost();
  }

  /// A folder card that opens another folder is removed with the focus ring on
  /// it; without handing the ring to the new page's first card, a remote is left
  /// with nothing highlighted and the D-pad looks dead.
  void _restoreFocusIfLost() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null && focus is! FocusScopeNode) return;
      FocusScope.of(context).nextFocus();
    });
  }

  void _handleCompletion(DownloadItem item) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.download_done_rounded,
                color: AppColors.primaryLight, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '"${item.title}" downloaded',
                style: AppTheme.badge
                    .copyWith(color: AppColors.white, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                _playDownload(item, playlist: _queueFor(item));
              },
              child: Text('Play',
                  style:
                      AppTheme.badge.copyWith(color: AppColors.primaryLight)),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceContainerHigh,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final delivery = context.watch<MediaDeliveryService>();
    final settings = context.watch<SettingsService>();
    final library = context.watch<LibraryService>();
    final items = delivery.downloads;
    final isEmpty = items.isEmpty;
    final lib = _libraryFor(items);

    final show = (_level == _BrowseLevel.show || _level == _BrowseLevel.season)
        ? lib.showNamed(_showName)
        : null;

    return PopScope(
      canPop: _atRoot || !widget.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_atRoot && widget.active) _goUp();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            // ── App Bar ─────────────────────────────────────────────────────
            SliverAppBar(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      if (!_atRoot) ...[
                        _HeaderIconBtn(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: _goUp,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _headerTitle(lib, show),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.sectionTitle
                                  .copyWith(fontSize: 20, letterSpacing: -0.3),
                            ),
                            if (_headerSubtitle(lib, show) case final sub?)
                              Text(
                                sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.metadata.copyWith(
                                  fontSize: 10,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (delivery.activeCount > 0)
                        _HeaderIconBtn(
                          icon: Icons.pause_rounded,
                          tooltip: 'Pause all',
                          onTap: delivery.pauseAll,
                        ),
                      if (delivery.downloads
                          .any((d) => d.status == DownloadStatus.paused)) ...[
                        const SizedBox(width: 8),
                        _HeaderIconBtn(
                          icon: Icons.play_arrow_rounded,
                          tooltip: 'Resume all',
                          onTap: delivery.resumeAll,
                        ),
                      ],
                      if (delivery.downloads.any((d) => d.isComplete)) ...[
                        const SizedBox(width: 8),
                        _HeaderIconBtn(
                          icon: Icons.delete_sweep_rounded,
                          tooltip: 'Clear completed',
                          onTap: () => _confirmClearCompleted(delivery),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Storage / stats bar (library root only) ─────────────────────
            if (_atRoot)
              SliverToBoxAdapter(
                child: _buildStatsBar(delivery, settings),
              ),

            // ── Sequential mode notice ──────────────────────────────────────
            if (_atRoot &&
                settings.sequentialDownloads &&
                items.any((d) => d.status == DownloadStatus.pending))
              const SliverToBoxAdapter(child: _SequentialQueueNotice()),

            // ── Empty state or folder contents ──────────────────────────────
            if (isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              SliverList(
                delegate: SliverChildListDelegate(
                  _rowsFor(lib, show, library, delivery),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  String _headerTitle(_DownloadLibrary lib, _ShowFolder? show) =>
      switch (_level) {
        _BrowseLevel.root => 'Downloads',
        _BrowseLevel.movies => 'Movies',
        _BrowseLevel.series => 'Series',
        _BrowseLevel.show => show?.name ?? 'Series',
        _BrowseLevel.season => 'Season ${_seasonNumber ?? 1}',
      };

  String? _headerSubtitle(_DownloadLibrary lib, _ShowFolder? show) {
    switch (_level) {
      case _BrowseLevel.root:
        return null;
      case _BrowseLevel.movies:
        return lib.movies.isEmpty ? null : _count(lib.movies.length, 'movie');
      case _BrowseLevel.series:
        return lib.shows.isEmpty ? null : _count(lib.shows.length, 'series');
      case _BrowseLevel.show:
        if (show == null) return null;
        return '${_count(show.seasons.length, 'season')}  •  '
            '${_count(show.episodes.length, 'episode')}';
      case _BrowseLevel.season:
        return show?.name;
    }
  }

  // ── Folder rows ───────────────────────────────────────────────────────────

  List<Widget> _rowsFor(
    _DownloadLibrary lib,
    _ShowFolder? show,
    LibraryService library,
    MediaDeliveryService delivery,
  ) {
    final rows = <Widget>[];

    switch (_level) {
      case _BrowseLevel.root:
        if (lib.active.isNotEmpty) {
          rows.add(_SectionHeader(
            title: 'Downloading',
            count: lib.active.length,
          ));
          rows.addAll(lib.active.map((item) => _activeCard(item, delivery)));
        }
        if (lib.movies.isNotEmpty) {
          rows.add(_FolderCard(
            title: 'Movies',
            subtitle: _folderMeta(
              _count(lib.movies.length, 'movie'),
              lib.movies.fold<int>(0, (sum, d) => sum + d.sizeMb),
            ),
            semanticLabel: 'Movies folder, ${lib.movies.length} movies',
            onTap: _openMovies,
          ));
        }
        if (lib.shows.isNotEmpty) {
          rows.add(_FolderCard(
            title: 'Series',
            subtitle: _folderMeta(
              _count(lib.shows.length, 'series'),
              lib.shows.fold<int>(
                0,
                (sum, s) =>
                    sum + s.episodes.fold<int>(0, (n, d) => n + d.sizeMb),
              ),
            ),
            semanticLabel: 'Series folder, ${lib.shows.length} series',
            onTap: _openSeries,
          ));
        }

      case _BrowseLevel.movies:
        if (lib.movies.isEmpty) {
          rows.add(const _FolderEmpty(message: 'No downloaded movies'));
        }
        for (final movie in lib.movies) {
          rows.add(_completedCard(movie, lib.movies, library, delivery));
        }

      case _BrowseLevel.series:
        if (lib.shows.isEmpty) {
          rows.add(const _FolderEmpty(message: 'No downloaded series'));
        }
        for (final entry in lib.shows) {
          rows.add(_FolderCard(
            title: entry.name,
            subtitle: _folderMeta(
              '${_count(entry.seasons.length, 'season')}  •  '
              '${_count(entry.episodes.length, 'episode')}',
              entry.episodes.fold<int>(0, (sum, d) => sum + d.sizeMb),
            ),
            semanticLabel: '${entry.name} folder',
            onTap: () => _openShow(entry.name),
          ));
        }

      case _BrowseLevel.show:
        if (show == null) {
          rows.add(const _FolderEmpty(message: 'This show is no longer here'));
          break;
        }
        for (final season in show.seasons.keys) {
          final episodes = show.seasons[season]!;
          rows.add(_FolderCard(
            title: 'Season $season',
            subtitle: _folderMeta(
              _count(episodes.length, 'episode'),
              episodes.fold<int>(0, (sum, d) => sum + d.sizeMb),
            ),
            semanticLabel: 'Season $season folder',
            onTap: () => _openSeason(show.name, season),
          ));
        }

      case _BrowseLevel.season:
        if (show == null || !show.seasons.containsKey(_seasonNumber)) {
          rows.add(
              const _FolderEmpty(message: 'This season is no longer here'));
          break;
        }
        final episodes = show.seasons[_seasonNumber]!;
        for (final episode in episodes) {
          rows.add(_completedCard(
            episode,
            show.episodes,
            library,
            delivery,
          ));
        }
    }
    return rows;
  }

  Widget _activeCard(DownloadItem item, MediaDeliveryService delivery) {
    return _DownloadItemCard(
      key: ValueKey(item.id),
      item: item,
      onPause: item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.pending
          ? () => delivery.pause(item.id)
          : null,
      onResume: item.status == DownloadStatus.paused ||
              item.status == DownloadStatus.failed
          ? () => delivery.resume(item.id)
          : null,
      onCancel: () => _confirmDelete(delivery, item),
    );
  }

  Widget _completedCard(
    DownloadItem item,
    List<DownloadItem> playlist,
    LibraryService library,
    MediaDeliveryService delivery,
  ) {
    return _DownloadItemCard(
      key: ValueKey(item.id),
      item: item,
      watchProgress: library.getWatchProgress(
        _movieForItem(item),
        season: item.season,
        episode: item.episode,
      ),
      onPlay: () => _playDownload(item, playlist: playlist),
      onDelete: () => _confirmDelete(delivery, item),
    );
  }

  String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  String _folderMeta(String counts, int totalMb) {
    final size = totalMb <= 0
        ? ''
        : totalMb >= 1024
            ? '${(totalMb / 1024).toStringAsFixed(1)} GB'
            : '$totalMb MB';
    return size.isEmpty ? counts : '$counts  •  $size';
  }

  // ── Folder-scoped playlists ───────────────────────────────────────────────

  /// Every downloaded title in the folder that contains [item]: all movies for
  /// a movie, or the show's episodes in season/episode order for an episode.
  List<DownloadItem> _queueFor(DownloadItem item) {
    final lib = _libraryFor(context.read<MediaDeliveryService>().downloads);
    if (item.season == null) return lib.movies;
    final show = lib.showNamed((item.seriesName ?? item.title).trim());
    return show?.episodes ?? [item];
  }

  _DownloadLibrary _libraryFor(List<DownloadItem> items) {
    final active = items.where((d) => !d.isComplete).toList();
    final complete = items.where((d) => d.isComplete).toList();
    final movies = complete.where((d) => d.season == null).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    final byShow = <String, Map<int, List<DownloadItem>>>{};
    for (final ep in complete.where((d) => d.season != null)) {
      final show = (ep.seriesName ?? ep.title).trim();
      (byShow[show] ??= {}).putIfAbsent(ep.season!, () => []).add(ep);
    }

    final names = byShow.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final shows = <_ShowFolder>[];
    for (final name in names) {
      final seasons = <int, List<DownloadItem>>{};
      for (final number in byShow[name]!.keys.toList()..sort()) {
        seasons[number] = byShow[name]![number]!
          ..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
      }
      shows.add(_ShowFolder(name, seasons));
    }

    return _DownloadLibrary(active: active, movies: movies, shows: shows);
  }

  /// Rebuilds the catalog model behind a download so the player can persist
  /// progress and resume it through [LibraryService].
  Movie _movieForItem(DownloadItem item) {
    final tmdbId = int.tryParse(item.movieId) ?? 0;
    final genres = item.genre
        .split('•')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toList();
    final badges = item.badge.isEmpty ? const <String>[] : [item.badge];
    if (item.season != null && item.episode != null) {
      return TVShow(
        id: item.movieId,
        tmdbId: tmdbId,
        title: item.seriesName ?? item.title,
        description: '',
        imageUrl: item.imageUrl,
        backdropUrl: '',
        rating: 0,
        duration: item.duration,
        genres: genres,
        badges: badges,
        year: 0,
        ageRating: '',
        season: item.season!,
        episode: item.episode!,
        episodeTitle: item.episodeTitle ?? '',
      );
    }
    return Movie(
      id: item.movieId,
      tmdbId: tmdbId,
      title: item.title,
      description: '',
      imageUrl: item.imageUrl,
      backdropUrl: '',
      rating: 0,
      duration: item.duration,
      genres: genres,
      badges: badges,
      year: 0,
      ageRating: '',
    );
  }

  // ── Play a completed download in the native player ────────────────────────

  void _playDownload(DownloadItem item,
      {List<DownloadItem> playlist = const []}) {
    HapticFeedback.lightImpact();
    final queue = playlist.where((d) => d.isComplete).toList();
    Navigator.push(context, _playerRoute(item, queue.isEmpty ? [item] : queue));
  }

  /// Player route for [item]; previous/next stay inside [queue] and swap the
  /// route in place, so the offline playlist never resolves a network stream.
  Route<void> _playerRoute(DownloadItem item, List<DownloadItem> queue) {
    final delivery = context.read<MediaDeliveryService>();
    final settings = context.read<SettingsService>();
    final index = queue.indexWhere((d) => d.id == item.id);
    final previous = index > 0 ? queue[index - 1] : null;
    final next =
        index >= 0 && index < queue.length - 1 ? queue[index + 1] : null;

    // LICENSE SEAM: offlineLocalPath returns the real file once downloads write
    // to disk; until then the bundled demo clip stands in so playback works.
    final path = delivery.offlineLocalPath(item) ?? VideoService.localDemoAsset;

    return MaterialPageRoute<void>(
      builder: (routeContext) => VideoPlayerScreen.fromUrl(
        url: path,
        title: item.title,
        movie: _movieForItem(item),
        season: item.season,
        episode: item.episode,
        downloadPlayback: true,
        theme: CinePlayerTheme(
          autoPlay: settings.autoPlay,
          defaultSpeed: settings.playbackSpeed,
          subtitlesOn: settings.subtitlesEnabled,
        ),
        onPlayPrevious: previous == null
            ? null
            : () => Navigator.of(routeContext)
                .pushReplacement(_playerRoute(previous, queue)),
        onPlayNext: next == null
            ? null
            : () => Navigator.of(routeContext)
                .pushReplacement(_playerRoute(next, queue)),
      ),
    );
  }

  // ── Delete confirmation ───────────────────────────────────────────────────

  void _confirmDelete(MediaDeliveryService delivery, DownloadItem item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${item.title}"?', style: AppTheme.cardTitle),
        content: Text(
          'Remove this download and free its storage?',
          style: AppTheme.metadata.copyWith(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style:
                    AppTheme.badge.copyWith(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              delivery.delete(item.id);
            },
            child: Text('Delete',
                style: AppTheme.badge.copyWith(color: AppColors.secondary)),
          ),
        ],
      ),
    );
  }

  void _confirmClearCompleted(MediaDeliveryService delivery) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear completed?', style: AppTheme.cardTitle),
        content: Text(
          'Remove all finished downloads from the list and free their storage?',
          style: AppTheme.metadata.copyWith(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style:
                    AppTheme.badge.copyWith(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              delivery.clearCompleted();
            },
            child: Text('Clear',
                style: AppTheme.badge.copyWith(color: AppColors.secondary)),
          ),
        ],
      ),
    );
  }

  // ── Stats bar ─────────────────────────────────────────────────────────────

  Widget _buildStatsBar(
      MediaDeliveryService delivery, SettingsService settings) {
    final maxGb = settings.maxStorageGB.toDouble();
    final usedGb = delivery.usedStorageGb;
    final pct = maxGb > 0 ? (usedGb / maxGb).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage_rounded,
                    color: AppColors.primaryLight, size: 18),
                const SizedBox(width: 8),
                Text('Storage Used', style: AppTheme.cardTitle),
                const Spacer(),
                Text(
                  '${usedGb.toStringAsFixed(2)} GB / ${maxGb.toStringAsFixed(0)} GB',
                  style: AppTheme.metadata
                      .copyWith(color: AppColors.onSurface, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AppColors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  pct > 0.85 ? AppColors.secondary : AppColors.primary,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatPill(
                  label: '${delivery.activeCount} active',
                  icon: Icons.download_rounded,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 8),
                _StatPill(
                  label: '${delivery.completedCount} complete',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                _StatPill(
                  label: settings.downloadQuality.label,
                  icon: Icons.hd_rounded,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                _StatPill(
                  label:
                      settings.sequentialDownloads ? 'Sequential' : 'Parallel',
                  icon: settings.sequentialDownloads
                      ? Icons.view_stream_rounded
                      : Icons.layers_rounded,
                  color: AppColors.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// Downloaded library, split the way the browser navigates it.
class _DownloadLibrary {
  final List<DownloadItem> active;
  final List<DownloadItem> movies;
  final List<_ShowFolder> shows;

  const _DownloadLibrary({
    required this.active,
    required this.movies,
    required this.shows,
  });

  _ShowFolder? showNamed(String? name) {
    if (name == null) return null;
    for (final show in shows) {
      if (show.name == name) return show;
    }
    return null;
  }
}

/// One show folder with its completed episodes grouped by season.
class _ShowFolder {
  final String name;
  final Map<int, List<DownloadItem>> seasons; // season number → episodes

  const _ShowFolder(this.name, this.seasons);

  List<DownloadItem> get episodes =>
      [for (final season in seasons.values) ...season];
}

// ─────────────────────────────────────────────────────────────────────────────
// Folder card
// ─────────────────────────────────────────────────────────────────────────────

class _FolderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String semanticLabel;
  final VoidCallback onTap;

  const _FolderCard({
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: TvFocusable(
          onSelect: onTap,
          semanticLabel: semanticLabel,
          scale: 1.01,
          borderRadius: 16,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.emerald.withValues(alpha: 0.3),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.folder_rounded,
                        color: AppColors.pureWhite, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.cardTitle.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.metadata.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.onSurfaceVariant, size: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderEmpty extends StatelessWidget {
  final String message;
  const _FolderEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
      child: Column(
        children: [
          Icon(Icons.folder_off_outlined,
              size: 48,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                AppTheme.metadata.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.sectionTitle
                  .copyWith(fontSize: 15, letterSpacing: -0.2),
            ),
          ),
          Text(
            '$count',
            style: AppTheme.metadata.copyWith(
              fontSize: 11,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DownloadItem card
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadItemCard extends StatelessWidget {
  final DownloadItem item;
  final double? watchProgress;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  const _DownloadItemCard({
    super.key,
    required this.item,
    this.watchProgress,
    this.onPlay,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDownloading = item.status == DownloadStatus.downloading;
    final isPending = item.status == DownloadStatus.pending;
    final isPaused = item.status == DownloadStatus.paused;
    final isFailed = item.status == DownloadStatus.failed;
    final isComplete = item.isComplete;

    // Enter on the card does the one obvious thing for its status, so the
    // remote has a single stop per row instead of landing on a small icon.
    final onPrimary = isComplete
        ? onPlay
        : (isPaused || isFailed)
            ? onResume
            : onPause;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TvFocusable(
        onSelect: onPrimary,
        semanticLabel: item.title,
        scale: 1.01,
        borderRadius: 16,
        // The row's action buttons are their own focus stops with their own
        // rings; keep the card outline off while one of them is focused.
        ringOnlyWhenPrimary: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: InkWell(
                  onTap: onPrimary,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    children: [
                      // Poster / still
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 54,
                          height: 76,
                          child: item.imageUrl.isNotEmpty
                              ? Image.network(
                                  item.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.surfaceContainerHigh,
                                    child: const Icon(Icons.movie_rounded,
                                        color: AppColors.onSurfaceVariant),
                                  ),
                                )
                              : Container(
                                  color: AppColors.surfaceContainerHigh,
                                  child: const Icon(Icons.movie_rounded,
                                      color: AppColors.onSurfaceVariant),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.cardTitle.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${item.genre}  •  ${item.duration}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.metadata.copyWith(fontSize: 11),
                            ),
                            const SizedBox(height: 6),
                            if (isDownloading || isPending || isPaused) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: isPending ? null : item.progress,
                                  minHeight: 4,
                                  backgroundColor:
                                      AppColors.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation(
                                    isPaused
                                        ? AppColors.onSurfaceVariant
                                        : AppColors.secondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isPending
                                    ? 'Queued'
                                    : isPaused
                                        ? 'Paused  •  ${(item.progress * 100).toStringAsFixed(0)}%'
                                        : '${(item.progress * 100).toStringAsFixed(0)}%  •  ${item.speed != null && item.speed!.isNotEmpty ? '${item.speed}  •  ' : ''}${item.size}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.metadata.copyWith(
                                  fontSize: 10,
                                  color: isPaused
                                      ? AppColors.onSurfaceVariant
                                      : AppColors.primaryLight,
                                ),
                              ),
                            ] else if (isComplete) ...[
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      item.badge,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.badge.copyWith(
                                        fontSize: 10,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.size,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.metadata.copyWith(
                                        fontSize: 11,
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (watchProgress != null &&
                                  watchProgress! > 0.01) ...[
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: watchProgress,
                                    minHeight: 3,
                                    backgroundColor:
                                        AppColors.surfaceContainerHighest,
                                    valueColor: const AlwaysStoppedAnimation(
                                        AppColors.secondary),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${(watchProgress! * 100).round()}% watched  •  Resumes here',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.metadata.copyWith(
                                    fontSize: 10,
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                            ] else if (isFailed) ...[
                              Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      size: 13, color: AppColors.error),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Failed — tap to retry',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.metadata.copyWith(
                                        fontSize: 10,
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Actions cleanly contained inside the card
              if (isComplete) ...[
                _action(
                  icon: const Icon(Icons.play_circle_fill_rounded,
                      color: AppColors.secondary, size: 32),
                  onPressed: onPlay,
                  tooltip: watchProgress != null && watchProgress! > 0.01
                      ? 'Resume'
                      : 'Play offline',
                ),
                _action(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.onSurfaceVariant, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Delete download',
                ),
              ] else if (isPaused || isFailed) ...[
                _action(
                  icon: const Icon(Icons.play_arrow_rounded,
                      color: AppColors.primaryLight, size: 26),
                  onPressed: onResume,
                  tooltip: 'Resume',
                ),
                _action(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.onSurfaceVariant, size: 20),
                  onPressed: onCancel,
                  tooltip: 'Remove',
                ),
              ] else ...[
                _action(
                  icon: const Icon(Icons.pause_rounded,
                      color: AppColors.onSurfaceVariant, size: 22),
                  onPressed: onPause,
                  tooltip: 'Pause',
                ),
                _action(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.onSurfaceVariant, size: 20),
                  onPressed: onCancel,
                  tooltip: 'Cancel download',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// An action button wearing the card focus ring.
  Widget _action({
    required Icon icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) =>
      TvButton(
        onSelect: onPressed,
        semanticLabel: tooltip,
        borderRadius: 10,
        child: SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: icon,
            onPressed: onPressed,
            tooltip: tooltip,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Private sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderIconBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onTap,
      semanticLabel: tooltip,
      scale: 1.08,
      borderRadius: 18,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.onSurfaceVariant, size: 20),
          ),
        ),
      ),
    );
  }
}

class _SequentialQueueNotice extends StatelessWidget {
  const _SequentialQueueNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            const Icon(Icons.view_stream_rounded,
                color: AppColors.onSurfaceVariant, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sequential mode on — downloads queue one at a time',
                style: AppTheme.metadata
                    .copyWith(fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _StatPill(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: AppTheme.metadata.copyWith(fontSize: 10, color: color)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.download_for_offline_outlined,
            size: 72,
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.25)),
        const SizedBox(height: 16),
        Text('No downloads yet',
            style: AppTheme.sectionTitle
                .copyWith(fontSize: 18, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Text(
          'Movies and episodes downloaded from the detail page\nwill appear here for offline viewing.',
          textAlign: TextAlign.center,
          style: AppTheme.metadata.copyWith(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
              height: 1.6),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}
