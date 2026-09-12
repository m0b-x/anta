import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';

/// The v37 presence default in its two halves: what an event says about an
/// unmarked day (`CalendarEvent.assumesAbsentOn`), and how that loses to an
/// explicit mark (`EventPresence.isMissed`).
///
/// Before v37 the absence of a row *was* the answer, so there was only one
/// reading to get wrong. Now there are two and they are ordered — a mark
/// always wins — which is the property every surface depends on and none of
/// them would reveal breaking: a wrong precedence shows up as the grid
/// quietly disagreeing with the day panel about a day the user confirmed.
///
/// Neither half may read the wall clock. An unconfirmed *future* day of an
/// assume-absent event reads missed exactly like a past one, which is what
/// keeps every read path free of a clock and of a midnight rollover.
void main() {
  final day = DateTime.utc(2026, 8, 12);
  final before = DateTime.utc(2026, 8, 11);
  final after = DateTime.utc(2026, 8, 13);

  CalendarEvent event({
    bool assumeAbsent = false,
    DateTime? assumeAbsentFrom,
    String id = 'e1',
  }) {
    return CalendarEvent(
      id: id,
      title: 'Leg day',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 1, 1),
      rule: const DailyRecurrence(),
      tracksPresence: true,
      assumeAbsent: assumeAbsent,
      assumeAbsentFrom: assumeAbsentFrom,
    );
  }

  void mark(DateTime on, PresenceStatus status, {String id = 'e1'}) {
    EventPresence.updateCache(
      byEvent: {
        id: {on: status},
      },
    );
  }

  setUp(EventPresence.resetCache);
  tearDown(EventPresence.resetCache);

  group('assumesAbsentOn', () {
    test('an assume-present event never claims a day', () {
      final subject = event();

      expect(subject.assumesAbsentOn(before), isFalse);
      expect(subject.assumesAbsentOn(day), isFalse);
      expect(subject.assumesAbsentOn(after), isFalse);
    });

    test('the flag with no boundary covers the whole event', () {
      final subject = event(assumeAbsent: true);

      expect(subject.assumesAbsentOn(before), isTrue);
      expect(subject.assumesAbsentOn(day), isTrue);
      expect(subject.assumesAbsentOn(after), isTrue);
    });

    test('a boundary is inclusive of its own day', () {
      final subject = event(assumeAbsent: true, assumeAbsentFrom: day);

      // The day the user flipped the event over is the first day that reads
      // missed, not the day after it — the editor seeds the tile with the
      // occurrence the sheet was opened from, and that occurrence is the one
      // they meant.
      expect(subject.assumesAbsentOn(day), isTrue);
    });

    test('days before the boundary keep their old meaning', () {
      final subject = event(assumeAbsent: true, assumeAbsentFrom: day);

      // The entire reason the column exists: flipping an existing event must
      // not rewrite the history it already has.
      expect(subject.assumesAbsentOn(before), isFalse);
      expect(subject.assumesAbsentOn(after), isTrue);
    });

    test('a boundary is ignored while the flag is off', () {
      final subject = event(assumeAbsentFrom: day);

      expect(subject.assumesAbsentOn(day), isFalse);
      expect(subject.assumesAbsentOn(after), isFalse);
    });

    test('a boundary carrying a time component still compares by date', () {
      // `CalendarEventService` normalizes on read, but the model is handed
      // draft events straight from the editor too — a stray wall-clock
      // component must not push the boundary a day forward.
      final subject = event(
        assumeAbsent: true,
        assumeAbsentFrom: DateTime.utc(2026, 8, 12, 21, 30),
      );

      expect(subject.assumeAbsentFromUtc, day);
      expect(subject.assumesAbsentOn(day), isTrue);
      expect(subject.assumesAbsentOn(before), isFalse);
    });

    test('both fields are in props, so an edit is a new value', () {
      // The bloc emits `Equatable` state and the grid compares `allEvents` by
      // identity behind it — a field outside `props` would make flipping the
      // default a silent no-op all the way to the screen.
      expect(event(), isNot(event(assumeAbsent: true)));
      expect(
        event(assumeAbsent: true),
        isNot(event(assumeAbsent: true, assumeAbsentFrom: day)),
      );
    });
  });

  group('isMissed precedence', () {
    test('with no mark the event default is the whole answer', () {
      expect(EventPresence.isMissed(event(), day), isFalse);
      expect(EventPresence.isMissed(event(assumeAbsent: true), day), isTrue);
    });

    test('an explicit present beats an assume-absent default', () {
      mark(day, PresenceStatus.present);
      final subject = event(assumeAbsent: true);

      expect(EventPresence.isMissed(subject, day), isFalse);
      // One day only: the mark is a statement about that occurrence, never
      // about the event.
      expect(EventPresence.isMissed(subject, after), isTrue);
    });

    test('an explicit missed beats an assume-present default', () {
      mark(day, PresenceStatus.missed);
      final subject = event();

      expect(EventPresence.isMissed(subject, day), isTrue);
      expect(EventPresence.isMissed(subject, after), isFalse);
    });

    test('a mark before the boundary still wins', () {
      mark(before, PresenceStatus.missed);
      final subject = event(assumeAbsent: true, assumeAbsentFrom: day);

      // Converting an event never rewrites mark rows, so the ones on the
      // assume-present side of the boundary keep meaning exactly what they
      // meant when they were written.
      expect(EventPresence.isMissed(subject, before), isTrue);
    });

    test('marks are keyed per event, not shared across them', () {
      mark(day, PresenceStatus.present, id: 'e1');

      expect(
        EventPresence.isMissed(event(assumeAbsent: true, id: 'e2'), day),
        isTrue,
      );
    });

    test('an unconfirmed future day reads missed like a past one', () {
      final subject = event(assumeAbsent: true);
      final farFuture = DateTime.utc(2099, 1, 1);

      expect(EventPresence.isMissed(subject, farFuture), isTrue);
    });

    test('a raw local day is rejected in debug', () {
      // The date-only-UTC contract is what makes the map probe O(1) and
      // allocation-free; a caller handing over a wall-clock DateTime would
      // silently miss every mark instead.
      expect(
        () => EventPresence.isMissed(event(), DateTime(2026, 8, 12)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('PresenceStatus.fromName', () {
    test('round-trips the two names', () {
      expect(PresenceStatus.fromName('missed'), PresenceStatus.missed);
      expect(PresenceStatus.fromName('present'), PresenceStatus.present);
    });

    test('never throws on anything else', () {
      // A startup `_load` that threw here would silently clear every mark in
      // the database, and an archive written by a newer build is exactly the
      // input that would do it.
      expect(PresenceStatus.fromName(null), PresenceStatus.missed);
      expect(PresenceStatus.fromName(''), PresenceStatus.missed);
      expect(PresenceStatus.fromName('partial'), PresenceStatus.missed);
      expect(PresenceStatus.fromName('MISSED'), PresenceStatus.missed);
    });
  });
}
