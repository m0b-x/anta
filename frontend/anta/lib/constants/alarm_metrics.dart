/// The ring screen's own numbers.
///
/// The alarm page is a takeover page, the UI language's fourth idiom: it
/// reads the language's tokens and its row kit, and everything a form or a
/// row already names comes from `FormMetrics` and `RowMetrics`. What is left
/// is what only a ring screen has — a display numeral and a pinned pair of
/// buttons sized for a hand that is half asleep — and it lives here, the way
/// the bars' numbers live in `AppBarMetrics`, rather than in `FormMetrics`,
/// which holds what a form uses.
abstract final class AlarmMetrics {
  /// The time the ring was due at: the one display numeral in the app, read
  /// first and at arm's length. Never scaled with the text — it is fitted to
  /// the page's width instead — so [heroLineHeight] is the height it holds
  /// at every text scale and for every string, an empty one included.
  static const double heroFontSize = 64;
  static const double heroLineHeight = 68;

  /// Between the day under the time and the event's card.
  static const double heroGap = 16;

  /// How much of the event's description the card shows: its first line,
  /// wrapped at most this far. More would push the time off the top of a
  /// short phone for a text the event's own sheet is one tap away from.
  static const int excerptMaxLines = 2;

  /// Between the dock's rows — the remove row, Stop, Snooze — and between
  /// the card and the dock.
  static const double dockGap = 12;

  /// Under Snooze, above the system's own bottom inset: the button on the
  /// screen's edge still needs air between it and the gesture bar.
  static const double dockBottomPadding = 12;

  /// Stop's minimum height. The largest target on the page, because it is
  /// the one that settles the ring; a label that wraps makes it taller.
  static const double stopHeight = 64;

  /// Snooze's minimum height: a step under Stop, and still well over the
  /// 48 dp floor, since it is the button a grabbing hand lands on.
  static const double snoozeHeight = 56;

  /// Stop's and Snooze's labels, a step apart like their heights.
  static const double stopLabelSize = 20;
  static const double snoozeLabelSize = 17;

  /// The glyph before each of the two labels — the rows' glyph size, so the
  /// dock's icons and the card's read as one set.
  static const double dockIconSize = 22;

  /// The most the dock's text grows with the phone's text scale, the time
  /// pad's own ceiling: past it the German Snooze label no longer fits one
  /// line on a 360 dp phone, and a dock that wraps takes the card's room.
  static const double dockMaxTextScale = 1.4;

  /// The page's body height under which the dock is no longer pinned and
  /// scrolls as the end of the content instead — landscape, a split screen.
  /// Pinned there, the dock would leave the card a strip too short to read.
  static const double pinnedDockMinHeight = 480;
}
