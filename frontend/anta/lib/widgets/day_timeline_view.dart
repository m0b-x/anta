import 'package:flutter/material.dart';

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
class DayTimelineView extends StatelessWidget {
  /// The day being drawn, used to decide whether to show the "now" line.
  final DateTime day;

  /// Events occurring on [day], already category-filtered by the bloc.
  final List<CalendarEvent> events;

  final ValueChanged<CalendarEvent> onEventTap;

  /// Whether occurrences marked as missed are dimmed or dropped. Hidden mode
  /// filters [events] before the layout is computed, so a dropped event costs
  /// neither a block nor an all-day chip nor a column in the overlap solver.
  final CalendarMissedDisplay missedDisplay;

  const DayTimelineView({
    super.key,
    required this.day,
    required this.events,
    required this.onEventTap,
    this.missedDisplay = CalendarMissedDisplay.faded,
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
      EventPresence.appliesTo(event) && EventPresence.isMissed(event.id, day);

  /// Minutes since midnight of "now", or `null` when [day] is not today.
  int? _nowMinute() {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final target = DateTime.utc(day.year, day.month, day.day);
    if (today != target) return null;
    return now.hour * 60 + now.minute;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Filtered before the layout so the empty state, the hour span and the
    // overlap columns all reflect what is actually drawn.
    final visible = missedDisplay == CalendarMissedDisplay.hidden
        ? [
            for (final event in events)
              if (!_isMissed(event)) event,
          ]
        : events;
    final layout = DayTimelineLayout.compute(visible);

    if (layout.isEmpty) {
      return AgendaEmptyState(
        title: l10n.calendarNoEventsForDay,
        hint: l10n.timelineEmptyHint,
      );
    }

    final totalHeight = (layout.endHour - layout.startHour) * hourHeight;
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
                          onPressed: () => onEventTap(event),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 8, 16, 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth - gutterWidth;
                return SizedBox(
                  height: totalHeight + _topInset * 2,
                  child: Stack(
                    children: [
                      for (
                        var hour = layout.startHour;
                        hour <= layout.endHour;
                        hour++
                      )
                        Positioned(
                          top:
                              _offsetOf(layout, hour * 60) - _hourRowHeight / 2,
                          height: _hourRowHeight,
                          left: 0,
                          right: 0,
                          child: _HourRow(
                            label: _hourLabel(context, hour),
                            gutterWidth: gutterWidth,
                          ),
                        ),
                      for (final block in layout.blocks)
                        Positioned(
                          top: _offsetOf(layout, block.startMinute),
                          left:
                              gutterWidth +
                              block.column * (trackWidth / block.columnCount),
                          width: (trackWidth / block.columnCount) - columnGap,
                          height: _blockHeight(block),
                          child: Opacity(
                            opacity: _isMissed(block.event)
                                ? CalendarColors.missedEventAlpha
                                : 1.0,
                            child: _TimelineBlockCard(
                              block: block,
                              color: _colorFor(block.event),
                              onTap: () => onEventTap(block.event),
                            ),
                          ),
                        ),
                      if (nowMinute != null &&
                          nowMinute >= layout.startHour * 60 &&
                          nowMinute <= layout.endHour * 60)
                        Positioned(
                          top: _offsetOf(layout, nowMinute) - 4,
                          height: 8,
                          left: gutterWidth - 6,
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
    return _topInset + (minute - layout.startHour * 60) / 60 * hourHeight;
  }

  double _blockHeight(TimelineBlock block) {
    final height = block.durationMinutes / 60 * hourHeight;
    return height < minBlockHeight ? minBlockHeight : height;
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
