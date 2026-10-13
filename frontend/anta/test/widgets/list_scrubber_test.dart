import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/widgets/list_scrubber.dart';

/// The scrubber over a plain list of a thousand fixed-height rows, grouped
/// by the hundred: what a lane drag does to the list, the bubble and the
/// thumb the scrubber draws, what a drag on the rows and a tap in the lane
/// still do, and the one node it adds to the semantics tree.
void main() {
  const surface = Size(400, 800);
  const rowHeight = 48.0;
  const rowCount = 1000;
  const scrubberId = 'test-scrubber';
  const scrubberLabel = 'Scroll by group';

  String groupAt(double offset) =>
      'Group ${(offset / rowHeight).floor() ~/ 100}';

  late ScrollController controller;
  late List<int> taps;
  late int labelChanges;

  setUp(() {
    taps = [];
    labelChanges = 0;
  });

  /// [touchSlop] is the device's own slop, as Android reports it through
  /// `MediaQuery` (8 dp); null keeps the framework default.
  Future<void> pumpScrubber(
    WidgetTester tester, {
    double? touchSlop,
    ValueChanged<int>? onStep,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    if (touchSlop != null) {
      tester.view.gestureSettings = ui.GestureSettings(
        physicalTouchSlop: touchSlop,
      );
    }
    addTearDown(tester.view.reset);
    controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListScrubber(
            controller: controller,
            labelAt: groupAt,
            semanticsLabel: scrubberLabel,
            identifier: scrubberId,
            onLabelChanged: () => labelChanges++,
            onStep: onStep,
            child: ListView.builder(
              controller: controller,
              itemExtent: rowHeight,
              itemCount: rowCount,
              itemBuilder: (context, index) => InkWell(
                onTap: () => taps.add(index),
                child: Text('Row $index'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double maxOffset() => controller.position.maxScrollExtent;

  /// A point in the lane, the rightmost 48 dp, at height [y].
  Offset lane(double y) =>
      Offset(surface.width - FormMetrics.scrubberLaneWidth / 2, y);

  Finder bubble(String text) => find.descendant(
    of: find.byType(AnimatedOpacity),
    matching: find.text(text),
  );

  double bubbleOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byType(AnimatedOpacity),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  /// The scrollbar thumb's painted opacity; 0 while it is faded out.
  double thumbOpacity(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ScrollbarPainter,
      ),
    );
    return (paint.foregroundPainter! as ScrollbarPainter)
        .fadeoutOpacityAnimation
        .value;
  }

  testWidgets('a drag down the lane scrolls to the proportional offset and '
      'the bubble names the group there', (tester) async {
    await pumpScrubber(tester);

    final gesture = await tester.startGesture(lane(100));
    await gesture.moveTo(lane(130));
    await gesture.moveTo(lane(400));
    await tester.pump();

    expect(
      controller.offset,
      moreOrLessEquals(400 / surface.height * maxOffset()),
    );
    final label = groupAt(controller.offset);
    expect(bubble(label), findsOneWidget);
    expect(bubbleOpacity(tester), 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the bubble follows the pointer, stays inside the lane, sits '
      'left of the lane and fades after the lift', (tester) async {
    await pumpScrubber(tester);

    final gesture = await tester.startGesture(lane(100));
    await gesture.moveTo(lane(130));
    await gesture.moveTo(lane(300));
    await tester.pump();
    final first = find.byType(AnimatedOpacity);
    expect(tester.getCenter(first).dy, moreOrLessEquals(300));
    expect(
      tester.getTopRight(first).dx,
      moreOrLessEquals(
        surface.width -
            FormMetrics.scrubberLaneWidth -
            FormMetrics.scrubberBubbleInset,
      ),
    );

    await gesture.moveTo(lane(600));
    await tester.pump();
    expect(tester.getCenter(first).dy, moreOrLessEquals(600));

    // At the lane's very bottom the bubble stops at the edge.
    await gesture.moveTo(lane(surface.height - 1));
    await tester.pump();
    expect(tester.getBottomRight(first).dy, moreOrLessEquals(surface.height));
    expect(controller.offset, moreOrLessEquals(maxOffset(), epsilon: 60));
    final label = groupAt(controller.offset);

    await gesture.up();
    await tester.pump();
    await tester.pump(FormMetrics.scrubberBubbleFade ~/ 2);
    expect(bubble(label), findsOneWidget);
    expect(bubbleOpacity(tester), inExclusiveRange(0, 1));

    await tester.pump(FormMetrics.scrubberBubbleFade);
    expect(bubbleOpacity(tester), 0);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a drag on the rows scrolls the list as usual and shows no '
      'bubble', (tester) async {
    await pumpScrubber(tester);

    final gesture = await tester.startGesture(const Offset(100, 600));
    await gesture.moveBy(const Offset(0, -40));
    await gesture.moveBy(const Offset(0, -260));
    await tester.pump();

    expect(controller.offset, moreOrLessEquals(260, epsilon: 41));
    expect(find.byType(AnimatedOpacity), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedOpacity), findsNothing);
  });

  testWidgets('a tap in the lane reaches the row beneath it', (tester) async {
    await pumpScrubber(tester);

    await tester.tapAt(lane(rowHeight * 3 + rowHeight / 2));
    await tester.pumpAndSettle();

    expect(taps, [3]);
    expect(controller.offset, 0);
    expect(find.byType(AnimatedOpacity), findsNothing);
  });

  group('under the device touch slop (Android, 8 dp)', () {
    const deviceSlop = 8.0;

    testWidgets('a lane drag past the slop scrubs; the list never wins the '
        'arena', (tester) async {
      await pumpScrubber(tester, touchSlop: deviceSlop);

      final gesture = await tester.startGesture(lane(100));
      // Past the device slop, short of the framework's 18.
      await gesture.moveTo(lane(110));
      await gesture.moveTo(lane(400));
      await tester.pump();

      expect(
        controller.offset,
        moreOrLessEquals(400 / surface.height * maxOffset()),
      );
      expect(bubble(groupAt(controller.offset)), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a drag on the rows scrolls by its distance and a tap in the '
        'lane reaches the row', (tester) async {
      await pumpScrubber(tester, touchSlop: deviceSlop);

      final gesture = await tester.startGesture(const Offset(100, 600));
      await gesture.moveBy(const Offset(0, -20));
      await gesture.moveBy(const Offset(0, -280));
      await tester.pump();
      expect(controller.offset, moreOrLessEquals(280, epsilon: 21));
      expect(find.byType(AnimatedOpacity), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();

      final offset = controller.offset;
      final index = ((offset + 200) / rowHeight).floor();
      await tester.tapAt(lane(index * rowHeight + rowHeight / 2 - offset));
      await tester.pumpAndSettle();
      expect(taps, [index]);
      expect(controller.offset, offset);
    });
  });

  testWidgets('the thumb shows throughout a scrub held still and fades after '
      'the lift', (tester) async {
    await pumpScrubber(tester);
    expect(thumbOpacity(tester), 0);

    final gesture = await tester.startGesture(lane(100));
    await gesture.moveTo(lane(130));
    await gesture.moveTo(lane(400));
    await tester.pumpAndSettle();
    expect(thumbOpacity(tester), 1);

    // Held still far past the scrollbar's own fade-out delay.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(thumbOpacity(tester), 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(thumbOpacity(tester), 0);
  });

  testWidgets('a press where the track band was reaches the row while the '
      'thumb shows, and pages nothing', (tester) async {
    await pumpScrubber(tester);

    final scrub = await tester.startGesture(lane(100));
    await scrub.moveTo(lane(130));
    await scrub.moveTo(lane(400));
    await tester.pumpAndSettle();
    await scrub.up();
    await tester.pump();
    expect(thumbOpacity(tester), greaterThan(0));

    final offset = controller.offset;
    final index = ((offset + 300) / rowHeight).floor();
    final y = index * rowHeight + rowHeight / 2 - offset;
    // Held past the tap-down deadline, where a track tap would page.
    final press = await tester.startGesture(Offset(surface.width - 1, y));
    await tester.pump(const Duration(milliseconds: 150));
    await press.up();
    await tester.pumpAndSettle();

    expect(taps, [index]);
    expect(controller.offset, offset);
  });

  testWidgets('onLabelChanged fires once per label change', (tester) async {
    await pumpScrubber(tester);

    final seen = <String>[];
    final gesture = await tester.startGesture(lane(1));
    await gesture.moveTo(lane(25));
    seen.add(groupAt(controller.offset));
    expect(labelChanges, 0, reason: 'the start stays in the first group');

    for (var y = 35.0; y < surface.height; y += 10) {
      await gesture.moveTo(lane(y));
      final label = groupAt(controller.offset);
      if (label != seen.last) seen.add(label);
    }
    await tester.pump();
    expect(seen.first, 'Group 0');
    expect(seen.last, groupAt(maxOffset()));
    expect(labelChanges, seen.length - 1);

    // Back up across one boundary: one more.
    final before = labelChanges;
    await gesture.moveTo(lane(surface.height - 100));
    expect(labelChanges, before + 1);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('one semantics node with the id and the label; the bubble has '
      'none', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScrubber(tester);

    final node = find.bySemanticsIdentifier(scrubberId);
    expect(node, findsOneWidget);
    final data = tester.getSemantics(node).getSemanticsData();
    expect(data.label, scrubberLabel);
    expect(data.hasAction(SemanticsAction.scrollUp), isFalse);
    expect(data.hasAction(SemanticsAction.scrollDown), isFalse);

    final gesture = await tester.startGesture(lane(100));
    await gesture.moveTo(lane(130));
    await gesture.moveTo(lane(400));
    await tester.pump();
    final label = groupAt(controller.offset);
    expect(bubble(label), findsOneWidget);
    expect(find.bySemanticsLabel(label), findsNothing);
    expect(find.bySemanticsIdentifier(scrubberId), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('increase and decrease on the node step the caller on and back; '
      'without onStep the node offers neither', (tester) async {
    final semantics = tester.ensureSemantics();
    final steps = <int>[];
    await pumpScrubber(tester, onStep: steps.add);

    final node = tester.getSemantics(find.bySemanticsIdentifier(scrubberId));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    node.owner!.performAction(node.id, SemanticsAction.decrease);
    expect(steps, [1, -1]);

    await pumpScrubber(tester);
    final bare = tester
        .getSemantics(find.bySemanticsIdentifier(scrubberId))
        .getSemanticsData();
    expect(bare.hasAction(SemanticsAction.increase), isFalse);
    expect(bare.hasAction(SemanticsAction.decrease), isFalse);
    semantics.dispose();
  });
}
