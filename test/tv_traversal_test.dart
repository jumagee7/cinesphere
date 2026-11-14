import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinesphere/shared/widgets/tv_focus.dart';

/// A miniature of the home page's TV sliver stack, at the geometry the couch
/// layout actually asks for on a small canvas: poster cards 210 wide (so a 363
/// tall row), a 420 tall hero and a 212 tall premiere banner. Every one of
/// those is taller than the 315 logical pixels a 510x473 @1.5 browser pane
/// hands Flutter, which is the condition the D-pad has to survive.
///
/// [_MiniHomeState.showRow] flips the poster row in and out, which is how a
/// test reproduces a feed arriving while the ring is parked further down the
/// page.
void main() {
  final homeKey = GlobalKey<_MiniHomeState>();
  final nodes = <String, FocusNode>{};

  Future<void> pumpHome(WidgetTester tester, {bool withRowAbove = true}) async {
    tester.view.physicalSize = const Size(510, 473);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    nodes.clear();
    await tester.pumpWidget(MaterialApp(
      shortcuts: tvShortcuts,
      builder: (context, child) => TvFocusLadder(child: child!),
      home: _MiniHome(key: homeKey, nodes: nodes, showRow: withRowAbove),
    ));
    await tester.pumpAndSettle();
  }

  /// The detail page at the same small-canvas geometry: a 300 tall hero, the
  /// action buttons, a short season-chip row, full-width 94 tall episode rows
  /// and a 260 tall related-poster row below them.
  Future<void> pumpDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(510, 473);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    nodes.clear();
    await tester.pumpWidget(MaterialApp(
      shortcuts: tvShortcuts,
      builder: (context, child) => TvFocusLadder(child: child!),
      home: _MiniDetail(nodes: nodes),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('up from the premiere banner climbs to the poster row',
      (tester) async {
    await pumpHome(tester);

    nodes['banner']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(nodes['poster0']!.hasFocus || nodes['poster1']!.hasFocus, isTrue,
        reason: 'up from the banner must land on the row above it');
  });

  testWidgets('down from the hero drops to the poster row', (tester) async {
    await pumpHome(tester);

    nodes['watchNow']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(
        nodes.values
            .any((n) => n.hasFocus && n.debugLabel!.startsWith('poster')),
        isTrue,
        reason:
            'down from the hero must land on the first row, not the banner');
  });

  testWidgets('up from the banner with no row above it', (tester) async {
    await pumpHome(tester, withRowAbove: false);

    nodes['banner']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(nodes['watchNow']!.hasFocus, isTrue,
        reason: 'the nearest content above must win, not the app bar');
  });

  testWidgets(
      'a row that loads after the ring moved past it is still climbable',
      (tester) async {
    await pumpHome(tester, withRowAbove: false);

    // Walk down from the hero to the banner while the TV feed is still empty,
    // so the framework records hero -> banner as the last hop.
    nodes['watchNow']!.requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(nodes['banner']!.hasFocus, isTrue,
        reason: 'the banner is the next stop while the row is missing');

    // The feed arrives: a poster row now sits between the hero and the banner.
    homeKey.currentState!.setShowRow(true);
    await tester.pumpAndSettle();
    expect(nodes['banner']!.hasFocus, isTrue, reason: 'the ring stays put');

    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(nodes['poster0']!.hasFocus, isTrue,
        reason: 'up must climb to the row the user can now see, not replay the '
            'hop made before it existed');
  });

  testWidgets('down from an episode row advances to the next row',
      (tester) async {
    await pumpDetail(tester);

    nodes['ep0']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(nodes['ep1']!.hasFocus, isTrue,
        reason:
            'the rows walk one at a time; the download icon beside each row '
            'is a sibling stop, not one the vertical ladder has to cross');
  });

  testWidgets('right from an episode row steps to its download icon',
      (tester) async {
    await pumpDetail(tester);

    nodes['ep2']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(nodes['ep2-dl']!.hasFocus, isTrue,
        reason: 'the icon stays reachable — a remote still has to be able to '
            'start a download, it just is not in the way of Down');
  });

  testWidgets('down from a season chip lands on the episode list',
      (tester) async {
    await pumpDetail(tester);

    nodes['season1']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(nodes['ep0']!.hasFocus, isTrue,
        reason: 'the episodes listed under the chips are the next stop down, '
            'even though a taller poster row also overlaps the chip column');
  });

  testWidgets('up from a related poster lands on the episode list',
      (tester) async {
    await pumpDetail(tester);

    nodes['ep2']!.requestFocus();
    await tester.pumpAndSettle();
    nodes['poster0']!.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(
        nodes.values.any((n) => n.hasFocus && n.debugLabel!.startsWith('ep')),
        isTrue,
        reason: 'climbing out of the related row has to pass through the '
            'episodes above it, not jump over them to the season chips');
  });
}

class _MiniDetail extends StatefulWidget {
  const _MiniDetail({required this.nodes});

  final Map<String, FocusNode> nodes;

  @override
  State<_MiniDetail> createState() => _MiniDetailState();
}

class _MiniDetailState extends State<_MiniDetail> {
  late final FocusScopeNode scope = FocusScopeNode(
    debugLabel: 'detail',
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );

  @override
  void dispose() {
    scope.dispose();
    super.dispose();
  }

  FocusNode n(String key) =>
      widget.nodes.putIfAbsent(key, () => FocusNode(debugLabel: key));

  Widget card(String key, {double height = 100, double width = 100}) =>
      SizedBox(
        width: width,
        height: height,
        child: TvFocusable(
          focusNode: n(key),
          semanticLabel: key,
          child: const ColoredBox(color: Colors.grey),
        ),
      );

  /// An episode row and its download icon. The icon is a *sibling* of the row:
  /// nested inside it, the icon's centre falls in the row's own band, so it
  /// wins every Down press and the walk never leaves the first row.
  Widget epCard(String key) => Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 94,
              child: TvFocusable(
                focusNode: n(key),
                semanticLabel: key,
                child: const ColoredBox(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TvFocusable(
            focusNode: n('$key-dl'),
            semanticLabel: '$key-dl',
            child: const SizedBox(
              height: 48,
              width: 48,
              child: Icon(Icons.download),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: scope,
      child: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
        slivers: [
          // Poster hero of the detail page.
          SliverToBoxAdapter(
              child: SizedBox(height: 300, child: card('hero', width: 340))),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  card('watch', width: 308, height: 38),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: card('trailer', height: 38)),
                      const SizedBox(width: 12),
                      Expanded(child: card('download', height: 38)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Seasons & Episodes'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          // Season chips: a short horizontal row.
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => card('season$i', width: 80, height: 40),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          // Episodes: full width, ~94 tall each, in a plain Column — a nested
          // scrollable here would group them out of every directional hop.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    epCard('ep$i'),
                    if (i != 5) const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          // Related posters: much taller than the episode rows.
          SliverToBoxAdapter(
            child: SizedBox(
              height: 260,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) =>
                    card('poster$i', width: 140, height: 260),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _MiniHome extends StatefulWidget {
  const _MiniHome({
    super.key,
    required this.nodes,
    required this.showRow,
  });

  final Map<String, FocusNode> nodes;
  final bool showRow;

  @override
  State<_MiniHome> createState() => _MiniHomeState();
}

class _MiniHomeState extends State<_MiniHome> {
  late bool _showRow = widget.showRow;

  // Owned by the state: rebuilding the page must not hand FocusScope a new
  // node, or the scope loses the focused child the test is tracking.
  late final FocusScopeNode scope = FocusScopeNode(
    debugLabel: 'Tab 0',
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );

  @override
  void dispose() {
    scope.dispose();
    super.dispose();
  }

  void setShowRow(bool value) => setState(() => _showRow = value);

  FocusNode n(String key) =>
      widget.nodes.putIfAbsent(key, () => FocusNode(debugLabel: key));

  Widget card(String key, {double height = 100, double width = 100}) =>
      SizedBox(
        width: width,
        height: height,
        child: TvFocusable(
          focusNode: n(key),
          semanticLabel: key,
          child: const ColoredBox(color: Colors.grey),
        ),
      );

  Widget row(String prefix, int count) => SliverToBoxAdapter(
        child: SizedBox(
          height: 363,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => card('$prefix$i', width: 210, height: 363),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: scope,
      child: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 60,
              child: Row(children: [card('profile', width: 36, height: 36)]),
            ),
          ),
          // Hero: buttons live at the bottom of a 420 tall card.
          SliverToBoxAdapter(
            child: SizedBox(
              height: 420,
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [card('watchNow', width: 140, height: 44)],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          if (_showRow) ...[
            const SliverToBoxAdapter(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Popular TV Series'),
            )),
            row('poster', 6),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: card('banner', width: double.infinity, height: 212),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          row('forYou', 6),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
