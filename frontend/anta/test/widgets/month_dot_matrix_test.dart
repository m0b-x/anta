import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/utils/marker_contrast.dart';
import 'package:anta/widgets/month_dot_matrix.dart';

const _marked = Color(0xFF1E88E5);
const _missed = Color(0x591E88E5);
const _unmarked = Color(0x40808080);
const _outside = Color(0x20808080);
const _today = Color(0xFFFFB300);
const _background = Color(0xFF1B1B1F);
const _outline = Color(0xFF938F99);

MonthDotMatrixPainter _painter({
  int daysInMonth = 30,
  int firstWeekdayColumn = 2,
  int markedMask = 0x5,
  int missedMask = 0,
  int windowMask = 0x3FFFFFFF,
  int? todayIndex = 4,
  Color markedColor = _marked,
  Color missedColor = _missed,
  Color unmarkedColor = _unmarked,
  Color outsideColor = _outside,
  Color todayColor = _today,
  Color backgroundColor = _background,
  Color outlineColor = _outline,
  int? selectedIndex,
  Color? selectedColor,
}) {
  return MonthDotMatrixPainter(
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
    selectedIndex: selectedIndex,
    selectedColor: selectedColor,
  );
}

const _selected = Color(0xFFE6E1E5);

/// A 30-day month from the third column, its last day outside the window.
MonthDotMatrix _matrix({ValueChanged<int>? onDayTap}) => MonthDotMatrix(
  daysInMonth: 30,
  firstWeekdayColumn: 2,
  markedMask: 0x5,
  missedMask: 0,
  windowMask: 0x1FFFFFFF,
  todayIndex: 4,
  markedColor: _marked,
  missedColor: _missed,
  unmarkedColor: _unmarked,
  outsideColor: _outside,
  todayColor: _today,
  backgroundColor: _background,
  outlineColor: _outline,
  onDayTap: onDayTap,
);

/// The centre of the square in [slot] of the 7 × 6 grid, in the matrix's
/// own units.
Offset _centreOf(int slot) {
  const pitch = MonthDotMatrix.cellSize + MonthDotMatrix.gap;
  return Offset(
    slot % MonthDotMatrix.columns * pitch + MonthDotMatrix.cellSize / 2,
    slot ~/ MonthDotMatrix.columns * pitch + MonthDotMatrix.cellSize / 2,
  );
}

/// What [painter] draws on a matrix-sized canvas, call by call.
List<String> _recorded(MonthDotMatrixPainter painter) {
  final canvas = TestRecordingCanvas();
  painter.paint(
    canvas,
    const Size(MonthDotMatrix.width, MonthDotMatrix.height),
  );
  return [for (final call in canvas.invocations) '$call'];
}

extension _PainterCopy on MonthDotMatrixPainter {
  MonthDotMatrixPainter copyWith({List<Color?>? dayColors}) {
    return MonthDotMatrixPainter(
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
      dayColors: dayColors ?? this.dayColors,
      selectedIndex: selectedIndex,
      selectedColor: selectedColor,
    );
  }
}

/// Pumps the painter alone — no `MaterialApp`, no `FittedBox` — so the only
/// `CustomPaint` in the tree is this one and its canvas is unscaled.
Future<void> pumpPainter(
  WidgetTester tester,
  MonthDotMatrixPainter painter,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: MonthDotMatrix.width,
          height: MonthDotMatrix.height,
          child: CustomPaint(painter: painter),
        ),
      ),
    ),
  );
}

void main() {
  group('MonthDotMatrixPainter.shouldRepaint', () {
    test('is false when every input is identical', () {
      final a = _painter();
      final b = _painter();

      expect(a.shouldRepaint(b), isFalse);
    });

    test('is true when daysInMonth changes', () {
      final a = _painter(daysInMonth: 30);
      final b = _painter(daysInMonth: 31);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when firstWeekdayColumn changes', () {
      final a = _painter(firstWeekdayColumn: 2);
      final b = _painter(firstWeekdayColumn: 3);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when markedMask changes', () {
      final a = _painter(markedMask: 0x5);
      final b = _painter(markedMask: 0x9);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when missedMask changes', () {
      final a = _painter(missedMask: 0x1);
      final b = _painter(missedMask: 0x4);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when windowMask changes', () {
      final a = _painter(windowMask: 0x3FFFFFFF);
      final b = _painter(windowMask: 0x1FFFFFFF);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when todayIndex changes', () {
      final a = _painter(todayIndex: 4);
      final b = _painter(todayIndex: 5);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when todayIndex changes from null to a value', () {
      final a = _painter(todayIndex: null);
      final b = _painter(todayIndex: 4);

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when markedColor changes', () {
      final a = _painter(markedColor: const Color(0xFF1E88E5));
      final b = _painter(markedColor: const Color(0xFF43A047));

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when missedColor changes', () {
      final a = _painter(missedColor: const Color(0x591E88E5));
      final b = _painter(missedColor: const Color(0x5943A047));

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when unmarkedColor changes', () {
      final a = _painter(unmarkedColor: const Color(0x40808080));
      final b = _painter(unmarkedColor: const Color(0x40909090));

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when outsideColor changes', () {
      final a = _painter(outsideColor: const Color(0x20808080));
      final b = _painter(outsideColor: const Color(0x20909090));

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when todayColor changes', () {
      final a = _painter(todayColor: const Color(0xFFFFB300));
      final b = _painter(todayColor: const Color(0xFFFF7043));

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when backgroundColor changes', () {
      final a = _painter(backgroundColor: const Color(0xFF1B1B1F));
      final b = _painter(backgroundColor: const Color(0xFFEDE7F6));

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when the per-day colours change', () {
      final a = _painter().copyWith(dayColors: const [Color(0xFFE53935)]);
      final b = _painter().copyWith(dayColors: const [Color(0xFF43A047)]);
      final c = _painter().copyWith(dayColors: const [Color(0xFFE53935)]);

      expect(a.shouldRepaint(b), isTrue);
      expect(a.shouldRepaint(c), isFalse);
      expect(a.shouldRepaint(_painter()), isTrue);
    });

    test('is true when outlineColor changes', () {
      final a = _painter(outlineColor: const Color(0xFF938F99));
      final b = _painter(outlineColor: const Color(0xFF49454F));

      expect(a.shouldRepaint(b), isTrue);
    });

    test('is true when selectedIndex changes, null to a day included', () {
      final a = _painter(selectedIndex: 3, selectedColor: _selected);

      expect(
        a.shouldRepaint(_painter(selectedIndex: 4, selectedColor: _selected)),
        isTrue,
      );
      expect(_painter(selectedColor: _selected).shouldRepaint(a), isTrue);
      expect(
        a.shouldRepaint(_painter(selectedIndex: 3, selectedColor: _selected)),
        isFalse,
      );
    });

    test('is true when selectedColor changes', () {
      final a = _painter(selectedIndex: 3, selectedColor: _selected);
      final b = _painter(selectedIndex: 3, selectedColor: _marked);

      expect(a.shouldRepaint(b), isTrue);
      expect(a.shouldRepaint(_painter(selectedIndex: 3)), isTrue);
    });
  });

  group('MonthDotMatrixPainter.paint', () {
    testWidgets('the four day states paint in four distinct colours', (
      tester,
    ) async {
      // Four consecutive days from the first column: missed-only, marked,
      // in-window-but-empty, outside the window — in that precedence order.
      await pumpPainter(
        tester,
        _painter(
          daysInMonth: 4,
          firstWeekdayColumn: 0,
          markedMask: 0x3,
          missedMask: 0x1,
          windowMask: 0x7,
          todayIndex: null,
        ),
      );

      expect(
        find.byType(CustomPaint),
        paints
          ..rrect(color: _missed)
          ..rrect(color: _marked)
          ..rrect(color: _unmarked)
          ..rrect(color: _outside),
      );
    });

    testWidgets('a missed day wins the square from the marked colour', (
      tester,
    ) async {
      await pumpPainter(
        tester,
        _painter(
          daysInMonth: 1,
          firstWeekdayColumn: 0,
          markedMask: 0x1,
          missedMask: 0x1,
          windowMask: 0x1,
          todayIndex: null,
        ),
      );

      expect(find.byType(CustomPaint), paints..rrect(color: _missed));
      expect(find.byType(CustomPaint), isNot(paints..rrect(color: _marked)));
    });

    testWidgets('per-day colours paint each marked day in its own colour', (
      tester,
    ) async {
      const red = Color(0xFFE53935);
      const green = Color(0xFF43A047);
      await pumpPainter(
        tester,
        _painter(
          daysInMonth: 3,
          firstWeekdayColumn: 0,
          markedMask: 0x7,
          missedMask: 0x4,
          windowMask: 0x7,
          todayIndex: null,
        ).copyWith(dayColors: const [red, null, green]),
      );

      // A day with its own colour paints it, a day without falls back to the
      // marked colour, and a missed day fades its own colour rather than
      // taking the shared missed one.
      expect(
        find.byType(CustomPaint),
        paints
          ..rrect(color: red)
          ..rrect(color: _marked)
          ..rrect(color: green.withValues(alpha: 0.35)),
      );
      expect(find.byType(CustomPaint), isNot(paints..rrect(color: _missed)));
    });

    testWidgets('today is ringed on top of its own fill', (tester) async {
      await pumpPainter(
        tester,
        _painter(
          daysInMonth: 2,
          firstWeekdayColumn: 0,
          markedMask: 0x1,
          missedMask: 0,
          windowMask: 0x3,
          todayIndex: 1,
        ),
      );

      expect(
        find.byType(CustomPaint),
        paints
          ..rrect(color: _marked)
          ..rrect(color: _unmarked)
          ..rrect(color: _today, style: PaintingStyle.stroke, strokeWidth: 1),
      );
    });

    testWidgets('the picked day is ringed outside its square, after today\'s '
        'ring', (tester) async {
      await pumpPainter(
        tester,
        _painter(
          daysInMonth: 2,
          firstWeekdayColumn: 0,
          markedMask: 0x1,
          missedMask: 0,
          windowMask: 0x3,
          todayIndex: 1,
          selectedIndex: 1,
          selectedColor: _selected,
        ),
      );

      // Day 2's square is 10..18 × 0..8; its ring one unit out, its corners
      // grown by the same unit.
      expect(
        find.byType(CustomPaint),
        paints
          ..rrect(color: _marked)
          ..rrect(color: _unmarked)
          ..rrect(color: _today, style: PaintingStyle.stroke, strokeWidth: 1)
          ..rrect(
            rrect: RRect.fromRectAndRadius(
              const Rect.fromLTWH(9, -1, 10, 10),
              const Radius.circular(2.5),
            ),
            color: _selected,
            style: PaintingStyle.stroke,
            strokeWidth: MonthDotMatrix.selectedRingWidth,
          ),
      );
    });

    test('with no day picked the drawing is the year tile\'s, call for '
        'call', () {
      final plain = _recorded(_painter());
      final selectedOnly = _recorded(_painter(selectedIndex: 7));
      final colourOnly = _recorded(_painter(selectedColor: _selected));
      final picked = _recorded(
        _painter(selectedIndex: 7, selectedColor: _selected),
      );

      // One fill per day and today's ring, nothing else.
      expect(plain, hasLength(31));
      expect(selectedOnly, plain);
      expect(colourOnly, plain);
      // A picked day adds its ring, and only its ring.
      expect(picked, hasLength(plain.length + 1));
      expect(picked.sublist(0, 9), plain.sublist(0, 9));
      expect(picked.sublist(10), plain.sublist(9));
      // Day 8, slot 9: its square 20..28 × 10..18, one unit out.
      expect(
        picked[9],
        contains('RRect.fromLTRBR(19.0, 9.0, 29.0, 19.0, 2.5)'),
      );
    });

    testWidgets('a marked colour too pale for the tile gains a hairline', (
      tester,
    ) async {
      // A near-white category on a near-white tile: 1.05:1, far under the
      // 1.6:1 floor `CalendarDayBars` outlines at.
      const pale = Color(0xFFF2F0F5);
      await pumpPainter(
        tester,
        _painter(
          daysInMonth: 1,
          firstWeekdayColumn: 0,
          markedMask: 0x1,
          missedMask: 0,
          windowMask: 0x1,
          todayIndex: null,
          markedColor: pale,
          backgroundColor: const Color(0xFFEDE7F6),
        ),
      );

      expect(
        find.byType(CustomPaint),
        paints
          ..rrect(color: pale)
          ..rrect(color: _outline, style: PaintingStyle.stroke, strokeWidth: 1),
      );
    });

    testWidgets('a marked colour that stands on its own gets no hairline', (
      tester,
    ) async {
      await pumpPainter(
        tester,
        _painter(
          daysInMonth: 1,
          firstWeekdayColumn: 0,
          markedMask: 0x1,
          missedMask: 0,
          windowMask: 0x1,
          todayIndex: null,
          markedColor: _marked,
          backgroundColor: const Color(0xFFEDE7F6),
        ),
      );

      expect(find.byType(CustomPaint), isNot(paints..rrect(color: _outline)));
    });

    testWidgets('a day past the sixth row is dropped rather than overflowing', (
      tester,
    ) async {
      // 31 days from column 6 needs 37 slots; the matrix has 42, so nothing is
      // dropped here — the guard is for the impossible input, and the point is
      // that it does not paint outside its box.
      await pumpPainter(
        tester,
        _painter(daysInMonth: 31, firstWeekdayColumn: 6, todayIndex: null),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('MonthDotMatrix contrast', () {
    /// The app's real palette, and the same `(hi + 0.05) / (lo + 0.05)` ratio
    /// the marker outline rule uses — so these numbers move only when someone
    /// means to move them.
    double ratioAgainstTile(Color color, ColorScheme scheme) {
      final tile = scheme.surfaceContainerHigh;
      return MarkerContrast.contrastRatio(
        Color.alphaBlend(color, tile).computeLuminance(),
        tile.computeLuminance(),
      );
    }

    ColorScheme schemeFor(Brightness brightness) =>
        brightness == Brightness.light
        ? AppTheme.lightScheme
        : AppTheme.darkScheme;

    for (final brightness in Brightness.values) {
      test('an unmarked square clears the marker floor in $brightness', () {
        final scheme = schemeFor(brightness);

        expect(
          ratioAgainstTile(
            scheme.outline.withValues(alpha: MonthDotMatrix.unmarkedAlpha),
            scheme,
          ),
          greaterThanOrEqualTo(MarkerContrast.minContrastRatio),
        );
      });

      test('an outside square stays fainter than an unmarked one '
          'in $brightness', () {
        final scheme = schemeFor(brightness);

        expect(
          ratioAgainstTile(
            scheme.outline.withValues(alpha: MonthDotMatrix.outsideAlpha),
            scheme,
          ),
          lessThan(
            ratioAgainstTile(
              scheme.outline.withValues(alpha: MonthDotMatrix.unmarkedAlpha),
              scheme,
            ),
          ),
        );
      });
    }

    test('the outside alpha is about half the unmarked one', () {
      expect(
        MonthDotMatrix.outsideAlpha / MonthDotMatrix.unmarkedAlpha,
        closeTo(0.5, 0.06),
      );
    });
  });

  group('MonthDotMatrix widget', () {
    testWidgets('renders inside a 60dp-wide box with no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 60,
                height: 60,
                child: MonthDotMatrix(
                  daysInMonth: 31,
                  firstWeekdayColumn: 5,
                  markedMask: 0x2A,
                  missedMask: 0x8,
                  windowMask: 0x7FFFFFFF,
                  todayIndex: 10,
                  markedColor: _marked,
                  missedColor: _missed,
                  unmarkedColor: _unmarked,
                  outsideColor: _outside,
                  todayColor: _today,
                  backgroundColor: _background,
                  outlineColor: _outline,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(MonthDotMatrix), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders a full 6-row month (31 days) with no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 60,
                height: 60,
                // Saturday-start with a 31-day month starting on a Saturday
                // fills every one of the 6 rows, the worst case for overflow.
                child: MonthDotMatrix(
                  daysInMonth: 31,
                  firstWeekdayColumn: 6,
                  markedMask: 0,
                  missedMask: 0,
                  windowMask: 0x7FFFFFFF,
                  todayIndex: null,
                  markedColor: _marked,
                  missedColor: _missed,
                  unmarkedColor: _unmarked,
                  outsideColor: _outside,
                  todayColor: _today,
                  backgroundColor: _background,
                  outlineColor: _outline,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('without onDayTap the matrix adds no gesture', (tester) async {
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: _matrix()),
      );

      expect(
        find.descendant(
          of: find.byType(MonthDotMatrix),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('a tap on the scaled matrix reports the day under it', (
      tester,
    ) async {
      final taps = <int>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: MonthDotMatrix.width * 4,
              height: MonthDotMatrix.height * 4,
              child: FittedBox(child: _matrix(onDayTap: taps.add)),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(MonthDotMatrix));
      expect(
        tester.getRect(find.byType(MonthDotMatrix)).size,
        const Size(MonthDotMatrix.width * 4, MonthDotMatrix.height * 4),
      );

      // The first day and the window's last.
      await tester.tapAt(origin + _centreOf(2) * 4);
      await tester.tapAt(origin + _centreOf(30) * 4);
      // Before the first day, the last day outside the window, after it.
      await tester.tapAt(origin + _centreOf(1) * 4);
      await tester.tapAt(origin + _centreOf(31) * 4);
      await tester.tapAt(origin + _centreOf(32) * 4);

      expect(taps, [0, 28]);
    });
  });

  group('MonthDotMatrix.dayAt', () {
    final matrix = _matrix();
    const pitch = MonthDotMatrix.cellSize + MonthDotMatrix.gap;

    test('the first and the last day of the window', () {
      expect(matrix.dayAt(_centreOf(2)), 0);
      expect(matrix.dayAt(_centreOf(30)), 28);
    });

    test('a square\'s tile is one pitch centred on it', () {
      // Day 1 is slot 2: its square spans 20..28, its tile 19..29.
      expect(matrix.dayAt(const Offset(2 * pitch - 1, 0)), 0);
      expect(matrix.dayAt(const Offset(2 * pitch - 1.01, 0)), isNull);
      expect(matrix.dayAt(const Offset(3 * pitch - 1.01, 4)), 0);
      // The gap between day 1 and day 2: each half goes to its square.
      expect(matrix.dayAt(const Offset(3 * pitch - 1, 4)), 1);
      // The gap between two rows.
      expect(matrix.dayAt(const Offset(24, pitch - 1.01)), 0);
      expect(matrix.dayAt(const Offset(24, pitch - 1)), 7);
    });

    test('a slot outside the month or the window is no day', () {
      // Before the first day.
      expect(matrix.dayAt(_centreOf(0)), isNull);
      expect(matrix.dayAt(_centreOf(1)), isNull);
      // Day 30, outside the window, and the slots after the month.
      expect(matrix.dayAt(_centreOf(31)), isNull);
      expect(matrix.dayAt(_centreOf(32)), isNull);
      expect(matrix.dayAt(_centreOf(41)), isNull);
      // Past the grid's edges.
      expect(matrix.dayAt(const Offset(-2, 4)), isNull);
      expect(matrix.dayAt(const Offset(MonthDotMatrix.width + 2, 4)), isNull);
      expect(matrix.dayAt(const Offset(24, MonthDotMatrix.height + 2)), isNull);
    });
  });
}
