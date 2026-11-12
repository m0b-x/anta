import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/event_presence.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/app_user.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/partner_look.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../utils/day_timeline_layout.dart';
import '../utils/marker_contrast.dart';
import 'agenda_list_view.dart';
import 'user_avatar.dart';

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

  /// Null draws every block and chip inert, with no tap in semantics: the
  /// guide's stages show the timeline without opening anything from it.
  final ValueChanged<CalendarEvent>? onEventTap;

  /// Whether occurrences marked as missed are dimmed or dropped. Hidden mode
  /// filters [events] before the layout is computed, so a dropped event costs
  /// neither a block nor an all-day chip nor a column in the overlap solver.
  final CalendarMissedDisplay missedDisplay;

  /// Where presence is read from; null reads `EventPresence.isMissed`. The
  /// guide's practice calendar keeps its marks in memory and passes its own,
  /// which no revision tracks — so with a reader the layout is never memoized.
  final bool Function(CalendarEvent event, DateTime dayUtc)? isMissed;

  /// Who a partner's events are from and the look they are drawn in; their
  /// words carry "From {name}" first in every look, the plain one included.
  final PartnerLook partnerLook;

  const DayTimelineView({
    super.key,
    required this.day,
    required this.events,
    this.onEventTap,
    this.missedDisplay = CalendarMissedDisplay.faded,
    this.isMissed,
    this.partnerLook = const PartnerLook(),
  });

  /// Vertical scale of the grid: logical pixels per hour.
  static const double hourHeight = 56;

  /// Width of the hour-label gutter on the leading edge.
  static const double gutterWidth = 52;

  /// Horizontal gap between two side-by-side overlapping blocks.
  static const double columnGap = 4;

  /// Between a block's title and the partner's face at the title line's end
  /// under the Avatar look.
  static const double partnerFaceGap = 4;

  /// The title width a block keeps before its partner's face is dropped: a
  /// four-column overlap on a 360 dp phone would leave the title a few
  /// letters beside the face.
  static const double partnerFaceMinTitleWidth = 40;

  /// Smallest drawn block height, for a lower [hourHeight]: at this one the
  /// layout's floor of [DayTimelineLayout.minBlockMinutes] already draws
  /// every block at least 28 dp tall, so this never applies.
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
        widget.isMissed == null &&
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
      (widget.isMissed ?? EventPresence.isMissed)(event, widget.day);

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
    final blockText = _BlockText.of(context);
    final partnerLabel = widget.partnerLook.label(l10n);

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
                        child: _allDayChip(
                          event,
                          event.fromPartner ? partnerLabel : null,
                          event.fromPartner ? widget.partnerLook : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Builder(
            builder: (context) => SingleChildScrollView(
              // Clears the page's floating add button — see AppSpacing.
              padding: EdgeInsets.fromLTRB(
                0,
                8,
                16,
                24 +
                    AppSpacing.fabClearance +
                    MediaQuery.viewInsetsOf(context).bottom,
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
                                text: blockText,
                                fromPartner: block.event.fromPartner
                                    ? partnerLabel
                                    : null,
                                look: block.event.fromPartner
                                    ? widget.partnerLook
                                    : null,
                                onTap: switch (widget.onEventTap) {
                                  final onTap? => () => onTap(block.event),
                                  null => null,
                                },
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
                            // Drawn over the blocks: a tap where the line
                            // crosses an event belongs to the event.
                            child: IgnorePointer(
                              child: _NowIndicator(color: colorScheme.error),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// An all-day event's chip. Without [DayTimelineView.onEventTap] it is a
  /// plain [Chip] in the same colours: a disabled `ActionChip` would grey
  /// it out, and an inert stage is not a disabled one. [fromPartner] is a
  /// partner's event's "From {name}", read before its title, and [look] the
  /// look it is drawn in; both null for mine.
  ///
  /// The Outlined chip keeps the chip's own 1.0 side, in the colour walked
  /// against the panel's ground: a [FormMetrics.shareOutlineWidth] side grew
  /// the chip a pixel and pushed the whole grid down at large text.
  Widget _allDayChip(
    CalendarEvent event,
    String? fromPartner,
    PartnerLook? look,
  ) {
    final ground = Theme.of(context).colorScheme.pageGround;
    final outlined = look?.outlined ?? false;
    final iconColor = EventSummaryProvider.colorFor(
      event,
      CalendarCategories.resolve(event.categoryId),
    );
    final Widget avatar = look != null && look.avatar
        // No room for a badge below the 40 dp avatar: the face takes the
        // glyph's slot.
        ? UserAvatar(
            user: look.partner ?? const AppUser(uid: ''),
            radius: RowMetrics.partnerAvatarRadius,
          )
        : Icon(
            CalendarCategories.iconFor(event),
            size: 18,
            color: outlined
                ? MarkerContrast.atLeast(iconColor, ground)
                : iconColor,
          );
    final label = Text(
      event.title,
      semanticsLabel: fromPartner == null
          ? null
          : '$fromPartner, ${event.title}',
    );
    final background = outlined
        ? Colors.transparent
        : _colorFor(event).withValues(alpha: 0.12);
    final side = outlined
        ? BorderSide(color: MarkerContrast.atLeast(_colorFor(event), ground))
        : null;
    final onTap = widget.onEventTap;
    if (onTap == null) {
      return Chip(
        avatar: avatar,
        label: label,
        visualDensity: VisualDensity.compact,
        backgroundColor: background,
        side: side,
      );
    }
    return ActionChip(
      avatar: avatar,
      label: label,
      visualDensity: VisualDensity.compact,
      backgroundColor: background,
      side: side,
      onPressed: () => onTap(event),
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

/// A block's two text styles and their line heights, measured once per
/// [DayTimelineView] build — they depend on the theme, the ambient style and
/// the text scale, never on a block.
class _BlockText {
  final TextStyle titleStyle;
  final TextStyle timeStyle;

  /// One line of each style at no text scaling.
  final double titleLine;
  final double timeLine;

  /// One line of each style at the ambient text scale.
  final double scaledTitleLine;
  final double scaledTimeLine;

  const _BlockText._({
    required this.titleStyle,
    required this.timeStyle,
    required this.titleLine,
    required this.timeLine,
    required this.scaledTitleLine,
    required this.scaledTimeLine,
  });

  factory _BlockText.of(BuildContext context) {
    final theme = Theme.of(context);
    final ambient = DefaultTextStyle.of(context).style;
    final titleStyle = ambient.merge(
      theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final timeStyle = ambient.merge(
      theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style, TextScaler scaler) {
      final painter = TextPainter(
        text: TextSpan(style: style),
        textDirection: direction,
        textScaler: scaler,
      );
      final height = painter.preferredLineHeight;
      painter.dispose();
      return height;
    }

    final titleLine = line(titleStyle, TextScaler.noScaling);
    final timeLine = line(timeStyle, TextScaler.noScaling);
    final unscaled = scaler == TextScaler.noScaling;
    return _BlockText._(
      titleStyle: titleStyle,
      timeStyle: timeStyle,
      titleLine: titleLine,
      timeLine: timeLine,
      scaledTitleLine: unscaled ? titleLine : line(titleStyle, scaler),
      scaledTimeLine: unscaled ? timeLine : line(timeStyle, scaler),
    );
  }
}

class _TimelineBlockCard extends StatelessWidget {
  final TimelineBlock block;
  final Color color;
  final _BlockText text;

  /// Null leaves the block inert.
  final VoidCallback? onTap;

  /// A partner's event's "From {name}", read first; null for mine.
  final String? fromPartner;

  /// The look a partner's event is drawn in; null for mine.
  final PartnerLook? look;

  const _TimelineBlockCard({
    required this.block,
    required this.color,
    required this.text,
    required this.onTap,
    this.fromPartner,
    this.look,
  });

  static const double _radius = 6;

  /// The content width under which the partner's face is dropped.
  static const double _faceMinContentWidth =
      _faceSize + DayTimelineView.partnerFaceMinTitleWidth;

  static const double _faceSize = 2 * RowMetrics.partnerAvatarRadius;

  /// The title's end padding that keeps it clear of the face.
  static const double _faceRoom = _faceSize + DayTimelineView.partnerFaceGap;

  @override
  Widget build(BuildContext context) {
    final time = EventTimeFormatter.formatRangeOfContext(
      block.event.time!,
      context,
    );
    final outlined = look?.outlined ?? false;
    // The ring is the block's only coloured mark, so it takes the graphics
    // floor against the panel's ground the block shows through.
    final ring = outlined
        ? BorderSide(
            color: MarkerContrast.atLeast(
              color,
              Theme.of(context).colorScheme.pageGround,
            ),
            width: FormMetrics.shareOutlineWidth,
          )
        : null;

    // One node whichever lines are drawn: a block too short for its time row
    // still says when the event is.
    return Semantics(
      label: [?fromPartner, block.event.title, time].join(', '),
      button: onTap != null,
      // The ring is painted on the Material's foreground, so the text inside
      // keeps the place it has on my blocks.
      child: Material(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.16),
        borderRadius: ring == null ? BorderRadius.circular(_radius) : null,
        shape: ring == null
            ? null
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_radius),
                side: ring,
              ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              // The stripe's lane stays under the Outlined look, unpainted,
              // so the text does not move: a filled mark on a hollow block
              // would read as mine.
              border: Border(
                left: BorderSide(
                  color: outlined ? Colors.transparent : color,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: LayoutBuilder(
              builder: (context, constraints) => ExcludeSemantics(
                child: _content(
                  time,
                  constraints.maxHeight,
                  _faceFor(constraints.maxWidth),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The partner's face under the Avatar look, where the block is wide
  /// enough to keep a readable title beside it; never dropped for height,
  /// since the shortest block still has a 20 dp line of room.
  Widget? _faceFor(double width) {
    final look = this.look;
    if (look == null || !look.avatar || width < _faceMinContentWidth) {
      return null;
    }
    return UserAvatar(
      user: look.partner ?? const AppUser(uid: ''),
      radius: RowMetrics.partnerAvatarRadius,
    );
  }

  /// [title] with [face] centred on its first line at the line's end. The
  /// title keeps its own top, so it sits where my block draws it, and the
  /// face may overhang the block's vertical padding on a line shorter than
  /// the face.
  Widget _withFace(Widget title, Widget? face, double room) {
    if (face == null) return title;
    final line = math.min(text.scaledTitleLine, room);
    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: _faceRoom),
            child: title,
          ),
          PositionedDirectional(
            end: 0,
            top: (line - _faceSize) / 2,
            width: _faceSize,
            height: _faceSize,
            child: face,
          ),
        ],
      ),
    );
  }

  /// The block is as tall as its event is long, whatever the text scale, so
  /// its text fits the block: one whole title line always — the scale is
  /// clamped to the largest at which a title line fits [room], since a
  /// taller line in a shorter box shears its letters off at the bottom —
  /// and the time row only where both lines fit.
  Widget _content(String time, double room, Widget? face) {
    final title = _withFace(
      Text(
        block.event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleStyle,
      ),
      face,
      room,
    );
    if (text.scaledTitleLine > room) {
      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: room / text.titleLine,
        child: title,
      );
    }
    if (text.scaledTitleLine + text.scaledTimeLine > room) return title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        Text(
          time,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.timeStyle,
        ),
      ],
    );
  }
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
