import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/calendar_weekend.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/day_bar.dart';
import '../utils/calendar_week_start.dart';
import 'calendar_day_bars.dart';
import 'calendar_day_cell.dart';

/// A mini month calendar drawn with the calendar page's own day cells and
/// marker bars, over pre-resolved data.
///
/// [hasEntry] and [barsFor] must be cache-only: both run inside builders and a
/// predicate while a frame is being built, and a mid-swipe frame asks for the
/// month being left as well as the one being entered.
class AgendaMonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime firstDay;
  final DateTime lastDay;

  /// Date-only UTC today.
  final DateTime today;

  final DateTime? selectedDay;
  final CalendarAppearance appearance;
  final bool Function(DateTime day) hasEntry;
  final List<DayBar>? Function(DateTime day) barsFor;

  /// Receives a date-only UTC day.
  final ValueChanged<DateTime> onDaySelected;

  /// Receives the first day of the month paged to, date-only UTC.
  final ValueChanged<DateTime> onPageChanged;

  const AgendaMonthGrid({
    super.key,
    required this.month,
    required this.firstDay,
    required this.lastDay,
    required this.today,
    required this.selectedDay,
    required this.appearance,
    required this.hasEntry,
    required this.barsFor,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  static int maxBarsFor(CalendarAppearance appearance) =>
      appearance.maxDayBars.clamp(1, 3);

  static double rowHeightFor(CalendarAppearance appearance) {
    final strip = CalendarDayBars.stripHeight(
      maxBarsFor(appearance),
      appearance.markerStyle,
    );
    final height = CalendarDayCell.chipZoneHeight + strip + 6;
    return height < 52 ? 52 : height.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = appearance.accentOr(Theme.of(context).colorScheme.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TableCalendar<void>(
        firstDay: firstDay,
        lastDay: lastDay,
        focusedDay: month,
        headerVisible: false,
        calendarFormat: CalendarFormat.month,
        startingDayOfWeek: startingDayOfWeekFor(appearance.weekStart),
        weekendDays: CalendarWeekend.days,
        weekNumbersVisible: appearance.showWeekNumbers,
        rowHeight: rowHeightFor(appearance),
        daysOfWeekHeight: 24,
        locale: l10n.localeName,
        availableGestures: AvailableGestures.horizontalSwipe,
        selectedDayPredicate: (day) =>
            selectedDay != null && isSameDay(day, selectedDay),
        enabledDayPredicate: hasEntry,
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: false,
          markersMaxCount: 0,
        ),
        calendarBuilders: CalendarBuilders<void>(
          defaultBuilder: (context, day, _) => _cell(day, accent),
          todayBuilder: (context, day, _) => _cell(day, accent),
          selectedBuilder: (context, day, _) => _cell(day, accent),
          disabledBuilder: (context, day, _) => _cell(day, accent),
          markerBuilder: (context, day, _) => _marker(day),
        ),
        onDaySelected: (selected, _) => onDaySelected(
          DateTime.utc(selected.year, selected.month, selected.day),
        ),
        onPageChanged: (focused) =>
            onPageChanged(DateTime.utc(focused.year, focused.month, 1)),
      ),
    );
  }

  /// A day with nothing on it is drawn through the faded out-of-month path:
  /// it is inert, and a full-strength number reads as tappable. Today keeps
  /// its own styling either way.
  Widget _cell(DateTime day, Color accent) {
    final isToday = isSameDay(day, today);
    return CalendarDayCell(
      day: day,
      isToday: isToday,
      isSelected: selectedDay != null && isSameDay(day, selectedDay),
      isOutside: !isToday && !hasEntry(day),
      isWeekend: CalendarWeekend.isWeekend(day),
      todayStyle: appearance.todayStyle,
      highlightWeekends: appearance.highlightWeekends,
      accent: accent,
    );
  }

  Widget _marker(DateTime day) {
    final bars = barsFor(day);
    if (bars == null || bars.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: CalendarDayBars(
          bars: bars,
          maxBars: maxBarsFor(appearance),
          style: appearance.markerStyle,
        ),
      ),
    );
  }
}
