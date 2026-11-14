import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinesphere/shared/widgets/tv_focus.dart';

/// The white outline a focused card paints around itself.
final Finder _ring = find.byWidgetPredicate((w) {
  if (w is! DecoratedBox) return false;
  final decoration = w.decoration;
  return decoration is BoxDecoration &&
      decoration.border is Border &&
      (decoration.border! as Border).top.color == Colors.white;
});

void main() {
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<FocusNode> pumpCard(WidgetTester tester,
      {double width = 300, double height = 90}) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TvFocusable(
            focusNode: node,
            onSelect: () {},
            child: SizedBox(width: width, height: height),
          ),
        ),
      ),
    ));
    return node;
  }

  testWidgets('touch focus draws no ring and no scale', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    final node = await pumpCard(tester);

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(node.hasFocus, isTrue);
    expect(_ring, findsNothing);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
  });

  testWidgets('D-pad input brings the ring back', (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    final node = await pumpCard(tester);

    node.requestFocus();
    await tester.pumpAndSettle();
    // Android starts in touch mode, so the tap ring is suppressed.
    expect(_ring, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_ring, findsOneWidget);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        greaterThan(1.0));
  });

  testWidgets('the ring covers the whole card, not just its content',
      (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final node = await pumpCard(tester);

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(tester.getSize(_ring), const Size(300, 90));
  });
}
