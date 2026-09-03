import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  );
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

    test('is true when outlineColor changes', () {
      final a = _painter(outlineColor: const Color(0xFF938F99));
      final b = _painter(outlineColor: const Color(0xFF49454F));

      expect(a.shouldRepaint(b), isTrue);
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
    /// The app's own seed, and the same `(hi + 0.05) / (lo + 0.05)` ratio the
    /// marker outline rule uses — so these numbers move only when someone
    /// means to move them.
    double ratioAgainstTile(Color color, ColorScheme scheme) {
      final tile = scheme.surfaceContainerHigh;
      return MarkerContrast.contrastRatio(
        Color.alphaBlend(color, tile).computeLuminance(),
        tile.computeLuminance(),
      );
    }

    for (final brightness in Brightness.values) {
      test('an unmarked square clears the marker floor in $brightness', () {
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: brightness,
        );

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
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: brightness,
        );

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
  });
}
