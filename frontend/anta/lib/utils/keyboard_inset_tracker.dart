import 'dart:math' as math;

/// Turns the per-frame bottom view inset into the two signals the calendar
/// grid needs: whether it should be collapsed to a week, and how far through
/// the keyboard's own motion that transition is.
///
/// The collapse flag is deliberately asymmetric. It flips on as soon as the
/// inset starts growing, but off on the first *falling* frame rather than at
/// zero — the inset only reaches zero at the very end of the hide animation,
/// so waiting for it serialises the grid behind the keyboard.
class KeyboardInsetTracker {
  /// Per-frame movement below this is jitter, not motion.
  static const double _epsilon = 0.5;

  /// A frame that covers this much of the keyboard's height in one step never
  /// animated: there is nothing to couple to, so the caller runs its own timed
  /// animation instead. Android below API 30 reports the inset this way.
  static const double _jumpFraction = 0.9;

  double _inset = 0;
  double _peak = 0;
  double _learnedPeak = 0;
  bool _collapsed = false;
  bool _opening = false;
  bool _jumped = false;
  double? _progress;

  /// Whether the grid should render as a single week.
  bool get collapsed => _collapsed;

  /// How far the current transition has come, or `null` when the inset is not
  /// animating and the caller should fall back to a timed animation.
  double? get progress => _progress;

  /// Peak inset of the last completed cycle. The show path has no observed
  /// peak of its own to divide by, so it borrows this one.
  double get learnedPeak => _learnedPeak;

  void update(double inset) {
    final value = inset > 0 ? inset : 0.0;
    final previous = _inset;
    _inset = value;

    if (value == 0) {
      if (previous == 0) {
        _progress = null;
        return;
      }
      if (_peak > 0) _learnedPeak = _peak;
      _progress = previous > _peak * _jumpFraction ? null : 1.0;
      _peak = 0;
      _opening = false;
      _collapsed = false;
      return;
    }

    _peak = math.max(_peak, value);

    if (value > previous + _epsilon) {
      if (!_opening) {
        _opening = true;
        _jumped = _learnedPeak <= 0 || value >= _learnedPeak * _jumpFraction;
      }
      _collapsed = true;
      _progress = _jumped ? null : math.min(value / _learnedPeak, 1.0);
      return;
    }

    if (value < previous - _epsilon) {
      _opening = false;
      _collapsed = false;
      _progress = math.min((_peak - value) / _peak, 1.0);
    }
  }

  void reset() {
    _inset = 0;
    _peak = 0;
    _learnedPeak = 0;
    _collapsed = false;
    _opening = false;
    _jumped = false;
    _progress = null;
  }
}
