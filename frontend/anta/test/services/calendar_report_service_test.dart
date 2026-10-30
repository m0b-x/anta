import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_report_service.dart';

/// The service is the boundary between the live facades and the pure fold,
/// so the risks are what crosses it — one sample per occurrence, the missed
/// flag only where a day could be missed, the texts and skips of the span —
/// and when the memo may answer instead of a fold.
void main() {
  DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
  DateRange span(DateTime start, DateTime end) => (start: start, end: end);

  CalendarEvent ev(
    String id,
    String categoryId,
    DateTime start, {
    RecurrenceRule rule = const OneTimeRecurrence(),
    bool tracked = false,
    bool assumeAbsent = false,
    bool perDay = false,
    EventTime? time,
  }) {
    return CalendarEvent(
      id: id,
      title: id,
      categoryId: categoryId,
      startDate: start,
      rule: rule,
      tracksPresence: tracked,
      assumeAbsent: assumeAbsent,
      perOccurrenceDescriptions: perDay,
      time: time,
    );
  }

  ReportRequest request({
    required DateRange span,
    DateRange? previousSpan,
    Set<String> categoryIds = const {},
    required List<CalendarEvent> events,
    required DateTime today,
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    int occurrenceRevision = 0,
    int membershipRevision = 0,
    int presenceRevision = 0,
  }) {
    return ReportRequest(
      span: span,
      previousSpan: previousSpan,
      categoryIds: categoryIds,
      events: events,
      today: today,
      weekStart: weekStart,
      occurrenceRevision: occurrenceRevision,
      membershipRevision: membershipRevision,
      presenceRevision: presenceRevision,
    );
  }

  ReportTileValue tile(CalendarReport report, ReportTile kind) =>
      report.tiles.singleWhere((t) => t.tile == kind);

  void seedCategories() {
    CalendarCategories.updateCache([
      for (final (i, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: CalendarCategories.builtInSeedName(seed.kind),
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: i,
          isBuiltIn: true,
        ),
      const CalendarCategory(
        id: 'friends',
        name: 'Friends',
        colorValue: 0xFF3949AB,
        iconKey: 'event',
        sortOrder: 9,
        isBuiltIn: false,
      ),
    ]);
  }

  setUp(seedCategories);

  tearDown(() {
    EventPresence.resetCache();
    EventSkips.resetCache();
    OccurrenceDescriptions.resetCache();
    CalendarCategories.updateCache(const []);
  });

  group('sampling', () {
    // October 2026 starts on a Thursday: Mondays 5, 12, 19, 26; Tuesdays 6,
    // 13, 20, 27; Wednesdays 7, 14, 21, 28.
    final today = day(2026, 10, 15);
    final october = span(day(2026, 10, 1), day(2026, 10, 31));
    final gym = ev(
      'gym',
      'gym',
      day(2026, 9, 1),
      rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
      tracked: true,
    );
    final absent = ev(
      'absent',
      'gym',
      day(2026, 9, 1),
      rule: const WeeklyRecurrence(weekdays: {DateTime.tuesday}),
      tracked: true,
      assumeAbsent: true,
    );
    final walk = ev(
      'walk',
      'cardio',
      day(2026, 9, 1),
      rule: const WeeklyRecurrence(weekdays: {DateTime.wednesday}),
      perDay: true,
    );
    final party = ev('party', 'friends', day(2026, 10, 20));
    final lost = ev('lost', 'gone', day(2026, 10, 9));
    final nap = ev('nap', 'rest', day(2026, 10, 10));
    final events = [gym, absent, walk, party, lost, nap];
    const scope = {'gym', 'cardio', 'friends', 'other'};

    setUp(() {
      EventPresence.updateCache(
        byEvent: {
          'gym': {
            day(2026, 10, 5): PresenceStatus.missed,
            day(2026, 10, 19): PresenceStatus.missed,
          },
          'absent': {day(2026, 10, 13): PresenceStatus.present},
          'walk': {day(2026, 10, 7): PresenceStatus.missed},
        },
      );
      EventSkips.updateCache(
        byEvent: {
          'gym': {day(2026, 9, 28), day(2026, 10, 12), day(2026, 10, 26)},
        },
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'walk': {
            day(2026, 10, 7): '- [x] stretch',
            day(2026, 10, 14): '',
            day(2026, 11, 4): '- [ ] later',
          },
        },
      );
    });

    ReportInput sample({
      Set<String> categoryIds = scope,
      DateRange? over,
      List<CalendarEvent>? from,
    }) => CalendarReportService.sampleInput(
      request(
        span: over ?? october,
        categoryIds: categoryIds,
        events: from ?? events,
        today: today,
      ),
    );

    List<ReportSample> of(ReportInput input, String eventId) => [
      for (final s in input.samples)
        if (s.eventId == eventId) s,
    ];

    test('every occurrence appears once, a skipped day never', () {
      final input = sample();
      expect(input.samples.toSet(), hasLength(input.samples.length));
      expect(of(input, 'gym').map((s) => s.day), [
        day(2026, 10, 5),
        day(2026, 10, 19),
      ]);
      expect(of(input, 'walk').map((s) => s.day), [
        day(2026, 10, 7),
        day(2026, 10, 14),
        day(2026, 10, 21),
        day(2026, 10, 28),
      ]);
      expect(of(input, 'party').map((s) => s.day), [day(2026, 10, 20)]);
      expect(input.span, october);
    });

    test('missed only on a tracked day up to today', () {
      final input = sample();
      expect(
        {for (final s in of(input, 'gym')) s.day: s.missed},
        // The explicit mark on the 19th is ahead of today.
        {day(2026, 10, 5): true, day(2026, 10, 19): false},
      );
      expect(
        {for (final s in of(input, 'absent')) s.day: s.missed},
        // Assumed absent to today, an explicit present wins, a future
        // assume-absent day is not missed yet.
        {
          day(2026, 10, 6): true,
          day(2026, 10, 13): false,
          day(2026, 10, 20): false,
          day(2026, 10, 27): false,
        },
      );
      expect(of(input, 'walk').any((s) => s.missed), isFalse);
    });

    test('a skipped day is counted only in the counted part', () {
      expect(sample().skippedDays, 1);
      expect(
        sample(over: span(day(2026, 9, 1), day(2026, 9, 30))).skippedDays,
        1,
      );
      expect(
        sample(over: span(day(2026, 11, 1), day(2026, 11, 30))).skippedDays,
        0,
      );
    });

    test('a skip the rule no longer produces skipped nothing', () {
      // The routine moved from Mondays to Tuesdays; its cancelled Monday
      // stayed behind.
      final moved = ev(
        'moved',
        'gym',
        day(2026, 9, 1),
        rule: const WeeklyRecurrence(weekdays: {DateTime.tuesday}),
        tracked: true,
      );
      EventSkips.updateCache(
        byEvent: {
          'moved': {day(2026, 10, 12)},
        },
      );
      expect(sample(from: [moved]).skippedDays, 0);
    });

    test('every per-day text reaches the input, outside the span too', () {
      // The Tasks tile is decided by the selection (D15), so the builder's
      // gate must see a text the span does not show; a blanked day stays
      // blank.
      expect(sample().overrides, {
        'walk': {
          day(2026, 10, 7): '- [x] stretch',
          day(2026, 10, 14): '',
          day(2026, 11, 4): '- [ ] later',
        },
      });
    });

    test('the catalogue orders, the resolved id groups', () {
      final input = sample();
      expect(input.categoryOf, {
        'gym': 'gym',
        'absent': 'gym',
        'walk': 'cardio',
        'party': 'friends',
      });
      expect(input.categoryOrder, [
        for (final c in CalendarCategories.all) c.id,
      ]);
    });

    test('an event outside the category set is not sampled', () {
      final input = sample();
      expect(input.events.containsKey('nap'), isFalse);
      expect(of(input, 'nap'), isEmpty);
    });

    test('an empty category set reports every category', () {
      final input = sample(categoryIds: const {});
      expect(input.events.keys.toSet(), {
        'gym',
        'absent',
        'walk',
        'party',
        'lost',
        'nap',
      });
      expect(of(input, 'nap').map((s) => s.day), [day(2026, 10, 10)]);
    });

    test('the allowlist matches the stored id, as the overview does', () {
      // D32: under {other} the overview does not list an event whose
      // category is gone, so neither does the report; with every category
      // it is in, and it groups under other, where its row is drawn.
      expect(sample(categoryIds: const {'other'}).events, isEmpty);
      final all = sample(categoryIds: const {});
      expect(of(all, 'lost').map((s) => s.day), [day(2026, 10, 9)]);
      expect(all.categoryOf['lost'], 'other');
    });
  });

  group('today (D31)', () {
    final today = day(2026, 10, 15);
    final unmarked = ev(
      'unmarked',
      'gym',
      day(2026, 10, 13),
      rule: const DailyRecurrence(),
      tracked: true,
      assumeAbsent: true,
    );
    final marked = ev(
      'marked',
      'gym',
      day(2026, 10, 15),
      rule: const DailyRecurrence(),
      tracked: true,
    );
    final untracked = ev(
      'untracked',
      'gym',
      day(2026, 10, 15),
      rule: const DailyRecurrence(),
    );

    Map<DateTime, (bool, bool)> flags(ReportInput input, String eventId) => {
      for (final s in input.samples)
        if (s.eventId == eventId) s.day: (s.missed, s.pending),
    };

    test('an unmarked routine day today is pending, never missed', () {
      EventPresence.updateCache(
        byEvent: {
          'marked': {day(2026, 10, 15): PresenceStatus.present},
        },
      );
      final input = CalendarReportService.sampleInput(
        request(
          span: span(day(2026, 10, 13), day(2026, 10, 16)),
          events: [unmarked, marked, untracked],
          today: today,
        ),
      );
      expect(flags(input, 'unmarked'), {
        day(2026, 10, 13): (true, false),
        day(2026, 10, 14): (true, false),
        day(2026, 10, 15): (false, true),
        day(2026, 10, 16): (false, false),
      });
      expect(flags(input, 'marked'), {
        day(2026, 10, 15): (false, false),
        day(2026, 10, 16): (false, false),
      });
      expect(flags(input, 'untracked'), {
        day(2026, 10, 15): (false, false),
        day(2026, 10, 16): (false, false),
      });
    });

    test('a missed mark on today settles it', () {
      EventPresence.updateCache(
        byEvent: {
          'marked': {day(2026, 10, 15): PresenceStatus.missed},
        },
      );
      final input = CalendarReportService.sampleInput(
        request(
          span: span(day(2026, 10, 15), day(2026, 10, 15)),
          events: [marked],
          today: today,
        ),
      );
      expect(flags(input, 'marked'), {day(2026, 10, 15): (true, false)});
    });

    test('a one-time tracked event today is neither pending nor missed', () {
      final once = CalendarEvent(
        id: 'once',
        title: 'once',
        categoryId: 'gym',
        startDate: today,
        tracksPresence: true,
        assumeAbsent: true,
      );
      final input = CalendarReportService.sampleInput(
        request(span: span(today, today), events: [once], today: today),
      );
      expect(flags(input, 'once'), {today: (false, false)});
    });
  });

  group('the clamp', () {
    final daily = ev('d', 'gym', day(2024, 1, 1), rule: const DailyRecurrence());

    test('a 400-day span keeps its last 366 days, today and ahead', () {
      final report = CalendarReportService().report(
        request(
          span: span(day(2025, 11, 27), day(2026, 12, 31)),
          events: [daily],
          today: day(2026, 10, 30),
        ),
      );
      expect(report.span, span(day(2025, 12, 31), day(2026, 12, 31)));
      expect(report.span.end.difference(report.span.start).inDays + 1, 366);
      expect(report.tense, ReportTense.current);
      expect(report.aheadCount, 62);
    });

    test('an inverted local-time span reports nothing', () {
      final report = CalendarReportService().report(
        request(
          span: (start: DateTime(2026, 10, 10, 15), end: DateTime(2026, 10, 5)),
          previousSpan: (
            start: DateTime(2026, 9, 10, 9),
            end: DateTime(2026, 9, 5),
          ),
          events: [daily],
          today: day(2026, 10, 30),
        ),
      );
      expect(report.span, span(day(2026, 10, 10), day(2026, 10, 5)));
      expect(report.isEmpty, isTrue);
    });
  });

  group('the memo', () {
    final today = day(2026, 10, 30);
    final events = [
      ev(
        'd',
        'gym',
        day(2026, 1, 1),
        rule: const DailyRecurrence(),
        tracked: true,
      ),
    ];
    final august = span(day(2026, 8, 1), day(2026, 8, 31));
    final july = span(day(2026, 7, 1), day(2026, 7, 31));
    final june = span(day(2026, 6, 1), day(2026, 6, 30));

    ReportRequest augustAsked({
      DateTime? on,
      CalendarWeekStart weekStart = CalendarWeekStart.monday,
      List<CalendarEvent>? from,
      int occurrenceRevision = 0,
      int membershipRevision = 0,
      int presenceRevision = 0,
    }) => request(
      span: august,
      previousSpan: july,
      events: from ?? events,
      today: on ?? today,
      weekStart: weekStart,
      occurrenceRevision: occurrenceRevision,
      membershipRevision: membershipRevision,
      presenceRevision: presenceRevision,
    );

    test('the same request folds once', () {
      final service = CalendarReportService();
      final first = service.report(augustAsked());
      final second = service.report(augustAsked());
      expect(service.foldCount, 1);
      expect(identical(first, second), isTrue);
    });

    test('a presence mark folds exactly once more', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      service.report(augustAsked(presenceRevision: 1));
      service.report(augustAsked(presenceRevision: 1));
      expect(service.foldCount, 2);
    });

    test('each revision bump misses', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      service.report(augustAsked(occurrenceRevision: 1));
      service.report(augustAsked(membershipRevision: 1));
      service.report(augustAsked(presenceRevision: 1));
      expect(service.foldCount, 4);
    });

    test('a step back and forth re-folds nothing it already knew', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      service.report(
        request(span: july, previousSpan: june, events: events, today: today),
      );
      expect(service.foldCount, 2);
      service.report(augustAsked());
      expect(service.foldCount, 2);
    });

    test('clear empties the memo', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      service.clear();
      service.report(augustAsked());
      expect(service.foldCount, 2);
    });

    test('another day misses', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      service.report(augustAsked(on: day(2026, 10, 31)));
      expect(service.foldCount, 2);
    });

    test('another week start misses', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      service.report(augustAsked(weekStart: CalendarWeekStart.sunday));
      expect(service.foldCount, 2);
    });

    test('a fresh events list misses, as an event edit bumps no counter', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      service.report(augustAsked(from: [...events]));
      expect(service.foldCount, 2);
    });

    test('a catalogue change misses, as it re-resolves the groups', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      seedCategories();
      service.report(augustAsked());
      expect(service.foldCount, 2);
    });

    test('a holiday change misses, as it moves the workday rules', () {
      final service = CalendarReportService();
      service.report(augustAsked());
      PublicHolidays.resetCache();
      service.report(augustAsked());
      expect(service.foldCount, 2);
    });
  });

  group('previous totals (D28)', () {
    final daily = ev(
      'd',
      'gym',
      day(2026, 1, 1),
      rule: const DailyRecurrence(),
    );

    test('no previous span leaves every delta out', () {
      final report = CalendarReportService().report(
        request(
          span: span(day(2026, 9, 1), day(2026, 9, 30)),
          events: [daily],
          today: day(2026, 10, 30),
        ),
      );
      expect(report.tiles, isNotEmpty);
      expect(report.tiles.every((t) => t.previous == null), isTrue);
    });

    test('a past span compares with the whole previous span', () {
      final report = CalendarReportService().report(
        request(
          span: span(day(2026, 9, 1), day(2026, 9, 30)),
          previousSpan: span(day(2026, 8, 1), day(2026, 8, 31)),
          events: [daily],
          today: day(2026, 10, 30),
        ),
      );
      final events = tile(report, ReportTile.events);
      expect(events.value, 30);
      expect(events.previous, 31);
    });

    test('a current span compares with the same elapsed length', () {
      final report = CalendarReportService().report(
        request(
          span: span(day(2026, 10, 1), day(2026, 10, 31)),
          previousSpan: span(day(2026, 9, 1), day(2026, 9, 30)),
          events: [daily],
          today: day(2026, 10, 10),
        ),
      );
      final events = tile(report, ReportTile.events);
      expect(events.value, 10);
      expect(events.previous, 10);
    });

    test('on the first day the previous span counts its first day alone', () {
      final report = CalendarReportService().report(
        request(
          span: span(day(2026, 10, 1), day(2026, 10, 31)),
          previousSpan: span(day(2026, 9, 1), day(2026, 9, 30)),
          events: [daily],
          today: day(2026, 10, 1),
        ),
      );
      final events = tile(report, ReportTile.events);
      expect(events.value, 1);
      expect(events.previous, 1);
    });

    test('the elapsed length never runs past the previous span', () {
      final report = CalendarReportService().report(
        request(
          span: span(day(2026, 10, 1), day(2026, 10, 31)),
          previousSpan: span(day(2026, 9, 1), day(2026, 9, 30)),
          events: [daily],
          today: day(2026, 10, 31),
        ),
      );
      final events = tile(report, ReportTile.events);
      expect(events.value, 31);
      expect(events.previous, 30);
    });

    test('a plan counts today\'s pending occurrence in its previous span', () {
      final routine = ev(
        'r',
        'gym',
        day(2026, 1, 1),
        rule: const DailyRecurrence(),
        tracked: true,
      );
      final october = span(day(2026, 10, 1), day(2026, 10, 31));
      final service = CalendarReportService();
      final graded = service.report(
        request(span: october, events: [routine], today: day(2026, 10, 31)),
      );
      // Today's unmarked day is still ahead in the graded October.
      expect(tile(graded, ReportTile.events).value, 30);
      final plan = service.report(
        request(
          span: span(day(2026, 11, 1), day(2026, 11, 30)),
          previousSpan: october,
          events: [routine],
          today: day(2026, 10, 31),
        ),
      );
      expect(tile(plan, ReportTile.planned).previous, 31);
    });

    test('a plan compares with every previous occurrence, missed too', () {
      final routine = ev(
        'r',
        'gym',
        day(2026, 1, 1),
        rule: const DailyRecurrence(),
        tracked: true,
        time: const EventTime(startMinute: 9 * 60, durationMinutes: 60),
      );
      EventPresence.updateCache(
        byEvent: {
          'r': {day(2026, 10, 2): PresenceStatus.missed},
        },
      );
      final report = CalendarReportService().report(
        request(
          span: span(day(2026, 11, 1), day(2026, 11, 30)),
          previousSpan: span(day(2026, 10, 1), day(2026, 10, 31)),
          events: [routine],
          today: day(2026, 10, 10),
        ),
      );
      expect(report.tense, ReportTense.future);
      final planned = tile(report, ReportTile.planned);
      expect(planned.value, 30);
      expect(planned.previous, 31);
      final hours = tile(report, ReportTile.hours);
      expect(hours.value, 30 * 60);
      expect(hours.previous, 31 * 60);
    });
  });
}
