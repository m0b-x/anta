import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/widgets/scrollable_app_bar_actions.dart';

/// The calendar's app bar carries four actions, and four fixed 48dp buttons
/// squeeze the title to an ellipsis on a narrow phone. This widget is the
/// alternative to folding one into the overflow — which would bury a button
/// that exists to be one tap away.
///
/// What is worth pinning is the pair of claims the layout makes: that the
/// group **can** scroll once it stops fitting, and that it does **not** on an
/// ordinary screen (a scroller that always scrolls would let the leading
/// buttons drift out of reach for no reason).
void main() {
  const iconWidth = 48.0;

  Widget host(double width, {int actions = 3}) {
    return MediaQuery(
      data: MediaQueryData(size: Size(width, 640)),
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Calendar'),
            actions: [
              ScrollableAppBarActions(
                children: [
                  for (var i = 0; i < actions; i++)
                    IconButton(
                      key: ValueKey('action$i'),
                      icon: const Icon(Icons.circle),
                      onPressed: () {},
                    ),
                ],
              ),
              // The overflow's stand-in: deliberately **outside** the group.
              IconButton(
                key: const ValueKey('overflow'),
                icon: const Icon(Icons.more_vert),
                onPressed: () {},
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
  }

  ScrollableState scroller(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first);

  testWidgets('a roomy toolbar has nothing to scroll', (tester) async {
    await tester.pumpWidget(host(800));

    expect(scroller(tester).position.maxScrollExtent, 0);
    expect(find.byKey(const ValueKey('action0')), findsOneWidget);
    expect(find.byKey(const ValueKey('action2')), findsOneWidget);
  });

  /// 360dp is the width this app is designed against, and the budget is picked
  /// so the full set still fits there unscrolled.
  testWidgets('the design width still fits four actions unscrolled', (
    tester,
  ) async {
    await tester.pumpWidget(host(360, actions: 3));

    expect(scroller(tester).position.maxScrollExtent, 0);
  });

  testWidgets('a narrow toolbar scrolls instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(host(280));

    final position = scroller(tester).position;
    expect(position.maxScrollExtent, greaterThan(0));
    // The budget, not the screen, is what the group is measured against.
    expect(
      position.viewportDimension,
      280 - ScrollableAppBarActions.reservedForTitle,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last action is reachable by scrolling', (tester) async {
    await tester.pumpWidget(host(280));

    // At rest the group shows its leading buttons; the trailing one is out of
    // the viewport, which is the deliberate order (least-used action last).
    final before = tester.getRect(find.byKey(const ValueKey('action2')));
    expect(before.right, greaterThan(280 - iconWidth));

    await tester.drag(find.byType(Scrollable).first, const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const ValueKey('action2'))).left,
      lessThan(before.left),
    );
  });

  /// The `⋮` belongs flush at the trailing edge on every platform, so it sits
  /// outside the group and never moves when the group is dragged.
  testWidgets('the overflow button never scrolls with the group', (
    tester,
  ) async {
    await tester.pumpWidget(host(280));
    final before = tester.getRect(find.byKey(const ValueKey('overflow')));

    await tester.drag(find.byType(Scrollable).first, const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(const ValueKey('overflow'))), before);
    expect(
      find.descendant(
        of: find.byType(ScrollableAppBarActions),
        matching: find.byKey(const ValueKey('overflow')),
      ),
      findsNothing,
    );
  });
}
