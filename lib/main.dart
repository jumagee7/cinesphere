import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/services/device_form.dart';
import 'core/services/settings_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/trakt_service.dart';
import 'core/services/profile_service.dart';
import 'core/services/library_service.dart';
import 'core/services/media_delivery_service.dart';
import 'core/services/media_orchestrator_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/os_notifications.dart';
import 'core/services/stream_resolver_service.dart';
import 'core/services/diagnostic_service.dart';
import 'core/providers/movie_provider.dart';

/// Root navigator key — required by [StreamResolverService] to insert
/// the hidden InAppWebView overlay without a BuildContext.
final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Initialize diagnostic telemetry hub early
  await DiagnosticService.instance.initialize();

  // Give the stream resolver access to the root overlay.
  StreamResolverService.navigatorKey = _navigatorKey;

  // Android says whether it is a TV; the answer gates the couch layout prompt
  // and D-pad shortcuts, so it has to be known before the first frame.
  await probeNativeTv();

  final settingsService = SettingsService();
  await settingsService.initialize();

  final authService = AuthService();
  await authService.initialize();

  _installCrashHandlers(settingsService);

  final profileService = ProfileService();
  await profileService.initialize();

  final libraryService = LibraryService();
  await libraryService.initialize(profileId: profileService.currentId);

  // The library stays offline-first; mirroring is a fire-and-forget side
  // effect that follows the Sync Watchlist switch.
  libraryService.onWatchlistChanged = (movie, {required added}) async {
    final token = authService.accessToken;
    if (!settingsService.syncWatchlist ||
        !authService.isLoggedIn ||
        token == null) {
      return;
    }
    final type = movie.isTV ? 'shows' : 'movies';
    if (added) {
      await TraktService.addToWatchlist(token,
          imdbId: movie.imdbId, title: movie.title, type: type);
    } else {
      await TraktService.removeFromWatchlist(token,
          imdbId: movie.imdbId, title: movie.title, type: type);
    }
  };

  // Single service responsible for BOTH streaming and downloads.
  final deliveryService = MediaDeliveryService(settingsService);
  await deliveryService.initialize();

  settingsService.addListener(deliveryService.applySettings);

  if (settingsService.traktClientId.isNotEmpty) {
    TraktService.customClientId = settingsService.traktClientId;
  }

  // Orchestrator takes both settings and delivery service.
  final orchestrator =
      MediaOrchestratorService(settingsService, deliveryService);

  // Set up the OS notification channel + runtime permission (Android only;
  // no-op on web) before the service can start raising notifications. A box
  // with an unusable notification manager still has to reach its first frame,
  // so this stays off the critical startup path.
  try {
    await OsNotifications.initialize();
  } catch (error) {
    debugPrint('[Notifications] OS channel unavailable: $error');
  }

  final notificationService = NotificationService(settingsService);
  await notificationService.initialize();
  deliveryService.addOnCompleteCallback(notificationService.onDownloadComplete);

  final movieProvider = MovieProvider(orchestrator);
  notificationService.attach(
    provider: movieProvider,
    library: libraryService,
    orchestrator: orchestrator,
  );
  movieProvider.loadHome();

  profileService.addListener(() {
    libraryService.bindToProfile(profileService.currentId);
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: profileService),
        ChangeNotifierProvider.value(value: libraryService),
        ChangeNotifierProvider.value(value: deliveryService),
        ChangeNotifierProvider.value(value: notificationService),
        Provider<MediaOrchestratorService>.value(value: orchestrator),
        ChangeNotifierProvider.value(value: movieProvider),
      ],
      child: VyroApp(navigatorKey: _navigatorKey),
    ),
  );
}

/// Crash Reporting writes uncaught errors into the Diagnostics log, which the
/// Diagnostics screen can copy out. Off means the default console handling.
void _installCrashHandlers(SettingsService settings) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (settings.crashReportingEnabled) {
      DiagnosticService.instance.error(
        'Crash',
        details.exceptionAsString(),
        details.exception,
        details.stack,
      );
    }
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (settings.crashReportingEnabled) {
      DiagnosticService.instance.error(
        'Crash',
        'Uncaught platform error',
        error,
        stack,
      );
    }
    return false;
  };
}
