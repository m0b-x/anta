import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';

/// `createdAt` is storage metadata the lead-time measure reads; it rides
/// every copy of the event and never takes part in equality, so a draft and
/// its stored copy still compare equal.
void main() {
  final created = DateTime.utc(2026, 10, 2, 8, 15);

  CalendarEvent event({DateTime? createdAt}) => CalendarEvent(
    id: 'e1',
    title: 'Dentist',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 11, 4),
    createdAt: createdAt,
  );

  test('defaults to null', () {
    expect(event().createdAt, isNull);
  });

  test('copyWith carries it through every change', () {
    final stored = event(createdAt: created);
    expect(stored.copyWith(title: 'Dentist again').createdAt, created);
    expect(
      stored.copyWith(rule: const WeeklyRecurrence(weekdays: {1})).createdAt,
      created,
    );
    expect(stored.copyWith(clearTime: true).createdAt, created);
    expect(
      stored.withExplicitDates({DateTime.utc(2026, 11, 5)}).createdAt,
      created,
    );
    final later = DateTime.utc(2026, 10, 3);
    expect(stored.copyWith(createdAt: later).createdAt, later);
  });

  test('two events differing only in createdAt are equal', () {
    final draft = event();
    final stored = event(createdAt: created);
    expect(stored, draft);
    expect(stored.hashCode, draft.hashCode);
    expect(event(createdAt: DateTime.utc(2020)), stored);
  });
}
