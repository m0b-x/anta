import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_rail_mark.dart';
import 'package:anta/widgets/calendar_day_rail.dart';

/// The rail's accessibility contract, mirroring
/// `calendar_day_bars_semantics_test.dart`: **one** merged node per cell
/// carrying every visible mark's label, never one node per mark.
///
/// A day already contributes a marker node for the bottom strip, and the two
/// live in separate table_calendar subtrees (`cellBuilder` vs
/// `markerBuilder`), so one node each is the floor. What must not happen is a
/// 3px sliver becoming its own unlabelled focus target, five deep, across 42
/// cells.
///
/// The load-bearing assertion is that nothing is lost: missed state rides the
/// mark's own label, so colour is never the only carrier, and the overflow
/// count — which has no room to be drawn beside a 3px rail — exists *only*
/// here.
void main() {
  DayRailMark mark(String label, {bool missed = false}) => DayRailMark(
    key: 'event:$label',
    color: const Color(0xFFD32F2F),
    priority: 0,
    missed: missed,
    semanticLabel: missed ? '$label, missed' : label,
  );

  Future<void> pump(
    WidgetTester tester, {
    required List<DayRailMark> marks,
    DayRailStyle style = DayRailStyle.line,
    int maxMarks = 3,
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final style in [DayRailStyle.line, DayRailStyle.dot]) {
    group(style.name, () {
      testWidgets('every mark label survives the merge', (tester) async {
        await pump(tester, style: style, marks: [mark('Gym'), mark('Physio')]);

        expect(find.bySemanticsLabel('Gym, Physio'), findsOneWidget);
      });

      testWidgets('marks do not each get their own node', (tester) async {
        await pump(tester, style: style, marks: [mark('Gym'), mark('Physio')]);

        expect(find.bySemanticsLabel('Gym'), findsNothing);
        expect(find.bySemanticsLabel('Physio'), findsNothing);
      });

      testWidgets('missed state is audible, not just visible', (tester) async {
        await pump(
          tester,
          style: style,
          marks: [mark('Gym', missed: true), mark('Physio')],
        );

        // The faded/hollow rendering is a colour cue; a screen reader gets the
        // same fact from the label the provider composed.
        expect(find.bySemanticsLabel('Gym, missed, Physio'), findsOneWidget);
      });

      testWidgets('the overflow count lives only in the label', (tester) async {
        await pump(
          tester,
          style: style,
          maxMarks: 3,
          marks: [mark('Gym'), mark('Physio'), mark('Class'), mark('Standup')],
        );

        // Three slots, so two marks plus the affordance. The affordance itself
        // draws no number — a 3px rail has nowhere to put one — which makes
        // this label the only place "+2" exists at all.
        expect(find.bySemanticsLabel('Gym, Physio, +2'), findsOneWidget);
        expect(find.bySemanticsLabel('+2'), findsNothing);
      });

      testWidgets('a single mark still announces itself', (tester) async {
        await pump(tester, style: style, marks: [mark('Gym')]);
        expect(find.bySemanticsLabel('Gym'), findsOneWidget);
      });

      testWidgets('an empty rail contributes no node', (tester) async {
        await pump(tester, style: style, marks: const []);

        expect(find.byType(CalendarDayRail), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CalendarDayRail),
            matching: find.byType(ExcludeSemantics),
          ),
          findsNothing,
        );
      });
    });
  }

  testWidgets('the merged node is the only one the rail contributes', (
    tester,
  ) async {
    await pump(
      tester,
      maxMarks: 2,
      marks: [mark('Gym'), mark('Physio'), mark('Class')],
    );

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Gym, +2'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a single slot still announces what it could not draw', (
    tester,
  ) async {
    await pump(tester, maxMarks: 1, marks: [mark('Gym'), mark('Physio')]);

    // One slot draws the top mark instead of the affordance, so the label is
    // the *only* place the other two facts survive: that there is more, and
    // how much more.
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Gym, +1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CalendarDayRail),
        matching: find.byType(Semantics),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
