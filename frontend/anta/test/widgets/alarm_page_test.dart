import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/alarm_metrics.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/controllers/alert_ring_controller.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_keep_notice.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/lock_screen_state.dart';
import 'package:anta/utils/quick_alarm.dart';
import 'package:anta/widgets/alarm_ground.dart';

import 'support/alarm_page_fakes.dart';
import 'support/alarm_page_robot.dart';

/// The full-screen ring surface.
///
/// **No harness at all**, and that is the point of the page: it renders from
/// the payload alone — no `path_provider`, no `SharedPreferences`, no
/// database, no gateway — because a ring arrives in a process where nothing is
/// loaded yet and may belong to a database that is not even open. Every
/// service call the controller makes is best-effort and swallows its own
/// failure, so the page draws identically here and on a phone.
///
/// **Clearance.** The page has no text field and raises no keyboard — the
/// first case pins that it never grows one — but it resumes the app, and an
/// Android activity paused mid keyboard-inset animation comes back with
/// `viewInsets.bottom` stuck at the keyboard height. The page stands in a
/// `Scaffold`, which takes that inset out of its body, so the dock is lifted
/// clear of it; and under the dock is `AlarmMetrics.dockBottomPadding` plus
/// the system's own bottom inset as the `Scaffold` reports it inside its
/// body — nothing, while an inset stands. That is the sheets'
/// `max(viewInsets, viewPadding)` rule, reached by a page: the layout group
/// pins both halves, and what happens when the inset leaves the body too
/// short to pin a dock at all. The suite draws every phone with a status bar
/// and a gesture bar (`AlarmPageRobot.systemBar`), since both of those
/// insets are what the clearance is made of.
///
/// **Through the robot.** Nothing here names a widget: `AlarmPageRobot` is
/// the one place that knows how the page is put together, so a redraw of the
/// page rewrites the robot and these bodies keep saying what the page has to
/// do. The cases down to "on a locked phone" that are not in a group were
/// written against the page as it stood on 2026-10-04, before it was redrawn
/// as a takeover page, and were carried over it; their bodies changed only
/// where `docs/alert-surfaces-redesign-roadmap.md` §4.2 changes the page on
/// purpose. Two of them were named `DEFECT` and pinned a wrong pop; they now
/// say what holds.
///
/// **The test font is about twice as wide as a phone's**, so a label that
/// sits on one line on a device wraps here. The layout cases therefore
/// assert that nothing overflows and where things are, never how many lines
/// a label takes.
void main() {
  final l10n = AppLocalizationsEn();

  /// When the suite's ring was due: Sunday's 07:00.
  final due = DateTime(2026, 9, 20, 7);

  /// [older] is an entry armed by a build that stamped none of the optional
  /// facts: no due instant, so the page has only the frozen label and the
  /// occurrence's day; no resolved avatar.
  AlertPayload payload({
    bool removeAfterAlert = false,
    bool test = false,
    String database = 'gym_notes',
    int snoozeMinutes = 10,
    String title = 'Leg day',
    int osId = 4242,
    String timeLabel = '07:00',
    DateTime? dueAt,
    bool older = false,
    bool snooze = false,
    bool reRing = false,
    String whenLabel = '',
    String excerpt = '',
    int? tintValue,
    String? glyphKey,
  }) {
    return AlertPayload(
      database: database,
      eventId: test ? AlertPayload.testEventId : 'e1',
      alertId: test ? AlertPayload.testEventId : 'a1',
      dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
      osId: osId,
      mode: AlertMode.ring,
      title: title,
      timeLabel: timeLabel,
      categoryId: 'gym',
      removeAfterAlert: removeAfterAlert,
      // A test ring is registered as a snooze, and wears the app's own
      // colour and the alarm glyph: what the scheduler stamps.
      snooze: snooze || test,
      snoozeMinutes: snoozeMinutes,
      fireAtMs: older ? null : (dueAt ?? due).millisecondsSinceEpoch,
      reRing: reRing,
      whenLabel: whenLabel,
      excerpt: excerpt,
      tintValue:
          tintValue ??
          (test && !older ? AppTheme.lightScheme.primary.toARGB32() : null),
      glyphKey: glyphKey ?? (test && !older ? kQuickAlarmIconKey : null),
    );
  }

  testWidgets('it draws the ring from the payload alone', (tester) async {
    final page = AlarmPageRobot(tester);
    await page.pumpPage(payload());

    expect(page.eyebrow, l10n.alarmPageTitle.toUpperCase());
    // Written the way the phone writes a time, and the test phone is on the
    // 12-hour clock.
    expect(page.time, '7:00 AM');
    expect(page.title, 'Leg day');
    // The day the ring was due, in the app's locale rather than the
    // payload's raw instant.
    expect(page.dayLine, contains('September'));
    // Nothing that could raise a keyboard of its own. An inset left standing
    // by the app the page resumes reaches it all the same: that hazard is the
    // layout group's (the header's "Clearance").
    expect(page.hasTextField, isFalse);
  });

  testWidgets('every action is there, and Snooze names the payload length', (
    tester,
  ) async {
    final page = AlarmPageRobot(tester);
    await page.pumpPage(payload(snoozeMinutes: 15));

    expect(page.labelOf(AlarmAction.stop), l10n.alarmStop);
    expect(page.labelOf(AlarmAction.snooze), l10n.alarmSnoozeMinutes(15));
    expect(page.labelOf(AlarmAction.openEvent), l10n.alarmOpenEvent);
    // Keep is offered only for an event that would otherwise be deleted: a
    // plain alarm has no row for it at all, neither drawn nor laid out and
    // waiting for the database.
    expect(page.isOffered(AlarmAction.keep), isFalse);
    expect(page.says(l10n.alarmKeep), isFalse);

    for (final action in [
      AlarmAction.stop,
      AlarmAction.snooze,
      AlarmAction.openEvent,
    ]) {
      expect(
        page.isOffered(action),
        isTrue,
        reason:
            '${action.id} is how a device pass reaches this button in any '
            'locale',
      );
    }
  });

  testWidgets('back does nothing while it is ringing', (tester) async {
    final page = AlarmPageRobot(tester);
    await page.pumpPage(payload());

    expect(page.backPops, isFalse);
  });

  testWidgets('a removable event explains itself and offers Keep', (
    tester,
  ) async {
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(
      payload(removeAfterAlert: true),
      active: 'gym_notes',
    );
    addTearDown(controller.dispose);
    await page.pumpPage(controller.payload, controller: controller);

    expect(page.removeAfterCaptionShown, isTrue);
    // One word beside the sentence it answers; the whole of it for a screen
    // reader, which reaches the button on its own.
    expect(page.labelOf(AlarmAction.keep), l10n.alarmKeep);
    expect(page.nameOf(AlarmAction.keep), l10n.alarmKeepEvent);

    await page.keep();

    // Keeping withdraws the warning and says so once. The offer stays where
    // it was, spent: nothing moves under the thumb that pressed it.
    expect(controller.keepEvent, isTrue);
    expect(controller.willRemoveEvent, isFalse);
    expect(page.keptCaptionShown, isTrue);
    expect(page.removeAfterCaptionShown, isFalse);
    expect(page.isOffered(AlarmAction.keep), isTrue);
    expect(page.isEnabled(AlarmAction.keep), isFalse);
  });

  testWidgets('an alarm from the open database offers no switch (A9)', (
    tester,
  ) async {
    final page = AlarmPageRobot(tester);
    final same = FakeRingController(payload(), active: 'gym_notes');
    addTearDown(same.dispose);
    await page.pumpPage(same.payload, controller: same);

    expect(page.says(l10n.alarmSwitchDatabase('gym_notes')), isFalse);
    expect(page.databaseLabel, isNull);
  });

  testWidgets('an alarm from another database offers the switch to it where '
      'Open event would be (A9)', (tester) async {
    final page = AlarmPageRobot(tester);
    final other = FakeRingController(
      payload(database: 'work'),
      active: 'gym_notes',
    );
    addTearDown(other.dispose);
    await page.pumpPage(other.payload, controller: other);

    expect(page.databaseLabel, l10n.alarmSwitchDatabase('work'));
    expect(page.databaseEnabled, isTrue);
    // Its event is not in the calendar "Open event" would land on, so that
    // row is the way to the event's own database instead — under an id of
    // its own, so that nothing looking for Open event finds the switch.
    expect(page.isOffered(AlarmAction.openEvent), isFalse);
    expect(page.says(l10n.alarmOpenEvent), isFalse);
  });

  testWidgets('a test alarm titles itself and cannot open an event', (
    tester,
  ) async {
    final page = AlarmPageRobot(tester);
    await page.pumpPage(payload(test: true));

    expect(page.title, l10n.alarmTestTitle);
    expect(page.says('Leg day'), isFalse);
    // There is no event behind a test ring, so the row that would open one is
    // inert rather than absent — the layout must not move between a test and
    // a real alarm.
    expect(page.labelOf(AlarmAction.openEvent), l10n.alarmOpenEvent);
    expect(page.isEnabled(AlarmAction.openEvent), isFalse);
  });

  testWidgets('a ring that ends elsewhere closes the page', (tester) async {
    // Stop on the platform's own notification, or the Silence-after timeout.
    // Back is disabled here, so a page left up would keep offering Stop for a
    // ring that is over with no other way off it.
    final page = AlarmPageRobot(tester);
    final gateway = EndingGateway();
    GetIt.I.registerSingleton<AlertGateway>(gateway);
    addTearDown(() async {
      await GetIt.I.unregister<AlertGateway>();
      await gateway.ends.close();
    });

    await page.pumpApp();
    await page.ring(payload());

    // Someone else's ring ending is not this page's business.
    gateway.ends.add((
      payload: payload().copyWith(osId: 1),
      cause: AlertRingEndCause.dismissed,
    ));
    await tester.pumpAndSettle();
    expect(page.isUp, isTrue);

    gateway.ends.add((payload: payload(), cause: AlertRingEndCause.timedOut));
    await tester.pumpAndSettle();

    expect(page.isUp, isFalse);
    expect(page.underneathShown, isTrue);
  });

  testWidgets('a ring whose entry the app cancels closes the page too', (
    tester,
  ) async {
    // The plan dropping an entry while it rings is nobody's answer, so
    // nothing is settled for it. The ring is over all the same, and the page
    // hears of it under a cause of its own: left up, it would stand there
    // silent, back disabled, its Stop still able to post the session chip
    // and remove the event.
    final page = AlarmPageRobot(tester);
    final gateway = EndingGateway();
    GetIt.I.registerSingleton<AlertGateway>(gateway);
    addTearDown(() async {
      await GetIt.I.unregister<AlertGateway>();
      await gateway.ends.close();
    });

    await page.pumpApp();
    await page.ring(payload(removeAfterAlert: true));
    expect(page.isUp, isTrue);

    gateway.ends.add((
      payload: payload(removeAfterAlert: true),
      cause: AlertRingEndCause.cancelled,
    ));
    await tester.pumpAndSettle();

    expect(page.isUp, isFalse);
    expect(page.underneathShown, isTrue);
  });

  testWidgets('Stop closes the page', (tester) async {
    final page = AlarmPageRobot(tester);
    await page.pumpApp();
    await page.ring(payload());
    expect(page.isUp, isTrue);

    await page.stop();

    expect(page.isUp, isFalse);
  });

  testWidgets('Snooze asks the controller once and closes the page; a second '
      'tap does nothing', (tester) async {
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(payload(), active: 'gym_notes')
      ..hold();
    addTearDown(controller.dispose);
    await page.pumpApp();
    await page.ring(controller.payload, controller: controller);

    await page.snooze();
    expect(controller.requests, [RingRequest.snooze]);

    // The first one is still in flight — on a phone, the scheduler silencing
    // the ring and arming the snooze — and the button stands switched off, so
    // the second tap of a double tap reaches nothing.
    await page.snooze();
    expect(controller.requests, [RingRequest.snooze]);
    expect(page.isUp, isTrue);

    controller.release();
    await tester.pumpAndSettle();

    expect(page.isUp, isFalse);
    expect(page.underneathShown, isTrue);
    expect(controller.requests, [RingRequest.snooze]);
  });

  testWidgets('while the controller is busy, Stop, Snooze, Open event and '
      'Keep are there and switched off', (tester) async {
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(
      payload(removeAfterAlert: true),
      active: 'gym_notes',
    )..hold();
    addTearDown(controller.dispose);
    await page.pumpApp();
    await page.ring(controller.payload, controller: controller);
    for (final action in AlarmAction.values) {
      expect(page.isEnabled(action), isTrue, reason: action.id);
    }

    await page.stop();

    expect(controller.busy, isTrue);
    for (final action in AlarmAction.values) {
      // Switched off in place rather than taken away: nothing moves under a
      // thumb that is already on its way to the next button.
      expect(page.isOffered(action), isTrue, reason: action.id);
      expect(page.isEnabled(action), isFalse, reason: action.id);
    }
    expect(page.removeAfterCaptionShown, isTrue);

    // Switched off is not a look: a tap on any of the four asks for nothing.
    for (final action in AlarmAction.values) {
      await page.tap(action);
    }
    expect(controller.requests, [RingRequest.stop]);
    expect(page.keptCaptionShown, isFalse);

    controller.release();
    await tester.pumpAndSettle();
    expect(page.isUp, isFalse);
  });

  testWidgets('Keep asks the controller to keep, and nothing else', (
    tester,
  ) async {
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(
      payload(removeAfterAlert: true),
      active: 'gym_notes',
    );
    addTearDown(controller.dispose);
    await page.pumpApp();
    await page.ring(controller.payload, controller: controller);

    await page.keep();

    // The ring goes on: keeping the event is not an answer to the alarm.
    expect(controller.requests, [RingRequest.keep]);
    expect(page.isUp, isTrue);
    expect(page.keptCaptionShown, isTrue);
    // One-way: the button stays in its place, and is spent.
    expect(page.isOffered(AlarmAction.keep), isTrue);
    expect(page.isEnabled(AlarmAction.keep), isFalse);
    expect(page.isEnabled(AlarmAction.stop), isTrue);
  });

  testWidgets('the database switch asks for the unlock first, and a refusal '
      'switches nothing and raises no dialog', (tester) async {
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(
      payload(database: 'work'),
      active: 'gym_notes',
      unlocks: false,
    );
    addTearDown(controller.dispose);
    await page.pumpApp();
    await page.ring(controller.payload, controller: controller);
    expect(page.databaseEnabled, isTrue);

    await page.openDatabase();

    expect(controller.requests, [RingRequest.unlock]);
    expect(page.restartDialogShown, isFalse);
    expect(page.isUp, isTrue);
    expect(page.isEnabled(AlarmAction.stop), isTrue);
  });

  testWidgets('the database switch, once unlocked, switches the database and '
      'raises a dialog that says so, with the ring still going', (
    tester,
  ) async {
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(
      payload(database: 'work'),
      active: 'gym_notes',
    );
    addTearDown(controller.dispose);
    await page.pumpApp();
    await page.ring(controller.payload, controller: controller);

    await page.openDatabase();

    // Unlock, then the switch, and no Stop anywhere on this path: the phone
    // is still ringing under a dialog whose one button leaves the app.
    expect(controller.requests, [
      RingRequest.unlock,
      RingRequest.activateDatabase,
    ]);
    expect(controller.stopped, isFalse);
    expect(page.restartDialogShown, isTrue);
    // What happened, and what is left to do — it used to be one sentence
    // about a restart that "may be required", said twice.
    expect(page.restartDialogTitle, l10n.alarmDatabaseSwitchedTitle('work'));
    expect(page.restartDialogBody, l10n.alarmDatabaseSwitchedBody);
    expect(page.isUp, isTrue);
  });

  testWidgets('the database switch raises no dialog when the switch fails', (
    tester,
  ) async {
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(
      payload(database: 'work'),
      active: 'gym_notes',
      switches: false,
    );
    addTearDown(controller.dispose);
    await page.pumpApp();
    await page.ring(controller.payload, controller: controller);

    await page.openDatabase();

    expect(controller.requests, [
      RingRequest.unlock,
      RingRequest.activateDatabase,
    ]);
    expect(page.restartDialogShown, isFalse);
    expect(page.isEnabled(AlarmAction.stop), isTrue);
  });

  group('Open event, once the phone is unlocked,', () {
    // `AppNavigator.toCalendarOccurrence` publishes the trip for a calendar
    // page that is already on the stack rather than pushing a second one, so
    // a stand-in wearing the calendar's route stamp is enough to read where
    // the page sent the user — no calendar, bloc or database stood up. The
    // other branch, a calendar pushed because none is open, builds the real
    // `CalendarPage` and is not reached from here.
    tearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);

    testWidgets('stops the ring, closes the page and opens the event on its '
        'day', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(payload(), active: 'gym_notes');
      addTearDown(controller.dispose);
      await page.pumpApp(appNavigator: true);
      await page.openCalendar();
      await page.ring(
        controller.payload,
        controller: controller,
        instant: true,
      );

      await page.openEvent();

      expect(controller.requests, [RingRequest.unlock, RingRequest.stop]);
      expect(page.isUp, isFalse);
      expect(page.calendarShown, isTrue);
      expect(AppNavigator.pendingCalendarOccurrence.value, (
        day: DateTime.utc(2026, 9, 20),
        eventId: 'e1',
      ));
    });

    testWidgets('opens an event that Stop removes on its day alone', (
      tester,
    ) async {
      // Whether Stop will remove the event is read before Stop runs: after it
      // the flag has been acted on, and a detail sheet would open over a
      // tombstone instead of the day carrying the Undo.
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);
      await page.pumpApp(appNavigator: true);
      await page.openCalendar();
      await page.ring(
        controller.payload,
        controller: controller,
        instant: true,
      );

      await page.openEvent();

      expect(controller.requests, [RingRequest.unlock, RingRequest.stop]);
      expect(page.isUp, isFalse);
      expect(page.calendarShown, isTrue);
      expect(AppNavigator.pendingCalendarOccurrence.value, (
        day: DateTime.utc(2026, 9, 20),
        eventId: null,
      ));
    });

    testWidgets('opens an event that was kept as the event it still is', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);
      await page.pumpApp(appNavigator: true);
      await page.openCalendar();
      await page.ring(
        controller.payload,
        controller: controller,
        instant: true,
      );

      await page.keep();
      await page.openEvent();

      expect(controller.requests, [
        RingRequest.keep,
        RingRequest.unlock,
        RingRequest.stop,
      ]);
      expect(AppNavigator.pendingCalendarOccurrence.value, (
        day: DateTime.utc(2026, 9, 20),
        eventId: 'e1',
      ));
    });

    testWidgets('ignores a second tap while the unlock is still being '
        'answered', (tester) async {
      // On a locked phone the unlock is a PIN prompt, up for as long as the
      // user takes, over a page that looks no different. A second tap used
      // to ask the keyguard again and then stop twice.
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(payload(), active: 'gym_notes')
        ..holdUnlock();
      addTearDown(controller.dispose);
      await page.pumpApp(appNavigator: true);
      await page.openCalendar();
      await page.ring(
        controller.payload,
        controller: controller,
        instant: true,
      );

      await page.tapOpenRowOnce();
      await page.tapOpenRowOnce();
      expect(controller.requests, [RingRequest.unlock]);
      // The ring is still the user's to stop while the prompt is up.
      expect(page.isEnabled(AlarmAction.stop), isTrue);

      controller.releaseUnlock();
      await tester.pumpAndSettle();

      expect(controller.requests, [RingRequest.unlock, RingRequest.stop]);
      expect(page.isUp, isFalse);
    });

    testWidgets('answers a tap again after an unlock that was refused', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(),
        active: 'gym_notes',
        unlocks: false,
      );
      addTearDown(controller.dispose);
      await page.pumpApp(appNavigator: true);
      await page.ring(
        controller.payload,
        controller: controller,
        instant: true,
      );

      await page.openEvent();
      await page.openEvent();

      // The first refusal did not leave the row dead: the second tap asked
      // again. Nothing was stopped either time.
      expect(controller.requests, [RingRequest.unlock, RingRequest.unlock]);
      expect(page.isUp, isTrue);
    });
  });

  testWidgets('with two rings stacked, the lower one ending elsewhere closes '
      'its own page and leaves the upper one ringing', (tester) async {
    // `main.dart` pushes a page for every ring it is told about, and with two
    // alarms due in one minute it is told about both, so two stack (seen on
    // the emulator, 2026-10-05). The page used to close by popping whatever
    // route was on top of the navigator, which here was the page of the ring
    // still going.
    final page = AlarmPageRobot(tester);
    final gateway = EndingGateway();
    GetIt.I.registerSingleton<AlertGateway>(gateway);
    addTearDown(() async {
      await GetIt.I.unregister<AlertGateway>();
      await gateway.ends.close();
    });
    final first = payload();
    final second = payload(title: 'Second ring', osId: 4343);

    await page.pumpApp();
    await page.ring(first, instant: true);
    await page.ring(second, instant: true);
    expect(page.pagesOnStack, 2);
    expect(page.title, 'Second ring');

    // The first ring is stopped from its notification while the second one's
    // page is in front.
    gateway.ends.add((payload: first, cause: AlertRingEndCause.dismissed));
    await tester.pumpAndSettle();

    // The first ring's page went, from under the one in front.
    expect(page.pagesOnStack, 1);
    expect(page.title, 'Second ring');

    // And the page left is the ring that is still going: its Stop stops it.
    await page.stop();
    expect(page.isUp, isFalse);
    expect(page.pagesOnStack, 0);
    expect(page.underneathShown, isTrue);
  });

  testWidgets('under the switch dialog, the ring ending elsewhere closes the '
      'page and leaves the dialog', (tester) async {
    // The dialog covers Stop while the phone goes on ringing, so the ring is
    // ended from its notification — or runs into the Silence-after timeout.
    // The page's close used to pop the dialog instead of the page: the one
    // button that leaves the app for the restart the switch needs.
    final page = AlarmPageRobot(tester);
    final controller = ScriptedRingController(
      payload(database: 'work'),
      active: 'gym_notes',
    );
    addTearDown(controller.dispose);
    await page.pumpApp();
    await page.ring(controller.payload, controller: controller, instant: true);
    await page.openDatabase();
    expect(page.restartDialogShown, isTrue);

    controller.endElsewhere();
    await tester.pumpAndSettle();

    // The page of a ring that is over is gone; the dialog is still there to
    // say the database was switched, over the app.
    expect(page.pagesOnStack, 0);
    expect(page.restartDialogShown, isTrue);
    expect(page.restartDialogTitle, l10n.alarmDatabaseSwitchedTitle('work'));
  });

  testWidgets('the robot dresses the page: locale, theme, text scale and '
      'phone size all reach it', (tester) async {
    // Not a layout case — those are the layout group's. This only proves the
    // four dressings they are written with do arrive.
    const phone = Size(360, 780);
    final page = AlarmPageRobot(tester);
    await page.pumpPage(
      payload(),
      locale: const Locale('de'),
      theme: AppTheme.dark(),
      textScale: 1.3,
      surface: phone,
    );

    expect(tester.takeException(), isNull);
    expect(page.labelOf(AlarmAction.stop), AppLocalizationsDe().alarmStop);
    expect(Theme.of(page.context).brightness, Brightness.dark);
    expect(MediaQuery.textScalerOf(page.context).scale(10), closeTo(13, 0.001));
    expect(MediaQuery.sizeOf(page.context), phone);
  });

  group('the time and the day', () {
    testWidgets('follow the clock the phone is on', (tester) async {
      final page = AlarmPageRobot(tester);
      final afternoon = payload(dueAt: DateTime(2026, 9, 20, 18, 5));

      await page.pumpPage(afternoon, use24Hour: false);
      expect(page.time, '6:05 PM');

      await page.pumpPage(afternoon, use24Hour: true);
      expect(page.time, '18:05');
    });

    testWidgets('in a language with no day period stay on the 24-hour clock '
        'whatever the phone says', (tester) async {
      // Material's rule, the one every in-app surface follows.
      final page = AlarmPageRobot(tester);
      final afternoon = payload(dueAt: DateTime(2026, 9, 20, 18, 5));

      for (final language in ['de', 'ro']) {
        await page.pumpPage(
          afternoon,
          locale: Locale(language),
          use24Hour: false,
        );
        expect(page.time, '18:05', reason: language);
      }
    });

    testWidgets('are the instant this ring was due, not the minute the label '
        'was frozen at', (tester) async {
      // A ring the platform moved — snoozed on its notification — carries
      // its new instant; the label beside it may be an older one.
      final page = AlarmPageRobot(tester);
      await page.pumpPage(
        payload(timeLabel: '07:00', dueAt: DateTime(2026, 9, 20, 7, 10)),
        use24Hour: true,
      );

      expect(page.time, '07:10');
    });

    testWidgets('name the day the ring was due, which is not always the '
        "occurrence's", (tester) async {
      // "1 day before": Sunday's event, due on Saturday. The old page put
      // Saturday's time over Sunday's date.
      final page = AlarmPageRobot(tester);
      await page.pumpPage(
        payload(
          dueAt: DateTime(2026, 9, 19, 9),
          whenLabel: 'Sun, Sep 20 · All day',
        ),
      );

      expect(page.dayLine, 'Saturday, September 19');
      expect(page.eventTime, 'Sun, Sep 20 · All day');
    });

    testWidgets('are spelled in the app language', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(), locale: const Locale('de'));

      expect(page.dayLine, 'Sonntag, 20. September');
    });

    testWidgets('an entry armed by an older build shows what it carries: the '
        "frozen label, the occurrence's day, no time of the event's own and "
        "the category's avatar", (tester) async {
      // Another database's entries and standing snoozes are never re-armed,
      // so a payload with none of the newer facts can ring for years.
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(older: true));

      expect(page.time, '07:00');
      expect(page.dayLine, 'Sunday, September 20');
      expect(page.eventTime, isNull);
      expect(page.excerpt, isNull);
      final category = CalendarCategories.resolve('gym');
      expect(page.avatarColor, Color(category.colorValue));
      expect(
        page.avatarIcon,
        CalendarIcons.forKey(category.iconKey) ?? Icons.alarm_rounded,
      );
    });

    testWidgets('an entry with no time at all keeps its line, and its day', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(older: true, timeLabel: ''));

      expect(tester.takeException(), isNull);
      expect(page.time, '');
      expect(page.timeLineHeight, AlarmMetrics.heroLineHeight);
      expect(page.dayLine, 'Sunday, September 20');
    });
  });

  group('what is ringing', () {
    testWidgets("is named with the event's own time and the first line of its "
        'description', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(
        payload(whenLabel: '07:00 – 08:30', excerpt: 'Squats first.'),
      );

      expect(page.title, 'Leg day');
      expect(page.eventTime, '07:00 – 08:30');
      expect(page.excerpt, 'Squats first.');
    });

    testWidgets('a plain alarm draws neither: no line that only repeats the '
        'clock above it, no empty description', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload());

      expect(page.eventTime, isNull);
      expect(page.excerpt, isNull);
    });

    testWidgets('a long description is cut after its second line', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(
        payload(
          excerpt:
              'Bring the belt and the chalk. Warm up on the bike first, then '
              'two light sets before the first working one, and keep the '
              'rest between them short.',
        ),
        surface: const Size(360, 780),
      );

      expect(page.excerptMaxLines, AlarmMetrics.excerptMaxLines);
      expect(page.excerptCut, isTrue);
    });

    testWidgets('wears the avatar that was resolved when it was armed', (
      tester,
    ) async {
      // The category facade is empty wherever no database is open, and
      // another database's alarm would otherwise wear this database's
      // category.
      final page = AlarmPageRobot(tester);
      await page.pumpPage(
        payload(tintValue: 0xFF00897B, glyphKey: 'fitness_center'),
      );

      expect(page.avatarColor, const Color(0xFF00897B));
      expect(page.avatarIcon, CalendarIcons.forKey('fitness_center'));
    });

    testWidgets('an event with no title is named by what it is', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(title: ''));
      expect(page.title, l10n.eventAlertModeRing);

      await page.pumpPage(payload(title: '   '));
      expect(page.title, l10n.eventAlertModeRing);
    });

    testWidgets('a test alarm is called a test alarm, in the app colour, with '
        "nothing of an event's about it", (tester) async {
      // It used to be titled with the settings button's own label, "Test
      // alarm in 10 s", which is what the payload still carries as its title.
      // The database is known, and it is the ring's own: the one state in
      // which a remove row is drawn, so its absence below is the test ring's
      // doing and not a database still unknown.
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(
          test: true,
          title: l10n.alertsTestAlarm,
          removeAfterAlert: true,
        ),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);
      // The app's own theme, which the colour below is named from: with none
      // pumped the page wears Flutter's default, whose primary happens to be
      // the same purple, and the case passed on that coincidence alone.
      await page.pumpPage(
        controller.payload,
        controller: controller,
        theme: AppTheme.light(),
      );
      expect(controller.activeDatabase, 'gym_notes', reason: 'precondition');

      expect(page.title, l10n.alarmTestTitle);
      expect(page.says(l10n.alertsTestAlarm), isFalse);
      expect(page.avatarColor, AppTheme.lightScheme.primary);
      expect(page.avatarIcon, CalendarIcons.forKey(kQuickAlarmIconKey));
      expect(page.eventTime, isNull);
      expect(page.excerpt, isNull);
      // Nobody's event, so there is none for Stop to remove.
      expect(page.removeAfterCaptionShown, isFalse);
      expect(page.isOffered(AlarmAction.keep), isFalse);
    });

    testWidgets("a test alarm's avatar is the theme's own colour, whatever "
        'its payload was stamped with', (tester) async {
      // The stamp is one fixed colour, the light scheme's, because an entry
      // is armed with no theme to ask: it is what the ring's notification
      // wears. Drawn on the dark page it was the dimmest thing there.
      final page = AlarmPageRobot(tester);
      final ring = payload(test: true);
      expect(ring.tintValue, AppTheme.lightScheme.primary.toARGB32());

      await page.pumpPage(ring, theme: AppTheme.light());
      expect(page.avatarColor, AppTheme.lightScheme.primary);

      await page.pumpPage(ring, theme: AppTheme.dark());
      expect(page.avatarColor, AppTheme.darkScheme.primary);
      expect(page.avatarColor, isNot(AppTheme.lightScheme.primary));
      expect(page.avatarIcon, CalendarIcons.forKey(kQuickAlarmIconKey));

      // And a test ring that carries some other tint, or none, is drawn the
      // same: nothing about its payload decides this.
      await page.pumpPage(
        payload(test: true, tintValue: 0xFF00897B),
        theme: AppTheme.dark(),
      );
      expect(page.avatarColor, AppTheme.darkScheme.primary);
      await page.pumpPage(
        payload(test: true, older: true),
        theme: AppTheme.dark(),
      );
      expect(page.avatarColor, AppTheme.darkScheme.primary);
    });
  });

  group('a ring that was snoozed', () {
    // The eyebrow as a phone draws it, written out: an expectation built
    // from the getters the page reads passes whatever the translation says.
    // The second word is said of the alarm, so where a language has gender
    // it agrees with the first — Romanian's "Alarmă" is feminine.

    testWidgets('says so when the snooze was taken on this page', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(snooze: true));

      expect(page.eyebrow, 'ALARM · SNOOZED');
    });

    testWidgets('says so when this process saw the platform move the ring', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(reRing: true));

      expect(page.eyebrow, 'ALARM · SNOOZED');
    });

    testWidgets('says so in German capitals', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(reRing: true), locale: const Locale('de'));

      expect(page.eyebrow, 'ALARM · GESCHLUMMERT');
    });

    testWidgets('says so in Romanian capitals', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(reRing: true), locale: const Locale('ro'));

      expect(page.eyebrow, 'ALARMĂ · AMÂNATĂ');
    });

    testWidgets('a first ring does not say it', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload());

      expect(page.eyebrow, l10n.alarmPageTitle.toUpperCase());
    });

    testWidgets('nor does a test ring, which is only registered as a snooze', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final testRing = payload(test: true);
      expect(testRing.snooze, isTrue, reason: 'precondition');
      await page.pumpPage(testRing);

      expect(page.eyebrow, l10n.alarmPageTitle.toUpperCase());
    });
  });

  group('an event that Stop removes', () {
    testWidgets('is not said to be one until the page knows whose it is, and '
        'then says so and offers Keep together', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      // Which database is open comes back a frame after the page, and stays
      // unknown if the read fails. Until then the page claims nothing.
      expect(controller.activeDatabase, isNull);
      expect(page.removeAfterCaptionShown, isFalse);
      expect(page.keptCaptionShown, isFalse);
      expect(page.isOffered(AlarmAction.keep), isFalse);

      controller.resolveDatabase('gym_notes');
      await tester.pump();

      expect(page.removeAfterCaptionShown, isTrue);
      expect(page.isOffered(AlarmAction.keep), isTrue);
      expect(page.isEnabled(AlarmAction.keep), isTrue);
    });

    testWidgets("another database's alarm is never said to be one, and has "
        'no Keep', (tester) async {
      // Stop removes nothing there — the removal is refused for a database
      // that is not open — and Keep would have nothing to write to.
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true, database: 'work'),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      expect(page.databaseLabel, l10n.alarmSwitchDatabase('work'));
      expect(page.removeAfterCaptionShown, isFalse);
      expect(page.keptCaptionShown, isFalse);
      expect(page.isOffered(AlarmAction.keep), isFalse);
    });

    testWidgets('while Keep is being saved, nothing is removed and nothing is '
        'called kept', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
        active: 'gym_notes',
      )..holdKeep();
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      await page.keep();

      // From the press a Stop removes nothing…
      expect(controller.willRemoveEvent, isFalse);
      // …but "kept" is a fact about the database, and is not one yet.
      expect(controller.keepEvent, isFalse);
      expect(page.keptCaptionShown, isFalse);
      expect(page.removeAfterCaptionShown, isTrue);
      // A second press has nowhere to go.
      expect(page.isEnabled(AlarmAction.keep), isFalse);
      await page.keep();
      expect(controller.requests, [RingRequest.keep]);
      // The ring is still the user's to answer.
      expect(page.isEnabled(AlarmAction.stop), isTrue);
      expect(page.isEnabled(AlarmAction.snooze), isTrue);

      controller.releaseKeep(ok: true);
      await tester.pumpAndSettle();

      expect(controller.keepEvent, isTrue);
      expect(page.keptCaptionShown, isTrue);
      expect(page.removeAfterCaptionShown, isFalse);
      expect(page.isOffered(AlarmAction.keep), isTrue);
      expect(page.isEnabled(AlarmAction.keep), isFalse);
    });

    testWidgets('a Keep that could not be saved is taken back: the event is '
        'still one that Stop removes, and Keep can be pressed again', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
        active: 'gym_notes',
      )..holdKeep();
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      await page.keep();
      controller.releaseKeep(ok: false);
      await tester.pumpAndSettle();

      expect(controller.keepEvent, isFalse);
      expect(controller.willRemoveEvent, isTrue);
      expect(page.keptCaptionShown, isFalse);
      expect(page.removeAfterCaptionShown, isTrue);
      expect(page.isEnabled(AlarmAction.keep), isTrue);

      await page.keep();
      expect(controller.requests, [RingRequest.keep, RingRequest.keep]);
      expect(page.keptCaptionShown, isTrue);
    });

    testWidgets('a ring whose event was kept before it began says so from the '
        'first thing it says, with Keep already spent', (tester) async {
      // A Keep on an earlier ring of the event. This one was armed before it
      // — the same alarm snoozed on its notification, or a second alarm of
      // the event — and its payload still says that Stop removes the event.
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);
      expect(page.removeAfterCaptionShown, isFalse);
      expect(page.keptCaptionShown, isFalse);

      controller.resolveDatabase('gym_notes', kept: true);
      await tester.pump();

      expect(page.keptCaptionShown, isTrue);
      expect(page.removeAfterCaptionShown, isFalse);
      expect(page.spoken, contains(l10n.alarmKeptEvent));
      expect(page.spoken, isNot(contains(l10n.alarmRemoveAfterCaption)));
      // Where it always is, and off: there is nothing left to keep.
      expect(page.isOffered(AlarmAction.keep), isTrue);
      expect(page.isEnabled(AlarmAction.keep), isFalse);
      await page.keep();
      expect(controller.requests, isEmpty);
      expect(controller.willRemoveEvent, isFalse);
      // The ring is still the user's to answer.
      expect(page.isEnabled(AlarmAction.stop), isTrue);
      expect(page.isEnabled(AlarmAction.snooze), isTrue);
      expect(page.isEnabled(AlarmAction.openEvent), isTrue);
    });

    testWidgets('with the real controller and no database to ask, nothing is '
        'claimed', (tester) async {
      // What the page does on a phone whose database read failed.
      final page = AlarmPageRobot(tester);
      final controller = AlertRingController(
        payload: payload(removeAfterAlert: true),
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);
      await tester.pumpAndSettle();

      expect(controller.activeDatabase, isNull);
      expect(page.removeAfterCaptionShown, isFalse);
      expect(page.isOffered(AlarmAction.keep), isFalse);
      expect(page.isEnabled(AlarmAction.stop), isTrue);
    });
  });

  group('the switch to another database', () {
    testWidgets('is switched off, in place, while the controller is busy', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(database: 'work'),
        active: 'gym_notes',
      )..hold();
      addTearDown(controller.dispose);
      await page.pumpApp();
      await page.ring(controller.payload, controller: controller);

      await page.snooze();

      expect(controller.busy, isTrue);
      expect(page.databaseLabel, l10n.alarmSwitchDatabase('work'));
      expect(page.databaseEnabled, isFalse);
      await page.openDatabase();
      expect(controller.requests, [RingRequest.snooze]);

      controller.release();
      await tester.pumpAndSettle();
    });

    testWidgets('ignores a second tap while the unlock is still being '
        'answered', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(database: 'work'),
        active: 'gym_notes',
      )..holdUnlock();
      addTearDown(controller.dispose);
      await page.pumpApp();
      await page.ring(controller.payload, controller: controller);

      await page.tapOpenRowOnce();
      await page.tapOpenRowOnce();
      expect(controller.requests, [RingRequest.unlock]);

      controller.releaseUnlock();
      await tester.pumpAndSettle();

      // One unlock, one switch, one dialog.
      expect(controller.requests, [
        RingRequest.unlock,
        RingRequest.activateDatabase,
      ]);
      expect(page.restartDialogShown, isTrue);
    });

    testWidgets('arrives in place of Open event when the database is known', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(payload(database: 'work'));
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      // Until the answer is in, the row is the one every alarm has.
      expect(page.labelOf(AlarmAction.openEvent), l10n.alarmOpenEvent);
      expect(page.databaseLabel, isNull);

      controller.resolveDatabase('gym_notes');
      await tester.pump();

      expect(page.isOffered(AlarmAction.openEvent), isFalse);
      expect(page.databaseLabel, l10n.alarmSwitchDatabase('work'));
    });
  });

  group('closing its own route', () {
    testWidgets('Stop on the first of two rings, finishing after the second '
        "ring's page has come up, takes the first page and leaves the second "
        'one working', (tester) async {
      // Two alarms due in one minute: the second ring's page comes up within
      // a second of the first one's. A Stop tapped on the first page before
      // then is still in flight when it does, and finishes underneath it —
      // the hand-over that used to leave a dead page on screen with the
      // phone ringing.
      final page = AlarmPageRobot(tester);
      final first = ScriptedRingController(payload(), active: 'gym_notes')
        ..hold();
      final second = ScriptedRingController(
        payload(title: 'Second ring', osId: 4343),
        active: 'gym_notes',
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await page.pumpApp();
      await page.ring(first.payload, controller: first, instant: true);

      await page.stop();
      expect(first.busy, isTrue);
      await page.ring(second.payload, controller: second, instant: true);
      expect(page.pagesOnStack, 2);

      first.release();
      await tester.pumpAndSettle();

      expect(page.pagesOnStack, 1);
      expect(page.title, 'Second ring');
      expect(page.backPops, isFalse);

      await page.stop();

      expect(second.requests, [RingRequest.stop]);
      expect(page.isUp, isFalse);
      expect(page.underneathShown, isTrue);
    });

    testWidgets('a page removed from under another completes its route, which '
        'is what releases the taps a ring held back', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(payload(), active: 'gym_notes');
      addTearDown(controller.dispose);
      await page.pumpApp();
      final route = await page.ring(
        controller.payload,
        controller: controller,
        instant: true,
      );
      var completed = false;
      route.popped.whenComplete(() => completed = true);
      await page.ring(payload(title: 'Second ring', osId: 4343), instant: true);

      controller.endElsewhere();
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(page.pagesOnStack, 1);
    });

    testWidgets('as the only route it has nowhere to go, and stays', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(payload(), active: 'gym_notes');
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      await page.stop();

      expect(controller.requests, [RingRequest.stop]);
      expect(page.isUp, isTrue);
    });
  });

  group('ground and bars', () {
    final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

    for (final MapEntry(key: name, value: theme) in themes.entries) {
      testWidgets('in the $name theme the page stands on the page ground and '
          'says what both system bars wear', (tester) async {
        final page = AlarmPageRobot(tester);
        await page.pumpPage(payload(), theme: theme);

        // One tone under the card, in both themes — the scaffold's own
        // ground is the card's tone in light.
        expect(page.groundColor, theme.colorScheme.pageGround);
        final icons = theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
        final bars = page.bars;
        expect(bars, AlarmGround.barsOver(theme.brightness));
        expect(bars.statusBarColor, Colors.transparent);
        // The icons used to be whatever the page underneath had left: white
        // on this light ground after Calendar settings.
        expect(bars.statusBarIconBrightness, icons);
        expect(bars.systemNavigationBarColor, Colors.transparent);
        expect(bars.systemNavigationBarDividerColor, Colors.transparent);
        expect(bars.systemNavigationBarIconBrightness, icons);
        // No band of the phone's own across the bottom of the page.
        expect(bars.systemNavigationBarContrastEnforced, isFalse);
      });

      testWidgets('in the $name theme the lock-screen cover is the same '
          'ground under the same bars', (tester) async {
        final lock = LockScreenState.instance..resetForTesting();
        addTearDown(lock.resetForTesting);
        final page = AlarmPageRobot(tester);
        await page.pumpApp(observed: true, curtain: true, theme: theme);
        lock.setLocked(true);
        await tester.pump();

        expect(page.coverShown, isTrue);
        final coverColor = page.coverColor;
        final coverBars = page.coverBars;
        expect(coverColor, theme.colorScheme.pageGround);

        await page.ring(payload(), instant: true);

        // Cover, page, cover: no step in tone and no change of bars.
        expect(page.coverShown, isFalse);
        expect(page.groundColor, coverColor);
        expect(page.bars, coverBars);
      });
    }
  });

  group('what a screen reader is told', () {
    testWidgets('the eyebrow is a heading that names the screen', (
      tester,
    ) async {
      // The page has no app bar; Android announces a route by the first node
      // under the route's scope that says it names one, and without it the
      // page opened to silence. The scope itself is the next case's.
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(reRing: true));

      final node = page.eyebrowNode;
      final flags = node.getSemanticsData().flagsCollection;
      expect(flags.isHeader, isTrue);
      expect(flags.namesRoute, isTrue);
      // Said as words, not as the capitals it is drawn in, and with a pause
      // where the drawn line has a dot.
      expect(
        node.label,
        '${l10n.alarmPageTitle}, ${l10n.alertsOutcomeSnoozed}',
      );
    });

    testWidgets('pushed the way a ring pushes it, on a route that scopes '
        'nothing, the page is announced by its eyebrow all the same', (
      tester,
    ) async {
      // `main.dart` pushes the page on a bare route with no transition, and
      // only a `MaterialPageRoute` scopes the page it builds. Android
      // announces a screen from a node that scopes a route: under none, the
      // eyebrow named a route nobody was listening for.
      final page = AlarmPageRobot(tester);
      await page.pumpApp();
      await page.ring(payload(), instant: true);

      expect(page.announcedAs, l10n.alarmPageTitle);
    });

    testWidgets('the event is one node: its title, then its time', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(whenLabel: '07:00 – 08:30'));

      expect(page.titleNode.label, 'Leg day\n07:00 – 08:30');
    });

    testWidgets('the page is read top to bottom, the avatar left out and the '
        'remove row as two stops', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(
          removeAfterAlert: true,
          whenLabel: '07:00 – 08:30',
          excerpt: 'Squats first.',
        ),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      expect(page.spoken, [
        l10n.alarmPageTitle,
        '7:00 AM',
        'Sunday, September 20',
        'Leg day\n07:00 – 08:30',
        'Squats first.',
        l10n.alarmOpenEvent,
        l10n.alarmRemoveAfterCaption,
        l10n.alarmKeepEvent,
        l10n.alarmStop,
        l10n.alarmSnoozeMinutes(10),
      ]);
    });

    testWidgets('each action is a button on its own node, under its id', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      for (final action in AlarmAction.values) {
        final data = page.nodeOf(action).getSemanticsData();
        expect(data.identifier, action.id);
        expect(data.flagsCollection.isButton, isTrue, reason: action.id);
        expect(
          data.flagsCollection.isEnabled,
          Tristate.isTrue,
          reason: action.id,
        );
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: action.id);
      }
    });

    testWidgets('an Open row that is switched off is a button that is '
        'switched off, not a line of text', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(test: true));

      final data = page.openRowNode.getSemanticsData();
      expect(data.identifier, AlarmAction.openEvent.id);
      expect(data.label, l10n.alarmOpenEvent);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets('a Keep that is spent is still there, and says it is off', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      await page.keep();

      final data = page.nodeOf(AlarmAction.keep).getSemanticsData();
      expect(data.label, l10n.alarmKeepEvent);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(page.spoken, contains(l10n.alarmKeptEvent));
      expect(page.spoken, isNot(contains(l10n.alarmRemoveAfterCaption)));
    });

    testWidgets('a remove row that is not drawn yet is not read out either', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
      );
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      expect(page.spoken, isNot(contains(l10n.alarmRemoveAfterCaption)));
      expect(page.spoken, isNot(contains(l10n.alarmKeepEvent)));
    });
  });

  group('layout', () {
    const small = Size(360, 780);
    const large = Size(412, 915);
    const landscape = Size(780, 360);
    const locales = [Locale('en'), Locale('de'), Locale('ro')];
    const scales = [1.0, 1.3, 2.0];
    final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

    /// Everything the page can draw at once: a re-ring of a removable event
    /// with a title that wraps, a time of its own and a description that is
    /// cut.
    AlertPayload fullest() => payload(
      removeAfterAlert: true,
      snooze: true,
      title: 'Leg day - heavy squats and accessory work',
      whenLabel: '07:00 – 08:30',
      excerpt:
          'Bring the belt and the chalk. Warm up on the bike first, then two '
          'light sets before the first working one.',
    );

    /// What every cell of the matrix has to show: nothing overflowed, the two
    /// buttons that answer the ring are whole, on the screen and big enough
    /// to hit, and the row that leads into the app is in view without a
    /// scroll.
    void expectHolds(WidgetTester tester, AlarmPageRobot page, String cell) {
      expect(tester.takeException(), isNull, reason: cell);
      final screen = page.screen;
      for (final action in [AlarmAction.stop, AlarmAction.snooze]) {
        final rect = page.rectOf(action);
        expect(
          rect.height,
          greaterThanOrEqualTo(kMinInteractiveDimension),
          reason: '$cell: ${action.id}',
        );
        expect(
          screen.contains(rect.topLeft) &&
              rect.bottom <= screen.bottom &&
              rect.right <= screen.right,
          isTrue,
          reason: '$cell: ${action.id} at $rect is not inside $screen',
        );
      }
      final body = page.bodyRect;
      final open = page.openRowRect;
      expect(
        open.top >= body.top && open.bottom <= body.bottom,
        isTrue,
        reason: '$cell: the Open row at $open is not inside the body $body',
      );
    }

    testWidgets('the plain page and the fullest one hold in every language, '
        'at every text scale, on both phones, in both themes', (tester) async {
      final page = AlarmPageRobot(tester);
      for (final surface in [small, large]) {
        for (final MapEntry(key: themeName, value: theme) in themes.entries) {
          for (final locale in locales) {
            for (final scale in scales) {
              for (final full in [false, true]) {
                final controller = ScriptedRingController(
                  full ? fullest() : payload(),
                  active: 'gym_notes',
                );
                addTearDown(controller.dispose);
                await page.pumpPage(
                  controller.payload,
                  controller: controller,
                  surface: surface,
                  theme: theme,
                  locale: locale,
                  textScale: scale,
                );
                final cell =
                    '${full ? 'fullest' : 'plain'} $surface $themeName '
                    '$locale ×$scale';
                expectHolds(tester, page, cell);
                if (full) {
                  // The matrix is about the page with everything on it: a
                  // remove row still waiting for its database would pass
                  // every check above with nothing drawn.
                  expect(page.removeAfterCaptionShown, isTrue, reason: cell);
                  expect(page.keepRect.height, greaterThanOrEqualTo(48));
                } else {
                  // And with the database known and the alarm its own, a
                  // plain alarm still offers no Keep: here the row's
                  // absence is the payload's doing, not a database the
                  // page is still waiting for.
                  expect(
                    page.isOffered(AlarmAction.keep),
                    isFalse,
                    reason: cell,
                  );
                }
              }
            }
          }
        }
      }
    });

    testWidgets('a window 360 dp high holds too, and scrolls', (tester) async {
      // Landscape, or a split screen: German at the largest text, with
      // everything on the page.
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(fullest(), active: 'gym_notes');
      addTearDown(controller.dispose);
      await page.pumpPage(
        controller.payload,
        controller: controller,
        surface: landscape,
        theme: AppTheme.dark(),
        locale: const Locale('de'),
        textScale: 2.0,
      );

      expectHolds(tester, page, 'landscape');
      // Too short to pin anything: the dock is the end of the scroll, where
      // the page rests, and everything above it is a drag away.
      final body = page.bodyRect;
      expect(body.contains(page.rectOf(AlarmAction.stop).center), isTrue);
      expect(page.eyebrowRect.bottom, lessThanOrEqualTo(body.top));

      await page.dragBody(2000);

      expect(tester.takeException(), isNull);
      expect(page.eyebrowRect.top, greaterThanOrEqualTo(body.top));
    });

    testWidgets('on a phone the dock is pinned under the body, and the body '
        'rests on it', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(), surface: small);

      final body = page.bodyRect;
      final stop = page.rectOf(AlarmAction.stop);
      final snooze = page.rectOf(AlarmAction.snooze);
      expect(stop.top, greaterThanOrEqualTo(body.bottom));
      // Stop over Snooze, Snooze on the bottom edge: a stray grab at the
      // edge of the phone costs minutes, not an event.
      expect(snooze.top, stop.bottom + AlarmMetrics.dockGap);
      expect(stop.height, AlarmMetrics.stopHeight);
      expect(snooze.height, AlarmMetrics.snoozeHeight);
      // Short content sits at the bottom of the body, on the dock: the top
      // of the screen is where Android draws the ring's heads-up.
      expect(page.openRowRect.bottom, body.bottom - AlarmMetrics.dockGap);
      expect(page.eyebrowRect.top, greaterThan(small.height / 3));
    });

    testWidgets('content taller than the body loses its top first, and one '
        'drag brings it back', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(fullest(), active: 'gym_notes');
      addTearDown(controller.dispose);
      await page.pumpPage(
        controller.payload,
        controller: controller,
        surface: small,
        textScale: 2.0,
      );

      final body = page.bodyRect;
      // At rest the end of the content is what shows: the row that leads on.
      expect(page.openRowRect.bottom, body.bottom - AlarmMetrics.dockGap);
      expect(page.eyebrowRect.bottom, lessThanOrEqualTo(body.top));
      final stop = page.rectOf(AlarmAction.stop);

      await page.dragBody(2000);

      expect(page.eyebrowRect.top, greaterThanOrEqualTo(body.top));
      // The dock does not scroll with it.
      expect(page.rectOf(AlarmAction.stop), stop);
    });

    testWidgets('under Snooze is the dock padding plus the system inset, and '
        'the page starts under the status bar', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(), surface: small);

      expect(
        page.rectOf(AlarmAction.snooze).bottom,
        small.height -
            AlarmPageRobot.systemBar -
            AlarmMetrics.dockBottomPadding,
      );
      expect(page.bodyRect.top, AlarmPageRobot.systemBar);
    });

    testWidgets('an inset left behind by a keyboard lifts the dock clear of '
        'it', (tester) async {
      // The page raises no keyboard, but the page under it may have left
      // one's inset standing.
      const keyboard = 200.0;
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(), surface: small, keyboard: keyboard);

      expect(tester.takeException(), isNull);
      // The system's own inset is under the keyboard now, and is not added a
      // second time.
      expect(
        page.rectOf(AlarmAction.snooze).bottom,
        small.height - keyboard - AlarmMetrics.dockBottomPadding,
      );
    });

    testWidgets('an inset that leaves the body too short to pin the dock '
        'unpins it instead of overflowing', (tester) async {
      const keyboard = 320.0;
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(fullest(), active: 'gym_notes');
      addTearDown(controller.dispose);
      await page.pumpPage(
        controller.payload,
        controller: controller,
        surface: small,
        keyboard: keyboard,
        textScale: 2.0,
        locale: const Locale('de'),
      );

      expect(tester.takeException(), isNull);
      final body = page.bodyRect;
      expect(body.bottom, small.height - keyboard);
      expect(body.height, lessThan(AlarmMetrics.pinnedDockMinHeight));
      // Snooze is what the page rests on, above the inset.
      expect(
        page.rectOf(AlarmAction.snooze).bottom,
        body.bottom - AlarmMetrics.dockBottomPadding,
      );
    });

    testWidgets('unpinned, a page shorter than its body still rests on the '
        "body's bottom edge", (tester) async {
      // Two ways to a body under the pinning height that the plain page
      // fits with room to spare: a keyboard's inset left standing, and a
      // split-screen window. The unpinned scroll used to take its content's
      // height and hang from the top of the body — Stop in mid-screen, bare
      // ground under Snooze, the time up where the heads-up is drawn.
      final page = AlarmPageRobot(tester);

      const keyboard = 320.0;
      await page.pumpPage(payload(), surface: small, keyboard: keyboard);
      expect(tester.takeException(), isNull);
      var body = page.bodyRect;
      expect(body.height, lessThan(AlarmMetrics.pinnedDockMinHeight));
      expect(body.top, AlarmPageRobot.systemBar);
      expect(body.bottom, small.height - keyboard);
      expect(
        page.eyebrowRect.top,
        greaterThan(body.top),
        reason: 'precondition: the page fits its body',
      );
      expect(
        page.rectOf(AlarmAction.snooze).bottom,
        small.height - keyboard - AlarmMetrics.dockBottomPadding,
      );

      const window = Size(412, 470);
      await page.pumpPage(payload(), surface: window);
      expect(tester.takeException(), isNull);
      body = page.bodyRect;
      expect(body.height, lessThan(AlarmMetrics.pinnedDockMinHeight));
      expect(body.bottom, window.height);
      expect(
        page.eyebrowRect.top,
        greaterThan(body.top),
        reason: 'precondition: the page fits its body',
      );
      expect(
        page.rectOf(AlarmAction.snooze).bottom,
        window.height -
            AlarmPageRobot.systemBar -
            AlarmMetrics.dockBottomPadding,
      );
    });

    testWidgets('nothing in the dock moves: not when the database is known, '
        'not when Keep is pressed, not when it has been saved', (tester) async {
      final page = AlarmPageRobot(tester);
      final dressings = [
        (surface: small, locale: const Locale('en'), scale: 1.0),
        (surface: small, locale: const Locale('de'), scale: 2.0),
        (surface: large, locale: const Locale('ro'), scale: 1.3),
      ];
      for (final dressing in dressings) {
        final controller = ScriptedRingController(
          payload(
            removeAfterAlert: true,
            whenLabel: '07:00 – 08:30',
            excerpt: 'Squats first.',
          ),
        )..holdKeep();
        addTearDown(controller.dispose);
        await page.pumpPage(
          controller.payload,
          controller: controller,
          surface: dressing.surface,
          locale: dressing.locale,
          textScale: dressing.scale,
        );
        final cell = '${dressing.locale} ×${dressing.scale}';

        List<Rect> dock() => [
          page.rectOf(AlarmAction.stop),
          page.rectOf(AlarmAction.snooze),
          page.keepRect,
        ];
        final open = page.openRowRect;

        // The slot is there from the first frame, sized and not yet drawn.
        final before = dock();
        expect(page.isOffered(AlarmAction.keep), isFalse, reason: cell);

        controller.resolveDatabase('gym_notes');
        await tester.pump();
        expect(page.removeAfterCaptionShown, isTrue, reason: cell);
        expect(dock(), before, reason: '$cell: the database is known');
        expect(page.openRowRect, open, reason: cell);

        await page.keep();
        expect(dock(), before, reason: '$cell: Keep is pressed');

        controller.releaseKeep(ok: true);
        await tester.pumpAndSettle();
        expect(page.keptCaptionShown, isTrue, reason: cell);
        expect(dock(), before, reason: '$cell: the event is kept');
        expect(page.openRowRect, open, reason: cell);
        expect(tester.takeException(), isNull, reason: cell);
      }
    });

    testWidgets('a ring that starts as kept has its dock where a ring that '
        'does not has it', (tester) async {
      // The row says "kept" from its first drawing there, in the slot the
      // other sentence would have had.
      final page = AlarmPageRobot(tester);
      final dressings = [
        (surface: small, locale: const Locale('en'), scale: 1.0),
        (surface: small, locale: const Locale('de'), scale: 2.0),
        (surface: large, locale: const Locale('ro'), scale: 1.3),
      ];
      for (final dressing in dressings) {
        final cell = '${dressing.locale} ×${dressing.scale}';

        List<Rect> dock() => [
          page.rectOf(AlarmAction.stop),
          page.rectOf(AlarmAction.snooze),
          page.keepRect,
          page.openRowRect,
        ];

        /// The dock of a removable event's ring once the event has answered,
        /// held against the dock of its first frame on the way.
        Future<List<Rect>> dockOnce({required bool kept}) async {
          final controller = ScriptedRingController(
            payload(
              removeAfterAlert: true,
              whenLabel: '07:00 – 08:30',
              excerpt: 'Squats first.',
            ),
          );
          addTearDown(controller.dispose);
          await page.pumpPage(
            controller.payload,
            controller: controller,
            surface: dressing.surface,
            locale: dressing.locale,
            textScale: dressing.scale,
          );
          final unanswered = dock();

          controller.resolveDatabase('gym_notes', kept: kept);
          await tester.pump();

          expect(dock(), unanswered, reason: '$cell: kept $kept');
          return dock();
        }

        final claimed = await dockOnce(kept: false);
        expect(page.removeAfterCaptionShown, isTrue, reason: cell);

        final kept = await dockOnce(kept: true);
        expect(page.keptCaptionShown, isTrue, reason: cell);
        expect(page.removeAfterCaptionShown, isFalse, reason: cell);
        expect(page.isEnabled(AlarmAction.keep), isFalse, reason: cell);

        expect(kept, claimed, reason: cell);
        expect(tester.takeException(), isNull, reason: cell);
      }
    });

    testWidgets("another database's name arriving moves nothing in the dock "
        'either', (tester) async {
      // The Open row's label changes in place, and at large text its height
      // can change with it; it is the last row of the body, so what moves is
      // the content above it.
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true, database: 'the-other-database'),
      );
      addTearDown(controller.dispose);
      await page.pumpPage(
        controller.payload,
        controller: controller,
        surface: small,
        locale: const Locale('de'),
        textScale: 2.0,
      );
      final stop = page.rectOf(AlarmAction.stop);
      final snooze = page.rectOf(AlarmAction.snooze);
      final keep = page.keepRect;
      final openBottom = page.openRowRect.bottom;

      controller.resolveDatabase('gym_notes');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        page.databaseLabel,
        AppLocalizationsDe().alarmSwitchDatabase('the-other-database'),
      );
      expect(page.rectOf(AlarmAction.stop), stop);
      expect(page.rectOf(AlarmAction.snooze), snooze);
      expect(page.keepRect, keep);
      expect(page.openRowRect.bottom, openBottom);
    });

    testWidgets('the time is not scaled with the text, the card is, and the '
        'dock only so far', (tester) async {
      final page = AlarmPageRobot(tester);
      final controller = ScriptedRingController(
        payload(removeAfterAlert: true),
        active: 'gym_notes',
      );
      addTearDown(controller.dispose);

      await page.pumpPage(
        controller.payload,
        controller: controller,
        surface: large,
        use24Hour: true,
      );
      final timeAtOne = page.timeRect;

      await page.pumpPage(
        controller.payload,
        controller: controller,
        surface: large,
        use24Hour: true,
        textScale: 2.0,
      );

      // A display numeral is fitted to the page, never grown past it.
      expect(page.timeRect.size, timeAtOne.size);
      expect(page.timeLineHeight, AlarmMetrics.heroLineHeight);
      expect(page.textScaleOf(AlarmAction.openEvent), 2.0);
      for (final action in [
        AlarmAction.stop,
        AlarmAction.snooze,
        AlarmAction.keep,
      ]) {
        expect(
          page.textScaleOf(action),
          AlarmMetrics.dockMaxTextScale,
          reason: action.id,
        );
      }

      await page.pumpPage(
        controller.payload,
        controller: controller,
        surface: large,
        textScale: 1.3,
      );
      expect(page.textScaleOf(AlarmAction.stop), 1.3);
    });

    testWidgets('a time too wide for the page is fitted to it, on its line', (
      tester,
    ) async {
      // In the test font a 12-hour time at 64 px is wider than a 360 dp
      // phone; on a device it is the 200 % font setting that does it to
      // nothing, since the time is not scaled, but a narrower window would.
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(), surface: small, use24Hour: false);

      expect(tester.takeException(), isNull);
      expect(page.time, '7:00 AM');
      final time = page.timeRect;
      expect(time.left, greaterThanOrEqualTo(0));
      expect(time.right, lessThanOrEqualTo(small.width));
      expect(page.timeLineHeight, AlarmMetrics.heroLineHeight);
    });

    testWidgets('the time, the day and the eyebrow start on one line with '
        'the card set in from it', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpPage(payload(), surface: large, use24Hour: true);

      expect(page.timeRect.left, page.eyebrowTextLeft);
      expect(page.dayLeft, page.eyebrowTextLeft);
      expect(page.cardRect.left, lessThan(page.eyebrowTextLeft));
      expect(page.cardRect.left, page.rectOf(AlarmAction.stop).left);
      expect(page.cardRect.right, page.rectOf(AlarmAction.stop).right);
    });
  });

  group('on a locked phone', () {
    // A ring lifts the whole activity above the keyguard, and the alarm page
    // is the one surface allowed there. `LockScreenCurtain` hides the rest for
    // as long as `LockScreenState.alarmOnTop` is false, so what the page
    // reports is what decides whether a note is readable without a PIN.
    final lock = LockScreenState.instance;

    setUp(lock.resetForTesting);
    tearDown(lock.resetForTesting);

    testWidgets('the page is the allowed surface from push to pop', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      expect(lock.alarmOnTop, isFalse);
      await page.pumpApp(observed: true);
      await page.ring(payload());
      expect(lock.alarmOnTop, isTrue);

      await page.stop();

      expect(page.isUp, isFalse);
      expect(lock.alarmOnTop, isFalse);
    });

    testWidgets('a page pushed over it takes the allowance away', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpApp(observed: true);
      await page.ring(payload());

      // Whatever lands above the alarm page is not the alarm page: the
      // curtain has to come back, or that page is on the lock screen.
      await page.pushPageOver();
      expect(lock.alarmOnTop, isFalse);

      await page.popTop();
      expect(lock.alarmOnTop, isTrue);
    });

    testWidgets('a dialog the page raises leaves it the allowed surface', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpApp(observed: true);
      await page.ring(payload());

      await page.raiseDialog();

      expect(page.dialogShown, isTrue);
      expect(lock.alarmOnTop, isTrue);
    });

    testWidgets('pushed on a locked phone, it is what the curtain lets '
        'through', (tester) async {
      // The page reports itself while it is being mounted — inside a build —
      // and the curtain's rebuild from there used to throw, be swallowed by
      // the notifier, and leave the cover over the alarm page: a ringing
      // phone showing a blank screen (seen on the emulator, 2026-10-04).
      final page = AlarmPageRobot(tester);
      await page.pumpApp(observed: true, curtain: true);
      lock.setLocked(true);
      await tester.pump();
      expect(lock.mustCover, isTrue);

      await page.ring(payload(), instant: true);

      expect(tester.takeException(), isNull);
      expect(lock.mustCover, isFalse);
      // Reachable, not merely built: a covered Stop is an alarm nobody can
      // stop.
      await page.stop();

      expect(page.isUp, isFalse);
      // The page is gone and the phone is still locked: the note under it
      // must not be hittable.
      expect(lock.mustCover, isTrue);
      expect(page.underneathReachable, isFalse);
    });

    testWidgets('removed outright on a locked phone, the cover comes back', (
      tester,
    ) async {
      // `removeRoute` pops nothing, so the page's only report is its dispose
      // — which runs while the tree is locked, the other moment a rebuild
      // from the notifier used to be lost.
      final page = AlarmPageRobot(tester);
      await page.pumpApp(observed: true, curtain: true);
      lock.setLocked(true);
      final route = await page.ring(payload(), instant: true);
      expect(lock.mustCover, isFalse);

      await page.removeOutright(route);

      expect(tester.takeException(), isNull);
      expect(lock.mustCover, isTrue);
      expect(page.underneathReachable, isFalse);
    });

    testWidgets('Open event asks for the unlock first, and a refusal leaves '
        'the ring alone', (tester) async {
      // Stopping first would end the ring and send the app back behind the
      // keyguard, with the event opening where nobody can see it.
      final page = AlarmPageRobot(tester);
      final gateway = LockedGateway(unlocks: false);
      GetIt.I.registerSingleton<AlertGateway>(gateway);
      addTearDown(() => GetIt.I.unregister<AlertGateway>());
      final controller = FakeRingController(payload(), active: 'gym_notes');
      addTearDown(controller.dispose);
      await page.pumpPage(controller.payload, controller: controller);

      await page.openEvent();

      expect(gateway.unlockRequests, 1);
      expect(controller.stopped, isFalse);
      expect(page.isUp, isTrue);
    });

    testWidgets('a second ring taking over from the first leaves an alarm '
        'page the allowed surface throughout', (tester) async {
      // The first page is removed from under the second: no pop, so nothing
      // tells the lock state but the first page's own dispose — which must
      // not take the second page's allowance with it.
      final page = AlarmPageRobot(tester);
      final first = ScriptedRingController(payload(), active: 'gym_notes');
      addTearDown(first.dispose);
      await page.pumpApp(observed: true, curtain: true);
      lock.setLocked(true);
      await page.ring(first.payload, controller: first, instant: true);
      await page.ring(payload(title: 'Second ring', osId: 4343), instant: true);
      expect(lock.mustCover, isFalse);

      first.endElsewhere();
      await tester.pumpAndSettle();

      expect(page.pagesOnStack, 1);
      expect(lock.alarmOnTop, isTrue);
      expect(lock.mustCover, isFalse);
      expect(page.isEnabled(AlarmAction.stop), isTrue);
    });
  });

  group('the guide\'s preview', () {
    // The real page over a demo payload: every action only closes it, no
    // call reaches the platform, the lock state is never told, and back
    // closes it. Each case is also the guard against a write path added to
    // the page later and forgotten here.
    final lock = LockScreenState.instance;
    late RecordingGateway gateway;
    final keepNotice = AlertKeepNotice.instance;
    var keepNotified = 0;
    void onKeepNotice() => keepNotified++;

    setUp(() {
      lock.resetForTesting();
      gateway = RecordingGateway();
      GetIt.I.registerSingleton<AlertGateway>(gateway);
      keepNotice.clearForTesting();
      keepNotified = 0;
      keepNotice.addListener(onKeepNotice);
    });

    tearDown(() async {
      keepNotice.removeListener(onKeepNotice);
      keepNotice.clearForTesting();
      lock.resetForTesting();
      await GetIt.I.unregister<AlertGateway>();
    });

    testWidgets('draws the ring of the open database, back included', (
      tester,
    ) async {
      final page = AlarmPageRobot(tester);
      await page.pumpApp(observed: true);
      await page.ring(payload(removeAfterAlert: true), preview: true);

      expect(page.isUp, isTrue);
      expect(page.eyebrow, l10n.alarmPageTitle.toUpperCase());
      expect(page.title, 'Leg day');
      expect(page.removeAfterCaptionShown, isTrue);
      for (final action in AlarmAction.values) {
        expect(page.isEnabled(action), isTrue, reason: action.name);
      }
      expect(page.databaseLabel, isNull);
      expect(page.backPops, isTrue);
      expect(lock.alarmOnTop, isFalse);

      await page.systemBack();

      expect(page.isUp, isFalse);
      expect(page.underneathShown, isTrue);
      expect(gateway.calls, isEmpty);
      expect(lock.alarmOnTop, isFalse);
    });

    for (final action in AlarmAction.values) {
      testWidgets('${action.name} only closes it and nothing is armed', (
        tester,
      ) async {
        final page = AlarmPageRobot(tester);
        await page.pumpApp(observed: true, appNavigator: true);
        await page.ring(payload(removeAfterAlert: true), preview: true);

        await page.tap(action);

        expect(page.isUp, isFalse);
        expect(page.underneathShown, isTrue);
        expect(page.calendarShown, isFalse);
        expect(gateway.calls, isEmpty);
        expect(keepNotice.hasPending, isFalse);
        expect(keepNotified, 0);
        expect(lock.alarmOnTop, isFalse);
      });
    }

    testWidgets('on a locked phone it never lifts the curtain', (tester) async {
      final page = AlarmPageRobot(tester);
      await page.pumpApp(observed: true, curtain: true);
      lock.setLocked(true);
      await tester.pump();

      await page.ring(payload(), preview: true, instant: true);

      expect(tester.takeException(), isNull);
      expect(lock.alarmOnTop, isFalse);
      expect(lock.mustCover, isTrue);

      await page.systemBack();

      expect(page.isUp, isFalse);
      expect(lock.mustCover, isTrue);
      expect(gateway.calls, isEmpty);
    });
  });
}
