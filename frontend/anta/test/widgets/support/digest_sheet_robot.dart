import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/widgets/digest_editor_sheet.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';

import 'time_pad_support.dart';

/// Drives the digest sheet — [DigestEditorSheet] — for the suites: they say
/// what the user does and read what the form shows, and never name a widget
/// type.
///
/// The form's controls are tapped by their `SemanticsIds`, the handles a
/// device flow uses; what a row shows is read off the row widget, which stays
/// readable under a menu or a dialog, where the semantics tree does not.
class DigestSheetRobot {
  const DigestSheetRobot(this.tester);

  final WidgetTester tester;

  Finder get _sheet => find.byType(DigestEditorSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  /// The widget that puts [id] on a control of the form; it exists wherever
  /// the form is scrolled to, so a row under the fold can be brought into
  /// view first.
  Finder _carrier(String id) => _in(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.identifier == id,
    ),
  );

  Finder _pickerRow(String id) => _in(
    find.byWidgetPredicate(
      (widget) => widget is FormPickerRow && widget.identifier == id,
    ),
  );

  Finder _menuRow(String id) => _in(
    find.byWidgetPredicate(
      (widget) => widget is FormMenuRow && widget.identifier == id,
    ),
  );

  Finder _switchRow(String id) => _in(
    find.byWidgetPredicate(
      (widget) => widget is FormSwitchRow && widget.identifier == id,
    ),
  );

  Finder get _dialog => find.byType(AlertDialog);

  bool get isOpen => _sheet.evaluate().isNotEmpty;

  Future<void> _tap(String id) async {
    await tester.ensureVisible(_carrier(id));
    await tester.pumpAndSettle();
    await tester.tap(_byId(id));
    await tester.pumpAndSettle();
  }

  /// Picks the item [itemId] from the menu the row [rowId] opens; a long
  /// menu (the days of the month) is scrolled to it first.
  Future<void> _pickFromMenu(String rowId, String itemId) async {
    await _tap(rowId);
    final item = find.bySemanticsIdentifier(itemId, skipOffstage: false);
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  // --- Rows -----------------------------------------------------------------

  Future<void> enterName(String name) async {
    await tester.enterText(_in(find.byType(EditableText)), name);
    await tester.pump();
  }

  /// The name field's placeholder: the title a nameless digest takes.
  String get nameHint =>
      tester.widget<FormTitleRow>(_in(find.byType(FormTitleRow))).hint;

  String? get categoriesValue => tester
      .widget<FormPickerRow>(_pickerRow(SemanticsIds.digestCategories))
      .value;

  /// Opens the Categories row's picker and confirms it with [ticked] as the
  /// only rows ticked — through Select none, then each row by id; [all]
  /// ticks every row through Select all instead.
  Future<void> pickCategories({
    Set<String> ticked = const {},
    bool all = false,
  }) async {
    await _tap(SemanticsIds.digestCategories);
    await tester.tap(
      find.bySemanticsIdentifier(
        all
            ? SemanticsIds.categoryPickSelectAll
            : SemanticsIds.categoryPickSelectNone,
      ),
    );
    await tester.pumpAndSettle();
    for (final id in all ? const <String>{} : ticked) {
      final row = find.bySemanticsIdentifier(SemanticsIds.categoryPickRow(id));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.categoryPickDone));
    await tester.pumpAndSettle();
  }

  String get showsValue =>
      tester.widget<FormMenuRow>(_menuRow(SemanticsIds.digestShows)).value;

  /// The Shows menu's labels in its order; the menu is closed again.
  Future<List<String>> showsChoices() => _menuChoices(SemanticsIds.digestShows);

  /// [slug] is `upcoming`, `week-report` or `month-report`.
  Future<void> pickShows(String slug) => _pickFromMenu(
    SemanticsIds.digestShows,
    SemanticsIds.digestShowsItem(slug),
  );

  String get cadenceValue =>
      tester.widget<FormMenuRow>(_menuRow(SemanticsIds.digestCadence)).value;

  /// Whether the Every row opens its menu — a report's is implied.
  bool get cadenceEnabled =>
      tester
          .widget<FormMenuRow<DigestCadence>>(
            _menuRow(SemanticsIds.digestCadence),
          )
          .onSelected !=
      null;

  Future<void> pickCadence(DigestCadence cadence) => _pickFromMenu(
    SemanticsIds.digestCadence,
    SemanticsIds.digestCadenceItem(cadence.name),
  );

  /// Whether the On row is there — a daily digest has none.
  bool get hasAnchor =>
      _menuRow(SemanticsIds.digestAnchor).evaluate().isNotEmpty;

  String get anchorValue =>
      tester.widget<FormMenuRow>(_menuRow(SemanticsIds.digestAnchor)).value;

  /// The On menu's labels in the order it lists them; the menu is closed
  /// again without a pick.
  Future<List<String>> anchorChoices() =>
      _menuChoices(SemanticsIds.digestAnchor);

  Future<List<String>> _menuChoices(String rowId) async {
    await _tap(rowId);
    final labels = [
      for (final row in tester.widgetList<FormMenuItemRow>(
        find.byType(FormMenuItemRow, skipOffstage: false),
      ))
        row.label,
    ];
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    return labels;
  }

  /// [value] is a weekday (1–7) for a weekly digest, a day of the month
  /// (1–28) for a monthly one.
  Future<void> pickAnchor(int value) => _pickFromMenu(
    SemanticsIds.digestAnchor,
    SemanticsIds.digestAnchorItem(value),
  );

  String? get timeValue =>
      tester.widget<FormPickerRow>(_pickerRow(SemanticsIds.digestTime)).value;

  Future<void> pickTime(TimeOfDay time) async {
    await _tap(SemanticsIds.digestTime);
    await typeOnTimePad(tester, time);
  }

  String get leadValue =>
      tester.widget<FormMenuRow>(_menuRow(SemanticsIds.digestLead)).value;

  /// Whether the Covers row opens its menu — a report's span is the period
  /// that ended.
  bool get leadEnabled =>
      tester
          .widget<FormMenuRow<int>>(_menuRow(SemanticsIds.digestLead))
          .onSelected !=
      null;

  Future<void> pickLead(int days) =>
      _pickFromMenu(SemanticsIds.digestLead, SemanticsIds.digestLeadItem(days));

  /// What dims the row [id] — `FormMetrics.disabledOpacity` on a disabled
  /// row — or null when nothing does.
  double? rowOpacity(String id) {
    final opacities = tester.widgetList<Opacity>(
      find.descendant(of: _byId(id), matching: find.byType(Opacity)),
    );
    return opacities.isEmpty ? null : opacities.first.opacity;
  }

  /// The row [id]'s semantics node, as a screen reader meets it.
  SemanticsData rowSemantics(String id) =>
      tester.getSemantics(_byId(id)).getSemanticsData();

  double rowHeight(String id) => tester.getSize(_carrier(id)).height;

  bool get includeEmpty => tester
      .widget<FormSwitchRow>(_switchRow(SemanticsIds.digestIncludeEmpty))
      .value;

  Future<void> toggleIncludeEmpty() => _tap(SemanticsIds.digestIncludeEmpty);

  /// The next-fire line under the rows.
  String get caption =>
      (tester.widget<FormCaptionSlot>(_in(find.byType(FormCaptionSlot))).child
              as FormCaption)
          .text;

  double get captionHeight =>
      tester.getSize(_in(find.byType(FormCaptionSlot))).height;

  bool get hasDelete =>
      _carrier(SemanticsIds.digestDelete).evaluate().isNotEmpty;

  // --- Leaving --------------------------------------------------------------

  Future<void> save() => _tap(SemanticsIds.digestSheetSave);

  /// ✕: closes at once on a clean form, asks on a dirty one.
  Future<void> close() => _tap(SemanticsIds.digestSheetClose);

  /// Delete digest, then the confirmation's [confirm] or its cancel.
  Future<void> delete({bool confirm = true}) async {
    await _tap(SemanticsIds.digestDelete);
    await tester.tap(
      find.bySemanticsIdentifier(
        confirm ? SemanticsIds.sheetConfirm : SemanticsIds.sheetCancel,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The system back gesture, which the sheet routes through its leave
  /// guard.
  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  /// A tap on the scrim above the sheet.
  Future<void> tapBarrier() async {
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
  }

  bool get isAskingToDiscard => _dialog.evaluate().isNotEmpty;

  Future<void> discard() async {
    await tester.tap(
      find.descendant(of: _dialog, matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> keepEditing() async {
    await tester.tap(
      find.descendant(of: _dialog, matching: find.byType(TextButton)),
    );
    await tester.pumpAndSettle();
  }
}
