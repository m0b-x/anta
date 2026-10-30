import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:table_calendar/table_calendar.dart';

import '../constants/calendar_bounds.dart';
import '../constants/calendar_weekend.dart';
import '../constants/guide_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../services/cell_tint_resolver.dart';
import '../services/day_bars_resolver.dart';
import '../utils/calendar_days_of_week.dart';
import '../utils/calendar_week_start.dart';
import '../utils/guide_locale_format.dart';
import '../utils/lru_cache.dart';
import 'calendar_day_bars.dart';
import 'calendar_day_cell.dart';

/// The calendar page's `TableCalendar`, its arguments copied, over a
/// [GuideDemoCalendar]'s per-day map.
///
/// The one copy of that wiring in the guide: the practice calendar's two
/// lessons and the screen page's grid card draw it, and so will the fasting
/// card, so a change to how the calendar's grid is built reaches every
/// guide grid at once instead of drifting in copies (the owner's rule, D59).
/// The demo owns what it shows; the caller owns what a tap does.
class GuideCalendarGrid extends StatelessWidget {
  const GuideCalendarGrid({
    super.key,
    required this.demo,
    required this.appearance,
    required this.barsResolver,
    required this.monthTitle,
    required this.onDaySelected,
    required this.onPageChanged,
    this.holdsMonthHeight = false,
    this.tintResolver = CellTintResolver.none,
    this.numberColorFor,
  });

  /// The cells' wash, resolved per cell as the calendar page resolves it;
  /// none by default — the practice page and the screen card wash nothing.
  final CellTintResolver tintResolver;

  /// The day number's colour for a date-only UTC day — the strong fasting
  /// style, which reaches the cell outside the tint providers on the real
  /// grid too; null paints every number in the cell's own colour.
  final Color? Function(DateTime utcDay)? numberColorFor;

  /// Keeps the grid as tall as its tallest month — six rows under the
  /// tallest of the focused year's twelve titles — in every format and on
  /// every page: a card's stage must not change height when the title menu
  /// turns the grid to a week or a swipe reaches a five-row month. The
  /// practice page's grid is the page's top and moves nothing below it, so
  /// it keeps the real calendar's own heights.
  final bool holdsMonthHeight;

  final GuideDemoCalendar demo;
  final CalendarAppearance appearance;
  final DayBarsResolver barsResolver;

  /// The month title's format, kept by the caller so it is built once per
  /// locale rather than once per build.
  final GuideLocaleFormat monthTitle;

  /// [day] is the tapped day as date-only UTC; [focused] is the grid's page
  /// as `table_calendar` reports it.
  final void Function(DateTime day, DateTime focused) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  /// The most weeks a month spans: a 31-day month that starts on the week's
  /// last day.
  static const int _maxMonthRows = 6;

  static String _formatLabel(AppLocalizations l10n, CalendarFormat format) {
    return switch (format) {
      CalendarFormat.month => l10n.calendarFormatMonth,
      CalendarFormat.twoWeeks => l10n.calendarFormatTwoWeeks,
      CalendarFormat.week => l10n.calendarFormatWeek,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = appearance.accentOr(colorScheme.primary);
    final rowHeight = CalendarDayCell.rowHeightFor(
      CalendarDayBars.stripHeight(
        appearance.maxDayBars,
        appearance.markerStyle,
      ),
    );
    final cellStyle = appearance.cellStyleFor(theme.brightness);
    final monthly = demo.format == CalendarFormat.month;
    final fadesOutside = monthly;
    final titleStyle = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w600,
    );

    Widget cell(DateTime day, {required bool isOutside}) {
      final key = DateTime.utc(day.year, day.month, day.day);
      return CalendarDayCell(
        day: day,
        isToday: isSameDay(day, demo.today),
        isSelected: isSameDay(day, demo.selectedDay),
        isOutside: isOutside,
        isWeekend: CalendarWeekend.isWeekend(day),
        todayStyle: appearance.todayStyle,
        highlightWeekends: appearance.highlightWeekends,
        accent: accent,
        tint: tintResolver.resolve(day, demo.eventsFor(day)),
        cellStyle: cellStyle,
        fastingNumberColor: numberColorFor?.call(key),
      );
    }

    final grid = TableCalendar<CalendarEvent>(
      firstDay: CalendarBounds.earliest,
      lastDay: CalendarBounds.latest,
      focusedDay: demo.focusedDay,
      selectedDayPredicate: (day) => isSameDay(demo.selectedDay, day),
      calendarFormat: demo.format,
      formatAnimationDuration: const Duration(milliseconds: 1),
      pageAnimationEnabled: false,
      availableGestures: AvailableGestures.horizontalSwipe,
      eventLoader: demo.eventsFor,
      startingDayOfWeek: startingDayOfWeekFor(appearance.weekStart),
      weekendDays: CalendarWeekend.days,
      weekNumbersVisible: appearance.showWeekNumbers,
      rowHeight: rowHeight,
      daysOfWeekHeight: CalendarDaysOfWeek.height,
      locale: l10n.localeName,
      availableCalendarFormats: {
        for (final format in CalendarFormat.values)
          format: _formatLabel(l10n, format),
      },
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: titleStyle,
        headerPadding: const EdgeInsets.symmetric(
          horizontal: GuideMetrics.practiceHeaderInset,
        ),
        leftChevronMargin: EdgeInsets.zero,
        rightChevronMargin: EdgeInsets.zero,
        leftChevronPadding: const EdgeInsets.all(
          GuideMetrics.practiceChevronPadding,
        ),
        rightChevronPadding: const EdgeInsets.all(
          GuideMetrics.practiceChevronPadding,
        ),
        // The chevrons are bare ink wells: the tooltip on the glyph is
        // what names each one.
        leftChevronIcon: Tooltip(
          message: monthly
              ? l10n.dayListPreviousMonth
              : l10n.overviewPeriodPrevious,
          child: Icon(
            Icons.chevron_left_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        rightChevronIcon: Tooltip(
          message: monthly ? l10n.dayListNextMonth : l10n.overviewPeriodNext,
          child: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      daysOfWeekStyle: CalendarDaysOfWeek.style(
        theme,
        highlightWeekends: appearance.highlightWeekends,
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: true,
        weekNumberTextStyle: theme.textTheme.labelSmall!.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        markersMaxCount: 0,
      ),
      calendarBuilders: CalendarBuilders<CalendarEvent>(
        // Plain text: the stock title is a gesture detector with no
        // callback, which still reads as a button that does nothing.
        headerTitleBuilder: (context, day) => Text(
          monthTitle.of(l10n).format(day),
          style: titleStyle,
          textAlign: TextAlign.center,
        ),
        defaultBuilder: (context, day, _) => cell(day, isOutside: false),
        todayBuilder: (context, day, _) => cell(day, isOutside: false),
        selectedBuilder: (context, day, _) => cell(day, isOutside: false),
        outsideBuilder: (context, day, _) => cell(day, isOutside: fadesOutside),
        markerBuilder: (context, day, events) {
          final bars = demo.barsFor(day, events, barsResolver);
          if (bars.isEmpty) return const SizedBox.shrink();
          final isOutside =
              fadesOutside &&
              (day.month != demo.focusedDay.month ||
                  day.year != demo.focusedDay.year);
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: GuideMetrics.practiceMarkerInset,
              ),
              child: CalendarDayBars(
                bars: bars,
                maxBars: appearance.maxDayBars,
                style: appearance.markerStyle,
                opacity: isOutside ? CalendarDayCell.outsideAlpha : 1.0,
              ),
            ),
          );
        },
      ),
      onDaySelected: (selected, focused) => onDaySelected(
        DateTime.utc(selected.year, selected.month, selected.day),
        focused,
      ),
      onPageChanged: onPageChanged,
    );
    if (!holdsMonthHeight) return grid;
    // An unseen copy of the grid's frame at its tallest, laid out under it:
    // the header's row — `table_calendar`'s `CalendarHeader`, a chevron
    // button each side of the expanded title, at this grid's paddings —
    // over every title the focused year can show, then the weekday row and
    // six rows of days.
    final chevron =
        GuideMetrics.practiceChevronPadding * 2 + IconTheme.of(context).size!;
    final titles = _yearTitles(
      l10n.localeName,
      monthTitle.of(l10n),
      demo.focusedDay.year,
    );
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        IgnorePointer(
          child: ExcludeSemantics(
            child: Opacity(
              opacity: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GuideMetrics.practiceHeaderInset,
                    ),
                    child: Row(
                      children: [
                        SizedBox.square(dimension: chevron),
                        Expanded(
                          child: Stack(
                            children: [
                              for (final title in titles)
                                Text(
                                  title,
                                  style: titleStyle,
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        ),
                        SizedBox.square(dimension: chevron),
                      ],
                    ),
                  ),
                  SizedBox(
                    height:
                        CalendarDaysOfWeek.height + _maxMonthRows * rowHeight,
                  ),
                ],
              ),
            ),
          ),
        ),
        grid,
      ],
    );
  }

  /// A year's twelve titles, written once per language and year: the grid
  /// rebuilds on every tap, and a page of it stays within one or two years.
  static final LruCache<(String, int), List<String>> _titleCache = LruCache(
    maxSize: 4,
  );

  static List<String> _yearTitles(
    String localeName,
    DateFormat format,
    int year,
  ) {
    final key = (localeName, year);
    final cached = _titleCache.get(key);
    if (cached != null) return cached;
    final titles = List<String>.unmodifiable([
      for (var month = 1; month <= 12; month++)
        format.format(DateTime.utc(year, month)),
    ]);
    _titleCache.put(key, titles);
    return titles;
  }
}
