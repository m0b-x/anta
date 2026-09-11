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
  Listenable? repaint,
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
                child: ScrollProgressIndicator(
                  scrollController: controller,
                  repaint: repaint,
                ),
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
    testWidgets(
      'adopts the restored offset instead of easing up from the top',
      (tester) async {
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

        final trackHeight = tester
            .getSize(find.byType(CustomSingleChildLayout))
            .height;
        final thumbHeight = tester.getSize(_thumb).height;
        final travel = trackHeight - thumbHeight;
        final thumbTop =
            tester.getTopLeft(_thumb).dy -
            tester.getTopLeft(find.byType(CustomSingleChildLayout)).dy;

        // Seeded, not smoothed: one frame is enough to land on the real
        // position, rather than crawling there over a dozen rebuilds.
        expect(thumbTop, moreOrLessEquals(progress * travel, epsilon: 1));

        await _teardown(tester);
      },
    );

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

      final trackHeight = tester
          .getSize(find.byType(CustomSingleChildLayout))
          .height;
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

      // Keyboard closes again, with no scroll in between. This pins the
      // invariant — the thumb is a share of whatever the track measures
      // right now — rather than the exact stale-cache sequence the phone
      // hit, which is not reproducible deterministically here.
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
      final targetY = trackRect.top + thumbHeight / 2 + effectiveTrack * 0.75;
      await tester.dragFrom(
        Offset(trackRect.center.dx, trackRect.top + thumbHeight / 2),
        Offset(0, targetY - (trackRect.top + thumbHeight / 2)),
      );
      await tester.pump();

      expect(
        controller.offset,
        moreOrLessEquals(
          controller.position.maxScrollExtent * 0.75,
          epsilon: 2,
        ),
      );
      // And the thumb sits under the finger, not eased towards it.
      expect(
        tester.getCenter(_thumb).dy,
        moreOrLessEquals(targetY, epsilon: 2),
      );

      await _teardown(tester);
    });

    testWidgets(
      'comes to rest on the true position after a continuous scroll',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_harness(height: 600, controller: controller));
        await tester.pump(
          const Duration(
            milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
          ),
        );

        final maxScroll = controller.position.maxScrollExtent;
        final track = find.byType(CustomSingleChildLayout);
        double thumbTop() =>
            tester.getTopLeft(_thumb).dy - tester.getTopLeft(track).dy;
        final travel =
            tester.getSize(track).height - tester.getSize(_thumb).height;

        // A finger scroll: twenty frames of 2% each, every step well under
        // the discontinuity threshold, so each one is smoothed.
        for (var step = 1; step <= 20; step++) {
          controller.jumpTo(maxScroll * 0.02 * step);
          await tester.pump();
        }
        final expected = 0.4 * travel;
        // The filter lags a moving target — that is its job...
        expect(thumbTop(), lessThan(expected - 2));

        // ...and then, with no further scroll, it settles on its own.
        await tester.pumpAndSettle();
        expect(thumbTop(), moreOrLessEquals(expected, epsilon: 1));

        await _teardown(tester);
      },
    );

    testWidgets('the thumb stays under the finger throughout a drag', (
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

      final trackRect = tester.getRect(find.byType(CustomSingleChildLayout));
      final thumbHeight = tester.getSize(_thumb).height;
      final effectiveTrack = trackRect.height - thumbHeight;
      final start = Offset(
        trackRect.center.dx,
        trackRect.top + thumbHeight / 2,
      );

      // A short pull — 5% of the travel, well under the discontinuity
      // threshold — so only the drag rule can make the thumb exact here.
      final gesture = await tester.startGesture(start);
      await tester.pump();
      await gesture.moveBy(Offset(0, effectiveTrack * 0.05));
      await tester.pump();

      expect(
        tester.getCenter(_thumb).dy,
        moreOrLessEquals(start.dy + effectiveTrack * 0.05, epsilon: 1),
      );

      await gesture.up();
      await tester.pump();

      await _teardown(tester);
    });

    testWidgets('a repaint tick shows an offset corrected without notifying', (
      tester,
    ) async {
      // The editor restores a stored position with `correctBy` inside
      // layout, which notifies no scroll listener; it hands its metrics
      // notifications in as `repaint` so the thumb still hears about it.
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);

      await tester.pumpWidget(
        _harness(height: 600, controller: controller, repaint: repaint),
      );
      await tester.pump(
        const Duration(
          milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
        ),
      );

      final track = find.byType(CustomSingleChildLayout);
      double thumbTop() =>
          tester.getTopLeft(_thumb).dy - tester.getTopLeft(track).dy;
      final travel =
          tester.getSize(track).height - tester.getSize(_thumb).height;
      final maxScroll = controller.position.maxScrollExtent;

      controller.position.correctPixels(maxScroll * 0.6);
      await tester.pump();
      // Nothing has told the thumb yet.
      expect(thumbTop(), moreOrLessEquals(0, epsilon: 1));

      repaint.value++;
      await tester.pump();
      expect(thumbTop(), moreOrLessEquals(0.6 * travel, epsilon: 1));

      await _teardown(tester);
    });

    testWidgets(
      'content that grows under a still offset is a jump, not a glide',
      (tester) async {
        // A note reloaded four times longer beneath a buried editor keeps its
        // offset while the extent quadruples: the thumb's true position
        // changes by a third of the track with no scroll at all.
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_harness(height: 600, controller: controller));
        await tester.pump(
          const Duration(
            milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
          ),
        );
        final maxScroll = controller.position.maxScrollExtent;
        controller.jumpTo(maxScroll * 0.5);
        await tester.pump();

        await tester.pumpWidget(
          _harness(height: 600, controller: controller, itemCount: 400),
        );
        // The extent change reaches the thumb through the metrics check.
        await tester.pump(
          const Duration(
            milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs + 50,
          ),
        );

        final track = find.byType(CustomSingleChildLayout);
        final travel =
            tester.getSize(track).height - tester.getSize(_thumb).height;
        final thumbTop =
            tester.getTopLeft(_thumb).dy - tester.getTopLeft(track).dy;
        final expected =
            controller.offset / controller.position.maxScrollExtent * travel;

        expect(thumbTop, moreOrLessEquals(expected, epsilon: 1));

        await _teardown(tester);
      },
    );

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

      await tester.tapAt(
        tester.getCenter(find.byType(CustomSingleChildLayout)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.offset, 0);

      await _teardown(tester);
    });
  });
}
