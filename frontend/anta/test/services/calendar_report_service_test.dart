import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/analytics_metrics.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/category_profiles.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/overview_view.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/services/note_money_ledger_service.dart';
import 'package:anta/utils/calendar_report_builder.dart';
import 'package:anta/utils/event_agenda.dart';

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
    ReportCompare compare = ReportCompare.previous,
    OverviewView? compareView,
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
      compare: compare,
      compareView: compareView,
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

    test('a one-time tracked event today unmarked is pending', () {
      // Decision B: a tracked one-off is still to come on its day, like a
      // routine's — no longer a plain sample.
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
      expect(flags(input, 'once'), {today: (false, true)});
    });
  });

  group('one-offs (decision B)', () {
    final today = day(2026, 10, 15);
    final twoDaysAgo = day(2026, 10, 13);
    final october = span(day(2026, 10, 1), day(2026, 10, 31));

    CalendarEvent dentist(DateTime on) =>
        ev('dentist', 'other', on, tracked: true, assumeAbsent: true);

    List<ReportSample> samplesOf(ReportInput input) =>
        input.samples.where((s) => s.eventId == 'dentist').toList();

    ReportInput sample(CalendarEvent event) =>
        CalendarReportService.sampleInput(
          request(span: october, events: [event], today: today),
        );

    test('two days ago under assume-absent folds as missed', () {
      final only = samplesOf(sample(dentist(twoDaysAgo))).single;
      expect((only.day, only.missed, only.pending), (twoDaysAgo, true, false));
    });

    test('marked present folds as kept', () {
      EventPresence.updateCache(
        byEvent: {
          'dentist': {twoDaysAgo: PresenceStatus.present},
        },
      );
      final only = samplesOf(sample(dentist(twoDaysAgo))).single;
      expect((only.missed, only.pending), (false, false));
    });

    test('today unmarked is pending', () {
      final only = samplesOf(sample(dentist(today))).single;
      expect((only.missed, only.pending), (false, true));
    });

    test('a day still ahead is a plain sample, never missed', () {
      final ahead = day(2026, 10, 20);
      final only = samplesOf(sample(dentist(ahead))).single;
      expect((only.day, only.missed, only.pending), (ahead, false, false));
    });

    test('cancelled is dropped and counted as one skipped day', () {
      EventSkips.updateCache(
        byEvent: {
          'dentist': {twoDaysAgo},
        },
      );
      final input = sample(dentist(twoDaysAgo));
      expect(samplesOf(input), isEmpty);
      expect(input.skippedDays, 1);
    });

    test('a tracked one-off stays a one-off shape', () {
      // Not the presence gate: a one-off row is dated, never aggregated.
      expect(shapeOf(dentist(twoDaysAgo)), ReportShape.oneOff);
      // D31 still holds: a tracked set of explicit dates is a routine.
      final dates = ev(
        'dates',
        'other',
        twoDaysAgo,
        rule: SpecificDatesRecurrence(dates: {twoDaysAgo, today}),
        tracked: true,
      );
      expect(shapeOf(dates), ReportShape.routine);
    });
  });

  group('the readers (the guide\'s seam)', () {
    // October 2026: Mondays 5, 12, 19, 26.
    final today = day(2026, 10, 19);
    final october = span(day(2026, 10, 1), day(2026, 10, 31));
    final yoga = ev(
      'guide-demo-yoga',
      'gym',
      day(2026, 9, 1),
      rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
      tracked: true,
    );

    test('with none, the facades are read', () {
      EventPresence.updateCache(
        byEvent: {
          yoga.id: {day(2026, 10, 5): PresenceStatus.missed},
        },
      );
      EventSkips.updateCache(
        byEvent: {
          yoga.id: {day(2026, 10, 12)},
        },
      );
      final input = CalendarReportService.sampleInput(
        request(span: october, events: [yoga], today: today),
      );
      expect(
        [
          for (final s in input.samples)
            if (s.missed) s.day,
        ],
        [day(2026, 10, 5)],
      );
      expect(input.skippedDays, 1);
    });

    test('a demo\'s missed day reaches the report through its readers '
        'alone', () {
      // Nothing in the facades: a demo keeps its marks in memory.
      final marks = {
        day(2026, 10, 12): PresenceStatus.missed,
        today: PresenceStatus.present,
      };
      final report = CalendarReportBuilder.fold(
        CalendarReportService.sampleInput(
          ReportRequest(
            span: october,
            events: [yoga],
            today: today,
            weekStart: CalendarWeekStart.monday,
            isMissed: (event, dayUtc) => marks[dayUtc] == PresenceStatus.missed,
            marksFor: (id) => id == yoga.id ? marks : const {},
          ),
        ),
      );
      final missed = [
        for (final group in report.missed)
          for (final row in group.rows)
            if (row case ReportDatedRow(missed: true, :final day)) day,
      ];
      expect(missed, [day(2026, 10, 12)]);
      // The 5th kept, and today kept: marked present through the reader,
      // so not pending.
      expect(tile(report, ReportTile.events).value, 2);
      expect(EventPresence.marksFor(yoga.id), isEmpty);
    });

    test('a demo\'s skipped day is neither sampled nor shown, and counted '
        'skipped once', () {
      final request = ReportRequest(
        span: october,
        events: [yoga],
        today: today,
        weekStart: CalendarWeekStart.monday,
        // Every past day missed: a sampled 5th would be a Missed row.
        isMissed: (_, _) => true,
        skipsFor: (id) => id == yoga.id ? {day(2026, 10, 5)} : const {},
      );
      final input = CalendarReportService.sampleInput(request);
      expect(input.samples.map((s) => s.day), [
        day(2026, 10, 12),
        day(2026, 10, 19),
        day(2026, 10, 26),
      ]);
      expect(input.skippedDays, 1);
      final report = CalendarReportBuilder.fold(input);
      expect(
        [
          for (final group in report.missed)
            for (final row in group.rows)
              if (row case ReportDatedRow(:final day)) day,
        ],
        // Today unmarked is pending, never missed (D31).
        [day(2026, 10, 12)],
      );
      expect(EventSkips.daysFor(yoga.id), isEmpty);
    });

    test('a demo\'s per-day texts reach the input through its reader', () {
      final walk = ev(
        'guide-demo-walk',
        'cardio',
        day(2026, 9, 1),
        rule: const WeeklyRecurrence(weekdays: {DateTime.wednesday}),
        perDay: true,
      );
      final input = CalendarReportService.sampleInput(
        ReportRequest(
          span: october,
          events: [walk],
          today: today,
          weekStart: CalendarWeekStart.monday,
          descriptionsFor: (id) =>
              id == walk.id ? {day(2026, 10, 7): '- [x] stretch'} : const {},
        ),
      );
      expect(input.overrides, {
        walk.id: {day(2026, 10, 7): '- [x] stretch'},
      });
      expect(OccurrenceDescriptions.overridesFor(walk.id), isEmpty);
    });

    test('the memo refuses a request with readers', () {
      expect(
        () => CalendarReportService().report(
          ReportRequest(
            span: october,
            events: [yoga],
            today: today,
            weekStart: CalendarWeekStart.monday,
            isMissed: (_, _) => false,
          ),
        ),
        throwsAssertionError,
      );
    });
  });

  group('the clamp', () {
    final daily = ev(
      'd',
      'gym',
      day(2024, 1, 1),
      rule: const DailyRecurrence(),
    );

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

  // The analytics facts (S2a-i): what the service resolves so the builder
  // reads no facade — profiles, cancelled days, money, the lookback, the
  // working days — and what each costs in scans.
  group('the analytics facts', () {
    final today = day(2026, 10, 30);
    final august = span(day(2026, 8, 1), day(2026, 8, 31));
    final july = span(day(2026, 7, 1), day(2026, 7, 31));
    final june = span(day(2026, 6, 1), day(2026, 6, 30));
    final daily = ev(
      'd',
      'gym',
      day(2026, 1, 1),
      rule: const DailyRecurrence(),
      tracked: true,
    );
    final service = ev('service', 'other', day(2026, 5, 10));

    CategoryProfile profile(String categoryId, CategoryKind kind) =>
        CategoryProfile(
          id: 'p-$categoryId',
          categoryId: categoryId,
          kind: kind,
        );

    ReportRequest augustAsked(
      List<CalendarEvent> events, {
      int occurrenceRevision = 0,
    }) => request(
      span: august,
      previousSpan: july,
      events: events,
      today: today,
      occurrenceRevision: occurrenceRevision,
    );

    tearDown(() {
      CategoryProfiles.resetCache();
      NoteMoneyLedgerService.reset();
    });

    test('every scoped category resolves its profile, unprofiled too', () {
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.workout),
      });
      final input = CalendarReportService.sampleInput(
        augustAsked([daily, service, ev('lost', 'gone', day(2026, 8, 9))]),
      );
      expect(input.profiles.keys, unorderedEquals(['gym', 'other']));
      expect(input.profiles['gym']!.kind, CategoryKind.workout);
      expect(input.profiles['other'], EffectiveProfile.unprofiled);
    });

    test('the skipped days counted arrive as cancelled samples', () {
      EventSkips.updateCache(
        byEvent: {
          'd': {day(2026, 8, 5), day(2026, 8, 20)},
        },
      );
      final input = CalendarReportService.sampleInput(augustAsked([daily]));
      expect(input.skippedDays, 2);
      expect(
        [for (final s in input.cancelled) (s.eventId, s.day)],
        [('d', day(2026, 8, 5)), ('d', day(2026, 8, 20))],
      );
      expect(input.samples.where((s) => s.day == day(2026, 8, 5)), isEmpty);
    });

    test('money reads the cached ledgers of the linked notes', () {
      final events = [
        ev('shop', 'other', day(2026, 8, 3)).copyWith(noteId: 'n1'),
        ev('lunch', 'other', day(2026, 8, 4)).copyWith(noteId: 'n2'),
        ev('walk', 'other', day(2026, 8, 5)),
      ];
      expect(
        CalendarReportService.sampleInput(augustAsked(events)).money,
        isEmpty,
        reason: 'no ledger service, no money',
      );
      NoteMoneyLedgerService.seedForTesting({
        'n1': (balance: 0, net: -1500, title: 'Shop'),
      });
      expect(CalendarReportService.sampleInput(augustAsked(events)).money, {
        'shop': -1500,
      });
      final measures = CalendarReportService().report(augustAsked(events));
      expect(measures.measures['other']!.spentCents, 1500);
    });

    ({int working, int holidays}) workingDaysOf(DateRange over) {
      final input = CalendarReportService.sampleInput(
        request(span: over, events: [daily], today: today),
      );
      return (working: input.workingDays, holidays: input.publicHolidays);
    }

    test('working days leave out weekends and public holidays (T)', () {
      PublicHolidays.resetCache();
      CategoryProfiles.updateCache({'gym': profile('gym', CategoryKind.work)});
      // 1 May 2026 is a Friday; 15 August a Saturday.
      expect(workingDaysOf(span(day(2026, 5, 1), day(2026, 5, 31))), (
        working: 20,
        holidays: 1,
      ));
      expect(workingDaysOf(august), (working: 21, holidays: 1));
      final report = CalendarReportService().report(augustAsked([daily]));
      expect((report.workingDays, report.publicHolidays), (21, 1));
    });

    test('working days: a leap February, a plan year, a clamped custom '
        'span', () {
      PublicHolidays.resetCache();
      CategoryProfiles.updateCache({'gym': profile('gym', CategoryKind.work)});
      // 1 February 2028 is a Tuesday: four weeks and the 29th, a Tuesday.
      expect(workingDaysOf(span(day(2028, 2, 1), day(2028, 2, 29))), (
        working: 21,
        holidays: 0,
      ));
      ({int working, int holidays}) walked(int year) {
        var working = 0;
        var holidays = 0;
        for (
          var d = day(year, 1, 1);
          d.year == year;
          d = day(d.year, d.month, d.day + 1)
        ) {
          final holiday = PublicHolidays.isHoliday(d);
          if (holiday) holidays++;
          if (!holiday && d.weekday <= DateTime.friday) working++;
        }
        return (working: working, holidays: holidays);
      }

      final plan = workingDaysOf(span(day(2027, 1, 1), day(2027, 12, 31)));
      expect(plan, walked(2027), reason: 'a plan year reads its own');
      expect(plan.holidays, greaterThan(0));
      expect(
        workingDaysOf(span(day(2027, 1, 1), day(2028, 12, 31))),
        walked(2028),
        reason: 'D33 keeps 2028\'s 366 days, a whole year',
      );
    });

    test('working days are resolved only for a whole month or year whose scope '
        'holds a Work, Meeting or Leave kind (analytics P)', () {
      PublicHolidays.resetCache();
      // Unprofiled, nothing: every month report reads as before S4.
      expect(workingDaysOf(august), (working: 0, holidays: 0));
      // A Workout is no working-days story either.
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.workout),
      });
      expect(workingDaysOf(august), (working: 0, holidays: 0));
      // Meeting and Leave count like Work; a week and a span that is not a
      // calendar month do not, whatever the kind.
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.meeting),
      });
      expect(workingDaysOf(august), (working: 21, holidays: 1));
      expect(workingDaysOf(span(day(2026, 8, 3), day(2026, 8, 9))), (
        working: 0,
        holidays: 0,
      ));
      expect(workingDaysOf(span(day(2026, 8, 2), day(2026, 8, 31))), (
        working: 0,
        holidays: 0,
      ));
      CategoryProfiles.updateCache({'gym': profile('gym', CategoryKind.leave)});
      // The whole year, and a plan's month (December seen from October).
      expect(
        workingDaysOf(span(day(2026, 1, 1), day(2026, 12, 31))).working,
        greaterThan(200),
      );
      expect(
        workingDaysOf(span(day(2026, 12, 1), day(2026, 12, 31))).working,
        greaterThan(0),
      );
    });

    test('the lookback finds the last kept day before the span', () {
      final missed = ev('oil', 'other', day(2026, 6, 10), tracked: true);
      final cancelled = ev('tyres', 'other', day(2026, 7, 1));
      EventPresence.updateCache(
        byEvent: {
          'oil': {day(2026, 6, 10): PresenceStatus.missed},
        },
      );
      EventSkips.updateCache(
        byEvent: {
          'tyres': {day(2026, 7, 1)},
        },
      );
      final events = [daily, service, missed, cancelled];
      expect(
        CalendarReportService.sampleInput(augustAsked(events)).lastSeenBefore,
        isEmpty,
        reason: 'no category reads a gap',
      );
      CategoryProfiles.updateCache({
        'other': profile('other', CategoryKind.maintenance),
      });
      expect(
        CalendarReportService.sampleInput(augustAsked(events)).lastSeenBefore,
        {'other': day(2026, 5, 10)},
      );
      final other = CalendarReportService()
          .report(augustAsked(events))
          .measures['other']!;
      expect((other.lastSeenDay, other.lastSeenDays), (day(2026, 5, 10), 173));
      expect(other.primary, ReportMeasure.lastSeen);
    });

    test('a fold scans its span and its previous span, a memo hit none', () {
      final events = [daily];
      final reports = CalendarReportService();
      reports.report(augustAsked(events));
      expect(reports.scanCount, 2);
      reports.report(augustAsked(events));
      expect(reports.scanCount, 2);
      reports.report(request(span: june, events: events, today: today));
      expect(reports.scanCount, 3, reason: 'no previous span, one scan');
    });

    test('a category that reads a gap adds one lookback, and after a past '
        'span one lookahead, cached', () {
      CategoryProfiles.updateCache({
        'other': profile('other', CategoryKind.maintenance),
      });
      final events = [daily, service];
      final reports = CalendarReportService();
      reports.report(augustAsked(events));
      expect(reports.scanCount, 4, reason: 'August is past: 2 + 2');
      reports.report(augustAsked(events));
      // A profiled calendar folds the previous period too (§6.11): two
      // folds a report, over the scans the totals fold took.
      expect((reports.foldCount, reports.scanCount), (2, 4));
      // A description edit refolds the span; the windows are unchanged.
      reports.report(augustAsked(events, occurrenceRevision: 1));
      expect((reports.foldCount, reports.scanCount), (4, 6));
      reports.report(
        request(span: july, previousSpan: june, events: events, today: today),
      );
      expect((reports.foldCount, reports.scanCount), (6, 10));
      reports.report(augustAsked(events, occurrenceRevision: 1));
      expect((reports.foldCount, reports.scanCount), (6, 10), reason: '◄ ►');
    });

    test('a profile change refolds once', () {
      final events = [daily];
      final reports = CalendarReportService();
      reports.report(augustAsked(events));
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.workout),
      });
      reports.report(augustAsked(events));
      reports.report(augustAsked(events));
      expect(
        reports.foldCount,
        3,
        reason: 'one unprofiled fold, then a report and its compared fold',
      );
    });

    test('a ledger change refolds once', () {
      final events = [daily];
      final reports = CalendarReportService();
      reports.report(augustAsked(events));
      NoteMoneyLedgerService.seedForTesting(const {});
      reports.report(augustAsked(events));
      reports.report(augustAsked(events));
      expect(reports.foldCount, 2);
    });

    test('the guide\'s path folds what the memo folds', () {
      final asked = augustAsked([daily, service]);
      final folded = CalendarReportBuilder.fold(
        CalendarReportService.sampleInput(asked),
      );
      expect(folded, CalendarReportService().report(asked));
      expect(folded.measures.keys, unorderedEquals(['gym', 'other']));
    });

    // The goals' lookback (S2a-ii): the same one scan per category, now also
    // for a target, handing over its samples.
    const weekly3 = ReportTarget(
      kind: TargetKind.atLeast,
      value: 3,
      period: TargetPeriod.week,
    );

    test('the lookback reads the scan\'s cap', () {
      expect(AnalyticsMetrics.lookbackDays, EventAgenda.maxRangeDays);
    });

    test('a target\'s lookback hands over its kept and missed samples', () {
      EventPresence.updateCache(
        byEvent: {
          'd': {day(2026, 7, 15): PresenceStatus.missed},
        },
      );
      EventSkips.updateCache(
        byEvent: {
          'd': {day(2026, 7, 20)},
        },
      );
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.workout).copyWith(target: weekly3),
      });
      final asked = augustAsked([daily, service]);
      final input = CalendarReportService.sampleInput(asked);
      expect(input.lookback.keys, ['gym']);
      final gym = input.lookback['gym']!;
      expect(
        (gym.first.day, gym.last.day),
        (day(2026, 1, 1), day(2026, 7, 31)),
      );
      expect(gym.length, 211, reason: '1 January to 31 July, the skip out');
      expect(
        [
          for (final s in gym)
            if (s.missed) s.day,
        ],
        [day(2026, 7, 15)],
      );
      expect(input.lastSeenBefore, isEmpty, reason: 'a target reads no gap');

      final goal = CalendarReportService().report(asked).goals.single;
      expect(goal.periods.first.start, day(2026, 7, 27));
      expect(goal.periods.first.value, 7, reason: 'five days of July');
      // Every week from that of 1 January to that of 31 August kept three —
      // the last valued past the span's end from the lookahead.
      expect(goal.streak, 36);
    });

    test('a gap that is also a target derives its last-seen from the one '
        'lookback', () {
      CategoryProfiles.updateCache({
        'other': profile('other', CategoryKind.maintenance).copyWith(
          target: const ReportTarget(kind: TargetKind.maxGap, value: 90),
        ),
      });
      final input = CalendarReportService.sampleInput(
        augustAsked([daily, service]),
      );
      expect(input.lastSeenBefore, {'other': day(2026, 5, 10)});
      expect(
        [for (final s in input.lookback['other']!) s.day],
        [day(2026, 5, 10)],
      );
      final goal = CalendarReportService()
          .report(augustAsked([daily, service]))
          .goals
          .single;
      expect((goal.gap!.daysSince, goal.gap!.state), (173, GapState.overdue));
    });

    test('one lookback per category with a target or a gap, cached', () {
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.workout).copyWith(target: weekly3),
        'other': profile('other', CategoryKind.maintenance).copyWith(
          target: const ReportTarget(kind: TargetKind.maxGap, value: 90),
        ),
      });
      final events = [daily, service];
      final reports = CalendarReportService();
      reports.report(augustAsked(events));
      expect(
        reports.scanCount,
        6,
        reason:
            'the span, the previous span, and per category one lookback '
            'and, August being past, one lookahead',
      );
      reports.report(augustAsked(events));
      // Two folds a report: profiled, the previous period is a compared
      // fold (§6.11).
      expect((reports.foldCount, reports.scanCount), (2, 6));
      reports.report(
        request(span: july, previousSpan: june, events: events, today: today),
      );
      expect((reports.foldCount, reports.scanCount), (4, 12));
      reports.report(augustAsked(events));
      expect((reports.foldCount, reports.scanCount), (4, 12), reason: '◄ ►');
      reports.report(augustAsked(events, occurrenceRevision: 1));
      expect(
        (reports.foldCount, reports.scanCount),
        (6, 14),
        reason: 'a description edit rescans the spans, never the windows',
      );
    });

    // The S2a fix pass: the days after a past span, what the windows key
    // on, the guide's profiles and an Expiry left unrenewed.
    final september = span(day(2026, 9, 1), day(2026, 9, 30));
    final october = span(day(2026, 10, 1), day(2026, 10, 31));

    test('a past span hands over the days after it to today; a current '
        'span none', () {
      EventSkips.updateCache(
        byEvent: {
          'd': {day(2026, 9, 10)},
        },
      );
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.workout).copyWith(target: weekly3),
        'other': profile('other', CategoryKind.maintenance),
      });
      final tyres = ev('tyres', 'other', day(2026, 10, 20));
      final events = [daily, service, tyres];
      final input = CalendarReportService.sampleInput(augustAsked(events));
      expect(input.lookahead.keys, unorderedEquals(['gym', 'other']));
      final gym = input.lookahead['gym']!;
      expect(
        (gym.first.day, gym.last.day, gym.length),
        (day(2026, 9, 1), day(2026, 10, 29), 58),
        reason: 'the skip and today\'s pending day out',
      );
      expect(
        [for (final s in input.lookahead['other']!) s.day],
        [day(2026, 10, 20)],
      );
      final other = CalendarReportService()
          .report(augustAsked(events))
          .measures['other']!;
      expect((other.lastSeenDay, other.lastSeenDays), (day(2026, 10, 20), 10));

      final current = request(
        span: october,
        previousSpan: september,
        events: events,
        today: today,
      );
      expect(CalendarReportService.sampleInput(current).lookahead, isEmpty);
      final reports = CalendarReportService();
      reports.report(current);
      expect(
        reports.scanCount,
        4,
        reason: 'a current span: the two spans and one lookback each',
      );
    });

    test('a presence or a membership bump rescans the lookback; a '
        'description edit never', () {
      CategoryProfiles.updateCache({
        'other': profile('other', CategoryKind.maintenance),
      });
      final events = [daily, service];
      ReportRequest asked({
        int occurrence = 0,
        int presence = 0,
        int membership = 0,
      }) => request(
        span: october,
        previousSpan: september,
        events: events,
        today: today,
        occurrenceRevision: occurrence,
        presenceRevision: presence,
        membershipRevision: membership,
      );
      final reports = CalendarReportService();
      reports.report(asked());
      expect(reports.scanCount, 3);
      reports.report(asked(occurrence: 1));
      expect(reports.scanCount, 5, reason: 'the two spans alone');
      reports.report(asked(occurrence: 1, presence: 1));
      expect(reports.scanCount, 8, reason: 'a mark moves what was kept');
      reports.report(asked(occurrence: 1, presence: 1, membership: 1));
      expect(reports.scanCount, 11, reason: 'a skip moves what occurred');
    });

    // M1's window (S2b-i fix pass): the Bill categories' next month, scanned
    // once beside the span in any tense.
    test('a Bill category adds one bills-ahead scan over the next month, '
        'cached', () {
      final rent = ev(
        'rent',
        'other',
        day(2025, 1, 3),
        rule: const MonthlyRecurrence(),
      ).copyWith(noteId: 'n1');
      final events = [daily, rent];
      expect(
        CalendarReportService.sampleInput(augustAsked(events)).billsAhead,
        isEmpty,
        reason: 'no Bill category, no scan',
      );
      CategoryProfiles.updateCache({
        'other': profile('other', CategoryKind.bill),
      });
      EventSkips.updateCache(
        byEvent: {
          'rent': {day(2026, 11, 3)},
        },
      );
      final input = CalendarReportService.sampleInput(augustAsked(events));
      expect(
        [for (final s in input.billsAhead) (s.eventId, s.day)],
        isEmpty,
        reason: '30 October to 29 November: the one Rent day is skipped',
      );
      EventSkips.resetCache();
      expect(
        [
          for (final s in CalendarReportService.sampleInput(
            augustAsked(events),
          ).billsAhead)
            (s.eventId, s.day),
        ],
        [('rent', day(2026, 11, 3))],
        reason: 'the Bill alone, a year after its start, past the span',
      );

      NoteMoneyLedgerService.seedForTesting({
        'n1': (balance: 0, net: -1200, title: 'Rent'),
      });
      final reports = CalendarReportService();
      final august = reports.report(augustAsked(events));
      final m1 = august.insights.singleWhere((i) => i.rule == InsightRule.m1);
      expect((m1.cents, m1.n1, m1.day), (1200, 1, today));
      expect(
        reports.scanCount,
        3,
        reason: 'the span, the previous span and the bills ahead',
      );
      reports.report(augustAsked(events, occurrenceRevision: 1));
      expect(
        (reports.foldCount, reports.scanCount),
        (4, 5),
        reason:
            'a description edit rescans the spans, never the window; two '
            'folds a report, the previous period compared (§6.11)',
      );
      reports.report(
        request(span: july, previousSpan: june, events: events, today: today),
      );
      expect(
        (reports.foldCount, reports.scanCount),
        (6, 7),
        reason: 'another span reads the same next month',
      );
    });

    test('the streak\'s first period is the first event\'s partial week', () {
      // Wednesday 14 October: its week holds five of the event's days.
      final gym = ev(
        'g',
        'gym',
        day(2026, 10, 14),
        rule: const DailyRecurrence(),
        tracked: true,
      );
      int streakFor(int perWeek) {
        CategoryProfiles.updateCache({
          'gym': profile('gym', CategoryKind.workout).copyWith(
            target: ReportTarget(
              kind: TargetKind.atLeast,
              value: perWeek,
              period: TargetPeriod.week,
            ),
          ),
        });
        return CalendarReportService()
            .report(
              request(
                span: span(day(2026, 10, 26), day(2026, 11, 1)),
                events: [gym],
                today: today,
              ),
            )
            .goals
            .single
            .streak;
      }

      expect(streakFor(5), 2, reason: '5 of 12–18 October, then 7');
      expect(streakFor(6), 1, reason: 'the partial week missed six');
    });

    test('an Expiry unmarked past its day is overdue (analytics AN)', () {
      expect(CategoryKinds.of(CategoryKind.expiry).assumeAbsentNew, isTrue);
      CategoryProfiles.updateCache({
        'other': profile('other', CategoryKind.expiry),
      });
      expect(CategoryProfiles.effectiveFor('other').assumeAbsentNew, isTrue);
      // As the editor pre-fills a new event from its kind.
      final passport = ev(
        'passport',
        'other',
        day(2026, 10, 20),
        tracked: true,
        assumeAbsent: true,
      );
      final report = CalendarReportService().report(
        request(span: october, events: [passport], today: today),
      );
      expect(
        [for (final r in report.dueSoon) (r.eventId, r.state, r.kind, r.days)],
        [('passport', ReportDueState.overdue, ReportDueKind.expiry, 10)],
      );
    });

    test('the guide\'s profile reader folds the demo unprofiled', () {
      CategoryProfiles.updateCache({
        'gym': profile('gym', CategoryKind.bill).copyWith(
          target: const ReportTarget(
            kind: TargetKind.budget,
            value: 10000,
            period: TargetPeriod.month,
          ),
        ),
      });
      final run = ev(
        'run',
        'gym',
        day(2026, 8, 3),
        time: const EventTime(startMinute: 7 * 60, durationMinutes: 45),
      );
      ReportRequest asked(EffectiveProfile Function(String)? profileOf) =>
          ReportRequest(
            span: august,
            events: [run],
            today: today,
            weekStart: CalendarWeekStart.monday,
            profileOf: profileOf,
          );
      final owners = CalendarReportBuilder.fold(
        CalendarReportService.sampleInput(asked(null)),
      );
      expect(owners.goals, hasLength(1));
      expect(
        owners.tiles.where((t) => t.tile == ReportTile.hours),
        isEmpty,
        reason: 'a Bill counts no hours',
      );
      final demo = CalendarReportBuilder.fold(
        CalendarReportService.sampleInput(
          asked((_) => EffectiveProfile.unprofiled),
        ),
      );
      expect(demo.goals, isEmpty);
      expect(tile(demo, ReportTile.hours).value, 45);
      expect(
        () => CalendarReportService().report(
          asked((_) => EffectiveProfile.unprofiled),
        ),
        throwsAssertionError,
      );
    });
  });

  // Compare's second fold (S2b-ii, §6.11): the compared span per mode, the
  // compared today, the view's fold, the two-fold memo, and the unprofiled
  // calendar folding exactly as it did.
  group('compare (§6.11)', () {
    final daily = ev(
      'd',
      'gym',
      day(2020, 1, 1),
      rule: const DailyRecurrence(),
      tracked: true,
    );
    final october = span(day(2026, 10, 1), day(2026, 10, 31));
    final september = span(day(2026, 9, 1), day(2026, 9, 30));
    final august = span(day(2026, 8, 1), day(2026, 8, 31));
    final july = span(day(2026, 7, 1), day(2026, 7, 31));
    final june = span(day(2026, 6, 1), day(2026, 6, 30));
    final may = span(day(2026, 5, 1), day(2026, 5, 31));
    final april = span(day(2026, 4, 1), day(2026, 4, 30));
    final today = day(2026, 11, 15);
    // One list for the memo's cases: the memo keys on the list's identity.
    final dailies = [daily];

    void profileGym() => CategoryProfiles.updateCache({
      'gym': const CategoryProfile(
        id: 'p-gym',
        categoryId: 'gym',
        kind: CategoryKind.workout,
      ),
    });

    tearDown(CategoryProfiles.resetCache);

    OverviewView viewOf(Set<String> categoryIds) => OverviewView(
      id: 'v',
      name: 'Life',
      period: const OverviewYearPeriod(2026),
      categoryIds: categoryIds,
    );

    CalendarReport lastYear(DateRange of, DateTime on) =>
        CalendarReportService().report(
          request(
            span: of,
            events: [daily],
            today: on,
            compare: ReportCompare.lastYear,
          ),
        );

    test('last year: a calendar year, a month, whole weeks, any other '
        'span', () {
      final cases = <(DateRange, DateTime, DateRange)>[
        (
          span(day(2026, 1, 1), day(2026, 12, 31)),
          day(2027, 1, 15),
          span(day(2025, 1, 1), day(2025, 12, 31)),
        ),
        (
          span(day(2028, 2, 1), day(2028, 2, 29)),
          day(2028, 3, 10),
          span(day(2027, 2, 1), day(2027, 2, 28)),
        ),
        (
          span(day(2026, 11, 2), day(2026, 11, 8)),
          today,
          span(day(2025, 11, 3), day(2025, 11, 9)),
        ),
        (
          span(day(2028, 2, 20), day(2028, 2, 29)),
          day(2028, 3, 10),
          span(day(2027, 2, 20), day(2027, 2, 28)),
        ),
        (
          span(day(2028, 2, 29), day(2028, 3, 9)),
          day(2028, 3, 10),
          span(day(2027, 2, 28), day(2027, 3, 9)),
        ),
      ];
      for (final (of, on, expected) in cases) {
        final report = lastYear(of, on);
        expect(report.compare, ReportCompare.lastYear, reason: '$of');
        expect(report.previousSpan, expected, reason: '$of');
        expect(report.compared!.span, expected, reason: '$of');
      }
      expect(
        lastYear(
          span(day(2026, 11, 2), day(2026, 11, 8)),
          today,
        ).previousSpan!.start.weekday,
        DateTime.monday,
        reason: 'whole weeks keep their weekdays',
      );
    });

    test('last year: a shifted span that gains 29 February is clamped to '
        'the scan\'s cap', () {
      final report = lastYear(
        span(day(2028, 3, 1), day(2029, 3, 1)),
        day(2029, 3, 10),
      );
      final compared = report.compared!.span;
      expect(compared.end, day(2028, 3, 1), reason: 'the shifted end');
      expect(
        compared.end.difference(compared.start).inDays + 1,
        lessThanOrEqualTo(EventAgenda.maxRangeDays),
      );
      expect(report.previousSpan, compared);
      expect(
        report.compared!.totals!.kept,
        EventAgenda.maxRangeDays,
        reason: 'every day the span names is scanned',
      );
    });

    test('last year before the calendar\'s first day folds as the previous '
        'period', () {
      final report = lastYear(span(day(1900, 1, 1), day(1900, 1, 31)), today);
      expect(report.compare, ReportCompare.previous);
      expect(report.previousSpan, isNull);
      expect(report.compared, isNull);
    });

    test('a plan compares with the previous period whatever is asked', () {
      profileGym();
      final november = span(day(2026, 11, 1), day(2026, 11, 30));
      for (final (compare, view) in [
        (ReportCompare.lastYear, null),
        (ReportCompare.view, viewOf({'gym'})),
      ]) {
        final service = CalendarReportService();
        final report = service.report(
          request(
            span: november,
            previousSpan: october,
            events: [daily],
            today: day(2026, 10, 15),
            compare: compare,
            compareView: view,
          ),
        );
        expect(report.tense, ReportTense.future);
        expect(report.compare, ReportCompare.previous, reason: '$compare');
        expect(report.previousSpan, october, reason: '$compare');
        expect(report.compared, isNull, reason: '$compare');
        expect(service.foldCount, 1, reason: '$compare');
      }
    });

    test('the compared today: the counted part\'s last day in a current '
        'span, the real today in a past one', () {
      final current = CalendarReportService().report(
        request(
          span: october,
          events: [daily],
          today: day(2026, 10, 10),
          compare: ReportCompare.lastYear,
        ),
      );
      final before = span(day(2025, 10, 1), day(2025, 10, 10));
      expect(current.previousCounted, before);
      final compared = current.compared!;
      expect((compared.today, compared.countedTo), (before.end, before.end));
      expect(compared.tense, ReportTense.current);
      expect(tile(current, ReportTile.events).previous, 10);

      final past = CalendarReportService()
          .report(
            request(
              span: september,
              events: [daily],
              today: day(2026, 10, 30),
              compare: ReportCompare.lastYear,
            ),
          )
          .compared!;
      expect((past.today, past.tense), (day(2026, 10, 30), ReportTense.past));
      expect(past.totals!.kept, 30);
    });

    test('previous totals are the compared fold\'s totals on the D28 '
        'fixtures', () {
      profileGym();
      EventPresence.updateCache(
        byEvent: {
          'd': {
            day(2026, 9, 5): PresenceStatus.missed,
            day(2026, 8, 7): PresenceStatus.missed,
          },
        },
      );
      for (final (of, before, on, previous) in [
        (september, august, day(2026, 10, 30), 30),
        (october, september, day(2026, 10, 10), 9),
        (october, september, day(2026, 10, 1), 1),
        (october, september, day(2026, 10, 31), 29),
      ]) {
        final asked = request(
          span: of,
          previousSpan: before,
          events: [daily],
          today: on,
        );
        final report = CalendarReportService().report(asked);
        expect(
          report.compared!.totals,
          CalendarReportService.sampleInput(asked).previousTotals,
          reason: '$of on $on',
        );
        expect(
          tile(report, ReportTile.events).previous,
          previous,
          reason: '$of on $on',
        );
      }
    });

    test('a view folds its categories over the span with the page\'s '
        'tiles', () {
      final events = [
        ev(
          'gym',
          'gym',
          day(2026, 1, 1),
          rule: const DailyRecurrence(),
          time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
        ),
        ev('lunch', 'friends', day(2026, 10, 3)),
        ev('dinner', 'friends', day(2026, 10, 9)),
      ];
      final report = CalendarReportService().report(
        request(
          span: october,
          previousSpan: september,
          events: events,
          today: today,
          compare: ReportCompare.view,
          compareView: viewOf({'friends'}),
        ),
      );
      expect(report.compare, ReportCompare.view);
      expect(report.previousSpan, september);
      expect(tile(report, ReportTile.events).previous, 30);
      final view = report.compared!;
      expect(view.span, october);
      expect(view.measures.keys, ['friends']);
      expect(
        [for (final t in view.tiles) t.tile],
        [for (final t in report.tiles) t.tile],
      );
      expect(tile(view, ReportTile.events).value, 2);
      expect(tile(view, ReportTile.hours).value, 0);
      expect(view.tiles.every((t) => t.previous == null), isTrue);
    });

    test('the two-fold memo: the same request folds nothing more, a step '
        'back and forth neither, a presence mark refolds both', () {
      profileGym();
      ReportRequest asked(
        DateRange of,
        DateRange before, {
        int presenceRevision = 0,
      }) => request(
        span: of,
        previousSpan: before,
        events: dailies,
        today: today,
        presenceRevision: presenceRevision,
      );
      final service = CalendarReportService();
      final first = service.report(asked(august, july));
      expect(service.foldCount, 2);
      expect(service.report(asked(august, july)), same(first));
      expect(service.foldCount, 2);
      service.report(asked(july, june));
      expect(service.foldCount, 4);
      service.report(asked(august, july));
      expect(service.foldCount, 4, reason: '◄ ►');
      service.report(asked(august, july, presenceRevision: 1));
      expect(service.foldCount, 6);
    });

    test('a view is two memo entries, and an edited view misses', () {
      ReportRequest asked(Set<String> ids) => request(
        span: august,
        previousSpan: july,
        events: dailies,
        today: today,
        compare: ReportCompare.view,
        compareView: viewOf(ids),
      );
      final service = CalendarReportService();
      service.report(asked({'gym'}));
      service.report(asked({'gym'}));
      expect(service.foldCount, 2);
      service.report(asked({'gym', 'friends'}));
      expect(service.foldCount, 4);
      service.report(
        request(
          span: august,
          previousSpan: july,
          events: dailies,
          today: today,
        ),
      );
      expect(service.foldCount, 5, reason: 'unprofiled, previous: one fold');
    });

    test('memoFolds keeps four compared reports', () {
      profileGym();
      final service = CalendarReportService();
      final spans = [(august, july), (july, june), (june, may), (may, april)];
      void askAll() {
        for (final (of, before) in spans) {
          service.report(
            request(
              span: of,
              previousSpan: before,
              events: dailies,
              today: today,
            ),
          );
        }
      }

      askAll();
      expect(service.foldCount, 8);
      askAll();
      expect(service.foldCount, 8, reason: 'eight entries hold four reports');
    });

    test('unprofiled, the default mode folds once, exactly as before', () {
      final asked = request(
        span: october,
        previousSpan: september,
        events: [daily],
        today: day(2026, 10, 20),
      );
      final service = CalendarReportService();
      final report = service.report(asked);
      expect(service.foldCount, 1);
      expect((report.compare, report.compared), (ReportCompare.previous, null));
      expect(report.balanceLastYear, isNull);
      expect(
        report,
        CalendarReportBuilder.fold(CalendarReportService.sampleInput(asked)),
      );
    });

    test('last year folds a second fold even unprofiled; Balance reads it', () {
      final service = CalendarReportService();
      final report = service.report(
        request(
          span: september,
          events: [
            ev(
              'gym',
              'gym',
              day(2025, 1, 1),
              rule: const DailyRecurrence(),
              time: const EventTime(startMinute: 9 * 60, durationMinutes: 30),
            ),
          ],
          today: today,
          compare: ReportCompare.lastYear,
        ),
      );
      expect(service.foldCount, 2);
      expect(report.balanceLastYear, report.compared!.balance);
      expect(report.balanceLastYear, {LifeArea.other: 30 * 30});
      expect(report.trend!.lastYear, List.filled(30, 1));
    });

    test('T1 through the service: a current span against the previous '
        'period\'s counted part', () {
      CategoryProfiles.updateCache({
        'gym': const CategoryProfile(
          id: 'p-gym',
          categoryId: 'gym',
          kind: CategoryKind.custom,
          measure: ReportMeasure.count,
        ),
      });
      // Ten visits by 20 September and three after it; thirteen by
      // 20 October and one still ahead.
      final events = [
        for (var i = 1; i <= 10; i++) ev('s$i', 'gym', day(2026, 9, i)),
        for (var i = 21; i <= 23; i++) ev('s$i', 'gym', day(2026, 9, i)),
        for (var i = 1; i <= 13; i++) ev('o$i', 'gym', day(2026, 10, i)),
        ev('ahead', 'gym', day(2026, 10, 25)),
      ];
      final report = CalendarReportService().report(
        request(
          span: october,
          previousSpan: september,
          events: events,
          today: day(2026, 10, 20),
        ),
      );
      final compared = report.compared!;
      expect(
        (compared.today, compared.countedTo),
        (day(2026, 9, 20), day(2026, 9, 20)),
      );
      final t1 = report.insights.singleWhere((i) => i.rule == InsightRule.t1);
      expect(
        (t1.categoryId, t1.n1, t1.n2),
        ('gym', 13, 10),
        reason: 'the whole of September would read 13 against 13',
      );
      expect(t1.ratio, closeTo(0.3, 1e-9));
    });

    test('the memo: a calendar year\'s previous period and last year share '
        'one compared entry', () {
      profileGym();
      final service = CalendarReportService();
      final y2026 = span(day(2026, 1, 1), day(2026, 12, 31));
      final y2025 = span(day(2025, 1, 1), day(2025, 12, 31));
      final on = day(2027, 1, 15);
      final previous = service.report(
        request(span: y2026, previousSpan: y2025, events: dailies, today: on),
      );
      expect(service.foldCount, 2);
      final lastYear = service.report(
        request(
          span: y2026,
          previousSpan: y2025,
          events: dailies,
          today: on,
          compare: ReportCompare.lastYear,
        ),
      );
      expect(service.foldCount, 3, reason: 'the main fold alone');
      expect(lastYear.compared, same(previous.compared));
    });

    test('the memo: the same previous span on another elapsed day misses', () {
      profileGym();
      final service = CalendarReportService();
      CalendarReport on(DateTime today) => service.report(
        request(
          span: october,
          previousSpan: september,
          events: dailies,
          today: today,
        ),
      );
      final tenth = on(day(2026, 10, 10));
      final twelfth = on(day(2026, 10, 12));
      expect(service.foldCount, 4);
      expect(
        (tenth.compared!.totals!.kept, twelfth.compared!.totals!.kept),
        (10, 12),
      );
    });

    test('the memo: a view re-folds when the main tile set changes, and a '
        'profiled view stays at two folds', () {
      profileGym();
      final events = [
        daily,
        ev('lunch', 'friends', day(2026, 8, 3)),
        ev('dinner', 'friends', day(2026, 8, 9)),
      ];
      final service = CalendarReportService();
      CalendarReport asked(Set<String> categoryIds) => service.report(
        request(
          span: august,
          previousSpan: july,
          categoryIds: categoryIds,
          events: events,
          today: today,
          compare: ReportCompare.view,
          compareView: viewOf({'friends'}),
        ),
      );
      List<ReportTile> tilesOf(CalendarReport r) => [
        for (final t in r.tiles) t.tile,
      ];
      final all = asked(const {});
      expect(service.foldCount, 2, reason: 'profiled: the main and the view');
      final gym = asked({'gym'});
      expect(tilesOf(gym), tilesOf(all));
      expect(service.foldCount, 3, reason: 'the same tiles: the view is hit');
      final friends = asked({'friends'});
      expect(tilesOf(friends), isNot(tilesOf(all)));
      expect(service.foldCount, 5, reason: 'other tiles: the view re-folds');
      expect(tilesOf(friends.compared!), tilesOf(friends));
    });
  });
}
