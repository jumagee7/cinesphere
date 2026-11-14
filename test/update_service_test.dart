import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinesphere/core/services/update_service.dart';
import 'package:cinesphere/shared/widgets/update_dialog.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('compares version parts numerically', () {
      expect(UpdateService.isNewer('1.2.0', '1.1.9'), isTrue);
      expect(UpdateService.isNewer('2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewer('1.0.10', '1.0.9'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('ignores the leading v and build suffix', () {
      expect(UpdateService.isNewer('v1.1.0', '1.0.0+3'), isTrue);
      expect(UpdateService.isNewer('1.0.0+7', '1.0.0'), isFalse);
    });
  });

  testWidgets('update dialog names both versions and can be dismissed',
      (tester) async {
    const update = AppUpdate(
      version: '1.2.0',
      currentVersion: '1.0.0',
      notes: 'Playlist fixes',
      url: 'https://github.com/jumagee7/cinesphere/releases',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppUpdateDialog(update: update)),
    ));

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('1.2.0'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsOneWidget);
    expect(find.text('Playlist fixes'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsNothing);
  });
}
