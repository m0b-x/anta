/// Decides how much of the platform's bottom view inset really is a keyboard.
///
/// Android's embedding defers the keyboard inset while the IME animates and,
/// when the animation ends, replays the insets it captured as the animation
/// began (`ImeSyncDeferringInsetsCallback`). An inset change that lands while
/// that animation is still running — a field focused and left again at once,
/// the app sent to the background a moment after the keyboard was asked for —
/// is swallowed, and the replay then reports a keyboard that is no longer
/// there. Nothing corrects it until the window's insets change again, which
/// in practice is the next time the keyboard opens: until then every surface
/// that pads by the inset floats above an empty, keyboard-sized strip.
///
/// The one thing the app knows that the platform value does not say is
/// whether anything holds the focus a keyboard needs. Every input in the app
/// closes its connection when it loses focus, so with nothing focused the
/// keyboard can only be *leaving*: the inset may fall, never rise, and never
/// rest above zero. That is the whole rule, and it leaves a real dismissal
/// untouched — its falling frames pass straight through.
///
/// While something is focused the raw value is believed as it is. That is
/// deliberate: clamping there would be a guess, and a wrong guess hides the
/// field being typed into behind the keyboard.
class KeyboardInsetTrust {
  double _trusted = 0;

  /// The inset to lay out against, as of the last [observe] or [settle].
  double get trusted => _trusted;

  /// Folds one reading of the raw bottom view inset in and answers the inset
  /// to lay out against.
  ///
  /// [hasInputFocus] is whether a focus node that could own an input
  /// connection holds the focus. [appResumed] is whether the app is in front
  /// and focused; it counts because the app drops focus as it is paused, and
  /// no keyboard of ours outlives that.
  double observe({
    required double raw,
    required bool hasInputFocus,
    required bool appResumed,
  }) {
    final inset = raw > 0 ? raw : 0.0;
    if (hasInputFocus) {
      _trusted = inset;
    } else if (!appResumed) {
      _trusted = 0;
    } else if (inset < _trusted) {
      _trusted = inset;
    }
    return _trusted;
  }

  /// Folds in the fact that the raw inset has stood still for the settle
  /// window.
  ///
  /// A closing keyboard moves the inset every frame, so one that rests above
  /// zero with nothing focused is not closing: it is stale, and it is dropped.
  double settle({required bool hasInputFocus}) {
    if (!hasInputFocus) _trusted = 0;
    return _trusted;
  }
}
