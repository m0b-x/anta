import 'package:flutter/material.dart';

import '../constants/calendar_colors.dart';
import '../constants/calendar_weekend.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_bar.dart';
import '../models/day_cell_tint.dart';
import '../models/day_rail_mark.dart';
import '../services/recurrence_formatter.dart';
import 'calendar_day_bars.dart';
import 'calendar_day_cell.dart';
import 'calendar_day_rail.dart';

/// Live preview strip: the seven days of the week containing today, under a
/// weekday header, rendered with the exact widgets the calendar grid uses —
/// so every appearance option is visible without leaving the settings page.
///
/// A full week rather than a hand-picked handful of cells for two reasons:
/// seven cells across the same width land within a couple of logical pixels
/// of the real grid's column, and the week is what lets the week-start
/// setting demonstrate itself by rotating the strip.
///
/// Five cells carry a sample decoration — the weekend bar, today, the
/// selected day, and a busy day whose markers and rail marks both overflow —
/// and the rest render plain, which is the untinted baseline. The *days* are
/// real (today keeps its own position in the week), but the decorations are
/// **illustrative, not a real week's data**: they land on whichever cells are
/// free once today and the selected sample have taken theirs, so a weekend
/// bar can end up on a weekday when today and tomorrow are the weekend.
class CalendarAppearancePreview extends StatelessWidget {
  final CalendarAppearance appearance;

  const CalendarAppearancePreview({super.key, required this.appearance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final accent = appearance.accentOr(colorScheme.primary);
    // Once per preview, not once per cell — and from the *ambient* brightness,
    // so the preview shows the half of the setting the user is looking at.
    final cellStyle = appearance.cellStyleFor(theme.brightness);
    // Date-only UTC, the normalization every other calendar surface uses: the
    // strip steps a whole week by whole days, and local-time arithmetic
    // repeats or skips a date across a DST boundary.
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final todayIndex = (today.weekday - appearance.weekStart.weekday + 7) % 7;
    final days = [
      for (var i = 0; i < 7; i++) today.add(Duration(days: i - todayIndex)),
    ];
    final layout = _SampleLayout.of(days, todayIndex);
    // Matches the grid's own day-of-week header (`calendar_page.dart`'s
    // `dowStyle`) so the strip reads as a week rather than as a legend.
    final dowStyle = theme.textTheme.labelMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );

    final palette = [
      for (final value in CalendarColors.swatchPalette) Color(value),
    ];
    final overflowBars = [
      for (var i = 0; i <= appearance.maxDayBars; i++)
        _previewBar('overflow$i', palette[(i * 3) % palette.length]),
    ];
    // One over the cap, so the overflow affordance previews too — the same
    // trick `overflowBars` plays for the marker strip. The **first** mark is
    // the missed one, because hollow-vs-filled is the part of the rail that
    // is hard to picture from the setting's copy alone, and at a cap of 1 the
    // first mark is the only one drawn.
    final overflowRailMarks = [
      for (var i = 0; i <= appearance.maxDayRailMarks; i++)
        _previewRailMark(
          'railOverflow$i',
          palette[(i * 5) % palette.length],
          missed: i == 0,
        ),
    ];
    // Both heights come from the grid's own definitions rather than being
    // restated here — the preview's whole job is to be the grid. Restating
    // the row formula is exactly how the two drifted: the copy lost the
    // grid's `ceilToDouble`, so every even `maxDayBars` previewed a row half
    // a pixel short, and because this number is `railLaneHeight`'s input the
    // error carried straight into the rail capacity the preview claimed.
    final previewStripHeight = CalendarDayBars.stripHeight(
      appearance.maxDayBars,
      appearance.markerStyle,
    );
    final previewCellHeight = CalendarDayCell.rowHeightFor(previewStripHeight);
    // The same lane the grid computes, through the same helper: the preview
    // stacks its strip in a sibling `Align` at the same 4px offset, so
    // previewing a capacity the grid does not have would be a lie.
    final previewRailHeight = CalendarDayCell.railLaneHeight(
      rowHeight: previewCellHeight,
      stripHeight: previewStripHeight,
      railStyle: appearance.dayRailStyle,
    );

    // Samples the real alpha ramp rather than picked-by-eye values, so the
    // preview cannot drift from the grid. `priority` is 1-based like the
    // event field; a null one means the day carries no event.
    DayCellTint previewTint(Color color, {int? priority}) {
      if (!appearance.eventTint) {
        return priority == null
            ? DayCellTint.empty
            // With the tint off, a fasting day is the only wash there is.
            : DayCellTint(
                wash: CalendarColors.fasting.withValues(
                  alpha: CalendarColors.fastingTintAlpha,
                ),
              );
      }
      if (priority == null) return DayCellTint.empty;
      final eventWash = color.withValues(
        alpha: CalendarColors.eventTintAlphaByPriority[priority - 1],
      );
      final fastingWash = CalendarColors.fasting.withValues(
        alpha: CalendarColors.fastingTintAlpha,
      );
      return switch (appearance.tintConflict) {
        CalendarTintConflict.eventWins => DayCellTint(wash: eventWash),
        CalendarTintConflict.fastingWins => DayCellTint(wash: fastingWash),
        CalendarTintConflict.both => DayCellTint(
          wash: eventWash,
          edge: CalendarColors.fasting.withValues(
            alpha: CalendarColors.cellEdgeAlpha,
          ),
        ),
      };
    }

    Widget cell(
      DateTime day, {
      bool isToday = false,
      bool isSelected = false,
      List<DayBar> bars = const [],
      DayCellTint tint = DayCellTint.empty,
      List<DayRailMark> railMarks = const [],
    }) {
      // Real weekend-ness, not a sample flag: the days below are a real week,
      // so `highlightWeekends` previews on the days it will actually paint.
      final isWeekend = CalendarWeekend.isWeekend(day);
      final railLabel = CalendarDayRail.semanticsLabelFor(
        marks: railMarks,
        style: appearance.dayRailStyle,
        maxMarks: appearance.maxDayRailMarks,
        height: previewRailHeight,
        hasBase: tint.edge != null,
      );
      return Expanded(
        child: SizedBox(
          height: previewCellHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CalendarDayCell(
                  day: day,
                  isToday: isToday,
                  isSelected: isSelected,
                  isOutside: false,
                  isWeekend: isWeekend,
                  todayStyle: appearance.todayStyle,
                  highlightWeekends: appearance.highlightWeekends,
                  accent: accent,
                  tint: tint,
                  cellStyle: cellStyle,
                  railMarks: railMarks,
                  railStyle: appearance.dayRailStyle,
                  maxRailMarks: appearance.maxDayRailMarks,
                  railBasePosition: appearance.dayRailBasePosition,
                  railHeight: previewRailHeight,
                ),
              ),
              if (bars.isNotEmpty || railLabel != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: CalendarDayBars(
                      bars: bars,
                      maxBars: appearance.maxDayBars,
                      style: appearance.markerStyle,
                      railLabel: railLabel,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Text(
                    RecurrenceFormatter.weekdayShort(
                      day.weekday,
                      l10n.localeName,
                    ),
                    style: dowStyle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                if (i == layout.todayIndex)
                  // The two tinted samples sit at opposite ends of the
                  // priority ramp so the "stronger means higher priority"
                  // claim is visible.
                  cell(
                    days[i],
                    isToday: true,
                    bars: [_previewBar('a', palette[0])],
                    tint: previewTint(palette[0], priority: kMinEventPriority),
                    railMarks: [_previewRailMark('rail1', palette[2])],
                  )
                else if (i == layout.selectedIndex)
                  cell(
                    days[i],
                    isSelected: true,
                    bars: [
                      _previewBar('b', palette[3]),
                      _previewBar('c', palette[7]),
                    ],
                    tint: previewTint(palette[3], priority: kMaxEventPriority),
                    railMarks: [
                      _previewRailMark('rail2', palette[2]),
                      _previewRailMark('rail3', palette[6]),
                    ],
                  )
                else if (i == layout.weekendIndex)
                  cell(
                    days[i],
                    bars: [_previewBar('weekend', CalendarColors.weekend)],
                  )
                else if (i == layout.overflowIndex)
                  cell(
                    days[i],
                    bars: overflowBars,
                    railMarks: overflowRailMarks,
                  )
                else
                  cell(days[i]),
            ],
          ),
        ],
      ),
    );
  }

  static DayBar _previewBar(String key, Color color) {
    return DayBar(key: key, color: color, priority: 0, semanticLabel: '');
  }

  static DayRailMark _previewRailMark(
    String key,
    Color color, {
    bool missed = false,
  }) {
    return DayRailMark(
      key: key,
      color: color,
      priority: 0,
      missed: missed,
      semanticLabel: '',
    );
  }
}

/// Which cell of the week carries which sample decoration.
///
/// Today keeps whatever position the real date gives it, and the selected
/// sample sits immediately next to it — adjacent so the two tinted cells read
/// as one comparison of the priority ramp's ends, and falling back to the
/// cell *before* today when today closes the week. Everything after that
/// fills whatever is left: the weekend bar prefers a real weekend day, and
/// the overflow sample takes the last free cell so the busiest day closes the
/// row.
///
/// When today and the selected sample have already eaten both weekend days
/// the bar lands on a weekday instead. That is deliberate — the strip is
/// illustrative, not a real week's data, and losing the weekend sample
/// entirely would cost more than showing it a day early.
class _SampleLayout {
  const _SampleLayout({
    required this.todayIndex,
    required this.selectedIndex,
    required this.weekendIndex,
    required this.overflowIndex,
  });

  final int todayIndex;
  final int selectedIndex;
  final int? weekendIndex;
  final int? overflowIndex;

  static _SampleLayout of(List<DateTime> days, int todayIndex) {
    final selectedIndex = todayIndex + 1 < days.length
        ? todayIndex + 1
        : todayIndex - 1;
    final used = <int>{todayIndex, selectedIndex};

    int? weekendIndex;
    for (var i = 0; i < days.length; i++) {
      if (!used.contains(i) && CalendarWeekend.isWeekend(days[i])) {
        weekendIndex = i;
        break;
      }
    }
    weekendIndex ??= _firstFree(days.length, used);
    if (weekendIndex != null) used.add(weekendIndex);

    return _SampleLayout(
      todayIndex: todayIndex,
      selectedIndex: selectedIndex,
      weekendIndex: weekendIndex,
      overflowIndex: _lastFree(days.length, used),
    );
  }

  static int? _firstFree(int length, Set<int> used) {
    for (var i = 0; i < length; i++) {
      if (!used.contains(i)) return i;
    }
    return null;
  }

  static int? _lastFree(int length, Set<int> used) {
    for (var i = length - 1; i >= 0; i--) {
      if (!used.contains(i)) return i;
    }
    return null;
  }
}
