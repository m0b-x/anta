import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/event_search_query.dart';

/// The agenda scan's search semantics: every term must match (AND), a term may
/// be answered by the title, the description or the localized category label,
/// and a date term narrows the occurrence to its day.
///
/// Pure — no widget tree, no database. Category labels arrive as a map because
/// [EventAgenda] is deliberately context-free; the view resolves them once per
/// rescan where `AppLocalizations` actually exists.
void main() {
  final windowStart = DateTime.utc(2026, 8, 1);
  final windowEnd = DateTime.utc(2026, 9, 30);

  final gymDaily = CalendarEvent(
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
  final payday = CalendarEvent(
    id: 'pay',
    title: 'Payday',
    categoryId: 'finance',
    startDate: DateTime.utc(2026, 8, 5),
    description: 'Salary and rent',
    rule: const OneTimeRecurrence(),
  );
  final audit = CalendarEvent(
    id: 'audit',
    title: 'August audit',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 9, 3),
    rule: const OneTimeRecurrence(),
  );

  final events = [gymDaily, dentist, payday, audit];

  const labels = {
    'gym': 'Gym',
    'health': 'Health',
    'finance': 'Money',
    'other': 'Other',
  };

  List<EventOccurrence> scan(
    String query, {
    List<CalendarEvent>? only,
    Map<String, String> categoryLabels = labels,
  }) {
    return EventAgenda.occurrencesInRange(
      events: only ?? events,
      from: windowStart,
      to: windowEnd,
      query: EventSearchQuery.parse(query),
      categoryLabels: categoryLabels,
    );
  }

  Set<String> idsFor(String query, {Map<String, String> categoryLabels = labels}) {
    return scan(query, categoryLabels: categoryLabels)
        .map((o) => o.event.id)
        .toSet();
  }

  Set<DateTime> daysFor(String query, String eventId) {
    return scan(query)
        .where((o) => o.event.id == eventId)
        .map((o) => o.day)
        .toSet();
  }

  setUp(() {
    EventAgenda.debugDescriptionFolds = 0;
    CalendarEvent.debugOccursOnCalls = 0;
  });

  group('single term', () {
    test('an empty query keeps every event', () {
      expect(idsFor(''), {'gym', 'dentist', 'pay', 'audit'});
    });

    test('a title substring narrows to that event', () {
      expect(idsFor('dentist'), {'dentist'});
    });

    test('a description substring narrows to that event', () {
      expect(idsFor('barbell'), {'gym'});
    });
  });

  group('multi-term AND', () {
    test('every term must match, across fields', () {
      expect(idsFor('leg squat'), {'gym'});
      expect(idsFor('squat barbell'), {'gym'});
    });

    test('one unmatched term drops the event', () {
      expect(idsFor('leg deadlift'), isEmpty);
    });

    test('terms living on different events match neither', () {
      expect(idsFor('leg dentist'), isEmpty);
    });

    test('order does not matter', () {
      expect(idsFor('squat leg'), idsFor('leg squat'));
    });

    test('extra whitespace changes nothing', () {
      expect(idsFor('  leg    squat  '), {'gym'});
    });

    test('diacritics and case still fold per term', () {
      expect(idsFor('LEG SqUaT'), {'gym'});
    });
  });

  group('category matching', () {
    test('a term matches the localized category label', () {
      expect(idsFor('gym'), {'gym'});
      expect(idsFor('money'), {'pay'});
    });

    test('without labels the same term finds nothing', () {
      expect(idsFor('money', categoryLabels: const {}), isEmpty);
    });

    test('a category term counts as satisfied for the AND', () {
      expect(idsFor('money rent'), {'pay'});
      expect(idsFor('money salary'), {'pay'});
    });

    test('a category term still has to co-exist with the others', () {
      expect(idsFor('money squat'), isEmpty);
      expect(idsFor('gym rent'), isEmpty);
    });

    test('a label hit costs no description fold', () {
      scan('gym', only: [gymDaily]);
      expect(EventAgenda.debugDescriptionFolds, 0);
    });

    test('an unknown category id simply contributes nothing', () {
      final orphan = CalendarEvent(
        id: 'orphan',
        title: 'Orphan',
        categoryId: 'deleted-category',
        startDate: DateTime.utc(2026, 8, 4),
        rule: const OneTimeRecurrence(),
      );
      expect(idsFor('orphan'), isEmpty);
      expect(
        scan('orphan', only: [orphan]).map((o) => o.event.id).toSet(),
        {'orphan'},
      );
    });
  });

  group('date terms', () {
    test('a month + day pair narrows to that day', () {
      expect(daysFor('aug 26', 'gym'), {DateTime.utc(2026, 8, 26)});
      expect(idsFor('aug 26'), {'gym', 'dentist'});
    });

    test('the reversed order is the same filter', () {
      expect(idsFor('26 aug'), idsFor('aug 26'));
    });

    test('an ISO date narrows to that exact day', () {
      expect(daysFor('2026-09-03', 'gym'), {DateTime.utc(2026, 9, 3)});
      expect(idsFor('2026-09-03'), {'gym', 'audit'});
    });

    test('a bare month name selects the whole month', () {
      final september = daysFor('september', 'gym');
      expect(september, hasLength(30));
      expect(september.every((d) => d.month == 9), isTrue);
    });

    test('a date term ANDs with a text term', () {
      expect(idsFor('squat aug 26'), {'gym'});
      expect(daysFor('squat aug 26', 'gym'), {DateTime.utc(2026, 8, 26)});
      expect(idsFor('dentist aug 26'), {'dentist'});
      expect(idsFor('dentist september'), isEmpty);
    });

    test('a date term is still satisfiable by text on another day', () {
      // "August audit" falls on 3 September, and its title carries the term.
      expect(idsFor('august'), contains('audit'));
    });

    test('a day the query excludes drops out of a daily event', () {
      expect(daysFor('aug 26', 'gym'), isNot(contains(DateTime.utc(2026, 8, 25))));
    });

    test('narrowing by date costs no extra occursOn call', () {
      scan('');
      final baseline = CalendarEvent.debugOccursOnCalls;
      CalendarEvent.debugOccursOnCalls = 0;
      scan('aug 26');
      expect(CalendarEvent.debugOccursOnCalls, baseline);
    });
  });
}
