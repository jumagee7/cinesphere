import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinesphere/shared/widgets/tv_focus.dart';

/// The D-pad ladder inside a scrolling page.
///
/// A pinned bar sits at the top of the viewport whatever the scroll offset, so
/// once the row above a card has scrolled away the bar measures closer than that
/// row and up leaves the page. [TvChrome] keeps the bar out of traversal while
/// the page is scrolled, and [TvFocusLadder] stops the top of the page from
/// becoming a dead end.
void main() {
  testWidgets('up climbs to the row above instead of the pinned bar',
      (tester) async {
    final scroll = ScrollController();
    final spots = _Spots(rows: [
      FocusNode(debugLabel: 'first row'),
      FocusNode(debugLabel: 'second row'),
      FocusNode(debugLabel: 'third row'),
    ]);
    await tester.pumpWidget(spots.app(scroll));

    // Build the far row, then focus it: scrolling it into view leaves the row
    // above off the top of the screen, which is the position where the pinned
    // bar measured closer than the row and stole the press.
    scroll.jumpTo(500);
    await tester.pumpAndSettle();
    spots.rows.last.requestFocus();
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(4));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(spots.rows[1].hasFocus, isTrue,
        reason: 'up should climb one row, not jump out of the page');
    expect(spots.bar.hasFocus, isFalse);
    spots.dispose();
  });

  testWidgets('a stalled up comes back for the bar on the next press',
      (tester) async {
    final scroll = ScrollController();
    final spots = _Spots(rows: [FocusNode(debugLabel: 'only row')], hero: 600);
    await tester.pumpWidget(spots.app(scroll));

    // The only focusable content sits far down the page, so there is nothing
    // left to climb to while the bar is hidden.
    spots.rows.first.requestFocus();
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(4));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(scroll.position.pixels, 0,
        reason: 'a dead up should bring the page home');
    expect(spots.rows.first.hasFocus, isTrue,
        reason: 'the ring stays put while the page travels');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(spots.bar.hasFocus, isTrue,
        reason: 'from the top of the page the chrome is reachable again');
    spots.dispose();
  });
}

/// A pinned bar plus [rows] of cards on a 400 pixel pitch — artwork and its
/// heading, which is taller than the 45% of the test viewport a focused card is
/// scrolled to.
class _Spots {
  _Spots({required this.rows, this.hero = 0});

  final FocusNode bar = FocusNode(debugLabel: 'bar');
  final List<FocusNode> rows;
  final double hero;

  void dispose() {
    bar.dispose();
    for (final row in rows) {
      row.dispose();
    }
  }

  Widget app(ScrollController scroll) {
    return MaterialApp(
      shortcuts: tvShortcuts,
      home: TvFocusLadder(
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 60,
              title: TvChrome(child: _spot(bar, 800, 60)),
            ),
            if (hero > 0) SliverToBoxAdapter(child: SizedBox(height: hero)),
            for (final row in rows) ...[
              SliverToBoxAdapter(child: _spot(row, 160, 230)),
              const SliverToBoxAdapter(child: SizedBox(height: 170)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 400)),
          ],
        ),
      ),
    );
  }

  Widget _spot(FocusNode node, double width, double height) {
    return TvFocusable(
      focusNode: node,
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF445566),
      ),
    );
  }
}
