import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/widgets/slider_setting_row.dart';

/// `SliderSettingRow` exists so a calendar-settings slider does not fire a
/// haptic, an awaited settings write and a whole-page rebuild on every drag
/// tick — only once, when the drag commits. These tests pin the commit
/// contract directly against the widget's `Slider` callbacks (rather than
/// simulating a raw drag gesture, which cannot easily leave `onChangeEnd`
/// unfired to exercise the debounce fallback) and the caption swap that
/// keeps the value visible while a drag is in progress.
void main() {
  const captionStyle = TextStyle(fontSize: 12, color: Colors.grey);

  Future<int> pumpRow(
    WidgetTester tester, {
    required int value,
    required List<int> commits,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SliderSettingRow(
            title: const Text('Max day bars'),
            description: const Text('idle caption'),
            value: value,
            min: 1,
            max: 6,
            divisions: 5,
            captionStyle: captionStyle,
            draftCaption: (draft) => 'draft caption $draft',
            onCommit: commits.add,
          ),
        ),
      ),
    );
    return value;
  }

  Slider slider(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider));

  testWidgets('dragging updates the caption but never commits', (
    tester,
  ) async {
    final commits = <int>[];
    await pumpRow(tester, value: 3, commits: commits);
    final row = slider(tester);

    row.onChanged!(5);
    await tester.pump();

    expect(commits, isEmpty);
    expect(find.text('draft caption 5'), findsOneWidget);
    expect(find.text('idle caption'), findsNothing);
    // The thumb tracks the draft, not the committed prop.
    expect(tester.widget<Slider>(find.byType(Slider)).value, 5);
  });

  testWidgets('onChangeEnd commits exactly once with the final value', (
    tester,
  ) async {
    final commits = <int>[];
    await pumpRow(tester, value: 3, commits: commits);
    final row = slider(tester);

    row.onChanged!(4);
    await tester.pump();
    row.onChanged!(5);
    await tester.pump();
    row.onChangeEnd!(5);
    await tester.pump();

    expect(commits, [5]);
    // The caption falls back to the idle, pre-rendered description again.
    expect(find.text('idle caption'), findsOneWidget);
    expect(find.textContaining('draft caption'), findsNothing);
  });

  testWidgets(
    'a debounce timer commits once when onChangeEnd never arrives',
    (tester) async {
      final commits = <int>[];
      await pumpRow(tester, value: 3, commits: commits);
      final row = slider(tester);

      row.onChanged!(6);
      await tester.pump();
      expect(commits, isEmpty);

      // Past the ~350ms fallback debounce; onChangeEnd is never called,
      // simulating an accessibility-driven change.
      await tester.pump(const Duration(milliseconds: 500));

      expect(commits, [6]);
      expect(find.text('idle caption'), findsOneWidget);
    },
  );

  testWidgets(
    'a timer commit followed by a late onChangeEnd does not double-commit',
    (tester) async {
      final commits = <int>[];
      await pumpRow(tester, value: 3, commits: commits);
      final row = slider(tester);

      row.onChanged!(6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(commits, [6]);

      // A late onChangeEnd for the same drag must be a no-op: the draft
      // that guards a pending commit was already cleared by the timer.
      row.onChangeEnd!(6);
      await tester.pump();

      expect(commits, [6]);
    },
  );

  testWidgets('an external value change discards an in-progress draft', (
    tester,
  ) async {
    final commits = <int>[];
    await pumpRow(tester, value: 3, commits: commits);
    final row = slider(tester);

    row.onChanged!(5);
    await tester.pump();
    expect(find.text('draft caption 5'), findsOneWidget);

    // The parent's "Reset to defaults" path: the committed `value` prop
    // changes from outside, independent of this row's own drag.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SliderSettingRow(
            title: const Text('Max day bars'),
            description: const Text('idle caption'),
            value: 2,
            min: 1,
            max: 6,
            divisions: 5,
            captionStyle: captionStyle,
            draftCaption: (draft) => 'draft caption $draft',
            onCommit: commits.add,
          ),
        ),
      ),
    );

    expect(find.text('idle caption'), findsOneWidget);
    expect(find.textContaining('draft caption'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 2);
    expect(commits, isEmpty);
  });
}
