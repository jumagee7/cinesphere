import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cinesphere/core/services/device_form.dart';
import 'package:cinesphere/core/services/settings_service.dart';
import 'package:cinesphere/core/theme/screen_metrics.dart';

void main() {
  group('detectDeviceForm', () {
    test('a phone is a phone', () {
      expect(detectDeviceForm(const Size(360, 800), 3), DeviceForm.phone);
    });

    test('a 1080p TV stick is a TV', () {
      expect(detectDeviceForm(const Size(1920, 1080), 1), DeviceForm.tv);
    });

    test('a 4K TV drawing at density 2 is a TV', () {
      expect(detectDeviceForm(const Size(1920, 1080), 2), DeviceForm.tv);
    });

    test('a low-density tablet is not a TV', () {
      expect(detectDeviceForm(const Size(1280, 800), 1), DeviceForm.tablet);
    });

    test('a high-density tablet is not a TV', () {
      expect(detectDeviceForm(const Size(1280, 800), 2), DeviceForm.tablet);
    });

    test('an iPad in portrait is a tablet', () {
      expect(detectDeviceForm(const Size(810, 1080), 2), DeviceForm.tablet);
    });

    test('an Android TV canvas at tvdpi is a TV, not a tablet', () {
      // 1920x1080 physical at density 1.75 — the case that mislabelled real
      // TV boxes as tablets.
      expect(detectDeviceForm(const Size(1097, 617), 1.75), DeviceForm.tv);
    });

    test('the platform saying "TV" beats the geometry', () {
      expect(
          detectDeviceForm(const Size(960, 540), 2.0, nativeTv: true),
          DeviceForm.tv);
    });
  });

  group('chosen layout', () {
    tearDown(() => forceDeviceForm(null));

    test('a pinned form beats both the platform answer and the canvas', () {
      forceDeviceForm(DeviceForm.phone);
      // The 800x600 test window is a tablet by geometry; the choice wins.
      expect(deviceFormOfRootView(), DeviceForm.phone);
    });

    test('clearing the choice hands the decision back to geometry', () {
      forceDeviceForm(DeviceForm.tv);
      expect(deviceFormOfRootView(), DeviceForm.tv);
      forceDeviceForm(null);
      expect(deviceFormOfRootView(), isNot(DeviceForm.tv));
    });

    test('the settings store keeps one choice, not a switch', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.initialize();

      expect(settings.hasChosenLayout, isFalse);
      expect(settings.useTvLayout, isFalse);

      settings.chooseLayout(DeviceForm.tv);
      expect(settings.useTvLayout, isTrue);
      expect(settings.hasChosenLayout, isTrue);
      expect(deviceFormOfRootView(), DeviceForm.tv);

      settings.chooseLayout(DeviceForm.phone);
      expect(settings.useTvLayout, isFalse);
      expect(settings.forcedLayout, DeviceForm.phone);
    });

    test('an install that had the couch switch keeps the TV layout', () async {
      SharedPreferences.setMockInitialValues({'useTvLayout': true});
      final settings = SettingsService();
      await settings.initialize();

      expect(settings.layoutChoice, 'tv');
      expect(settings.useTvLayout, isTrue);
    });
  });

  group('ScreenMetrics', () {
    ScreenMetrics measure(Size logical,
            {bool couch = false, bool mobile = false}) =>
        ScreenMetrics(
            width: logical.width,
            height: logical.height,
            couch: couch,
            mobile: mobile);

    test('phone reproduces the design baseline', () {
      final m = measure(const Size(360, 800));
      expect(m.posterWidth, 150);
      expect(m.landscapeWidth, 220);
      expect(m.heroHeight, 480);
      expect(m.posterColumns, 2);
      expect(m.tileColumns, 3);
      expect(m.genreColumns, 2);
      expect(m.scrollCacheExtent, 250);
    });

    test('a landscape tablet grows cards but adds grid columns too', () {
      final m = measure(const Size(1280, 800));
      expect(m.posterWidth, greaterThan(150));
      expect(m.posterWidth, lessThanOrEqualTo(200));
      // Two columns of 620px of art is the "TV UI on a tablet" bug this stops.
      expect(m.posterColumns, 6);
      expect(m.tileColumns, 6);
      expect(m.genreColumns, 4);
      expect(m.heroHeight, lessThanOrEqualTo(560));
    });

    test('the TV layout keeps its own numbers whatever the size', () {
      final tv = measure(const Size(1920, 1080), couch: true);
      expect(tv.posterWidth, 210);
      expect(tv.landscapeWidth, 320);
      expect(tv.rowGap, 18);
      expect(tv.posterColumns, 2);
      expect(tv.tileColumns, 3);
      expect(tv.genreColumns, 2);
      expect(tv.scrollCacheExtent, 900);
    });

    test('a pinned mobile layout keeps phone art on a wide canvas', () {
      final m = measure(const Size(1280, 800), mobile: true);
      expect(m.posterWidth, 175);
      expect(m.posterColumns, 2);
      expect(m.tileColumns, 3);
      expect(m.genreColumns, 2);
    });
  });

  group('native TV signal', () {
    const channel = MethodChannel('cinesphere/device');
    late TestWidgetsFlutterBinding binding;

    setUp(() => binding = TestWidgetsFlutterBinding.ensureInitialized());
    tearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('leanback overrides a phone-sized canvas', () async {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isTelevision');
        return true;
      });

      await probeNativeTv();

      expect(nativeTvDetected, isTrue);
      // The 800x600 test window is a tablet by geometry: only the platform
      // answer can call this a TV.
      expect(deviceFormOfRootView(), DeviceForm.tv);
    });

    test('a missing channel falls back to geometry instead of throwing',
        () async {
      await probeNativeTv();

      expect(nativeTvDetected, isFalse);
      // Without the platform answer the 800x600 test window is judged on
      // canvas alone — so whatever it lands on, it is not a TV.
      expect(deviceFormOfRootView(), isNot(DeviceForm.tv));
    });

    test('the Dart channel matches what MainActivity answers', () {
      // A name mismatch between the two sides fails silently: `probeNativeTv`
      // catches MissingPluginException and falls back to geometry, which is
      // exactly the bug that called every Android TV a tablet.
      final source = File(
              'android/app/src/main/kotlin/com/majumaink/cinesphere/MainActivity.kt')
          .readAsStringSync();

      expect(source, contains('cinesphere/device'));
      expect(source, contains('isTelevision'));
      expect(source, contains('FEATURE_LEANBACK'));
    });
  });

  testWidgets('form and metrics read the live view', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DeviceForm? form;
    ScreenMetrics? metrics;

    await tester.pumpWidget(ChangeNotifierProvider<SettingsService>(
      create: (_) => SettingsService(),
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            form = deviceFormOf(context);
            metrics = ScreenMetrics.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ));

    expect(metrics!.width, 1280);
    expect(form, DeviceForm.tablet);
    expect(metrics!.posterColumns, 6);
  });
}
