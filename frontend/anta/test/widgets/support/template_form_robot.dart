import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/widgets/color_swatch_picker.dart';
import 'package:anta/widgets/event_description_sheet.dart';
import 'package:anta/widgets/event_look_sheet.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/event_template_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/icon_picker_sheet.dart';

import 'time_pad_support.dart';

/// The repeat shapes the form offers. The Repeat sheet names them by label,
/// so the suites name a shape through this one.
enum TemplateRepeat { once, daily, weekly, monthly, yearly, workdays, weekends }

/// Drives the template form — [EventTemplateEditorSheet] — for the suites:
/// they say what the user does and read what the form shows, and never name
/// a widget type.
///
/// The seam worked once already: the bodies that call this predate the
/// 2026-10 rebuild of the form (`docs/calendar-language-tier-2-roadmap.md`)
/// and passed it unchanged, but for the behaviour that record changes on
/// purpose. Inlining a finder back into a suite gives that up for the next
/// rebuild.
///
/// The form's own controls are tapped by their `SemanticsIds`, the handles
/// the device flows use, and what a row shows is read off the row widget —
/// which stays readable under a sub-sheet, where the semantics tree is not.
///
/// The repeat and the look moved off the form into sub-sheets that confirm
/// with Done. The calls that predate the rebuild changed the form at once,
/// so each of them still does: it makes its change in the sub-sheet, confirms
/// it, and opens the sub-sheet again for whatever the suite reads or changes
/// next. A change the sub-sheet will not confirm (Weekly with no weekday)
/// stays pending in it. `confirm: false` leaves a change pending on purpose,
/// for the cases that go on to cancel it. Any call that is the form's own
/// leaves an open sub-sheet first, through its ✕.
///
/// What the form and its sub-sheets open in turn — the category picker, the
/// icon picker, the time pad, the description sheet — is driven through its
/// own `SemanticsIds` and labels: those have been on the UI language since
/// Tier 1 and are not part of the swap.
class TemplateFormRobot {
  const TemplateFormRobot(this.tester);

  final WidgetTester tester;

  static const List<String> _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String _repeatLabel(TemplateRepeat repeat) => switch (repeat) {
    TemplateRepeat.once => 'Does not repeat',
    TemplateRepeat.daily => 'Daily',
    TemplateRepeat.weekly => 'Weekly',
    TemplateRepeat.monthly => 'Monthly',
    TemplateRepeat.yearly => 'Yearly',
    TemplateRepeat.workdays => 'Workdays',
    TemplateRepeat.weekends => 'Weekends',
  };

  static String _countStyleId(OccurrenceCountStyle style) => switch (style) {
    OccurrenceCountStyle.numbered => SemanticsIds.templateCountStyleNumbered,
    OccurrenceCountStyle.elapsed => SemanticsIds.templateCountStyleElapsed,
  };

  Finder get _sheet => find.byType(EventTemplateEditorSheet);

  Finder get _repeatSheet => find.byType(EventRepeatSheet);

  Finder get _lookSheet => find.byType(EventLookSheet);

  Finder get _descriptionSheet => find.byType(EventDescriptionSheet);

  Finder _in(Finder scope, Finder matching) =>
      find.descendant(of: scope, matching: matching);

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  /// The widget that puts [id] on a control of the form. Unlike the control's
  /// semantics node it exists wherever the form is scrolled to, which is what
  /// lets a row under the fold be brought into view before it is tapped.
  Finder _carrier(String id) => _in(
    _sheet,
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.identifier == id,
    ),
  );

  Finder _pickerRow(String id) => _in(
    _sheet,
    find.byWidgetPredicate(
      (widget) => widget is FormPickerRow && widget.identifier == id,
    ),
  );

  Finder _switchRow(String id) => _in(
    _sheet,
    find.byWidgetPredicate(
      (widget) => widget is FormSwitchRow && widget.identifier == id,
    ),
  );

  Finder _chip(String id) => _in(
    _sheet,
    find.byWidgetPredicate(
      (widget) => widget is FormChip && widget.identifier == id,
    ),
  );

  Finder get _nameField => _in(_sheet, find.byType(EditableText));

  /// What of the Repeat sheet is drawn. The sheet also lays out the tallest
  /// group it may ever show, unseen, to hold its height; those rows are
  /// nobody's to read or tap.
  Finder _liveRepeat<T extends Widget>([bool Function(T widget)? matches]) {
    return _in(
      _repeatSheet,
      find.byElementPredicate((element) {
        final widget = element.widget;
        if (widget is! T || (matches != null && !matches(widget))) {
          return false;
        }
        var unseen = false;
        element.visitAncestorElements((ancestor) {
          final above = ancestor.widget;
          if (above is Opacity && above.opacity == 0) unseen = true;
          return !unseen && above is! EventRepeatSheet;
        });
        return !unseen;
      }),
    );
  }

  FormStepperRow get _stepper => tester.widget(_liveRepeat<FormStepperRow>());

  Finder get _tintRow => _in(_lookSheet, find.byType(FormSwitchRow));

  /// Whether [finder] matches. A second match is a robot that lost its way,
  /// so it fails the test whichever answer the caller expected.
  bool _shown(Finder finder) {
    final matches = finder.evaluate().length;
    if (matches > 1) {
      fail('Expected at most one match, found $matches: $finder');
    }
    return matches == 1;
  }

  Future<void> _tapOn(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// A sheet's body scrolls on a phone-sized surface, so a control in it is
  /// brought into view before it is tapped.
  Future<void> _tapInBody(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await _tapOn(target);
  }

  /// Taps the form's control carrying [id], on its semantics node.
  Future<void> _tap(String id) async {
    await tester.ensureVisible(_carrier(id));
    await tester.pumpAndSettle();
    await _tapOn(_byId(id));
  }

  Future<void> _setSwitch(String id, bool value) async {
    await _backToForm();
    if (tester.widget<FormSwitchRow>(_switchRow(id)).value == value) return;
    await _tap(id);
  }

  Future<void> _backToForm() async {
    if (_repeatOpen) await cancelRepeat();
    if (_lookOpen) await cancelLook();
  }

  bool get _repeatOpen => _shown(_repeatSheet);

  bool get _lookOpen => _shown(_lookSheet);

  Future<void> _settleRepeat(bool confirm) async {
    if (!confirm || !canConfirmRepeat) return;
    await confirmRepeat();
    await openRepeat();
  }

  Future<void> _settleLook(bool confirm) async {
    if (!confirm) return;
    await confirmLook();
    await openLook();
  }

  // --- The form -----------------------------------------------------------

  bool get isOpen => _shown(_sheet);

  bool get canSave =>
      tester
          .widget<FormHeaderTextButton>(
            _in(_sheet, find.byType(FormHeaderTextButton)),
          )
          .onPressed !=
      null;

  /// Whether the "Save failed" notice is up where a finger can reach it: it
  /// is raised in the overlay, above the form, so it is looked for on the
  /// whole screen and has to be the topmost thing where it stands.
  bool get saveFailureShown => _shown(find.text('Save failed').hitTestable());

  /// Whether the form is asking before it drops what was entered.
  bool get discardPromptShown => _shown(find.text('Unsaved changes'));

  String get name => tester.widget<EditableText>(_nameField).controller.text;

  /// Whether the name holds the focus, which is what keeps a keyboard up.
  bool get nameFocused =>
      tester.widget<EditableText>(_nameField).focusNode.hasFocus;

  /// What the Category row reads.
  String get categoryLabel => tester
      .widget<FormPickerRow>(_pickerRow(SemanticsIds.templateCategory))
      .value!;

  /// What the Icon & color row reads: Default, or Custom.
  String get lookLabel => tester
      .widget<FormPickerRow>(_pickerRow(SemanticsIds.templateLook))
      .value!;

  /// What the description row shows: the description on one line, or the
  /// invitation to add one.
  String get descriptionLabel => tester
      .widget<Text>(
        _in(_carrier(SemanticsIds.templateDescription), find.byType(Text)),
      )
      .data!;

  bool get allDay => tester
      .widget<FormSwitchRow>(_switchRow(SemanticsIds.templateAllDay))
      .value;

  /// What the Starts row reads, or null while the template is all day and
  /// the row is not there.
  String? get startsLabel => _timeLabel(SemanticsIds.templateStarts);

  /// What the Ends row reads, or null while the template is all day.
  String? get endsLabel => _timeLabel(SemanticsIds.templateEnds);

  String? _timeLabel(String id) => _shown(_pickerRow(id))
      ? tester.widget<FormPickerRow>(_pickerRow(id)).value
      : null;

  /// What the Repeat row reads back.
  String get repeatLabel => tester
      .widget<FormPickerRow>(_pickerRow(SemanticsIds.templateRepeat))
      .value!;

  /// Whether the form shows the options only a repeating template has.
  bool get occurrencesVisible =>
      _shown(_switchRow(SemanticsIds.templatePresence));

  bool get countOccurrencesVisible =>
      _shown(_switchRow(SemanticsIds.templateCount));

  /// What the Count occurrences switch shows.
  bool get countsOccurrences => tester
      .widget<FormSwitchRow>(_switchRow(SemanticsIds.templateCount))
      .value;

  /// The count style whose chip is the selected one, or null while the chips
  /// are not there.
  OccurrenceCountStyle? get countStyle {
    final selected = [
      for (final style in OccurrenceCountStyle.values)
        if (_shown(_chip(_countStyleId(style))) &&
            tester.widget<FormChip>(_chip(_countStyleId(style))).selected)
          style,
    ];
    if (selected.length > 1) {
      fail('Expected at most one selected count style, found $selected');
    }
    return selected.firstOrNull;
  }

  /// What the Track presence switch shows.
  bool get tracksPresence => tester
      .widget<FormSwitchRow>(_switchRow(SemanticsIds.templatePresence))
      .value;

  /// Whether the Assume absent chip is the selected one, or null while the
  /// pair is not there.
  bool? get assumesAbsent => _shown(_chip(SemanticsIds.templateAssumeAbsent))
      ? tester
            .widget<FormChip>(_chip(SemanticsIds.templateAssumeAbsent))
            .selected
      : null;

  /// What the Separate description per day switch shows.
  bool get perDay => tester
      .widget<FormSwitchRow>(_switchRow(SemanticsIds.templatePerDay))
      .value;

  /// What the Priority row reads.
  String get priorityLabel => tester
      .widget<FormMenuRow<int>>(_in(_sheet, find.byType(FormMenuRow<int>)))
      .value;

  /// Leaves the text exactly as typed — trimming is the form's to do on Save.
  Future<void> enterName(String text) async {
    await _backToForm();
    await tester.enterText(_nameField, text);
    await tester.pump();
  }

  /// Puts the caret in the name, as a tap on it does: the field takes the
  /// focus and the keyboard comes up.
  Future<void> focusName() async {
    await _backToForm();
    await _tap(SemanticsIds.templateName);
  }

  /// Picks the category with [id] in the category picker.
  Future<void> chooseCategory(String id) async {
    await openCategoryPicker();
    await _tapInBody(_byId(SemanticsIds.categoryPickRow(id)));
  }

  Future<void> openCategoryPicker() async {
    await _backToForm();
    await _tap(SemanticsIds.templateCategory);
  }

  Future<void> setAllDay(bool value) =>
      _setSwitch(SemanticsIds.templateAllDay, value);

  Future<void> openStartPad() async {
    await _backToForm();
    await _tap(SemanticsIds.templateStarts);
  }

  Future<void> openEndPad() async {
    await _backToForm();
    await _tap(SemanticsIds.templateEnds);
  }

  Future<void> pickStart(TimeOfDay time) async {
    await openStartPad();
    await typeOnTimePad(tester, time);
  }

  Future<void> pickEnd(TimeOfDay time) async {
    await openEndPad();
    await typeOnTimePad(tester, time);
  }

  Future<void> clearEnd() async {
    await _backToForm();
    await _tap(SemanticsIds.templateEndsClear);
  }

  Future<void> openPriorityMenu() async {
    await _backToForm();
    await _tap(SemanticsIds.templatePriority);
  }

  /// [priority] on the P1…P5 scale: 1 is the highest.
  Future<void> choosePriority(int priority) async {
    await openPriorityMenu();
    await _tapOn(_byId(SemanticsIds.templatePriorityItem(priority)));
  }

  Future<void> setTrackPresence(bool value) =>
      _setSwitch(SemanticsIds.templatePresence, value);

  Future<void> chooseAssume({required bool absent}) async {
    await _backToForm();
    await _tap(
      absent
          ? SemanticsIds.templateAssumeAbsent
          : SemanticsIds.templateAssumePresent,
    );
  }

  Future<void> setPerDay(bool value) =>
      _setSwitch(SemanticsIds.templatePerDay, value);

  Future<void> setCountOccurrences(bool value) =>
      _setSwitch(SemanticsIds.templateCount, value);

  Future<void> chooseCountStyle(OccurrenceCountStyle style) async {
    await _backToForm();
    await _tap(_countStyleId(style));
  }

  // --- The description sheet ----------------------------------------------

  /// Whether the description sheet's Done can be tapped: it cannot while the
  /// text is over the limit.
  bool get canConfirmDescription =>
      tester
          .widget<FormHeaderTextButton>(
            _in(_descriptionSheet, find.byType(FormHeaderTextButton)),
          )
          .onPressed !=
      null;

  CodeLineEditingController get _descriptionController => tester
      .widget<CodeEditor>(_in(_descriptionSheet, find.byType(CodeEditor)))
      .controller!;

  Future<void> openDescription() async {
    await _backToForm();
    await _tap(SemanticsIds.templateDescription);
  }

  /// Rewrites the text in the open description sheet the way the app does,
  /// through the controller: its editor is not an `EditableText`, so
  /// `enterText` has nothing to drive.
  Future<void> typeDescription(String text) async {
    _descriptionController.text = text;
    await tester.pump();
  }

  /// Done on the description sheet: its text becomes the form's.
  Future<void> confirmDescription() async {
    if (!canConfirmDescription) {
      fail('The description sheet cannot be confirmed as it stands');
    }
    await _tapOn(_byId(SemanticsIds.descriptionDone));
  }

  /// ✕ on the description sheet, through its own question when the text was
  /// changed: the form keeps the description it had.
  Future<void> cancelDescription() async {
    await _tapOn(_byId(SemanticsIds.descriptionClose));
    if (discardPromptShown) await discardChanges();
  }

  /// Leaves the text exactly as typed — trimming is the form's to do on Save.
  Future<void> enterDescription(String text) async {
    await openDescription();
    await typeDescription(text);
    await confirmDescription();
  }

  // --- The Repeat sheet ---------------------------------------------------

  /// Whether the interval stepper is on show. It lives in the Repeat sheet,
  /// so with that sheet closed there is none.
  bool get intervalVisible =>
      _repeatOpen && _shown(_liveRepeat<FormStepperRow>());

  /// The number the Repeat sheet's stepper stands on. Its value also names
  /// the unit ("3 weeks").
  int get interval =>
      int.parse(RegExp(r'\d+').firstMatch(_stepper.value)!.group(0)!);

  bool canStepInterval({required bool up}) =>
      (up ? _stepper.onIncrement : _stepper.onDecrement) != null;

  /// Whether the Repeat sheet's Done can be tapped: it cannot on Weekly with
  /// no weekday.
  bool get canConfirmRepeat =>
      tester
          .widget<FormHeaderTextButton>(
            _in(_repeatSheet, find.byType(FormHeaderTextButton)),
          )
          .onPressed !=
      null;

  Future<void> openRepeat() async {
    if (_repeatOpen) return;
    await _backToForm();
    await _tap(SemanticsIds.templateRepeat);
  }

  /// Done on the Repeat sheet: what it shows becomes the form's repeat.
  Future<void> confirmRepeat() async {
    if (!canConfirmRepeat) {
      fail('The Repeat sheet cannot be confirmed as it stands');
    }
    await _tapOn(_byId(SemanticsIds.repeatDone));
  }

  /// ✕ on the Repeat sheet: the form keeps the repeat it had. The sheet's
  /// close carries no id, so it is found as its header's one icon — in any
  /// language.
  Future<void> cancelRepeat() => _tapOn(
    _in(
      _in(_repeatSheet, find.byType(FormSheetHeader)),
      find.byIcon(Icons.close_rounded),
    ),
  );

  Future<void> chooseRepeat(
    TemplateRepeat repeat, {
    bool confirm = true,
  }) async {
    await openRepeat();
    await _tapInBody(
      _liveRepeat<FormRadioRow>((row) => row.label == _repeatLabel(repeat)),
    );
    await _settleRepeat(confirm);
  }

  Future<void> stepInterval({required bool up, bool confirm = true}) async {
    await openRepeat();
    await _tapInBody(
      _in(
        _liveRepeat<FormStepperRow>(),
        find.byIcon(up ? Icons.add_rounded : Icons.remove_rounded),
      ),
    );
    await _settleRepeat(confirm);
  }

  /// [weekday] as `DateTime` counts it: Monday is 1, Sunday is 7.
  Future<void> toggleWeekday(int weekday, {bool confirm = true}) async {
    await openRepeat();
    await _tapInBody(
      _liveRepeat<Semantics>(
        (cell) => cell.properties.label == _weekdayNames[weekday - 1],
      ),
    );
    await _settleRepeat(confirm);
  }

  /// The "also before the start date" switch: from the day the template is
  /// added on, or before it too.
  Future<void> chooseScope({
    required bool retroactive,
    bool confirm = true,
  }) async {
    await openRepeat();
    final row = _liveRepeat<FormSwitchRow>();
    if (tester.widget<FormSwitchRow>(row).value != retroactive) {
      await _tapInBody(row);
    }
    await _settleRepeat(confirm);
  }

  // --- The Icon & color sheet ---------------------------------------------

  /// Whether the Tint switch can be flipped. The first form took it off the
  /// screen while the template had no colour, and the suites that predate
  /// the rebuild ask for that state by this name. The switch lives in the
  /// Icon & color sheet now and never leaves it: without a colour it stands
  /// dimmed in its place, and with that sheet closed there is none to flip.
  bool get tintVisible =>
      _lookOpen && tester.widget<FormSwitchRow>(_tintRow).onChanged != null;

  Future<void> openLook() async {
    if (_lookOpen) return;
    await _backToForm();
    await _tap(SemanticsIds.templateLook);
  }

  /// Done on the Icon & color sheet: what it shows becomes the form's look.
  Future<void> confirmLook() => _tapOn(_byId(SemanticsIds.lookDone));

  /// ✕ on the Icon & color sheet: the form keeps the look it had.
  Future<void> cancelLook() => _tapOn(_byId(SemanticsIds.lookClose));

  /// Picks the icon with [key] in the icon picker, through its search.
  Future<void> chooseIcon(String key, {bool confirm = true}) async {
    final name = key.replaceAll('_', ' ');
    await openLook();
    await _tapOn(_byId(SemanticsIds.lookIcon));
    final picker = find.byType(IconPickerSheet);
    await tester.enterText(_in(picker, find.byType(TextField)), name);
    await tester.pumpAndSettle();
    await _tapOn(_in(picker, find.byTooltip(name)));
    await _settleLook(confirm);
  }

  /// Goes back to the category's icon: no icon of the template's own.
  Future<void> resetIcon({bool confirm = true}) async {
    await openLook();
    await _tapOn(_in(_lookSheet, find.byType(FormTrailingButton)));
    await _settleLook(confirm);
  }

  /// Picks the palette swatch of [argb]. The category-colour dot can wear the
  /// same colour, and is told apart by its glyph.
  Future<void> chooseColor(int argb, {bool confirm = true}) async {
    await openLook();
    await _tapInBody(
      _in(
        _lookSheet,
        find.byWidgetPredicate(
          (widget) =>
              widget is ColorSwatchDot &&
              widget.icon == null &&
              widget.color?.toARGB32() == argb,
        ),
      ),
    );
    await _settleLook(confirm);
  }

  /// Goes back to the category's colour: no colour of the template's own.
  Future<void> useCategoryColor({bool confirm = true}) async {
    await openLook();
    await _tapInBody(_in(_lookSheet, find.byTooltip('Category color')));
    await _settleLook(confirm);
  }

  Future<void> setTint(bool value, {bool confirm = true}) async {
    await openLook();
    if (tester.widget<FormSwitchRow>(_tintRow).value != value) {
      await _tapInBody(_tintRow);
    }
    await _settleLook(confirm);
  }

  // --- Saving and leaving -------------------------------------------------

  /// Taps Save and stops one frame in, with the write still in flight.
  Future<void> startSave() async {
    await _backToForm();
    await tester.tap(_byId(SemanticsIds.templateSave));
    await tester.pump();
  }

  /// Waits for a started save to end: the form closed on its template, or
  /// still open over a failure.
  Future<void> finishSave() => tester.pumpAndSettle();

  Future<void> save() async {
    await startSave();
    await finishSave();
  }

  /// ✕ on the form, and nothing after it: a form that has something to lose
  /// is now asking, [discardPromptShown].
  Future<void> tapClose() async {
    await _backToForm();
    await _tapOn(_byId(SemanticsIds.templateClose));
  }

  /// The question's "Keep editing": the form stays as it was.
  Future<void> keepEditing() => _tapOn(find.text('Keep editing'));

  /// The question's "Discard changes": the form leaves with nothing.
  Future<void> discardChanges() => _tapOn(find.text('Discard changes'));

  /// Leaves through the ✕ as a user who means it does: the form asks before
  /// it drops what was entered, and the answer is to discard it.
  Future<void> close() async {
    await tapClose();
    if (discardPromptShown) await discardChanges();
  }
}
