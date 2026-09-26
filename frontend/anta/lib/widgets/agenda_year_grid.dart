import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_colors.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../utils/agenda_day_list_index.dart';
import '../utils/calendar_week_start.dart';
import 'agenda_day_list_rows.dart';
import 'month_dot_matrix.dart';
import 'year_month_tile.dart';

/// One month of a year overview, resolved on state change so the grid only
/// paints.
class AgendaYearTile {
  final DateTime month;
  final int daysInMonth;

  /// Entries that were attended — the number the tile prints.
  final int count;

  /// Entries that were missed, announced beside the count and never added to
  /// it.
  final int missedCount;

  final int markedMask;
  final int missedMask;
  final int windowMask;

  /// The colour of each marked day's top entry, index `day - 1`, for a tile
  /// whose days come from several sources. Null paints every day in the
  /// grid's one colour.
  final List<Color?>? dayColors;

  const AgendaYearTile({
    required this.month,
    required this.daysInMonth,
    required this.count,
    required this.missedCount,
    required this.markedMask,
    required this.missedMask,
    required this.windowMask,
    this.dayColors,
  });

  /// A month of the agenda window, read from the window index: days outside
  /// the window fade.
  factory AgendaYearTile.ofWindow(AgendaDayListIndex index, DateTime month) {
    final kept = index.keptCountForMonth(month);
    return AgendaYearTile(
      month: month,
      daysInMonth: DateTime.utc(month.year, month.month + 1, 0).day,
      count: kept,
      missedCount: index.countForMonth(month) - kept,
      markedMask: index.markedMaskForMonth(month),
      missedMask: index.missedMaskForMonth(month),
      windowMask: index.windowMaskForMonth(month),
    );
  }

  /// A complete calendar month: nothing to fade, every day in the window.
  /// [perDayColors] paints each marked day in its first entry's colour — the
  /// entries arrive in same-day order, so that is the day's top entry.
  factory AgendaYearTile.ofMonth(
    AgendaDayListMonth bucket, {
    bool perDayColors = false,
  }) => AgendaYearTile(
    month: bucket.month,
    daysInMonth: bucket.daysInMonth,
    count: bucket.keptCount,
    missedCount: bucket.count - bucket.keptCount,
    markedMask: bucket.markedMask,
    missedMask: bucket.missedMask,
    windowMask: (1 << bucket.daysInMonth) - 1,
    dayColors: perDayColors ? bucket.dayColors : null,
  );

  /// The same tile from a marks-only tally — what a year page is built from,
  /// so paging costs the scan and never a row.
  factory AgendaYearTile.ofTally(
    AgendaMonthTally tally, {
    bool perDayColors = false,
  }) => AgendaYearTile(
    month: tally.month,
    daysInMonth: tally.daysInMonth,
    count: tally.keptCount,
    missedCount: tally.count - tally.keptCount,
    markedMask: tally.markedMask,
    missedMask: tally.missedMask,
    windowMask: (1 << tally.daysInMonth) - 1,
    dayColors: perDayColors ? tally.dayColors : null,
  );
}

/// The year overview: one [YearMonthTile] per [AgendaYearTile], each with a
/// dot-matrix month in [color] (or its own per-day colours) and its attendance
/// count, with the missed tally announced to a screen reader.
class AgendaYearGrid extends StatelessWidget {
  final List<AgendaYearTile> tiles;
  final Color color;
  final CalendarAppearance appearance;

  /// Date-only UTC today, ringed in its tile.
  final DateTime today;

  final ValueChanged<DateTime> onOpenMonth;
  final EdgeInsets padding;

  /// The month a jump just landed on: its tile is brought into view and
  /// flashes once. [highlightToken] changes on every jump, so landing on the
  /// same month twice flashes twice.
  final DateTime? highlightMonth;
  final int highlightToken;

  const AgendaYearGrid({
    super.key,
    required this.tiles,
    required this.color,
    required this.appearance,
    required this.today,
    required this.onOpenMonth,
    required this.padding,
    this.highlightMonth,
    this.highlightToken = 0,
  });

  static final Map<String, DateFormat> _labelFormatCache = {};

  static String tileLabel(String localeName, DateTime month) =>
      (_labelFormatCache[localeName] ??= DateFormat.yMMM(
        localeName,
      )).format(month);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final missed = color.withValues(alpha: CalendarColors.missedEventAlpha);
    final unmarked = colorScheme.outline.withValues(
      alpha: MonthDotMatrix.unmarkedAlpha,
    );
    final outside = colorScheme.outline.withValues(
      alpha: MonthDotMatrix.outsideAlpha,
    );
    final tileBackground = colorScheme.surfaceContainerHigh;
    final accent = appearance.accentOr(colorScheme.primary);
    return GridView.builder(
      padding: padding,
      gridDelegate: YearMonthTile.gridDelegate,
      itemCount: tiles.length,
      itemBuilder: (context, index) {
        final tile = tiles[index];
        final month = tile.month;
        final label = tileLabel(l10n.localeName, month);
        final highlight = highlightMonth;
        final highlighted =
            highlight != null &&
            highlight.year == month.year &&
            highlight.month == month.month;
        final tileWidget = YearMonthTile(
          label: label,
          count: '${tile.count}',
          countColor: tile.count > 0 ? color : colorScheme.onSurfaceVariant,
          semanticsLabel:
              '$label, '
              '${agendaDayListCountLabel(l10n, tile.count, tile.missedCount)}',
          background: tileBackground,
          onTap: () => onOpenMonth(month),
          matrix: MonthDotMatrix(
            daysInMonth: tile.daysInMonth,
            firstWeekdayColumn: weekdayColumnOf(month, appearance.weekStart),
            markedMask: tile.markedMask,
            missedMask: tile.missedMask,
            windowMask: tile.windowMask,
            todayIndex: today.year == month.year && today.month == month.month
                ? today.day - 1
                : null,
            markedColor: color,
            missedColor: missed,
            unmarkedColor: unmarked,
            outsideColor: outside,
            todayColor: accent,
            backgroundColor: tileBackground,
            outlineColor: colorScheme.outline,
            dayColors: tile.dayColors,
          ),
        );
        if (!highlighted) return tileWidget;
        return _TileFlash(
          key: ValueKey(highlightToken),
          accent: accent,
          child: tileWidget,
        );
      },
    );
  }
}

/// Brings a tile into view and rings it in the accent for a moment, so the
/// eye finds where a jump landed. Keyed by the jump, so a repeat re-runs it.
class _TileFlash extends StatefulWidget {
  final Color accent;
  final Widget child;

  const _TileFlash({super.key, required this.accent, required this.child});

  @override
  State<_TileFlash> createState() => _TileFlashState();
}

class _TileFlashState extends State<_TileFlash> {
  static const Duration _duration = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: _duration,
      curve: Curves.easeOutCubic,
      child: widget.child,
      builder: (context, strength, child) => Stack(
        fit: StackFit.passthrough,
        children: [
          child!,
          if (strength > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.accent.withValues(alpha: strength),
                      width: 2,
                    ),
                    color: widget.accent.withValues(alpha: 0.12 * strength),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
