import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/device_form.dart';
import '../services/settings_service.dart';

/// The layout numbers the browsing screens share, sized for the window the app
/// actually draws into.
///
/// Full-bleed surfaces (grids, hero) already grow with width, which is what
/// made a landscape tablet read like a 10-foot UI: a two-column search grid put
/// 620px of poster on screen. So proportional grids gain columns to keep a tile
/// near its phone size, while fixed poster rows grow moderately with width.
///
/// 360x800 is the design baseline and reproduces the original phone numbers
/// exactly. The TV layout's hand-tuned 10-foot metrics win whatever the size —
/// that mode is a choice the user made, not a size we inferred — and so does
/// the phone choice, which holds the art at phone size even on a wide canvas.
class ScreenMetrics {
  const ScreenMetrics({
    required this.width,
    required this.height,
    required this.couch,
    this.mobile = false,
  });

  factory ScreenMetrics.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ScreenMetrics(
      width: size.width,
      height: size.height,
      couch: context.select((SettingsService s) => s.useTvLayout),
      mobile: context
          .select((SettingsService s) => s.forcedLayout == DeviceForm.phone),
    );
  }

  final double width;
  final double height;

  /// True for the TV layout: side rail, big art, D-pad focus.
  final bool couch;

  /// True when the user pinned the mobile layout on a screen bigger than a
  /// phone, so art stays phone-sized instead of stretching.
  final bool mobile;

  /// The width the art is sized from: the real canvas, capped at the phone
  /// baseline when the mobile layout was chosen on purpose.
  double get _artWidth => mobile ? width.clamp(0.0, 420.0) : width;

  /// Poster art in a horizontal row. 360 / 2.6 ≈ the 138px phone baseline.
  double get posterWidth => couch ? 178 : (_artWidth / 2.6).clamp(132.0, 185.0);

  /// Continue-watching cards: 16:9 art plus two text lines.
  double get landscapeWidth =>
      couch ? 272 : (_artWidth / 1.8).clamp(196.0, 268.0);

  double get rowGap => couch ? 16 : 12;

  /// ~60% of the viewport height — the 480px banner on a phone — clamped so it
  /// stays a banner rather than becoming a wall.
  double get heroHeight => (height * 0.6).clamp(420.0, 560.0);

  /// Search / browse posters, ~150px per tile.
  int get posterColumns => couch ? 3 : _columns(150, 2, 8);

  /// The tighter library grid, ~110px per tile.
  int get tileColumns => couch ? 4 : _columns(110, 3, 7);

  /// Wide genre tiles, ~150px per tile.
  int get genreColumns => couch ? 3 : _columns(150, 2, 5);

  int _columns(double target, int min, int max) =>
      (_artWidth / target).floor().clamp(min, max);

  /// Directional focus can only reach children that are already built, so the
  /// TV layout keeps many more of them alive.
  double get scrollCacheExtent => couch ? 900 : 250;
}
