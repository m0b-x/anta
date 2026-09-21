import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';

/// The sheet edits a **draft** and reports it on Save, so what is worth
/// pinning is the round trip: a chip tap, a tier change and the remove switch
/// all have to survive it, and the offset set the form is *not* showing has to
/// come back untouched — that is the whole promise `EventAlert` makes about an
/// event flipped between timed and all-day.
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

  Future<_Result> openSheet(
    WidgetTester tester, {
    EventAlert initial = alert,
    bool allDay = false,
    bool canRemove = true,
    bool showSound = true,
    bool showRemoveAfter = false,
    bool removeAfterAlert = false,
  }) async {
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
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

  /// The sheet is 70% of the screen and the footer sits under the timing
  /// section, so everything below the chips has to be reached first.
  Future<void> scrollTo(WidgetTester tester, Finder target) {
    return tester.dragUntilVisible(
      target,
      find.byType(SingleChildScrollView).first,
      const Offset(0, -80),
    );
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
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
    final result = await openSheet(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '30 min before'));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.offsetMinutes, 30);
    // The set the form never showed comes back exactly as it went in.
    expect(saved.alert.daysBefore, 2);
    expect(saved.alert.dayMinute, 8 * 60);
  });

  testWidgets('an all-day event is asked for days, not minutes', (
    tester,
  ) async {
    final result = await openSheet(tester, allDay: true);

    expect(find.widgetWithText(ChoiceChip, '30 min before'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'The day before'));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.daysBefore, 1);
    expect(saved.alert.offsetMinutes, 10);
  });

  testWidgets('the tier survives the round trip', (tester) async {
    final result = await openSheet(tester);

    await tester.tap(find.text('Alarm'));
    await tester.pumpAndSettle();
    await save(tester);

    expect((result.value as AlertEditorSaved).alert.mode, AlertMode.ring);
  });

  testWidgets('the remove switch is offered for an alarm and rides the result',
      (tester) async {
    final result = await openSheet(tester, showRemoveAfter: true);

    // A reminder cannot be what deletes an event, so the switch is not there
    // until the tier is.
    expect(find.text('Remove after it rings'), findsNothing);
    await tester.tap(find.text('Alarm'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = result.value as AlertEditorSaved;
    expect(saved.removeAfterAlert, isTrue);
  });

  testWidgets('going back to a reminder disarms the removal', (tester) async {
    final result = await openSheet(
      tester,
      initial: alert.copyWith(mode: AlertMode.ring),
      showRemoveAfter: true,
      removeAfterAlert: true,
    );

    expect(find.text('Remove after it rings'), findsOneWidget);
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.mode, AlertMode.notify);
    expect(saved.removeAfterAlert, isFalse);
  });

  testWidgets('Remove alert reports a removal, not a save', (tester) async {
    final result = await openSheet(tester);

    await scrollTo(tester, find.widgetWithText(FilledButton, 'Remove alert'));
    await tester.tap(find.widgetWithText(FilledButton, 'Remove alert'));
    await tester.pumpAndSettle();

    expect(result.value, isA<AlertEditorRemoved>());
  });

  testWidgets('a draft with nothing to remove offers no removal', (
    tester,
  ) async {
    await openSheet(tester, canRemove: false);

    expect(find.text('Remove alert'), findsNothing);
  });

  testWidgets('the custom row counts in the unit it is set to', (tester) async {
    final result = await openSheet(tester);

    await scrollTo(tester, find.widgetWithText(ChoiceChip, 'Custom'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Hours'));
    await tester.tap(find.text('Hours'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byTooltip('More time before'));
    await tester.tap(find.byTooltip('More time before'));
    await tester.pumpAndSettle();
    await save(tester);

    // The number survives the unit change — ten minutes becomes ten hours,
    // the way every stepper with a unit beside it behaves — and the step
    // takes it to eleven.
    expect((result.value as AlertEditorSaved).alert.offsetMinutes, 11 * 60);
  });

  testWidgets('an offset that matches no chip opens the custom row', (
    tester,
  ) async {
    await openSheet(tester, initial: alert.copyWith(offsetMinutes: 7));

    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('7 min before'), findsOneWidget);
  });

  testWidgets('the Sound row belongs to the alarm tier alone', (tester) async {
    // A reminder plays through a notification channel whose sound Android
    // froze when the channel was created, so a control there would be a
    // promise nothing keeps.
    await openSheet(tester);
    expect(find.text('Alarm sound'), findsNothing);

    await tester.tap(find.text('Alarm'));
    await tester.pumpAndSettle();
    expect(find.text('Alarm sound'), findsOneWidget);
    // With nothing chosen the row defers, and says so rather than naming a
    // sound the app setting might not be on.
    expect(find.text('Use the app setting'), findsOneWidget);
  });

  testWidgets('the sound rides Save untouched, tier flip included', (
    tester,
  ) async {
    // Both offset sets survive a tier flip; so does the sound, for the same
    // reason — the row hides, the value does not disappear.
    final result = await openSheet(
      tester,
      initial: alert.copyWith(mode: AlertMode.ring, sound: 'system:default'),
    );

    expect(find.text("Phone's default alarm"), findsOneWidget);
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await save(tester);

    final saved = result.value as AlertEditorSaved;
    expect(saved.alert.mode, AlertMode.notify);
    expect(saved.alert.sound, 'system:default');
  });

  testWidgets('the settings defaults are offered no sound at all', (
    tester,
  ) async {
    // `alert_default_timed` encodes a tier and an offset and nothing else, so
    // a sound picked here would be discarded on Save.
    await openSheet(
      tester,
      initial: alert.copyWith(mode: AlertMode.ring),
      showSound: false,
    );

    expect(find.text('Alarm sound'), findsNothing);
  });

  testWidgets('closing the sheet decides nothing', (tester) async {
    final result = await openSheet(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(result.value, isNull);
  });
}

class _Result {
  AlertEditorResult? value;
}
