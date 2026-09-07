import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_cell_tint.dart';
import 'package:anta/widgets/calendar_day_cell.dart';

/// `CalendarCellStyle` is a **paint-side** setting: the wash colour and its
/// priority alpha still arrive fully resolved from `CellTintResolver`, and the
/// cell only restates them in a different shape using style-wide constants —
/// the same class of operation `_fade` already performs for adjacent-month
/// days.
///
/// Three things could silently break and none of them would fail anywhere
/// else: `solid` drifting away from the look that shipped (it is the default
/// in both themes, so a drift repaints every existing install), `fade` scaling
/// the wash instead of using it as the gradient's peak (which would move the
/// priority ramp into the painter), and `outline`'s two derived alphas
/// inverting so the border stops being the stronger of the pair — at which
/// point the style has no way left to show priority at all.
void main() {
  // Alpha 0.28 and 0.55: the P1 wash and the runner-up edge, so the numbers
  // below are the ones the grid actually paints.
  const wash = Color(0x47FF5722);
  const edge = Color(0x8C4CAF50);
  const accent = Color(0xFF1A73E8);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(
        // A 360dp phone's cell, to the fraction.
        child: SizedBox(width: 51.43, height: 62, child: child),
      ),
    ),
  );

  CalendarDayCell cell({
    CalendarCellStyle? style,
    DayCellTint tint = const DayCellTint(wash: wash),
    bool isOutside = false,
  }) => CalendarDayCell(
    day: DateTime.utc(2026, 8, 10),
    isToday: false,
    isSelected: false,
    isOutside: isOutside,
    isWeekend: false,
    todayStyle: CalendarTodayStyle.tonal,
    highlightWeekends: false,
    accent: accent,
    tint: tint,
    // Omitted entirely in the "default" cases, so they exercise the
    // constructor default rather than a value the test chose.
    cellStyle: style ?? CalendarCellStyle.solid,
  );

  /// The tinted container, found by its decoration rather than by position:
  /// it is the only `BoxDecoration` in the cell carrying a `borderRadius`
  /// (the day-number chip is a `BoxShape.circle`, and the runner-up stripe
  /// rounds to 2, not 10).
  BoxDecoration tintDecoration(WidgetTester tester) {
    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.borderRadius == BorderRadius.circular(10))
        .toList();
    expect(decorations, hasLength(1));
    return decorations.single;
  }

  /// `outline`'s border, which rides `foregroundDecoration` so that it paints
  /// over the child instead of insetting it. `null` for every other style.
  BoxDecoration? tintForeground(WidgetTester tester) {
    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.foregroundDecoration)
        .whereType<BoxDecoration>()
        .toList();
    expect(decorations.length, lessThanOrEqualTo(1));
    return decorations.isEmpty ? null : decorations.single;
  }

  group('each style paints the shape it promises', () {
    testWidgets('solid fills with a flat colour and nothing else', (
      tester,
    ) async {
      await tester.pumpWidget(host(cell(style: CalendarCellStyle.solid)));

      final decoration = tintDecoration(tester);
      expect(decoration.color, wash);
      expect(decoration.gradient, isNull);
      expect(decoration.border, isNull);
    });

    testWidgets('solid is exactly what the cell paints by default', (
      tester,
    ) async {
      // The default in both themes, so this branch has to stay a literal
      // no-op against the behaviour that shipped before the setting existed.
      await tester.pumpWidget(host(cell()));
      final byDefault = tintDecoration(tester);

      await tester.pumpWidget(host(cell(style: CalendarCellStyle.solid)));

      expect(tintDecoration(tester), byDefault);
    });

    testWidgets('fade paints a gradient and no flat colour', (tester) async {
      await tester.pumpWidget(host(cell(style: CalendarCellStyle.fade)));

      final decoration = tintDecoration(tester);
      expect(decoration.color, isNull);
      expect(decoration.gradient, isNotNull);
      expect(decoration.border, isNull);
    });

    testWidgets('outline paints both a fill and a border', (tester) async {
      await tester.pumpWidget(host(cell(style: CalendarCellStyle.outline)));

      final decoration = tintDecoration(tester);
      expect(decoration.color, isNotNull);
      expect(decoration.gradient, isNull);
      // The border is deliberately *not* on the background decoration — see
      // the day-number group below for what that would cost.
      expect(decoration.border, isNull);
      expect(tintForeground(tester)?.border, isNotNull);
    });

    testWidgets('only outline paints a foreground at all', (tester) async {
      for (final style in [CalendarCellStyle.solid, CalendarCellStyle.fade]) {
        await tester.pumpWidget(host(cell(style: style)));
        expect(tintForeground(tester), isNull, reason: style.name);
      }
    });
  });

  group('the resolved wash is used, never re-derived', () {
    testWidgets('fade peaks at the wash exactly as it was handed', (
      tester,
    ) async {
      await tester.pumpWidget(host(cell(style: CalendarCellStyle.fade)));

      final gradient = tintDecoration(tester).gradient! as LinearGradient;
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.stops, [0.16, 1.0]);
      // The transparent end is a gradient *stop*, not a strength decision;
      // scaling the peak here is what would move the priority ramp into the
      // painter.
      expect(gradient.colors.first.a, 0);
      expect(gradient.colors.last, wash);
    });

    testWidgets('outline derives both alphas from the wash it was handed', (
      tester,
    ) async {
      await tester.pumpWidget(host(cell(style: CalendarCellStyle.outline)));

      final decoration = tintDecoration(tester);
      expect(
        decoration.color!.a,
        closeTo(wash.a * CalendarColors.outlineStyleWashScale, 0.005),
      );
      final side = (tintForeground(tester)!.border! as Border).top;
      expect(
        side.color.a,
        closeTo(wash.a * CalendarColors.outlineStyleBorderScale, 0.005),
      );
      expect(side.width, 1);
      // The hue is the event's; only the alpha is style-wide.
      expect(decoration.color!.r, wash.r);
      expect(side.color.g, wash.g);
    });

    test(
      'outline keeps the border stronger than the fill, at every priority',
      () {
        // The fill is a whisper by design, so the border is the only thing left
        // carrying priority. If these two ever cross, the ramp inverts and the
        // style silently starts saying the opposite of what it means.
        for (final alpha in CalendarColors.eventTintAlphaByPriority) {
          final fill = alpha * CalendarColors.outlineStyleWashScale;
          final border = (alpha * CalendarColors.outlineStyleBorderScale).clamp(
            0.0,
            1.0,
          );
          expect(border, greaterThan(fill), reason: 'at wash alpha $alpha');
        }
        // And the ramp itself still runs downhill in both derived channels.
        final borders = [
          for (final a in CalendarColors.eventTintAlphaByPriority)
            (a * CalendarColors.outlineStyleBorderScale).clamp(0.0, 1.0),
        ];
        for (var i = 1; i < borders.length; i++) {
          expect(borders[i], lessThan(borders[i - 1]));
        }
      },
    );

    testWidgets('both derived styles inherit the outside-month fade', (
      tester,
    ) async {
      // They read the faded local, not `tint.wash`, so an adjacent-month day
      // needs no per-style handling.
      await tester.pumpWidget(
        host(cell(style: CalendarCellStyle.fade, isOutside: true)),
      );
      final gradient = tintDecoration(tester).gradient! as LinearGradient;
      expect(
        gradient.colors.last.a,
        closeTo(wash.a * CalendarDayCell.outsideAlpha, 0.005),
      );

      await tester.pumpWidget(
        host(cell(style: CalendarCellStyle.outline, isOutside: true)),
      );
      final decoration = tintDecoration(tester);
      expect(
        decoration.color!.a,
        closeTo(
          wash.a *
              CalendarDayCell.outsideAlpha *
              CalendarColors.outlineStyleWashScale,
          0.005,
        ),
      );
      expect(
        (tintForeground(tester)!.border! as Border).top.color.a,
        closeTo(
          wash.a *
              CalendarDayCell.outsideAlpha *
              CalendarColors.outlineStyleBorderScale,
          0.005,
        ),
      );
    });
  });

  group('a tint that carries only an edge', () {
    // `CellTintResolver` can hand over a runner-up with no winner. Neither
    // derived style has anything to paint then, so both fall back to the
    // shape that has always shipped.
    for (final style in CalendarCellStyle.values) {
      testWidgets('${style.name} falls back to the flat shape', (tester) async {
        await tester.pumpWidget(
          host(
            cell(
              style: style,
              tint: const DayCellTint(edge: edge),
            ),
          ),
        );

        final decoration = tintDecoration(tester);
        expect(decoration.color, isNull);
        expect(decoration.gradient, isNull);
        expect(decoration.border, isNull);
      });
    }
  });

  group('a border must not move anything', () {
    // The whole reason `outline`'s border lives in `foregroundDecoration`. A
    // `Container` folds its *background* decoration's border width into the
    // child's padding, and only tinted days build this container at all — so
    // a border in `decoration` shifts the day number and the runner-up stripe
    // by 1px on exactly the days that carry an event, leaving them misaligned
    // against their untinted neighbours inside one grid.
    final stripeFinder = find.byWidgetPredicate((w) {
      if (w is! DecoratedBox) return false;
      final d = w.decoration;
      return d is BoxDecoration && d.borderRadius == BorderRadius.circular(2);
    });

    Future<Rect> stripeIn(WidgetTester tester, CalendarCellStyle style) async {
      await tester.pumpWidget(
        host(
          cell(
            style: style,
            tint: const DayCellTint(wash: wash, edge: edge),
          ),
        ),
      );
      final cellRect = tester.getRect(find.byType(CalendarDayCell));
      final stripe = tester.getRect(stripeFinder);
      return stripe.shift(-cellRect.topLeft);
    }

    testWidgets('every style keeps the stripe in the documented edge lane', (
      tester,
    ) async {
      // `edgeLaneLeft`/`edgeLaneInset` are the stripe's geometry restated in
      // cell coordinates, and `CalendarDayRail` shares that lane to the pixel
      // in `line` style — so a style that walked the stripe inward would split
      // the lane in half on any day that is both tinted and marked.
      for (final style in CalendarCellStyle.values) {
        final rect = await stripeIn(tester, style);
        expect(rect.left, CalendarDayCell.edgeLaneLeft, reason: style.name);
        expect(rect.top, CalendarDayCell.edgeLaneInset, reason: style.name);
        expect(rect.width, CalendarDayCell.edgeLaneWidth, reason: style.name);
      }
    });

    testWidgets('every style puts the day number in the same place', (
      tester,
    ) async {
      // A month mixes the three styles across nothing — one style is active
      // at a time — but it does mix *tinted* and untinted days constantly, and
      // the styles differ in whether their decoration carries a border. Pin
      // them to each other so a border can never start insetting the child.
      //
      // The baseline is `solid`, not an untinted cell: the tinted container's
      // 1.5px margin already lowers the digit by 1.5px on every tinted day,
      // which predates this setting and is deliberately left alone here.
      Future<Rect> numberFor(CalendarCellStyle style) async {
        await tester.pumpWidget(host(cell(style: style)));
        final cellRect = tester.getRect(find.byType(CalendarDayCell));
        return tester.getRect(find.text('10')).shift(-cellRect.topLeft);
      }

      final baseline = await numberFor(CalendarCellStyle.solid);
      for (final style in CalendarCellStyle.values) {
        expect(await numberFor(style), baseline, reason: style.name);
      }
    });
  });
}
