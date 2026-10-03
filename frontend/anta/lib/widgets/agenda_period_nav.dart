import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../constants/form_metrics.dart';
import '../utils/lru_cache.dart';
import 'automation_id.dart';

/// Everything the height of a year's twelve month titles depends on: the
/// strings (the locale's `yMMMM` of each month of the year) and how they are
/// laid out — the width they wrap in, the text scale, the style, the
/// direction and the line limit.
typedef _YearTitlesKey = ({
  String locale,
  int year,
  double width,
  TextScaler scaler,
  TextStyle? style,
  TextDirection direction,
  int maxLines,
});

/// The navigation row above a month grid or a year overview: a chevron each
/// side, the period's title and count in the middle, and a button back to the
/// current period in a fixed slot so the title never shifts when it is
/// disabled. With [onTitleTap] the title becomes the jump control — a tap
/// opens a date picker — and wears a drop-down glyph to say so.
///
/// The title may take two lines rather than drop its year ("Oktober 20…" at
/// 200 % on the device, Tier 3 D6), and it sits in a box as tall as the
/// tallest title the row will show — the twelve month titles of [month]'s
/// year, the Dates sheet's idiom — so paging from "Juli 2026" to "September
/// 2026" never grows the row and moves the grid under the finger.
class AgendaPeriodNav extends StatelessWidget {
  /// Side of the square slots the buttons sit in — a full Material touch
  /// target, matching the chevrons.
  static const double slot = 48;

  /// How many entries [_yearTitleHeights] keeps: one per year shown at one
  /// locale, width, text scale and theme. A few dozen hold every year a
  /// session pages through at its one or two widths; the bound keeps
  /// rotations, scale changes and far jumps from growing the map for the
  /// life of the app.
  static const int yearTitleCacheSize = 32;

  /// The tallest of a year's twelve month titles, per everything that layout
  /// depends on ([_YearTitlesKey]).
  ///
  /// The row is rebuilt by every `setState` of the sheet or page above it —
  /// a day tap in the day list, a scope change, a page inside the year — and
  /// the twelve titles of one year lay out the same way each time, so their
  /// twelve formats and twelve `TextPainter` layouts are paid once per key
  /// rather than on every build. A static rather than a `State` field: a
  /// field would die with the day list and be measured again by its next
  /// opening and by the overview's nav, where one map serves every month nav
  /// of the session. The key holds every input of the layout — the line
  /// limit too, because a static outlives a hot reload that edits it — so an
  /// entry is never stale, only dropped, least recently used first.
  static final LruCache<_YearTitlesKey, double> _yearTitleHeights = LruCache(
    maxSize: yearTitleCacheSize,
  );

  static int _yearMeasurements = 0;

  /// How many times a year's twelve titles have been laid out — the misses
  /// of [_yearTitleHeights] — so a test can pin that a rebuild lays out none.
  @visibleForTesting
  static int get measurementCount => _yearMeasurements;

  final String title;

  /// The month [title] names, when the row heads a month grid. With it the
  /// title's box is measured over that year's twelve `yMMMM` titles; without
  /// it — a year nav, whose title is a bare year — over the title alone.
  final DateTime? month;
  final String? subtitle;
  final String previousTooltip;
  final String nextTooltip;
  final String todayTooltip;

  /// Null disables the button.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToday;

  final VoidCallback? onTitleTap;
  final String? titleTooltip;

  /// `SemanticsIds` for the four controls, each on the control's own node.
  /// Null leaves the node without an id, as every nav outside the day list:
  /// "Previous month" and "This year" repeat across surfaces, so a flow that
  /// walks the day list addresses its row by these.
  final String? previousIdentifier;
  final String? nextIdentifier;
  final String? todayIdentifier;
  final String? titleIdentifier;

  const AgendaPeriodNav({
    super.key,
    required this.title,
    this.month,
    this.subtitle,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.todayTooltip,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    this.onTitleTap,
    this.titleTooltip,
    this.previousIdentifier,
    this.nextIdentifier,
    this.todayIdentifier,
    this.titleIdentifier,
  });

  static Widget _identified(String? identifier, Widget child) =>
      identifier == null
      ? child
      : AutomationId(identifier: identifier, child: child);

  /// [text]'s height in [style] within [maxWidth], on at most the title's
  /// lines.
  static double _measure(
    String text,
    TextStyle? style,
    TextScaler scaler,
    TextDirection direction,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: FormMetrics.periodTitleMaxLines,
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// The box's height at the ambient text scale: the shown title's, and
  /// under a month grid at least the tallest of its year's twelve titles, so
  /// no month is taller than the box — the Dates sheet's `_monthTitleHeight`.
  /// The shown title is one layout per build; the year's twelve come from
  /// [_yearTitleHeights].
  double _titleHeight(BuildContext context, TextStyle? style, double maxWidth) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final shown = _measure(title, style, scaler, direction, maxWidth);
    final shownMonth = month;
    if (shownMonth == null) return shown;
    final tallestOfYear = _yearTitlesHeight((
      locale: Localizations.localeOf(context).toString(),
      year: shownMonth.year,
      width: maxWidth,
      scaler: scaler,
      style: style,
      direction: direction,
      maxLines: FormMetrics.periodTitleMaxLines,
    ));
    return math.max(shown, tallestOfYear);
  }

  /// The tallest of the twelve `yMMMM` titles [key] names, laid out on the
  /// first build that asks and remembered after.
  static double _yearTitlesHeight(_YearTitlesKey key) {
    final cached = _yearTitleHeights.get(key);
    if (cached != null) return cached;
    _yearMeasurements++;
    final format = DateFormat.yMMMM(key.locale);
    var height = 0.0;
    for (var m = DateTime.january; m <= DateTime.december; m++) {
      final candidate = format.format(DateTime(key.year, m));
      height = math.max(
        height,
        _measure(candidate, key.style, key.scaler, key.direction, key.width),
      );
    }
    _yearTitleHeights.put(key, height);
    return height;
  }

  /// The count's one-line height at the ambient scale, laid out unbounded:
  /// the box it shrinks inside (see [build]), so the row is as tall with a
  /// count that had to shrink as with one that did not.
  double _subtitleHeight(BuildContext context, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: subtitle, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final subtitleStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    // The builder's constraints are exactly the text's — inside the jump
    // control, what the drop-down glyph leaves it — which is why the measure
    // happens here and not outside the row.
    Widget heading = LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: _titleHeight(context, titleStyle, constraints.maxWidth),
        child: Center(
          widthFactor: 1,
          child: Text(
            title,
            style: titleStyle,
            textAlign: TextAlign.center,
            softWrap: true,
            maxLines: FormMetrics.periodTitleMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    if (onTitleTap != null) {
      heading = Tooltip(
        message: titleTooltip ?? '',
        child: InkWell(
          onTap: onTitleTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: heading),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }
    heading = _identified(titleIdentifier, heading);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        children: [
          _identified(
            previousIdentifier,
            IconButton(
              tooltip: previousTooltip,
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: onPrevious,
            ),
          ),
          Expanded(
            child: Column(
              children: [
                heading,
                if (subtitle case final subtitle?)
                  // Its own node whatever encloses the row: a loose text is
                  // absorbed by the nearest node above it, and under the day
                  // list's `day-list-body` container the count was announced
                  // as the body's label, before the scope chips, while under
                  // a sliver it had a node to itself (the simulator,
                  // 2026-10-03).
                  Semantics(
                    container: true,
                    child: SizedBox(
                      // The count shrinks rather than cuts ("32 Einträge ·
                      // 1 verpa…" at German 200 % between the chevrons and
                      // the today slot) inside a box of its one-line height
                      // at the current text scale, so a month with a longer
                      // count is no taller than one without — D7's idiom for
                      // the day numbers.
                      height: _subtitleHeight(context, subtitleStyle),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          subtitle,
                          style: subtitleStyle,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: slot,
            child: _identified(
              todayIdentifier,
              IconButton(
                tooltip: todayTooltip,
                icon: const Icon(Icons.today_rounded),
                onPressed: onToday,
              ),
            ),
          ),
          _identified(
            nextIdentifier,
            IconButton(
              tooltip: nextTooltip,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: onNext,
            ),
          ),
        ],
      ),
    );
  }
}
