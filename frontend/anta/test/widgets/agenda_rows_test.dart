import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/agenda_list_view.dart';

/// `buildAgendaRows` is the single place the agenda decides what exists: the
/// list draws these rows and the panel header counts them. So the property
/// worth pinning is not "hidden mode dims something" but that **the count and
/// the rows come out of the same pass** — the bug that made the header promise
/// entries the list had already dropped.
///
/// Driven directly against `AppLocalizationsEn()`, with no widget tree: the
/// function is pure given the static presence/description facades, which is
/// exactly what makes it testable this way.
void main() {
  final l10n = AppLocalizationsEn();

  final day1 = DateTime.utc(2026, 8, 10);
  final day2 = DateTime.utc(2026, 8, 11);

  /// New Year resolves through the uninitialized fixed-date fallback, so a
  /// holiday day needs no profile configured here.
  final holiday = DateTime.utc(2026, 1, 1);

  /// Tracked, so its occurrences can be marked missed.
  final tracked = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
    tracksPresence: true,
  );

  /// Untracked: never droppable, so it proves hiding narrows to the marks.
  final untracked = CalendarEvent(
    id: 'e2',
    title: 'Mobility',
    categoryId: 'mobility',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
  );

  List<AgendaRow> build({
    List<EventOccurrence> occurrences = const [],
    List<DateTime> holidayDays = const [],
    CalendarMissedDisplay missedDisplay = CalendarMissedDisplay.faded,
  }) {
    return buildAgendaRows(
      occurrences: occurrences,
      holidayDays: holidayDays,
      l10n: l10n,
      showRecurrenceLabels: true,
      missedDisplay: missedDisplay,
    );
  }

  /// Day 1 carries both events, day 2 only the tracked one — which is marked
  /// missed, so hiding empties that day completely.
  final occurrences = [
    EventOccurrence(event: tracked, day: day1),
    EventOccurrence(event: untracked, day: day1),
    EventOccurrence(event: tracked, day: day2),
  ];

  setUp(() {
    EventPresence.updateCache(
      byEvent: {
        'e1': {day2},
      },
    );
  });

  // The facade is process-wide static state; leaving a mark behind would
  // silently change what a later test — in any file — renders.
  tearDown(EventPresence.resetCache);

  test('hidden mode drops a missed entry and the header it emptied', () {
    final rows = build(
      occurrences: occurrences,
      missedDisplay: CalendarMissedDisplay.hidden,
    );

    expect(rows.whereType<AgendaDayHeaderRow>().map((r) => r.day), [day1]);
    expect(rows.whereType<AgendaEntryRow>().map((r) => r.entry.title), [
      'Leg day',
      'Mobility',
    ]);
  });

  test('faded mode keeps the missed entry and its day', () {
    final rows = build(occurrences: occurrences);

    expect(rows.whereType<AgendaDayHeaderRow>().map((r) => r.day), [
      day1,
      day2,
    ]);
    final missed = rows.whereType<AgendaEntryRow>().where((r) => r.day == day2);
    expect(missed.single.entry.title, 'Leg day');
    expect(missed.single.entry.missed, isTrue);
  });

  test('every header count equals the entry rows that follow it', () {
    for (final display in CalendarMissedDisplay.values) {
      final rows = build(
        occurrences: occurrences,
        holidayDays: [holiday],
        missedDisplay: display,
      );

      final perDay = <DateTime, int>{};
      for (final row in rows.whereType<AgendaEntryRow>()) {
        perDay.update(row.day, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final header in rows.whereType<AgendaDayHeaderRow>()) {
        expect(header.count, perDay[header.day], reason: display.name);
      }
      // The panel header's number: totalling the per-day counts and counting
      // the rows must be the same arithmetic, or the two disagree again.
      expect(
        rows.whereType<AgendaEntryRow>().length,
        rows.whereType<AgendaDayHeaderRow>().fold<int>(
          0,
          (sum, header) => sum + header.count,
        ),
        reason: display.name,
      );
    }
  });

  test('a holiday day with no events still produces an entry row', () {
    expect(PublicHolidays.isHoliday(holiday), isTrue);

    final rows = build(holidayDays: [holiday]);

    expect(rows.whereType<AgendaDayHeaderRow>().single.count, 1);
    final entry = rows.whereType<AgendaEntryRow>().single;
    expect(entry.day, holiday);
    expect(entry.entry.title, l10n.publicHolidayNewYear);
    // No event behind it, which is what strips the row's edit/note actions.
    expect(entry.entry.event, isNull);
  });

  test('a holiday shares its day with the events, after them', () {
    final rows = build(
      occurrences: [EventOccurrence(event: untracked, day: holiday)],
      holidayDays: [holiday],
    );

    expect(rows.whereType<AgendaDayHeaderRow>().single.count, 2);
    expect(rows.whereType<AgendaEntryRow>().map((r) => r.entry.key), [
      'event:e2',
      'holiday',
    ]);
  });
}
