import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/alert_skip_action.dart';
import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/utils/quick_alarm.dart';

import '../database/support/db_test_support.dart';

/// Every handler that changes what the phone should do about an event has to
/// say so **exactly once**, with the right id.
///
/// Once, because reconcile is a full pass over the horizon and a second call
/// is pure cost; with the right id, because the delete handler's event is gone
/// by the time it runs and the skip handlers never hold an event at all — the
/// three places the id is easiest to get wrong.
///
/// The bloc takes the reconciler as a seam, so none of this needs a scheduler,
/// a gateway or a registry: the bloc's entire responsibility is knowing *that*
/// alerts must be reconciled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late CalendarBloc bloc;
  late List<({String eventId, AlertReconcileReason reason})> calls;
  late List<({String eventId, List<EventAlert> alerts, Set<String>? knownIds})>
  writes;

  /// The whole-horizon seam a digest's write reconciles through (D22).
  late List<AlertReconcileReason> fullCalls;

  /// What the bloc's digest events write through; set by the digest group.
  DigestWriter? digestWriter;

  /// Both seams appending to one list, so "the rows are written **before** the
  /// platform is asked to plan from them" is a property the suite can state
  /// rather than one the reader has to trust.
  late List<String> order;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_alerts');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    CalendarEventService.reset();
    EventSkipService.reset();
    db = await openTestDatabase();
    await EventSkipService.forTesting(db);
    calls = [];
    writes = [];
    fullCalls = [];
    order = [];
    bloc = CalendarBloc(
      service: CalendarEventService.forTesting(db),
      alertReconciler: (eventId, reason) async {
        calls.add((eventId: eventId, reason: reason));
        order.add('reconcile');
      },
      alertWriter: (eventId, alerts, {knownIds}) async {
        writes.add((eventId: eventId, alerts: alerts, knownIds: knownIds));
        order.add('write');
      },
      allAlertsReconciler: (reason) async => fullCalls.add(reason),
      // Handed over, never resolved: no test reaches the service singleton.
      digestWriter: () async => digestWriter!,
    );
  });

  tearDown(() async {
    await bloc.close();
    CalendarEventService.reset();
    EventSkipService.reset();
    await db.close();
  });

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  CalendarEvent eventOf({
    String id = 'e1',
    String title = 'Leg day',
    RecurrenceRule rule = const OneTimeRecurrence(),
  }) => CalendarEvent(
    id: id,
    title: title,
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 20),
    rule: rule,
    time: const EventTime(startMinute: 18 * 60),
  );

  group('a quick alarm (Session 6)', () {
    test('creates exactly one event with one alert, reconciled once', () async {
      await dispatch(const LoadCalendarEvents());
      calls.clear();
      writes.clear();
      order.clear();
      final draft = QuickAlarmDraft(
        day: DateTime.utc(2026, 9, 23),
        startMinute: 7 * 60,
        name: 'Alarm',
      );
      final event = buildQuickAlarmEvent(draft, id: 'q1');
      final alert = buildQuickAlarmAlert(draft, eventId: 'q1', id: 'qa1');

      await dispatch(CreateCalendarEvent(event: event, alerts: [alert]));

      final service = await CalendarEventService.getInstance();
      final stored = service.events.where((e) => e.id == 'q1').toList();
      expect(stored, hasLength(1));
      expect(stored.single.removeAfterAlert, isTrue);
      expect(stored.single.iconKey, 'alarm');
      expect(stored.single.time?.startMinute, 7 * 60);
      expect(writes, hasLength(1));
      expect(writes.single.eventId, 'q1');
      expect(writes.single.alerts, hasLength(1));
      expect(writes.single.alerts.single.mode, AlertMode.ring);
      expect(writes.single.alerts.single.offsetMinutes, 0);
      expect(calls, hasLength(1));
      expect(calls.single.eventId, 'q1');
      expect(calls.single.reason, AlertReconcileReason.eventChanged);
      expect(order, ['write', 'reconcile']);
    });

    test('Undo is the delete, which reconciles the event once more', () async {
      await dispatch(const LoadCalendarEvents());
      final draft = QuickAlarmDraft(
        day: DateTime.utc(2026, 9, 23),
        startMinute: 7 * 60,
        name: 'Alarm',
      );
      await dispatch(
        CreateCalendarEvent(
          event: buildQuickAlarmEvent(draft, id: 'q2'),
          alerts: [buildQuickAlarmAlert(draft, eventId: 'q2', id: 'qa2')],
        ),
      );
      calls.clear();

      await dispatch(const DeleteCalendarEvent(eventId: 'q2'));

      final service = await CalendarEventService.getInstance();
      expect(service.events.where((e) => e.id == 'q2'), isEmpty);
      expect(calls, hasLength(1));
      expect(calls.single.eventId, 'q2');
    });
  });

  group("an upcoming notice's Skip (OS-3)", () {
    tearDown(EventAlerts.resetCache);

    AlertPayload payloadFor(CalendarEvent event, DateTime day) => AlertPayload(
      database: 'gym_notes',
      eventId: event.id,
      alertId: 'a1',
      dayUtcMs: day.millisecondsSinceEpoch,
      osId: 7,
      mode: AlertMode.ring,
      title: event.title,
      timeLabel: '18:00',
      categoryId: 'gym',
    );

    EventAlert alarmOf(CalendarEvent event) =>
        EventAlert(id: 'a1', eventId: event.id, mode: AlertMode.ring);

    test(
      'cancels one occurrence of a recurring event, and Undo restores it',
      () async {
        await dispatch(const LoadCalendarEvents());
        final event = eventOf(rule: const DailyRecurrence());
        final alert = alarmOf(event);
        await dispatch(CreateCalendarEvent(event: event, alerts: [alert]));
        EventAlerts.updateCache(
          byEvent: {
            event.id: [alert],
          },
        );
        calls.clear();
        writes.clear();
        final day = DateTime.utc(2026, 9, 22);
        final action = AlertSkipAction.resolve(
          event: event,
          payload: payloadFor(event, day),
          today: DateTime.utc(2026, 9, 22),
        )!;
        expect(action.apply, isA<SetOccurrenceSkipped>());

        await dispatch(action.apply);

        expect(EventSkips.isSkipped(event.id, day), isTrue);
        expect(
          EventSkips.isSkipped(event.id, DateTime.utc(2026, 9, 23)),
          isFalse,
        );
        // Exactly one reconcile, for this event: that is what takes the
        // alarm off the platform.
        expect(calls, hasLength(1));
        expect(calls.single.eventId, event.id);
        expect(writes, isEmpty);

        await dispatch(action.undo);
        expect(EventSkips.isSkipped(event.id, day), isFalse);
        expect(calls, hasLength(2));
      },
    );

    test(
      'switches a one-time event\'s alert off, and Undo switches it on',
      () async {
        await dispatch(const LoadCalendarEvents());
        final event = eventOf();
        final alert = EventAlert(
          id: 'a1',
          eventId: event.id,
          mode: AlertMode.ring,
        );
        await dispatch(CreateCalendarEvent(event: event, alerts: [alert]));
        EventAlerts.updateCache(
          byEvent: {
            event.id: [alert],
          },
        );
        calls.clear();
        writes.clear();
        final action = AlertSkipAction.resolve(
          event: event,
          payload: payloadFor(event, DateTime.utc(2026, 9, 20)),
          today: DateTime.utc(2026, 9, 19),
        )!;
        expect(action.apply, isA<ToggleEventAlert>());

        await dispatch(action.apply);

        expect(writes, hasLength(1));
        expect(writes.single.alerts.single.enabled, isFalse);
        expect(calls, hasLength(1));
        // A one-time event cannot be skipped — a cancelled occurrence of one
        // would be a deletion — so nothing reached the skip table.
        expect(
          EventSkips.isSkipped(event.id, DateTime.utc(2026, 9, 20)),
          isFalse,
        );

        EventAlerts.updateCache(
          byEvent: {
            event.id: [alert.copyWith(enabled: false)],
          },
        );
        await dispatch(action.undo);
        expect(writes, hasLength(2));
        expect(writes.last.alerts.single.enabled, isTrue);
      },
    );

    test("opts a one-time event out of its category's alerts for an "
        'inherited alarm, and Undo opts it back in (v42)', () async {
      await dispatch(const LoadCalendarEvents());
      final event = eventOf();
      await dispatch(CreateCalendarEvent(event: event));
      EventAlerts.updateCategoryCache(
        byCategory: {
          CalendarCategories.resolve(event.categoryId).id: [
            CategoryAlert(
              id: 'a1',
              categoryId: CalendarCategories.resolve(event.categoryId).id,
              mode: AlertMode.ring,
            ),
          ],
        },
      );
      calls.clear();
      writes.clear();
      final action = AlertSkipAction.resolve(
        event: event,
        payload: payloadFor(event, DateTime.utc(2026, 9, 20)),
        today: DateTime.utc(2026, 9, 19),
      )!;
      expect(action.apply, isA<UpdateCalendarEvent>());

      await dispatch(action.apply);

      final service = await CalendarEventService.getInstance();
      CalendarEvent stored() =>
          service.events.singleWhere((candidate) => candidate.id == event.id);
      expect(stored().categoryAlerts, isFalse);
      // The category's alert is the category's: nothing of it was written,
      // and the event's own alerts were left as they were.
      expect(writes, isEmpty);
      expect(calls.map((call) => call.eventId), [event.id]);

      await dispatch(action.undo);
      expect(stored().categoryAlerts, isTrue);
      expect(writes, isEmpty);
    });

    test('resolves to nothing for a day already gone', () {
      // A notice that outlived its alarm (review): its Skip must not cancel
      // an occurrence that already happened.
      final event = eventOf(rule: const DailyRecurrence());
      expect(
        AlertSkipAction.resolve(
          event: event,
          payload: payloadFor(event, DateTime.utc(2026, 9, 21)),
          today: DateTime.utc(2026, 9, 22),
        ),
        isNull,
      );
    });

    test(
      'resolves to nothing when the occurrence is already cancelled',
      () async {
        // The notice sits on the shade for the whole lead time, so the user
        // can cancel that day from the day list meanwhile: Skip would apply
        // nothing and its Undo would bring the occurrence — and its alarm —
        // back.
        await dispatch(const LoadCalendarEvents());
        final event = eventOf(rule: const DailyRecurrence());
        final alert = alarmOf(event);
        await dispatch(CreateCalendarEvent(event: event, alerts: [alert]));
        EventAlerts.updateCache(
          byEvent: {
            event.id: [alert],
          },
        );
        final day = DateTime.utc(2026, 9, 22);
        await dispatch(SetOccurrenceSkipped(eventId: event.id, day: day));
        expect(EventSkips.isSkipped(event.id, day), isTrue);

        expect(
          AlertSkipAction.resolve(
            event: event,
            payload: payloadFor(event, day),
            today: DateTime.utc(2026, 9, 22),
          ),
          isNull,
        );
      },
    );

    test("resolves to nothing when a recurring event's alert is gone or off", () {
      // A notice for an alert since deleted or switched off must not cancel
      // the whole occurrence.
      final event = eventOf(rule: const DailyRecurrence());
      final payload = payloadFor(event, DateTime.utc(2026, 9, 22));
      final today = DateTime.utc(2026, 9, 22);

      EventAlerts.updateCache(byEvent: const {});
      expect(
        AlertSkipAction.resolve(event: event, payload: payload, today: today),
        isNull,
      );
      EventAlerts.updateCache(
        byEvent: {
          event.id: [alarmOf(event).copyWith(enabled: false)],
        },
      );
      expect(
        AlertSkipAction.resolve(event: event, payload: payload, today: today),
        isNull,
      );
      EventAlerts.updateCache(
        byEvent: {
          event.id: [alarmOf(event)],
        },
      );
      expect(
        AlertSkipAction.resolve(event: event, payload: payload, today: today),
        isNotNull,
      );
    });

    test(
      "resolves to nothing when a one-time event's alert is gone or off",
      () {
        final event = eventOf();
        final alert = EventAlert(
          id: 'a1',
          eventId: event.id,
          mode: AlertMode.ring,
        );
        final payload = payloadFor(event, DateTime.utc(2026, 9, 20));
        final today = DateTime.utc(2026, 9, 19);

        EventAlerts.updateCache(byEvent: const {});
        expect(
          AlertSkipAction.resolve(event: event, payload: payload, today: today),
          isNull,
        );
        EventAlerts.updateCache(
          byEvent: {
            event.id: [alert.copyWith(enabled: false)],
          },
        );
        expect(
          AlertSkipAction.resolve(event: event, payload: payload, today: today),
          isNull,
        );
        EventAlerts.updateCache(
          byEvent: {
            event.id: [alert],
          },
        );
        expect(
          AlertSkipAction.resolve(event: event, payload: payload, today: today),
          isNotNull,
        );
      },
    );
  });

  test('creating an event reconciles it once', () async {
    await dispatch(const LoadCalendarEvents());
    calls.clear();

    await dispatch(CreateCalendarEvent(event: eventOf()));

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
    expect(calls.single.reason, AlertReconcileReason.eventChanged);
  });

  test('updating an event reconciles it once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    calls.clear();

    await dispatch(
      UpdateCalendarEvent(event: eventOf(title: 'Leg day, later')),
    );

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
  });

  test('deleting an event reconciles it once, by id', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    calls.clear();

    await dispatch(const DeleteCalendarEvent(eventId: 'e1'));

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
  });

  test('deleting an event the bloc does not hold reconciles nothing', () async {
    await dispatch(const LoadCalendarEvents());
    calls.clear();

    bloc.add(const DeleteCalendarEvent(eventId: 'ghost'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls, isEmpty);
  });

  /// A sheet open while a pull tombstones the event it is editing: the Save
  /// still arrives, and `upsert` would clear `is_deleted` under a fresh stamp
  /// — undoing the remote delete on every device.
  test('updating an event the bloc does not hold leaves it deleted', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    await dispatch(const DeleteCalendarEvent(eventId: 'e1'));
    calls.clear();
    writes.clear();

    bloc.add(
      UpdateCalendarEvent(
        event: eventOf(title: 'saved from the open sheet'),
        alerts: const [],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = bloc.state as CalendarPageLoaded;
    expect(state.allEvents.map((e) => e.id), isNot(contains('e1')));
    expect(writes, isEmpty);
    expect(calls, isEmpty);
  });

  test('an update carries the alert ids its sheet was showing', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    writes.clear();

    await dispatch(
      UpdateCalendarEvent(
        event: eventOf(title: 'Leg day, later'),
        alerts: const [],
        knownAlertIds: const {'seeded'},
      ),
    );

    expect(writes.single.knownIds, {'seeded'});
  });

  test('skipping an occurrence reconciles the event once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: eventOf(rule: const WeeklyRecurrence(weekdays: {1, 3, 5})),
      ),
    );
    calls.clear();

    await dispatch(
      SetOccurrenceSkipped(eventId: 'e1', day: DateTime.utc(2026, 9, 21)),
    );

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
    expect(calls.single.reason, AlertReconcileReason.occurrenceChanged);
  });

  test('unskipping an occurrence reconciles the event once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: eventOf(rule: const WeeklyRecurrence(weekdays: {1, 3, 5})),
      ),
    );
    await dispatch(
      SetOccurrenceSkipped(eventId: 'e1', day: DateTime.utc(2026, 9, 21)),
    );
    calls.clear();

    await dispatch(
      ClearOccurrenceSkipped(eventId: 'e1', day: DateTime.utc(2026, 9, 21)),
    );

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
  });

  test('handlers that change nothing the phone owes never reconcile', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    calls.clear();

    // A day tap and a month page are rendering: the plan is untouched, so
    // the platform must not be asked to do anything.
    await dispatch(
      SelectCalendarDay(
        day: DateTime.utc(2026, 9, 21),
        focusedDay: DateTime.utc(2026, 9, 21),
        source: CalendarSelectionSource.grid,
      ),
    );

    expect(calls, isEmpty);
  });

  test("a day's description edit reconciles its event once (OS-4)", () async {
    // Until OS-4 a description edit was rendering too. It is not any more:
    // the day's description is what its reminder and Missed notice expand
    // to, so the edit re-arms the event's entries like a rename does — and
    // so does resetting the day back to the template.
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: eventOf(
          rule: const DailyRecurrence(),
        ).copyWith(perOccurrenceDescriptions: true),
      ),
    );
    calls.clear();

    await dispatch(
      SetOccurrenceDescription(
        eventId: 'e1',
        day: DateTime.utc(2026, 9, 20),
        description: 'squats',
      ),
    );
    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
    expect(calls.single.reason, AlertReconcileReason.eventChanged);

    await dispatch(
      ClearOccurrenceDescription(eventId: 'e1', day: DateTime.utc(2026, 9, 20)),
    );
    expect(calls, hasLength(2));
  });

  const alert = EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 10);

  test('an edited alert list reaches the writer exactly once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    writes.clear();
    order.clear();

    await dispatch(
      UpdateCalendarEvent(
        event: eventOf(title: 'Leg day, later'),
        alerts: const [alert],
      ),
    );

    expect(writes, hasLength(1));
    expect(writes.single.eventId, 'e1');
    expect(writes.single.alerts, const [alert]);
  });

  test('a new event writes its alerts before the platform is asked', () async {
    await dispatch(const LoadCalendarEvents());
    order.clear();

    await dispatch(
      CreateCalendarEvent(event: eventOf(), alerts: const [alert]),
    );

    // The reconcile plans from the rows, so a pass that overtook the write
    // would arm the previous set and only correct itself at the next launch.
    expect(order, ['write', 'reconcile']);
  });

  test('an empty list is a removal, and null is silence', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(event: eventOf(), alerts: const [alert]),
    );
    writes.clear();

    await dispatch(
      UpdateCalendarEvent(event: eventOf(title: 'Leg day, later')),
    );
    expect(writes, isEmpty, reason: 'null means the caller never showed them');

    await dispatch(UpdateCalendarEvent(event: eventOf(), alerts: const []));
    expect(writes, hasLength(1));
    expect(writes.single.alerts, isEmpty);
  });

  test('a write that throws still lets the event save', () async {
    await bloc.close();
    bloc = CalendarBloc(
      service: CalendarEventService.forTesting(db),
      alertReconciler: (eventId, reason) async {
        calls.add((eventId: eventId, reason: reason));
      },
      alertWriter: (eventId, alerts, {knownIds}) async =>
          throw StateError('no database'),
    );
    await dispatch(const LoadCalendarEvents());
    calls.clear();

    await dispatch(
      CreateCalendarEvent(event: eventOf(), alerts: const [alert]),
    );

    final state = bloc.state as CalendarPageLoaded;
    expect(state.allEvents.map((e) => e.id), contains('e1'));
    expect(calls, hasLength(1));
  });

  group('ToggleEventAlert', () {
    const reminder = EventAlert(
      id: 'a1',
      eventId: 'e1',
      mode: AlertMode.notify,
      offsetMinutes: 10,
    );
    const alarm = EventAlert(id: 'a2', eventId: 'e1', mode: AlertMode.ring);

    Future<void> seed() async {
      await dispatch(const LoadCalendarEvents());
      await dispatch(CreateCalendarEvent(event: eventOf()));
      EventAlerts.updateCache(
        byEvent: {
          'e1': List.unmodifiable(const [reminder, alarm]),
        },
      );
      calls.clear();
      writes.clear();
      order.clear();
    }

    tearDown(EventAlerts.resetCache);

    test(
      'writes the whole set with one alert flipped, then reconciles once',
      () async {
        await seed();
        final before = (bloc.state as CalendarPageLoaded).occurrenceRevision;

        await dispatch(
          const ToggleEventAlert(eventId: 'e1', alertId: 'a2', enabled: false),
        );

        expect(writes, hasLength(1));
        expect(writes.single.eventId, 'e1');
        expect(writes.single.alerts, [
          reminder,
          alarm.copyWith(enabled: false),
        ]);
        expect(calls, hasLength(1));
        expect(calls.single.eventId, 'e1');
        expect(order, ['write', 'reconcile']);
        expect(
          (bloc.state as CalendarPageLoaded).occurrenceRevision,
          before + 1,
          reason: 'the row badges re-render on this revision',
        );
      },
    );

    test('bounds the write by the set it was built from', () async {
      // C151: the hub wrote with `knownIds: null`, so a pull landing between
      // the facade read and the DAO's `SELECT` had its alert tombstoned — or
      // its own tombstone undone — by a switch that never drew the row.
      await seed();

      await dispatch(
        const ToggleEventAlert(eventId: 'e1', alertId: 'a2', enabled: false),
      );

      expect(writes.single.knownIds, {'a1', 'a2'});
    });

    test('setting the value an alert already has does nothing', () async {
      await seed();

      bloc.add(
        const ToggleEventAlert(eventId: 'e1', alertId: 'a2', enabled: true),
      );
      bloc.add(
        const ToggleEventAlert(eventId: 'e1', alertId: 'gone', enabled: false),
      );
      await pumpEventQueue();

      expect(writes, isEmpty);
      expect(calls, isEmpty);
    });
  });

  // v42: the category editor writes a category's alerts itself; the bloc
  // only re-renders what draws them.
  group('CategoryAlertsChanged', () {
    test('bumps the occurrence revision and writes nothing', () async {
      await dispatch(const LoadCalendarEvents());
      await dispatch(CreateCalendarEvent(event: eventOf()));
      calls.clear();
      writes.clear();
      final before = bloc.state as CalendarPageLoaded;

      await dispatch(const CategoryAlertsChanged());

      final after = bloc.state as CalendarPageLoaded;
      expect(after.occurrenceRevision, before.occurrenceRevision + 1);
      expect(after.membershipRevision, before.membershipRevision);
      expect(writes, isEmpty);
      expect(calls, isEmpty);
    });
  });

  // v42, D22: a digest belongs to no event, so each of its three writes
  // reconciles the whole horizon, once, and bumps the revision the hub
  // re-reads on.
  group('digests', () {
    late EventDigestService digests;

    // A new digest reaches the bloc without an id: the service mints it.
    const draft = EventDigest(id: '', name: 'Birthdays');

    setUp(() async {
      EventDigestService.reset();
      digests = await EventDigestService.forTesting(db);
      digestWriter = digests;
    });

    tearDown(() {
      digestWriter = null;
      EventDigestService.reset();
    });

    Future<int> loadedRevision() async {
      await dispatch(const LoadCalendarEvents());
      return (bloc.state as CalendarPageLoaded).occurrenceRevision;
    }

    int revision() => (bloc.state as CalendarPageLoaded).occurrenceRevision;

    test('a save of a new digest creates it, reconciles all, bumps', () async {
      final before = await loadedRevision();

      await dispatch(const SaveEventDigest(draft));

      expect(EventDigests.all.single.name, 'Birthdays');
      expect(EventDigests.all.single.id, isNotEmpty);
      expect(fullCalls, [AlertReconcileReason.eventChanged]);
      expect(calls, isEmpty);
      expect(revision(), before + 1);
    });

    test('a save of a known digest updates it in place', () async {
      final saved = (await digests.create(draft))!;
      final before = await loadedRevision();

      await dispatch(SaveEventDigest(saved.copyWith(leadDays: 1)));

      expect(EventDigests.all.single.id, saved.id);
      expect(EventDigests.all.single.leadDays, 1);
      expect(fullCalls, hasLength(1));
      expect(revision(), before + 1);
    });

    test('the toggle writes the switch; the same value is a no-op', () async {
      final saved = (await digests.create(draft))!;
      final before = await loadedRevision();

      await dispatch(ToggleEventDigest(saved.id, enabled: false));
      expect(EventDigests.byId(saved.id)!.enabled, isFalse);
      expect(fullCalls, hasLength(1));
      expect(revision(), before + 1);

      bloc.add(ToggleEventDigest(saved.id, enabled: false));
      await pumpEventQueue();
      expect(fullCalls, hasLength(1));
      expect(revision(), before + 1);
    });

    test('the toggle writes the column alone: a payload this build cannot '
        'fully read keeps every byte', () async {
      // A newer build's digest: a field this one does not know.
      const payload =
          '{"cadence":"monthly","anchor":1,"minute":540,"leadDays":0,'
          '"categories":[],"includeEmpty":false,"pinnedTo":"lockscreen"}';
      await db.eventDigestDao.upsertDigest(
        const EventDigestsCompanion(
          id: Value('newer'),
          name: Value('Newer'),
          payload: Value(payload),
          enabled: Value(true),
          sortOrder: Value(0),
        ),
      );
      await digests.reload();
      final version = (await db.eventDigestDao.getAll()).single.version;
      await loadedRevision();

      await dispatch(const ToggleEventDigest('newer', enabled: false));

      final row = (await db.eventDigestDao.getAll()).single;
      expect(row.payload, payload);
      expect(row.enabled, isFalse);
      expect(row.version, version + 1);
    });

    test('a save equal to the stored digest writes nothing', () async {
      final saved = (await digests.create(draft))!;
      final version = (await db.eventDigestDao.getAll()).single.version;
      final before = await loadedRevision();

      bloc.add(SaveEventDigest(saved));
      await pumpEventQueue();

      expect((await db.eventDigestDao.getAll()).single.version, version);
      expect(fullCalls, isEmpty);
      expect(revision(), before);
    });

    /// A pull can tombstone the open row from another device while the sheet
    /// is up. An upsert would resurrect it under a stamp that beats that
    /// tombstone for good — re-armed, and one over the planner's horizon.
    test('an edit whose digest vanished meanwhile is refused', () async {
      final before = await loadedRevision();
      final emitted = <CalendarPageState>[];
      final subscription = bloc.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      bloc.add(const SaveEventDigest(EventDigest(id: 'gone', name: 'Kept')));
      await pumpEventQueue();

      expect(EventDigests.byId('gone'), isNull);
      expect(emitted, isEmpty);
      expect(fullCalls, isEmpty);
      expect(revision(), before);
    });

    test('a delete tombstones it, reconciles all, bumps', () async {
      final saved = (await digests.create(draft))!;
      final before = await loadedRevision();

      await dispatch(DeleteEventDigest(saved.id));

      expect(EventDigests.all, isEmpty);
      expect(fullCalls, [AlertReconcileReason.eventChanged]);
      expect(revision(), before + 1);
    });

    test('a create past the cap is refused and emits nothing', () async {
      for (var i = 0; i < kDigestHorizon.maxDigests; i++) {
        await digests.create(EventDigest(id: 'x', name: 'D$i'));
      }
      final before = await loadedRevision();
      final emitted = <CalendarPageState>[];
      final subscription = bloc.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      bloc.add(const SaveEventDigest(draft));
      await pumpEventQueue();

      expect(EventDigests.all, hasLength(kDigestHorizon.maxDigests));
      expect(emitted, isEmpty);
      expect(fullCalls, isEmpty);
      expect(revision(), before);
    });
  });

  // S4: presence arms nothing, but a report digest's words count it, so a
  // mark asks the whole horizon once — and only while such a digest is on.
  group('a presence mark', () {
    setUp(() async {
      EventPresenceService.reset();
      await EventPresenceService.forTesting(db);
    });

    tearDown(() {
      EventDigests.resetCache();
      EventPresenceService.reset();
    });

    /// Marks a day with [digests] on. The facade is seeded after the load,
    /// which reads the (empty) digests table into it.
    Future<void> mark(List<EventDigest> digests) async {
      await dispatch(const LoadCalendarEvents());
      EventDigests.updateCache(List.unmodifiable(digests));
      calls.clear();
      fullCalls.clear();
      await dispatch(
        SetOccurrencePresence(
          eventId: 'e1',
          day: DateTime.utc(2026, 9, 20),
          status: PresenceStatus.missed,
        ),
      );
    }

    test('with a report digest on reconciles all, once', () async {
      await mark(const [
        EventDigest(
          id: 'r1',
          cadence: DigestCadence.weeklyReport,
          anchor: DateTime.monday,
        ),
      ]);

      expect(fullCalls, [AlertReconcileReason.eventChanged]);
      expect(calls, isEmpty);
    });

    test('with none, or only a switched-off one or an upcoming one, asks '
        'nothing', () async {
      await mark(const []);
      expect(fullCalls, isEmpty);

      await mark(const [
        EventDigest(id: 'm1'),
        EventDigest(
          id: 'r1',
          cadence: DigestCadence.monthlyReport,
          enabled: false,
        ),
      ]);

      expect(fullCalls, isEmpty);
      expect(calls, isEmpty);
    });
  });
}
