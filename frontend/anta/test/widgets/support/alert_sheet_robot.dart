import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/utils/alert_offset.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/alert_offset_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

import 'time_pad_support.dart' as time_pad;

// The unit a custom offset counts in is the app's own enum; re-exported so a
// suite that names a unit needs no import but the robot's.
export 'package:anta/utils/alert_offset.dart' show AlertOffsetUnit;

/// Drives [AlertEditorSheet] and its Custom sub-sheet for the suites: they
/// say what the user does and read what the sheet shows, and never name a
/// widget type.
///
/// The seam worked once already: the bodies that call this predate the
/// 2026-10 rebuild of the sheet (`docs/calendar-language-tier-2-roadmap.md`)
/// and passed it unchanged, but for the behaviour that record changes on
/// purpose. Inlining a finder back into a suite gives that up for the next
/// rebuild.
///
/// Controls are addressed by their `SemanticsIds`, the same handles the
/// device flows use, so the robot also serves the event editor's suites,
/// where the form underneath has a Save and tier labels of its own.
class AlertSheetRobot {
  const AlertSheetRobot(this.tester);

  final WidgetTester tester;

  Finder get _sheet => find.byType(AlertEditorSheet);

  Finder get _custom => find.byType(AlertOffsetSheet);

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  Finder _in(Finder scope, Finder matching) =>
      find.descendant(of: scope, matching: matching);

  /// A row of the sheet by the id it was built with. Read off the widget and
  /// not the semantics tree, which the Custom sub-sheet blocks while it is
  /// up.
  Finder _row<T extends Widget>(bool Function(T row) carriesId) => _in(
    _sheet,
    find.byWidgetPredicate((widget) => widget is T && carriesId(widget)),
  );

  Finder get _soundRow =>
      _row<FormPickerRow>((row) => row.identifier == SemanticsIds.alertSound);

  Finder get _removeAfterRow => _row<FormSwitchRow>(
    (row) => row.identifier == SemanticsIds.alertRemoveAfter,
  );

  Finder get _removeAlertRow =>
      _row<FormActionRow>((row) => row.identifier == SemanticsIds.alertRemove);

  Finder get _timeOfDayRow => _row<FormPickerRow>(
    (row) => row.identifier == SemanticsIds.alertTimeOfDay,
  );

  FormMenuRow<int> get _whenRow =>
      tester.widget(_in(_sheet, find.byType(FormMenuRow<int>)));

  /// What of the Custom sub-sheet a finger can reach. The sheet also lays out
  /// every unit's group and every line its read-back can say, unseen, to
  /// hold its height; those take no touch.
  Finder _live(Finder matching) => _in(_custom, matching).hitTestable();

  FormStepperRow get _stepper =>
      tester.widget(_live(find.byType(FormStepperRow)));

  /// Whether [finder] matches, with the strength of the `findsOneWidget` /
  /// `findsNothing` pair it stands for: a second match fails the test
  /// whichever answer the caller expected.
  bool _shown(Finder finder) {
    final matches = finder.evaluate().length;
    if (matches > 1) {
      fail('Expected at most one match, found $matches: $finder');
    }
    return matches == 1;
  }

  /// The sheet is as tall as its rows up to most of the screen, and scrolls
  /// past that — a large text scale, a short surface — so a row is brought
  /// into view before it is tapped.
  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  static String _tierId(AlertMode mode) => switch (mode) {
    AlertMode.notify => SemanticsIds.alertTypeReminder,
    AlertMode.ring => SemanticsIds.alertTypeAlarm,
  };

  static String _unitId(AlertOffsetUnit unit) => switch (unit) {
    AlertOffsetUnit.minutes => SemanticsIds.alertCustomUnitMinutes,
    AlertOffsetUnit.hours => SemanticsIds.alertCustomUnitHours,
    AlertOffsetUnit.days => SemanticsIds.alertCustomUnitDays,
  };

  /// Whether the Custom sub-sheet is up.
  bool get customOpen => _shown(_custom);

  /// Whether the When menu offers the preset reading [label].
  bool offersPreset(String label) =>
      _whenRow.items.any((item) => item.label == label);

  /// What the When row reads.
  String get whenLabel => _whenRow.value;

  /// The labels of the When menu, top to bottom, Custom… last.
  List<String> get whenChoices => [
    for (final item in _whenRow.items) item.label,
  ];

  /// Whether Custom… is the checked item of the When menu: the offset is one
  /// no preset names.
  bool get customChecked => _whenRow.selected == _whenRow.items.last.value;

  /// Whether the Minutes / Hours / Days choice is on offer. The first sheet
  /// opened an offset no chip named with that choice standing under the
  /// chips, and the suites that predate the rebuild ask for that state by
  /// this name. The choice lives in the Custom sub-sheet now: while that is
  /// up this is the unit chips themselves, and until then it is
  /// [customChecked], the same state one tap earlier.
  bool get unitChoiceVisible => customOpen
      ? _shown(_byId(_unitId(AlertOffsetUnit.minutes)))
      : customChecked;

  /// How the custom offset reads: the Custom sub-sheet's own read-back while
  /// it is up, the When row otherwise.
  String get customLabel => customOpen
      ? tester.widget<FormCaption>(_live(find.byType(FormCaption))).text
      : whenLabel;

  /// The number the Custom sub-sheet's stepper stands on.
  int get customValue => int.parse(_stepper.value);

  /// Whether the Custom sub-sheet's stepper can still go [up], or down.
  bool canStepCustom({required bool up}) =>
      (up ? _stepper.onIncrement : _stepper.onDecrement) != null;

  bool get soundRowVisible => _shown(_soundRow);

  /// Whether the Sound row can be opened, or stands dimmed in its place.
  bool get soundRowEnabled => tester.widget<FormPickerRow>(_soundRow).enabled;

  /// What the Sound row says is chosen.
  String get soundLabel => tester.widget<FormPickerRow>(_soundRow).value!;

  bool get removeAfterVisible => _shown(_removeAfterRow);

  /// Whether the remove switch can be flipped, or stands dimmed in its place.
  bool get removeAfterEnabled =>
      tester.widget<FormSwitchRow>(_removeAfterRow).onChanged != null;

  /// What the remove switch shows.
  bool get removeAfterValue =>
      tester.widget<FormSwitchRow>(_removeAfterRow).value;

  bool get removeAlertVisible => _shown(_removeAlertRow);

  bool get timeOfDayVisible => _shown(_timeOfDayRow);

  /// What the Time of day row reads.
  String get timeOfDayLabel =>
      tester.widget<FormPickerRow>(_timeOfDayRow).value!;

  Future<void> chooseTier(AlertMode mode) => _tap(_byId(_tierId(mode)));

  Future<void> openWhenMenu() => _tap(_byId(SemanticsIds.alertWhen));

  Future<void> _chooseWhen(FormMenuItem<int> item) async {
    await openWhenMenu();
    await tester.tap(_byId(item.identifier!));
    await tester.pumpAndSettle();
  }

  /// Picks the timing preset reading [label] — "30 min before", "The day
  /// before" — from the When menu.
  Future<void> choosePreset(String label) =>
      _chooseWhen(_whenRow.items.firstWhere((item) => item.label == label));

  /// Opens the Custom sub-sheet through the When menu's last item.
  Future<void> openCustom() => _chooseWhen(_whenRow.items.last);

  Future<void> chooseUnit(AlertOffsetUnit unit) => _tap(_byId(_unitId(unit)));

  /// One step on the custom offset: more time before the event when [up].
  Future<void> stepCustom({required bool up}) => _tap(
    _byId(up ? SemanticsIds.alertCustomMore : SemanticsIds.alertCustomLess),
  );

  /// Done on the Custom sub-sheet: the offset it shows becomes the sheet's.
  Future<void> confirmCustom() => _tap(_byId(SemanticsIds.alertCustomDone));

  /// ✕ on the Custom sub-sheet: the sheet keeps the offset it had.
  Future<void> cancelCustom() => _tap(_byId(SemanticsIds.alertCustomClose));

  Future<void> toggleRemoveAfter() =>
      _tap(_byId(SemanticsIds.alertRemoveAfter));

  Future<void> tapSoundRow() => _tap(_byId(SemanticsIds.alertSound));

  /// Picks [time] for an all-day alert: the Time of day row, then the pad.
  Future<void> pickTimeOfDay(TimeOfDay time) async {
    await _tap(_byId(SemanticsIds.alertTimeOfDay));
    await time_pad.typeOnTimePad(tester, time);
  }

  Future<void> tapRemoveAlert() => _tap(_byId(SemanticsIds.alertRemove));

  /// Done on the sheet. With the Custom sub-sheet still up, the way there is
  /// the user's: Custom's own Done first, then the sheet's.
  Future<void> save() async {
    if (customOpen) await confirmCustom();
    await _tap(_byId(SemanticsIds.alertSheetSave));
  }

  Future<void> close() => _tap(_byId(SemanticsIds.alertSheetClose));
}
