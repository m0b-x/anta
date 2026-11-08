/// The pure half of a custom-order write: which order the whole group takes
/// after a drag, and which `position` each row needs for it.
///
/// Split from the DAOs so the planning can be tested without a database and
/// so the transaction around it never changes when the allocator does.
library;

import '../constants/app_constants.dart';

const int _stride = AppConstants.positionStride;

/// Beyond this magnitude a key is treated as corrupt (a remote row near the
/// int64 edge): arithmetic between two such keys could wrap.
const int _safeMagnitude = 1 << 61;

/// Where a row appended after [maxPosition] goes; [maxPosition] is null for
/// an empty group. A maximum at the int64 edge ties instead of wrapping; the
/// next drag in that group respreads it.
int nextPosition(int? maxPosition) {
  if (maxPosition == null) return 0;
  if (maxPosition > _safeMagnitude) return maxPosition;
  return maxPosition + _stride;
}

/// One row of a group as the database holds it, in display order.
typedef PositionedId = ({String id, int position});

/// The group's full new order: the rows the page had loaded, in the order
/// the user left them, put where the loaded window sat.
///
/// Rows that sort before the first loaded row — created after the page
/// loaded, at the top of a `positionDesc` list — stay before it; every other
/// unloaded row follows the window in its stored order.
///
/// [windowAtTop] is for the first drag after a title, date or label sort:
/// the page showed an order the positions never held, so its rows are not a
/// stretch of the stored order at all, and the window goes first — what the
/// user saw is what the reload shows on top.
///
/// [displayOrder] is the group read in its active custom direction. Ids in
/// [loadedOrder] the group no longer holds are dropped, and a repeated id
/// counts once.
List<String> spliceLoadedOrder({
  required List<String> displayOrder,
  required List<String> loadedOrder,
  bool windowAtTop = false,
}) {
  final known = displayOrder.toSet();
  final placed = <String>{};
  final window = <String>[
    for (final id in loadedOrder)
      if (known.contains(id) && placed.add(id)) id,
  ];
  final first = windowAtTop ? 0 : displayOrder.indexWhere(placed.contains);
  if (first < 0) return [...displayOrder];
  return [
    for (final id in displayOrder.take(first))
      if (!placed.contains(id)) id,
    ...window,
    for (final id in displayOrder.skip(first))
      if (!placed.contains(id)) id,
  ];
}

/// The positions [order] needs, as only the rows that must move.
///
/// The rows forming the longest run already in order keep their positions
/// (so one drag moves one row); each other run takes even steps between its
/// new neighbours. Only when two neighbours have no room left is the window
/// widened, one neighbour at a time towards the nearer end of the list —
/// and then it keeps widening until its rows can sit [_widenedGap] apart, or
/// it reaches an open end, where it steps away by the stride. The bar grows
/// with the window, as in order-maintenance labelling: a small pile is
/// respread cheaply among its near neighbours, and only a crowded
/// neighbourhood forces a wide window — which then leaves room for many
/// more drags at that spot. Measured over 300 drags into one gap of a
/// stride-spaced group: 1,176 rows written in all (a fixed half-stride bar
/// wrote 3,958, a bar loosening with the window 3,160). A dense region is so
/// healed once, never the whole group while both ends are closed.
///
/// Keys past ±2^61 (a corrupt remote position) cannot be stepped between
/// without wrapping; the whole group is then respread from zero.
///
/// [descending] plans for a group read `ORDER BY position DESC`: keys are
/// the negated positions, so the display reads keys in ascending order.
Map<String, int> planGappedPositions({
  required List<PositionedId> current,
  required List<String> order,
  required bool descending,
}) {
  final stored = {for (final row in current) row.id: row.position};
  final n = order.length;
  // Checked on the stored values, before any negation: `abs()` and unary
  // minus both wrap at -2^63, which would slip a corrupt key past the guard.
  final corrupt = [
    for (final id in order) stored[id] ?? 0,
  ].any((p) => p > _safeMagnitude || p < -_safeMagnitude);
  final keys = [
    for (final id in order)
      corrupt
          ? 0
          : descending
          ? -(stored[id] ?? 0)
          : (stored[id] ?? 0),
  ];
  final fixed = corrupt
      ? List<bool>.filled(n, false)
      : _longestIncreasing(keys);
  final next = [...keys];

  var i = 0;
  while (i < n) {
    if (fixed[i]) {
      i++;
      continue;
    }
    var a = i;
    var b = i;
    while (b < n && !fixed[b]) {
      b++;
    }
    var widened = false;
    while (true) {
      final lo = a > 0 ? next[a - 1] : null;
      final hi = b < n ? next[b] : null;
      final m = b - a;
      final roomy =
          lo == null ||
          hi == null ||
          (widened ? (hi - lo) ~/ (m + 1) >= _widenedGap(m) : hi - lo - 1 >= m);
      if (!roomy) {
        // No room: take in the neighbour on the side nearer its open end.
        widened = true;
        if (a <= n - b) {
          a--;
        } else {
          b++;
        }
        continue;
      }
      for (var k = 0; k < m; k++) {
        next[a + k] = switch ((lo, hi)) {
          (final int lo, final int hi) => lo + (hi - lo) ~/ (m + 1) * (k + 1),
          (final int lo, null) => lo + _stride * (k + 1),
          (null, final int hi) => hi - _stride * (m - k),
          (null, null) => _stride * k,
        };
      }
      break;
    }
    i = b;
  }

  final changes = <String, int>{};
  for (var k = 0; k < n; k++) {
    final position = descending ? -next[k] : next[k];
    if (stored[order[k]] != position) changes[order[k]] = position;
  }
  return changes;
}

/// The average gap a widened window of [m] rows must reach before it is
/// respread: about m² key units, capped at half a stride.
int _widenedGap(int m) {
  final grown = 1 << (2 * m.bitLength);
  return grown < _stride ~/ 2 ? grown : _stride ~/ 2;
}

/// Marks one longest strictly increasing subsequence of [keys]
/// (patience sorting, O(n log n)).
List<bool> _longestIncreasing(List<int> keys) {
  final tails = <int>[];
  final previous = List<int>.filled(keys.length, -1);
  for (var i = 0; i < keys.length; i++) {
    var low = 0;
    var high = tails.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (keys[tails[mid]] < keys[i]) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0) previous[i] = tails[low - 1];
    if (low == tails.length) {
      tails.add(i);
    } else {
      tails[low] = i;
    }
  }
  final fixed = List<bool>.filled(keys.length, false);
  var k = tails.isEmpty ? -1 : tails.last;
  while (k >= 0) {
    fixed[k] = true;
    k = previous[k];
  }
  return fixed;
}
