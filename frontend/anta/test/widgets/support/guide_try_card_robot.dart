import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/widgets/form_rows.dart';

/// Drives one "Try it" card of a calendar guide page for its suite: the
/// tests say what she does on the stage and read what the card says, by the
/// `SemanticsIds` a device flow uses. The real sheets the stage opens are
/// driven by their own ids, through [tapId].
class GuideTryCardRobot {
  const GuideTryCardRobot(this.tester, this.slug);

  final WidgetTester tester;
  final String slug;

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  Finder get card => _byId(SemanticsIds.calendarGuideTry(slug));

  Finder control(String name) =>
      _byId(SemanticsIds.calendarGuideTryControl(slug, name));

  Finder get _slot =>
      find.descendant(of: card, matching: find.byType(FormCaptionSlot));

  /// The live caption as it reads now; empty in the reserved slot.
  String get caption {
    final slot = tester.widget<FormCaptionSlot>(_slot);
    return ((slot.child as Semantics).child! as FormCaption).text;
  }

  Size get slotSize => tester.getSize(_slot);

  /// The stage: the card body's one `RepaintBoundary`.
  Size get stageSize => tester.getSize(
    find.descendant(of: card, matching: find.byType(RepaintBoundary)).first,
  );

  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tap(String name) => _tap(control(name));

  Future<void> longPress(String name) async {
    await tester.ensureVisible(control(name));
    await tester.pumpAndSettle();
    await tester.longPress(control(name));
    await tester.pumpAndSettle();
  }

  /// A control of a sheet or menu the stage opened.
  Future<void> tapId(String id) => _tap(_byId(id));

  /// Whether the stage's [name] control answers a tap: an action row with
  /// no callback is drawn disabled, never removed.
  bool enabled(String name) {
    final row = tester.widget<FormActionRow>(
      find.ancestor(of: control(name), matching: find.byType(FormActionRow)),
    );
    return row.onTap != null;
  }

  /// Whether the card draws [text] anywhere — its stage, or the events
  /// stage's unseen sizing rows, which hold only the seed's titles.
  bool shows(String text) =>
      find.descendant(of: card, matching: find.text(text)).evaluate().isNotEmpty;
}
