import 'package:flutter/material.dart';

import '../models/calendar_appearance.dart';
import '../models/day_cell_tint.dart';

/// Day-number cell for the calendar grid.
///
/// The number sits in a fixed-size chip anchored to the **top** of the cell,
/// leaving the bottom strip exclusively to the day markers (bars/dots), so
/// the today/selected highlight can never collide with event markers.
///
/// Also used by the calendar settings page to render a live preview of the
/// current appearance options.
class CalendarDayCell extends StatelessWidget {
  /// Diameter of the day-number chip.
  static const double chipSize = 34;

  /// Vertical space reserved above the marker strip: top inset + chip + gap.
  static const double chipZoneHeight = 4 + chipSize + 2;

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isOutside;
  final bool isWeekend;
  final CalendarTodayStyle todayStyle;
  final bool highlightWeekends;

  /// Effective highlight accent (theme primary or the user's custom color).
  final Color accent;

  /// Background decoration, already resolved by `CellTintResolver` — the cell
  /// stays a dumb painter and never learns which source won, what a fasting
  /// tradition is, or how priority maps to strength. Both colours arrive with
  /// their alpha applied.
  final DayCellTint tint;

  /// Recolours and bolds the day number for a fasting tradition using the
  /// "strong" display style. Not a tint layer — the number is the cell's own
  /// job — so it stays a separate parameter.
  final Color? fastingNumberColor;

  const CalendarDayCell({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isOutside,
    required this.isWeekend,
    required this.todayStyle,
    required this.highlightWeekends,
    required this.accent,
    this.tint = DayCellTint.empty,
    this.fastingNumberColor,
  });

  /// Text color that stays legible on top of [accent], whatever the user
  /// picked (the accent is customizable, so `onPrimary` is not enough).
  Color get _onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : Colors.black87;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filledToday =
        isToday && !isSelected && todayStyle == CalendarTodayStyle.filled;
    final strongFasting = fastingNumberColor != null;
    Color numberColor;
    if (isSelected || filledToday) {
      numberColor = _onAccent;
    } else if (isToday) {
      numberColor = accent;
    } else if (strongFasting) {
      numberColor = fastingNumberColor!;
    } else if (highlightWeekends && isWeekend) {
      numberColor = colorScheme.error.withValues(alpha: 0.85);
    } else {
      numberColor = colorScheme.onSurface;
    }

    final numberStyle = theme.textTheme.bodyMedium!.copyWith(
      color: numberColor,
      fontWeight: isToday || isSelected || strongFasting
          ? FontWeight.w700
          : FontWeight.w500,
      height: 1.0,
    );

    Widget chip;
    if (isSelected && isToday) {
      // Filled selection core plus a detached ring: "selected, and it is
      // today" reads at a glance without a second color.
      chip = Container(
        width: chipSize,
        height: chipSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 1.6),
        ),
        alignment: Alignment.center,
        child: Container(
          width: chipSize - 7,
          height: chipSize - 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          alignment: Alignment.center,
          child: Text('${day.day}', style: numberStyle),
        ),
      );
    } else {
      final decoration = isSelected
          ? BoxDecoration(shape: BoxShape.circle, color: accent)
          : isToday
          ? switch (todayStyle) {
              CalendarTodayStyle.tonal => BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.16),
              ),
              CalendarTodayStyle.ring => BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1.6),
              ),
              CalendarTodayStyle.filled => BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
              ),
            }
          : null;
      chip = Container(
        width: chipSize,
        height: chipSize,
        decoration: decoration,
        alignment: Alignment.center,
        child: Text('${day.day}', style: numberStyle),
      );
    }

    Widget cell = Align(
      alignment: Alignment.topCenter,
      child: Padding(padding: const EdgeInsets.only(top: 4), child: chip),
    );
    final wash = tint.wash;
    final edge = tint.edge;
    if (wash != null || edge != null) {
      cell = Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: wash,
          borderRadius: BorderRadius.circular(10),
        ),
        // A non-uniform `Border` cannot carry a `borderRadius`, so the
        // runner-up's stripe is stacked rather than drawn as a side.
        child: edge == null
            ? cell
            : Stack(
                children: [
                  cell,
                  Positioned(
                    left: 0,
                    top: 4,
                    bottom: 4,
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: edge,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }
    if (isOutside) {
      cell = Opacity(opacity: 0.35, child: cell);
    }
    return cell;
  }
}
