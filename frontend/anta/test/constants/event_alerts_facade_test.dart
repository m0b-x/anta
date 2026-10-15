import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';

/// `EventAlerts.effectiveFor` is what every reader of "what will this event
/// do" moves to — the badges now, the planner, the hub and the editor later —
/// so its merge is pinned here against the facade alone: the order, the
/// dedupe (D4), the opt-out (D3), and the badge answers over inherited rows.
void main() {
  CalendarCategory category(String id, int sortOrder) => CalendarCategory(
    id: id,
    name: id,
    colorValue: 0xFF000000,
    iconKey: 'event',
    sortOrder: sortOrder,
    isBuiltIn: true,
  );

  setUp(() {
    EventAlerts.resetCache();
    EventAlerts.configureDefaultDayMinute(null);
    // `effectiveFor` resolves the category as rendering does, and an
    // unconfigured catalog resolves every id to `other`.
    CalendarCategories.updateCache([
      category('birthday', 0),
      category('gym', 1),
      category('other', 2),
    ]);
  });
  tearDown(() {
    EventAlerts.resetCache();
    CalendarCategories.updateCache(const []);
  });

  CalendarEvent eventOf({
    String id = 'e1',
    String categoryId = 'birthday',
    bool categoryAlerts = true,
    EventTime? time,
  }) => CalendarEvent(
    id: id,
    title: 'Ana',
    categoryId: categoryId,
    startDate: DateTime.utc(2026, 10, 4),
    rule: const OneTimeRecurrence(),
    categoryAlerts: categoryAlerts,
    time: time,
  );

  void publish({
    Map<String, List<EventAlert>> byEvent = const {},
    Map<String, List<CategoryAlert>> byCategory = const {},
  }) {
    EventAlerts.updateCache(
      byEvent: {
        for (final entry in byEvent.entries)
          entry.key: List.unmodifiable(entry.value),
      },
    );
    EventAlerts.updateCategoryCache(
      byCategory: {
        for (final entry in byCategory.entries)
          entry.key: List.unmodifiable(entry.value),
      },
    );
  }

  const dayBefore = CategoryAlert(
    id: 'c1',
    categoryId: 'birthday',
    daysBefore: 1,
    dayMinute: 1200,
  );
  const onTheDay = CategoryAlert(
    id: 'c2',
    categoryId: 'birthday',
    mode: AlertMode.ring,
    offsetMinutes: 60,
  );

  group('effectiveFor', () {
    test('own alerts first, then the category\'s in its order', () {
      publish(
        byEvent: {
          'e1': const [EventAlert(id: 'own', eventId: 'e1', offsetMinutes: 5)],
        },
        byCategory: {
          'birthday': const [onTheDay, dayBefore],
        },
      );

      final effective = EventAlerts.effectiveFor(eventOf());

      expect(effective.map((a) => a.id), ['own', 'c2', 'c1']);
      expect(effective.map((a) => a.categoryId), [
        null,
        'birthday',
        'birthday',
      ]);
      expect(
        effective.every((a) => a.eventId == 'e1'),
        isTrue,
        reason: 'a projected alert belongs to the event it is read for',
      );
    });

    test('an own alert with the same timing wins, with its id and sound', () {
      publish(
        byEvent: {
          'e1': const [
            EventAlert(
              id: 'own',
              eventId: 'e1',
              daysBefore: 1,
              dayMinute: 1200,
              sound: 'mine',
            ),
          ],
        },
        byCategory: {
          'birthday': const [dayBefore, onTheDay],
        },
      );

      final effective = EventAlerts.effectiveFor(eventOf());

      expect(effective.map((a) => a.id), ['own', 'c2']);
      expect(effective.first.sound, 'mine');
      expect(effective.first.categoryId, isNull);
    });

    test('a different mode or time of day is not a duplicate', () {
      publish(
        byEvent: {
          'e1': const [
            EventAlert(
              id: 'ring',
              eventId: 'e1',
              mode: AlertMode.ring,
              daysBefore: 1,
              dayMinute: 1200,
            ),
            EventAlert(
              id: 'early',
              eventId: 'e1',
              daysBefore: 1,
              dayMinute: 60,
            ),
          ],
        },
        byCategory: {
          'birthday': const [dayBefore],
        },
      );

      expect(EventAlerts.effectiveFor(eventOf()).map((a) => a.id), [
        'ring',
        'early',
        'c1',
      ]);
    });

    test('an opted-out event inherits nothing', () {
      publish(
        byEvent: {
          'e1': const [EventAlert(id: 'own', eventId: 'e1')],
        },
        byCategory: {
          'birthday': const [dayBefore, onTheDay],
        },
      );

      expect(
        EventAlerts.effectiveFor(
          eventOf(categoryAlerts: false),
        ).map((a) => a.id),
        ['own'],
      );
    });

    test('disabled rows stay in the list on either side', () {
      publish(
        byEvent: {
          'e1': const [EventAlert(id: 'own', eventId: 'e1', enabled: false)],
        },
        byCategory: {
          'birthday': [dayBefore.copyWith(enabled: false)],
        },
      );

      final effective = EventAlerts.effectiveFor(eventOf());

      expect(effective.map((a) => a.id), ['own', 'c1']);
      expect(effective.every((a) => !a.enabled), isTrue);
    });

    test('another category\'s alerts never reach the event', () {
      publish(
        byCategory: {
          'birthday': const [dayBefore],
        },
      );

      expect(EventAlerts.effectiveFor(eventOf(categoryId: 'gym')), isEmpty);
    });

    test('a dangling category id inherits other\'s alerts', () {
      publish(
        byCategory: {
          'other': const [
            CategoryAlert(id: 'o1', categoryId: 'other', daysBefore: 1),
          ],
        },
      );

      final effective = EventAlerts.effectiveFor(eventOf(categoryId: 'gone'));

      expect(effective.map((a) => a.id), ['o1']);
      expect(effective.single.categoryId, 'other');
      expect(EventAlerts.hasReminder(eventOf(categoryId: 'gone')), isTrue);
    });

    test('a timed event compares only its minutes before the start', () {
      publish(
        byEvent: {
          'e1': const [EventAlert(id: 'own', eventId: 'e1', offsetMinutes: 30)],
        },
        byCategory: {
          'birthday': const [
            CategoryAlert(
              id: 'c1',
              categoryId: 'birthday',
              offsetMinutes: 30,
              daysBefore: 1,
              dayMinute: 540,
            ),
          ],
        },
      );

      final timed = eventOf(time: const EventTime(startMinute: 18 * 60));

      expect(EventAlerts.effectiveFor(timed).map((a) => a.id), ['own']);
    });

    test('an all-day event reads a null time as the default it fires at', () {
      EventAlerts.configureDefaultDayMinute(540);
      publish(
        byEvent: {
          'e1': const [EventAlert(id: 'own', eventId: 'e1', daysBefore: 1)],
        },
        byCategory: {
          'birthday': const [
            CategoryAlert(
              id: 'c1',
              categoryId: 'birthday',
              offsetMinutes: 15,
              daysBefore: 1,
              dayMinute: 540,
            ),
          ],
        },
      );

      final effective = EventAlerts.effectiveFor(eventOf());

      expect(effective.map((a) => a.id), ['own']);
      expect(effective.single.categoryId, isNull);
    });

    test('with nothing inherited the own list comes back as is', () {
      publish(
        byEvent: {
          'e1': const [EventAlert(id: 'own', eventId: 'e1')],
        },
      );

      expect(
        identical(
          EventAlerts.effectiveFor(eventOf()),
          EventAlerts.alertsFor('e1'),
        ),
        isTrue,
      );
    });

    test('hands out an unmodifiable list', () {
      publish(
        byCategory: {
          'birthday': const [dayBefore],
        },
      );

      expect(
        () => EventAlerts.effectiveFor(
          eventOf(),
        ).add(const EventAlert(id: 'x', eventId: 'e1')),
        throwsUnsupportedError,
      );
    });
  });

  group('inheritedFor', () {
    test('is effectiveFor\'s inherited tail', () {
      publish(
        byEvent: {
          'e1': const [
            EventAlert(
              id: 'own',
              eventId: 'e1',
              daysBefore: 1,
              dayMinute: 1200,
            ),
          ],
        },
        byCategory: {
          'birthday': const [dayBefore, onTheDay],
        },
      );

      expect(EventAlerts.inheritedFor(eventOf()).map((a) => a.id), ['c2']);
    });

    test('reads shadowing against the own set it is handed', () {
      publish(
        byCategory: {
          'birthday': const [dayBefore, onTheDay],
        },
      );

      final inherited = EventAlerts.inheritedFor(
        eventOf(),
        own: const [
          EventAlert(id: 'new', eventId: 'e1', daysBefore: 1, dayMinute: 1200),
        ],
      );

      expect(inherited.map((a) => a.id), ['c2']);
      expect(inherited.single.categoryId, 'birthday');
    });

    test('an opted-out event inherits only when the opt-out is ignored', () {
      publish(
        byCategory: {
          'birthday': const [dayBefore],
        },
      );
      final optedOut = eventOf(categoryAlerts: false);

      expect(EventAlerts.inheritedFor(optedOut), isEmpty);
      expect(
        EventAlerts.inheritedFor(
          optedOut,
          ignoreOptOut: true,
        ).map((a) => (a.id, a.eventId)),
        [('c1', 'e1')],
      );
    });
  });

  group('categoryAlertsFor', () {
    test('is the category\'s list, empty for an unknown one', () {
      publish(
        byCategory: {
          'birthday': const [dayBefore, onTheDay],
        },
      );

      expect(EventAlerts.categoryAlertsFor('birthday'), [dayBefore, onTheDay]);
      expect(EventAlerts.categoryAlertsFor('gym'), isEmpty);
    });
  });

  group('hasAlarm and hasReminder', () {
    test('answer over inherited alerts', () {
      publish(
        byCategory: {
          'birthday': const [onTheDay, dayBefore],
        },
      );

      expect(EventAlerts.hasAlarm(eventOf()), isTrue);
      expect(EventAlerts.hasReminder(eventOf()), isTrue);
    });

    test('an opt-out silences only what was inherited', () {
      publish(
        byEvent: {
          'e1': const [EventAlert(id: 'own', eventId: 'e1')],
        },
        byCategory: {
          'birthday': const [onTheDay],
        },
      );

      final optedOut = eventOf(categoryAlerts: false);
      expect(EventAlerts.hasAlarm(optedOut), isFalse);
      expect(EventAlerts.hasReminder(optedOut), isTrue);
    });

    test('a disabled inherited alert promises nothing', () {
      publish(
        byCategory: {
          'birthday': [onTheDay.copyWith(enabled: false)],
        },
      );

      expect(EventAlerts.hasAlarm(eventOf()), isFalse);
    });

    test('a disabled own alert shadows the inherited one it duplicates', () {
      publish(
        byEvent: {
          'e1': const [
            EventAlert(
              id: 'own',
              eventId: 'e1',
              mode: AlertMode.ring,
              offsetMinutes: 60,
              enabled: false,
            ),
          ],
        },
        byCategory: {
          'birthday': const [onTheDay],
        },
      );

      // The own row wins the dedupe (D4) and is switched off, so the event
      // will not ring — the badge must agree with effectiveFor.
      expect(EventAlerts.effectiveFor(eventOf()).single.id, 'own');
      expect(EventAlerts.hasAlarm(eventOf()), isFalse);
    });
  });

  group('revision', () {
    test('moves on a category write', () {
      final before = EventAlerts.revision;
      EventAlerts.updateCategoryCache(
        byCategory: {
          'birthday': List.unmodifiable(const [dayBefore]),
        },
      );
      expect(EventAlerts.revision, greaterThan(before));
    });

    test('reset clears the category half too', () {
      publish(
        byCategory: {
          'birthday': const [dayBefore],
        },
      );

      EventAlerts.resetCache();

      expect(EventAlerts.categoryAlertsFor('birthday'), isEmpty);
      expect(EventAlerts.hasReminder(eventOf()), isFalse);
    });
  });
}
