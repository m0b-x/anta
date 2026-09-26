import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/event_detail_sheet.dart';

/// A pinned-dates event shows its whole set on the detail sheet instead of
/// the recurring "next occurrences" scan, and both one-time and pinned
/// events offer Add date as an action the host runs.
void main() {
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  DateTime offset(int days) => today.add(Duration(days: days));

  CalendarEvent event({required RecurrenceRule rule, DateTime? startDate}) =>
      CalendarEvent(
        id: 'e1',
        title: 'Physio',
        categoryId: 'health',
        startDate: startDate ?? today,
        rule: rule,
      );

  Future<List<EventDetailAction?>> openSheet(
    WidgetTester tester,
    CalendarEvent subject, {
    DateTime? day,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 1800);
    final actions = <EventDetailAction?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                actions.add(
                  await EventDetailSheet.show(
                    context,
                    event: subject,
                    day: day ?? today,
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

  testWidgets('a pinned-dates event lists its whole set with the count ahead', (
    tester,
  ) async {
    await openSheet(
      tester,
      event(
        startDate: offset(-7),
        rule: SpecificDatesRecurrence(
          dates: {offset(-7), today, offset(7), offset(14)},
        ),
      ),
    );

    expect(find.text('Dates'), findsOneWidget);
    expect(find.text('3 of 4 ahead'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(4));
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Next occurrences'), findsNothing);
    expect(find.textContaining('Repeats since'), findsNothing);
    expect(find.text('4 dates'), findsOneWidget);
  });

  testWidgets('past eight dates only the next few show, with an All chip that '
      'pops showDates', (tester) async {
    final dates = {for (var i = -2; i < 8; i++) offset(i)};
    final actions = await openSheet(
      tester,
      event(
        startDate: offset(-2),
        rule: SpecificDatesRecurrence(dates: dates),
      ),
    );

    expect(find.text('8 of 10 ahead'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(3));
    expect(find.widgetWithText(ActionChip, 'All 10 dates'), findsOneWidget);

    await tester.tap(find.text('All 10 dates'));
    await tester.pumpAndSettle();
    expect(actions, [EventDetailAction.showDates]);
  });

  testWidgets('with every date past, the most recent few show', (tester) async {
    final dates = {for (var i = -12; i < -2; i++) offset(i)};
    await openSheet(
      tester,
      event(
        startDate: offset(-12),
        rule: SpecificDatesRecurrence(dates: dates),
      ),
      day: offset(-3),
    );

    expect(find.text('All in the past'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(3));
    expect(find.widgetWithText(ActionChip, 'All 10 dates'), findsOneWidget);
  });

  testWidgets('Add date pops addDate for a one-time event', (tester) async {
    final actions = await openSheet(
      tester,
      event(rule: const OneTimeRecurrence()),
    );

    await tester.tap(find.text('Add date'));
    await tester.pumpAndSettle();
    expect(actions, [EventDetailAction.addDate]);
  });

  testWidgets('Add date pops addDate for a pinned-dates event', (tester) async {
    final actions = await openSheet(
      tester,
      event(rule: SpecificDatesRecurrence(dates: {today, offset(7)})),
    );

    await tester.tap(find.text('Add date'));
    await tester.pumpAndSettle();
    expect(actions, [EventDetailAction.addDate]);
  });

  testWidgets('a periodic event offers no Add date and keeps the scan', (
    tester,
  ) async {
    await openSheet(
      tester,
      event(
        rule: const WeeklyRecurrence(
          weekdays: {1, 2, 3, 4, 5, 6, 7},
          interval: 1,
        ),
      ),
    );

    expect(find.text('Add date'), findsNothing);
    expect(find.text('Next occurrences'), findsOneWidget);
  });
}
