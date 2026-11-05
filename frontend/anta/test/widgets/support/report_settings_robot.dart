import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/report_cards.dart';
import 'package:anta/pages/calendar_report_settings_page.dart';
import 'package:anta/widgets/form_rows.dart' show FormActionRow;

/// Drives [CalendarReportSettingsPage] for its suite: a card's handle and
/// switch by their `SemanticsIds`, the order as the handles stand on screen,
/// a drag as a finger on a handle makes it, a move as a screen reader asks
/// for it.
///
/// The page reads and writes its setting through Drift, whose futures
/// `FakeAsync` alone never completes, so every step interleaves real time
/// with pumped frames rather than settling.
class ReportSettingsRobot {
  const ReportSettingsRobot(this.tester);

  final WidgetTester tester;

  Finder handleOf(ReportCardKind kind) =>
      find.bySemanticsIdentifier(SemanticsIds.reportCardHandle(kind.name));

  Finder switchOf(ReportCardKind kind) =>
      find.bySemanticsIdentifier(SemanticsIds.reportCardSwitch(kind.name));

  Finder get reset => find.bySemanticsIdentifier(SemanticsIds.reportCardsReset);

  Future<void> settle({int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Flips [kind]'s switch, as a finger on the switch would.
  Future<void> toggle(ReportCardKind kind) async {
    final target = find.descendant(
      of: switchOf(kind),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle();
  }

  bool isOn(ReportCardKind kind) => tester
      .widget<Switch>(
        find.descendant(of: switchOf(kind), matching: find.byType(Switch)),
      )
      .value;

  /// Whether the card's [name] is drawn in the off role, `onSurfaceVariant`,
  /// rather than the on one, `onSurface`.
  bool isDimmed(String name) {
    final text = find.text(name);
    final color = tester.renderObject<RenderParagraph>(text).text.style?.color;
    final scheme = Theme.of(tester.element(text)).colorScheme;
    expect(
      color,
      anyOf(scheme.onSurface, scheme.onSurfaceVariant),
      reason: '"$name" is in neither role',
    );
    return color == scheme.onSurfaceVariant;
  }

  /// The cards top to bottom, as their handles stand.
  List<ReportCardKind> order() {
    final tops = {
      for (final kind in ReportCardKind.values)
        kind: tester.getTopLeft(handleOf(kind)).dy,
    };
    return [...ReportCardKind.values]
      ..sort((a, b) => tops[a]!.compareTo(tops[b]!));
  }

  /// Lifts [kind] by its handle, which lifts at once, carries it [by] and
  /// drops it, then lets the write land.
  Future<void> dragBy(ReportCardKind kind, Offset by) async {
    final from = tester.getCenter(handleOf(kind));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(from + by * (step / 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await settle();
  }

  /// Every semantics node carrying [kind]'s handle id, as a dump lists them.
  /// Needs semantics on.
  FinderBase<SemanticsNode> handleNodes(ReportCardKind kind) =>
      find.semantics.byPredicate(
        (node) =>
            node.getSemanticsData().identifier ==
            SemanticsIds.reportCardHandle(kind.name),
      );

  /// Whether [kind]'s handle offers [action] to a screen reader.
  bool offers(ReportCardKind kind, CustomSemanticsAction action) =>
      tester
          .getSemantics(handleOf(kind))
          .getSemanticsData()
          .customSemanticsActionIds
          ?.contains(CustomSemanticsAction.getIdentifier(action)) ??
      false;

  /// Performs [action] on [kind]'s handle, as a screen reader's action
  /// menu would, then lets the write land. Needs semantics on.
  Future<void> perform(
    ReportCardKind kind,
    CustomSemanticsAction action,
  ) async {
    tester.semantics.customAction(handleNodes(kind), action);
    await tester.pump();
    await settle();
  }

  Future<void> tapReset() async {
    await tester.ensureVisible(reset);
    await tester.pump();
    await tester.tap(reset);
    await settle();
  }

  /// Whether Reset takes a tap, as the row and a screen reader see it.
  bool isResetEnabled() {
    final data = tester.getSemantics(reset).getSemanticsData();
    final enabled = data.flagsCollection.isEnabled == Tristate.isTrue;
    final tappable = tester
        .widget<FormActionRow>(find.byType(FormActionRow))
        .onTap;
    expect(enabled, tappable != null, reason: 'the node and the row disagree');
    return enabled;
  }
}
