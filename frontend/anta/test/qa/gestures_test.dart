import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/gestures.dart';

void main() {
  const width = 1280;
  const height = 2856;

  group('parseSwipeDirection', () {
    test('accepts the four directions in any case', () {
      expect(parseSwipeDirection('up'), SwipeDirection.up);
      expect(parseSwipeDirection(' Down '), SwipeDirection.down);
      expect(parseSwipeDirection('LEFT'), SwipeDirection.left);
      expect(parseSwipeDirection('right'), SwipeDirection.right);
    });

    test('rejects anything else', () {
      expect(() => parseSwipeDirection('sideways'),
          throwsA(isA<UsageFailure>()));
    });
  });

  group('buildSwipe direction vectors', () {
    test('up moves the finger towards the top', () {
      final path = buildSwipe(
          width: width, height: height, direction: SwipeDirection.up);
      expect(path.x1, path.x2);
      expect(path.y2, lessThan(path.y1));
    });

    test('down moves the finger towards the bottom', () {
      final path = buildSwipe(
          width: width, height: height, direction: SwipeDirection.down);
      expect(path.y2, greaterThan(path.y1));
    });

    test('left and right move only on x', () {
      final left = buildSwipe(
          width: width, height: height, direction: SwipeDirection.left);
      final right = buildSwipe(
          width: width, height: height, direction: SwipeDirection.right);
      expect(left.y1, left.y2);
      expect(left.x2, lessThan(left.x1));
      expect(right.x2, greaterThan(right.x1));
    });

    test('starts at the centre by default', () {
      final path = buildSwipe(
          width: width, height: height, direction: SwipeDirection.up);
      expect(path.x1, width ~/ 2);
      expect(path.y1, height ~/ 2);
    });
  });

  group('edge avoidance', () {
    test('a horizontal swipe never touches the back-gesture strips', () {
      for (final direction in [SwipeDirection.left, SwipeDirection.right]) {
        final path = buildSwipe(
          width: width,
          height: height,
          direction: direction,
          distance: 5000,
        );
        for (final x in [path.x1, path.x2]) {
          expect(x, greaterThanOrEqualTo(edgeMargin));
          expect(x, lessThanOrEqualTo(width - edgeMargin));
        }
      }
    });

    test('an explicit --from on the edge is pulled inside', () {
      final path = buildSwipe(
        width: width,
        height: height,
        direction: SwipeDirection.up,
        fromX: 0,
        fromY: 0,
      );
      expect(path.x1, edgeMargin);
      expect(path.y1, edgeMargin);

      final far = buildSwipe(
        width: width,
        height: height,
        direction: SwipeDirection.up,
        fromX: width + 100,
        fromY: height + 100,
      );
      expect(far.x1, width - edgeMargin);
      expect(far.y1, height - edgeMargin);
    });

    test('a long vertical swipe stops short of both ends', () {
      final path = buildSwipe(
        width: width,
        height: height,
        direction: SwipeDirection.up,
        distance: 99999,
      );
      expect(path.y2, edgeMargin);
      expect(path.y1, lessThanOrEqualTo(height - edgeMargin));
    });
  });

  group('inside a scrollable box', () {
    test('the path stays within the offset box', () {
      final path = buildSwipe(
        left: 100,
        top: 500,
        width: 600,
        height: 800,
        direction: SwipeDirection.up,
        distance: 5000,
      );
      expect(path.x1, 400);
      expect(path.x2, 400);
      expect(path.y1, lessThanOrEqualTo(500 + 800 - edgeMargin));
      expect(path.y2, greaterThanOrEqualTo(500 + edgeMargin));
    });

    test('an empty box is a usage failure', () {
      expect(
        () => buildSwipe(width: 0, height: 10, direction: SwipeDirection.up),
        throwsA(isA<UsageFailure>()),
      );
    });

    test('a box narrower than the margins still yields a usable point', () {
      final path = buildSwipe(
        width: 40,
        height: 40,
        direction: SwipeDirection.left,
      );
      expect(path.x1, isNotNull);
      expect(path.y1, isNotNull);
    });
  });

  test('default travel is half the axis extent', () {
    final path = buildSwipe(
      width: width,
      height: 1000,
      direction: SwipeDirection.down,
    );
    expect(path.y1, 500);
    expect(path.y2, 1000 - edgeMargin);
  });

  test('the duration is carried through', () {
    final path = buildSwipe(
      width: width,
      height: height,
      direction: SwipeDirection.up,
      durationMs: 900,
    );
    expect(path.durationMs, 900);
  });
}
