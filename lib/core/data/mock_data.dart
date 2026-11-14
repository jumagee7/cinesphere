import '../models/movie.dart';

class MockData {
  static const List<Movie> featuredMovies = [
    Movie(
      id: 'chrono_mirage',
      tmdbId: 12345,
      title: 'Chrono Mirage',
      description:
          "When humanity's final observatory detects reverse chronological echoes, a rogue physicist races to decode the signal before civilization unravels.",
      imageUrl:
          'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=800&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=1200&q=80',
      rating: 8.9,
      duration: '2h 24m',
      genres: ['Sci-Fi', 'Thriller'],
      badges: ['4K HDR', 'IMAX'],
      year: 2025,
      ageRating: 'PG-13',
      isTrending: true,
    ),
    Movie(
      id: 'obsidian_mirror',
      tmdbId: 12346,
      title: 'Obsidian Mirror',
      description:
          'A detective discovers that the ancient mirror in an abandoned estate reflects events yet to come, spiraling into a dark mystery that challenges reality.',
      imageUrl:
          'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=800&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=1200&q=80',
      rating: 9.4,
      duration: '2h 05m',
      genres: ['Mystery', 'Thriller'],
      badges: ['4K UHD'],
      year: 2025,
      ageRating: 'R',
    ),
    Movie(
      id: 'solaris_awakening',
      tmdbId: 12347,
      title: 'Solaris Awakening',
      description:
          'In the endless dark, the light will find you. A crew of deep-space explorers encounters a sentient star that reshapes memory itself.',
      imageUrl:
          'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=800&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=1200&q=80',
      rating: 9.2,
      duration: '2h 40m',
      genres: ['Sci-Fi', 'Drama'],
      badges: ['IMAX'],
      year: 2025,
      ageRating: 'PG-13',
    ),
    Movie(
      id: 'velvet_midnight',
      tmdbId: 12348,
      title: 'Velvet Midnight',
      description:
          'A jazz pianist stumbles upon a secret society in 1940s New Orleans where the music is the key to unlocking forbidden doors.',
      imageUrl:
          'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=1200&q=80',
      rating: 8.7,
      duration: '1h 58m',
      genres: ['Noir', 'Mystery'],
      badges: ['HDR10'],
      year: 2024,
      ageRating: 'R',
    ),
  ];

  static const List<TVShow> continueWatching = [
    TVShow(
      id: 'cyberpunk_2099',
      tmdbId: 12350,
      title: 'Cyberpunk 2099',
      description: 'The city never sleeps, and neither do its secrets.',
      imageUrl:
          'https://images.unsplash.com/photo-1563089145-599997674d42?w=800&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1563089145-599997674d42?w=1200&q=80',
      rating: 9.1,
      duration: '42m left',
      genres: ['Sci-Fi', 'Action'],
      badges: ['4K'],
      year: 2025,
      ageRating: 'TV-MA',
      watchProgress: 0.38,
      season: 2,
      episode: 6,
      episodeTitle: 'Glitch in the Veil',
    ),
    TVShow(
      id: 'interstellar_echoes',
      tmdbId: 12351,
      title: 'Interstellar Echoes',
      description: 'A journey across the cosmos reveals an ancient truth.',
      imageUrl:
          'https://images.unsplash.com/photo-1502134249126-9f3755a50d78?w=800&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1502134249126-9f3755a50d78?w=1200&q=80',
      rating: 8.8,
      duration: '1h 15m',
      genres: ['Sci-Fi', 'Drama'],
      badges: ['IMAX'],
      year: 2025,
      ageRating: 'TV-14',
      watchProgress: 0.65,
      season: 1,
      episode: 4,
      episodeTitle: 'Extended',
    ),
    TVShow(
      id: 'void_protocol',
      tmdbId: 12352,
      title: 'Void Protocol',
      description: 'When the network goes dark, who controls the truth?',
      imageUrl:
          'https://images.unsplash.com/photo-1518770660439-4636190af475?w=800&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1518770660439-4636190af475?w=1200&q=80',
      rating: 8.3,
      duration: '55m left',
      genres: ['Thriller', 'Tech'],
      badges: ['HDR'],
      year: 2024,
      ageRating: 'TV-MA',
      watchProgress: 0.22,
      season: 1,
      episode: 8,
      episodeTitle: 'Dark Protocol',
    ),
  ];

  static const List<Movie> topRated = [
    Movie(
      id: 'obsidian_mirror',
      tmdbId: 12346,
      title: 'Obsidian Mirror',
      description: 'A detective discovers a mirror that reflects the future.',
      imageUrl:
          'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=1200&q=80',
      rating: 9.4,
      duration: '2h 05m',
      genres: ['Mystery', 'Thriller'],
      badges: ['4K UHD'],
      year: 2025,
      ageRating: 'R',
    ),
    Movie(
      id: 'solaris_awakening_top',
      tmdbId: 12347,
      title: 'Solaris Awakening',
      description: 'In the endless dark, the light will find you.',
      imageUrl:
          'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=1200&q=80',
      rating: 9.2,
      duration: '2h 40m',
      genres: ['Sci-Fi', 'Drama'],
      badges: ['IMAX'],
      year: 2025,
      ageRating: 'PG-13',
    ),
    Movie(
      id: 'velvet_midnight_top',
      tmdbId: 12348,
      title: 'Velvet Midnight',
      description: 'Jazz, secrets, and forbidden doors in 1940s New Orleans.',
      imageUrl:
          'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=1200&q=80',
      rating: 8.9,
      duration: '1h 58m',
      genres: ['Noir', 'Mystery'],
      badges: ['HDR10'],
      year: 2024,
      ageRating: 'R',
    ),
    Movie(
      id: 'neon_dynasty',
      tmdbId: 12349,
      title: 'Neon Dynasty',
      description: 'An empire built on light, crumbling in the dark.',
      imageUrl:
          'https://images.unsplash.com/photo-1444703686981-a3abbc4d4fe3?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1444703686981-a3abbc4d4fe3?w=1200&q=80',
      rating: 8.7,
      duration: '2h 12m',
      genres: ['Action', 'Drama'],
      badges: ['4K', 'Dolby'],
      year: 2025,
      ageRating: 'R',
    ),
  ];

  static const List<Movie> trending = [
    Movie(
      id: 'quantum_drift',
      tmdbId: 12353,
      title: 'Quantum Drift',
      description: 'Five strangers wake up in a world slightly out of phase.',
      imageUrl:
          'https://images.unsplash.com/photo-1446776709462-d6b525c57bd3?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1446776709462-d6b525c57bd3?w=1200&q=80',
      rating: 8.5,
      duration: '1h 52m',
      genres: ['Sci-Fi', 'Thriller'],
      badges: ['4K'],
      year: 2025,
      ageRating: 'PG-13',
      isTrending: true,
    ),
    Movie(
      id: 'crimson_aurora',
      tmdbId: 12354,
      title: 'Crimson Aurora',
      description:
          'When the sky turns red, the world must answer for its sins.',
      imageUrl:
          'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?w=1200&q=80',
      rating: 8.4,
      duration: '2h 18m',
      genres: ['Fantasy', 'Action'],
      badges: ['HDR', 'IMAX'],
      year: 2025,
      ageRating: 'PG-13',
      isTrending: true,
    ),
    Movie(
      id: 'iron_meridian',
      tmdbId: 12355,
      title: 'Iron Meridian',
      description: 'Steel meets soul in the ultimate battle for the city.',
      imageUrl:
          'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=1200&q=80',
      rating: 8.6,
      duration: '2h 08m',
      genres: ['Action', 'Sci-Fi'],
      badges: ['4K', 'HDR'],
      year: 2025,
      ageRating: 'PG-13',
      isTrending: true,
    ),
  ];

  static const List<Movie> newReleases = [
    Movie(
      id: 'echo_chamber',
      tmdbId: 12356,
      title: 'Echo Chamber',
      description: 'In a world where sound can kill, silence is survival.',
      imageUrl:
          'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=1200&q=80',
      rating: 8.1,
      duration: '1h 45m',
      genres: ['Horror', 'Thriller'],
      badges: ['Dolby Atmos'],
      year: 2025,
      ageRating: 'R',
    ),
    Movie(
      id: 'the_architect',
      tmdbId: 12357,
      title: 'The Architect',
      description:
          'A visionary designer uncovers a conspiracy hidden inside a masterpiece.',
      imageUrl:
          'https://images.unsplash.com/photo-1486325212027-8081e485255e?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1486325212027-8081e485255e?w=1200&q=80',
      rating: 7.9,
      duration: '2h 02m',
      genres: ['Drama', 'Mystery'],
      badges: ['4K'],
      year: 2025,
      ageRating: 'PG-13',
    ),
    Movie(
      id: 'primal_surge',
      tmdbId: 12358,
      title: 'Primal Surge',
      description:
          "Nature's fury unleashed as ancient creatures return to reclaim the earth.",
      imageUrl:
          'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=500&q=80',
      backdropUrl:
          'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=1200&q=80',
      rating: 7.7,
      duration: '1h 58m',
      genres: ['Action', 'Adventure'],
      badges: ['4K', 'HDR'],
      year: 2025,
      ageRating: 'PG-13',
    ),
  ];

  static const List<Movie> allMovies = [
    ...featuredMovies,
    ...topRated,
    ...trending,
    ...newReleases,
  ];
}
