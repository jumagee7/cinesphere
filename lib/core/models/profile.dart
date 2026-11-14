import 'dart:math';

import 'movie.dart';

/// Local app profile. Trakt itself doesn't support sub-profiles, so these
/// live in the app and share whatever Trakt account is connected.
class Profile {
  final String id;
  final String name;
  final int colorSeed;
  final String emoji;
  final bool isKids;
  final DateTime createdAt;

  /// Genres this profile explicitly likes. Empty = no explicit preference
  /// (fall back to organic top-genre detection from watch history).
  final List<String> preferredGenres;

  /// Genres this profile never wants to see. Applied as a hard filter on
  /// every catalog row before personalization.
  final List<String> blockedGenres;

  /// Maximum maturity rating this profile can see. Values mirror the MPAA
  /// style ladder used across the catalog: G, PG, PG-13, R, NC-17.
  /// `null` means "no restriction".
  final String? maxMaturity;

  const Profile({
    required this.id,
    required this.name,
    required this.colorSeed,
    required this.emoji,
    this.isKids = false,
    required this.createdAt,
    this.preferredGenres = const [],
    this.blockedGenres = const [],
    this.maxMaturity,
  });

  static const List<String> defaultEmojis = [
    '🎬',
    '🍿',
    '🎥',
    '🌟',
    '🚀',
    '🎭',
    '🎨',
    '🎧',
    '🦊',
    '🐼',
  ];

  /// Canonical genre list used by the picker UI.
  static const List<String> allGenres = [
    'Action',
    'Adventure',
    'Animation',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'History',
    'Horror',
    'Music',
    'Mystery',
    'Romance',
    'Science Fiction',
    'Thriller',
    'TV Movie',
    'War',
    'Western',
  ];

  /// Maturity ladder from most permissive to most restrictive.
  static const List<String> maturityLadder = [
    'G',
    'PG',
    'PG-13',
    'R',
    'NC-17',
  ];

  static String randomEmoji(Random rng) =>
      defaultEmojis[rng.nextInt(defaultEmojis.length)];

  Profile copyWith({
    String? name,
    int? colorSeed,
    String? emoji,
    bool? isKids,
    List<String>? preferredGenres,
    List<String>? blockedGenres,
    String? maxMaturity,
    bool clearMaturity = false,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        colorSeed: colorSeed ?? this.colorSeed,
        emoji: emoji ?? this.emoji,
        isKids: isKids ?? this.isKids,
        createdAt: createdAt,
        preferredGenres: preferredGenres ?? this.preferredGenres,
        blockedGenres: blockedGenres ?? this.blockedGenres,
        maxMaturity: clearMaturity ? null : (maxMaturity ?? this.maxMaturity),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorSeed': colorSeed,
        'emoji': emoji,
        'isKids': isKids,
        'createdAt': createdAt.toIso8601String(),
        'preferredGenres': preferredGenres,
        'blockedGenres': blockedGenres,
        'maxMaturity': maxMaturity,
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Profile',
        colorSeed: (j['colorSeed'] as num?)?.toInt() ?? 0,
        emoji: j['emoji'] as String? ?? '🎬',
        isKids: j['isKids'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        preferredGenres: ((j['preferredGenres'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        blockedGenres: ((j['blockedGenres'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        maxMaturity: j['maxMaturity'] as String?,
      );

  // ─── Filtering ──────────────────────────────────────────────────────────

  /// Whether [movie] is allowed for this profile. Applies blocked genres,
  /// maturity cap, and the kids flag (which is shorthand for maxMaturity=PG).
  bool allows(Movie movie) {
    final blockedLower = blockedGenres.map((g) => g.toLowerCase()).toSet();
    for (final g in movie.genres) {
      if (blockedLower.contains(g.toLowerCase())) return false;
    }

    final cap = isKids ? 'PG' : maxMaturity;
    if (cap != null && cap.isNotEmpty) {
      final capIdx = maturityLadder.indexOf(cap);
      final movieIdx = maturityLadder.indexOf(movie.ageRating);
      // Unknown ratings pass through — better to show than to hide everything.
      if (capIdx >= 0 && movieIdx > capIdx) return false;
    }
    return true;
  }

  /// Filter a catalog list down to what this profile is allowed to see.
  List<Movie> filter(List<Movie> movies) =>
      movies.where(allows).toList(growable: false);
}
