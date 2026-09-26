import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/event_time_formatter.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// The detail sheet in the editor's language (2026-09-26): the chrome, the
/// read rule (a row exists only while it carries a fact), the WHEN values,
/// the presence chips, Skip this day, the alert rows, the linked note's three
/// states, and the layout under German at text scale 2.0 on a small phone.
/// Behaviour the older suites pin — ticks, the quick edit, wiki links, the
/// Dates row — stays there.
void main() {
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  DateTime offset(int days) => today.add(Duration(days: days));

  const everyDay = WeeklyRecurrence(weekdays: {1, 2, 3, 4, 5, 6, 7});

  CalendarEvent event({
    RecurrenceRule rule = const OneTimeRecurrence(),
    DateTime? startDate,
    DateTime? endDate,
    EventTime? time,
    String? description,
    String? noteId,
    int priority = kDefaultEventPriority,
    bool tracksPresence = false,
    bool removeAfterAlert = false,
    String title = 'Leg day',
  }) => CalendarEvent(
    id: 'e1',
    title: title,
    categoryId: 'gym',
    startDate: startDate ?? today,
    endDate: endDate,
    rule: rule,
    time: time,
    description: description,
    noteId: noteId,
    priority: priority,
    tracksPresence: tracksPresence,
    removeAfterAlert: removeAfterAlert,
  );

  tearDown(() {
    EventAlerts.resetCache();
    EventSkips.resetCache();
  });

  /// Opens the sheet and records the action it pops with.
  Future<List<EventDetailAction?>> openSheet(
    WidgetTester tester,
    CalendarEvent subject, {
    DateTime? day,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 1800),
    double textScale = 1,
    void Function(DateTime day, bool missed)? onPresenceChanged,
    Future<String?> Function(String noteId)? resolveNoteTitle,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    final actions = <EventDetailAction?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          // A 24-hour clock, so the Time row's expectations read as the
          // neutral strings the rest of the calendar prints.
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                actions.add(
                  await EventDetailSheet.show(
                    context,
                    event: subject,
                    day: day ?? today,
                    onPresenceChanged: onPresenceChanged,
                    resolveNoteTitle: resolveNoteTitle,
                  ),
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
    return actions;
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(EventDetailSheet)))!;

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

  group('chrome', () {
    testWidgets('close pops null, Edit pops edit, and Edit is a text button', (
      tester,
    ) async {
      final actions = await openSheet(tester, event());
      expect(find.byType(FilledButton), findsNothing);
      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
      expect(find.byType(FormSheetHandle), findsOneWidget);
      expect(find.byType(FormSheetHeader), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailEdit),
      );
      await tester.pumpAndSettle();
      expect(actions, [EventDetailAction.edit]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailClose),
      );
      await tester.pumpAndSettle();
      expect(actions, [EventDetailAction.edit, null]);
    });

    testWidgets('the barrier pops null and the sheet is as tall as its '
        'content', (tester) async {
      final actions = await openSheet(tester, event());
      final sheet = tester.getRect(find.byType(EventDetailSheet));
      expect(sheet.top, greaterThan(600), reason: 'a one-time event is short');
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(actions, [null]);
    });

    testWidgets('the title row shows the title and the category', (
      tester,
    ) async {
      await openSheet(tester, event());
      expect(find.text('Leg day'), findsOneWidget);
      // A bare test has no category facade, so the caption is whatever the
      // resolver falls back to — the same call the sheet makes.
      final category = CalendarCategories.resolve('gym');
      expect(
        find.text(CalendarCategories.labelOf(category, l10nOf(tester))),
        findsOneWidget,
      );
    });
  });

  group('the read rule', () {
    testWidgets('a one-time event with defaults has WHEN and nothing else', (
      tester,
    ) async {
      await openSheet(tester, event());
      expect(find.text('WHEN'), findsOneWidget);
      expect(find.text('OCCURRENCES'), findsNothing);
      expect(find.text('ALERTS'), findsNothing);
      expect(find.text('DETAILS'), findsNothing);
      expect(find.text('Priority'), findsNothing);
      expect(find.text('Linked note'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Skip this day'), findsNothing);
      expect(find.text('Presence'), findsNothing);
    });

    testWidgets('a non-default priority brings DETAILS', (tester) async {
      await openSheet(tester, event(priority: 1));
      expect(find.text('DETAILS'), findsOneWidget);
      expect(find.text('Priority'), findsOneWidget);
      expect(find.text('Highest'), findsOneWidget);
    });
  });

  group('WHEN', () {
    testWidgets('an all-day event reads All day under Time', (tester) async {
      await openSheet(tester, event());
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('All day'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
    });

    testWidgets('a timed event reads its range and its duration', (
      tester,
    ) async {
      await openSheet(
        tester,
        event(time: const EventTime(startMinute: 18 * 60, durationMinutes: 75)),
      );
      final duration = EventTimeFormatter.formatDuration(75, l10nOf(tester));
      expect(find.text('18:00 – 19:15 · $duration'), findsOneWidget);
    });

    testWidgets('a start without an end reads the start alone', (tester) async {
      await openSheet(tester, event(time: const EventTime(startMinute: 450)));
      expect(find.text('07:30'), findsOneWidget);
    });

    testWidgets('Repeat carries the end date, and Start date shows only when '
        'it differs from the opened day', (tester) async {
      await openSheet(
        tester,
        event(rule: everyDay, startDate: offset(-7), endDate: offset(30)),
      );
      expect(find.text('Repeat'), findsOneWidget);
      expect(find.textContaining('until'), findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('Next occurrence'), findsOneWidget);
    });

    testWidgets('opened on the series start, there is no Start date row', (
      tester,
    ) async {
      await openSheet(tester, event(rule: everyDay));
      expect(find.text('Start date'), findsNothing);
      expect(find.textContaining('until'), findsNothing);
    });

    testWidgets('Next occurrence lists the following days as a caption', (
      tester,
    ) async {
      await openSheet(tester, event(rule: everyDay, startDate: offset(-7)));
      expect(find.text('Next occurrence'), findsOneWidget);
      // Opened on today's occurrence, "next" is tomorrow — never the day the
      // Date row already names.
      expect(
        find.text(DateFormat.MMMEd('en').format(offset(1))),
        findsOneWidget,
      );
      expect(find.textContaining('then '), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
    });

    testWidgets('an ended series reads No upcoming occurrences', (
      tester,
    ) async {
      await openSheet(
        tester,
        event(rule: everyDay, startDate: offset(-30), endDate: offset(-2)),
        day: offset(-3),
      );
      expect(find.text('No upcoming occurrences'), findsOneWidget);
      expect(find.textContaining('then '), findsNothing);
    });
  });

  group('OCCURRENCES', () {
    testWidgets('the presence chips write immediately and read the tap back', (
      tester,
    ) async {
      final writes = <(DateTime, bool)>[];
      await openSheet(
        tester,
        event(rule: everyDay, startDate: offset(-14), tracksPresence: true),
        onPresenceChanged: (day, missed) => writes.add((day, missed)),
      );
      expect(find.text('Presence'), findsOneWidget);
      expect(
        dataOf(
          tester,
          SemanticsIds.eventDetailPresent,
        ).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(find.textContaining('attended'), findsOneWidget);
      expect(find.textContaining('Streak'), findsOneWidget);
      final attendedBefore = tester
          .widget<Text>(find.textContaining('attended'))
          .data;

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailMissed),
      );
      await tester.pumpAndSettle();
      expect(writes, [(today, true)]);
      // The adherence line moves with the tap, before the write lands.
      expect(
        tester.widget<Text>(find.textContaining('attended')).data,
        isNot(attendedBefore),
      );
      expect(
        dataOf(
          tester,
          SemanticsIds.eventDetailMissed,
        ).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        dataOf(
          tester,
          SemanticsIds.eventDetailPresent,
        ).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(find.byType(EventDetailSheet), findsOneWidget);
    });

    testWidgets('without the presence callback there are no chips', (
      tester,
    ) async {
      await openSheet(tester, event(rule: everyDay, tracksPresence: true));
      expect(find.text('Presence'), findsNothing);
      expect(find.byType(FormChip), findsNothing);
    });

    testWidgets('Skip this day pops skipOccurrence on a recurring event', (
      tester,
    ) async {
      final actions = await openSheet(tester, event(rule: everyDay));
      expect(find.text('OCCURRENCES'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailSkip),
      );
      await tester.pumpAndSettle();
      expect(actions, [EventDetailAction.skipOccurrence]);
    });

    testWidgets('a day already skipped offers no Skip', (tester) async {
      EventSkips.updateCache(
        byEvent: {
          'e1': {today},
        },
      );
      await openSheet(tester, event(rule: everyDay, startDate: offset(-7)));
      expect(find.text('Skip this day'), findsNothing);
    });
  });

  group('ALERTS', () {
    testWidgets('one row per alert, its kind as the value, tapping opens the '
        'editor', (tester) async {
      EventAlerts.updateCache(
        byEvent: {
          'e1': const [
            EventAlert(id: 'a1', eventId: 'e1', mode: AlertMode.ring),
            EventAlert(
              id: 'a2',
              eventId: 'e1',
              mode: AlertMode.notify,
              offsetMinutes: 30,
            ),
          ],
        },
      );
      final actions = await openSheet(
        tester,
        event(time: const EventTime(startMinute: 450)),
      );
      expect(find.text('ALERTS'), findsOneWidget);
      expect(find.text('At start'), findsOneWidget);
      expect(find.text('Alarm'), findsOneWidget);
      expect(find.text('30 min before'), findsOneWidget);
      expect(find.text('Reminder'), findsOneWidget);
      expect(find.text('Remove after it rings'), findsNothing);

      await tester.tap(find.text('At start'));
      await tester.pumpAndSettle();
      expect(actions, [EventDetailAction.edit]);
    });

    testWidgets('Remove after it rings is a fact row under the alerts', (
      tester,
    ) async {
      EventAlerts.updateCache(
        byEvent: {
          'e1': const [
            EventAlert(id: 'a1', eventId: 'e1', mode: AlertMode.ring),
          ],
        },
      );
      await openSheet(
        tester,
        event(time: const EventTime(startMinute: 450), removeAfterAlert: true),
      );
      expect(find.text('Remove after it rings'), findsOneWidget);
    });
  });

  group('the linked note', () {
    testWidgets('shows its title once resolved and opens on tap', (
      tester,
    ) async {
      final actions = await openSheet(
        tester,
        event(noteId: 'n1'),
        resolveNoteTitle: (_) async => 'Leg day log',
      );
      expect(find.text('DETAILS'), findsOneWidget);
      expect(find.text('Linked note'), findsOneWidget);
      expect(find.text('Leg day log'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailNote),
      );
      await tester.pumpAndSettle();
      expect(actions, [EventDetailAction.openNote]);
    });

    testWidgets('an empty title reads Untitled Note', (tester) async {
      await openSheet(
        tester,
        event(noteId: 'n1'),
        resolveNoteTitle: (_) async => '',
      );
      expect(find.text('Untitled Note'), findsOneWidget);
    });

    testWidgets('a missing note reads Not found with the full sentence as '
        'its semantics', (tester) async {
      await openSheet(
        tester,
        event(noteId: 'n1'),
        resolveNoteTitle: (_) async => null,
      );
      expect(find.text('Not found'), findsOneWidget);
      expect(
        dataOf(tester, SemanticsIds.eventDetailNote).label,
        'Linked note no longer exists',
      );
    });

    testWidgets('without a resolver the row still stands, with no title', (
      tester,
    ) async {
      await openSheet(tester, event(noteId: 'n1'));
      expect(find.text('Linked note'), findsOneWidget);
      expect(find.text('Untitled Note'), findsNothing);
      expect(find.text('Not found'), findsNothing);
    });
  });

  group('layout stress', () {
    testWidgets('German at text scale 2.0 on a 360 × 780 phone lays out '
        'without overflow', (tester) async {
      EventAlerts.updateCache(
        byEvent: {
          'e1': const [
            EventAlert(
              id: 'a1',
              eventId: 'e1',
              mode: AlertMode.notify,
              offsetMinutes: 30,
            ),
          ],
        },
      );
      await openSheet(
        tester,
        event(
          title: 'Schwere Woche mit Kniebeugen und Kreuzheben',
          rule: everyDay,
          startDate: offset(-7),
          endDate: offset(60),
          time: const EventTime(startMinute: 18 * 60, durationMinutes: 75),
          description: '- [ ] Aufwärmen 10 Min.\n- [ ] Kniebeuge 5×5',
          noteId: 'n1',
          priority: 2,
          tracksPresence: true,
        ),
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScale: 2.0,
        onPresenceChanged: (_, _) {},
        resolveNoteTitle: (_) async => 'Beintag-Log',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Uhrzeit'), findsOneWidget);
      expect(find.text('Anwesenheit'), findsOneWidget);
      expect(find.text('Diesen Tag auslassen'), findsOneWidget);
      expect(find.text('Bearbeiten'), findsOneWidget);
      final sheet = tester.getRect(find.byType(EventDetailSheet));
      expect(sheet.height, lessThanOrEqualTo(780 * 0.92 + 1));
    });

    testWidgets('every driver id is on the sheet', (tester) async {
      await openSheet(
        tester,
        event(
          rule: everyDay,
          startDate: offset(-7),
          description: 'Squats',
          noteId: 'n1',
          tracksPresence: true,
        ),
        onPresenceChanged: (_, _) {},
      );
      for (final id in [
        SemanticsIds.eventDetailEdit,
        SemanticsIds.eventDetailClose,
        SemanticsIds.eventDetailDescription,
        SemanticsIds.eventDetailPresent,
        SemanticsIds.eventDetailMissed,
        SemanticsIds.eventDetailSkip,
        SemanticsIds.eventDetailNote,
      ]) {
        expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
      }
    });
  });
}
