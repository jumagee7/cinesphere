import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/movie.dart';
import 'stream_loading_screen.dart';

/// Single entry point for "play this title" across all screens.
///
/// Immediately pushes [StreamLoadingScreen] which:
///   1. Shows a full-screen loading UI with the movie poster while
///      [StreamResolverService] intercepts the real stream URL from VidSrc.
///   2. Replaces itself with [VideoPlayerScreen] on success.
///   3. Shows a retry/back error state if resolution fails.
///
/// Every card, button, and row that starts playback should call this.
Future<void> launchPlayer(
  BuildContext context,
  Movie movie, {
  int? season,
  int? episode,
  bool isTrailer = false,
}) async {
  // For a TVShow the season/episode can live on the model itself.
  final s = season ?? (movie is TVShow ? movie.season : null);
  final e = episode ?? (movie is TVShow ? movie.episode : null);

  HapticFeedback.lightImpact();

  await Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => StreamLoadingScreen(
        movie: movie,
        season: s,
        episode: e,
        isTrailer: isTrailer,
      ),
      transitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}
