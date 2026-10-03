import 'dart:async';
import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/alert_offset_sheet.dart';
import 'package:anta/widgets/alert_sound_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/time_pad_sheet.dart';
import 'package:anta/widgets/value_change_highlight.dart';

import '../database/support/db_test_support.dart';
import '../services/permission_support.dart';
import 'support/alert_sheet_robot.dart';

/// The sheet edits a **draft** and reports it on Done, so what is worth
/// pinning is the round trip: a picked preset, a tier change and the remove
/// switch all have to survive it, and the offset set the form is *not*
/// showing has to come back untouched — that is the whole promise
/// `EventAlert` makes about an event flipped between timed and all-day.
void main() {
  CalendarEvent eventOf({bool allDay = false}) => CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 20),
    rule: const OneTimeRecurrence(),
    time: allDay ? null : const EventTime(startMinute: 18 * 60),
  );

  const alert = EventAlert(
    id: 'a1',
    eventId: 'e1',
    offsetMinutes: 10,
    daysBefore: 2,
    dayMinute: 8 * 60,
  );

  /// [surface], [locale], [textScale] and [use24HourFormat] dress the device
  /// for the layout cases; left alone, the app is the bare one every
  /// round-trip case has always opened the sheet from.
  Future<_Result> openSheet(
    WidgetTester tester, {
    EventAlert initial = alert,
    bool allDay = false,
    bool canRemove = true,
    bool showSound = true,
    bool showRemoveAfter = false,
    bool removeAfterAlert = false,
    Size? surface,
    Locale locale = const Locale('en'),
    double? textScale,
    bool use24HourFormat = false,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: textScale == null && !use24HourFormat
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale ?? 1.0),
                  alwaysUse24HourFormat: use24HourFormat,
                ),
                child: child!,
              ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await AlertEditorSheet.show(
                  context,
                  alert: initial,
                  event: eventOf(allDay: allDay),
                  canRemove: canRemove,
                  showSound: showSound,
                  showRemoveAfter: showRemoveAfter,
                  removeAfterAlert: removeAfterAlert,
                );
                result.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  test('a timed draft is seeded for an all-day flip too', () {
    // Both offset sets ride every alert. One minted on a timed event used to
    // carry no day time at all, so flipping the event to all-day left it on
    // whatever the fallback happened to be rather than on the setting.
    final draft = AlertEditorSheet.draft(
      eventId: 'e1',
      allDay: false,
      timedDefault: (mode: AlertMode.ring, offsetMinutes: 15),
      allDayDefault: (mode: AlertMode.notify, daysBefore: 1, dayMinute: 480),
    );

    expect(draft.mode, AlertMode.ring);
    expect(draft.offsetMinutes, 15);
    expect(draft.daysBefore, 1);
    expect(draft.dayMinute, 480);
  });

  test('a draft with no settings default still opens on a useful offset', () {
    // The app ships with no default, so this is the draft "Add alert" opens
    // on for most people: ten minutes before, not "at start".
    final draft = AlertEditorSheet.draft(eventId: 'e1', allDay: false);

    expect(draft.mode, AlertMode.notify);
    expect(draft.offsetMinutes, kDraftAlertOffsetMinutes);
    expect(draft.daysBefore, 0);
    expect(draft.dayMinute, isNull);
  });

  testWidgets('a timed chip is what Save reports', (tester) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(tester);

    await sheet.choosePreset('30 min before');
    await sheet.save();

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.offsetMinutes, 30);
    // The set the form never showed comes back exactly as it went in.
    expect(saved.alert.daysBefore, 2);
    expect(saved.alert.dayMinute, 8 * 60);
  });

  testWidgets('an all-day event is asked for days, not minutes', (
    tester,
  ) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(tester, allDay: true);

    expect(sheet.offersPreset('30 min before'), isFalse);
    await sheet.choosePreset('The day before');
    await sheet.save();

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.daysBefore, 1);
    expect(saved.alert.offsetMinutes, 10);
  });

  testWidgets('the tier survives the round trip', (tester) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(tester);

    await sheet.chooseTier(AlertMode.ring);
    await sheet.save();

    expect((result.value as AlertEditorSaved).alert.mode, AlertMode.ring);
  });

  testWidgets('the remove switch is offered for an alarm and rides the result',
      (tester) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(tester, showRemoveAfter: true);

    // A reminder cannot be what deletes an event, so until the tier is Alarm
    // the switch stands in its place and cannot be flipped.
    expect(sheet.removeAfterVisible, isTrue);
    expect(sheet.removeAfterEnabled, isFalse);
    await sheet.chooseTier(AlertMode.ring);
    await sheet.toggleRemoveAfter();
    await sheet.save();

    final saved = result.value as AlertEditorSaved;
    expect(saved.removeAfterAlert, isTrue);
  });

  testWidgets('going back to a reminder disarms the removal', (tester) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(
      tester,
      initial: alert.copyWith(mode: AlertMode.ring),
      showRemoveAfter: true,
      removeAfterAlert: true,
    );

    expect(sheet.removeAfterVisible, isTrue);
    await sheet.chooseTier(AlertMode.notify);
    await sheet.save();

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.mode, AlertMode.notify);
    expect(saved.removeAfterAlert, isFalse);
  });

  testWidgets('Remove alert reports a removal, not a save', (tester) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(tester);

    await sheet.tapRemoveAlert();

    expect(result.value, isA<AlertEditorRemoved>());
  });

  testWidgets('a draft with nothing to remove offers no removal', (
    tester,
  ) async {
    final sheet = AlertSheetRobot(tester);
    await openSheet(tester, canRemove: false);

    expect(sheet.removeAlertVisible, isFalse);
  });

  testWidgets('the custom row counts in the unit it is set to', (tester) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(tester);

    await sheet.openCustom();
    await sheet.chooseUnit(AlertOffsetUnit.hours);
    await sheet.stepCustom(up: true);
    await sheet.save();

    // The number survives the unit change — ten minutes becomes ten hours,
    // the way every stepper with a unit beside it behaves — and the step
    // takes it to eleven.
    expect((result.value as AlertEditorSaved).alert.offsetMinutes, 11 * 60);
  });

  testWidgets('an offset that matches no chip opens the custom row', (
    tester,
  ) async {
    final sheet = AlertSheetRobot(tester);
    await openSheet(tester, initial: alert.copyWith(offsetMinutes: 7));

    expect(sheet.unitChoiceVisible, isTrue);
    expect(sheet.customLabel, '7 min before');
  });

  testWidgets('the Sound row belongs to the alarm tier alone', (tester) async {
    // A reminder plays through a notification channel whose sound Android
    // froze when the channel was created, so a control there would be a
    // promise nothing keeps: the row stands in its place, switched off.
    final sheet = AlertSheetRobot(tester);
    await openSheet(tester);
    expect(sheet.soundRowVisible, isTrue);
    expect(sheet.soundRowEnabled, isFalse);

    await sheet.chooseTier(AlertMode.ring);
    expect(sheet.soundRowEnabled, isTrue);
    // With nothing chosen the row defers, and says so rather than naming a
    // sound the app setting might not be on.
    expect(sheet.soundLabel, 'Use the app setting');
  });

  testWidgets('the sound rides Save untouched, tier flip included', (
    tester,
  ) async {
    // Both offset sets survive a tier flip; so does the sound, for the same
    // reason — the row dims, the value does not disappear.
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(
      tester,
      initial: alert.copyWith(mode: AlertMode.ring, sound: 'system:default'),
    );

    expect(sheet.soundLabel, "Phone's default alarm");
    await sheet.chooseTier(AlertMode.notify);
    await sheet.save();

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.mode, AlertMode.notify);
    expect(saved.alert.sound, 'system:default');
  });

  testWidgets('the settings defaults are offered no sound at all', (
    tester,
  ) async {
    // `alert_default_timed` encodes a tier and an offset and nothing else, so
    // a sound picked here would be discarded on Save.
    final sheet = AlertSheetRobot(tester);
    await openSheet(
      tester,
      initial: alert.copyWith(mode: AlertMode.ring),
      showSound: false,
    );

    expect(sheet.soundRowVisible, isFalse);
  });

  testWidgets('closing the sheet decides nothing', (tester) async {
    final sheet = AlertSheetRobot(tester);
    final result = await openSheet(tester);

    await sheet.close();

    expect(result.value, isNull);
  });

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(AlertEditorSheet), matching: matching);

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AlertEditorSheet)).height;

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(byId(id)).getSemanticsData();

  List<FormRowGroup> groupsOf(WidgetTester tester) => tester
      .widgetList<FormRowGroup>(inSheet(find.byType(FormRowGroup)))
      .toList();

  group('chrome and ways out', () {
    testWidgets('the header is a close, the title and a text Done on the save '
        'id', (tester) async {
      await openSheet(tester);

      expect(inSheet(find.byType(FormSheetHandle)), findsOneWidget);
      final header = tester.widget<FormSheetHeader>(
        inSheet(find.byType(FormSheetHeader)),
      );
      expect(header.title, 'Alert');
      expect(header.leadingIcon, Icons.close_rounded);
      expect(header.leadingIdentifier, SemanticsIds.alertSheetClose);
      expect(dataOf(tester, SemanticsIds.alertSheetClose).tooltip, 'Cancel');
      final done = tester.widget<FormHeaderTextButton>(
        inSheet(find.byType(FormHeaderTextButton)),
      );
      expect(done.label, 'Done');
      expect(done.identifier, SemanticsIds.alertSheetSave);
      expect(done.onPressed, isNotNull);
      // The filled Save is the event editor's alone.
      expect(inSheet(find.byType(FilledButton)), findsNothing);
    });

    final waysOut = <String, Future<void> Function(WidgetTester tester)>{
      'the barrier': (tester) => tester.tapAt(const Offset(10, 10)),
      'the system back': (tester) => tester.binding.handlePopRoute(),
      'a fling on the handle': (tester) => tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      ),
    };
    for (final way in waysOut.entries) {
      testWidgets('${way.key} decides nothing, a picked preset included', (
        tester,
      ) async {
        final sheet = AlertSheetRobot(tester);
        final result = await openSheet(tester);

        await sheet.choosePreset('30 min before');
        await way.value(tester);
        await tester.pumpAndSettle();

        expect(result.closed, isTrue);
        expect(result.value, isNull);
        expect(find.byType(AlertEditorSheet), findsNothing);
      });
    }

    testWidgets('an untouched sheet reports the alert it was given', (
      tester,
    ) async {
      // The id, the event and the hub's switch pass through, both offset sets
      // come back, and the sound and the time of day stay what they were.
      final sheet = AlertSheetRobot(tester);
      final initial = alert.copyWith(
        mode: AlertMode.ring,
        sound: 'system:default',
        enabled: false,
      );
      final result = await openSheet(
        tester,
        initial: initial,
        showRemoveAfter: true,
        removeAfterAlert: true,
      );

      await sheet.save();

      final saved = result.value as AlertEditorSaved;
      expect(saved.alert, initial);
      expect(saved.removeAfterAlert, isTrue);
    });

    testWidgets('an alert with no sound and no time of its own is reported '
        'with none', (tester) async {
      final sheet = AlertSheetRobot(tester);
      const bare = EventAlert(id: 'a2', eventId: 'e1', daysBefore: 1);
      final result = await openSheet(tester, initial: bare, allDay: true);

      // The row shows the setting's time; the alert still follows it.
      expect(sheet.timeOfDayLabel, '9:00 AM');
      await sheet.save();

      final saved = result.value as AlertEditorSaved;
      expect(saved.alert, bare);
      expect(saved.alert.dayMinute, isNull);
      expect(saved.alert.sound, isNull);
    });
  });

  group('the tier', () {
    testWidgets('Reminder comes before Alarm, each chip on its id', (
      tester,
    ) async {
      await openSheet(tester);

      final chips = tester
          .widgetList<FormChip>(inSheet(find.byType(FormChip)))
          .toList();
      expect([for (final chip in chips) chip.label], ['Reminder', 'Alarm']);
      expect(
        [for (final chip in chips) chip.identifier],
        [SemanticsIds.alertTypeReminder, SemanticsIds.alertTypeAlarm],
      );
      expect([for (final chip in chips) chip.selected], [isTrue, isFalse]);
      expect(
        dataOf(
          tester,
          SemanticsIds.alertTypeReminder,
        ).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        dataOf(tester, SemanticsIds.alertTypeAlarm).flagsCollection.isSelected,
        Tristate.isFalse,
      );
    });

    testWidgets('on the Reminder tier the sound row and the remove switch '
        'stay in place, dimmed, inert and announced disabled', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring),
        showRemoveAfter: true,
        removeAfterAlert: true,
      );
      const rows = [SemanticsIds.alertSound, SemanticsIds.alertRemoveAfter];
      final rects = [for (final id in rows) tester.getRect(byId(id))];
      for (final id in rows) {
        expect(dataOf(tester, id).hasAction(SemanticsAction.tap), isTrue);
      }

      await sheet.chooseTier(AlertMode.notify);

      expect([for (final id in rows) tester.getRect(byId(id))], rects);
      for (final id in rows) {
        final data = dataOf(tester, id);
        expect(data.hasAction(SemanticsAction.tap), isFalse, reason: id);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse, reason: id);
        final opacity = tester.widget<Opacity>(
          find.descendant(of: byId(id), matching: find.byType(Opacity)).first,
        );
        expect(opacity.opacity, FormMetrics.disabledOpacity, reason: id);
      }

      await tester.tap(byId(SemanticsIds.alertSound), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertSoundSheet), findsNothing);
      await tester.tap(
        byId(SemanticsIds.alertRemoveAfter),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(sheet.removeAfterValue, isFalse);
    });

    testWidgets('the remove switch is parked across a tier change, not '
        'dropped', (tester) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring),
        showRemoveAfter: true,
        removeAfterAlert: true,
      );
      expect(sheet.removeAfterValue, isTrue);

      await sheet.chooseTier(AlertMode.notify);
      expect(sheet.removeAfterEnabled, isFalse);
      expect(sheet.removeAfterValue, isFalse);

      await sheet.chooseTier(AlertMode.ring);
      expect(sheet.removeAfterEnabled, isTrue);
      expect(sheet.removeAfterValue, isTrue);
      await sheet.save();

      expect((result.value as AlertEditorSaved).removeAfterAlert, isTrue);
    });

    testWidgets('a switch turned off stays off across the round trip', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring),
        showRemoveAfter: true,
        removeAfterAlert: true,
      );

      await sheet.toggleRemoveAfter();
      await sheet.chooseTier(AlertMode.notify);
      await sheet.chooseTier(AlertMode.ring);
      expect(sheet.removeAfterValue, isFalse);
      await sheet.save();

      expect((result.value as AlertEditorSaved).removeAfterAlert, isFalse);
    });

    testWidgets('a reminder saved untouched hands the removal back as it '
        'came', (tester) async {
      // The flag is the event's, and belongs to whichever of its alerts
      // rings: confirming a reminder beside that alarm must not disarm it.
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        showRemoveAfter: true,
        removeAfterAlert: true,
      );
      expect(sheet.removeAfterEnabled, isFalse);
      expect(sheet.removeAfterValue, isFalse);

      await sheet.choosePreset('30 min before');
      await sheet.save();

      expect((result.value as AlertEditorSaved).removeAfterAlert, isTrue);
    });

    testWidgets('a reminder made an alarm shows the removal the event '
        'carries', (tester) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        showRemoveAfter: true,
        removeAfterAlert: true,
      );

      await sheet.chooseTier(AlertMode.ring);
      expect(sheet.removeAfterValue, isTrue);
      await sheet.chooseTier(AlertMode.notify);
      await sheet.save();

      // It was an alarm here and is saved a reminder: the removal goes.
      expect((result.value as AlertEditorSaved).removeAfterAlert, isFalse);
    });
  });

  group('When', () {
    SemanticsData item(WidgetTester tester, String id) => dataOf(tester, id);

    testWidgets('the menu lists the timed presets, then Custom…, with the '
        'current one checked', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester);

      expect(sheet.whenLabel, '10 min before');
      expect(sheet.whenChoices, [
        'At start',
        '5 min before',
        '10 min before',
        '15 min before',
        '30 min before',
        '1 h before',
        '1 day before',
        'Custom…',
      ]);

      await sheet.openWhenMenu();
      for (final minutes in [0, 5, 10, 15, 30, 60, 1440]) {
        final data = item(tester, SemanticsIds.alertWhenItem(minutes));
        expect(data.role, SemanticsRole.menuItemRadio, reason: '$minutes');
        expect(
          data.flagsCollection.isChecked,
          minutes == 10 ? CheckedState.isTrue : CheckedState.isFalse,
          reason: '$minutes',
        );
      }
      expect(
        item(tester, SemanticsIds.alertWhenCustom).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
    });

    testWidgets('an all-day event is offered days, on ids of their own', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, allDay: true);

      // Two days is no preset: the row names the count, without the time of
      // day the row under it holds, and Custom… is the checked item.
      expect(sheet.whenLabel, '2 days before');
      expect(sheet.whenChoices, [
        'On the day',
        'The day before',
        'A week before',
        'Custom…',
      ]);

      await sheet.openWhenMenu();
      for (final days in [0, 1, 7]) {
        expect(
          item(
            tester,
            SemanticsIds.alertWhenDayItem(days),
          ).flagsCollection.isChecked,
          CheckedState.isFalse,
          reason: '$days',
        );
      }
      expect(
        item(tester, SemanticsIds.alertWhenDayCustom).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      expect(byId(SemanticsIds.alertWhenCustom), findsNothing);
    });

    testWidgets('every timed preset is what Done reports', (tester) async {
      const presets = {
        'At start': 0,
        '5 min before': 5,
        '15 min before': 15,
        '1 h before': 60,
        '1 day before': 1440,
      };
      for (final preset in presets.entries) {
        final sheet = AlertSheetRobot(tester);
        final result = await openSheet(tester);

        await sheet.choosePreset(preset.key);
        expect(sheet.whenLabel, preset.key);
        expect(sheet.customChecked, isFalse, reason: preset.key);
        await sheet.save();

        expect(
          (result.value as AlertEditorSaved).alert.offsetMinutes,
          preset.value,
          reason: preset.key,
        );
      }
    });

    testWidgets('every all-day preset is what Done reports', (tester) async {
      const presets = {
        'On the day': 0,
        'The day before': 1,
        'A week before': 7,
      };
      for (final preset in presets.entries) {
        final sheet = AlertSheetRobot(tester);
        final result = await openSheet(tester, allDay: true);

        await sheet.choosePreset(preset.key);
        expect(sheet.whenLabel, preset.key);
        await sheet.save();

        final saved = (result.value as AlertEditorSaved).alert;
        expect(saved.daysBefore, preset.value, reason: preset.key);
        expect(saved.offsetMinutes, 10, reason: preset.key);
        expect(saved.dayMinute, 8 * 60, reason: preset.key);
      }
    });

    testWidgets('a dismissed menu changes nothing', (tester) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(tester);

      await sheet.openWhenMenu();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(AlertEditorSheet), findsOneWidget);
      expect(sheet.whenLabel, '10 min before');
      await sheet.save();
      expect((result.value as AlertEditorSaved).alert.offsetMinutes, 10);
    });
  });

  group('Custom', () {
    testWidgets('opening it on "At start" writes nothing: backing out leaves '
        'the alert at start', (tester) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        initial: alert.copyWith(offsetMinutes: 0),
      );

      await sheet.openCustom();
      expect(sheet.customOpen, isTrue);
      // The stepper cannot count zero, so it stands on one minute — a number
      // the sheet behind it has not been given.
      expect(sheet.customValue, 1);
      expect(sheet.customLabel, '1 min before');
      expect(sheet.whenLabel, 'At start');

      await sheet.cancelCustom();
      expect(sheet.customOpen, isFalse);
      expect(sheet.whenLabel, 'At start');
      await sheet.save();

      expect((result.value as AlertEditorSaved).alert.offsetMinutes, 0);
    });

    testWidgets('45 minutes from "At start" is confirmed only by its Done', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        initial: alert.copyWith(offsetMinutes: 0),
      );

      await sheet.openCustom();
      for (var minute = 1; minute < 45; minute++) {
        await sheet.stepCustom(up: true);
      }
      expect(sheet.customLabel, '45 min before');
      expect(sheet.whenLabel, 'At start');

      await sheet.confirmCustom();
      expect(sheet.customOpen, isFalse);
      expect(sheet.whenLabel, '45 min before');
      // No preset says 45 minutes, so Custom… is what the menu checks.
      expect(sheet.customChecked, isTrue);
      await sheet.save();

      expect((result.value as AlertEditorSaved).alert.offsetMinutes, 45);
    });

    for (final uncountable in const [
      (stored: 90, label: '90 min before', clamped: 59, read: '59 min before'),
      (
        stored: 36 * 60,
        label: '36 h before',
        clamped: 23 * 60,
        read: '23 h before',
      ),
    ]) {
      testWidgets('${uncountable.label} is kept until Done confirms the value '
          'the stepper clamped it to', (tester) async {
        final sheet = AlertSheetRobot(tester);
        final result = await openSheet(
          tester,
          initial: alert.copyWith(offsetMinutes: uncountable.stored),
        );
        expect(sheet.whenLabel, uncountable.label);
        expect(sheet.customChecked, isTrue);

        await sheet.openCustom();
        expect(sheet.customLabel, uncountable.read);
        expect(sheet.canStepCustom(up: true), isFalse);
        expect(sheet.whenLabel, uncountable.label);
        await sheet.cancelCustom();
        expect(sheet.whenLabel, uncountable.label);

        await sheet.openCustom();
        await sheet.confirmCustom();
        expect(sheet.whenLabel, uncountable.read);
        await sheet.save();

        expect(
          (result.value as AlertEditorSaved).alert.offsetMinutes,
          uncountable.clamped,
        );
      });
    }

    testWidgets('a custom value that is a preset reads as that preset', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, initial: alert.copyWith(offsetMinutes: 7));
      expect(sheet.customChecked, isTrue);

      await sheet.openCustom();
      // The unit choice the first sheet showed inline is here, on its ids.
      expect(sheet.unitChoiceVisible, isTrue);
      await sheet.stepCustom(up: false);
      await sheet.stepCustom(up: false);
      await sheet.confirmCustom();

      expect(sheet.whenLabel, '5 min before');
      expect(sheet.customChecked, isFalse);
      await sheet.openWhenMenu();
      expect(
        dataOf(tester, SemanticsIds.alertWhenItem(5)).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
    });

    testWidgets('an all-day event counts in days and nothing else', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(tester, allDay: true);

      await sheet.openCustom();
      expect(sheet.unitChoiceVisible, isFalse);
      expect(sheet.customValue, 2);
      await sheet.stepCustom(up: true);
      expect(sheet.customLabel, '3 days before');
      await sheet.confirmCustom();
      expect(sheet.whenLabel, '3 days before');
      await sheet.save();

      final saved = (result.value as AlertEditorSaved).alert;
      expect(saved.daysBefore, 3);
      // The set the form never showed comes back exactly as it went in.
      expect(saved.offsetMinutes, 10);
      expect(saved.dayMinute, 8 * 60);
    });

    testWidgets('on an all-day event Custom reads a day count the way the '
        'When row will after Done', (tester) async {
      // One wording for both, the row's own: a day and a week have names,
      // every other count is a number of days.
      const wordings = {
        1: 'The day before',
        7: 'A week before',
        3: '3 days before',
      };
      for (final wording in wordings.entries) {
        final reason = '${wording.key} days';
        final sheet = AlertSheetRobot(tester);
        final result = await openSheet(tester, allDay: true);

        await sheet.openCustom();
        while (sheet.customValue != wording.key) {
          await sheet.stepCustom(up: sheet.customValue < wording.key);
        }
        expect(sheet.customLabel, wording.value, reason: reason);
        await sheet.confirmCustom();
        expect(sheet.whenLabel, wording.value, reason: reason);
        await sheet.save();

        expect(
          (result.value as AlertEditorSaved).alert.daysBefore,
          wording.key,
          reason: reason,
        );
      }
    });

    testWidgets('the barrier and the system back leave Custom without '
        'writing, and the sheet behind stays', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester);

      await sheet.openCustom();
      await sheet.stepCustom(up: true);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(AlertOffsetSheet), findsNothing);
      expect(find.byType(AlertEditorSheet), findsOneWidget);
      expect(sheet.whenLabel, '10 min before');

      await sheet.openCustom();
      await sheet.stepCustom(up: true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertOffsetSheet), findsNothing);
      expect(find.byType(AlertEditorSheet), findsOneWidget);
      expect(sheet.whenLabel, '10 min before');
    });
  });

  group('time of day and sound', () {
    // The time pad reads the haptics setting as it opens, so the cases that
    // raise it need a settings backend bound.
    late AppDatabase db;

    setUp(() async {
      SettingsService.reset();
      db = await openTestDatabase();
      SettingsService.forTesting(db);
    });

    tearDown(() async {
      SettingsService.reset();
      await db.close();
    });

    testWidgets("the Time of day row follows the phone's clock", (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, allDay: true);
      expect(sheet.timeOfDayLabel, '8:00 AM');
    });

    testWidgets('on a 24-hour phone the Time of day row reads 24-hour', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, allDay: true, use24HourFormat: true);
      expect(sheet.timeOfDayLabel, '08:00');
    });

    testWidgets('a timed event has no Time of day row', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester);
      expect(sheet.timeOfDayVisible, isFalse);
    });

    testWidgets('a picked time of day is what Done reports', (tester) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(tester, allDay: true);

      await sheet.pickTimeOfDay(const TimeOfDay(hour: 20, minute: 30));
      expect(find.byType(TimePadSheet), findsNothing);
      expect(sheet.timeOfDayLabel, '8:30 PM');
      await sheet.save();

      final saved = (result.value as AlertEditorSaved).alert;
      expect(saved.dayMinute, 20 * 60 + 30);
      expect(saved.daysBefore, 2);
      expect(saved.offsetMinutes, 10);
    });

    testWidgets('the settings default round-trips a tier, a day count and a '
        'time of day', (tester) async {
      // The Calendar settings open the sheet with no sound row and nothing
      // else different: what it reports is what the page writes.
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(tester, allDay: true, showSound: false);

      await sheet.chooseTier(AlertMode.ring);
      await sheet.choosePreset('A week before');
      await sheet.pickTimeOfDay(const TimeOfDay(hour: 7, minute: 15));
      await sheet.save();

      final saved = (result.value as AlertEditorSaved).alert;
      expect(saved.mode, AlertMode.ring);
      expect(saved.daysBefore, 7);
      expect(saved.dayMinute, 7 * 60 + 15);
    });

    testWidgets('the time pad opens under the row\'s own name', (tester) async {
      await openSheet(tester, allDay: true);

      await tester.tap(byId(SemanticsIds.alertTimeOfDay));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(TimePadSheet),
          matching: find.text('Time of day'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a picked sound is what Done reports', (tester) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring),
      );
      expect(sheet.soundLabel, 'Use the app setting');

      await sheet.tapSoundRow();
      await tester.tap(byId(SemanticsIds.soundPhoneDefault));
      await tester.pumpAndSettle();
      expect(find.byType(AlertSoundSheet), findsNothing);
      expect(sheet.soundLabel, "Phone's default alarm");
      await sheet.save();

      expect((result.value as AlertEditorSaved).alert.sound, 'system:default');
    });

    testWidgets('a sound sheet left through its ✕ keeps the sound', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      final result = await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring, sound: 'system:default'),
      );

      await sheet.tapSoundRow();
      await tester.tap(byId(SemanticsIds.soundClose));
      await tester.pumpAndSettle();
      await sheet.save();

      expect((result.value as AlertEditorSaved).alert.sound, 'system:default');
    });

    testWidgets('a phone with no sound picker is told so above the sheet, '
        'where a finger can reach the message', (tester) async {
      GetIt.I.registerSingleton<AlertGateway>(const _NoPickerGateway());
      addTearDown(() => GetIt.I.unregister<AlertGateway>());
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, initial: alert.copyWith(mode: AlertMode.ring));

      await sheet.tapSoundRow();
      await tester.tap(byId(SemanticsIds.soundFromPhone));
      await tester.pumpAndSettle();

      // This sheet is itself a route above the page, so a bar on the page's
      // `Scaffold` would be drawn under it; the message is raised in the
      // overlay, the topmost thing where it stands, the sheet still open.
      final message = find.text('This phone has no sound picker');
      expect(message.hitTestable(), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertEditorSheet), findsOneWidget);
      expect(find.byType(AlertSoundSheet), findsNothing);
      expect(sheet.soundLabel, 'Use the app setting');
    });

    testWidgets("the Time of day row's flash takes the group's radius, so "
        "the group's clip does not shave its bottom corners", (tester) async {
      await openSheet(tester, allDay: true);

      final highlight = tester.widget<ValueChangeHighlight>(
        find.ancestor(
          of: byId(SemanticsIds.alertTimeOfDay),
          matching: find.byType(ValueChangeHighlight),
        ),
      );
      expect(
        highlight.borderRadius,
        const BorderRadius.all(Radius.circular(RowMetrics.groupRadius)),
      );
      // The row is the last of its group, flush with the corners the
      // group's clipped surface rounds (the group's own box carries the air
      // below it).
      final surface = find
          .descendant(
            of: find.ancestor(
              of: byId(SemanticsIds.alertTimeOfDay),
              matching: find.byType(FormRowGroup),
            ),
            matching: find.byType(Material),
          )
          .first;
      expect(
        tester.getRect(byId(SemanticsIds.alertTimeOfDay)).bottomRight,
        tester.getRect(surface).bottomRight,
      );
    });
  });

  group('the rows each caller is offered', () {
    /// How many rows each group holds, top to bottom.
    List<int> shape(WidgetTester tester) => [
      for (final group in groupsOf(tester)) group.children.length,
    ];

    /// The same rows and the same height on both tiers: nothing comes or
    /// goes with the Type chips.
    Future<void> expectSameOnBothTiers(
      WidgetTester tester,
      AlertSheetRobot sheet,
    ) async {
      final rows = shape(tester);
      final height = sheetHeight(tester);
      // Under its clamp, or two equal heights would prove nothing.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(height, lessThan(screen.height * FormMetrics.sheetHeightFactor));
      await sheet.chooseTier(AlertMode.ring);
      expect(shape(tester), rows);
      expect(sheetHeight(tester), height);
      await sheet.chooseTier(AlertMode.notify);
      expect(shape(tester), rows);
      expect(sheetHeight(tester), height);
    }

    testWidgets('the editor on a one-time event: every row', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, showRemoveAfter: true);

      expect(shape(tester), [1, 1, 2, 1]);
      expect(sheet.soundRowVisible, isTrue);
      expect(sheet.removeAfterVisible, isTrue);
      expect(sheet.removeAlertVisible, isTrue);
      await expectSameOnBothTiers(tester, sheet);
    });

    testWidgets('the editor on a repeating event: no remove switch on either '
        'tier', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester);

      expect(shape(tester), [1, 1, 1, 1]);
      expect(sheet.soundRowVisible, isTrue);
      expect(sheet.removeAfterVisible, isFalse);
      await expectSameOnBothTiers(tester, sheet);
      await sheet.chooseTier(AlertMode.ring);
      expect(sheet.removeAfterVisible, isFalse);
    });

    testWidgets('the editor adding an alert: nothing to remove', (
      tester,
    ) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, canRemove: false, showRemoveAfter: true);

      expect(shape(tester), [1, 1, 2]);
      expect(sheet.removeAlertVisible, isFalse);
      await expectSameOnBothTiers(tester, sheet);
    });

    testWidgets('the settings default: neither a sound nor the removal, so '
        'no third group', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, showSound: false);

      expect(shape(tester), [1, 1, 1]);
      expect(sheet.soundRowVisible, isFalse);
      expect(sheet.removeAfterVisible, isFalse);
      expect(sheet.removeAlertVisible, isTrue);
      await expectSameOnBothTiers(tester, sheet);
    });

    testWidgets('the settings default for an all-day event adds the Time of '
        'day row and nothing else', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, allDay: true, showSound: false);

      expect(shape(tester), [1, 2, 1]);
      expect(sheet.timeOfDayVisible, isTrue);
      await expectSameOnBothTiers(tester, sheet);
    });

    testWidgets('only the last group drops its trailing gap, whichever it '
        'is', (tester) async {
      await openSheet(tester, showRemoveAfter: true);
      expect(
        [for (final group in groupsOf(tester)) group.trailingGap],
        [true, true, true, false],
      );
      await AlertSheetRobot(tester).close();

      await openSheet(tester, canRemove: false, showSound: false);
      expect(
        [for (final group in groupsOf(tester)) group.trailingGap],
        [true, false],
      );
    });

    testWidgets('every row carries its id', (tester) async {
      await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring),
        allDay: true,
        showRemoveAfter: true,
      );

      for (final id in [
        SemanticsIds.alertSheetClose,
        SemanticsIds.alertSheetSave,
        SemanticsIds.alertTypeReminder,
        SemanticsIds.alertTypeAlarm,
        SemanticsIds.alertWhen,
        SemanticsIds.alertTimeOfDay,
        SemanticsIds.alertSound,
        SemanticsIds.alertRemoveAfter,
        SemanticsIds.alertRemove,
      ]) {
        expect(byId(id), findsOneWidget, reason: id);
        expect(dataOf(tester, id).identifier, id);
      }
      // One announcement per row: the label and the value in the row's node.
      expect(
        dataOf(tester, SemanticsIds.alertWhen).label,
        allOf(contains('When'), contains('2 days before')),
      );
      expect(
        dataOf(tester, SemanticsIds.alertTimeOfDay).label,
        allOf(contains('Time of day'), contains('8:00 AM')),
      );
      expect(
        dataOf(tester, SemanticsIds.alertRemoveAfter).label,
        contains('Remove after it rings'),
      );
    });
  });

  group('nothing moves', () {
    const phone = Size(360, 780);
    const notifyHint =
        'Sits in the shade with Snooze and Done. Silent mode and Focus apply.';
    const ringHint = 'Plays on the alarm stream until you stop or snooze it.';
    const fullScreenOff =
        'Full-screen alarms are off, so this rings as a banner instead of '
        'taking over the screen.';

    /// A permission service whose answer arrives when [FakePermissionGateway
    /// .statusGate] is completed — the round trip the sheet does not wait for.
    FakePermissionGateway bindPermissions(
      Map<AppPermission, PermissionStatus> statuses,
    ) {
      final gateway = FakePermissionGateway(statuses: statuses)
        ..statusGate = Completer<void>();
      final permissions = permissionServiceOver(gateway);
      GetIt.I.registerSingleton<PermissionService>(permissions);
      addTearDown(() async {
        await GetIt.I.unregister<PermissionService>();
        await permissions.dispose();
      });
      return gateway;
    }

    Finder slot() => inSheet(find.byType(FormCaptionSlot));

    Finder shown(String text) => find.text(text).hitTestable();

    Map<String, Rect> rowRects(WidgetTester tester) => {
      for (final id in [
        SemanticsIds.alertWhen,
        SemanticsIds.alertSound,
        SemanticsIds.alertRemoveAfter,
        SemanticsIds.alertRemove,
      ])
        id: tester.getRect(byId(id)),
    };

    testWidgets('the caption slot and the sheet keep their height across the '
        'tier and a late full-screen answer', (tester) async {
      final gateway = bindPermissions(const {
        AppPermission.fullScreenIntent: PermissionStatus.denied,
      });
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, showRemoveAfter: true, surface: phone);

      // At this width the three lines the slot can say take a different
      // number of lines each, so a bare caption would move the rows.
      double candidateHeight(String text) =>
          tester.getSize(find.text(text).first).height;
      expect(candidateHeight(ringHint), lessThan(candidateHeight(notifyHint)));
      expect(
        candidateHeight(notifyHint),
        lessThan(candidateHeight(fullScreenOff)),
      );

      final height = sheetHeight(tester);
      final slotHeight = tester.getSize(slot()).height;
      final rows = rowRects(tester);
      expect(slotHeight, candidateHeight(fullScreenOff));
      // Under its clamp, or an unchanged height would prove nothing.
      expect(height, lessThan(phone.height * FormMetrics.sheetHeightFactor));
      void expectUnmoved(String state) {
        expect(tester.getSize(slot()).height, slotHeight, reason: state);
        expect(sheetHeight(tester), height, reason: state);
        expect(rowRects(tester), rows, reason: state);
      }

      expect(shown(notifyHint), findsOneWidget);

      await sheet.chooseTier(AlertMode.ring);
      expectUnmoved('Alarm, before the answer');
      expect(shown(ringHint), findsOneWidget);
      // No answer yet is not a no: a slow platform is never accused.
      expect(shown(fullScreenOff), findsNothing);

      gateway.statusGate!.complete();
      await tester.pumpAndSettle();
      expectUnmoved('Alarm, full-screen alarms off');
      expect(shown(fullScreenOff), findsOneWidget);
      expect(shown(ringHint), findsNothing);
      expect(
        tester.widget<Text>(shown(fullScreenOff)).style!.color,
        Theme.of(tester.element(slot())).colorScheme.error,
      );

      await sheet.chooseTier(AlertMode.notify);
      expectUnmoved('Reminder, after the answer');
      expect(shown(notifyHint), findsOneWidget);
      expect(shown(fullScreenOff), findsNothing);
    });

    testWidgets('a phone that allows full-screen alarms is never warned', (
      tester,
    ) async {
      final gateway = bindPermissions(allGranted);
      final sheet = AlertSheetRobot(tester);
      await openSheet(tester, initial: alert.copyWith(mode: AlertMode.ring));

      gateway.statusGate!.complete();
      await tester.pumpAndSettle();

      expect(shown(ringHint), findsOneWidget);
      expect(shown(fullScreenOff), findsNothing);
      await sheet.chooseTier(AlertMode.notify);
      expect(shown(fullScreenOff), findsNothing);
    });

    testWidgets('only the shown caption is announced', (tester) async {
      await openSheet(tester);

      expect(find.semantics.byLabel(notifyHint), findsOne);
      expect(find.semantics.byLabel(ringHint), findsNothing);
      expect(find.semantics.byLabel(fullScreenOff), findsNothing);
    });

    testWidgets('the header\'s hairline follows the body: on while it is '
        'scrolled over a bottom inset, off once the inset is gone and the '
        'sheet no longer scrolls', (tester) async {
      await openSheet(tester, showRemoveAfter: true, surface: phone);
      final body = inSheet(find.byType(SingleChildScrollView));
      final scrolled = tester
          .widget<FormSheetHeader>(inSheet(find.byType(FormSheetHeader)))
          .scrolled!;
      double offset() => tester
          .state<ScrollableState>(
            find.descendant(of: body, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels;
      expect(scrolled.value, isFalse);

      // The sheet has no field of its own, but its body is padded by whatever
      // bottom inset the window reports, and an inset is the plainest way to
      // make a body shorter under its own scroll offset.
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(scrolled.value, isFalse);
      await tester.drag(body, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(offset(), greaterThan(0));
      expect(scrolled.value, isTrue);

      // Back at its top without a scroll: no listener on a scroll controller
      // hears of it.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(offset(), 0);
      expect(scrolled.value, isFalse);
    });

    testWidgets('on a 360 × 780 phone nothing overflows and every control '
        'keeps a 48 dp target', (tester) async {
      await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring),
        allDay: true,
        showRemoveAfter: true,
        surface: phone,
      );

      expect(tester.takeException(), isNull);
      // The test font draws every glyph a full em wide, about twice a
      // phone's, so the captions run to more lines here than on a device and
      // the sheet reaches its clamp; whether it fits unscrolled is the device
      // pass's to see. What holds at any font is the clamp and the targets.
      expect(sheetHeight(tester), lessThanOrEqualTo(phone.height * 0.92));
      for (final chip in inSheet(find.byType(FormChip)).evaluate()) {
        expect(
          tester.getSize(find.byWidget(chip.widget)).height,
          FormMetrics.chipTapTarget,
        );
      }
      for (final id in [
        SemanticsIds.alertWhen,
        SemanticsIds.alertTimeOfDay,
        SemanticsIds.alertSound,
        SemanticsIds.alertRemoveAfter,
        SemanticsIds.alertRemove,
      ]) {
        await tester.ensureVisible(byId(id));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: id);
        expect(
          tester.getSize(byId(id)).height,
          greaterThanOrEqualTo(FormMetrics.rowMinHeight),
          reason: id,
        );
        expect(
          tester.getRect(byId(id)).right,
          lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
          reason: id,
        );
      }
      expect(
        tester.getSize(byId(SemanticsIds.alertSheetClose)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(byId(SemanticsIds.alertSheetSave)).height,
        FormMetrics.headerHeight,
      );
    });

    testWidgets('German at text scale 2.0 on a 360 × 780 phone lays out '
        'without overflow and every label reads whole', (tester) async {
      final sheet = AlertSheetRobot(tester);
      await openSheet(
        tester,
        initial: alert.copyWith(mode: AlertMode.ring),
        allDay: true,
        showRemoveAfter: true,
        removeAfterAlert: true,
        surface: phone,
        locale: const Locale('de'),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(sheetHeight(tester), lessThanOrEqualTo(phone.height * 0.92));
      expect(
        tester
            .widget<FormHeaderTextButton>(
              inSheet(find.byType(FormHeaderTextButton)),
            )
            .label,
        'Fertig',
      );

      // A label wraps as far as it needs to and is never cut: no line limit,
      // a box as tall as its text, inside the group. The two Type chips are
      // in the list since their 32 dp became a minimum; a fixed chip cut its
      // label at this scale.
      for (final label in [
        'Art',
        'Mitteilung',
        'Alarm',
        'Wann',
        'Uhrzeit',
        'Weckton',
        'Nach dem Klingeln entfernen',
        'Erinnerung entfernen',
      ]) {
        final text = inSheet(find.text(label));
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
        expect(tester.widget<Text>(text).maxLines, isNull, reason: label);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
          paragraph.size.height,
          moreOrLessEquals(
            paragraph.getMaxIntrinsicHeight(paragraph.size.width),
            epsilon: 0.01,
          ),
          reason: label,
        );
        final rect = tester.getRect(text);
        expect(rect.left, greaterThanOrEqualTo(RowMetrics.groupInset));
        expect(
          rect.right,
          lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
          reason: label,
        );
      }
      for (final chip in inSheet(find.byType(FormChip)).evaluate()) {
        expect(
          tester.getSize(find.byWidget(chip.widget)).height,
          greaterThanOrEqualTo(FormMetrics.chipTapTarget),
        );
      }
      // The tier's line wraps whole as well. It is in the tree twice, the
      // copy that sizes the slot first and the one on screen last.
      final hint = inSheet(
        find.text('Spielt über den Weckton, bis du stoppst oder schlummerst.'),
      ).last;
      expect(tester.widget<Text>(hint).maxLines, isNull);
      expect(
        tester.getRect(hint).right,
        lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
      );
      // The same slot at this scale: the three German lines differ too.
      final slotHeight = tester.getSize(slot()).height;
      await sheet.chooseTier(AlertMode.notify);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(slot()).height, slotHeight);

      // The menu and the sub-sheet behind it open at this scale as well.
      await sheet.openCustom();
      expect(tester.takeException(), isNull);
      expect(sheet.customOpen, isTrue);
      await sheet.confirmCustom();
      await sheet.save();
      expect(tester.takeException(), isNull);
    });
  });
}

/// A phone with a sound picker to offer and no activity behind it.
class _NoPickerGateway extends NoOpAlertGateway {
  const _NoPickerGateway();

  @override
  bool get supportsSoundPicker => true;

  @override
  Future<PickedAlertSound?> pickSystemSound(String? current) async {
    throw const AlertSoundPickerUnavailable();
  }
}

class _Result {
  AlertEditorResult? value;

  /// Whether the sheet has closed, which a `null` [value] alone cannot say.
  bool closed = false;
}
