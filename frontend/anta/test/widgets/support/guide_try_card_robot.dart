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

  /// The card's coach slot: the first, above any slot a stage holds.
  Finder get _slot =>
      find.descendant(of: card, matching: find.byType(FormCaptionSlot)).first;

  /// The coach line as it reads now.
  String get line {
    final slot = tester.widget<FormCaptionSlot>(_slot);
    return ((slot.child as Semantics).child! as Text).data!;
  }

  /// Every line the coach slot is sized for.
  List<String> get lineCandidates => [
    for (final candidate in tester.widget<FormCaptionSlot>(_slot).candidates)
      (candidate as Text).data!,
  ];

  /// The coach's skip; the kinds stage's own `skip` is its Skip this day.
  Finder get skipButton => _byId(SemanticsIds.calendarGuideTrySkip(slug));

  /// Whether the skip button answers a tap: disabled, never hidden, once
  /// every step is done.
  bool get canSkip =>
      tester
          .widget<IconButton>(
            find.descendant(of: skipButton, matching: find.byType(IconButton)),
          )
          .onPressed !=
      null;

  Future<void> skip() => _tap(skipButton);

  /// What the stage's own caption slots show, top to bottom — every slot of
  /// the card that holds a caption, past the coach line's — rather than the
  /// unseen candidates laid out under them.
  List<String> get stageCaptions => [
    for (final slot in tester.widgetList<FormCaptionSlot>(
      find.descendant(of: card, matching: find.byType(FormCaptionSlot)),
    ))
      if (slot.child case final FormCaption caption) caption.text,
  ];

  /// The size of the stage's [index]th caption slot, for a count that must
  /// change its words under its row and never the row's height.
  Size stageCaptionSlotSize(int index) => find
      .descendant(of: card, matching: find.byType(FormCaptionSlot))
      .evaluate()
      .where((slot) => (slot.widget as FormCaptionSlot).child is FormCaption)
      .elementAt(index)
      .size!;

  Size get slotSize => tester.getSize(_slot);

  Rect get slotRect => tester.getRect(_slot);

  /// The stage: the card body's one `RepaintBoundary`.
  Finder get _stage =>
      find.descendant(of: card, matching: find.byType(RepaintBoundary)).first;

  Size get stageSize => tester.getSize(_stage);

  Rect get stageRect => tester.getRect(_stage);

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

  /// The stage's [name] chip, for its selected and disabled states.
  FormChip chip(String name) => tester.widget<FormChip>(
    find.ancestor(of: control(name), matching: find.byType(FormChip)),
  );

  /// Whether the card draws [text] anywhere — its stage, or the events
  /// stage's unseen sizing rows, which hold only the seed's titles.
  bool shows(String text) => find
      .descendant(of: card, matching: find.text(text))
      .evaluate()
      .isNotEmpty;
}
