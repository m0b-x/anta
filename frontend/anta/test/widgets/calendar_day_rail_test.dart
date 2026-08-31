import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_cell_tint.dart';
import 'package:anta/models/day_rail_mark.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/calendar_day_rail.dart';

/// The rail is the calendar's second presence channel, and the whole reason it
/// exists is that the cell wash can only ever describe **one** event on a day.
/// So the assertions that matter here are the ones about not losing marks:
/// every mark that fits is drawn, the ones that do not are still counted, and
/// a row too short for the user's cap silently narrows rather than overflowing.
void main() {
  const red = Color(0xFFD32F2F);
  const blue = Color(0xFF1976D2);
  const green = Color(0xFF388E3C);

  DayRailMark mark(
    String key,
    Color color, {
    int priority = 0,
    bool missed = false,
  }) => DayRailMark(
    key: key,
    color: color,
    priority: priority,
    missed: missed,
    semanticLabel: key,
  );

  Future<void> pump(
    WidgetTester tester, {
    required List<DayRailMark> marks,
    DayRailStyle style = DayRailStyle.line,
    int maxMarks = 3,
    double opacity = 1.0,
    double height = 44,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: CalendarDayRail.railWidth(style),
              height: height,
              child: CalendarDayRail(
                marks: marks,
                style: style,
                maxMarks: maxMarks,
                height: height,
                opacity: opacity,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Every box the rail painted, in top-to-bottom order. Both styles paint
  /// through a bare `DecoratedBox` inside a `SizedBox` rather than a
  /// `Container` — a `Container` builds a `DecoratedBox` of its own, so
  /// counting slots would double.
  List<BoxDecoration> decorations(WidgetTester tester) => [
    for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(CalendarDayRail),
        matching: find.byType(DecoratedBox),
      ),
    ))
      box.decoration as BoxDecoration,
  ];

  group('nothing to draw', () {
    testWidgets('no marks paints nothing', (tester) async {
      await pump(tester, marks: const []);
      expect(decorations(tester), isEmpty);
    });

    testWidgets('style none paints nothing even with marks', (tester) async {
      await pump(tester, style: DayRailStyle.none, marks: [mark('a', red)]);
      expect(decorations(tester), isEmpty);
    });

    testWidgets('a zero cap paints nothing', (tester) async {
      await pump(tester, maxMarks: 0, marks: [mark('a', red)]);
      expect(decorations(tester), isEmpty);
    });
  });

  for (final style in [DayRailStyle.line, DayRailStyle.dot]) {
    group(style.name, () {
      testWidgets('every mark under the cap is drawn', (tester) async {
        await pump(
          tester,
          style: style,
          marks: [mark('a', red), mark('b', blue), mark('c', green)],
        );

        final colors = [for (final d in decorations(tester)) d.color];
        expect(colors, [red, blue, green]);
      });

      testWidgets('the cap turns the last slot into a neutral overflow mark', (
        tester,
      ) async {
        await pump(
          tester,
          style: style,
          maxMarks: 3,
          marks: [
            mark('a', red),
            mark('b', blue),
            mark('c', green),
            mark('d', red),
          ],
        );

        final decos = decorations(tester);
        // Two real marks plus the affordance — never four, and never a
        // silently truncated three.
        expect(decos.length, 3);
        expect([for (final d in decos.take(2)) d.color], [red, blue]);
        // The overflow mark carries neither mark colour: it stands for "there
        // are more", not for any one of them.
        expect(decos.last.color, isNot(red));
        expect(decos.last.color, isNot(blue));
      });

      testWidgets('the overflow mark is actually painted', (tester) async {
        await pump(
          tester,
          style: style,
          maxMarks: 2,
          marks: [mark('a', red), mark('b', blue), mark('c', green)],
        );

        // A decoration is not a mark: `Center` passes loose constraints, and a
        // childless `DecoratedBox` under those collapses to `smallest`. The
        // affordance has to carry the whole "there are more here" signal, so
        // assert the box it lays out, not just the colour it would use.
        final box = tester.renderObject<RenderBox>(
          find
              .descendant(
                of: find.byType(CalendarDayRail),
                matching: find.byType(DecoratedBox),
              )
              .last,
        );
        expect(box.size.width, greaterThan(0));
        expect(box.size.height, greaterThan(0));
      });

      testWidgets('a cap of one keeps the top mark, not a blank affordance', (
        tester,
      ) async {
        await pump(
          tester,
          style: style,
          maxMarks: 1,
          marks: [mark('a', red), mark('b', blue)],
        );

        // The strip's "+N" chip can stand alone because it draws a number;
        // the rail's affordance draws nothing, so alone it would say less
        // than the mark it displaced. The count survives in the label.
        final decos = decorations(tester);
        expect(decos.length, 1);
        expect(decos.single.color, red);
      });

      testWidgets('a missed mark is faded, never dropped', (tester) async {
        await pump(
          tester,
          style: style,
          marks: [mark('a', red, missed: true), mark('b', blue)],
        );

        final decos = decorations(tester);
        expect(decos.length, 2);
        // `hidden` filtering happens in the provider, before a mark ever
        // reaches the widget; the widget's only job is to distinguish.
        if (style == DayRailStyle.dot) {
          // Hollow *instead of* faded: a 1px ring is already a fifth of a
          // filled disc's ink, and the two cues multiply on outside days.
          expect(decos.first.color, isNull);
          expect(decos.first.border!.top.color.a, 1.0);
        } else {
          expect(
            decos.first.color!.a,
            closeTo(CalendarColors.missedEventAlpha, 0.01),
          );
        }
        expect(decos[1].color!.a, 1.0);
      });
    });
  }

  testWidgets('a missed dot is hollow rather than faded', (tester) async {
    await pump(
      tester,
      style: DayRailStyle.dot,
      marks: [mark('a', red, missed: true)],
    );

    final deco = decorations(tester).single;
    // The one style with room for a non-colour cue. A fill would make
    // "missed" readable only by comparing two alphas side by side.
    expect(deco.color, isNull);
    expect(deco.border, isNotNull);
    expect(deco.border!.top.width, 1);
  });

  testWidgets('a missed dot on an outside day does not double-fade', (
    tester,
  ) async {
    await pump(
      tester,
      style: DayRailStyle.dot,
      opacity: CalendarDayCell.outsideAlpha,
      marks: [mark('a', red, missed: true), mark('b', blue)],
    );

    // The bug this pins: hollow *and* faded compounded to 0.35 x 0.35 = 0.12
    // alpha on a hairline, so a missed commitment on an adjacent-month day
    // vanished while the kept one beside it stayed legible. The ring now
    // carries the same weight as its neighbour's fill; hollowness is the cue.
    final decos = decorations(tester);
    expect(
      decos.first.border!.top.color.a,
      closeTo(CalendarDayCell.outsideAlpha, 0.01),
    );
    expect(decos[1].color!.a, closeTo(CalendarDayCell.outsideAlpha, 0.01));
  });

  testWidgets('a missed line segment stays filled', (tester) async {
    await pump(
      tester,
      style: DayRailStyle.line,
      marks: [mark('a', red, missed: true)],
    );

    // 3px is too narrow to read as an outline; the fade is the whole signal.
    expect(decorations(tester).single.color, isNotNull);
  });

  group('height clamping', () {
    testWidgets('a short row narrows below the user cap', (tester) async {
      // Five 5px dots with 3px gaps need 37px; 20px fits two.
      await pump(
        tester,
        style: DayRailStyle.dot,
        maxMarks: 5,
        height: 20,
        marks: [
          mark('a', red),
          mark('b', blue),
          mark('c', green),
          mark('d', red),
          mark('e', blue),
        ],
      );

      final decos = decorations(tester);
      expect(decos.length, 2);
      // The row shrank, so what did not fit became the overflow affordance
      // rather than vanishing.
      expect(decos.first.color, red);
      expect(decos.last.color, isNot(blue));
    });

    testWidgets('the default row fits the full cap of five', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.dot,
        maxMarks: 5,
        marks: [
          mark('a', red),
          mark('b', blue),
          mark('c', green),
          mark('d', red),
          mark('e', blue),
        ],
      );

      expect(decorations(tester).length, 5);
    });

    testWidgets('line segments divide the rail height evenly', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        maxMarks: 3,
        height: 44,
        marks: [mark('a', red), mark('b', blue), mark('c', green)],
      );

      final boxes = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(CalendarDayRail),
              matching: find.byType(SizedBox),
            ),
          )
          .where((b) => b.height != null && b.height != CalendarDayRail.lineGap)
          .toList();
      // (44 - 2 gaps of 2) / 3.
      expect(boxes.length, 3);
      for (final box in boxes) {
        expect(box.height, closeTo(40 / 3, 0.001));
      }
    });
  });

  testWidgets('opacity multiplies rather than replaces the mark alpha', (
    tester,
  ) async {
    const half = Color(0x80D32F2F);
    await pump(
      tester,
      opacity: CalendarDayCell.outsideAlpha,
      marks: [mark('a', half)],
    );

    // An `Opacity` wrapper would allocate an offscreen layer per outside day;
    // the fade is a colour change, and a colour that already carries alpha
    // must keep its relative weight.
    expect(
      decorations(tester).single.color!.a,
      closeTo(half.a * CalendarDayCell.outsideAlpha, 0.01),
    );
    expect(
      find.descendant(
        of: find.byType(CalendarDayRail),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });

  group('inside the day cell', () {
    CalendarDayCell cell({
      List<DayRailMark> marks = const [],
      DayRailStyle style = DayRailStyle.line,
      bool isOutside = false,
      bool isToday = false,
      DayCellTint tint = DayCellTint.empty,
    }) => CalendarDayCell(
      day: DateTime.utc(2026, 8, 30),
      isToday: isToday,
      isSelected: false,
      isOutside: isOutside,
      isWeekend: false,
      // `filled` is the opaque-circle case — the only one a rail lane can
      // actually collide with.
      todayStyle: CalendarTodayStyle.filled,
      highlightWeekends: false,
      accent: const Color(0xFF1A73E8),
      tint: tint,
      railMarks: marks,
      railStyle: style,
    );

    Future<void> pumpCell(WidgetTester tester, CalendarDayCell child) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox.square(dimension: 52, child: child)),
          ),
        ),
      );
    }

    testWidgets('an untinted cell with no marks stays a bare Align', (
      tester,
    ) async {
      await pumpCell(tester, cell());
      // The cheapest shape the cell has ever had; the rail must not cost it.
      expect(
        find.descendant(
          of: find.byType(CalendarDayCell),
          matching: find.byType(Stack),
        ),
        findsNothing,
      );
      expect(find.byType(CalendarDayRail), findsNothing);
    });

    testWidgets('style none never builds the rail', (tester) async {
      await pumpCell(
        tester,
        cell(marks: [mark('a', red)], style: DayRailStyle.none),
      );
      expect(find.byType(CalendarDayRail), findsNothing);
    });

    testWidgets('the rail sits clear of the tint edge stripe', (tester) async {
      await pumpCell(
        tester,
        cell(
          marks: [mark('a', red)],
          tint: const DayCellTint(wash: Color(0x33FF5722), edge: green),
        ),
      );

      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final railRect = tester.getRect(find.byType(CalendarDayRail));
      // The stripe is `left: 0, width: 3` inside the tinted container's 1.5px
      // margin, so it ends at 4.5. Both lanes are at a fixed x — a rail that
      // slid when the stripe is absent would shift under the user monthly.
      expect(railRect.left - cellRect.left, CalendarDayCell.railLeft);
      expect(CalendarDayCell.railLeft, greaterThanOrEqualTo(4.5));
    });

    testWidgets('the lane does not move when the stripe is absent', (
      tester,
    ) async {
      await pumpCell(tester, cell(marks: [mark('a', red)]));

      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final railRect = tester.getRect(find.byType(CalendarDayRail));
      expect(railRect.left - cellRect.left, CalendarDayCell.railLeft);
    });

    // The roadmap's gutter budget ("the chip is 34px, centred; at ~48px each
    // side has 7px clear, so 3+1+3 fits") is only true of the chip's bounding
    // box, and only if the tint stripe ends at 3. It ends at 4.5, and the chip
    // is a *circle* whose leftmost point sits exactly on that bounding box.
    // These pin what is actually true at real device widths so the wrong
    // arithmetic cannot be re-derived from the design record.
    for (final style in [DayRailStyle.line, DayRailStyle.dot]) {
      testWidgets('360dp: the ${style.name} lane clears the day chip', (
        tester,
      ) async {
        const cellWidth = 51.43;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: cellWidth,
                  height: 62,
                  // A filled chip is the only one that paints an opaque
                  // circle, so it is the only one the lane can collide with.
                  child: cell(
                    marks: [mark('a', red)],
                    style: style,
                    isToday: true,
                  ),
                ),
              ),
            ),
          ),
        );

        final railRect = tester.getRect(find.byType(CalendarDayRail));
        final chipRect = tester.getRect(
          find.descendant(
            of: find.byType(CalendarDayCell),
            matching: find.byType(Container),
          ),
        );
        // Measured, not derived: the chip shrinks to `railChipSize` whenever
        // the rail is on, which is what buys the clearance. At the full 34px
        // its box would start at 8.71 and the dot lane runs to 10.
        expect(railRect.right, lessThanOrEqualTo(chipRect.left));
        expect(chipRect.width, CalendarDayCell.railChipSize);
      });
    }

    testWidgets('320dp keeps the chip legible and lets the lane overlap', (
      tester,
    ) async {
      // The documented degradation. Below ~340dp the gutter does not exist:
      // clearing a 5px dot lane would need a chip around 26px, and a 26px
      // circle around a two-digit number is not a day chip any more. One or
      // two cells per screen draw a filled chip, so the overlap loses less
      // than the shrink would.
      const cellWidth = 45.71;
      final chipLeft = (cellWidth - CalendarDayCell.railChipSize) / 2;
      final dotRight =
          CalendarDayCell.railLeft +
          CalendarDayRail.railWidth(DayRailStyle.dot);
      expect(dotRight, greaterThan(chipLeft));
    });

    testWidgets('the chip is full size again with the rail off', (
      tester,
    ) async {
      await pumpCell(tester, cell(style: DayRailStyle.none, isToday: true));

      final chipRect = tester.getRect(
        find.descendant(
          of: find.byType(CalendarDayCell),
          matching: find.byType(Container),
        ),
      );
      expect(chipRect.width, CalendarDayCell.chipSize);
    });

    testWidgets('the day number does not move when the chip shrinks', (
      tester,
    ) async {
      Future<Rect> numberRect(DayRailStyle style) async {
        await pumpCell(
          tester,
          cell(marks: [mark('a', red)], style: style, isToday: true),
        );
        return tester.getRect(find.text('30'));
      }

      // The chip is re-centred inside the zone the full-size one occupied, so
      // turning the rail on shrinks the circle without shifting the digit —
      // the thing the whole grid and its weekday header align to.
      final withRail = await numberRect(DayRailStyle.line);
      final withoutRail = await numberRect(DayRailStyle.none);
      expect(withRail.center.dy, closeTo(withoutRail.center.dy, 0.01));
      expect(withRail.center.dx, closeTo(withoutRail.center.dx, 0.01));
    });

    testWidgets('the rail stops above the bottom marker strip', (tester) async {
      // The strip is not part of this cell — table_calendar builds it in
      // `markerBuilder`, a sibling subtree painted *after* the cell — and it
      // insets only `CalendarDayBars.horizontalInset` (6) from the cell edge,
      // which is inside the rail's lane. Without the reservation the strip
      // paints over 2 of the line lane's 3px (4 of the dot lane's 5).
      const strip = 16.0; // three bars: 3*3 + 2*1.5 + 4
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 51.43,
                height: 62,
                child: CalendarDayCell(
                  day: DateTime.utc(2026, 8, 30),
                  isToday: false,
                  isSelected: false,
                  isOutside: false,
                  isWeekend: false,
                  todayStyle: CalendarTodayStyle.tonal,
                  highlightWeekends: false,
                  accent: const Color(0xFF1A73E8),
                  railMarks: [mark('a', red)],
                  railStyle: DayRailStyle.line,
                  railHeight: 62 - 8 - strip,
                ),
              ),
            ),
          ),
        ),
      );

      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final railRect = tester.getRect(find.byType(CalendarDayRail));
      expect(cellRect.bottom - railRect.bottom, 4 + strip);
      // And the lane really is inside the strip's horizontal span, which is
      // why the reservation is needed at all rather than being belt-and-braces.
      expect(
        CalendarDayCell.railLeft + CalendarDayRail.lineWidth,
        greaterThan(CalendarDayBars.defaultHorizontalInset),
      );
    });

    testWidgets('an outside day fades its rail by the cell alpha', (
      tester,
    ) async {
      await pumpCell(tester, cell(marks: [mark('a', red)], isOutside: true));

      final rail = tester.widget<CalendarDayRail>(find.byType(CalendarDayRail));
      expect(rail.opacity, CalendarDayCell.outsideAlpha);
    });
  });
}
