import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/event_query_matcher.dart';
import 'package:anta/utils/event_search_query.dart';

/// The agenda's search grammar on its own: what `occurrencesInRange` asks per
/// event and per day, and what a post-filter over resolved entries asks
/// without a scan. The scan's own suites pin that it still agrees.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  final day = DateTime.utc(2026, 8, 4);

  final gym = CalendarEvent(
    id: 'gym',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 7, 1),
    description: 'Barbell squat programme',
    rule: const DailyRecurrence(),
  );
  final dentist = CalendarEvent(
    id: 'dentist',
    title: 'Dentist',
    categoryId: 'health',
    startDate: DateTime.utc(2026, 8, 26),
    rule: const OneTimeRecurrence(),
  );

  EventQueryMatcher matcher(
    String raw, {
    Map<String, String> categoryLabels = const {
      'gym': 'Gym',
      'health': 'Health',
    },
    String Function(CalendarEvent event)? labelTextOf,
  }) => EventQueryMatcher(
    query: EventSearchQuery.parse(raw, localeName: 'en'),
    categoryLabels: categoryLabels,
    labelTextOf: labelTextOf,
  );

  setUp(() {
    OccurrenceDescriptions.resetCache();
    EventAgenda.debugClearFoldCaches();
    EventAgenda.debugDescriptionFolds = 0;
    EventAgenda.debugLabelFolds = 0;
  });

  tearDownAll(OccurrenceDescriptions.resetCache);

  test('without a query everything matches and nothing is folded', () {
    var labelCalls = 0;
    final m = matcher(
      '',
      labelTextOf: (_) {
        labelCalls++;
        return 'Daily';
      },
    );

    expect(m.searching, isFalse);
    expect(m.mayMatch(gym), isTrue);
    expect(m.matches(dentist, day), isTrue);
    expect(labelCalls, 0);
    expect(EventAgenda.debugDescriptionFolds, 0);
  });

  test('a title hit matches every day and folds no description', () {
    final m = matcher('dentist');

    expect(m.searching, isTrue);
    expect(m.mayMatch(dentist), isTrue);
    expect(m.matches(dentist, day), isTrue);
    expect(m.mayMatch(gym), isFalse);
    expect(m.matches(gym, day), isFalse);
    expect(EventAgenda.debugDescriptionFolds, 1);
  });

  test('a category label answers for its term', () {
    final m = matcher('health');

    expect(m.mayMatch(dentist), isTrue);
    expect(m.mayMatch(gym), isFalse);
    expect(
      matcher('health', categoryLabels: const {}).mayMatch(dentist),
      isFalse,
    );
  });

  test('the row labels answer, once per event', () {
    var labelCalls = 0;
    final m = matcher(
      'weekly',
      labelTextOf: (event) {
        labelCalls++;
        return event.id == 'gym' ? 'Weekly · P3' : 'Once';
      },
    );

    expect(m.mayMatch(gym), isTrue);
    expect(m.matches(gym, day), isTrue);
    expect(m.matches(gym, day.add(const Duration(days: 1))), isTrue);
    expect(m.mayMatch(dentist), isFalse);
    expect(labelCalls, 2);
    expect(EventAgenda.debugLabelFolds, 2);
  });

  test('the template description answers, folded once across days', () {
    final m = matcher('barbell');

    expect(m.mayMatch(gym), isTrue);
    for (var i = 0; i < 5; i++) {
      expect(m.matches(gym, day.add(Duration(days: i))), isTrue);
    }
    expect(EventAgenda.debugDescriptionFolds, 1);
  });

  test('a per-day override replaces the template on its day only', () {
    final event = CalendarEvent(
      id: 'e',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 7, 1),
      description: 'Barbell squat programme',
      perOccurrenceDescriptions: true,
      rule: const DailyRecurrence(),
    );
    OccurrenceDescriptions.updateCache(
      byEvent: {
        'e': {day: 'Rest instead', DateTime.utc(2026, 8, 9): 'Deadlift'},
      },
    );

    final squat = matcher('squat');
    expect(squat.mayMatch(event), isTrue);
    expect(squat.matches(event, day), isFalse);
    expect(squat.matches(event, DateTime.utc(2026, 8, 5)), isTrue);

    final deadlift = matcher('deadlift');
    expect(deadlift.mayMatch(event), isTrue);
    expect(deadlift.matches(event, DateTime.utc(2026, 8, 9)), isTrue);
    expect(deadlift.matches(event, DateTime.utc(2026, 8, 10)), isFalse);
  });

  test('a date clause narrows to the day it names', () {
    final m = matcher('leg aug 4');

    expect(m.mayMatch(gym), isTrue);
    expect(m.matches(gym, day), isTrue);
    expect(m.matches(gym, DateTime.utc(2026, 8, 5)), isFalse);
    expect(m.matches(dentist, DateTime.utc(2026, 8, 26)), isFalse);
  });

  test('the scan with a query lists exactly what the query-free scan lists '
      'through mayMatch and matches (review 21)', () {
    // A per-day series whose overrides include an empty text — which hides
    // the template on its day — beside a title, a category and a row label.
    final perDay = CalendarEvent(
      id: 'per-day',
      title: 'Session',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      endDate: DateTime.utc(2026, 8, 31),
      description: 'Barbell squat programme',
      perOccurrenceDescriptions: true,
      rule: const DailyRecurrence(),
    );
    final weekly = CalendarEvent(
      id: 'weekly',
      title: 'Swim',
      categoryId: 'other',
      startDate: DateTime.utc(2026, 7, 6),
      rule: const WeeklyRecurrence(weekdays: {1}),
    );
    OccurrenceDescriptions.updateCache(
      byEvent: {
        'per-day': {
          day: '',
          DateTime.utc(2026, 8, 9): 'Deadlift',
          DateTime.utc(2026, 8, 10): 'Squat light',
        },
      },
    );
    final events = [gym, dentist, perDay, weekly];
    const labels = {'gym': 'Gym', 'health': 'Health', 'other': 'Other'};
    String labelTextOf(CalendarEvent event) =>
        event.id == 'weekly' ? 'Weekly · Mon' : 'Daily';
    List<(String, DateTime)> keys(Iterable<EventOccurrence> list) => [
      for (final occurrence in list) (occurrence.event.id, occurrence.day),
    ];
    List<EventOccurrence> scan(EventSearchQuery query) =>
        EventAgenda.occurrencesInRange(
          events: events,
          from: DateTime.utc(2026, 7, 1),
          to: DateTime.utc(2026, 9, 30),
          query: query,
          categoryLabels: labels,
          labelTextOf: labelTextOf,
        );

    final all = scan(EventSearchQuery.empty);
    for (final raw in const [
      'squat',
      'deadlift',
      'leg aug 4',
      'aug 26',
      'health',
      'weekly',
      'session',
    ]) {
      final query = EventSearchQuery.parse(raw, localeName: 'en');
      final post = EventQueryMatcher(
        query: query,
        categoryLabels: labels,
        labelTextOf: labelTextOf,
      );
      expect(
        keys(scan(query)),
        keys([
          for (final occurrence in all)
            if (post.mayMatch(occurrence.event) &&
                post.matches(occurrence.event, occurrence.day))
              occurrence,
        ]),
        reason: '"$raw"',
      );
    }
    // The empty override hides the template's "squat" on its day.
    expect(
      keys(scan(EventSearchQuery.parse('squat', localeName: 'en'))),
      isNot(contains(('per-day', day))),
    );
  });

  test('matches resolves an event mayMatch never saw', () {
    final m = matcher('barbell');

    expect(m.matches(gym, day), isTrue);
    expect(m.matches(dentist, day), isFalse);
    expect(EventAgenda.debugDescriptionFolds, 1);
  });

  test('an edited event is a new object and resolves afresh', () {
    final m = matcher('deadlift');
    expect(m.mayMatch(gym), isFalse);

    final edited = gym.copyWith(description: 'Deadlift programme');
    expect(m.mayMatch(edited), isTrue);
  });
}
