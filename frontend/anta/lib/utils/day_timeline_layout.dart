import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/calendar_event.dart';

/// One timed event placed on the day timeline.
///
/// [column] / [columnCount] describe horizontal packing: overlapping events
/// are split into side-by-side columns so neither is hidden behind the other.
class TimelineBlock {
  final CalendarEvent event;

  /// Start offset in minutes since local midnight.
  final int startMinute;

  /// End offset used for layout, clamped to the end of the day. Events that
  /// cross midnight keep their real end in [EventTime.endMinute] — only the
  /// drawn block stops at 24:00.
  final int endMinute;

  final int column;
  final int columnCount;

  const TimelineBlock({
    required this.event,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columnCount,
  });

  int get durationMinutes => endMinute - startMinute;
}

/// Layout of a single day: the all-day events, the placed timed blocks, and
/// the hour window the grid should draw.
class DayTimelineLayout {
  final List<CalendarEvent> allDayEvents;
  final List<TimelineBlock> blocks;

  /// First and last hour drawn on the grid (`startHour` inclusive,
  /// `endHour` exclusive-ish — the last gridline is drawn at [endHour]).
  final int startHour;
  final int endHour;

  const DayTimelineLayout({
    required this.allDayEvents,
    required this.blocks,
    required this.startHour,
    required this.endHour,
  });

  bool get isEmpty => allDayEvents.isEmpty && blocks.isEmpty;

  /// Smallest block height, expressed in minutes, so a zero-duration event
  /// (a point in time) still renders as a tappable band.
  static const int minBlockMinutes = 30;

  /// Hour window used when the day has no timed events to bound it.
  static const int defaultStartHour = 7;
  static const int defaultEndHour = 21;

  /// Counts [compute] invocations. Incremented inside an `assert`, so both
  /// the statement and its closure are stripped from profile and release
  /// builds and cost nothing there — mirrors `CalendarEvent.debugOccursOnCalls`.
  /// `DayTimelineView` memoizes its result (**5.7**), and this is the seam a
  /// test uses to assert the memo actually skips recomputation on an
  /// unrelated rebuild.
  @visibleForTesting
  static int debugComputeCalls = 0;

  /// Places [events] on a timeline.
  ///
  /// All-day events (`time == null`) are separated out for the pinned strip;
  /// timed events are packed into columns. Overlap is resolved per cluster —
  /// a maximal run of events that transitively overlap — so two events at
  /// 9:00 and 9:30 split the width only against each other and not against
  /// an unrelated 18:00 event.
  static DayTimelineLayout compute(List<CalendarEvent> events) {
    assert(() {
      debugComputeCalls++;
      return true;
    }());
    final allDay = <CalendarEvent>[];
    final timed = <CalendarEvent>[];
    for (final event in events) {
      if (event.time == null) {
        allDay.add(event);
      } else {
        timed.add(event);
      }
    }
    if (timed.isEmpty) {
      return DayTimelineLayout(
        allDayEvents: allDay,
        blocks: const [],
        startHour: defaultStartHour,
        endHour: defaultEndHour,
      );
    }

    timed.sort((a, b) {
      final byStart = a.time!.startMinute.compareTo(b.time!.startMinute);
      if (byStart != 0) return byStart;
      return _displayEnd(b).compareTo(_displayEnd(a));
    });

    final blocks = <TimelineBlock>[];
    var clusterStart = 0;
    var clusterMaxEnd = -1;
    // Per-column end-of-last-event within the current cluster.
    final columnEnds = <int>[];
    final pending = <_PlacedEvent>[];

    void flushCluster() {
      if (pending.isEmpty) return;
      final columnCount = columnEnds.length;
      for (final placed in pending) {
        blocks.add(
          TimelineBlock(
            event: placed.event,
            startMinute: placed.start,
            endMinute: placed.end,
            column: placed.column,
            columnCount: columnCount,
          ),
        );
      }
      pending.clear();
      columnEnds.clear();
    }

    for (var i = 0; i < timed.length; i++) {
      final event = timed[i];
      final start = event.time!.startMinute;
      final end = _displayEnd(event);
      if (i > clusterStart && start >= clusterMaxEnd) {
        flushCluster();
        clusterStart = i;
        clusterMaxEnd = -1;
      }
      var column = -1;
      for (var c = 0; c < columnEnds.length; c++) {
        if (columnEnds[c] <= start) {
          column = c;
          break;
        }
      }
      if (column == -1) {
        columnEnds.add(end);
        column = columnEnds.length - 1;
      } else {
        columnEnds[column] = end;
      }
      pending.add(
        _PlacedEvent(event: event, start: start, end: end, column: column),
      );
      if (end > clusterMaxEnd) clusterMaxEnd = end;
    }
    flushCluster();

    var minStart = blocks.first.startMinute;
    var maxEnd = blocks.first.endMinute;
    for (final block in blocks) {
      if (block.startMinute < minStart) minStart = block.startMinute;
      if (block.endMinute > maxEnd) maxEnd = block.endMinute;
    }
    final startHour = minStart ~/ 60;
    final endHour = (maxEnd / 60).ceil().clamp(startHour + 1, 24);

    return DayTimelineLayout(
      allDayEvents: allDay,
      blocks: blocks,
      startHour: startHour,
      endHour: endHour,
    );
  }

  /// Layout end of an event, floored at [minBlockMinutes] and clamped to the
  /// end of the day so a midnight-crossing event doesn't stretch the grid
  /// into a second day.
  static int _displayEnd(CalendarEvent event) {
    final time = event.time!;
    final rawEnd = time.endMinute ?? time.startMinute;
    final floored = rawEnd < time.startMinute + minBlockMinutes
        ? time.startMinute + minBlockMinutes
        : rawEnd;
    return floored > EventTime.minutesPerDay
        ? EventTime.minutesPerDay
        : floored;
  }
}

class _PlacedEvent {
  final CalendarEvent event;
  final int start;
  final int end;
  final int column;

  const _PlacedEvent({
    required this.event,
    required this.start,
    required this.end,
    required this.column,
  });
}
