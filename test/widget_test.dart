import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cinesphere/app.dart';
import 'package:cinesphere/core/services/auth_service.dart';
import 'package:cinesphere/core/services/media_delivery_service.dart';
import 'package:cinesphere/core/services/library_service.dart';
import 'package:cinesphere/core/services/media_orchestrator_service.dart';
import 'package:cinesphere/core/services/settings_service.dart';
import 'package:cinesphere/core/providers/movie_provider.dart';
import 'package:cinesphere/features/splash/splash_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final settingsService = SettingsService();
    final deliveryService = MediaDeliveryService(settingsService);
    final orchestrator =
        MediaOrchestratorService(settingsService, deliveryService);
    final authService = AuthService();
    final libraryService = LibraryService();
    final movieProvider = MovieProvider(orchestrator);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settingsService),
          Provider<MediaOrchestratorService>.value(value: orchestrator),
          ChangeNotifierProvider.value(value: authService),
          ChangeNotifierProvider.value(value: libraryService),
          ChangeNotifierProvider.value(value: deliveryService),
          ChangeNotifierProvider.value(value: movieProvider),
        ],
        child: const VyroApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('splash lockup fits a short viewport', (WidgetTester tester) async {
    // The browser window that surfaced the overflow: 504x213 logical px.
    tester.view.physicalSize = const Size(504, 213);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: SettingsService()),
          // Splash only reads auth once its nav timer fires (2.7s); the first
          // frames are pure layout.
          ChangeNotifierProvider.value(value: AuthService()),
        ],
        child: const VyroApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
