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

  /// [AgendaYearTileBuilder.background].
  final Color tileBackground;

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
    required this.tileBackground,
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
    final tileBuilder = AgendaYearTileBuilder.of(
      context,
      color: color,
      appearance: appearance,
      today: today,
      onOpenMonth: onOpenMonth,
      background: tileBackground,
    );
    return GridView.builder(
      padding: padding,
      gridDelegate: YearMonthTile.gridDelegate,
      itemCount: tiles.length,
      itemBuilder: (context, index) {
        final tile = tiles[index];
        final month = tile.month;
        final highlight = highlightMonth;
        final highlighted =
            highlight != null &&
            highlight.year == month.year &&
            highlight.month == month.month;
        final tileWidget = tileBuilder.build(tile);
        if (!highlighted) return tileWidget;
        return _TileFlash(
          key: ValueKey(highlightToken),
          accent: tileBuilder.accent,
          child: tileWidget,
        );
      },
    );
  }
}

/// The one way a year overview's tile is drawn — the day list's year pages
/// and the overview's year scroll alike — so the two surfaces cannot drift
/// apart. The colours a tile derives from the theme and the appearance are
/// worked out once per build of the surface, never per tile.
class AgendaYearTileBuilder {
  /// The month labels' locale and the count's words.
  final AppLocalizations l10n;

  /// The theme's roles the tile reads beyond the derived colours below: a
  /// zero count's and the outline's.
  final ColorScheme colorScheme;

  /// The marked days and a non-zero count — the surface's own colour, which
  /// follows the calendar's palette rather than the theme.
  final Color color;

  /// The week's first day and the accent, passed down by the surface as
  /// every calendar surface takes them.
  final CalendarAppearance appearance;

  /// The day ringed: the surface's own, so a tile agrees with the nav above
  /// it across midnight.
  final DateTime today;

  /// A tile's tap; the surface decides what opening a month means.
  final ValueChanged<DateTime> onOpenMonth;

  /// [color] faded for a missed day, as the grid's missed bars fade.
  final Color missed;

  /// An unmarked day's dot, and every dot of a placeholder.
  final Color unmarked;

  /// The dots outside the window a tile counts.
  final Color outside;

  /// The tile's ground, which the matrix also paints under its dots — the
  /// surface's choice, one tone off its own ground in both themes, as
  /// Month's and List's cards are on the page.
  final Color background;

  /// Today's ring, and the flash a jump lands with.
  final Color accent;

  const AgendaYearTileBuilder._({
    required this.l10n,
    required this.colorScheme,
    required this.color,
    required this.appearance,
    required this.today,
    required this.onOpenMonth,
    required this.missed,
    required this.unmarked,
    required this.outside,
    required this.background,
    required this.accent,
  });

  /// Works out every colour from [context]'s theme once, so a surface makes
  /// one builder per build — or, for the year scroll, per change of an input
  /// its sections draw — and never derives a colour per tile.
  factory AgendaYearTileBuilder.of(
    BuildContext context, {
    required Color color,
    required CalendarAppearance appearance,
    required DateTime today,
    required ValueChanged<DateTime> onOpenMonth,
    required Color background,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return AgendaYearTileBuilder._(
      l10n: AppLocalizations.of(context)!,
      colorScheme: colorScheme,
      color: color,
      appearance: appearance,
      today: today,
      onOpenMonth: onOpenMonth,
      missed: color.withValues(alpha: CalendarColors.missedEventAlpha),
      unmarked: colorScheme.outline.withValues(
        alpha: MonthDotMatrix.unmarkedAlpha,
      ),
      outside: colorScheme.outline.withValues(
        alpha: MonthDotMatrix.outsideAlpha,
      ),
      background: background,
      accent: appearance.accentOr(colorScheme.primary),
    );
  }

  /// [tile]'s [YearMonthTile]. A [placeholder] stands in for a month not
  /// resolved yet: its count is blank in a box of the same height, and a
  /// screen reader hears the month alone rather than a count it cannot know.
  Widget build(AgendaYearTile tile, {bool placeholder = false}) {
    final month = tile.month;
    final label = AgendaYearGrid.tileLabel(l10n.localeName, month);
    return YearMonthTile(
      label: label,
      count: placeholder ? '' : '${tile.count}',
      countColor: tile.count > 0 ? color : colorScheme.onSurfaceVariant,
      semanticsLabel: placeholder
          ? label
          : '$label, '
                '${agendaDayListCountLabel(l10n, tile.count, tile.missedCount)}',
      background: background,
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
        backgroundColor: background,
        outlineColor: colorScheme.outline,
        dayColors: tile.dayColors,
      ),
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
