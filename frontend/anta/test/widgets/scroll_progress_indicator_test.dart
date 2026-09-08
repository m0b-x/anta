import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/scroll_indicator_constants.dart';
import 'package:anta/widgets/scroll_progress_indicator.dart';

/// The thumb is the only [AnimatedContainer] under the layout delegate;
/// the other one is the track pill around it.
final Finder _thumb = find.descendant(
  of: find.byType(CustomSingleChildLayout),
  matching: find.byType(AnimatedContainer),
);

double _expectedThumbHeight(double trackHeight) =>
    (trackHeight * ScrollIndicatorConstants.thumbHeightPercentage)
        .clamp(
          ScrollIndicatorConstants.minThumbHeight,
          ScrollIndicatorConstants.maxThumbHeight,
        )
        .clamp(0.0, trackHeight);

Widget _harness({
  required double height,
  required ScrollController controller,
  int itemCount = 100,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: height,
          width: 300,
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView.builder(
                  controller: controller,
                  itemCount: itemCount,
                  itemBuilder: (_, index) =>
                      SizedBox(height: 50, child: Text('$index')),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: ScrollProgressIndicator(scrollController: controller),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Unmounts the indicator so its periodic timers are cancelled before the
/// test binding checks for pending ones.
Future<void> _teardown(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  group('ScrollProgressIndicator', () {
    testWidgets('adopts the restored offset instead of easing up from the top', (
      tester,
    ) async {
      // A note reopened mid-way through: the controller already carries the
      // stored offset before the indicator ever paints.
      final controller = ScrollController(initialScrollOffset: 2200);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_harness(height: 600, controller: controller));
      // The first frame has no content dimensions yet; the metrics check is
      // what delivers them to a caller that passes no repaint listenable.
      await tester.pump(
        const Duration(
          milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
        ),
      );

      final maxScroll = controller.position.maxScrollExtent;
      expect(maxScroll, greaterThan(0));
      final progress = 2200 / maxScroll;

      final trackHeight = tester.getSize(find.byType(CustomSingleChildLayout)).height;
      final thumbHeight = tester.getSize(_thumb).height;
      final travel = trackHeight - thumbHeight;
      final thumbTop =
          tester.getTopLeft(_thumb).dy -
          tester.getTopLeft(find.byType(CustomSingleChildLayout)).dy;

      // Seeded, not smoothed: one frame is enough to land on the real
      // position, rather than crawling there over a dozen rebuilds.
      expect(thumbTop, moreOrLessEquals(progress * travel, epsilon: 1));

      await _teardown(tester);
    });

    testWidgets('takes a large jump in one frame', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_harness(height: 600, controller: controller));
      await tester.pump(
        const Duration(
          milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
        ),
      );

      final maxScroll = controller.position.maxScrollExtent;
      controller.jumpTo(maxScroll * 0.8);
      await tester.pump();

      final trackHeight = tester.getSize(find.byType(CustomSingleChildLayout)).height;
      final travel = trackHeight - tester.getSize(_thumb).height;
      final thumbTop =
          tester.getTopLeft(_thumb).dy -
          tester.getTopLeft(find.byType(CustomSingleChildLayout)).dy;

      expect(thumbTop, moreOrLessEquals(0.8 * travel, epsilon: 1));

      await _teardown(tester);
    });

    testWidgets('thumb height follows the track when the viewport changes', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      // Keyboard closed.
      await tester.pumpWidget(_harness(height: 600, controller: controller));
      await tester.pump(
        const Duration(
          milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
        ),
      );
      expect(
        tester.getSize(_thumb).height,
        moreOrLessEquals(_expectedThumbHeight(600), epsilon: 0.5),
      );

      // Keyboard opens: the editor area shrinks.
      await tester.pumpWidget(_harness(height: 300, controller: controller));
      await tester.pump();
      expect(
        tester.getSize(_thumb).height,
        moreOrLessEquals(_expectedThumbHeight(300), epsilon: 0.5),
      );

      // Keyboard closes again. The thumb must grow back on this layout
      // alone — no scroll, no metrics tick — because nothing about its
      // geometry is cached across builds.
      await tester.pumpWidget(_harness(height: 600, controller: controller));
      await tester.pump();
      expect(
        tester.getSize(_thumb).height,
        moreOrLessEquals(_expectedThumbHeight(600), epsilon: 0.5),
      );

      await _teardown(tester);
    });

    testWidgets('dragging the thumb scrolls to the matching offset', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_harness(height: 600, controller: controller));
      await tester.pump(
        const Duration(
          milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
        ),
      );

      final track = find.byType(CustomSingleChildLayout);
      final trackRect = tester.getRect(track);
      final thumbHeight = tester.getSize(_thumb).height;
      final effectiveTrack = trackRect.height - thumbHeight;

      // Aim the thumb's centre at three quarters of its travel.
      final targetY =
          trackRect.top + thumbHeight / 2 + effectiveTrack * 0.75;
      await tester.dragFrom(
        Offset(trackRect.center.dx, trackRect.top + thumbHeight / 2),
        Offset(0, targetY - (trackRect.top + thumbHeight / 2)),
      );
      await tester.pump();

      expect(
        controller.offset,
        moreOrLessEquals(controller.position.maxScrollExtent * 0.75, epsilon: 2),
      );

      await _teardown(tester);
    });

    testWidgets('a track shorter than the minimum thumb is inert, not fatal', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      // 20px of track against a 30px minimum thumb: there is no travel to
      // map a tap onto, and the arithmetic must not throw on the way out.
      await tester.pumpWidget(_harness(height: 20, controller: controller));
      await tester.pump(
        const Duration(
          milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
        ),
      );

      await tester.tapAt(tester.getCenter(find.byType(CustomSingleChildLayout)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.offset, 0);

      await _teardown(tester);
    });
  });
}
