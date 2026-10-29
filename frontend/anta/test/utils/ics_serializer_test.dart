import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/ics_serializer.dart';

/// Pins the serializer's core document: the `RRULE` each rule shape maps to,
/// the all-day date pair, escaping, folding, `CATEGORIES` and `PRIORITY`.
///
/// The two existing suites cover `VALARM` and the skip/holiday date lists
/// only, which is how a fold that measured characters where RFC 5545 counts
/// octets survived — so the octet assertion below is written against a
/// Romanian fixture, the shape that defect lands on.
void main() {
  // 2026-08-03 is a Monday, which is what makes the weekday rules anchor on
  // their own first day rather than being pushed forward.
  final anchor = DateTime.utc(2026, 8, 3);

  CalendarEvent event({
    RecurrenceRule rule = const OneTimeRecurrence(),
    String title = 'Leg day',
    String categoryId = 'gym',
    DateTime? startDate,
    DateTime? endDate,
    EventTime? time,
    String? description,
    bool perOccurrenceDescriptions = false,
    int priority = 3,
  }) {
    return CalendarEvent(
      id: 'e1',
      title: title,
      categoryId: categoryId,
      startDate: startDate ?? anchor,
      rule: rule,
      endDate: endDate,
      time: time,
      description: description,
      perOccurrenceDescriptions: perOccurrenceDescriptions,
      priority: priority,
    );
  }

  String export(CalendarEvent e) =>
      IcsSerializer.serialize(events: [e], now: DateTime.utc(2026, 8, 1));

  /// The document's physical lines, folding included.
  List<String> physicalLines(String ics) =>
      ics.split('\r\n').where((l) => l.isNotEmpty).toList();

  /// The one line starting with [name], unfolded.
  String? property(String ics, String name) {
    final buffer = StringBuffer();
    var found = false;
    for (final line in physicalLines(ics)) {
      if (found) {
        if (line.startsWith(' ')) {
          buffer.write(line.substring(1));
          continue;
        }
        break;
      }
      if (line.startsWith(name)) {
        buffer.write(line);
        found = true;
      }
    }
    return found ? buffer.toString() : null;
  }

  tearDown(() {
    CalendarCategories.updateCache(const []);
    OccurrenceDescriptions.resetCache();
  });

  group('RRULE per rule shape', () {
    test('a one-time event carries no RRULE', () {
      final ics = export(event());

      expect(ics, isNot(contains('RRULE')));
      expect(ics, isNot(contains('RDATE')));
    });

    test('daily, with and without an interval', () {
      expect(
        property(export(event(rule: const DailyRecurrence())), 'RRULE'),
        'RRULE:FREQ=DAILY',
      );
      expect(
        property(
          export(event(rule: const DailyRecurrence(interval: 3))),
          'RRULE',
        ),
        'RRULE:FREQ=DAILY;INTERVAL=3',
      );
    });

    test('weekly carries BYDAY in weekday order and WKST=MO', () {
      final ics = export(
        event(
          rule: const WeeklyRecurrence(
            weekdays: {DateTime.friday, DateTime.monday},
            interval: 2,
          ),
        ),
      );

      expect(
        property(ics, 'RRULE'),
        'RRULE:FREQ=WEEKLY;INTERVAL=2;WKST=MO;BYDAY=MO,FR',
      );
    });

    test('monthly and yearly carry their interval', () {
      expect(
        property(
          export(event(rule: const MonthlyRecurrence(interval: 2))),
          'RRULE',
        ),
        'RRULE:FREQ=MONTHLY;INTERVAL=2',
      );
      expect(
        property(export(event(rule: const YearlyRecurrence())), 'RRULE'),
        'RRULE:FREQ=YEARLY',
      );
    });

    test('workdays and weekends map to their weekday sets', () {
      expect(
        property(export(event(rule: const WorkdaysRecurrence())), 'RRULE'),
        'RRULE:FREQ=WEEKLY;WKST=MO;BYDAY=MO,TU,WE,TH,FR',
      );
      expect(
        property(export(event(rule: const WeekendsRecurrence())), 'RRULE'),
        'RRULE:FREQ=WEEKLY;WKST=MO;BYDAY=SA,SU',
      );
    });

    test('an explicit date set is RDATEs, never an RRULE', () {
      final ics = export(
        event(
          rule: SpecificDatesRecurrence(
            dates: {anchor, DateTime.utc(2026, 9, 14), DateTime.utc(2026, 8, 20)},
          ),
        ),
      );

      expect(ics, isNot(contains('RRULE')));
      // The anchor is DTSTART, so it is not repeated as an RDATE.
      expect(property(ics, 'RDATE'), 'RDATE;VALUE=DATE:20260820,20260914');
    });

    test('holidays-only is expanded to RDATEs', () {
      final ics = export(
        event(
          rule: const PublicHolidaysOnlyRecurrence(),
          startDate: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(ics, isNot(contains('RRULE')));
      expect(property(ics, 'DTSTART'), 'DTSTART;VALUE=DATE:20260101');
      expect(property(ics, 'RDATE'), contains('20260106'));
    });

    test("UNTIL takes DTSTART's value type", () {
      final until = DateTime.utc(2026, 12, 31);

      expect(
        property(
          export(event(rule: const DailyRecurrence(), endDate: until)),
          'RRULE',
        ),
        'RRULE:FREQ=DAILY;UNTIL=20261231',
      );
      expect(
        property(
          export(
            event(
              rule: const DailyRecurrence(),
              endDate: until,
              time: const EventTime(startMinute: 18 * 60),
            ),
          ),
          'RRULE',
        ),
        'RRULE:FREQ=DAILY;UNTIL=20261231T180000',
      );
    });
  });

  group('the date pair', () {
    test('an all-day event ends on the following day', () {
      final ics = export(event());

      expect(property(ics, 'DTSTART'), 'DTSTART;VALUE=DATE:20260803');
      expect(property(ics, 'DTEND'), 'DTEND;VALUE=DATE:20260804');
    });

    test('a timed event is floating local time, with no DTEND when open', () {
      final open = export(
        event(time: const EventTime(startMinute: 18 * 60 + 30)),
      );
      expect(property(open, 'DTSTART'), 'DTSTART:20260803T183000');
      expect(property(open, 'DTEND'), isNull);

      final closed = export(
        event(
          time: const EventTime(startMinute: 18 * 60, durationMinutes: 90),
        ),
      );
      expect(property(closed, 'DTEND'), 'DTEND:20260803T193000');
    });
  });

  group('text properties', () {
    test('escaping covers the four characters RFC 5545 reserves', () {
      final ics = export(event(title: r'Gym; cardio, back\shoulders'));

      expect(
        property(ics, 'SUMMARY'),
        r'SUMMARY:Gym\; cardio\, back\\shoulders',
      );
    });

    test('a newline in a description becomes a literal \\n', () {
      final ics = export(event(description: 'Set 1\nSet 2'));

      expect(property(ics, 'DESCRIPTION'), r'DESCRIPTION:Set 1\nSet 2');
    });

    test('the anchor occurrence\'s own description is what exports', () {
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'e1': {anchor: 'Deadlifts only'},
        },
      );

      final ics = export(
        event(
          rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
          perOccurrenceDescriptions: true,
        ),
      );

      expect(property(ics, 'DESCRIPTION'), 'DESCRIPTION:Deadlifts only');
    });

    test('a category exports its name, never its id', () {
      const customId = '3f1a7c94-0b6d-4c21-9f8e-55aa11bb22cc';
      CalendarCategories.updateCache(const [
        CalendarCategory(
          id: customId,
          name: 'Fizioterapie',
          colorValue: 0xFF123456,
          iconKey: 'healing',
          sortOrder: 10,
          isBuiltIn: false,
        ),
      ]);

      final ics = export(event(categoryId: customId));

      expect(property(ics, 'CATEGORIES'), 'CATEGORIES:Fizioterapie');
      expect(ics, isNot(contains(customId)));
    });
  });

  test('PRIORITY maps the app scale onto the RFC one', () {
    expect(property(export(event(priority: 1)), 'PRIORITY'), 'PRIORITY:1');
    expect(property(export(event(priority: 3)), 'PRIORITY'), 'PRIORITY:5');
    expect(property(export(event(priority: 5)), 'PRIORITY'), 'PRIORITY:9');
  });

  group('folding', () {
    /// A Romanian title of 65 diacritics: 73 characters, 138 octets — short
    /// enough for a character-counting guard to wave through and twice the
    /// limit RFC 5545 §3.1 actually sets.
    final diacritics = 'ă' * 65;

    test('every physical line of a Romanian export fits in 75 octets', () {
      CalendarCategories.updateCache(const [
        CalendarCategory(
          id: 'gym',
          name: 'Ședințe de recuperare și mobilitate articulară',
          colorValue: 0xFF123456,
          iconKey: 'healing',
          sortOrder: 0,
          isBuiltIn: false,
        ),
      ]);

      final ics = export(
        event(
          title: diacritics,
          description: 'Încălzire, apoi genuflexiuni și împins cu bara, '
              'urmate de tracțiuni la bară fixă și o plimbare lungă.',
          rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
        ),
      );

      for (final line in physicalLines(ics)) {
        expect(
          utf8.encode(line).length,
          lessThanOrEqualTo(75),
          reason: 'line over the RFC 5545 limit: $line',
        );
      }
    });

    test('a folded line continues with a single leading space', () {
      final ics = export(event(title: diacritics));
      final lines = physicalLines(ics);
      final index = lines.indexWhere((l) => l.startsWith('SUMMARY'));

      expect(lines[index + 1], startsWith(' '));
      expect(property(ics, 'SUMMARY'), 'SUMMARY:$diacritics');
    });
  });
}
