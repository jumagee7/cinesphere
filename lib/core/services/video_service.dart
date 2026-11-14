import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for handling video playback from various sources.
class VideoService {
  // ─── Bundled demo asset ────────────────────────────────────────────────────

  /// Local demo clip shipped with the app. Used as the stand-in video for
  /// every title so the player has something to play regardless of source.
  /// Sintel trailer — CC-BY 3.0 Blender Foundation (https://durian.blender.org).
  static const String localDemoAsset = 'assets/videos/demo.mp4';

  // ─── Free video sources (public domain / royalty free) ────────────────────

  /// Demo videos for testing
  static const Map<String, String> demoVideos = {
    'Big Buck Bunny':
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    'Elephant Dream':
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    'Sintel':
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    'Tears of Steel':
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
  };

  /// Archive.org public domain movies
  static const String archiveOrgBase = 'https://archive.org/embed/';

  /// YouTube trailer base URL
  static const String youtubeBase = 'https://www.youtube.com/watch?v=';

  // ─── Get video URL for a movie ─────────────────────────────────────────────

  /// Returns a demo video URL for testing
  static String getDemoVideo(String? movieTitle) {
    // Try to match by title, otherwise return default
    for (final entry in demoVideos.entries) {
      if (movieTitle != null &&
          movieTitle.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return demoVideos.values.first; // Default to Big Buck Bunny
  }

  /// Returns YouTube trailer URL (would need to fetch trailer ID from TMDB)
  static String getYouTubeTrailerUrl(String trailerId) {
    return '$youtubeBase$trailerId';
  }

  /// Returns Archive.org embed URL for public domain movies
  static String getArchiveOrgUrl(String archiveId) {
    return '$archiveOrgBase$archiveId';
  }

  // ─── External player ───────────────────────────────────────────────────────

  static const _externalPlayerChannel =
      MethodChannel('cinesphere/external_player');

  /// Open video in external player (MX Player, VLC, etc.).
  ///
  /// On Android, fires an ACTION_VIEW intent and passes [headers] as extras
  /// understood by MX Player (`headers` array) and VLC (`extra_headers` string).
  /// Falls back to plain [url_launcher] if the platform channel is unavailable
  /// or headers are empty.
  static Future<bool> openInExternalPlayer(
    String videoUrl, {
    Map<String, String>? headers,
    String? title,
  }) async {
    if (headers != null && headers.isNotEmpty) {
      try {
        final launched = await _externalPlayerChannel.invokeMethod<bool>(
          'openVideoWithHeaders',
          {
            'url': videoUrl,
            'headers': headers,
            if (title != null) 'title': title,
          },
        );
        if (launched == true) return true;
      } on PlatformException {
        // Fall through to url_launcher fallback below.
      }
    }
    // Fallback: plain url_launcher (no custom headers).
    final uri = Uri.parse(videoUrl);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Open YouTube in YouTube app or browser
  static Future<bool> openYouTube(String videoId) async {
    final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
    final uri = Uri.parse(youtubeUrl);
    return await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  // ─── Video source detection ─────────────────────────────────────────────────

  /// Detect if URL is YouTube
  static bool isYouTube(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  /// Extract YouTube video ID from URL
  static String? extractYouTubeId(String url) {
    final regex = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
    );
    final match = regex.firstMatch(url);
    return match?.group(1);
  }
}
