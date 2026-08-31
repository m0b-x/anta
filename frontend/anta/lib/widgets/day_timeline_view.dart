import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/event_presence.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../services/event_time_formatter.dart';
import '../utils/day_timeline_layout.dart';
import 'agenda_list_view.dart';

/// "Timeline" mode of the calendar's bottom panel: the selected day drawn as
/// an hour grid, with each timed event occupying a block proportional to its
/// duration.
///
/// This is the only surface that renders `EventTime.durationMinutes` — the
/// day summary and the day bars both collapse an event to a single row.
/// All-day events have no position on the grid, so they are pinned to a strip
/// above it rather than being dropped.
class DayTimelineView extends StatefulWidget {
  /// The day being drawn, used to decide whether to show the "now" line.
  final DateTime day;

  /// Events occurring on [day], already category-filtered by the bloc.
  final List<CalendarEvent> events;

  final ValueChanged<CalendarEvent> onEventTap;

  /// Whether occurrences marked as missed are dimmed or dropped. Hidden mode
  /// filters [events] before the layout is computed, so a dropped event costs
  /// neither a block nor an all-day chip nor a column in the overlap solver.
  final CalendarMissedDisplay missedDisplay;

  final double bottomInset;

  const DayTimelineView({
    super.key,
    required this.day,
    required this.events,
    required this.onEventTap,
    this.missedDisplay = CalendarMissedDisplay.faded,
    this.bottomInset = 0,
  });

  /// Vertical scale of the grid: logical pixels per hour.
  static const double hourHeight = 56;

  /// Width of the hour-label gutter on the leading edge.
  static const double gutterWidth = 52;

  /// Horizontal gap between two side-by-side overlapping blocks.
  static const double columnGap = 4;

  /// Smallest drawn block height, so a short event stays readable and
  /// tappable even at a low [hourHeight].
  static const double minBlockHeight = 26;

  /// Vertical slack above the first gridline and below the last one. Hour
  /// rows are centered on their gridline, so without this the first and last
  /// labels would be clipped by the Stack.
  static const double _topInset = 8;

  /// Fixed height of an hour row, so the gridline lands exactly on the hour
  /// instead of wherever the label's intrinsic height happens to put it.
  static const double _hourRowHeight = 16;

  @override
  State<DayTimelineView> createState() => _DayTimelineViewState();
}

class _DayTimelineViewState extends State<DayTimelineView> {
  /// Memoized layout, so a rebuild that changes none of the three fields
  /// below (a keyboard-visibility tick, a theme rebuild bubbling down from
  /// the page) reuses the previous solve instead of re-running the overlap
  /// solver — **5.7**.
  ///
  /// `_layoutForPresenceRevision` is the load-bearing field of the three:
  /// `_isMissed` below reads `EventPresence`, a static cache the widget's own
  /// constructor arguments do not capture, so a memo keyed only on
  /// `events`/`missedDisplay` would keep serving a layout computed against a
  /// stale presence mark after a toggle — the class of bug **1.1** describes.
  /// `EventPresence.revision` is bumped on every republish, exactly like
  /// `OccurrenceDescriptions.revision`, so folding it in here is what makes
  /// the memo safe rather than just fast.
  DayTimelineLayout? _layout;
  List<CalendarEvent>? _layoutForEvents;
  CalendarMissedDisplay? _layoutForMissedDisplay;
  int? _layoutForPresenceRevision;

  DayTimelineLayout _layoutFor(List<CalendarEvent> events) {
    final missedDisplay = widget.missedDisplay;
    final presenceRevision = EventPresence.revision;
    if (_layout != null &&
        identical(_layoutForEvents, events) &&
        _layoutForMissedDisplay == missedDisplay &&
        _layoutForPresenceRevision == presenceRevision) {
      return _layout!;
    }
    // Filtered before the layout so the empty state, the hour span and the
    // overlap columns all reflect what is actually drawn.
    final visible = missedDisplay == CalendarMissedDisplay.hidden
        ? [
            for (final event in events)
              if (!_isMissed(event)) event,
          ]
        : events;
    final layout = DayTimelineLayout.compute(visible);
    _layout = layout;
    _layoutForEvents = events;
    _layoutForMissedDisplay = missedDisplay;
    _layoutForPresenceRevision = presenceRevision;
    return layout;
  }

  Color _colorFor(CalendarEvent event) {
    // Matches `EventDayBarProvider`: an explicit event color always wins for
    // a colored block (unlike icons, which additionally honor `tintIcon`).
    return event.colorValue != null
        ? Color(event.colorValue!)
        : CalendarCategories.resolve(event.categoryId).color;
  }

  /// Whether this occurrence carries a presence mark. Two static map probes,
  /// resolved through the same facade every other surface uses.
  bool _isMissed(CalendarEvent event) =>
      EventPresence.appliesTo(event) &&
      EventPresence.isMissed(event.id, widget.day);

  /// Minutes since midnight of "now", or `null` when [DayTimelineView.day] is
  /// not today.
  int? _nowMinute() {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final target = DateTime.utc(
      widget.day.year,
      widget.day.month,
      widget.day.day,
    );
    if (today != target) return null;
    return now.hour * 60 + now.minute;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final layout = _layoutFor(widget.events);

    if (layout.isEmpty) {
      return AgendaEmptyState(
        title: l10n.calendarNoEventsForDay,
        hint: l10n.timelineEmptyHint,
      );
    }

    final totalHeight =
        (layout.endHour - layout.startHour) * DayTimelineView.hourHeight;
    final nowMinute = _nowMinute();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (layout.allDayEvents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final event in layout.allDayEvents)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Opacity(
                        opacity: _isMissed(event)
                            ? CalendarColors.missedEventAlpha
                            : 1.0,
                        child: ActionChip(
                          avatar: Icon(
                            CalendarCategories.iconFor(event),
                            size: 18,
                            color: _colorFor(event),
                          ),
                          label: Text(event.title),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: _colorFor(
                            event,
                          ).withValues(alpha: 0.12),
                          onPressed: () => widget.onEventTap(event),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            // Clears the page's floating add button — see AppSpacing.
            padding: EdgeInsets.fromLTRB(
              0,
              8,
              16,
              24 + AppSpacing.fabClearance + widget.bottomInset,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth =
                    constraints.maxWidth - DayTimelineView.gutterWidth;
                return SizedBox(
                  height: totalHeight + DayTimelineView._topInset * 2,
                  child: Stack(
                    children: [
                      for (
                        var hour = layout.startHour;
                        hour <= layout.endHour;
                        hour++
                      )
                        Positioned(
                          top:
                              _offsetOf(layout, hour * 60) -
                              DayTimelineView._hourRowHeight / 2,
                          height: DayTimelineView._hourRowHeight,
                          left: 0,
                          right: 0,
                          child: _HourRow(
                            label: _hourLabel(context, hour),
                            gutterWidth: DayTimelineView.gutterWidth,
                          ),
                        ),
                      for (final block in layout.blocks)
                        Positioned(
                          top: _offsetOf(layout, block.startMinute),
                          left:
                              DayTimelineView.gutterWidth +
                              block.column * (trackWidth / block.columnCount),
                          width:
                              (trackWidth / block.columnCount) -
                              DayTimelineView.columnGap,
                          height: _blockHeight(block),
                          child: Opacity(
                            opacity: _isMissed(block.event)
                                ? CalendarColors.missedEventAlpha
                                : 1.0,
                            child: _TimelineBlockCard(
                              block: block,
                              color: _colorFor(block.event),
                              onTap: () => widget.onEventTap(block.event),
                            ),
                          ),
                        ),
                      if (nowMinute != null &&
                          nowMinute >= layout.startHour * 60 &&
                          nowMinute <= layout.endHour * 60)
                        Positioned(
                          top: _offsetOf(layout, nowMinute) - 4,
                          height: 8,
                          left: DayTimelineView.gutterWidth - 6,
                          right: 0,
                          child: _NowIndicator(color: colorScheme.error),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Vertical offset of a minute-of-day inside the grid. The single source
  /// of truth for placement, so gridlines, blocks and the now-line can never
  /// drift apart.
  double _offsetOf(DayTimelineLayout layout, int minute) {
    return DayTimelineView._topInset +
        (minute - layout.startHour * 60) / 60 * DayTimelineView.hourHeight;
  }

  double _blockHeight(TimelineBlock block) {
    final height = block.durationMinutes / 60 * DayTimelineView.hourHeight;
    return height < DayTimelineView.minBlockHeight
        ? DayTimelineView.minBlockHeight
        : height;
  }

  String _hourLabel(BuildContext context, int hour) {
    if (hour >= 24) return EventTimeFormatter.formatMinute(0, context);
    return EventTimeFormatter.formatMinute(hour * 60, context);
  }
}

class _HourRow extends StatelessWidget {
  final String label;
  final double gutterWidth;

  const _HourRow({required this.label, required this.gutterWidth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: gutterWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _TimelineBlockCard extends StatelessWidget {
  final TimelineBlock block;
  final Color color;
  final VoidCallback onTap;

  const _TimelineBlockCard({
    required this.block,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = block.event.time!;
    final compact = _blockIsCompact();

    return Material(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                block.event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!compact)
                Text(
                  EventTimeFormatter.formatRangeOfContext(time, context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Blocks shorter than roughly two text lines drop the time row so the
  /// title never overflows its own box.
  bool _blockIsCompact() =>
      block.durationMinutes / 60 * DayTimelineView.hourHeight < 40;
}

class _NowIndicator extends StatelessWidget {
  final Color color;

  const _NowIndicator({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Expanded(child: Container(height: 1.5, color: color)),
      ],
    );
  }
}
