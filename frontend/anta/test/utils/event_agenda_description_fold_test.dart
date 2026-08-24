import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/event_search_query.dart';

/// Guard for **4.1**: the agenda's search scan must fold each event's
/// **template** description once per event, not once per (event, day), while
/// still deciding membership per day for events that carry per-occurrence
/// text.
///
/// Two halves that have to hold together, which is why they share a file:
///
///   * the **budget** — `EventAgenda.debugDescriptionFolds`, in the register
///     of `CalendarEvent.debugOccursOnCalls`, counts calls rather than
///     milliseconds, so it belongs in the default suite;
///   * the **asymmetry** the cache is not allowed to flatten. A day's live
///     override always wins over the template, *including when it is empty*,
///     so an event can drop out of one day while staying on every other. A
///     naive per-event memo would erase exactly this.
///
/// Pure: no widget tree, no database. `OccurrenceDescriptions` is a
/// process-wide static, so every test resets it.
void main() {
  final windowStart = DateTime.utc(2026, 8, 1);
  // 31 days, so a per-day fold would exceed a per-event one by a factor no
  // off-by-one could explain away.
  final windowEnd = DateTime.utc(2026, 8, 31);
  const windowDays = 31;

  CalendarEvent daily({
    required String id,
    String title = 'Untitled',
    String? description,
    bool perOccurrenceDescriptions = false,
  }) {
    return CalendarEvent(
      id: id,
      title: title,
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 7, 1),
      description: description,
      perOccurrenceDescriptions: perOccurrenceDescriptions,
      rule: const DailyRecurrence(),
    );
  }

  List<EventOccurrence> scan(List<CalendarEvent> events, String query) {
    return EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      query: EventSearchQuery.parse(query),
    );
  }

  Set<DateTime> daysOf(List<EventOccurrence> occurrences, String eventId) {
    return occurrences
        .where((o) => o.event.id == eventId)
        .map((o) => o.day)
        .toSet();
  }

  setUp(() {
    OccurrenceDescriptions.resetCache();
    EventAgenda.debugDescriptionFolds = 0;
  });

  tearDownAll(OccurrenceDescriptions.resetCache);

  group('fold budget', () {
    test('a matching template is folded once per event, not once per day', () {
      final events = [
        for (var i = 0; i < 10; i++)
          daily(id: 'e$i', description: 'Barbell squat programme'),
      ];

      final result = scan(events, 'squat');

      // Every event occurs on every day, so the scan really did visit all
      // 310 (event, day) pairs — the fold count is low because of the cache,
      // not because the work was skipped.
      expect(result.length, 10 * windowDays);
      expect(EventAgenda.debugDescriptionFolds, 10);
    });

    test('a non-matching template is also folded only once per event', () {
      final events = [
        for (var i = 0; i < 10; i++)
          daily(id: 'e$i', description: 'Barbell squat programme'),
      ];

      expect(scan(events, 'deadlift'), isEmpty);
      // The miss is cached too: an event pruned at the candidate stage never
      // reaches the day loop at all.
      expect(EventAgenda.debugDescriptionFolds, 10);
    });

    test('a title hit costs no description fold', () {
      final events = [
        for (var i = 0; i < 10; i++)
          daily(id: 'e$i', title: 'Squat day', description: 'Long preamble'),
      ];

      expect(scan(events, 'squat').length, 10 * windowDays);
      expect(EventAgenda.debugDescriptionFolds, 0);
    });

    test('an empty query folds nothing', () {
      final events = [
        for (var i = 0; i < 10; i++)
          daily(id: 'e$i', description: 'Barbell squat programme'),
      ];

      expect(scan(events, '').length, 10 * windowDays);
      expect(EventAgenda.debugDescriptionFolds, 0);
    });

    test('an opted-in event with no override still folds once', () {
      // `perOccurrenceDescriptions` alone must not push the event onto the
      // per-day path: with an empty override map every day resolves to the
      // template, so the cached answer stands.
      final event = daily(
        id: 'e',
        description: 'Barbell squat programme',
        perOccurrenceDescriptions: true,
      );

      expect(scan([event], 'squat').length, windowDays);
      expect(EventAgenda.debugDescriptionFolds, 1);
    });

    test('an overriding event folds the template once plus its overrides', () {
      final event = daily(
        id: 'e',
        description: 'Barbell squat programme',
        perOccurrenceDescriptions: true,
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'e': {
            DateTime.utc(2026, 8, 4): 'Squat, heavy',
            DateTime.utc(2026, 8, 9): 'Rest instead',
          },
        },
      );

      expect(scan([event], 'squat').length, windowDays - 1);
      // One template fold plus one per overridden day — the other 29 days
      // fall back to the cached template answer without folding anything.
      expect(EventAgenda.debugDescriptionFolds, 3);
    });
  });

  group('per-day asymmetry survives the cache', () {
    test('an override that drops the needle drops only its own day', () {
      final event = daily(
        id: 'e',
        description: 'Barbell squat programme',
        perOccurrenceDescriptions: true,
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'e': {DateTime.utc(2026, 8, 9): 'Rest instead'},
        },
      );

      final days = daysOf(scan([event], 'squat'), 'e');

      expect(days, hasLength(windowDays - 1));
      expect(days, isNot(contains(DateTime.utc(2026, 8, 9))));
      expect(days, contains(DateTime.utc(2026, 8, 8)));
      expect(days, contains(DateTime.utc(2026, 8, 10)));
    });

    test('a blanked day drops out — an empty override is still live', () {
      final event = daily(
        id: 'e',
        description: 'Barbell squat programme',
        perOccurrenceDescriptions: true,
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'e': {DateTime.utc(2026, 8, 9): ''},
        },
      );

      final days = daysOf(scan([event], 'squat'), 'e');

      expect(days, hasLength(windowDays - 1));
      expect(days, isNot(contains(DateTime.utc(2026, 8, 9))));
    });

    test('an override that adds the needle brings in only its own day', () {
      // The candidate pre-filter must admit this event on the strength of the
      // override alone: its template never mentions the needle.
      final event = daily(
        id: 'e',
        description: 'Barbell press programme',
        perOccurrenceDescriptions: true,
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'e': {DateTime.utc(2026, 8, 9): 'Squat, heavy'},
        },
      );

      expect(daysOf(scan([event], 'squat'), 'e'), {DateTime.utc(2026, 8, 9)});
    });

    test('overrides are ignored while the event has not opted in', () {
      // `appliesTo` is false, so `descriptionFor` returns the template for
      // every day and the stale rows must not narrow anything.
      final event = daily(
        id: 'e',
        description: 'Barbell squat programme',
        perOccurrenceDescriptions: false,
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'e': {DateTime.utc(2026, 8, 9): 'Rest instead'},
        },
      );

      expect(scan([event], 'squat').length, windowDays);
      expect(EventAgenda.debugDescriptionFolds, 1);
    });

    test('a null template still matches through an override', () {
      final event = daily(id: 'e', perOccurrenceDescriptions: true);
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'e': {DateTime.utc(2026, 8, 9): 'Squat, heavy'},
        },
      );

      expect(daysOf(scan([event], 'squat'), 'e'), {DateTime.utc(2026, 8, 9)});
    });

    test('folding stays diacritic-insensitive on both paths', () {
      final template = daily(id: 't', description: 'Sărbătoare de vară');
      final overridden = daily(
        id: 'o',
        description: 'Nimic aici',
        perOccurrenceDescriptions: true,
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'o': {DateTime.utc(2026, 8, 9): 'Sărbătoare mutată'},
        },
      );

      final result = scan([template, overridden], 'sarbatoare');

      expect(daysOf(result, 't'), hasLength(windowDays));
      expect(daysOf(result, 'o'), {DateTime.utc(2026, 8, 9)});
    });
  });
}
