import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/recurrence_formatter.dart';
import 'package:anta/utils/alert_labels.dart';
import 'package:anta/utils/digest_notification_content.dart';
import 'package:anta/utils/digest_planner.dart';
import 'package:anta/utils/event_agenda.dart';

/// A digest's words, written once when it is armed (§3.6). Every day is
/// written by [AlertLabels.fixed] — 24-hour `en_US`, the one locale `intl`
/// answers with no date symbols loaded — so the literals hold on any host.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));
  final ro = lookupAppLocalizations(const Locale('ro'));
  final labels = AlertLabels.fixed;

  String labelOf(String id) => switch (id) {
    'birthday' => 'Birthdays',
    'gym' => 'Training',
    _ => id,
  };

  CalendarEvent eventOf(
    String title,
    DateTime day, {
    RecurrenceRule rule = const OneTimeRecurrence(),
    bool countOccurrences = false,
  }) => CalendarEvent(
    id: title,
    title: title,
    categoryId: 'birthday',
    startDate: day,
    rule: rule,
    countOccurrences: countOccurrences,
  );

  EventOccurrence on(CalendarEvent event, DateTime day) =>
      EventOccurrence(event: event, day: day);

  PlannedDigest fireOf({
    String name = '',
    DigestCadence cadence = DigestCadence.monthly,
    int anchor = 1,
    int leadDays = 0,
    Set<String> categoryIds = const {'birthday'},
    required DateTime spanStart,
    DateTime? spanEnd,
    List<EventOccurrence> entries = const [],
  }) {
    final digest = EventDigest(
      id: 'd1',
      name: name,
      cadence: cadence,
      anchor: anchor,
      leadDays: leadDays,
      categoryIds: categoryIds,
    );
    return PlannedDigest(
      digest: digest,
      fireAt: DateTime(spanStart.year, spanStart.month, spanStart.day, 9),
      spanStart: spanStart,
      // The span from its own first day, whatever the lead that put it there.
      spanEnd:
          spanEnd ??
          DigestPlanner.spanFor(digest.copyWith(leadDays: 0), spanStart).end,
      entries: entries,
    );
  }

  DigestNotificationContent contentOf(
    PlannedDigest fire, {
    AppLocalizations? strings,
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
  }) => digestNotificationContent(
    fire,
    strings ?? en,
    labels,
    categoryLabel: labelOf,
    weekStart: weekStart,
  );

  final october = DateTime.utc(2026, 10, 1);
  final monday = DateTime.utc(2026, 10, 5);

  PlannedDigest thisWeek() => fireOf(
    cadence: DigestCadence.weekly,
    anchor: DateTime.monday,
    spanStart: monday,
  );

  PlannedDigest nextWeek() => fireOf(
    cadence: DigestCadence.weekly,
    anchor: DateTime.sunday,
    leadDays: 1,
    spanStart: monday,
  );

  // Fired on 28 October, four days ahead: November, whole.
  PlannedDigest nextMonth() =>
      fireOf(anchor: 28, leadDays: 4, spanStart: DateTime.utc(2026, 11, 1));

  group('the title', () {
    test("is the digest's own name", () {
      expect(
        contentOf(fireOf(name: 'Family', spanStart: october)).title,
        'Family',
      );
    });

    test('else the one category it lists', () {
      expect(contentOf(fireOf(spanStart: october)).title, 'Birthdays');
    });

    test('else "Events" over every category', () {
      expect(
        contentOf(fireOf(categoryIds: const {}, spanStart: october)).title,
        'Events',
      );
    });

    test('else how many categories it lists', () {
      final fire = fireOf(
        categoryIds: const {'birthday', 'gym', 'other'},
        spanStart: october,
      );
      expect(contentOf(fire).title, '3 categories');
      expect(contentOf(fire, strings: de).title, '3 Kategorien');
    });

    test('a name of spaces is no name', () {
      expect(
        contentOf(fireOf(name: '  ', spanStart: october)).title,
        'Birthdays',
      );
    });
  });

  group('the period', () {
    String textOf(
      PlannedDigest fire, {
      CalendarWeekStart weekStart = CalendarWeekStart.monday,
      AppLocalizations? strings,
    }) => contentOf(fire, weekStart: weekStart, strings: strings).text;

    test('daily: today, or tomorrow with a lead of one', () {
      final day = DateTime.utc(2026, 10, 6);
      expect(
        textOf(fireOf(cadence: DigestCadence.daily, anchor: 0, spanStart: day)),
        'No events today',
      );
      expect(
        textOf(
          fireOf(
            cadence: DigestCadence.daily,
            anchor: 0,
            leadDays: 1,
            spanStart: day,
          ),
        ),
        'No events tomorrow',
      );
    });

    test('weekly from the week start: this week, or next week', () {
      expect(textOf(thisWeek()), 'No events this week');
      expect(textOf(nextWeek()), 'No events next week');
    });

    test("the week start is the app's, never the locale's", () {
      final fire = fireOf(
        cadence: DigestCadence.weekly,
        anchor: DateTime.sunday,
        spanStart: DateTime.utc(2026, 10, 4),
      );

      expect(
        textOf(fire, weekStart: CalendarWeekStart.sunday),
        'No events this week',
      );
      expect(
        textOf(fire, weekStart: CalendarWeekStart.monday),
        'No events from Oct 4 to Oct 10',
      );
    });

    test('weekly from mid-week is its two ends', () {
      expect(
        textOf(
          fireOf(
            cadence: DigestCadence.weekly,
            anchor: DateTime.wednesday,
            spanStart: DateTime.utc(2026, 10, 7),
          ),
        ),
        'No events from Oct 7 to Oct 13',
      );
    });

    test('monthly from the 1st: this month, or next month', () {
      expect(textOf(fireOf(spanStart: october)), 'No events this month');
      expect(textOf(nextMonth()), 'No events next month');
    });

    test('monthly from the 15th is its two ends', () {
      expect(
        textOf(fireOf(anchor: 15, spanStart: DateTime.utc(2026, 10, 15))),
        'No events from Oct 15 to Nov 14',
      );
    });

    test('monthly on the 1st with a lead of one is not a calendar month', () {
      expect(
        textOf(fireOf(leadDays: 1, spanStart: DateTime.utc(2026, 10, 2))),
        'No events from Oct 2 to Nov 1',
      );
    });

    test('a span no word names is one sentence in every language', () {
      final fire = fireOf(anchor: 15, spanStart: DateTime.utc(2026, 10, 15));

      expect(textOf(fire, strings: de), startsWith('Keine Termine vom '));
      expect(textOf(fire, strings: ro), startsWith('Niciun eveniment din '));
    });

    test('German names the calendar unit as a sentence would', () {
      expect(
        textOf(fireOf(spanStart: october), strings: de),
        'Keine Termine in diesem Monat',
      );
      expect(
        textOf(nextMonth(), strings: de),
        'Keine Termine im nächsten Monat',
      );
      expect(textOf(thisWeek(), strings: de), 'Keine Termine in dieser Woche');
      expect(
        textOf(nextWeek(), strings: de),
        'Keine Termine in der nächsten Woche',
      );
    });
  });

  group('the lines', () {
    test('an empty span is the =0 form, with no lines and no summary', () {
      final content = contentOf(fireOf(spanStart: october));

      expect(content.text, 'No events this month');
      expect(content.lines, isEmpty);
      expect(content.summary, isNull);
    });

    test('each occurrence is its day and title; the collapsed text names '
        'its date alone', () {
      final content = contentOf(
        fireOf(
          spanStart: october,
          entries: [
            on(
              eventOf('Ana', DateTime.utc(2026, 10, 4)),
              DateTime.utc(2026, 10, 4),
            ),
            on(
              eventOf('Mihai', DateTime.utc(2026, 10, 12)),
              DateTime.utc(2026, 10, 12),
            ),
          ],
        ),
      );

      expect(content.lines, ['Sun, Oct 4 · Ana', 'Mon, Oct 12 · Mihai']);
      expect(content.text, '2 events this month · Oct 4 · Ana, Oct 12 · Mihai');
      expect(content.summary, isNull);
    });

    test('five lines, then how many more', () {
      final entries = [
        for (var day = 1; day <= 7; day++)
          on(
            eventOf('E$day', DateTime.utc(2026, 10, day)),
            DateTime.utc(2026, 10, day),
          ),
      ];

      final content = contentOf(fireOf(spanStart: october, entries: entries));

      expect(content.lines, hasLength(5));
      expect(content.lines.last, 'Mon, Oct 5 · E5');
      expect(content.summary, '+2 more');
      expect(content.text, startsWith('7 events this month · '));
      expect(content.text, endsWith('Oct 4 · E4, Oct 5 · E5'));
    });

    test('an event that counts its occurrences says which one', () {
      final ana = eventOf(
        'Ana',
        DateTime.utc(1996, 10, 4),
        rule: const YearlyRecurrence(),
        countOccurrences: true,
      );
      final day = DateTime.utc(2026, 10, 4);
      final count = RecurrenceFormatter.countLabel(ana, day, en);

      final content = contentOf(
        fireOf(spanStart: october, entries: [on(ana, day)]),
      );

      expect(count, isNotNull);
      expect(content.lines.single, 'Sun, Oct 4 · Ana · $count');
      // The collapsed row keeps to the date and the title.
      expect(content.text, '1 event this month · Oct 4 · Ana');
    });
  });
}
