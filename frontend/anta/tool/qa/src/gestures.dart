import 'errors.dart';

/// Pixels kept clear of every screen edge when synthesising a swipe.
///
/// Android reserves the left and right strips for the back gesture, so a swipe
/// that starts there is taken by the system and never reaches the app.
const int edgeMargin = 48;

/// Finger travel direction of a swipe; `up` scrolls content down.
enum SwipeDirection { up, down, left, right }

SwipeDirection parseSwipeDirection(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'up' => SwipeDirection.up,
    'down' => SwipeDirection.down,
    'left' => SwipeDirection.left,
    'right' => SwipeDirection.right,
    _ => throw UsageFailure(
        'direction must be one of up, down, left, right (got "$raw")'),
  };
}

/// Start and end points of a swipe, already clamped away from the edges.
class SwipePath {
  const SwipePath(this.x1, this.y1, this.x2, this.y2, this.durationMs);

  final int x1;
  final int y1;
  final int x2;
  final int y2;
  final int durationMs;

  @override
  String toString() => '$x1,$y1 -> $x2,$y2 (${durationMs}ms)';
}

/// Builds a swipe path inside a [width] x [height] screen or scroll box.
///
/// [from] defaults to the centre of the box. [distance] defaults to half the
/// box extent along the swipe axis. Both ends are clamped to keep
/// [edgeMargin] clear on all four sides.
SwipePath buildSwipe({
  required int width,
  required int height,
  required SwipeDirection direction,
  int left = 0,
  int top = 0,
  int? fromX,
  int? fromY,
  int? distance,
  int durationMs = 300,
}) {
  if (width <= 0 || height <= 0) {
    throw UsageFailure('swipe area is empty (${width}x$height)');
  }
  final minX = left + edgeMargin;
  final maxX = left + width - edgeMargin;
  final minY = top + edgeMargin;
  final maxY = top + height - edgeMargin;

  final startX = _clamp(fromX ?? left + width ~/ 2, minX, maxX);
  final startY = _clamp(fromY ?? top + height ~/ 2, minY, maxY);

  final horizontal =
      direction == SwipeDirection.left || direction == SwipeDirection.right;
  final span = horizontal ? width : height;
  final travel = distance ?? (span ~/ 2);

  final dx = switch (direction) {
    SwipeDirection.left => -travel,
    SwipeDirection.right => travel,
    _ => 0,
  };
  final dy = switch (direction) {
    SwipeDirection.up => -travel,
    SwipeDirection.down => travel,
    _ => 0,
  };

  final endX = _clamp(startX + dx, minX, maxX);
  final endY = _clamp(startY + dy, minY, maxY);
  return SwipePath(startX, startY, endX, endY, durationMs);
}

int _clamp(int value, int min, int max) {
  if (min > max) return (min + max) ~/ 2;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
