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
    Color? baseColor,
    DayRailBasePosition basePosition = DayRailBasePosition.bottom,
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
                baseColor: baseColor,
                basePosition: basePosition,
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
  ///
  /// Foreground decorations are excluded: those are the lane-wide contrast
  /// outline, which is chrome over the bands rather than a band of its own.
  List<BoxDecoration> decorations(WidgetTester tester) => [
    for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(CalendarDayRail),
        matching: find.byType(DecoratedBox),
      ),
    ))
      if (box.position == DecorationPosition.background)
        box.decoration as BoxDecoration,
  ];

  /// The `line` style's bands, top to bottom. Every `SizedBox` under a line
  /// rail is a band now — there are no gap spacers left to filter out, which
  /// is itself the invariant the "one unbroken line" group pins.
  List<SizedBox> bands(WidgetTester tester) => tester
      .widgetList<SizedBox>(
        find.descendant(
          of: find.byType(CalendarDayRail),
          matching: find.byType(SizedBox),
        ),
      )
      .where((b) => b.height != null)
      .toList();

  List<Rect> bandRects(WidgetTester tester) {
    final finder = find.descendant(
      of: find.byType(CalendarDayRail),
      matching: find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.position == DecorationPosition.background,
      ),
    );
    return [
      for (var i = 0; i < finder.evaluate().length; i++)
        tester.getRect(finder.at(i)),
    ];
  }

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

    testWidgets('line bands divide the rail height evenly', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        maxMarks: 3,
        height: 44,
        marks: [mark('a', red), mark('b', blue), mark('c', green)],
      );

      final boxes = bands(tester);
      // No gaps any more: the whole 44 is divided three ways.
      expect(boxes.length, 3);
      for (final box in boxes) {
        expect(box.height, closeTo(44 / 3, 0.001));
      }
    });
  });

  group('one unbroken line', () {
    testWidgets('the bands touch — no gap widget between them', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue), mark('c', green)],
        height: 44,
      );

      // The whole point of the 2026-09-01 rework: the rail is one bar whose
      // colour changes, not three slivers with holes punched between them. If
      // a gap ever comes back it shows up here as a shortfall.
      final total = bands(tester).fold<double>(0, (sum, b) => sum + b.height!);
      expect(total, closeTo(44, 0.001));

      final rects = bandRects(tester);
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, closeTo(rects[i - 1].bottom, 0.001));
      }
    });

    testWidgets('only the lane\'s two outer ends are rounded', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue), mark('c', green)],
      );

      // Rounding every band would draw waists at each boundary and undo the
      // single-bar reading. The radii live on the end bands rather than on a
      // `ClipRRect`, which would cost a clip layer on a 42-cell path.
      final radii = [
        for (final d in decorations(tester)) d.borderRadius as BorderRadius,
      ];
      const round = Radius.circular(CalendarDayRail.lineWidth / 2);
      expect(radii.first.topLeft, round);
      expect(radii.first.bottomLeft, Radius.zero);
      expect(radii[1].topLeft, Radius.zero);
      expect(radii[1].bottomLeft, Radius.zero);
      expect(radii.last.topLeft, Radius.zero);
      expect(radii.last.bottomLeft, round);
    });

    testWidgets('a single band is rounded at both ends', (tester) async {
      await pump(tester, style: DayRailStyle.line, marks: [mark('a', red)]);

      final radius = decorations(tester).single.borderRadius as BorderRadius;
      const round = Radius.circular(CalendarDayRail.lineWidth / 2);
      expect(radius.topLeft, round);
      expect(radius.bottomLeft, round);
    });

    testWidgets('a low-contrast band outlines the lane, not itself', (
      tester,
    ) async {
      // A per-band border would paint a horizontal hairline at every boundary
      // — the separated look the single bar exists to avoid — so the outline
      // is one foreground decoration over the whole lane.
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', const Color(0xFFFFFDF5)), mark('b', blue)],
      );

      for (final d in decorations(tester)) {
        expect(d.border, isNull);
      }
      final outlines = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(CalendarDayRail),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((b) => b.position == DecorationPosition.foreground)
          .toList();
      expect(outlines, hasLength(1));
      expect((outlines.single.decoration as BoxDecoration).border, isNotNull);
    });
  });

  group('the fasting band shares the lane', () {
    testWidgets('it sits at the bottom, below every mark', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        height: 44,
        marks: [mark('a', red), mark('b', blue)],
        baseColor: green,
      );

      final colors = [for (final d in decorations(tester)) d.color];
      // A fast is the condition the day sits on; the commitments stack on top
      // of it, in priority order, exactly as they do without one.
      expect(colors, [red, blue, green]);
      expect(bands(tester).last.height, CalendarDayRail.baseBandFor(44));
    });

    testWidgets('it never displaces a mark', (tester) async {
      List<Color?> colorsWith({Color? base}) => [
        for (final d in decorations(tester)) d.color,
      ];

      await pump(
        tester,
        style: DayRailStyle.line,
        maxMarks: 3,
        height: 44,
        marks: [mark('a', red), mark('b', blue), mark('c', green)],
      );
      final without = colorsWith();

      await pump(
        tester,
        style: DayRailStyle.line,
        maxMarks: 3,
        height: 44,
        marks: [mark('a', red), mark('b', blue), mark('c', green)],
        baseColor: const Color(0xFF6A1B9A),
      );
      final withBase = colorsWith();

      // Fixed band, not a slot: the cap describes commitments, and a fasting
      // day must not quietly show one fewer of them.
      expect(withBase.length, without.length + 1);
      expect(withBase.take(3), without);
    });

    testWidgets('with no marks it is the whole lane', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: const [],
        height: 44,
        baseColor: green,
      );

      // Pixel-identical to the stripe the cell used to draw on its own, so
      // turning the rail on cannot change how a plain fasting day looks.
      final band = bands(tester).single;
      expect(band.height, 44);
      expect(decorations(tester).single.color, green);
    });

    testWidgets('it stays flush against the mark above it', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red)],
        baseColor: green,
        height: 44,
      );

      final rects = bandRects(tester);
      expect(rects, hasLength(2));
      expect(rects[1].top, closeTo(rects[0].bottom, 0.001));
    });

    testWidgets('marks and fasting split the lane evenly', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red)],
        baseColor: green,
        height: 44,
      );

      // Two questions — "is this a fasting day" and "what is on it" — and
      // neither is a sub-answer of the other, so neither gets the smaller
      // half. Hierarchy is carried by alpha instead: the band paints at
      // `cellEdgeAlpha` against marks at full alpha.
      final boxes = bands(tester);
      expect(boxes, hasLength(2));
      expect(boxes[0].height, closeTo(22, 0.001));
      expect(boxes[1].height, closeTo(22, 0.001));
    });

    testWidgets('the marks subdivide their own half, not the lane', (
      tester,
    ) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue), mark('c', green)],
        baseColor: const Color(0xFF6A1B9A),
        height: 48,
      );

      final boxes = bands(tester);
      expect(boxes, hasLength(4));
      for (final box in boxes.take(3)) {
        expect(box.height, closeTo(8, 0.001));
      }
      expect(boxes.last.height, closeTo(24, 0.001));
    });

    testWidgets('a short lane still splits evenly', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red)],
        baseColor: green,
        height: 18,
      );

      // Proportional, so there is no height at which the band stops being
      // half — the old fixed 12px band had to be clamped and stopped being
      // predictable on short rows.
      expect(bands(tester).last.height, closeTo(9, 0.001));
    });

    testWidgets('capacity counts against the marks half, not the lane', (
      tester,
    ) async {
      // 20px lane, half of it for marks = 10px, and `minLineSegment` is 3 —
      // three slots, so the fourth mark becomes the overflow band. Counting
      // against the full 20 would have promised six.
      await pump(
        tester,
        style: DayRailStyle.line,
        maxMarks: 5,
        height: 20,
        baseColor: green,
        marks: [
          mark('a', red),
          mark('b', blue),
          mark('c', green),
          mark('d', red),
          mark('e', blue),
        ],
      );

      final colors = [for (final d in decorations(tester)) d.color];
      expect(colors, hasLength(4));
      expect(colors.take(2), [red, blue]);
      expect(colors[2], isNot(green));
      expect(colors.last, green);
    });

    testWidgets('top position puts the band above the marks', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue)],
        baseColor: green,
        basePosition: DayRailBasePosition.top,
        height: 44,
      );

      final colors = [for (final d in decorations(tester)) d.color];
      expect(colors, [green, red, blue]);
      // The split moves; the shares do not.
      final boxes = bands(tester);
      expect(boxes.first.height, closeTo(22, 0.001));
      expect(boxes[1].height, closeTo(11, 0.001));
      expect(boxes[2].height, closeTo(11, 0.001));
    });

    testWidgets('the marks keep their priority order at either end', (
      tester,
    ) async {
      List<Color?> orderFor(DayRailBasePosition position) => [
        for (final d in decorations(tester)) d.color,
      ];

      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue)],
        baseColor: green,
        basePosition: DayRailBasePosition.bottom,
        height: 44,
      );
      expect(orderFor(DayRailBasePosition.bottom), [red, blue, green]);

      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue)],
        baseColor: green,
        basePosition: DayRailBasePosition.top,
        height: 44,
      );
      // Only the split moves — never the ranking. Reversing the marks with
      // the band would make the rail's top mark mean two different events
      // depending on a purely visual setting.
      expect(orderFor(DayRailBasePosition.top), [green, red, blue]);
    });

    testWidgets('the lane stays one bar with the band on top', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue)],
        baseColor: green,
        basePosition: DayRailBasePosition.top,
        height: 44,
      );

      final rects = bandRects(tester);
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, closeTo(rects[i - 1].bottom, 0.001));
      }
      final radii = [
        for (final d in decorations(tester)) d.borderRadius as BorderRadius,
      ];
      const round = Radius.circular(CalendarDayRail.lineWidth / 2);
      expect(radii.first.topLeft, round);
      expect(radii.first.bottomLeft, Radius.zero);
      expect(radii.last.bottomLeft, round);
    });

    testWidgets('position is inert without a band', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red), mark('b', blue)],
        basePosition: DayRailBasePosition.top,
        height: 44,
      );

      // Nothing to place, so the marks take the whole lane exactly as they do
      // under `bottom` — the setting must never cost a day without a fast.
      final boxes = bands(tester);
      expect(boxes, hasLength(2));
      expect(boxes[0].height, closeTo(22, 0.001));
    });

    testWidgets('the dot style ignores it — that lane is not the stripe\'s', (
      tester,
    ) async {
      await pump(
        tester,
        style: DayRailStyle.dot,
        marks: [mark('a', red)],
        baseColor: green,
      );

      // Dots keep their own inset lane, so the cell goes on drawing the
      // stripe itself; a band here would paint the fasting colour in the
      // wrong place.
      expect([for (final d in decorations(tester)) d.color], [red]);
    });

    testWidgets('an outside day fades the band exactly once', (tester) async {
      await pump(
        tester,
        style: DayRailStyle.line,
        marks: [mark('a', red)],
        baseColor: green,
        opacity: CalendarDayCell.outsideAlpha,
      );

      // The cell hands the rail the *unfaded* edge colour precisely so the
      // lane fades once. Fading it in the cell as well compounded to 0.12.
      expect(
        decorations(tester).last.color!.a,
        closeTo(CalendarDayCell.outsideAlpha, 0.01),
      );
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
      railHeight: CalendarDayCell.defaultRailHeight,
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

    testWidgets('the line rail takes over the tint edge stripe\'s lane', (
      tester,
    ) async {
      await pumpCell(
        tester,
        cell(
          marks: [mark('a', red)],
          tint: const DayCellTint(wash: Color(0x33FF5722), edge: green),
        ),
      );

      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final railRect = tester.getRect(find.byType(CalendarDayRail));
      // The stripe was `left: 0, width: 3` inside the tinted container's 1.5px
      // margin. The rail is positioned in *cell* coordinates by the outer
      // Stack, so those numbers have to be restated here — and they have to
      // match, or the lane splits in two the moment a fasting day also carries
      // marks.
      expect(railRect.left - cellRect.left, CalendarDayCell.edgeLaneLeft);
      expect(railRect.width, CalendarDayCell.edgeLaneWidth);
      expect(railRect.top - cellRect.top, CalendarDayCell.edgeLaneInset);
    });

    testWidgets('the cell draws no second stripe behind the line rail', (
      tester,
    ) async {
      await pumpCell(
        tester,
        cell(
          marks: [mark('a', red)],
          tint: const DayCellTint(wash: Color(0x33FF5722), edge: green),
        ),
      );

      // The fasting colour is the rail's base band and nothing else. Leaving
      // the old `Positioned` stripe in place too would paint it twice, at
      // full height, straight through the marks.
      final greens = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((b) {
            final decoration = b.decoration;
            return decoration is BoxDecoration && decoration.color == green;
          });
      expect(greens, hasLength(1));
      expect(
        find.descendant(
          of: find.byType(CalendarDayRail),
          matching: find.byType(DecoratedBox),
        ),
        findsWidgets,
      );
    });

    testWidgets('the dot rail keeps its own lane beside the stripe', (
      tester,
    ) async {
      await pumpCell(
        tester,
        cell(
          marks: [mark('a', red)],
          style: DayRailStyle.dot,
          tint: const DayCellTint(wash: Color(0x33FF5722), edge: green),
        ),
      );

      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final railRect = tester.getRect(find.byType(CalendarDayRail));
      // Dots cannot fit a 3px lane, so that style is unchanged: inset lane,
      // and the cell still draws the stripe itself at 1.5..4.5.
      expect(railRect.left - cellRect.left, CalendarDayCell.railLeft);
      expect(CalendarDayCell.railLeft, greaterThanOrEqualTo(4.5));
      expect(
        tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where((b) {
              final decoration = b.decoration;
              return decoration is BoxDecoration && decoration.color == green;
            }),
        hasLength(1),
      );
    });

    testWidgets('the lane does not move when the stripe is absent', (
      tester,
    ) async {
      await pumpCell(tester, cell(marks: [mark('a', red)]));

      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final railRect = tester.getRect(find.byType(CalendarDayRail));
      expect(railRect.left - cellRect.left, CalendarDayCell.edgeLaneLeft);
    });

    testWidgets('a fasting day with no marks still draws the lane', (
      tester,
    ) async {
      await pumpCell(
        tester,
        cell(tint: const DayCellTint(wash: Color(0x33FF5722), edge: green)),
      );

      // The rail widget now owns the stripe outright in `line` style, so it
      // has to render for a day that has no marks at all — otherwise turning
      // the rail on would delete the fasting cue from most of the month.
      expect(find.byType(CalendarDayRail), findsOneWidget);
      final rail = tester.widget<CalendarDayRail>(find.byType(CalendarDayRail));
      expect(rail.baseColor, green);
      expect(rail.marks, isEmpty);
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
        // Measured, not derived. `dot` still buys its clearance by shrinking
        // the chip to `railChipSize`: at the full 34px the chip's box starts
        // at 8.71 and the dot lane runs to 10. `line` no longer pays that —
        // its lane ends at 4.5, clear of a full-size chip.
        expect(railRect.right, lessThanOrEqualTo(chipRect.left));
        expect(
          chipRect.width,
          style == DayRailStyle.dot
              ? CalendarDayCell.railChipSize
              : CalendarDayCell.chipSize,
        );
      });
    }

    testWidgets('320dp: the line lane still clears a full-size chip', (
      tester,
    ) async {
      // The width at which the inset lane's gutter stops existing. The edge
      // lane has no such floor, which is the point of moving `line` into it:
      // 1.5 + 3 = 4.5 against a chip starting at 5.86.
      const cellWidth = 45.71;
      final lineRight =
          CalendarDayCell.edgeLaneLeft + CalendarDayCell.edgeLaneWidth;
      expect(lineRight, lessThan((cellWidth - CalendarDayCell.chipSize) / 2));
    });

    testWidgets('320dp keeps the dot chip legible and lets the lane overlap', (
      tester,
    ) async {
      // The documented degradation, now `dot`-only. Below ~340dp the inset
      // gutter does not exist: clearing a 5px dot lane would need a chip
      // around 26px, and a 26px circle around a two-digit number is not a day
      // chip any more. One or two cells per screen draw a filled chip, so the
      // overlap loses less than the shrink would.
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
      // turning the dot rail on shrinks the circle without shifting the digit
      // — the thing the whole grid and its weekday header align to.
      final withRail = await numberRect(DayRailStyle.dot);
      final withoutRail = await numberRect(DayRailStyle.none);
      expect(withRail.center.dy, closeTo(withoutRail.center.dy, 0.01));
      expect(withRail.center.dx, closeTo(withoutRail.center.dx, 0.01));
    });

    testWidgets('the line chip is full size, rail on or off', (tester) async {
      Future<double> chipWidth(DayRailStyle style) async {
        await pumpCell(
          tester,
          cell(marks: [mark('a', red)], style: style, isToday: true),
        );
        return tester
            .getRect(
              find.descendant(
                of: find.byType(CalendarDayCell),
                matching: find.byType(Container),
              ),
            )
            .width;
      }

      // The whole reason `line` moved to the edge lane: the rail's default
      // style stops costing the day number 4px on every cell of the grid.
      expect(await chipWidth(DayRailStyle.line), CalendarDayCell.chipSize);
      expect(await chipWidth(DayRailStyle.none), CalendarDayCell.chipSize);
    });

    testWidgets('the dot rail stops above the bottom marker strip', (
      tester,
    ) async {
      // The strip is not part of this cell — table_calendar builds it in
      // `markerBuilder`, a sibling subtree painted *after* the cell — and it
      // insets only `CalendarDayBars.horizontalInset` (6) from the cell edge,
      // which is inside the *inset* lane. Without the reservation the strip
      // paints over 4 of the dot lane's 5px.
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
                  railStyle: DayRailStyle.dot,
                  railHeight: CalendarDayCell.railLaneHeight(
                    rowHeight: 62,
                    stripHeight: strip,
                    railStyle: DayRailStyle.dot,
                  ),
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
        CalendarDayCell.railLeft + CalendarDayRail.railWidth(DayRailStyle.dot),
        greaterThan(CalendarDayBars.defaultHorizontalInset),
      );
    });

    testWidgets('the line rail runs the full row — the strip never reaches it', (
      tester,
    ) async {
      const strip = 16.0;
      final laneHeight = CalendarDayCell.railLaneHeight(
        rowHeight: 62,
        stripHeight: strip,
        railStyle: DayRailStyle.line,
      );
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
                  railHeight: laneHeight,
                ),
              ),
            ),
          ),
        ),
      );

      // The edge lane ends at 4.5 and the strip starts at 6, so the line rail
      // owes the strip no vertical clearance and gets the row's whole height
      // — 51px against the inset lane's 38, which is why it can afford the
      // fasting band without losing a mark slot.
      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final railRect = tester.getRect(find.byType(CalendarDayRail));
      expect(laneHeight, 62 - CalendarDayCell.edgeLaneInset * 2);
      expect(cellRect.bottom - railRect.bottom, CalendarDayCell.edgeLaneInset);
      expect(
        CalendarDayCell.edgeLaneLeft + CalendarDayCell.edgeLaneWidth,
        lessThanOrEqualTo(CalendarDayBars.defaultHorizontalInset),
      );
    });

    testWidgets('marks without a height are a loud caller bug', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 52,
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
                  // railHeight deliberately omitted.
                ),
              ),
            ),
          ),
        ),
      );

      // The rail sizes itself from the number it is given rather than
      // measuring its box, so a missing height is not a crash — it is a
      // silently wrong mark count. The assert is what keeps that from
      // shipping now that the `LayoutBuilder` no longer self-corrects.
      expect(tester.takeException(), isAssertionError);
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
