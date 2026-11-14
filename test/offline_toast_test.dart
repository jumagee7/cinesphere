import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cinesphere/core/providers/movie_provider.dart';
import 'package:cinesphere/core/services/media_delivery_service.dart';
import 'package:cinesphere/core/services/media_orchestrator_service.dart';
import 'package:cinesphere/core/services/settings_service.dart';
import 'package:cinesphere/shared/widgets/offline_toast.dart';

/// A provider whose offline flag a test can flip without making the network
/// calls that would normally set it.
class _FakeFeed extends MovieProvider {
  _FakeFeed(super.orchestrator);

  void goOffline() {
    isOffline = true;
    notifyListeners();
  }

  void goOnline() {
    isOffline = false;
    notifyListeners();
  }
}

void main() {
  late _FakeFeed feed;

  setUp(() {
    final settings = SettingsService();
    feed = _FakeFeed(
        MediaOrchestratorService(settings, MediaDeliveryService(settings)));
  });

  /// Pumps to a known-still baseline: online, and nothing announced.
  ///
  /// The provider probes the connectivity channel on construction; a widget
  /// test has no host, so that probe answers "no connection" and would be the
  /// very first stall the toast sees. The channel is stubbed to Wi-Fi.
  Future<void> pumpOnline(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? const ['wifi'] : null,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<MovieProvider>.value(
        value: feed,
        child: const MaterialApp(home: Scaffold(body: Stack(children: [
          SizedBox.expand(),
          OfflineToast(),
        ]))),
      ),
    );
    await tester.pump();
  }

  testWidgets('nothing is announced while the feed is live',
      (WidgetTester tester) async {
    await pumpOnline(tester);
    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('the notice appears when the feed stalls',
      (WidgetTester tester) async {
    await pumpOnline(tester);
    feed.goOffline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('the notice pops back away on its own',
      (WidgetTester tester) async {
    await pumpOnline(tester);
    feed.goOffline();
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('staying offline does not make it shout again',
      (WidgetTester tester) async {
    await pumpOnline(tester);
    feed.goOffline();
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);

    // Another repaint for the same stall must not re-show it.
    feed.goOffline();
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('reconnecting hides it before its time is up',
      (WidgetTester tester) async {
    await pumpOnline(tester);
    feed.goOffline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No internet connection'), findsOneWidget);

    feed.goOnline();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
  });
}
