import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';

/// A store of every shape the window index narrows over: one-time events
/// every few days across five years, on month and year edges, on the 29th of
/// February and on the European and American DST days, one clamped away by
/// its own end date; and the recurring shapes — dense, sparse, retroactive,
/// specific dates before their start, end dates on a month's last day. In
/// start-date order, as the store keeps it, with the recurring events
/// interleaved by their starts.
List<CalendarEvent> seededWindowStore() {
  const categories = ['gym', 'work', 'birthday', 'other'];
  final events = <CalendarEvent>[];
  var n = 0;
  CalendarEvent event(
    DateTime start, {
    RecurrenceRule rule = const OneTimeRecurrence(),
    DateTime? endDate,
    bool retroactive = false,
    bool timed = false,
  }) {
    final i = n++;
    return CalendarEvent(
      id: 'e${i.toString().padLeft(4, '0')}',
      title: 'Event $i',
      categoryId: categories[i % categories.length],
      startDate: start,
      rule: rule,
      endDate: endDate,
      retroactive: retroactive,
      tracksPresence: i % 7 == 0,
      assumeAbsent: i % 14 == 0,
      priority: 1 + i % 5,
      time: timed ? EventTime(startMinute: (i * 37) % 1440) : null,
    );
  }

  for (
    var day = DateTime.utc(2024, 1, 1);
    day.isBefore(DateTime.utc(2029, 1, 1));
    day = day.add(const Duration(days: 3))
  ) {
    events.add(event(day, timed: day.day.isEven));
  }
  for (final edge in [
    DateTime.utc(2025, 12, 31),
    DateTime.utc(2026, 1, 1),
    DateTime.utc(2026, 1, 31),
    DateTime.utc(2026, 2, 1),
    DateTime.utc(2026, 2, 28),
    DateTime.utc(2026, 3, 1),
    DateTime.utc(2026, 3, 8),
    DateTime.utc(2026, 3, 29),
    DateTime.utc(2026, 10, 25),
    DateTime.utc(2026, 11, 1),
    DateTime.utc(2026, 12, 31),
    DateTime.utc(2027, 1, 1),
    DateTime.utc(2028, 2, 29),
  ]) {
    events.add(event(edge));
    events.add(event(edge, timed: true));
  }
  events.add(
    event(DateTime.utc(2026, 6, 15), endDate: DateTime.utc(2026, 6, 14)),
  );
  events.addAll([
    event(DateTime.utc(2025, 1, 1), rule: const DailyRecurrence()),
    event(DateTime.utc(2025, 6, 3), rule: const DailyRecurrence(interval: 3)),
    event(
      DateTime.utc(2026, 1, 5),
      rule: const WeeklyRecurrence(
        weekdays: {DateTime.monday, DateTime.thursday},
      ),
      timed: true,
    ),
    event(
      DateTime.utc(2027, 3, 1),
      rule: const WeeklyRecurrence(weekdays: {DateTime.sunday}),
      retroactive: true,
    ),
    event(DateTime.utc(2024, 1, 31), rule: const MonthlyRecurrence()),
    event(
      DateTime.utc(2025, 5, 15),
      rule: const MonthlyRecurrence(interval: 2),
      endDate: DateTime.utc(2026, 8, 31),
    ),
    event(DateTime.utc(2024, 2, 29), rule: const YearlyRecurrence()),
    event(DateTime.utc(2020, 10, 25), rule: const YearlyRecurrence()),
    event(
      DateTime.utc(2026, 4, 1),
      rule: SpecificDatesRecurrence(
        dates: {
          DateTime.utc(2025, 12, 31),
          DateTime.utc(2026, 3, 29),
          DateTime.utc(2026, 4, 1),
          DateTime.utc(2027, 1, 1),
        },
      ),
    ),
    event(DateTime.utc(2026, 1, 1), rule: const WeekendsRecurrence()),
    event(
      DateTime.utc(2026, 2, 2),
      rule: const WorkdaysRecurrence(),
      endDate: DateTime.utc(2026, 4, 30),
    ),
  ]);
  events.sort((a, b) => a.startDate.compareTo(b.startDate));
  return List.unmodifiable(events);
}

/// Windows over [seededWindowStore]: every month of 2026, its whole year,
/// spans across a year's and a leap February's edges, the DST days alone,
/// one day with no one-time event, and a span longer than a scan allows.
final List<(DateTime, DateTime)> seededWindows = [
  for (var month = 1; month <= 12; month++)
    (DateTime.utc(2026, month), DateTime.utc(2026, month + 1, 0)),
  (DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31)),
  (DateTime.utc(2025, 12, 15), DateTime.utc(2026, 1, 15)),
  (DateTime.utc(2028, 2, 28), DateTime.utc(2028, 3, 1)),
  (DateTime.utc(2026, 3, 29), DateTime.utc(2026, 3, 29)),
  (DateTime.utc(2026, 10, 25), DateTime.utc(2026, 11, 1)),
  (DateTime.utc(2030, 6, 1), DateTime.utc(2030, 6, 1)),
  (DateTime.utc(2023, 7, 1), DateTime.utc(2029, 7, 1)),
];
