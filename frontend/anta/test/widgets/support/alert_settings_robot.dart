import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/pages/alert_settings_page.dart';

/// Drives [AlertSettingsPage] for its suite: rows by their `SemanticsIds`,
/// the sliders by what a drag ends on, sections by their header.
///
/// The page reads its settings through Drift, whose futures `FakeAsync`
/// alone never completes, so every step interleaves real time with pumped
/// frames rather than settling.
class AlertSettingsRobot {
  const AlertSettingsRobot(this.tester);

  final WidgetTester tester;

  Finder row(String id) => find.bySemanticsIdentifier(id);

  Future<void> settle({int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Brings the row into view, taps it and lets a sheet it raises finish
  /// opening.
  Future<void> tapRow(String id) async {
    await tester.ensureVisible(row(id));
    await tester.pump();
    await tester.tap(row(id));
    await settle();
  }

  /// Taps the row without a frame after it: a page it pushes stays unbuilt,
  /// so a suite can read the route without building what it holds.
  Future<void> tapRowUnbuilt(String id) async {
    await tester.ensureVisible(row(id));
    await tester.pump();
    await tester.tap(row(id));
  }

  Slider _slider(String id) => tester.widget<Slider>(
    find.descendant(of: row(id), matching: find.byType(Slider)),
  );

  /// A drag on the slider of row [id] that has reached [value] and is still
  /// held: the caption shows the draft.
  Future<void> dragTo(String id, int value) async {
    _slider(id).onChanged!(value.toDouble());
    await tester.pump();
  }

  /// The drag on row [id] let go at [value].
  Future<void> release(String id, int value) async {
    _slider(id).onChangeEnd!(value.toDouble());
    await settle();
  }

  /// Folds or unfolds the section headed [title] (drawn in capitals).
  Future<void> toggleSection(String title) async {
    await tester.tap(find.text(title.toUpperCase()));
    await settle();
  }
}
