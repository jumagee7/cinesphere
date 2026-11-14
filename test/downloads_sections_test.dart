import 'dart:convert';

import 'package:cinesphere/core/models/movie.dart';
import 'package:cinesphere/core/services/library_service.dart';
import 'package:cinesphere/core/services/media_delivery_service.dart';
import 'package:cinesphere/core/services/settings_service.dart';
import 'package:cinesphere/features/downloads/downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _item({
  required String id,
  required String movieId,
  required String title,
  DownloadStatus status = DownloadStatus.completed,
  int? season,
  int? episode,
  String? seriesName,
  String? episodeTitle,
}) =>
    DownloadItem(
      id: id,
      movieId: movieId,
      title: title,
      imageUrl: '',
      genre: 'Drama',
      duration: '45m',
      badge: season == null ? 'HD' : 'S$season:E$episode',
      status: status,
      progress: status == DownloadStatus.completed ? 1.0 : 0.3,
      size: '1 GB',
      sizeMb: 1024,
      season: season,
      episode: episode,
      seriesName: seriesName,
      episodeTitle: episodeTitle,
    ).toJson();

void main() {
  testWidgets('downloads browse as Movies / Series folders', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'media_delivery_queue_v1': jsonEncode([
        _item(id: '100', movieId: '100', title: 'Sicario'),
        _item(id: '101', movieId: '101', title: 'Heat'),
        _item(
          id: '200_s1_e2',
          movieId: '200',
          title: 'Carrie • S1 E2: The Rage',
          season: 1,
          episode: 2,
          seriesName: 'Carrie',
          episodeTitle: 'The Rage',
        ),
        _item(
          id: '200_s1_e1',
          movieId: '200',
          title: 'Carrie • S1 E1: Pilot',
          season: 1,
          episode: 1,
          seriesName: 'Carrie',
          episodeTitle: 'Pilot',
        ),
        _item(
          id: '200_s2_e1',
          movieId: '200',
          title: 'Carrie • S2 E1: Return',
          season: 2,
          episode: 1,
          seriesName: 'Carrie',
          episodeTitle: 'Return',
        ),
        _item(
          id: '200_s1_e3',
          movieId: '200',
          title: 'Carrie • S1 E3: Down',
          status: DownloadStatus.downloading,
          season: 1,
          episode: 3,
          seriesName: 'Carrie',
          episodeTitle: 'Down',
        ),
      ]),
    });

    final settings = SettingsService();
    final delivery = MediaDeliveryService(settings);
    final library = LibraryService();
    await delivery.initialize();
    await library.initialize();
    await library.updateWatchProgress(
      const TVShow(
        id: '200',
        tmdbId: 200,
        title: 'Carrie',
        description: '',
        imageUrl: '',
        backdropUrl: '',
        rating: 0,
        duration: '',
        genres: [],
        badges: [],
        year: 0,
        ageRating: '',
        season: 1,
        episode: 1,
        episodeTitle: 'Pilot',
      ),
      0.5,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: delivery),
          ChangeNotifierProvider.value(value: library),
        ],
        child: const MaterialApp(home: DownloadsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Root: active downloads plus the two library folders, no bare items.
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Heat'), findsNothing);
    expect(find.text('Carrie • S1 E1: Pilot'), findsNothing);

    // Series → show folders.
    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('Carrie'), findsOneWidget);
    expect(find.text('Season 1'), findsNothing);

    // Show → season folders.
    await tester.tap(find.text('Carrie'));
    await tester.pumpAndSettle();
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.text('2 seasons  •  3 episodes'), findsOneWidget);

    // Season → episodes sorted by number; only completed ones.
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();
    expect(find.text('Carrie • S1 E1: Pilot'), findsOneWidget);
    expect(find.text('Carrie • S1 E2: The Rage'), findsOneWidget);
    expect(find.text('Carrie • S1 E3: Down'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Carrie • S1 E1: Pilot')).dy,
      lessThan(tester.getTopLeft(find.text('Carrie • S1 E2: The Rage')).dy),
    );
    expect(find.textContaining('50% watched'), findsOneWidget);

    // System back walks up a folder instead of leaving the app.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Carrie'), findsOneWidget);

    // Back walks up one folder at a time.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Carrie'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Downloads'), findsOneWidget);

    // Movies folder lists every movie, alphabetically.
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('Sicario'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Heat')).dy,
      lessThan(tester.getTopLeft(find.text('Sicario')).dy),
    );
  });
}
