import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/day_cell_tint.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';

/// Outside-month days used to be wrapped in `Opacity` — once in the day cell
/// and once again around its marker strip, so 22-26 offscreen compositing
/// layers per page paint for what is only ever a colour change. The fade now
/// lives in the colours.
///
/// One branch is a deliberate exception: where the chip is opaque the number is
/// painted on top of it, so fading the two independently destroys their
/// contrast and washes the digit out. That branch keeps a single composite
/// layer.
///
/// These assertions pin the three things that could silently break: that an
/// inside cell is never faded, that the opaque branch keeps its composite, and
/// that `_onAccent` keeps its brightness estimate on the raw accent (fading
/// first inverts the day number on a pale accent).
void main() {
  const accent = Color(0xFF1A73E8);
  const paleAccent = Color(0xFFFFF176);
  const wash = Color(0x33FF5722);
  const edge = Color(0x884CAF50);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox.square(dimension: 60, child: child)),
    ),
  );

  CalendarDayCell cell({
    required bool isOutside,
    bool isSelected = false,
    bool isToday = false,
    Color cellAccent = accent,
  }) => CalendarDayCell(
    day: DateTime.utc(2026, 8, 10),
    isToday: isToday,
    isSelected: isSelected,
    isOutside: isOutside,
    isWeekend: false,
    todayStyle: CalendarTodayStyle.tonal,
    highlightWeekends: false,
    accent: cellAccent,
    tint: const DayCellTint(wash: wash, edge: edge),
  );

  Color textColor(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text)).style!.color!;

  List<Color> boxColors(WidgetTester tester) => [
    for (final d
        in tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>())
      if (d.color != null) d.color!,
  ];

  testWidgets('an outside cell fades its colours and allocates no Opacity', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: true)));

    expect(find.byType(Opacity), findsNothing);

    final colors = boxColors(tester);
    expect(
      colors.any((c) => (c.a - wash.a * 0.35).abs() < 0.01),
      isTrue,
      reason: 'the tint wash alpha should be multiplied, not replaced',
    );
    // colorScheme.onSurface is opaque, so the faded number lands exactly on
    // the factor.
    expect((textColor(tester).a - 0.35).abs(), lessThan(0.01));
  });

  testWidgets('an inside cell keeps every colour at full strength', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: false, isSelected: true)));

    expect(find.byType(Opacity), findsNothing);

    final colors = boxColors(tester);
    expect(colors.any((c) => c.a == accent.a), isTrue);
    expect(colors.any((c) => c.a == wash.a), isTrue);
    expect(textColor(tester).a, 1.0);
  });

  testWidgets('an opaque chip fades as a composite, not per layer', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: true, isSelected: true)));

    // The number sits on top of the chip. Fading both independently would
    // wash the digit out against its own background, so this one branch keeps
    // a single composite layer — and only this branch.
    expect(find.byType(Opacity), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.35);

    final colors = boxColors(tester);
    expect(
      colors.any((c) => c.a == accent.a),
      isTrue,
      reason: 'the chip keeps full alpha; the Opacity layer does the fading',
    );
    expect(
      textColor(tester).a,
      1.0,
      reason: 'number and chip must keep their relative contrast',
    );
    // The wash is outside the chip, so it still fades by colour.
    expect(colors.any((c) => (c.a - wash.a * 0.35).abs() < 0.01), isTrue);
  });

  testWidgets('the edge stripe fades with the rest of the cell', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: true)));

    final decorated = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null)
        .toList();

    expect(
      decorated.any((d) => (d.color!.a - edge.a * 0.35).abs() < 0.01),
      isTrue,
    );
  });

  testWidgets('the number brightness is estimated on the un-faded accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(cell(isOutside: true, isSelected: true, cellAccent: paleAccent)),
    );

    // A pale accent wants black87. Folding the fade in before the estimate
    // would darken the accent past the threshold and flip this to white.
    final color = textColor(tester);
    expect(color.r, Colors.black87.r);
    expect(color.g, Colors.black87.g);
    expect(color.b, Colors.black87.b);
  });

  testWidgets('day bars fade through the opacity parameter', (tester) async {
    const barColor = Color(0xFFE53935);
    await tester.pumpWidget(
      host(
        const CalendarDayBars(
          bars: [
            DayBar(
              key: 'event:x',
              color: barColor,
              priority: 0,
              semanticLabel: 'x',
            ),
          ],
          opacity: 0.35,
        ),
      ),
    );

    expect(find.byType(Opacity), findsNothing);

    final colors = boxColors(tester);
    expect(colors, isNotEmpty);
    expect((colors.first.a - barColor.a * 0.35).abs(), lessThan(0.01));
  });

  testWidgets('day bars default to full strength', (tester) async {
    const barColor = Color(0xFFE53935);
    await tester.pumpWidget(
      host(
        const CalendarDayBars(
          bars: [
            DayBar(
              key: 'event:x',
              color: barColor,
              priority: 0,
              semanticLabel: 'x',
            ),
          ],
        ),
      ),
    );

    expect(boxColors(tester).first.a, barColor.a);
  });
}
