import 'package:flutter_test/flutter_test.dart';

import 'package:cinesphere/core/services/trakt_service.dart';

void main() {
  group('Trakt scrobble payload', () {
    test('a movie is sent as a movie', () {
      final body = TraktService.scrobbleBody(
        title: 'Heat',
        imdbId: 'tt0113277',
        tmdbId: 949,
        progress: 40,
      );

      expect(body['movie'], {
        'title': 'Heat',
        'ids': {'imdb': 'tt0113277', 'tmdb': 949},
      });
      expect(body['show'], isNull);
      expect(body['episode'], isNull);
      expect(body['progress'], 40);
    });

    test('an episode is a show + episode, never a movie', () {
      // Sending a show as a movie leaves nothing in Trakt's playback or
      // history, so no other device could ever pull the progress.
      final body = TraktService.scrobbleBody(
        title: 'Carrie',
        tmdbId: 892,
        season: 1,
        episode: 9,
        progress: 40,
      );

      expect(body['movie'], isNull);
      expect(body['show'], {
        'title': 'Carrie',
        'ids': {'tmdb': 892},
      });
      expect(body['episode'], {'season': 1, 'number': 9});
    });

    test('blank ids are not sent', () {
      final body = TraktService.scrobbleBody(
        title: 'Unknown',
        imdbId: '',
        tmdbId: 0,
        progress: 12,
      );

      expect(body['movie'], {'title': 'Unknown', 'ids': <String, dynamic>{}});
    });
  });
}
