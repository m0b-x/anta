import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/alert_planner.dart';

/// The planner is the one pure piece of the alert pipeline, and the only one
/// where a wrong answer is silent: an alert that is never planned simply never
/// rings, and nothing on screen says so.
///
/// Every case here pins `now` explicitly. That is the point of the clock seam
/// — a horizon test that read the wall clock would pass in September and fail
/// in December.
///
/// Times are asserted as **wall clock** (`hour`/`minute`/`day`), never as
/// epoch values: the host's timezone is not ours to choose, and the whole
/// promise of A14 is that 07:00 is 07:00 wherever the phone is.
void main() {
  const defaults = (
    timedDefault: (mode: AlertMode.notify, offsetMinutes: 10),
    allDayDefault: (mode: AlertMode.notify, daysBefore: 0, dayMinute: 540),
    sound: '',
    snoozeMinutes: 10,
    silenceAfterMinutes: 10,
    noticeLeadMinutes: 120,
  );

  const horizon = AlertHorizon(perAlert: 2, days: 30, total: 48);

  EventAlert alertOf(
    String id, {
    String eventId = 'e1',
    AlertMode mode = AlertMode.notify,
    int offsetMinutes = 0,
    int daysBefore = 0,
    int? dayMinute,
    bool enabled = true,
  }) => EventAlert(
    id: id,
    eventId: eventId,
    mode: mode,
    offsetMinutes: offsetMinutes,
    daysBefore: daysBefore,
    dayMinute: dayMinute,
    enabled: enabled,
  );

  CalendarEvent eventOf({
    String id = 'e1',
    String title = 'Leg day',
    required DateTime startDate,
    RecurrenceRule rule = const OneTimeRecurrence(),
    EventTime? time = const EventTime(startMinute: 7 * 60),
    DateTime? endDate,
  }) => CalendarEvent(
    id: id,
    title: title,
    categoryId: 'gym',
    startDate: startDate,
    rule: rule,
    time: time,
    endDate: endDate,
  );

  List<PlannedFire> planOf({
    required List<CalendarEvent> events,
    required Map<String, List<EventAlert>> alerts,
    required DateTime now,
    AlertHorizon caps = horizon,
  }) => AlertPlanner.plan(
    events: events,
    alertsByEvent: alerts,
    defaults: defaults,
    horizon: caps,
    now: now,
  );

  setUp(() {
    EventSkips.resetCache();
    PublicHolidays.resetCache();
  });

  tearDown(() {
    EventSkips.resetCache();
    PublicHolidays.resetCache();
  });

  group('timed events', () {
    test('a one-time event plans one fire at start minus the offset', () {
      final event = eventOf(startDate: DateTime.utc(2026, 9, 20));
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1', offsetMinutes: 10)],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan, hasLength(1));
      expect(plan.single.day, DateTime.utc(2026, 9, 20));
      expect(plan.single.fireAt.year, 2026);
      expect(plan.single.fireAt.month, 9);
      expect(plan.single.fireAt.day, 20);
      expect(plan.single.fireAt.hour, 6);
      expect(plan.single.fireAt.minute, 50);
      expect(plan.single.kind, AlertKind.scheduled);
    });

    test('an offset larger than the start minute reaches the day before', () {
      final event = eventOf(startDate: DateTime.utc(2026, 9, 20));
      final plan = planOf(
        events: [event],
        // One day before a 07:00 event is 07:00 the previous day.
        alerts: {
          'e1': [alertOf('a1', offsetMinutes: 24 * 60)],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan.single.day, DateTime.utc(2026, 9, 20));
      expect(plan.single.fireAt.day, 19);
      expect(plan.single.fireAt.hour, 7);
      expect(plan.single.fireAt.minute, 0);
    });

    test('an occurrence whose instant already passed today is not planned', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const DailyRecurrence(),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        // 12:00 today — today's 07:00 fire is behind us, tomorrow's is not.
        now: DateTime(2026, 9, 15, 12),
        caps: const AlertHorizon(perAlert: 1, days: 30, total: 48),
      );

      expect(plan, hasLength(1));
      expect(plan.single.day, DateTime.utc(2026, 9, 16));
    });

    test('a fire exactly at `now` is in the past, not the future', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 15),
        rule: const DailyRecurrence(),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 7),
        caps: const AlertHorizon(perAlert: 1, days: 30, total: 48),
      );

      expect(plan.single.day, DateTime.utc(2026, 9, 16));
    });
  });

  group('all-day events', () {
    test('days before and an explicit minute', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 20),
        time: null,
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1', daysBefore: 2, dayMinute: 20 * 60)],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan.single.day, DateTime.utc(2026, 9, 20));
      expect(plan.single.fireAt.day, 18);
      expect(plan.single.fireAt.hour, 20);
      expect(plan.single.fireAt.minute, 0);
    });

    test('a null dayMinute takes the settings default', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 20),
        time: null,
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan.single.fireAt.day, 20);
      expect(plan.single.fireAt.hour, 9);
      expect(plan.single.fireAt.minute, 0);
    });

    test('a null dayMinute falls back to 09:00 with no default set', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 20),
        time: null,
      );
      final plan = AlertPlanner.plan(
        events: [event],
        alertsByEvent: {
          'e1': [alertOf('a1')],
        },
        defaults: (
          timedDefault: null,
          allDayDefault: null,
          sound: '',
          snoozeMinutes: 10,
          silenceAfterMinutes: 10,
          noticeLeadMinutes: 120,
        ),
        horizon: horizon,
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan.single.fireAt.hour, 9);
    });

    test('the offset set is picked by the derived allDay, not the column', () {
      // One alert carrying *both* offset sets, planned twice: once for a timed
      // event and once for the same event flipped to all-day. Nothing is
      // rewritten between the two, which is the whole reason both are stored.
      final alert = alertOf('a1', offsetMinutes: 30, daysBefore: 1,
          dayMinute: 18 * 60);
      final timed = eventOf(startDate: DateTime.utc(2026, 9, 20));
      final allDay = timed.copyWith(clearTime: true);

      final timedPlan = planOf(
        events: [timed],
        alerts: {
          'e1': [alert],
        },
        now: DateTime(2026, 9, 15, 12),
      );
      final allDayPlan = planOf(
        events: [allDay],
        alerts: {
          'e1': [alert],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(timedPlan.single.fireAt.day, 20);
      expect(timedPlan.single.fireAt.hour, 6);
      expect(timedPlan.single.fireAt.minute, 30);
      expect(allDayPlan.single.fireAt.day, 19);
      expect(allDayPlan.single.fireAt.hour, 18);
    });
  });

  group('recurrence', () {
    test('weekly plans the next two matching days', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 7),
        rule: const WeeklyRecurrence(weekdays: {1, 3, 5}),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        // Tuesday 2026-09-15, 12:00 → Wed 16th and Fri 18th.
        now: DateTime(2026, 9, 15, 12),
      );

      expect(
        plan.map((fire) => fire.day),
        [DateTime.utc(2026, 9, 16), DateTime.utc(2026, 9, 18)],
      );
    });

    test('a skipped occurrence is never planned', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 7),
        rule: const WeeklyRecurrence(weekdays: {1, 3, 5}),
      );
      EventSkips.updateCache(
        byEvent: {
          'e1': {DateTime.utc(2026, 9, 16)},
        },
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(
        plan.map((fire) => fire.day),
        [DateTime.utc(2026, 9, 18), DateTime.utc(2026, 9, 21)],
      );
    });

    test('endDate truncates the horizon', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 7),
        rule: const WeeklyRecurrence(weekdays: {1, 3, 5}),
        endDate: DateTime.utc(2026, 9, 16),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan.map((fire) => fire.day), [DateTime.utc(2026, 9, 16)]);
    });

    test('a workdays rule reads the live holiday profile', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const WorkdaysRecurrence(),
      );
      final alerts = {
        'e1': [alertOf('a1')],
      };
      final now = DateTime(2026, 9, 15, 12);

      PublicHolidays.configure(
        profile: HolidayProfile.generic,
        overrides: const {},
        suppressed: const {},
      );
      final before = planOf(events: [event], alerts: alerts, now: now);
      expect(before.first.day, DateTime.utc(2026, 9, 16));

      // Nothing is dispatched when a holiday profile changes: the planner
      // re-walks the rules on every call, which is the entire mechanism that
      // carries the change to the OS.
      PublicHolidays.configure(
        profile: HolidayProfile.generic,
        overrides: {
          DateTime.utc(2026, 9, 16): const PublicHolidayInfo.custom('Strike'),
        },
        suppressed: const {},
      );
      final after = planOf(events: [event], alerts: alerts, now: now);
      expect(after.first.day, DateTime.utc(2026, 9, 17));
    });
  });

  group('horizon caps', () {
    test('perAlert bounds the occurrence days per alert', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const DailyRecurrence(),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1'), alertOf('a2', offsetMinutes: 30)],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      // Two alerts × two occurrence days each, never four days of one alert.
      expect(plan, hasLength(4));
      expect(
        plan.map((fire) => '${fire.alert.id}@${fire.day.day}').toSet(),
        {'a1@16', 'a1@17', 'a2@16', 'a2@17'},
      );
    });

    test('days bounds the walk', () {
      final event = eventOf(
        startDate: DateTime.utc(2026, 10, 20),
        rule: const DailyRecurrence(),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 12),
        caps: const AlertHorizon(perAlert: 2, days: 30, total: 48),
      );

      // The first occurrence is 35 days out, past the 30-day window.
      expect(plan, isEmpty);
    });

    test('total truncates the merged list, soonest first', () {
      final events = [
        for (var i = 0; i < 5; i++)
          eventOf(
            id: 'e$i',
            startDate: DateTime.utc(2026, 9, 1),
            rule: const DailyRecurrence(),
            time: EventTime(startMinute: 8 * 60 + i),
          ),
      ];
      final alerts = {
        for (var i = 0; i < 5; i++)
          'e$i': [alertOf('a$i', eventId: 'e$i')],
      };
      final plan = planOf(
        events: events,
        alerts: alerts,
        now: DateTime(2026, 9, 15, 12),
        caps: const AlertHorizon(perAlert: 2, days: 30, total: 3),
      );

      expect(plan, hasLength(3));
      expect(plan.map((fire) => fire.event.id), ['e0', 'e1', 'e2']);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].fireAt.isBefore(plan[i - 1].fireAt), isFalse);
      }
    });

    test('five alerts on one event all plan', () {
      final event = eventOf(startDate: DateTime.utc(2026, 9, 20));
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [
            for (var i = 0; i < 5; i++) alertOf('a$i', offsetMinutes: i * 5),
          ],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan, hasLength(5));
      // Soonest first: the largest offset fires earliest.
      expect(
        plan.map((fire) => fire.alert.id),
        ['a4', 'a3', 'a2', 'a1', 'a0'],
      );
    });
  });

  group('work budget', () {
    // Counted, not timed — the register of `calendar_occurs_on_budget_test`.
    // Every `occursOnUtcDay` is one (event, day) probe, and the planner runs on
    // every launch, resume and edit, so what it does with events that can no
    // longer ring is worth pinning exactly.
    setUp(() => CalendarEvent.debugOccursOnCalls = 0);

    test('events that can no longer occur cost no occurrence check at all', () {
      // A year of one-time sessions already held, a weekly whose end date has
      // passed, a daily that ended — all still carrying an enabled alert, which
      // is what every finished event looks like in a real database.
      final events = <CalendarEvent>[
        for (var i = 0; i < 40; i++)
          eventOf(
            id: 'past$i',
            startDate: DateTime.utc(2026, 9, 14).subtract(Duration(days: i)),
          ),
        eventOf(
          id: 'ended-weekly',
          startDate: DateTime.utc(2026, 1, 5),
          rule: const WeeklyRecurrence(weekdays: {1, 3, 5}),
          endDate: DateTime.utc(2026, 9, 10),
        ),
        eventOf(
          id: 'ended-daily',
          startDate: DateTime.utc(2026, 1, 1),
          rule: const DailyRecurrence(),
          endDate: DateTime.utc(2026, 9, 1),
        ),
      ];
      final plan = planOf(
        events: events,
        alerts: {
          for (final event in events)
            event.id: [alertOf('a-${event.id}', eventId: event.id)],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(plan, isEmpty);
      expect(CalendarEvent.debugOccursOnCalls, 0);
    });

    test('a rule that names its days is asked about those days only', () {
      // Mondays only, from Tuesday the 15th: the rule names four Mondays in
      // the window and the planner stops after the two it needs, so two
      // probes — not thirty.
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 7),
        rule: const WeeklyRecurrence(weekdays: {1}),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(
        plan.map((fire) => fire.day),
        [DateTime.utc(2026, 9, 21), DateTime.utc(2026, 9, 28)],
      );
      expect(CalendarEvent.debugOccursOnCalls, 2);
    });

    test('named days are taken soonest first whatever order they came in', () {
      // A rule's candidate days come back in no particular order — the agenda
      // buckets them — but `perAlert` means the *first* two occurrences, so
      // the planner has to sort before it counts.
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: SpecificDatesRecurrence(
          dates: {
            DateTime.utc(2026, 10, 5),
            DateTime.utc(2026, 9, 20),
            DateTime.utc(2026, 9, 25),
          },
        ),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(
        plan.map((fire) => fire.day),
        [DateTime.utc(2026, 9, 20), DateTime.utc(2026, 9, 25)],
      );
      expect(CalendarEvent.debugOccursOnCalls, 2);
    });

    test('a rule that cannot name its days is walked until the cap', () {
      // Daily cannot prune itself, so the walk is day by day: today's fire is
      // already behind `now`, tomorrow and the day after fill the cap, and the
      // walk stops there rather than running to the end of the window.
      final event = eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const DailyRecurrence(),
      );
      final plan = planOf(
        events: [event],
        alerts: {
          'e1': [alertOf('a1')],
        },
        now: DateTime(2026, 9, 15, 12),
      );

      expect(
        plan.map((fire) => fire.day),
        [DateTime.utc(2026, 9, 16), DateTime.utc(2026, 9, 17)],
      );
      expect(CalendarEvent.debugOccursOnCalls, 3);
    });
  });

  test('a disabled alert is kept but never planned', () {
    final event = eventOf(startDate: DateTime.utc(2026, 9, 20));
    final plan = planOf(
      events: [event],
      alerts: {
        'e1': [alertOf('a1', enabled: false), alertOf('a2')],
      },
      now: DateTime(2026, 9, 15, 12),
    );

    expect(plan.map((fire) => fire.alert.id), ['a2']);
  });

  test('an event with no alerts costs nothing', () {
    final event = eventOf(
      startDate: DateTime.utc(2026, 9, 1),
      rule: const DailyRecurrence(),
    );
    expect(
      planOf(events: [event], alerts: const {}, now: DateTime(2026, 9, 15)),
      isEmpty,
    );
  });

  group('daylight saving', () {
    // A14: floating local time. The fire instant is built with the wall-clock
    // constructor, never by adding a `Duration` to local midnight — local
    // midnight carries the *pre*-transition offset, so absolute addition lands
    // an hour off on both transition days. Asserted as wall clock so the test
    // is honest in any host timezone; in a zone with no transition on these
    // dates it is simply the ordinary case, which must also hold.
    for (final date in [
      // European spring forward and fall back.
      DateTime.utc(2026, 3, 29),
      DateTime.utc(2026, 10, 25),
      // US transitions, for a host on that side of the Atlantic.
      DateTime.utc(2026, 3, 8),
      DateTime.utc(2026, 11, 1),
    ]) {
      test('a 07:00 timed alert fires at 07:00 on ${date.toIso8601String()}',
          () {
        final event = eventOf(
          startDate: date,
          time: const EventTime(startMinute: 7 * 60),
        );
        final plan = planOf(
          events: [event],
          alerts: {
            'e1': [alertOf('a1')],
          },
          now: DateTime(date.year, date.month, date.day - 3, 12),
        );

        final fireAt = plan.single.fireAt;
        expect(fireAt.year, date.year);
        expect(fireAt.month, date.month);
        expect(fireAt.day, date.day);
        expect(fireAt.hour, 7);
        expect(fireAt.minute, 0);
        expect(
          fireAt,
          DateTime(date.year, date.month, date.day, 0, 7 * 60),
          reason:
              'the fire instant must be the wall-clock constructor, so a time '
              'inside a spring gap rolls forward and a fall-back day does not '
              'slide an hour early',
        );
      });

      test('an all-day 09:00 alert fires at 09:00 on '
          '${date.toIso8601String()}', () {
        final event = eventOf(startDate: date, time: null);
        final plan = planOf(
          events: [event],
          alerts: {
            'e1': [alertOf('a1')],
          },
          now: DateTime(date.year, date.month, date.day - 3, 12),
        );

        expect(plan.single.fireAt.day, date.day);
        expect(plan.single.fireAt.hour, 9);
        expect(plan.single.fireAt.minute, 0);
      });
    }
  });
}
