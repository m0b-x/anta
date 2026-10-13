import 'package:flutter/painting.dart';

import 'row_metrics.dart';

/// Budgets and timings of the calendar overview — the List mode's resolution
/// and the page's motion (`docs/calendar-overview-list-roadmap.md` §3.1, §3.8).
abstract final class OverviewListMetrics {
  /// Year mode's pager padding: the tiles sit on the rows' group inset, and
  /// the same inset below keeps the last row of tiles off the screen's edge.
  static const EdgeInsets yearPagerPadding = EdgeInsets.fromLTRB(
    RowMetrics.groupInset,
    0,
    RowMetrics.groupInset,
    RowMetrics.groupInset,
  );

  /// Months resolved before the list's first frame: two years land at once,
  /// which covers every year period and the rolling presets.
  static const int syncMonths = 24;

  /// Months per store run after the first [syncMonths], one run per
  /// event-loop turn: the store's own run limit, so a turn is one scan.
  static const int batchMonths = 12;

  /// Listed entries past which resolution stops: a long period must never
  /// hold the memory of tens of thousands of rows.
  static const int maxEntries = 20000;

  /// The most of the list's share of the page the pinned label's band may
  /// take: with the keyboard up at a large text scale on a small phone a
  /// two-line band would leave the list no height to drag, so it yields.
  static const double pinnedBandMaxShare = 0.5;

  /// Pause after the last keystroke before the query is applied, so typing a
  /// word filters once rather than once per letter.
  static const Duration searchDebounce = Duration(milliseconds: 200);

  /// The cross-fade between Year, Month and List: short enough that a mode
  /// switch never reads as a page transition.
  static const Duration modeSwitchDuration = Duration(milliseconds: 150);

  /// A chevron's animated year page: long enough to read as the same paging
  /// a swipe does, short enough that repeated taps never queue up.
  static const Duration pageDuration = Duration(milliseconds: 260);

  /// Delay before the neighbouring years are resolved, so the prewarm never
  /// competes with the frame that shows the year just landed on.
  static const Duration prewarmDelay = Duration(milliseconds: 250);
}
