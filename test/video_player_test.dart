import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:cinesphere/core/models/movie.dart';
import 'package:cinesphere/core/services/auth_service.dart';
import 'package:cinesphere/core/services/library_service.dart';
import 'package:cinesphere/core/services/media_delivery_service.dart';
import 'package:cinesphere/core/services/settings_service.dart';
import 'package:cinesphere/features/player/video_player_screen.dart';

/// Minimal video platform: creation completes instantly with a 1920x1080,
/// 42-minute asset, and buffering events can be pushed from the test.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextId = 1;

  /// Delay before the fake reports a ready stream, so the loading state can be
  /// observed on the first frames.
  Duration initDelay = Duration.zero;

  StreamController<VideoEvent> controllerFor(int playerId) =>
      _events[playerId]!;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    Timer(initDelay, () {
      events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 42),
        size: const Size(1920, 1080),
      ));
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.black);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      buildView(options.playerId);
}

const _episode = TVShow(
  id: 'carrie',
  tmdbId: 1,
  title: 'Carrie',
  description: '',
  imageUrl: '',
  backdropUrl: '',
  rating: 7.0,
  duration: '42m',
  genres: ['Drama'],
  badges: [],
  year: 2024,
  ageRating: 'TV-MA',
  season: 1,
  episode: 2,
  episodeTitle: 'The One With the Blackout',
);

Widget _playerApp(Movie movie) {
  final settings = SettingsService();
  final delivery = MediaDeliveryService(settings);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: delivery),
      ChangeNotifierProvider.value(value: LibraryService()),
      ChangeNotifierProvider.value(value: AuthService()),
    ],
    child: MaterialApp(
      home: VideoPlayerScreen(
        movie: movie,
        assetPath: 'assets/videos/demo.mp4',
        theme: const CinePlayerTheme(autoPlay: true),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeVideoPlayerPlatform platform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('github.com/aaassseee/screen_brightness'),
      (call) async => 0.5,
    );
  });

  /// Initialization resolves across several microtasks/frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The player's Android-only PiP path has no test host.
  Future<void> asIOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('initial load spins over the artwork instead of a grey wash',
      (tester) async {
    await asIOS(() async {
      platform.initDelay = const Duration(milliseconds: 400);
      await tester.pumpWidget(_playerApp(_episode));
      await tester.pump();

      expect(find.text('Loading video…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await settle(tester);
      expect(find.text('Loading video…'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('series player shows the episode name under the show title',
      (tester) async {
    await asIOS(() async {
      await tester.pumpWidget(_playerApp(_episode));
      await settle(tester);

      expect(find.text('Carrie'), findsOneWidget);
      expect(find.text('The One With the Blackout'), findsOneWidget);
      expect(find.textContaining('S1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('placeholder episode labels are not repeated in the header',
      (tester) async {
    const placeholder = TVShow(
      id: 'carrie',
      tmdbId: 1,
      title: 'Carrie',
      description: '',
      imageUrl: '',
      backdropUrl: '',
      rating: 7.0,
      duration: '42m',
      genres: ['Drama'],
      badges: [],
      year: 2024,
      ageRating: 'TV-MA',
      season: 1,
      episode: 2,
      episodeTitle: 'S1 E2',
    );
    await asIOS(() async {
      await tester.pumpWidget(_playerApp(placeholder));
      await settle(tester);

      expect(find.text('S1 E2'), findsNothing);
      expect(find.textContaining('S1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });

  testWidgets('buffering spins over the last frame instead of blanking it',
      (tester) async {
    await asIOS(() async {
      await tester.pumpWidget(_playerApp(_episode));
      await settle(tester);

      // Initialized: no loading placeholder left behind.
      expect(find.text('Loading video…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      platform.controllerFor(1).add(VideoEvent(
            eventType: VideoEventType.bufferingStart,
            duration: const Duration(minutes: 42),
            size: const Size(1920, 1080),
          ));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Carrie'), findsOneWidget);

      platform.controllerFor(1).add(VideoEvent(
            eventType: VideoEventType.bufferingEnd,
            duration: const Duration(minutes: 42),
            size: const Size(1920, 1080),
          ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
