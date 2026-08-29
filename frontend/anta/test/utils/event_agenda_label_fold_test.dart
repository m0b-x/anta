import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/agenda_search_text.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/event_search_query.dart';

/// An agenda row shows more than its title, its category and its description:
/// it shows the recurrence pattern, the time (or an explicit "All day" badge)
/// and the priority word. This pins the seam that makes those searchable —
/// `occurrencesInRange`'s `labelTextOf` closure — on both halves at once:
///
///   * the **budget** — `EventAgenda.debugLabelFolds`, in the register of
///     `debugDescriptionFolds`, counts calls rather than milliseconds. The
///     closure builds several localized strings, so it must run once per
///     candidate event, never once per (event, day), and not at all when the
///     title or the category already settled the query;
///   * the **behaviour** — typing what the row displays finds the row.
///
/// The closure is supplied by the test for the same reason the view supplies
/// it in the app: [EventAgenda] is deliberately `AppLocalizations`-free, so it
/// takes these strings from outside exactly as it takes the category labels.
///
/// Pure: no widget tree, no database. `OccurrenceDescriptions` is a
/// process-wide static, so every test resets it.
void main() {
  final l10n = AppLocalizationsEn();

  // `RecurrenceFormatter` formats weekday names and `EventTimeFormatter`
  // formats times while the labels are folded. In the app the localization
  // delegates have loaded the locale data by then; driving the scan bare has
  // to do it explicitly.
  setUpAll(() => initializeDateFormatting('en'));

  final windowStart = DateTime.utc(2026, 8, 1);
  // 31 days, so a per-day fold would exceed a per-event one by a factor no
  // off-by-one could explain away.
  final windowEnd = DateTime.utc(2026, 8, 31);
  const windowDays = 31;

  CalendarEvent event({
    required String id,
    String title = 'Untitled',
    String? description,
    RecurrenceRule rule = const DailyRecurrence(),
    DateTime? startDate,
    EventTime? time,
    int priority = kDefaultEventPriority,
  }) {
    return CalendarEvent(
      id: id,
      title: title,
      categoryId: 'gym',
      startDate: startDate ?? DateTime.utc(2026, 7, 1),
      description: description,
      rule: rule,
      time: time,
      priority: priority,
    );
  }

  List<EventOccurrence> scan(
    List<CalendarEvent> events,
    String query, {
    bool withLabels = true,
  }) {
    return EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      query: EventSearchQuery.parse(query),
      labelTextOf: withLabels
          ? (candidate) => AgendaSearchText.forEvent(candidate, l10n)
          : null,
    );
  }

  Set<String> idsOf(List<EventOccurrence> occurrences) =>
      occurrences.map((o) => o.event.id).toSet();

  setUp(() {
    OccurrenceDescriptions.resetCache();
    EventAgenda.debugLabelFolds = 0;
    EventAgenda.debugDescriptionFolds = 0;
  });

  tearDownAll(OccurrenceDescriptions.resetCache);

  group('fold budget', () {
    test('a matching label is folded once per event, not once per day', () {
      final events = [
        for (var i = 0; i < 10; i++)
          event(id: 'e$i', description: 'Barbell squat programme'),
      ];

      // Every row reads "Daily · All day"; the recurrence segment answers it.
      final result = scan(events, 'daily');

      // Every event occurs on every day, so the scan really did visit all
      // 310 (event, day) pairs — the fold count is low because the labels do
      // not vary by day, not because the work was skipped.
      expect(result.length, 10 * windowDays);
      expect(EventAgenda.debugLabelFolds, 10);
      // Fold order: the labels settle the query before the description is
      // touched, so a recurrence hit costs no description fold at all.
      expect(EventAgenda.debugDescriptionFolds, 0);
    });

    test('a non-matching label is also folded only once per event', () {
      final events = [
        for (var i = 0; i < 10; i++)
          event(id: 'e$i', description: 'Barbell squat programme'),
      ];

      expect(scan(events, 'deadlift'), isEmpty);
      expect(EventAgenda.debugLabelFolds, 10);
      // A label that settles nothing must not shortcut the description — that
      // is what keeps every pinned description-fold number where it was.
      expect(EventAgenda.debugDescriptionFolds, 10);
    });

    test('a title hit costs no label fold', () {
      final events = [
        for (var i = 0; i < 10; i++)
          event(id: 'e$i', title: 'Squat day', description: 'Long preamble'),
      ];

      expect(scan(events, 'squat').length, 10 * windowDays);
      expect(EventAgenda.debugLabelFolds, 0);
      expect(EventAgenda.debugDescriptionFolds, 0);
    });

    test('an empty query folds nothing', () {
      final events = [
        for (var i = 0; i < 10; i++)
          event(id: 'e$i', description: 'Barbell squat programme'),
      ];

      expect(scan(events, '').length, 10 * windowDays);
      expect(EventAgenda.debugLabelFolds, 0);
    });

    test('no closure means no folds and no label matching', () {
      final events = [for (var i = 0; i < 10; i++) event(id: 'e$i')];

      expect(scan(events, 'daily', withLabels: false), isEmpty);
      expect(EventAgenda.debugLabelFolds, 0);
    });
  });

  group('displayed text is searchable', () {
    test('a recurrence pattern finds the event', () {
      final weekly = event(
        id: 'weekly',
        rule: const WeeklyRecurrence(weekdays: {1, 3, 5}),
      );
      final monthly = event(id: 'monthly', rule: const MonthlyRecurrence());

      // "Weekly · Mon, Wed, Fri" — the frequency word and a weekday name are
      // both on the row, so both have to find it.
      expect(idsOf(scan([weekly, monthly], 'weekly')), {'weekly'});
      expect(idsOf(scan([weekly, monthly], 'wed')), {'weekly'});
      expect(idsOf(scan([weekly, monthly], 'monthly')), {'monthly'});
    });

    test('the same term finds nothing without the closure', () {
      final weekly = event(
        id: 'weekly',
        rule: const WeeklyRecurrence(weekdays: {1, 3, 5}),
      );

      expect(scan([weekly], 'weekly', withLabels: false), isEmpty);
    });

    test('all day finds an untimed event and not a timed one', () {
      final untimed = event(
        id: 'untimed',
        rule: const OneTimeRecurrence(),
        startDate: DateTime.utc(2026, 8, 10),
      );
      final timed = event(
        id: 'timed',
        rule: const OneTimeRecurrence(),
        startDate: DateTime.utc(2026, 8, 11),
        time: const EventTime(startMinute: 9 * 60, durationMinutes: 60),
      );

      expect(idsOf(scan([untimed, timed], 'all day')), {'untimed'});
    });

    test('a priority word finds the event, and the middle shows none', () {
      final highest = event(
        id: 'highest',
        rule: const OneTimeRecurrence(),
        startDate: DateTime.utc(2026, 8, 10),
        priority: kMinEventPriority,
      );
      final normal = event(
        id: 'normal',
        rule: const OneTimeRecurrence(),
        startDate: DateTime.utc(2026, 8, 11),
      );

      expect(idsOf(scan([highest, normal], 'highest')), {'highest'});
      // The row hides the badge at the default priority, so the word is not on
      // screen and must not be findable either.
      expect(scan([highest, normal], 'normal'), isEmpty);
    });

    test('a label term ANDs with a title term', () {
      final legs = event(id: 'legs', title: 'Leg day');
      final arms = event(
        id: 'arms',
        title: 'Arm day',
        rule: const WeeklyRecurrence(weekdays: {2}),
      );

      expect(idsOf(scan([legs, arms], 'leg daily')), {'legs'});
      expect(scan([legs, arms], 'arm daily'), isEmpty);
    });

    test('a label hit still narrows by a date term', () {
      final daily = event(id: 'daily');

      final days = scan([daily], 'daily aug 26').map((o) => o.day).toSet();

      expect(days, {DateTime.utc(2026, 8, 26)});
    });
  });
}
