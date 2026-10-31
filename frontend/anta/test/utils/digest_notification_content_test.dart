import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/recurrence_formatter.dart';
import 'package:anta/utils/alert_labels.dart';
import 'package:anta/utils/calendar_report_builder.dart';
import 'package:anta/utils/digest_notification_content.dart';
import 'package:anta/utils/digest_planner.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/report_labels.dart';

/// A digest's words, written once when it is armed (§3.6). Every day is
/// written by [AlertLabels.fixed] — 24-hour `en_US`, the one locale `intl`
/// answers with no date symbols loaded — so the literals hold on any host.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));
  final ro = lookupAppLocalizations(const Locale('ro'));
  final labels = AlertLabels.fixed;

  // A report's words go through `ReportLabels`, which formats in the
  // strings' own locale.
  setUpAll(initializeDateFormatting);

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

  group('a report digest', () {
    const sep = ReportLabels.separator;
    // The week of Mon 19 – Sun 25 October 2026, read on Monday the 26th.
    final week = (
      start: DateTime.utc(2026, 10, 19),
      end: DateTime.utc(2026, 10, 25),
    );
    final today = DateTime.utc(2026, 10, 26);

    CalendarEvent reportEvent(
      String title,
      String categoryId,
      DateTime start, {
      RecurrenceRule rule = const OneTimeRecurrence(),
      bool tracked = false,
      EventTime? time,
      String? description,
    }) => CalendarEvent(
      id: title,
      title: title,
      categoryId: categoryId,
      startDate: start,
      rule: rule,
      tracksPresence: tracked,
      time: time,
      description: description,
    );

    /// The week's report from the builder itself — one sample per day each
    /// event occurs on, as the service samples them — so the words are
    /// checked against the model the page reads.
    CalendarReport reportOf(
      List<CalendarEvent> events, {
      Map<String, DateTime> missed = const {},
    }) {
      final samples = <ReportSample>[];
      for (
        var day = week.start;
        !day.isAfter(week.end);
        day = DateTime.utc(day.year, day.month, day.day + 1)
      ) {
        for (final event in events) {
          if (!event.occursOnUtcDay(day)) continue;
          samples.add(
            ReportSample(
              eventId: event.id,
              day: day,
              missed: missed[event.id] == day,
            ),
          );
        }
      }
      return CalendarReportBuilder.fold(
        ReportInput(
          span: week,
          today: today,
          weekStart: CalendarWeekStart.monday,
          events: {for (final event in events) event.id: event},
          categoryOf: {for (final event in events) event.id: event.categoryId},
          samples: samples,
          categoryOrder: [for (final c in CalendarCategories.all) c.id],
        ),
      );
    }

    PlannedDigest reportFire({
      DigestCadence cadence = DigestCadence.weeklyReport,
      Set<String> categoryIds = const {},
    }) {
      final digest = EventDigest(
        id: 'r1',
        cadence: cadence,
        anchor: 1,
        categoryIds: categoryIds,
      );
      final fireDay = cadence == DigestCadence.weeklyReport
          ? today
          : DateTime.utc(2026, 11, 1);
      final span = DigestPlanner.spanFor(digest, fireDay);
      return PlannedDigest(
        digest: digest,
        fireAt: DateTime(fireDay.year, fireDay.month, fireDay.day, 9),
        spanStart: span.start,
        spanEnd: span.end,
        entries: const [],
      );
    }

    String reportLabel(String id) => switch (id) {
      'gym' => 'Gym',
      'birthday' => 'Birthday',
      'other' => 'To do',
      'mobility' => 'Mobility',
      _ => id,
    };

    DigestNotificationContent reportContent(
      PlannedDigest fire, {
      CalendarReport? report,
      AppLocalizations? strings,
    }) => digestNotificationContent(
      fire,
      strings ?? en,
      labels,
      categoryLabel: reportLabel,
      weekStart: CalendarWeekStart.monday,
      report: report,
    );

    final gym = reportEvent(
      'Gym session',
      'gym',
      DateTime.utc(2026, 10, 5),
      rule: const WeeklyRecurrence(
        weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
      ),
      tracked: true,
      time: const EventTime(startMinute: 18 * 60, durationMinutes: 75),
    );
    final ana = reportEvent(
      'Ana',
      'birthday',
      DateTime.utc(1994, 10, 20),
      rule: const YearlyRecurrence(),
    );
    final mihai = reportEvent(
      'Mihai',
      'birthday',
      DateTime.utc(1986, 10, 24),
      rule: const YearlyRecurrence(),
    );
    final garage = reportEvent(
      'Garage',
      'other',
      DateTime.utc(2026, 10, 22),
      description: '- [x] tyres\n- [ ] oil\n- [x] lights',
    );
    final bank = reportEvent(
      'Call the bank',
      'other',
      DateTime.utc(2026, 10, 23),
    );
    final hike = reportEvent(
      'Hike',
      'mobility',
      DateTime.utc(2026, 10, 25),
      time: const EventTime(startMinute: 10 * 60, durationMinutes: 120),
    );
    final week6 = [gym, ana, mihai, garage, bank, hike];

    test('the title is the report word over the categories label', () {
      expect(reportContent(reportFire()).title, 'Weekly report${sep}Events');
      expect(
        reportContent(reportFire(categoryIds: const {'gym'})).title,
        'Weekly report${sep}Gym',
      );
      expect(
        reportContent(
          reportFire(cadence: DigestCadence.monthlyReport),
          strings: de,
        ).title,
        'Monatsbericht${sep}Termine',
      );
    });

    test('the period is last week or last month, lowercase with its '
        'preposition: it sits mid-sentence (D45)', () {
      String periodOf(PlannedDigest fire, AppLocalizations strings) =>
          digestPeriodOf(
            fire.digest,
            spanStart: fire.spanStart,
            spanEnd: fire.spanEnd,
            strings: strings,
            labels: labels,
            weekStart: CalendarWeekStart.monday,
          );
      final weekly = reportFire();
      final monthly = reportFire(cadence: DigestCadence.monthlyReport);

      expect(periodOf(weekly, en), 'last week');
      expect(periodOf(monthly, en), 'last month');
      expect(periodOf(weekly, de), 'in der letzten Woche');
      expect(periodOf(monthly, de), 'im letzten Monat');
      expect(periodOf(weekly, ro), 'săptămâna trecută');
      expect(periodOf(monthly, ro), 'luna trecută');
      expect(
        en.digestCountPeriod(5, periodOf(weekly, en)),
        '5 events last week',
      );
      expect(
        de.digestCountPeriod(5, periodOf(monthly, de)),
        '5 Termine im letzten Monat',
      );
    });

    test('a span not yet ended says only that the report is ready', () {
      final weekly = reportContent(reportFire());
      final monthly = reportContent(
        reportFire(cadence: DigestCadence.monthlyReport),
      );

      expect(weekly.text, "Last week's report is ready");
      expect(weekly.lines, isEmpty);
      expect(weekly.summary, isNull);
      expect(monthly.text, "Last month's report is ready");
      expect(
        reportContent(reportFire(), strings: de).text,
        'Der Bericht der letzten Woche ist fertig',
      );
    });

    test('an ended span: the summary, then a line per category by its '
        'dominant shape', () {
      final report = reportOf(
        week6,
        missed: {gym.id: DateTime.utc(2026, 10, 23)},
      );

      final content = reportContent(reportFire(), report: report);

      // Every category: the facts alone, never "Events — …" (D45).
      final summary = '2 of 3 attended${sep}4.5 h${sep}1 missed';
      expect(content.text, summary);
      expect(content.lines, [
        summary,
        // The report's own order: equal counts in the catalogue's order.
        'Birthday${sep}2${sep}Ana, Mihai',
        'Gym${sep}2 of 3${sep}2.5 h',
        'To do${sep}2${sep}2 of 3 tasks',
        'Mobility${sep}1${sep}2 h',
      ]);
      expect(content.summary, isNull);
    });

    test("a named selection keeps the categories label's prefix: one "
        'name, a count past that (D45)', () {
      final report = reportOf(
        [gym, ana, mihai],
        missed: {gym.id: DateTime.utc(2026, 10, 23)},
      );
      const facts = '2 of 3 attended${sep}2.5 h${sep}1 missed';

      expect(
        reportContent(
          reportFire(categoryIds: const {'gym'}),
          report: report,
        ).text,
        'Gym — $facts',
      );
      expect(
        reportContent(
          reportFire(categoryIds: const {'gym', 'birthday'}),
          report: report,
        ).text,
        '2 categories — $facts',
      );
      expect(reportContent(reportFire(), report: report).text, facts);
    });

    test("the report's counts group their digits (D45)", () {
      expect(de.reportEventCount(1234), '1.234 Termine');
      expect(de.reportAttendedOf(1234, 1200), '1.200 von 1.234 anwesend');
      expect(en.reportTasksOf(1234, 1001), '1,001 of 1,234 tasks');
      expect(ro.reportGroupMore(1234), 'Încă 1.234');
    });

    test('a selection that tracks nothing counts what happened', () {
      final report = reportOf([ana, mihai]);

      final content = reportContent(
        reportFire(categoryIds: const {'birthday'}),
        report: report,
      );

      expect(content.text, 'Birthday — 2 events');
      expect(content.lines, [
        'Birthday — 2 events',
        'Birthday${sep}2${sep}Ana, Mihai',
      ]);
    });

    test('a paused routine beside three birthdays counts the birthdays, '
        'never "0 of 0 attended" (D43)', () {
      final ioana = reportEvent(
        'Ioana',
        'birthday',
        DateTime.utc(2019, 10, 22),
        rule: const YearlyRecurrence(),
      );
      final paused = reportEvent(
        'Cake class',
        'birthday',
        DateTime.utc(2026, 9, 1),
        rule: const WeeklyRecurrence(weekdays: {DateTime.tuesday}),
        tracked: true,
      ).copyWith(endDate: DateTime.utc(2026, 9, 30));
      final report = reportOf([ana, mihai, ioana, paused]);
      final attended = report.tiles.where(
        (tile) => tile.tile == ReportTile.attended,
      );
      // The probe's premise: the builder still emits the empty share.
      expect(attended.single.of, 0);

      final content = reportContent(
        reportFire(categoryIds: const {'birthday'}),
        report: report,
      );

      expect(content.text, 'Birthday — 3 events');
      expect(content.lines, [
        'Birthday — 3 events',
        'Birthday${sep}3${sep}Ana, Ioana, Mihai',
      ]);
    });

    test("a routine line's hours are its routines' alone, not a timed "
        "one-off's beside them (D43)", () {
      final physio = reportEvent(
        'Physio',
        'gym',
        DateTime.utc(2026, 10, 21),
        time: const EventTime(startMinute: 8 * 60, durationMinutes: 60),
      );
      final report = reportOf(
        [gym, physio],
        missed: {gym.id: DateTime.utc(2026, 10, 23)},
      );

      final content = reportContent(
        reportFire(categoryIds: const {'gym'}),
        report: report,
      );

      // The summary still counts the hour of the one-off: 2 × 75 + 60.
      expect(content.text, 'Gym — 2 of 3 attended${sep}3.5 h${sep}1 missed');
      expect(content.lines[1], 'Gym${sep}2 of 3${sep}2.5 h');
    });

    test('the summary is the language\'s template over the categories and '
        'the facts', () {
      final report = reportOf([ana, mihai]);

      final content = reportContent(
        reportFire(categoryIds: const {'birthday'}),
        report: report,
        strings: de,
      );

      expect(content.text, de.digestReportSummary('Birthday', '2 Termine'));
    });

    test('more than five lines fold into how many more', () {
      final extra = [
        for (final (title, category) in [
          ('Run', 'cardio'),
          ('Nap', 'rest'),
          ('Race', 'competition'),
        ])
          reportEvent(title, category, DateTime.utc(2026, 10, 21)),
      ];
      final report = reportOf([...week6, ...extra]);

      final content = reportContent(reportFire(), report: report);

      expect(report.categories, hasLength(7));
      expect(content.lines, hasLength(5));
      expect(content.lines.first, content.text);
      expect(content.summary, '+3 more');
    });
  });
}
