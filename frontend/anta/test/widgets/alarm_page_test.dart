import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/controllers/alert_ring_controller.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/pages/alarm_page.dart';

/// The full-screen ring surface.
///
/// **No harness at all**, and that is the point of the page: it renders from
/// the payload alone — no `path_provider`, no `SharedPreferences`, no
/// database, no gateway — because a ring arrives in a process where nothing is
/// loaded yet and may belong to a database that is not even open. Every
/// service call the controller makes is best-effort and swallows its own
/// failure, so the page draws identically here and on a phone.
///
/// **No keyboard.** The page resumes the app, so it inherits the stale-inset
/// hazard the UX section describes — an Android activity paused mid
/// keyboard-inset animation comes back with `viewInsets.bottom` stuck at the
/// keyboard height. It has no text field and raises no IME, so there is
/// nothing for a stuck inset to eat and no `max(viewInsets, viewPadding)`
/// clearance to get wrong; a test asserting the clearance would be asserting
/// against a keyboard that can never appear. The one thing worth pinning is
/// that it never grows a field — the assertion below.
void main() {
  final l10n = AppLocalizationsEn();

  AlertPayload payload({
    bool removeAfterAlert = false,
    bool test = false,
    String database = 'gym_notes',
    int snoozeMinutes = 10,
  }) {
    return AlertPayload(
      database: database,
      eventId: test ? AlertPayload.testEventId : 'e1',
      alertId: test ? AlertPayload.testEventId : 'a1',
      dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
      osId: 4242,
      mode: AlertMode.ring,
      title: 'Leg day',
      timeLabel: '07:00',
      categoryId: 'gym',
      removeAfterAlert: removeAfterAlert,
      snoozeMinutes: snoozeMinutes,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    AlertPayload value, {
    AlertRingController? controller,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AlarmPage(payload: value, controller: controller),
      ),
    );
    await tester.pump();
  }

  testWidgets('it draws the ring from the payload alone', (tester) async {
    await pump(tester, payload());

    expect(find.text(l10n.alarmPageTitle.toUpperCase()), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    // The occurrence day, in the app's locale rather than the payload's raw
    // UTC instant.
    expect(find.textContaining('September'), findsOneWidget);
    // Nothing that could raise a keyboard, which is what makes the stale-inset
    // hazard inapplicable to this page.
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('every action is there, and Snooze names the payload length', (
    tester,
  ) async {
    await pump(tester, payload(snoozeMinutes: 15));

    expect(find.text(l10n.alarmStop), findsOneWidget);
    expect(find.text(l10n.alarmSnoozeMinutes(15)), findsOneWidget);
    expect(find.text(l10n.alarmOpenEvent), findsOneWidget);
    // Keep is offered only for an event that would otherwise be deleted.
    expect(find.text(l10n.alarmKeepEvent), findsNothing);

    for (final id in [
      SemanticsIds.alarmStop,
      SemanticsIds.alarmSnooze,
      SemanticsIds.alarmOpenEvent,
    ]) {
      expect(
        find.bySemanticsIdentifier(id),
        findsOneWidget,
        reason: '$id is how a device pass reaches this button in any locale',
      );
    }
  });

  testWidgets('back does nothing while it is ringing', (tester) async {
    await pump(tester, payload());

    final popScope = tester.widget<PopScope<dynamic>>(
      find.descendant(
        of: find.byType(AlarmPage),
        matching: find.byWidgetPredicate((w) => w is PopScope<dynamic>),
      ),
    );
    expect(popScope.canPop, isFalse);
  });

  testWidgets('a removable event explains itself and offers Keep', (
    tester,
  ) async {
    final controller = AlertRingController(
      payload: payload(removeAfterAlert: true),
    );
    addTearDown(controller.dispose);
    await pump(tester, controller.payload, controller: controller);

    expect(find.text(l10n.alarmRemoveAfterCaption), findsOneWidget);
    expect(find.text(l10n.alarmKeepEvent), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.alarmKeepEvent));
    await tester.pump();

    // Keeping withdraws the warning and the offer, and says so once.
    expect(controller.keepEvent, isTrue);
    expect(controller.willRemoveEvent, isFalse);
    expect(find.text(l10n.alarmKeptEvent), findsOneWidget);
    expect(find.text(l10n.alarmRemoveAfterCaption), findsNothing);
    expect(find.text(l10n.alarmKeepEvent), findsNothing);
  });

  testWidgets('an alarm from the open database wears no chip (A9)', (
    tester,
  ) async {
    final same = _FakeRingController(payload(), active: 'gym_notes');
    addTearDown(same.dispose);
    await pump(tester, same.payload, controller: same);

    expect(find.text(l10n.alarmFromDatabase('gym_notes')), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('an alarm from another database names it (A9)', (tester) async {
    final other = _FakeRingController(
      payload(database: 'work'),
      active: 'gym_notes',
    );
    addTearDown(other.dispose);
    await pump(tester, other.payload, controller: other);

    expect(find.text(l10n.alarmFromDatabase('work')), findsOneWidget);
  });

  testWidgets('a test alarm titles itself and cannot open an event', (
    tester,
  ) async {
    await pump(tester, payload(test: true));

    expect(find.text(l10n.alertsTestAlarm), findsOneWidget);
    expect(find.text('Leg day'), findsNothing);
    // There is no event behind a test ring, so the row that would open one is
    // inert rather than absent — the layout must not move between a test and
    // a real alarm.
    final open = tester.widget<TextButton>(
      find.widgetWithText(TextButton, l10n.alarmOpenEvent),
    );
    expect(open.onPressed, isNull);
  });

  testWidgets('Stop closes the page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AlarmPage(payload: payload()),
              ),
            ),
            child: const Text('ring'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ring'));
    await tester.pumpAndSettle();
    expect(find.byType(AlarmPage), findsOneWidget);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.alarmStop));
    await tester.pumpAndSettle();

    expect(find.byType(AlarmPage), findsNothing);
  });
}

/// A controller that already knows which database is open.
///
/// The real one asks `DatabaseManager`, which needs `path_provider`; the chip
/// it drives is the one thing on the page the payload cannot decide by itself,
/// so the answer is supplied rather than the whole harness stood up.
class _FakeRingController extends AlertRingController {
  _FakeRingController(AlertPayload payload, {required this.active})
    : super(payload: payload);

  final String active;

  @override
  String? get activeDatabase => active;

  @override
  bool get fromOtherDatabase => active != payload.database;

  @override
  Future<void> load() async {}
}
