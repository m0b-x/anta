@Tags(['benchmark'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/event_window_index.dart';
import 'package:anta/utils/event_agenda.dart';

/// The window index at the scalability record's volume (§5.6, S13): 20,000
/// events, about 95% one-time over twenty years, the rest routines. A year
/// run and a picker month, through the index and over the whole store
/// ([EventWindowIndex.debugFullScan]); the numbers are printed for reading,
/// and the bound is loose on purpose — the default suite pins the work in
/// calls (`event_window_index_test.dart`). Run it deliberately:
///
/// ```powershell
/// flutter test test/services/event_window_index_benchmark_test.dart --tags benchmark --run-skipped
/// ```
void main() {
  const total = 20000;
  const routines = 1000;
  final events = List<CalendarEvent>.unmodifiable([
    for (var i = 0; i < total; i++)
      CalendarEvent(
        id: 'e$i',
        title: 'Event $i',
        categoryId: i.isEven ? 'gym' : 'work',
        startDate: DateTime.utc(2010, 1, 1 + (i * 7305) ~/ total),
        rule: i % (total ~/ routines) == 0
            ? const WeeklyRecurrence(weekdays: {DateTime.tuesday})
            : const OneTimeRecurrence(),
      ),
  ]);

  tearDown(() => EventWindowIndex.debugFullScan = false);

  int microsOf(void Function() run, {required bool full}) {
    EventWindowIndex.debugFullScan = full;
    run();
    final watch = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      run();
    }
    EventWindowIndex.debugFullScan = false;
    return watch.elapsedMicroseconds ~/ 5;
  }

  test('a year run and a picker month, indexed and full', () {
    void year() => EventAgenda.occurrencesInRange(
      events: events,
      from: DateTime.utc(2026),
      to: DateTime.utc(2026, 12, 31),
    );
    void month() {
      for (var d = 0; d < 42; d++) {
        final day = DateTime.utc(2018, 5, 28 + d);
        for (final e in EventWindowIndex.of(
          events,
        ).eventsPossiblyIn(day, day)) {
          e.occursOnUtcDay(day);
        }
      }
    }

    final yearIndexed = microsOf(year, full: false);
    final yearFull = microsOf(year, full: true);
    final monthIndexed = microsOf(month, full: false);
    final monthFull = microsOf(month, full: true);
    debugPrint('\n=== Window index, $total events ($routines routines) ===');
    debugPrint('year run:     ${yearIndexed}us indexed, ${yearFull}us full');
    debugPrint('picker month: ${monthIndexed}us indexed, ${monthFull}us full');
    expect(yearIndexed, lessThan(yearFull * 2));
    expect(monthIndexed, lessThan(monthFull));
  });
}
