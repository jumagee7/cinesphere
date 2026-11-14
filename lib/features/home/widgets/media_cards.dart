import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/movie.dart';
import '../../../core/services/settings_service.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/cine_artwork.dart';
import '../../../shared/widgets/tv_focus.dart';
import '../../detail/movie_detail_screen.dart';
import '../../player/play_launcher.dart';

/// Space a caption gets under its thumbnail. The focus ring stops at the
/// thumbnail's edge, so the caption has to be exactly this tall for that to
/// line up — the home rows budget the same numbers in their heights.
const double _posterCaption = 48;
const double _landscapeCaption = 64;

// Vertical poster card (2:3 ratio)
class PosterCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;
  final double width;

  const PosterCard({
    super.key,
    required this.movie,
    this.onTap,
    this.width = 140,
  });

  @override
  Widget build(BuildContext context) {
    final radius = context.select((SettingsService s) => s.posterRadius);
    final showBadges = context.select((SettingsService s) => s.showBadges);
    final showRatings = context.select((SettingsService s) => s.showRatings);
    final showRuntime = context.select((SettingsService s) => s.showRuntime);

    final height = width * 1.5;
    void open() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
      );
    }

    final select = onTap ?? open;
    return TvFocusable(
      onSelect: select,
      semanticLabel: movie.title,
      borderRadius: radius,
      ringBottomInset: _posterCaption,
      child: GestureDetector(
        onTap: select,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  children: [
                    CineArtwork(
                      imageUrl: movie.imageUrl,
                      fallbackUrl: movie.backdropUrl,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                      title: movie.title,
                    ),
                    // Gradient overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: height * 0.4,
                        decoration: const BoxDecoration(
                          gradient: AppColors.posterGradient,
                        ),
                      ),
                    ),
                    // Bookmark icon
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh
                              .withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bookmark_border_rounded,
                          color: AppColors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    // Rating badge at bottom left
                    if (showRatings)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: StarRating(rating: movie.rating),
                      ),
                    // Badges at top left
                    if (showBadges && movie.badges.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: TechBadge(label: movie.badges.first),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: _posterCaption - 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      movie.title,
                      style: AppTheme.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showRuntime
                          ? '${movie.genreString} • ${movie.duration}'
                          : movie.genreString,
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
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.05, end: 0);
  }
}

// Landscape card (16:9) for Continue Watching
class LandscapeCard extends StatelessWidget {
  final TVShow show;
  final VoidCallback? onTap;
  final double width;

  const LandscapeCard({
    super.key,
    required this.show,
    this.onTap,
    this.width = 220,
  });

  @override
  Widget build(BuildContext context) {
    final height = width * 9 / 16;
    final radius = context.select((SettingsService s) => s.posterRadius);
    final showRuntime = context.select((SettingsService s) => s.showRuntime);

    final select = onTap ??
        () => launchPlayer(
              context,
              show,
              season: show.season,
              episode: show.episode,
            );
    return TvFocusable(
      onSelect: select,
      semanticLabel: show.title,
      borderRadius: radius,
      ringBottomInset: _landscapeCaption,
      child: GestureDetector(
        onTap: select,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  children: [
                    CineArtwork(
                      imageUrl: show.backdropUrl.isNotEmpty
                          ? show.backdropUrl
                          : show.imageUrl,
                      fallbackUrl: show.imageUrl,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                      title: show.title,
                    ),
                    // Dark overlay
                    Container(
                      width: width,
                      height: height,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x99000000)],
                        ),
                      ),
                    ),
                    // Play button
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: AppColors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Time remaining
                    if (showRuntime)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Text(
                          show.duration,
                          style: AppTheme.badge.copyWith(
                            fontSize: 11,
                            color: AppColors.white,
                            shadows: [
                              const Shadow(blurRadius: 4, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                    // More options
                    Positioned(
                      bottom: 4,
                      right: -4,
                      child: IconButton(
                        icon: const Icon(Icons.more_vert,
                            color: AppColors.white, size: 16),
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              ),
              // Progress bar
              SizedBox(
                height: _landscapeCaption,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (show.hasProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: LinearPercentIndicator(
                          padding: EdgeInsets.zero,
                          lineHeight: 3,
                          percent: show.watchProgress!,
                          backgroundColor: AppColors.surfaceContainerHighest,
                          progressColor: AppColors.secondary,
                          barRadius: const Radius.circular(2),
                        ),
                      )
                    else
                      const SizedBox(height: 6),
                    Text(
                      show.title,
                      style: AppTheme.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      show.episodeLabel,
                      style: AppTheme.metadata.copyWith(fontSize: 11),
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
    );
  }
}

/// Landscape card backed by a [Movie] (from [LibraryService.continueWatching]).
/// Unlike [LandscapeCard] which takes a [TVShow], this variant works directly
/// with the Movie model and real persisted watch-progress values.
class LandscapeCardFromMovie extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;
  final double width;

  const LandscapeCardFromMovie({
    super.key,
    required this.movie,
    this.onTap,
    this.width = 220,
  });

  @override
  Widget build(BuildContext context) {
    final height = width * 9 / 16;
    final radius = context.select((SettingsService s) => s.posterRadius);
    final showRuntime = context.select((SettingsService s) => s.showRuntime);

    final select = onTap ??
        () {
          final m = movie;
          if (m is TVShow) {
            launchPlayer(
              context,
              m,
              season: m.season,
              episode: m.episode,
            );
          } else {
            launchPlayer(context, m);
          }
        };
    return TvFocusable(
      onSelect: select,
      semanticLabel: movie.title,
      borderRadius: radius,
      ringBottomInset: _landscapeCaption,
      child: GestureDetector(
        onTap: select,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  children: [
                    CineArtwork(
                      imageUrl: movie.backdropUrl.isNotEmpty
                          ? movie.backdropUrl
                          : movie.imageUrl,
                      fallbackUrl: movie.imageUrl,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                      title: movie.title,
                    ),
                    // Dark gradient overlay
                    Container(
                      width: width,
                      height: height,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x99000000)],
                        ),
                      ),
                    ),
                    // Play button
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: AppColors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Duration badge
                    if (showRuntime && movie.duration.isNotEmpty)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Text(
                          movie.duration,
                          style: AppTheme.badge.copyWith(
                            fontSize: 11,
                            color: AppColors.white,
                            shadows: [
                              const Shadow(blurRadius: 4, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Real watch progress bar
              SizedBox(
                height: _landscapeCaption,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (movie.hasProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: LinearPercentIndicator(
                          padding: EdgeInsets.zero,
                          lineHeight: 3,
                          percent: movie.watchProgress!.clamp(0.0, 1.0),
                          backgroundColor: AppColors.surfaceContainerHighest,
                          progressColor: AppColors.secondary,
                          barRadius: const Radius.circular(2),
                        ),
                      )
                    else
                      const SizedBox(height: 6),
                    Text(
                      movie.title,
                      style: AppTheme.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      movie.genreString,
                      style: AppTheme.metadata.copyWith(fontSize: 11),
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
    );
  }
}
