import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';
import 'package:anta/widgets/time_pad_sheet.dart';

import 'time_pad_support.dart' as time_pad;

/// The sheet's three shortcuts. Its own enum is private, so the suites name a
/// preset through this one.
enum QuickAlarmPreset { in20Minutes, in1Hour, tonight }

/// Drives [QuickAlarmSheet] for the suites: they say what the user does and
/// read what the sheet shows, and never name a widget type.
///
/// The seam worked once already: the bodies that call this predate the
/// 2026-10 rebuild of the sheet (`docs/calendar-language-tier-2-roadmap.md`)
/// and passed it unchanged, but for the behaviour that record changes on
/// purpose. Inlining a finder back into a suite gives that up for the next
/// rebuild.
///
/// Controls are tapped by their `SemanticsIds`, the handles the device flows
/// use. What the sheet shows is read off its rows and not off the semantics
/// tree, which the time pad blocks while it is up.
class QuickAlarmRobot {
  const QuickAlarmRobot(this.tester);

  final WidgetTester tester;

  Finder get _sheet => find.byType(QuickAlarmSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  FormHeroRow get _timeRow => tester.widget(_in(find.byType(FormHeroRow)));

  Finder get _nameField => _in(find.byType(EditableText));

  Finder get _removeAfterRow => _in(
    find.byWidgetPredicate(
      (widget) =>
          widget is FormSwitchRow &&
          widget.identifier == SemanticsIds.quickAlarmRemoveAfter,
    ),
  );

  /// A chip of the sheet by the id it was built with.
  FormChip _chip(String id) => tester.widget(
    _in(
      find.byWidgetPredicate(
        (widget) => widget is FormChip && widget.identifier == id,
      ),
    ),
  );

  static String _presetId(QuickAlarmPreset preset) => switch (preset) {
    QuickAlarmPreset.in20Minutes => SemanticsIds.quickAlarmPreset20,
    QuickAlarmPreset.in1Hour => SemanticsIds.quickAlarmPreset60,
    QuickAlarmPreset.tonight => SemanticsIds.quickAlarmPresetTonight,
  };

  static String _tierId(AlertMode mode) => switch (mode) {
    AlertMode.notify => SemanticsIds.quickAlarmTypeReminder,
    AlertMode.ring => SemanticsIds.quickAlarmTypeAlarm,
  };

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
  /// past that — a large text scale, a short surface — so a control is
  /// brought into view before it is tapped.
  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The big time, as the sheet formats it.
  String get timeLabel => _timeRow.value;

  /// The line under the time saying which day the alarm lands on. Read off
  /// the row, so it stays readable under the time pad — which is how a suite
  /// checks the day while the pad is up.
  String get dayLabel => _timeRow.caption;

  String get name => tester.widget<EditableText>(_nameField).controller.text;

  /// Whether the name holds the focus, which is what keeps a keyboard up.
  bool get nameFocused =>
      tester.widget<EditableText>(_nameField).focusNode.hasFocus;

  /// The tier whose chip is the selected one.
  AlertMode get currentTier =>
      AlertMode.values.singleWhere((mode) => _chip(_tierId(mode)).selected);

  bool get removeAfterVisible => _shown(_removeAfterRow);

  /// Whether the remove switch can be flipped, or stands dimmed in its place.
  bool get removeAfterEnabled =>
      tester.widget<FormSwitchRow>(_removeAfterRow).onChanged != null;

  /// What the remove switch shows.
  bool get removeAfterValue =>
      tester.widget<FormSwitchRow>(_removeAfterRow).value;

  bool get timePadOpen => _shown(find.byType(TimePadSheet));

  bool isPresetEnabled(QuickAlarmPreset preset) =>
      _chip(_presetId(preset)).onTap != null;

  /// The preset whose chip is the selected one, or null when the time is the
  /// default or was picked by hand.
  QuickAlarmPreset? get selectedPreset {
    final selected = [
      for (final preset in QuickAlarmPreset.values)
        if (_chip(_presetId(preset)).selected) preset,
    ];
    if (selected.length > 1) {
      fail('Expected at most one selected preset, found $selected');
    }
    return selected.firstOrNull;
  }

  Future<void> choosePreset(QuickAlarmPreset preset) =>
      _tap(_byId(_presetId(preset)));

  Future<void> openTimePad() => _tap(_byId(SemanticsIds.quickAlarmTime));

  Future<void> cancelTimePad() => time_pad.cancelTimePad(tester);

  /// Picks [time] by hand: the big time, then the pad.
  Future<void> pickTime(TimeOfDay time) async {
    await openTimePad();
    await time_pad.typeOnTimePad(tester, time);
  }

  /// Puts the caret in the name, as a tap on it does: the field takes the
  /// focus and the keyboard comes up.
  Future<void> focusName() => _tap(_byId(SemanticsIds.quickAlarmName));

  /// Leaves the text exactly as typed — trimming it and falling back to the
  /// default name are the sheet's to do on Save.
  Future<void> enterName(String text) => tester.enterText(_nameField, text);

  Future<void> chooseTier(AlertMode mode) => _tap(_byId(_tierId(mode)));

  Future<void> toggleRemoveAfter() =>
      _tap(_byId(SemanticsIds.quickAlarmRemoveAfter));

  Future<void> save() => _tap(_byId(SemanticsIds.quickAlarmSave));

  Future<void> close() => _tap(_byId(SemanticsIds.quickAlarmClose));
}
