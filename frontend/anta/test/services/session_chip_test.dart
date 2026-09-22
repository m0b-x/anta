import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/session_chip.dart';

import '../database/support/db_test_support.dart';

/// The chip is posted from two places for the same ring, must never be posted
/// for a reminder, and has to come down on its own — the three things worth
/// pinning at the coordinator, where the binding only draws what it is handed.
void main() {
  final day = DateTime.utc(2026, 9, 20);

  AlertPayload payloadOf({
    int osId = 7,
    AlertMode mode = AlertMode.ring,
    String database = 'gym_notes',
    String eventId = 'e1',
  }) => AlertPayload(
    database: database,
    eventId: eventId,
    alertId: 'a$osId',
    dayUtcMs: day.millisecondsSinceEpoch,
    osId: osId,
    mode: mode,
    title: 'Leg day',
    timeLabel: '18:00',
    categoryId: 'gym',
  );

  CalendarEvent eventOf({int? durationMinutes = 90, String id = 'e1'}) =>
      CalendarEvent(
        id: id,
        title: 'Leg day',
        categoryId: 'gym',
        startDate: day,
        rule: const OneTimeRecurrence(),
        time: EventTime(startMinute: 18 * 60, durationMinutes: durationMinutes),
      );

  late _ChipGateway gateway;
  late SessionChip chip;
  late DateTime now;
  CalendarEvent? event;

  setUp(() {
    gateway = _ChipGateway();
    chip = SessionChip();
    now = DateTime(2026, 9, 20, 18, 0, 30);
    event = eventOf();
    chip.configureForTesting(
      gateway: () => gateway,
      activeDatabase: () async => 'gym_notes',
      findEvent: (id) async => event?.id == id ? event : null,
      clock: () => now,
    );
  });

  tearDown(() => chip.resetForTesting());

  group('sessionProgress', () {
    final start = DateTime(2026, 9, 20, 18);
    test('is indeterminate with no end, and clamped at both ends', () {
      expect(sessionProgress(startedAt: start, endsAt: null, now: start), isNull);
      final end = start.add(const Duration(minutes: 90));
      expect(sessionProgress(startedAt: start, endsAt: end, now: start), 0);
      expect(
        sessionProgress(
          startedAt: start,
          endsAt: end,
          now: start.add(const Duration(minutes: 45)),
        ),
        50,
      );
      expect(
        sessionProgress(
          startedAt: start,
          endsAt: end,
          now: end.add(const Duration(minutes: 5)),
        ),
        100,
      );
      expect(
        sessionProgress(
          startedAt: start,
          endsAt: end,
          now: start.subtract(const Duration(minutes: 5)),
        ),
        0,
      );
      // An end at or before the start is a session that is over.
      expect(sessionProgress(startedAt: start, endsAt: start, now: start), 100);
    });
  });

  group('sessionEndFor', () {
    test('is the day plus the end minute in local time, or nothing', () {
      expect(sessionEndFor(eventOf(), day), DateTime(2026, 9, 20, 19, 30));
      expect(sessionEndFor(eventOf(durationMinutes: null), day), isNull);
      expect(
        sessionEndFor(eventOf().copyWith(clearTime: true), day),
        isNull,
      );
    });

    test('is wall-clock time on the day the clocks change', () {
      // The last Sunday of October is a 25-hour day in every European zone:
      // an end computed by adding a Duration to midnight lands an hour early
      // there, the constructor form never does. Both sides below use the
      // constructor, so the assertion holds in any zone and catches the
      // Duration form wherever the day is not 24 hours long.
      final switchDay = DateTime.utc(2026, 10, 25);
      expect(
        sessionEndFor(eventOf(), switchDay),
        DateTime(2026, 10, 25, 0, 19 * 60 + 30),
      );
    });
  });

  group('linkedSessionNote', () {
    test('finds the linked note with its metadata, and never a tombstone',
        () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final notes = NoteRepository(database: db);
      final note = await notes.createNote(
        folderId: 'f1',
        title: 'Session 1',
        content: '# Session 1',
        preview: '# Session 1',
        contentLength: 11,
        chunkCount: 1,
        isCompressed: false,
      );
      final event = eventOf().copyWith(noteId: note.id);

      final linked = await linkedSessionNote(event, notes);
      expect(linked?.noteId, note.id);
      expect(linked?.folderId, 'f1');
      expect(linked?.metadata.title, 'Session 1');

      await notes.deleteNote(note.id);
      expect(await linkedSessionNote(event, notes), isNull);

      expect(await linkedSessionNote(eventOf(), notes), isNull);
      expect(await linkedSessionNote(null, notes), isNull);
    });
  });

  test('a stopped alarm posts one chip, with the event\'s end', () async {
    await chip.show(payloadOf());

    expect(gateway.shown, hasLength(1));
    final shown = gateway.shown.single;
    expect(shown.payload.osId, 7);
    expect(shown.startedAt, now);
    expect(shown.endsAt, DateTime(2026, 9, 20, 19, 30));
    expect(shown.progress, 0);
    expect(shown.refresh, isFalse);
    expect(chip.shownOsId, 7);
  });

  test('a first post the platform refuses leaves nothing to keep alive', () {
    fakeAsync((async) {
      gateway.standing = false;
      chip.show(payloadOf());
      async.flushMicrotasks();

      expect(gateway.shown, hasLength(1));
      expect(chip.shownOsId, isNull);
      async.elapse(const Duration(minutes: 5));
      expect(gateway.shown, hasLength(1));
    });
  });

  test('a Done on the shade ends the refresh: the refused re-post drops the '
      'timers and the state', () {
    fakeAsync((async) {
      chip.show(payloadOf());
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 2));
      expect(gateway.shown, hasLength(3));
      expect(gateway.shown.last.refresh, isTrue);

      // The receiver took the chip down with no Dart running; the platform
      // answers the next refresh with "not standing".
      gateway.standing = false;
      async.elapse(const Duration(minutes: 1));
      expect(gateway.shown, hasLength(4));
      expect(chip.shownOsId, isNull);

      // No more refreshes, and the end timer is gone with them.
      gateway.standing = true;
      async.elapse(const Duration(hours: 2));
      expect(gateway.shown, hasLength(4));
      expect(gateway.cleared, 0);
    });
  });

  test('an event with no end posts an indeterminate chip', () async {
    event = eventOf(durationMinutes: null);

    await chip.show(payloadOf());

    expect(gateway.shown.single.endsAt, isNull);
    expect(gateway.shown.single.progress, isNull);
  });

  test('a reminder, a test alarm and another database\'s alarm post nothing',
      () async {
    await chip.show(payloadOf(mode: AlertMode.notify));
    await chip.show(
      payloadOf(eventId: AlertPayload.testEventId, database: 'gym_notes'),
    );
    await chip.show(payloadOf(database: 'work'));

    expect(gateway.shown, isEmpty);
    expect(chip.shownOsId, isNull);
  });

  test('two routes acknowledging the same ring post one chip between them',
      () async {
    // Both arrive before either has resolved the database — the shape a
    // Stop on the platform's notification produces, when `main.dart` settles
    // the ring end alongside it.
    await Future.wait([chip.show(payloadOf()), chip.show(payloadOf())]);
    await chip.show(payloadOf());

    expect(gateway.shown, hasLength(1));
  });

  test('a session already over posts nothing', () async {
    now = DateTime(2026, 9, 20, 19, 31);

    await chip.show(payloadOf());

    expect(gateway.shown, isEmpty);
    expect(chip.shownOsId, isNull);
  });

  test('an event that is gone still gets its chip, with no end', () async {
    event = null;

    await chip.show(payloadOf());

    expect(gateway.shown.single.endsAt, isNull);
  });

  test('the chip is refreshed each minute and cleared at the end', () {
    fakeAsync((async) {
      chip.show(payloadOf());
      async.flushMicrotasks();
      expect(gateway.shown, hasLength(1));

      now = now.add(const Duration(minutes: 45));
      async.elapse(const Duration(minutes: 45));
      expect(gateway.shown.length, greaterThanOrEqualTo(45));
      expect(gateway.shown.last.progress, 50);
      expect(gateway.cleared, 0);

      now = DateTime(2026, 9, 20, 19, 31);
      async.elapse(const Duration(minutes: 45));
      expect(gateway.cleared, 1);
      expect(chip.shownOsId, isNull);
      final posts = gateway.shown.length;
      async.elapse(const Duration(minutes: 5));
      expect(gateway.shown.length, posts);
    });
  });

  test('a clear always reaches the platform, even with nothing remembered',
      () async {
    await chip.clear();

    expect(gateway.cleared, 1);
  });

  test('a new ring\'s chip replaces the old one', () async {
    await chip.show(payloadOf(osId: 7));
    await chip.clear();
    await chip.show(payloadOf(osId: 8));

    expect(gateway.shown, hasLength(2));
    expect(chip.shownOsId, 8);
  });

  test('no gateway means no chip and no error', () async {
    chip.configureForTesting(
      gateway: () => null,
      activeDatabase: () async => 'gym_notes',
      findEvent: (_) async => event,
      clock: () => now,
    );

    await chip.show(payloadOf());
    await chip.clear();

    expect(chip.shownOsId, isNull);
  });
}

typedef _Shown = ({
  AlertPayload payload,
  DateTime startedAt,
  DateTime? endsAt,
  int? progress,
  bool refresh,
});

class _ChipGateway extends NoOpAlertGateway {
  final List<_Shown> shown = [];
  int cleared = 0;

  /// What the "platform" answers: whether the chip stands after the post.
  bool standing = true;

  @override
  Future<bool> showSessionChip(
    AlertPayload payload, {
    required DateTime startedAt,
    DateTime? endsAt,
    int? progress,
    bool refresh = false,
  }) async {
    shown.add((
      payload: payload,
      startedAt: startedAt,
      endsAt: endsAt,
      progress: progress,
      refresh: refresh,
    ));
    return standing;
  }

  @override
  Future<void> clearSessionChip() async {
    cleared++;
  }
}
