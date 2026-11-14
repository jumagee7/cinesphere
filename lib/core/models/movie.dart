import '../services/tmdb_service.dart';

// ─── Genre id → display name ──────────────────────────────────────────────────
const Map<int, String> _tmdbGenreNames = {
  28: 'Action',
  12: 'Adventure',
  16: 'Animation',
  35: 'Comedy',
  80: 'Crime',
  99: 'Documentary',
  18: 'Drama',
  10751: 'Family',
  14: 'Fantasy',
  36: 'History',
  27: 'Horror',
  10402: 'Music',
  9648: 'Mystery',
  10749: 'Romance',
  878: 'Sci-Fi',
  53: 'Thriller',
  10752: 'War',
  37: 'Western',
};

class Movie {
  final String id; // TMDB numeric id as String
  final int tmdbId; // raw TMDB int id
  final String? imdbId; // e.g. "tt1234567"
  final String title;
  final String description;
  final String imageUrl; // poster
  final String backdropUrl;
  final double rating;
  final String duration; // e.g. "2h 14m"
  final List<String> genres;
  final List<String> badges; // 4K, HDR, IMAX …
  final int year;
  final DateTime? releaseDate;
  final String ageRating;
  final bool isExclusive;
  final bool isTrending;
  final double? watchProgress; // 0.0–1.0
  final bool isTV;

  const Movie({
    required this.id,
    required this.tmdbId,
    this.imdbId,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.backdropUrl,
    required this.rating,
    required this.duration,
    required this.genres,
    required this.badges,
    required this.year,
    this.releaseDate,
    required this.ageRating,
    this.isExclusive = false,
    this.isTrending = false,
    this.watchProgress,
    this.isTV = false,
  });

  // ─── Convenience getters ────────────────────────────────────────────────────
  String get genreString => genres.take(2).join(' • ');
  bool get hasProgress => watchProgress != null && watchProgress! > 0;

  // ─── Factory: build from TMDB movie result/detail JSON ─────────────────────
  factory Movie.fromTmdb(Map<String, dynamic> json, {bool trending = false}) {
    final id = json['id'] as int? ?? 0;

    // Title – movies use 'title', TV uses 'name'
    final title = (json['title'] ?? json['name'] ?? 'Unknown') as String;

    // Overview
    final overview = (json['overview'] ?? '') as String;

    // Poster & backdrop with mutual fallback
    final posterPath = json['poster_path'] as String?;
    final backdropPath = json['backdrop_path'] as String?;
    final effectivePoster = (posterPath != null && posterPath.isNotEmpty)
        ? posterPath
        : backdropPath;
    final effectiveBackdrop = (backdropPath != null && backdropPath.isNotEmpty)
        ? backdropPath
        : posterPath;
    final imageUrl = TmdbService.poster(effectivePoster, size: 'w500');
    final backdropUrl = TmdbService.backdrop(effectiveBackdrop, size: 'w780');

    // Rating
    final rating = ((json['vote_average'] ?? 0.0) as num).toDouble();

    // Runtime – detail responses have 'runtime' (int minutes)
    final runtimeMin = json['runtime'] as int?;
    final duration = runtimeMin != null && runtimeMin > 0
        ? _formatRuntime(runtimeMin)
        : (json['episode_run_time'] is List &&
                (json['episode_run_time'] as List).isNotEmpty
            ? _formatRuntime((json['episode_run_time'] as List).first as int)
            : '');

    // Genres
    final List<String> genres;
    if (json['genres'] is List) {
      // detailed response has [{id, name}]
      genres = (json['genres'] as List)
          .map((g) => g['name'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (json['genre_ids'] is List) {
      // list responses have [28, 12, ...]
      genres = (json['genre_ids'] as List)
          .map((gid) => _tmdbGenreNames[gid as int] ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      genres = [];
    }

    // Year
    final dateStr =
        (json['release_date'] ?? json['first_air_date'] ?? '') as String;
    final releaseDate = _parseDate(dateStr);
    final year =
        releaseDate?.year ??
            (dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) ?? 0 : 0);

    // Age rating (certification) – only in detailed responses
    String ageRating = '';
    final releaseDates = json['release_dates']?['results'] as List?;
    if (releaseDates != null) {
      final us = releaseDates.firstWhere(
        (r) => r['iso_3166_1'] == 'US',
        orElse: () => null,
      );
      if (us != null) {
        final releases = us['release_dates'] as List?;
        final cert = releases
            ?.map((r) => r['certification'] as String? ?? '')
            .firstWhere((c) => c.isNotEmpty, orElse: () => '');
        ageRating = cert ?? '';
      }
    }
    if (ageRating.isEmpty) ageRating = 'PG-13';

    // IMDB id (from external_ids sub-response)
    final imdbId = json['imdb_id'] as String? ??
        json['external_ids']?['imdb_id'] as String?;

    // Badges – derive from vote_count and popularity
    final List<String> badges = [];
    final popularity = (json['popularity'] as num? ?? 0).toDouble();
    if (popularity > 200) badges.add('4K');
    if (popularity > 100) badges.add('HDR');

    final isTV = json['media_type'] == 'tv' ||
        json['name'] != null && json['title'] == null;

    return Movie(
      id: '$id',
      tmdbId: id,
      imdbId: imdbId,
      title: title,
      description: overview,
      imageUrl: imageUrl,
      backdropUrl: backdropUrl,
      rating: rating,
      duration: duration,
      genres: genres,
      badges: badges,
      year: year,
      releaseDate: releaseDate,
      ageRating: ageRating,
      isTrending: trending,
      isTV: isTV,
    );
  }

  // ─── Factory: build from Trakt extended=full movie/show JSON ──────────────
  // Trakt public feeds (trending/popular/recommended) embed images + full
  // metadata, so rows can render without any TMDB call.
  factory Movie.fromTrakt(Map<String, dynamic> json,
      {bool isTv = false, bool trending = false}) {
    final ids = (json['ids'] as Map<String, dynamic>?) ?? {};
    final tmdbId = (ids['tmdb'] as num?)?.toInt() ?? 0;
    final traktId = (ids['trakt'] as num?)?.toInt() ?? 0;
    final imdbId = ids['imdb'] as String?;

    final images = (json['images'] as Map<String, dynamic>?) ?? {};
    String resolveImage(String key) {
      final list = images[key] as List?;
      if (list == null || list.isEmpty) return '';
      final path = list.first as String;
      if (path.isEmpty) return '';
      return path.startsWith('http') ? path : 'https://$path';
    }

    final poster = resolveImage('poster').isNotEmpty
        ? resolveImage('poster')
        : resolveImage('thumb');
    final backdrop = resolveImage('fanart').isNotEmpty
        ? resolveImage('fanart')
        : resolveImage('banner');

    final overview = (json['overview'] ?? '') as String;
    final title = (json['title'] ?? 'Unknown') as String;

    final runtimeMin = (json['runtime'] as num?)?.toInt() ?? 0;

    return Movie(
      id: tmdbId > 0 ? '$tmdbId' : 'trakt-$traktId',
      tmdbId: tmdbId,
      imdbId: imdbId,
      title: title,
      description:
          overview.isNotEmpty ? overview : (json['tagline'] as String? ?? ''),
      imageUrl: poster.isNotEmpty ? poster : backdrop,
      backdropUrl: backdrop.isNotEmpty ? backdrop : poster,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      duration: runtimeMin > 0 ? _formatRuntime(runtimeMin) : '',
      genres: ((json['genres'] as List?) ?? [])
          .map((g) => _traktGenreName('$g'))
          .where((s) => s.isNotEmpty)
          .toList(),
      badges: const [],
      year: (json['year'] as num?)?.toInt() ?? 0,
      releaseDate: _parseDate((json['released'] as String?) ?? ''),
      ageRating: (json['age_rating'] as String?) ?? '',
      isTrending: trending,
      isTV: isTv,
    );
  }

  /// Returns a copy with [imdbId] filled in (used after a separate external_ids call).
  Movie withImdbId(String id) => Movie(
        id: this.id,
        tmdbId: tmdbId,
        imdbId: id,
        title: title,
        description: description,
        imageUrl: imageUrl,
        backdropUrl: backdropUrl,
        rating: rating,
        duration: duration,
        genres: genres,
        badges: badges,
        year: year,
        releaseDate: releaseDate,
        ageRating: ageRating,
        isExclusive: isExclusive,
        isTrending: isTrending,
        watchProgress: watchProgress,
        isTV: isTV,
      );

  /// Returns a copy with artwork URLs replaced. Used to re-point Trakt-CDN
  /// images (media.trakt.tv, no CORS headers → unusable on web) at the
  /// CORS-friendly TMDB CDN.
  Movie withArtwork({required String imageUrl, required String backdropUrl}) =>
      Movie(
        id: id,
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        description: description,
        imageUrl: imageUrl,
        backdropUrl: backdropUrl,
        rating: rating,
        duration: duration,
        genres: genres,
        badges: badges,
        year: year,
        releaseDate: releaseDate,
        ageRating: ageRating,
        isExclusive: isExclusive,
        isTrending: isTrending,
        watchProgress: watchProgress,
        isTV: isTV,
      );

  /// Returns a copy with [watchProgress] set.
  Movie withProgress(double progress) => Movie(
        id: id,
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        description: description,
        imageUrl: imageUrl,
        backdropUrl: backdropUrl,
        rating: rating,
        duration: duration,
        genres: genres,
        badges: badges,
        year: year,
        releaseDate: releaseDate,
        ageRating: ageRating,
        isExclusive: isExclusive,
        isTrending: isTrending,
        watchProgress: progress,
        isTV: isTV,
      );

  // ─── Serialization for persistence ─────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'tmdbId': tmdbId,
        'imdbId': imdbId,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'backdropUrl': backdropUrl,
        'rating': rating,
        'duration': duration,
        'genres': genres,
        'badges': badges,
        'year': year,
        'releaseDate': releaseDate?.toIso8601String(),
        'ageRating': ageRating,
        'isExclusive': isExclusive,
        'isTrending': isTrending,
        'watchProgress': watchProgress,
        'isTV': isTV,
        'season': this is TVShow ? (this as TVShow).season : null,
        'episode': this is TVShow ? (this as TVShow).episode : null,
        'episodeTitle': this is TVShow ? (this as TVShow).episodeTitle : null,
      };

  factory Movie.fromJson(Map<String, dynamic> json) {
    final isTv = json['isTV'] as bool? ?? false;
    final season = json['season'] as int?;
    final episode = json['episode'] as int?;
    if (isTv && season != null && episode != null) {
      return TVShow(
        id: json['id'] as String,
        tmdbId: json['tmdbId'] as int,
        imdbId: json['imdbId'] as String?,
        title: json['title'] as String,
        description: json['description'] as String,
        imageUrl: json['imageUrl'] as String,
        backdropUrl: json['backdropUrl'] as String,
        rating: (json['rating'] as num).toDouble(),
        duration: json['duration'] as String,
        genres: (json['genres'] as List).map((e) => e as String).toList(),
        badges: (json['badges'] as List).map((e) => e as String).toList(),
        year: json['year'] as int,
        releaseDate: _parseDate(json['releaseDate'] as String? ?? ''),
        ageRating: json['ageRating'] as String,
        isExclusive: json['isExclusive'] as bool? ?? false,
        isTrending: json['isTrending'] as bool? ?? false,
        watchProgress: (json['watchProgress'] as num?)?.toDouble(),
        season: season,
        episode: episode,
        episodeTitle: json['episodeTitle'] as String? ?? '',
      );
    }
    return Movie(
      id: json['id'] as String,
      tmdbId: json['tmdbId'] as int,
      imdbId: json['imdbId'] as String?,
      title: json['title'] as String,
      description: json['description'] as String,
      imageUrl: json['imageUrl'] as String,
      backdropUrl: json['backdropUrl'] as String,
      rating: (json['rating'] as num).toDouble(),
      duration: json['duration'] as String,
      genres: (json['genres'] as List).map((e) => e as String).toList(),
      badges: (json['badges'] as List).map((e) => e as String).toList(),
      year: json['year'] as int,
      releaseDate: _parseDate(json['releaseDate'] as String? ?? ''),
      ageRating: json['ageRating'] as String,
      isExclusive: json['isExclusive'] as bool? ?? false,
      isTrending: json['isTrending'] as bool? ?? false,
      watchProgress: (json['watchProgress'] as num?)?.toDouble(),
      isTV: isTv,
    );
  }
}

// ─── TVShow extends Movie ─────────────────────────────────────────────────────
class TVShow extends Movie {
  final int season;
  final int episode;
  final String episodeTitle;

  const TVShow({
    required super.id,
    required super.tmdbId,
    super.imdbId,
    required super.title,
    required super.description,
    required super.imageUrl,
    required super.backdropUrl,
    required super.rating,
    required super.duration,
    required super.genres,
    required super.badges,
    required super.year,
    super.releaseDate,
    required super.ageRating,
    super.isExclusive,
    super.isTrending,
    super.watchProgress,
    required this.season,
    required this.episode,
    required this.episodeTitle,
  }) : super(isTV: true);

  @override
  TVShow withProgress(double progress) => TVShow(
        id: id,
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        description: description,
        imageUrl: imageUrl,
        backdropUrl: backdropUrl,
        rating: rating,
        duration: duration,
        genres: genres,
        badges: badges,
        year: year,
        releaseDate: releaseDate,
        ageRating: ageRating,
        isExclusive: isExclusive,
        isTrending: isTrending,
        watchProgress: progress,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
      );

  String get episodeLabel => 'S$season • E$episode: $episodeTitle';

  factory TVShow.fromTmdb(Map<String, dynamic> json,
      {int season = 1, int episode = 1, String episodeTitle = ''}) {
    final base = Movie.fromTmdb(json);
    return TVShow(
      id: base.id,
      tmdbId: base.tmdbId,
      imdbId: base.imdbId,
      title: base.title,
      description: base.description,
      imageUrl: base.imageUrl,
      backdropUrl: base.backdropUrl,
      rating: base.rating,
      duration: base.duration,
      genres: base.genres,
      badges: base.badges,
      year: base.year,
      releaseDate: base.releaseDate,
      ageRating: base.ageRating,
      isExclusive: base.isExclusive,
      isTrending: base.isTrending,
      watchProgress: base.watchProgress,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
    );
  }
}

// ─── TV Season & Episode models ──────────────────────────────────────────────
class EpisodeItem {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String overview;
  final String stillUrl;
  final String duration;
  final double rating;
  final String airDate;

  const EpisodeItem({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    required this.stillUrl,
    required this.duration,
    required this.rating,
    required this.airDate,
  });

  factory EpisodeItem.fromTmdb(Map<String, dynamic> json) {
    final epNum = json['episode_number'] as int? ?? 1;
    final seasonNum = json['season_number'] as int? ?? 1;
    final stillPath = json['still_path'] as String?;
    final runtimeMin = json['runtime'] as int?;
    final voteAvg = ((json['vote_average'] ?? 0.0) as num).toDouble();
    return EpisodeItem(
      id: json['id'] as int? ?? 0,
      episodeNumber: epNum,
      seasonNumber: seasonNum,
      name: json['name'] as String? ?? 'Episode $epNum',
      overview: json['overview'] as String? ?? '',
      stillUrl: TmdbService.backdrop(stillPath, size: 'w780'),
      duration: runtimeMin != null && runtimeMin > 0
          ? _formatRuntime(runtimeMin)
          : '45m',
      rating: voteAvg,
      airDate: json['air_date'] as String? ?? '',
    );
  }
}

class SeasonItem {
  final int id;
  final int seasonNumber;
  final String name;
  final String overview;
  final String posterUrl;
  final int episodeCount;
  final List<EpisodeItem> episodes;

  const SeasonItem({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    required this.posterUrl,
    required this.episodeCount,
    this.episodes = const [],
  });

  SeasonItem copyWith({
    int? id,
    int? seasonNumber,
    String? name,
    String? overview,
    String? posterUrl,
    int? episodeCount,
    List<EpisodeItem>? episodes,
  }) {
    return SeasonItem(
      id: id ?? this.id,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      name: name ?? this.name,
      overview: overview ?? this.overview,
      posterUrl: posterUrl ?? this.posterUrl,
      episodeCount: episodeCount ?? this.episodeCount,
      episodes: episodes ?? this.episodes,
    );
  }

  factory SeasonItem.fromTmdb(Map<String, dynamic> json) {
    final seasonNum = json['season_number'] as int? ?? 1;
    final posterPath = json['poster_path'] as String?;
    return SeasonItem(
      id: json['id'] as int? ?? 0,
      seasonNumber: seasonNum,
      name: json['name'] as String? ?? 'Season $seasonNum',
      overview: json['overview'] as String? ?? '',
      posterUrl: TmdbService.poster(posterPath, size: 'w500'),
      episodeCount: json['episode_count'] as int? ?? 0,
      episodes: const [],
    );
  }
}

// ─── Cast member ─────────────────────────────────────────────────────────────
class CastMember {
  final String name;
  final String character;
  final String profileUrl;

  const CastMember({
    required this.name,
    required this.character,
    required this.profileUrl,
  });

  factory CastMember.fromTmdb(Map<String, dynamic> json) {
    return CastMember(
      name: json['name'] as String? ?? '',
      character: json['character'] as String? ?? '',
      profileUrl: TmdbService.profile(json['profile_path'] as String?),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
String _formatRuntime(int minutes) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// TMDB and Trakt dates are day-precision ('YYYY-MM-DD'), while persisted
/// values carry a time suffix. Anything shorter or unparseable is no date.
DateTime? _parseDate(String raw) {
  final date = raw.contains('T') ? raw.substring(0, 10) : raw;
  final parts = date.split('-');
  if (parts.length < 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// Trakt genre slugs → app display names (kept consistent with TMDB names
/// so Explore/Home genre filters match: 'science-fiction' → 'Sci-Fi').
String _traktGenreName(String slug) {
  const overrides = {
    'science-fiction': 'Sci-Fi',
    'tv-movie': 'TV Movie',
    'action-adventure': 'Action',
    'film-noir': 'Film Noir',
    'war-politics': 'War',
  };
  if (overrides.containsKey(slug)) return overrides[slug]!;
  return slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
