import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/day_cell_tint.dart';
import 'package:anta/models/day_rail_mark.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/calendar_day_rail.dart';

/// The rail's label has to survive `table_calendar`, not just exist.
///
/// The package wraps **every** custom-built cell in
/// `Semantics(excludeSemantics: true)` — `cell_content.dart`, on both the
/// `prioritizedBuilder` and the `defaultBuilder` path — which drops every
/// descendant node. `CalendarDayRail` renders inside that cell, so for as long
/// as it built its own `Semantics` the day's commitments, their missed state
/// and the `+N` it has no room to draw were all silent in the real grid: built,
/// merged, and thrown away 42 times a rebuild.
///
/// The marker strip is the way out. `markerBuilder`'s widget is a **sibling**
/// of `CellContent` in the cell's `Stack`, outside the exclusion, which is the
/// only reason the bars have ever announced anything. The rail's label rides
/// that node now.
///
/// These tests pump the real package rather than a hand-rolled
/// `Semantics(excludeSemantics: true)`, so a future `table_calendar` that
/// stops excluding — or starts excluding the markers too — shows up here
/// instead of in a screen reader.
void main() {
  const insideCellProbe = 'probe-built-inside-the-cell';
  final marked = DateTime.utc(2026, 9, 15);
  final railStyle = DayRailStyle.line;

  DayRailMark mark(String label, {bool missed = false}) => DayRailMark(
    key: 'event:$label',
    color: const Color(0xFFD32F2F),
    priority: 0,
    missed: missed,
    semanticLabel: missed ? '$label, missed' : label,
  );

  DayBar bar(String label) => DayBar(
    key: 'bar:$label',
    color: const Color(0xFF1976D2),
    priority: 0,
    semanticLabel: label,
  );

  const rowHeight = 62.0;
  final stripHeight = CalendarDayBars.stripHeight(3, CalendarMarkerStyle.bars);
  final railHeight = CalendarDayCell.railLaneHeight(
    rowHeight: rowHeight,
    stripHeight: stripHeight,
    railStyle: railStyle,
  );

  /// A month grid wired exactly the way `calendar_page.dart` wires one: the
  /// cell through `defaultBuilder`, the strip through `markerBuilder`.
  ///
  /// [wireRailLabel] false reproduces the pre-fix wiring, where the strip is
  /// told nothing about the rail.
  ///
  /// [tint] and [laneHeight] exist for the base-band case: the page derives
  /// `hasBase` from the resolved tint's edge, so this harness derives it the
  /// same way rather than taking a bare flag, and the lane it paints is the
  /// lane the label was composed for.
  Future<void> pumpGrid(
    WidgetTester tester, {
    required List<DayRailMark> marks,
    required List<DayBar> bars,
    bool wireRailLabel = true,
    int maxRailMarks = 3,
    DayCellTint tint = DayCellTint.empty,
    double? laneHeight,
  }) {
    bool isMarked(DateTime day) => isSameDay(day, marked);
    final lane = laneHeight ?? railHeight;

    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableCalendar<Object>(
            firstDay: DateTime.utc(2026, 1, 1),
            lastDay: DateTime.utc(2026, 12, 31),
            focusedDay: marked,
            rowHeight: rowHeight,
            calendarStyle: const CalendarStyle(markersMaxCount: 0),
            calendarBuilders: CalendarBuilders<Object>(
              defaultBuilder: (context, day, focusedDay) => Semantics(
                // A control: anything the cell builds is under the package's
                // exclusion, so this must never reach the tree. If it does,
                // the premise of the whole fix has changed.
                label: insideCellProbe,
                child: CalendarDayCell(
                  day: day,
                  isToday: false,
                  isSelected: false,
                  isOutside: false,
                  isWeekend: false,
                  todayStyle: CalendarTodayStyle.ring,
                  highlightWeekends: false,
                  accent: const Color(0xFF1976D2),
                  tint: isMarked(day) ? tint : DayCellTint.empty,
                  railMarks: isMarked(day) ? marks : const [],
                  railStyle: railStyle,
                  maxRailMarks: maxRailMarks,
                  railHeight: lane,
                ),
              ),
              markerBuilder: (context, day, events) {
                final dayBars = isMarked(day) ? bars : const <DayBar>[];
                final railLabel = wireRailLabel && isMarked(day)
                    ? CalendarDayRail.semanticsLabelFor(
                        marks: marks,
                        style: railStyle,
                        maxMarks: maxRailMarks,
                        height: lane,
                        hasBase: tint.edge != null,
                      )
                    : null;
                if (dayBars.isEmpty && railLabel == null) {
                  return const SizedBox.shrink();
                }
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: CalendarDayBars(bars: dayBars, railLabel: railLabel),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the package still excludes everything the cell builds', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(tester, marks: [mark('Gym')], bars: [bar('Dentist')]);

    expect(find.bySemanticsLabel(insideCellProbe), findsNothing);
    handle.dispose();
  });

  testWidgets('the rail reaches the tree through the marker node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(
      tester,
      marks: [mark('Gym'), mark('Physio')],
      bars: [bar('Dentist')],
    );

    // The lane runs down the cell's left edge and the strip sits along its
    // bottom, so the rail's marks are read first.
    expect(find.bySemanticsLabel('Gym, Physio, Dentist'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the two channels stay one node, not one each', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(tester, marks: [mark('Gym')], bars: [bar('Dentist')]);

    // Merged, so neither channel is separately focusable: a day announces its
    // markers once.
    expect(find.bySemanticsLabel('Gym'), findsNothing);
    expect(find.bySemanticsLabel('Dentist'), findsNothing);
    expect(find.bySemanticsLabel('Gym, Dentist'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('missed state and the overflow count survive the trip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(
      tester,
      maxRailMarks: 2,
      marks: [mark('Gym', missed: true), mark('Physio'), mark('Class')],
      bars: [bar('Dentist')],
    );

    // Two slots: the top mark plus the affordance, which draws no number. The
    // "+2" and the missed state exist nowhere else in the grid.
    expect(find.bySemanticsLabel('Gym, missed, +2, Dentist'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the base band shortens what the grid announces', (tester) async {
    // The tint runner-up's band is not a slot — it takes room *from* the
    // marks — so `hasBase` changes the split, and therefore the string, before
    // it ever reaches the strip. Every other case here leaves the tint empty
    // and rides `hasBase`'s `false` default, which is exactly how a
    // `hasBase: false` hardcoded into a real `markerBuilder` would go
    // unnoticed.
    //
    // A 6px lane is what makes the difference visible: half of it goes to the
    // band, leaving one 3px segment (`minLineSegment`), so one slot draws the
    // top mark and the count goes into the label. The user's cap is 3 either
    // way, so the cap is demonstrably not what shortened the list.
    final handle = tester.ensureSemantics();
    await pumpGrid(
      tester,
      marks: [mark('Gym'), mark('Physio')],
      bars: [bar('Dentist')],
      tint: const DayCellTint(edge: Color(0xFF7E57C2)),
      laneHeight: 6,
    );

    expect(find.bySemanticsLabel('Gym, +1, Dentist'), findsOneWidget);
    expect(find.bySemanticsLabel('Gym, Physio, Dentist'), findsNothing);

    // The same lane, same marks, same cap — only the band gone. Both marks fit
    // now, which is what makes the assertion above about the band and not
    // about the height.
    await pumpGrid(
      tester,
      marks: [mark('Gym'), mark('Physio')],
      bars: [bar('Dentist')],
      laneHeight: 6,
    );

    expect(find.bySemanticsLabel('Gym, Physio, Dentist'), findsOneWidget);
    expect(find.bySemanticsLabel('Gym, +1, Dentist'), findsNothing);
    handle.dispose();
  });

  testWidgets('a rail-only day still announces, and with a real rect', (
    tester,
  ) async {
    // Not a corner case: with the rail on, `EventDayBarProvider` drops every
    // event the rail claimed, so a day whose only commitments are tracked
    // recurring ones has marks and no bars at all. Before the relocation such
    // a day contributed no marker node whatsoever.
    final handle = tester.ensureSemantics();
    await pumpGrid(
      tester,
      marks: [mark('Gym'), mark('Physio')],
      bars: const [],
    );

    final finder = find.bySemanticsLabel('Gym, Physio');
    expect(finder, findsOneWidget);
    // A zero-size render object is dropped from the semantics tree, which
    // would make the label reachable in the widget tree and unreachable to a
    // screen reader — the exact failure this whole change is about.
    expect(tester.getSemantics(finder).rect.isEmpty, isFalse);
    handle.dispose();
  });

  testWidgets('without the wiring the rail is silent — the bug it fixes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpGrid(
      tester,
      wireRailLabel: false,
      marks: [mark('Gym'), mark('Physio')],
      bars: [bar('Dentist')],
    );

    expect(find.bySemanticsLabel('Dentist'), findsOneWidget);
    expect(find.bySemanticsLabel('Gym, Physio, Dentist'), findsNothing);
    expect(find.bySemanticsLabel('Gym, Physio'), findsNothing);
    handle.dispose();
  });
}
