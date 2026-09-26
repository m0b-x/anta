import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/event_detail_sheet.dart';

/// A pinned-dates event reads its set back on the detail sheet through one
/// bundled Dates row — the editor's two-line value — instead of the recurring
/// "next occurrence" scan, and both one-time and pinned events offer Add date
/// as an action the host runs.
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

  testWidgets('a pinned-dates event reads the opened day and one bundled '
      'Dates row', (tester) async {
    await openSheet(
      tester,
      event(
        startDate: offset(-7),
        rule: SpecificDatesRecurrence(
          dates: {offset(-7), today, offset(7), offset(14)},
        ),
      ),
    );

    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Dates'), findsOneWidget);
    expect(find.textContaining('4 dates'), findsOneWidget);
    expect(find.textContaining('3 of 4 ahead'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Next occurrence'), findsNothing);
    expect(find.text('Repeat'), findsNothing);
    expect(find.text('Start date'), findsNothing);
  });

  testWidgets('past eight dates the row still reads the whole set, and '
      'opens the list', (tester) async {
    final dates = {for (var i = -2; i < 8; i++) offset(i)};
    final actions = await openSheet(
      tester,
      event(
        startDate: offset(-2),
        rule: SpecificDatesRecurrence(dates: dates),
      ),
    );

    expect(find.textContaining('10 dates'), findsOneWidget);
    expect(find.textContaining('8 of 10 ahead'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.eventDetailDates));
    await tester.pumpAndSettle();
    expect(actions, [EventDetailAction.showDates]);
  });

  testWidgets('with every date past, the row says so', (tester) async {
    final dates = {for (var i = -12; i < -2; i++) offset(i)};
    await openSheet(
      tester,
      event(
        startDate: offset(-12),
        rule: SpecificDatesRecurrence(dates: dates),
      ),
      day: offset(-3),
    );

    expect(find.textContaining('All in the past'), findsOneWidget);
    expect(find.textContaining('10 dates'), findsOneWidget);
  });

  testWidgets('Add date pops addDate for a one-time event', (tester) async {
    final actions = await openSheet(
      tester,
      event(rule: const OneTimeRecurrence()),
    );

    expect(find.text('Dates'), findsNothing);
    await tester.tap(find.text('Add date'));
    await tester.pumpAndSettle();
    expect(actions, [EventDetailAction.addDate]);
  });

  testWidgets('Add date pops addDate for a pinned-dates event', (tester) async {
    final actions = await openSheet(
      tester,
      event(rule: SpecificDatesRecurrence(dates: {today, offset(7)})),
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.eventDetailAddDate),
    );
    await tester.pumpAndSettle();
    expect(actions, [EventDetailAction.addDate]);
  });

  testWidgets('a periodic event offers no Add date and reads its next '
      'occurrence', (tester) async {
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
    expect(find.text('Dates'), findsNothing);
    expect(find.text('Next occurrence'), findsOneWidget);
  });
}
