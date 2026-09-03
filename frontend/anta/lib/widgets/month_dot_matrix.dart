import 'package:flutter/material.dart';

import '../utils/marker_contrast.dart';

/// A month drawn as a 7x6 grid of rounded squares — the year overview's
/// glanceable "when in the month" picture.
///
/// The four day states are the same ones the drill-down's month grid draws, in
/// the same order of precedence: a day whose every entry was missed, a day
/// carrying entries, a day inside the window with none, and a day outside the
/// window entirely.
class MonthDotMatrix extends StatelessWidget {
  static const double cellSize = 8;
  static const double gap = 2;
  static const int columns = 7;
  static const int rows = 6;

  static const double width = columns * cellSize + (columns - 1) * gap;
  static const double height = rows * cellSize + (rows - 1) * gap;

  /// Alpha of an unmarked in-window square over the tile's background.
  ///
  /// Measured, not picked: `outline` at this alpha over `surfaceContainerHigh`
  /// clears [MarkerContrast.minContrastRatio] in **both** schemes the app's
  /// `deepPurple` seed produces — 1.67:1 light, 2.02:1 dark. The 0.25 it
  /// replaced measured 1.32:1 and 1.47:1, which is a square you cannot see.
  /// `test/widgets/month_dot_matrix_test.dart` re-measures both so the numbers
  /// cannot drift.
  static const double unmarkedAlpha = 0.45;

  /// Alpha of a square outside the window — about half [unmarkedAlpha], so the
  /// two states stay tellable apart while the faint one still registers.
  static const double outsideAlpha = 0.22;

  final int daysInMonth;
  final int firstWeekdayColumn;
  final int markedMask;

  /// Bit `day - 1` set when the day carries entries and every one of them was
  /// missed. Wins over [markedMask], which it is a subset of.
  final int missedMask;

  final int windowMask;
  final int? todayIndex;
  final Color markedColor;
  final Color missedColor;
  final Color unmarkedColor;
  final Color outsideColor;
  final Color todayColor;

  /// What the squares are painted on, for the contrast rule below.
  final Color backgroundColor;

  /// Hairline for a marked square that cannot be seen against
  /// [backgroundColor] on its own.
  final Color outlineColor;

  const MonthDotMatrix({
    super.key,
    required this.daysInMonth,
    required this.firstWeekdayColumn,
    required this.markedMask,
    required this.missedMask,
    required this.windowMask,
    required this.todayIndex,
    required this.markedColor,
    required this.missedColor,
    required this.unmarkedColor,
    required this.outsideColor,
    required this.todayColor,
    required this.backgroundColor,
    required this.outlineColor,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: MonthDotMatrixPainter(
            daysInMonth: daysInMonth,
            firstWeekdayColumn: firstWeekdayColumn,
            markedMask: markedMask,
            missedMask: missedMask,
            windowMask: windowMask,
            todayIndex: todayIndex,
            markedColor: markedColor,
            missedColor: missedColor,
            unmarkedColor: unmarkedColor,
            outsideColor: outsideColor,
            todayColor: todayColor,
            backgroundColor: backgroundColor,
            outlineColor: outlineColor,
          ),
        ),
      ),
    );
  }
}

class MonthDotMatrixPainter extends CustomPainter {
  final int daysInMonth;
  final int firstWeekdayColumn;
  final int markedMask;
  final int missedMask;
  final int windowMask;
  final int? todayIndex;
  final Color markedColor;
  final Color missedColor;
  final Color unmarkedColor;
  final Color outsideColor;
  final Color todayColor;
  final Color backgroundColor;
  final Color outlineColor;

  const MonthDotMatrixPainter({
    required this.daysInMonth,
    required this.firstWeekdayColumn,
    required this.markedMask,
    required this.missedMask,
    required this.windowMask,
    required this.todayIndex,
    required this.markedColor,
    required this.missedColor,
    required this.unmarkedColor,
    required this.outsideColor,
    required this.todayColor,
    required this.backgroundColor,
    required this.outlineColor,
  });

  static const Radius _radius = Radius.circular(1.5);

  /// Whether [color] needs the hairline to stay visible on this tile — the
  /// same 1.6:1 rule and the same memoized luminance the day-cell markers use,
  /// so a pale category never renders as an invisible square on one surface
  /// and an outlined one on the other.
  bool _needsOutline(Color color, double backgroundLuminance) {
    return MarkerContrast.contrastRatio(
          MarkerContrast.luminanceOf(color),
          backgroundLuminance,
        ) <
        MarkerContrast.minContrastRatio;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = todayColor;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = outlineColor;

    final backgroundLuminance = MarkerContrast.luminanceOf(backgroundColor);
    final outlineMarked = _needsOutline(markedColor, backgroundLuminance);
    final outlineMissed = _needsOutline(missedColor, backgroundLuminance);

    for (var index = 0; index < daysInMonth; index++) {
      final slot = firstWeekdayColumn + index;
      final column = slot % MonthDotMatrix.columns;
      final row = slot ~/ MonthDotMatrix.columns;
      if (row >= MonthDotMatrix.rows) break;

      final left = column * (MonthDotMatrix.cellSize + MonthDotMatrix.gap);
      final top = row * (MonthDotMatrix.cellSize + MonthDotMatrix.gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          top,
          MonthDotMatrix.cellSize,
          MonthDotMatrix.cellSize,
        ),
        _radius,
      );

      final bit = 1 << index;
      var outlined = false;
      if (missedMask & bit != 0) {
        fill.color = missedColor;
        outlined = outlineMissed;
      } else if (markedMask & bit != 0) {
        fill.color = markedColor;
        outlined = outlineMarked;
      } else if (windowMask & bit != 0) {
        fill.color = unmarkedColor;
      } else {
        fill.color = outsideColor;
      }
      canvas.drawRRect(rect, fill);
      if (outlined) canvas.drawRRect(rect.deflate(0.5), outline);

      if (todayIndex == index) {
        canvas.drawRRect(rect.deflate(0.5), ring);
      }
    }
  }

  @override
  bool shouldRepaint(MonthDotMatrixPainter oldDelegate) {
    return oldDelegate.daysInMonth != daysInMonth ||
        oldDelegate.firstWeekdayColumn != firstWeekdayColumn ||
        oldDelegate.markedMask != markedMask ||
        oldDelegate.missedMask != missedMask ||
        oldDelegate.windowMask != windowMask ||
        oldDelegate.todayIndex != todayIndex ||
        oldDelegate.markedColor != markedColor ||
        oldDelegate.missedColor != missedColor ||
        oldDelegate.unmarkedColor != unmarkedColor ||
        oldDelegate.outsideColor != outsideColor ||
        oldDelegate.todayColor != todayColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.outlineColor != outlineColor;
  }
}
