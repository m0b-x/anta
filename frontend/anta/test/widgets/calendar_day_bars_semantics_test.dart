import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/widgets/calendar_day_bars.dart';

/// Guard for **5.6**: a day cell's markers announce as **one** semantics node
/// carrying every marker's label, not one node per marker.
///
/// The roadmap framed this as a render-object saving, and it is one — but the
/// reason to do it is accessibility. A 3px bar inside a calendar cell is not a
/// useful focus target, so a screen reader used to stop on each of up to
/// `maxBars` slivers per cell, across 42 cells, reading them one at a time.
/// Merged, the cell says its whole story once.
///
/// That makes "the labels survived" the load-bearing assertion here: the
/// failure mode of this change is silently *dropping* information, which no
/// perf metric would catch and which the original per-bar `Semantics` calls
/// were the only thing providing.
void main() {
  DayBar bar(String key, String label) =>
      DayBar(key: key, color: Colors.red, priority: 0, semanticLabel: label);

  Future<void> pump(
    WidgetTester tester, {
    required List<DayBar> bars,
    int maxBars = 3,
    CalendarMarkerStyle style = CalendarMarkerStyle.bars,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 48,
              child: CalendarDayBars(
                bars: bars,
                maxBars: maxBars,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final style in CalendarMarkerStyle.values) {
    group(style.name, () {
      testWidgets('every marker label survives the merge', (tester) async {
        await pump(
          tester,
          style: style,
          bars: [bar('a', 'Leg day'), bar('b', 'Dentist')],
        );

        // The whole strip reads as one node, in marker order.
        expect(find.bySemanticsLabel('Leg day, Dentist'), findsOneWidget);
      });

      testWidgets('markers do not each get their own node', (tester) async {
        await pump(
          tester,
          style: style,
          bars: [bar('a', 'Leg day'), bar('b', 'Dentist')],
        );

        // The old shape: one `Semantics(label: bars[i].semanticLabel)` each.
        // A node labelled with a single marker means the merge regressed.
        expect(find.bySemanticsLabel('Leg day'), findsNothing);
        expect(find.bySemanticsLabel('Dentist'), findsNothing);
      });

      testWidgets('the overflow count is folded into the label', (
        tester,
      ) async {
        await pump(
          tester,
          style: style,
          maxBars: 3,
          bars: [
            bar('a', 'Leg day'),
            bar('b', 'Dentist'),
            bar('c', 'Standup'),
            bar('d', 'Payday'),
          ],
        );

        // maxBars 3 with 4 bars renders two markers plus "+2". The chip used
        // to announce "+2" on its own, with no clue what it belonged to; it
        // must still be audible, now as part of the cell's one sentence.
        expect(find.bySemanticsLabel('Leg day, Dentist, +2'), findsOneWidget);
      });

      testWidgets('a single marker still announces itself', (tester) async {
        await pump(tester, style: style, bars: [bar('a', 'Leg day')]);
        expect(find.bySemanticsLabel('Leg day'), findsOneWidget);
      });

      testWidgets('an empty day announces nothing', (tester) async {
        await pump(tester, style: style, bars: const []);
        // Scoped to this widget's own subtree: a bare `find.byType` would
        // also match the `Semantics` and `ExcludeSemantics` that MaterialApp
        // and Scaffold build for their own chrome.
        expect(find.byType(CalendarDayBars), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CalendarDayBars),
            matching: find.byType(ExcludeSemantics),
          ),
          findsNothing,
        );
      });
    });
  }

  testWidgets('the merged node is the only one the strip contributes', (
    tester,
  ) async {
    await pump(
      tester,
      maxBars: 2,
      bars: [bar('a', 'Leg day'), bar('b', 'Dentist'), bar('c', 'Standup')],
    );

    final handle = tester.ensureSemantics();
    // One marker plus a "+2" chip. Without ExcludeSemantics the chip's own
    // `Text` would surface as a second node inside the merged one, which is
    // the shape this change exists to collapse.
    expect(find.bySemanticsLabel('Leg day, +2'), findsOneWidget);
    expect(find.bySemanticsLabel('+2'), findsNothing);
    handle.dispose();
  });
}
