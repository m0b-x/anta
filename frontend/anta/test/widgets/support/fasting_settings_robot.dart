import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/pages/fasting_settings_page.dart';

/// Drives [FastingSettingsPage] for its suite: rows by their `SemanticsIds`,
/// sections by their header, a row's state as its tile and its semantics
/// say it.
///
/// The page reads its settings through Drift, whose futures `FakeAsync`
/// alone never completes, so every step interleaves real time with pumped
/// frames rather than settling.
class FastingSettingsRobot {
  const FastingSettingsRobot(this.tester);

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

  /// Flips the switch of row [id], as a finger on the switch would.
  Future<void> toggle(String id) async {
    final target = find.descendant(of: row(id), matching: find.byType(Switch));
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle();
  }

  /// The tile row [id] draws — a `ListTile`, a `SwitchListTile`'s own one
  /// included.
  ListTile tile(String id) => tester.widget<ListTile>(
    find.descendant(of: row(id), matching: find.byType(ListTile)).first,
  );

  /// Whether row [id] takes a tap, as the tile and a screen reader see it.
  /// The node read is the tile's own: a `SwitchListTile` merges itself into
  /// a node under the one carrying the row's id.
  bool isEnabled(String id) {
    final data = tester
        .getSemantics(
          find.descendant(of: row(id), matching: find.byType(ListTile)).first,
        )
        .getSemanticsData();
    expect(
      data.flagsCollection.isEnabled != Tristate.none,
      isTrue,
      reason: '$id announces no enabled state',
    );
    return tile(id).enabled &&
        data.flagsCollection.isEnabled == Tristate.isTrue;
  }

  /// The colour row [id]'s leading glyph is painted in. Only a row with one:
  /// a sub-row has none, and its first icon is its trailing control's.
  Color? glyphColor(String id) => tester
      .widget<Icon>(
        find.descendant(of: row(id), matching: find.byType(Icon)).first,
      )
      .color;

  /// The colour row [id]'s [text] is drawn in, the ambient style included.
  Color? textColor(String id, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: row(id), matching: find.text(text)),
    );
    return paragraph.text.style?.color;
  }

  Rect switchRect(String id) => tester.getRect(
    find.descendant(of: row(id), matching: find.byType(Switch)),
  );

  /// Folds or unfolds the section headed [title] (drawn in capitals).
  Future<void> toggleSection(String title) async {
    await tester.tap(find.text(title.toUpperCase()));
    await settle();
  }
}
