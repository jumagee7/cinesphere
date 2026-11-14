import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum DeviceForm { phone, tablet, tv }

extension DeviceFormX on DeviceForm {
  bool get isBigScreen => this != DeviceForm.phone;

  bool get isTv => this == DeviceForm.tv;

  String get label => switch (this) {
        DeviceForm.tv => 'TV',
        DeviceForm.tablet => 'Tablet',
        DeviceForm.phone => 'Mobile',
      };
}

/// The persisted name of a layout choice, or `null` for anything unrecognised —
/// which includes the `'auto'` the settings store uses for "never asked".
DeviceForm? deviceFormFromName(String name) => switch (name) {
      'phone' => DeviceForm.phone,
      'tablet' => DeviceForm.tablet,
      'tv' => DeviceForm.tv,
      _ => null,
    };

/// Android TV's own declaration of what it is, read once at startup.
///
/// Geometry alone cannot separate a TV box from a tablet: a 1080p Android TV
/// runs at tvdpi (density 1.75), so Flutter sees a 1097x617 canvas — inside the
/// same band a 10-inch tablet lands in. `PackageManager.FEATURE_LEANBACK` is the
/// one signal that is never ambiguous.
///
/// A notifier, because the answer must never sit on the critical path to the
/// first frame: an unresponsive host channel would freeze startup, and a late
/// answer still needs to reach widgets that already built.
final ValueNotifier<bool> nativeTv = ValueNotifier<bool>(false);
bool get nativeTvDetected => nativeTv.value;

/// Ask the host platform whether it declares itself a TV. Call from `main()`;
/// it is bounded, so a host that never answers cannot hold the splash screen
/// open. No-op on web, where geometry is all there is.
Future<void> probeNativeTv({
  Duration timeout = const Duration(milliseconds: 500),
}) async {
  if (kIsWeb) return;
  try {
    final answer = await const MethodChannel('cinesphere/device')
        .invokeMethod<bool>('isTelevision')
        .timeout(timeout);
    nativeTv.value = answer ?? false;
  } catch (_) {
    // MissingPluginException (iOS, desktop, tests), a timeout, or a host error
    // all mean the same thing: fall back to geometry.
    nativeTv.value = false;
  }
}

/// Classifies the window the app draws into, from the logical canvas and its
/// density — unless the platform already said "TV".
///
/// Physical resolution separates nothing (a 4K tablet and a 4K TV are the same
/// pixels), so the fallbacks work on what layout actually sees. A canvas at
/// full 1920 logical pixels is a desktop browser or a 4K stick rendering 1:1;
/// the tvdpi band (1.6-1.9) with a 16:9 canvas is the Android/Linux TV box
/// pattern — a tablet at that aspect runs 4:3 or 3:2 instead.
DeviceForm detectDeviceForm(Size logicalSize, double devicePixelRatio,
    {bool nativeTv = false}) {
  if (nativeTv || nativeTvDetected) return DeviceForm.tv;

  final shortest = logicalSize.shortestSide;
  final longest = logicalSize.longestSide;
  final aspect = shortest == 0 ? 1.0 : longest / shortest;

  if (longest >= 1600 && shortest >= 700 && devicePixelRatio <= 2.2) {
    return DeviceForm.tv;
  }
  if (aspect >= 1.7 &&
      longest >= 950 &&
      shortest >= 560 &&
      devicePixelRatio >= 1.6 &&
      devicePixelRatio <= 1.9) {
    return DeviceForm.tv;
  }
  if (shortest >= 600 || longest >= 1280) return DeviceForm.tablet;
  return DeviceForm.phone;
}

/// A layout the user picked by hand, which beats both the platform's answer and
/// the geometry. `null` means "not chosen yet": classify from the canvas.
///
/// Held here rather than read off a provider so that every consumer — including
/// the ones above `MaterialApp`, where there is no provider scope to reach —
/// sees one answer. `SettingsService` is the only writer, and it notifies its
/// listeners on every change, so anything watching settings rebuilds and re-reads.
DeviceForm? _forcedForm;

DeviceForm? get forcedDeviceForm => _forcedForm;

void forceDeviceForm(DeviceForm? form) {
  _forcedForm = form;
}

/// Live form factor of the window this context is drawing into. Read it per
/// build — on web and desktop the user can resize the view at any time.
DeviceForm deviceFormOf(BuildContext context) {
  final forced = _forcedForm;
  if (forced != null) return forced;
  final media = MediaQuery.of(context);
  return detectDeviceForm(media.size, media.devicePixelRatio);
}

/// Same classification for a context that sits *above* `MaterialApp`, where
/// there is no `MediaQuery` yet — it reads the root view directly.
DeviceForm deviceFormOfRootView() {
  final forced = _forcedForm;
  if (forced != null) return forced;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
  return detectDeviceForm(view.physicalSize / dpr, dpr);
}
