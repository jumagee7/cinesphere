import 'movie.dart';

enum AppNotificationType {
  newMovie,
  newEpisode,
  premiere,
  download,
  watchlist,
  continueWatching,
}

/// A single entry in the in-app notification center.
///
/// [id] is stable (type + entity) so re-generating feeds never duplicates an
/// entry; [movieJson] carries just enough data to deep-link to the detail
/// screen without another network round-trip.
class AppNotification {
  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final String imageUrl;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? movieJson;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.imageUrl = '',
    this.isRead = false,
    this.movieJson,
  });

  Movie? get movie => movieJson == null ? null : Movie.fromJson(movieJson!);

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        imageUrl: imageUrl,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        movieJson: movieJson,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'imageUrl': imageUrl,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
        if (movieJson != null) 'movie': movieJson,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    AppNotificationType type;
    try {
      type = AppNotificationType.values.byName(json['type'] as String);
    } catch (_) {
      type = AppNotificationType.newMovie;
    }
    return AppNotification(
      id: json['id'] as String? ?? '',
      type: type,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
      movieJson: json['movie'] as Map<String, dynamic>?,
    );
  }
}
