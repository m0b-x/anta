import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/settings_section_list.dart';

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

  CalendarGuideCoachSemantics get _lineNode =>
      tester.widget<FormCaptionSlot>(_slot).child
          as CalendarGuideCoachSemantics;

  static String _textOf(Widget widget) => switch (widget) {
    Text(:final data?) => data,
    CalendarGuideReadBackText(:final text) => text,
    _ => throw StateError('not a coach line: $widget'),
  };

  /// The coach line as it reads now, live or read back.
  String get line => _textOf(_lineNode.child);

  /// An earlier step's line is shown, read back (D70).
  bool get reading => _lineNode.reading;

  /// Every line the coach slot is sized for, the read-back ones included.
  List<String> get lineCandidates => [
    for (final candidate in tester.widget<FormCaptionSlot>(_slot).candidates)
      _textOf(candidate),
  ];

  /// The read-back lines the slot is sized for, each with its mark (D93).
  List<String> get readBackCandidates => [
    for (final candidate in tester.widget<FormCaptionSlot>(_slot).candidates)
      if (candidate case CalendarGuideReadBackText(:final text)) text,
  ];

  /// The coach's forward, which skips at the live line and so keeps the
  /// skip's id (D89); the kinds stage's own `skip` is its Skip this day.
  Finder get skipButton => _byId(SemanticsIds.calendarGuideTrySkip(slug));

  Finder get backButton => _byId(SemanticsIds.calendarGuideTryStepBack(slug));

  IconButton _button(Finder button) => tester.widget<IconButton>(
    find.descendant(of: button, matching: find.byType(IconButton)),
  );

  /// Whether forward answers a tap: disabled, never hidden, once every step
  /// is done and the live line is shown.
  bool get canSkip => _button(skipButton).onPressed != null;

  bool get canBack => _button(backButton).onPressed != null;

  /// Forward: a skip at the live line, a step toward it while reading back.
  Future<void> skip() => _tap(skipButton);

  Future<void> back() => _tap(backButton);

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

  /// Moves the page's list from its top down until the card is built, then
  /// brings it into view — by the list's position, not a drag: a drag over
  /// another card's stage would scroll that stage's own slot.
  Future<void> reveal() async {
    final list = find
        .descendant(
          of: find.byType(SettingsSectionList),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(list).position;
    if (card.evaluate().isEmpty) {
      position.jumpTo(0);
      await tester.pump();
    }
    for (var i = 0; i < 200 && card.evaluate().isEmpty; i++) {
      position.jumpTo(
        (position.pixels + 300).clamp(0.0, position.maxScrollExtent),
      );
      await tester.pump();
    }
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
  }

  /// Scrolls the page's list only as far as [target] needs to be whole on
  /// screen, as a finger would — never an inner scrollable, whose month
  /// pager `ensureVisible` would page, and never to the top, where
  /// `ensureVisible` would put a chip under the grid it washes.
  Future<void> showOnPage(Finder target) async {
    final list = find
        .descendant(
          of: find.byType(SettingsSectionList),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(list).position;
    final viewport = tester.getRect(list);
    final rect = tester.getRect(target);
    final delta = rect.top < viewport.top
        ? rect.top - viewport.top
        : rect.bottom > viewport.bottom
        ? rect.bottom - viewport.bottom
        : 0.0;
    if (delta == 0) return;
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the stage's [name] chip where the page shows it — the fasting
  /// card's traditions, under the grid they wash.
  Future<void> tapChip(String name) async {
    await showOnPage(control(name));
    await tester.tap(control(name));
    await tester.pumpAndSettle();
  }

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

  /// The stage's [name] switch row, for its value and whether it answers.
  FormSwitchRow switchRow(String name) => tester.widget(
    find.ancestor(of: control(name), matching: find.byType(FormSwitchRow)),
  );

  /// The stage's [name] picker row: disabled, never removed, while it has
  /// nothing to open.
  FormPickerRow pickerRow(String name) => tester.widget(
    find.ancestor(of: control(name), matching: find.byType(FormPickerRow)),
  );

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
