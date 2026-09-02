import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_rail_mark.dart';
import 'package:anta/widgets/calendar_day_rail.dart';

/// The rail's accessibility contract: **one** merged label per cell carrying
/// every visible mark, never one per mark — and it is produced by a pure
/// static, not by a `Semantics` node the widget emits.
///
/// The widget cannot announce anything itself. `table_calendar` wraps every
/// custom-built cell in `Semantics(excludeSemantics: true)`, and the rail
/// renders inside that cell, so a node built here would be dropped before it
/// reached a screen reader. `calendar_day_rail_grid_semantics_test.dart` pins
/// that escape route end-to-end; this file pins the label's *content*, which
/// is the half that can regress silently.
///
/// The load-bearing assertion is still that nothing is lost: missed state
/// rides the mark's own label, so colour is never the only carrier, and the
/// overflow count — which has no room to be drawn beside a 3px rail — exists
/// only in this string.
void main() {
  DayRailMark mark(String label, {bool missed = false}) => DayRailMark(
    key: 'event:$label',
    color: const Color(0xFFD32F2F),
    priority: 0,
    missed: missed,
    semanticLabel: missed ? '$label, missed' : label,
  );

  String? labelFor(
    List<DayRailMark> marks, {
    DayRailStyle style = DayRailStyle.line,
    int maxMarks = 3,
    double height = 44,
    bool hasBase = false,
  }) => CalendarDayRail.semanticsLabelFor(
    marks: marks,
    style: style,
    maxMarks: maxMarks,
    height: height,
    hasBase: hasBase,
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
      test('every mark label survives the merge', () {
        expect(
          labelFor([mark('Gym'), mark('Physio')], style: style),
          'Gym, Physio',
        );
      });

      test('missed state is audible, not just visible', () {
        // The faded/hollow rendering is a colour cue; a screen reader gets the
        // same fact from the label the provider composed.
        expect(
          labelFor([mark('Gym', missed: true), mark('Physio')], style: style),
          'Gym, missed, Physio',
        );
      });

      test('the overflow count lives only in the label', () {
        // Three slots, so two marks plus the affordance. The affordance itself
        // draws no number — a 3px rail has nowhere to put one — which makes
        // this string the only place "+2" exists at all.
        expect(
          labelFor([
            mark('Gym'),
            mark('Physio'),
            mark('Class'),
            mark('Standup'),
          ], style: style),
          'Gym, Physio, +2',
        );
      });

      test('a single mark still announces itself', () {
        expect(labelFor([mark('Gym')], style: style), 'Gym');
      });

      test('an empty rail announces nothing', () {
        expect(labelFor(const [], style: style), isNull);
      });

      testWidgets('the widget itself contributes no semantics node', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pump(tester, style: style, marks: [mark('Gym'), mark('Physio')]);

        // Not an oversight: inside a `table_calendar` cell this subtree is
        // excluded wholesale, so a node here would be built, merged, and
        // thrown away 42 times a rebuild. The label is carried by the day's
        // marker strip instead.
        expect(find.bySemanticsLabel('Gym, Physio'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(CalendarDayRail),
            matching: find.byType(Semantics),
          ),
          findsNothing,
        );
        handle.dispose();
      });
    });
  }

  test('a cap below capacity still leaves room for the affordance', () {
    expect(
      labelFor([mark('Gym'), mark('Physio'), mark('Class')], maxMarks: 2),
      'Gym, +2',
    );
  });

  test('a single slot still announces what it could not draw', () {
    // One slot draws the top mark instead of the affordance, so the label is
    // the *only* place the other two facts survive: that there is more, and
    // how much more.
    expect(labelFor([mark('Gym'), mark('Physio')], maxMarks: 1), 'Gym, +1');
  });

  test('a lane too short for a mark announces nothing', () {
    expect(
      labelFor([mark('Gym')], height: CalendarDayRail.minLineSegment - 1),
      isNull,
    );
  });

  test('the base band takes room from the marks, not a slot', () {
    // Half a 6px lane goes to the tint runner-up's band, leaving one 3px
    // segment: the single slot draws the top mark and the label carries the
    // rest. The same lane without a band fits both marks outright, so the
    // band is demonstrably what shortened the list.
    expect(
      labelFor([mark('Gym'), mark('Physio')], height: 6, hasBase: true),
      'Gym, +1',
    );
    expect(labelFor([mark('Gym'), mark('Physio')], height: 6), 'Gym, Physio');
  });

  test('the label never claims a mark the lane did not paint', () {
    // Both sides read the same split, so this is a structural guarantee
    // rather than a coincidence of two copies agreeing today.
    for (var markCount = 1; markCount <= 6; markCount++) {
      for (final height in [4.0, 9.0, 20.0, 44.0]) {
        for (final style in [DayRailStyle.line, DayRailStyle.dot]) {
          final marks = [for (var i = 0; i < markCount; i++) mark('m$i')];
          final label = labelFor(marks, style: style, height: height);
          if (label == null) continue;
          final parts = label.split(', ');
          final named = parts.where((p) => !p.startsWith('+')).length;
          expect(
            named,
            lessThanOrEqualTo(markCount),
            reason: '$style @$height with $markCount marks named $named',
          );
          final overflow = parts.where((p) => p.startsWith('+')).toList();
          if (overflow.isNotEmpty) {
            expect(overflow, hasLength(1));
            expect(int.parse(overflow.single.substring(1)), markCount - named);
          } else {
            expect(named, markCount);
          }
        }
      }
    }
  });
}
