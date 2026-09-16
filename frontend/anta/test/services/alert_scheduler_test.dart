import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/pending_navigation.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/alert_planner.dart';

import '../database/support/db_test_support.dart';

/// Records everything the scheduler asks a platform to do, and answers for a
/// platform that can be asked back.
///
/// The whole point of the gateway seam: the diff, the OS-truth pruning and the
/// multi-database filter are all exercised here against the real DAO and the
/// real planner, with no plugin and no channel anywhere in the test tree.
class FakeAlertGateway implements AlertGateway {
  FakeAlertGateway({this.tracksPending = true});

  @override
  final bool tracksPending;

  @override
  String get backendName => 'fake';

  /// What the "platform" currently holds, keyed by os id.
  final Map<int, AlertPayload> platform = {};

  final List<PlannedFire> scheduled = [];
  final List<int> cancelled = [];
  final List<int> stopped = [];
  final List<AlertPayload> missed = [];

  /// When false, every schedule is refused — the revoked-permission case.
  bool accepts = true;

  /// What the "platform" is ringing right now.
  final Set<int> ringingNow = {};

  @override
  Set<int> get ringingIds => ringingNow;

  void resetCalls() {
    scheduled.clear();
    cancelled.clear();
    stopped.clear();
    missed.clear();
  }

  /// Arms an entry the app did not put there — an imported `.db` file's
  /// registrations, or another database's alarms.
  void seedPlatform(AlertPayload payload) => platform[payload.osId] = payload;

  @override
  Future<bool> schedule(PlannedFire fire, AlertPayload payload) async {
    if (!accepts) return false;
    scheduled.add(fire);
    platform[payload.osId] = payload;
    return true;
  }

  @override
  Future<void> cancel(int osId) async {
    cancelled.add(osId);
    platform.remove(osId);
  }

  @override
  Future<List<PendingAlertEntry>> pendingEntries() async => [
    for (final entry in platform.entries)
      (osId: entry.key, payload: entry.value),
  ];

  @override
  Future<Set<int>> pendingIds() async => platform.keys.toSet();

  @override
  Future<void> showMissed(AlertPayload payload) async => missed.add(payload);

  @override
  Future<AlertPermissions> permissions() async => (
    notifications: AlertPermissionState.granted,
    fullScreenIntent: AlertPermissionState.granted,
    exactAlarms: AlertPermissionState.granted,
  );

  @override
  Future<bool> requestNotifications() async => true;

  @override
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<void> stopRinging(int osId) async => stopped.add(osId);

  @override
  Stream<AlertPayload> get ringing => const Stream<AlertPayload>.empty();

  @override
  Future<AlertIntent?> launchIntent() async => null;

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late FakeAlertGateway gateway;
  late CalendarEventService events;
  late EventAlertService alerts;
  late DateTime now;

  // `PublicHolidayService` has no `forTesting` seam and opens the singleton
  // database; stubbing `path_provider` keeps it from logging on every pass.
  // Neither plugin of *this* feature is stubbed anywhere.
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_alert_scheduler');
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

  void resetSingletons() {
    AlertScheduler.reset();
    CalendarEventService.reset();
    EventAlertService.reset();
    EventSkipService.reset();
    SettingsService.reset();
  }

  setUp(() async {
    resetSingletons();
    db = await openTestDatabase();
    gateway = FakeAlertGateway();
    SettingsService.forTesting(db);
    events = await CalendarEventService.forTesting(db);
    alerts = await EventAlertService.forTesting(db);
    await EventSkipService.forTesting(db);
    now = DateTime(2026, 9, 15, 12);
  });

  tearDown(() async {
    resetSingletons();
    PublicHolidayService.reset();
    await db.close();
  });

  AlertScheduler schedulerOf({
    String database = 'gym_notes',
    FakeAlertGateway? withGateway,
    AlertHorizon horizon = kAlertHorizon,
  }) => AlertScheduler.forTesting(
    db: db,
    gateway: withGateway ?? gateway,
    databaseName: database,
    clock: () => now,
    horizon: horizon,
  );

  CalendarEvent eventOf({
    String id = 'e1',
    String title = 'Leg day',
    RecurrenceRule rule = const OneTimeRecurrence(),
    DateTime? startDate,
    EventTime? time = const EventTime(startMinute: 18 * 60),
    bool removeAfterAlert = false,
  }) => CalendarEvent(
    id: id,
    title: title,
    categoryId: 'gym',
    startDate: startDate ?? DateTime.utc(2026, 9, 20),
    rule: rule,
    time: time,
    removeAfterAlert: removeAfterAlert,
  );

  EventAlert alertOf({
    String id = 'a1',
    String eventId = 'e1',
    AlertMode mode = AlertMode.ring,
    int offsetMinutes = 0,
  }) => EventAlert(
    id: id,
    eventId: eventId,
    mode: mode,
    offsetMinutes: offsetMinutes,
  );

  Future<void> seed({
    CalendarEvent? event,
    List<EventAlert> eventAlerts = const [],
  }) async {
    final target = event ?? eventOf();
    await events.upsert(target);
    await alerts.replaceForEvent(
      target.id,
      eventAlerts.isEmpty ? [alertOf(eventId: target.id)] : eventAlerts,
    );
  }

  Future<List<AlertRegistrationRow>> registrations() =>
      db.select(db.alertRegistrations).get();

  group('the diff', () {
    test('a first pass schedules the plan and records it', () async {
      await seed();
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.scheduled, hasLength(1));
      final rows = await registrations();
      expect(rows, hasLength(1));
      expect(rows.single.eventId, 'e1');
      expect(rows.single.alertId, 'a1');
      expect(rows.single.state, AlertRegistrationState.pending.name);
      expect(rows.single.kind, AlertKind.scheduled.name);
      expect(rows.single.backend, 'fake');
      expect(
        rows.single.day,
        DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
      );
      expect(gateway.platform, hasLength(1));
    });

    test('an unchanged plan issues zero platform calls', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled, isEmpty);
      expect(await registrations(), hasLength(1));
    });

    test('the os id survives a scheduler rebuilt from scratch', () async {
      await seed();
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);
      final before = (await registrations()).single.osId;

      // A process death: a brand new scheduler, the same registry.
      AlertScheduler.reset();
      gateway.resetCalls();
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect((await registrations()).single.osId, before);
      expect(gateway.scheduled, isEmpty);
    });

    test('an edited time re-schedules the same registration', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = (await registrations()).single;
      gateway.resetCalls();

      await events.upsert(
        eventOf(time: const EventTime(startMinute: 19 * 60)),
      );
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.scheduled, hasLength(1));
      final after = (await registrations()).single;
      expect(after.osId, before.osId, reason: 'same alert, same day, same id');
      expect(after.fireAt, greaterThan(before.fireAt));
      expect(after.createdAt, before.createdAt);
    });

    test('a rename refreshes that event\'s payloads, and only those', () async {
      // The registry stores the instant and the backend, not the payload, so
      // a rename changes nothing the fast path can see — and the OS would go
      // on holding the old title until the *time* changed.
      await seed(
        eventAlerts: [
          alertOf(id: 'a1', offsetMinutes: 0),
          alertOf(id: 'a2', offsetMinutes: 30),
        ],
      );
      await events.upsert(eventOf(id: 'e2', title: 'Swim'));
      await alerts.replaceForEvent('e2', [alertOf(id: 'b1', eventId: 'e2')]);

      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = {
        for (final row in await registrations()) row.alertId: row,
      };
      gateway.resetCalls();

      await events.upsert(eventOf(title: 'Leg day (heavy)'));
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      // Once per planned entry of that event, and nothing for the other one.
      expect(gateway.scheduled, hasLength(2));
      expect(
        gateway.scheduled.map((fire) => fire.event.id).toSet(),
        {'e1'},
      );
      expect(gateway.cancelled, isEmpty);
      for (final alertId in ['a1', 'a2']) {
        final row = before[alertId]!;
        expect(gateway.platform[row.osId]!.title, 'Leg day (heavy)');
        final after = (await registrations()).firstWhere(
          (candidate) => candidate.alertId == alertId,
        );
        expect(after.osId, row.osId, reason: 'the id must not move');
        expect(after.fireAt, row.fireAt);
      }
      expect(gateway.platform[before['b1']!.osId]!.title, 'Swim');
    });

    test('a removed alert is cancelled, never the whole set', () async {
      final other = eventOf(id: 'e2', title: 'Swim');
      await seed();
      await events.upsert(other);
      await alerts.replaceForEvent('e2', [alertOf(id: 'b1', eventId: 'e2')]);

      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      expect(await registrations(), hasLength(2));
      gateway.resetCalls();

      await alerts.replaceForEvent('e1', const []);
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, hasLength(1));
      expect(gateway.scheduled, isEmpty, reason: 'e2 must not be re-armed');
      final rows = await registrations();
      final byEvent = {for (final row in rows) row.eventId: row.state};
      expect(byEvent['e1'], AlertRegistrationState.cancelled.name);
      expect(byEvent['e2'], AlertRegistrationState.pending.name);
    });

    test('a refused schedule records nothing, so the next pass retries',
        () async {
      await seed();
      gateway.accepts = false;
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      expect(await registrations(), isEmpty);

      gateway.accepts = true;
      await scheduler.reconcileAll(AlertReconcileReason.resumed);
      expect(await registrations(), hasLength(1));
    });

    test('a deleted event has its registrations cancelled', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;
      gateway.resetCalls();

      // `deleteById` cascades the alert rows and hard-deletes the registry
      // rows; the platform still holds the entry, and that is the point.
      await events.deleteById('e1');
      await alerts.refreshAfterEventRemoval();
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, contains(osId));
      expect(gateway.platform, isEmpty);
    });
  });

  group('OS truth', () {
    test('a registry row the platform forgot is dropped and re-armed',
        () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;

      // A force stop: the OS dropped every pending entry and told nobody.
      gateway.platform.clear();
      gateway.resetCalls();
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(
        gateway.scheduled,
        hasLength(1),
        reason: 'the row must not be trusted over the platform',
      );
      expect(gateway.cancelled, isEmpty);
      final rows = await registrations();
      final pending = rows.where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      expect(pending, hasLength(1));
      expect(pending.single.osId, osId);
    });

    test(
      'a platform entry the registry lost is cancelled (the import wipe)',
      () async {
        await seed();
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        final osId = (await registrations()).single.osId;

        // `CalendarEventService.deleteAll` — the event-import wipe — empties
        // the registry while the OS keeps its entries.
        await db.alertRegistrationDao.deleteAll();
        await alerts.deleteAll();
        await events.deleteAll();
        gateway.resetCalls();

        await scheduler.reconcileAll(AlertReconcileReason.backupRestored);

        expect(gateway.cancelled, [osId]);
        expect(gateway.platform, isEmpty);
      },
    );

    test('an entry of another database is never touched (A9)', () async {
      await seed();
      gateway.seedPlatform(
        AlertPayload(
          database: 'work',
          eventId: 'w1',
          alertId: 'wa1',
          dayUtcMs: DateTime.utc(2026, 9, 21).millisecondsSinceEpoch,
          osId: 99001,
          mode: AlertMode.ring,
          title: 'Standup',
          timeLabel: '09:00',
          categoryId: 'other',
        ),
      );

      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.cancelled, isEmpty);
      expect(gateway.platform.containsKey(99001), isTrue);
    });

    test('OS truth is not applied to a gateway that cannot answer', () async {
      // The no-op binding knows nothing, always. Applying its silence would
      // cancel and re-register the whole horizon on every pass.
      final blind = FakeAlertGateway(tracksPending: false);
      await seed();
      final scheduler = schedulerOf(withGateway: blind);
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      blind.platform.clear();
      blind.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(blind.scheduled, isEmpty);
      expect(blind.cancelled, isEmpty);
    });
  });

  group('late fires', () {
    // The app never sees a delivery: the alarm plugin relaunches the process
    // and emits on `Alarm.ringing` a second or two *after* the launch reconcile
    // that relaunch provoked, and the notification tier never calls back at
    // all. So a past instant means one of three things, and the grace window is
    // what tells them apart.
    const fireAt = 18 * 60; // 2026-09-20 18:00, the seeded event's start.

    /// Arms the seeded alert, then reconciles again [lateness] past its fire.
    Future<AlertRegistrationRow> runLate(
      AlertScheduler scheduler,
      Duration lateness,
    ) async {
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      gateway.resetCalls();
      now = DateTime(
        2026,
        9,
        20,
        0,
        fireAt,
      ).add(lateness);
      await scheduler.reconcileAll(AlertReconcileReason.resumed);
      return armed;
    }

    Future<AlertRegistrationRow> rowOf(int osId) async =>
        (await registrations()).firstWhere((row) => row.osId == osId);

    for (final mode in [AlertMode.ring, AlertMode.notify]) {
      final tier = mode == AlertMode.ring ? 'an alarm' : 'a reminder';

      test('$tier five minutes late is in flight and left alone', () async {
        await seed(eventAlerts: [alertOf(mode: mode)]);
        final scheduler = schedulerOf();

        final armed = await runLate(scheduler, const Duration(minutes: 5));

        // Session 3's ring handler is what settles this row. A reconcile that
        // cancelled it would disarm a ring in progress, and one that reported
        // it would post "Missed" over the noise it is still making.
        expect((await rowOf(armed.osId)).state,
            AlertRegistrationState.pending.name);
        expect(gateway.cancelled, isEmpty);
        expect(gateway.scheduled, isEmpty);
        expect(gateway.missed, isEmpty);
        expect(
          gateway.platform.containsKey(armed.osId),
          isTrue,
          reason: 'the platform entry must survive both OS-truth directions',
        );
      });

      test('$tier thirty-one minutes late is over', () async {
        await seed(eventAlerts: [alertOf(mode: mode)]);
        final scheduler = schedulerOf();

        final armed = await runLate(scheduler, const Duration(minutes: 31));

        expect((await rowOf(armed.osId)).state,
            AlertRegistrationState.cancelled.name);
        expect(gateway.cancelled, contains(armed.osId));
        if (mode == AlertMode.ring) {
          expect(gateway.missed, hasLength(1));
          expect(gateway.missed.single.title, 'Leg day');
          expect(gateway.missed.single.timeLabel, '18:00');
          expect(gateway.missed.single.mode, AlertMode.ring);
        } else {
          // A reminder that was simply not tapped is not a missed
          // appointment, and the OS gives the app no way to tell the two
          // apart — so every launch would otherwise post a pile of these.
          expect(gateway.missed, isEmpty);
        }
      });

      test('$tier twenty-five hours late is settled quietly', () async {
        await seed(eventAlerts: [alertOf(mode: mode)]);
        final scheduler = schedulerOf();

        final armed = await runLate(scheduler, const Duration(hours: 25));

        expect((await rowOf(armed.osId)).state,
            AlertRegistrationState.cancelled.name);
        expect(gateway.missed, isEmpty);
      });
    }

    test('a ring the app has been told about is left ringing', () async {
      await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      // The ring handler's first act: the row is now `fired`, so it is neither
      // pending nor in flight — but the `alarm` package still holds the entry
      // until Stop, and the platform reports it as ringing.
      await scheduler.markFired(armed.osId);
      gateway.ringingNow.add(armed.osId);
      gateway.resetCalls();

      // The resume reconcile the alarm page's own appearance provokes, two
      // seconds into the ring.
      now = DateTime(2026, 9, 20, 0, fireAt).add(const Duration(seconds: 2));
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.cancelled, isEmpty);
      expect(gateway.stopped, isEmpty);
      expect(gateway.platform.containsKey(armed.osId), isTrue);
      expect((await rowOf(armed.osId)).state,
          AlertRegistrationState.fired.name);
    });

    test('an alarm whose alert was deleted is settled quietly', () async {
      await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      await alerts.replaceForEvent('e1', const []);
      gateway.resetCalls();

      now = DateTime(2026, 9, 20, 0, fireAt).add(const Duration(minutes: 31));
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.missed, isEmpty);
      expect((await rowOf(armed.osId)).state,
          AlertRegistrationState.cancelled.name);
    });

    test('a recurring event re-arms the next occurrence after a late fire',
        () async {
      await seed(
        event: eventOf(
          startDate: DateTime.utc(2026, 9, 1),
          rule: const DailyRecurrence(),
        ),
      );
      final scheduler = schedulerOf(
        horizon: const AlertHorizon(perAlert: 1, days: 30, total: 48),
      );
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      expect(
        (await registrations()).single.day,
        DateTime.utc(2026, 9, 15).millisecondsSinceEpoch,
      );

      now = DateTime(2026, 9, 15, 19);
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      final pending = (await registrations()).where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      expect(pending, hasLength(1));
      expect(pending.single.day, DateTime.utc(2026, 9, 16).millisecondsSinceEpoch);
    });
  });

  group('snooze', () {
    test('creates its own registration snoozeMinutes out', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;

      now = DateTime(2026, 9, 20, 18);
      await scheduler.snooze(osId);

      final rows = await registrations();
      expect(rows, hasLength(2));
      final snoozed = rows.firstWhere(
        (row) => row.kind == AlertKind.snooze.name,
      );
      expect(snoozed.state, AlertRegistrationState.pending.name);
      expect(
        snoozed.fireAt,
        DateTime(2026, 9, 20, 18, 10).millisecondsSinceEpoch,
      );
      expect(
        rows.firstWhere((row) => row.osId == osId).state,
        AlertRegistrationState.fired.name,
      );
      expect(gateway.stopped, [osId]);
      expect(gateway.scheduled.last.kind, AlertKind.snooze);
      expect(gateway.platform[snoozed.osId]!.snooze, isTrue);
    });

    test('an unrelated reconcile leaves a snooze alone', () async {
      await seed();
      final other = eventOf(id: 'e2', title: 'Swim');
      await events.upsert(other);
      await alerts.replaceForEvent('e2', [alertOf(id: 'b1', eventId: 'e2')]);

      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final target = (await registrations()).firstWhere(
        (row) => row.eventId == 'e1',
      );
      now = DateTime(2026, 9, 20, 18);
      await scheduler.snooze(target.osId);
      final snoozed = (await registrations()).firstWhere(
        (row) => row.kind == AlertKind.snooze.name,
      );
      gateway.resetCalls();

      await events.upsert(other.copyWith(title: 'Swim, later'));
      await scheduler.reconcileEvent('e2', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, isNot(contains(snoozed.osId)));
      final after = (await registrations()).firstWhere(
        (row) => row.osId == snoozed.osId,
      );
      expect(after.state, AlertRegistrationState.pending.name);
      expect(after.fireAt, snoozed.fireAt);
    });

    test('cancelSnooze drops it', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      now = DateTime(2026, 9, 20, 18);
      await scheduler.snooze((await registrations()).single.osId);
      final snoozed = (await registrations()).firstWhere(
        (row) => row.kind == AlertKind.snooze.name,
      );
      gateway.resetCalls();

      await scheduler.cancelSnooze(snoozed.osId);

      expect(gateway.cancelled, [snoozed.osId]);
      expect(
        (await registrations())
            .firstWhere((row) => row.osId == snoozed.osId)
            .state,
        AlertRegistrationState.cancelled.name,
      );
    });
  });

  group('stop', () {
    test('marks the registration stopped and arms the next occurrence',
        () async {
      await seed(
        event: eventOf(
          startDate: DateTime.utc(2026, 9, 1),
          rule: const DailyRecurrence(),
        ),
      );
      final scheduler = schedulerOf(
        horizon: const AlertHorizon(perAlert: 1, days: 30, total: 48),
      );
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;

      now = DateTime(2026, 9, 15, 18);
      await scheduler.stop(osId);

      final rows = await registrations();
      expect(
        rows.firstWhere((row) => row.osId == osId).state,
        AlertRegistrationState.stopped.name,
      );
      final pending = rows.where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      expect(pending, hasLength(1));
      expect(
        pending.single.day,
        DateTime.utc(2026, 9, 16).millisecondsSinceEpoch,
      );
      expect(gateway.stopped, [osId]);
    });

    test('an unknown os id is a no-op, not a crash', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      await scheduler.stop(4242);

      expect(gateway.stopped, [4242]);
      expect(await registrations(), hasLength(1));
    });
  });

  group('the payload', () {
    test('carries the database, the event and the fire time', () async {
      await seed(event: eventOf(removeAfterAlert: true));
      await schedulerOf(database: 'work').reconcileAll(
        AlertReconcileReason.launch,
      );

      final payload = gateway.platform.values.single;
      expect(payload.database, 'work');
      expect(payload.eventId, 'e1');
      expect(payload.alertId, 'a1');
      expect(payload.title, 'Leg day');
      expect(payload.timeLabel, '18:00');
      expect(payload.mode, AlertMode.ring);
      expect(payload.categoryId, 'gym');
      expect(payload.removeAfterAlert, isTrue);
      expect(payload.snooze, isFalse);
      expect(payload.dayUtc, DateTime.utc(2026, 9, 20));
      // Round-trips through the wire form the platform actually stores.
      expect(AlertPayload.decode(payload.encode()), payload);
    });
  });

  group('the sweep', () {
    test('settled rows older than a week go, the pending plan stays',
        () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final planned = (await registrations()).single.osId;

      // A settled registration of an alert that is long gone, a fortnight old.
      await db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: const Value(4242),
          alertId: const Value('gone'),
          eventId: const Value('gone'),
          day: Value(DateTime.utc(2026, 9, 1).millisecondsSinceEpoch),
          fireAt: Value(DateTime(2026, 9, 1, 7).millisecondsSinceEpoch),
          kind: Value(AlertKind.scheduled.name),
          state: Value(AlertRegistrationState.stopped.name),
          backend: const Value('fake'),
          createdAt: Value(DateTime(2026, 9, 1)),
          updatedAt: Value(DateTime(2026, 9, 1)),
        ),
      );

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      final rows = await registrations();
      expect(rows.map((row) => row.osId), [planned]);
      expect(rows.single.state, AlertRegistrationState.pending.name);
    });

    test('a pending row is never swept, however old', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;
      await (db.update(db.alertRegistrations)
            ..where((row) => row.osId.equals(osId)))
          .write(
            AlertRegistrationsCompanion(
              updatedAt: Value(DateTime(2026, 1, 1)),
            ),
          );

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      // Still exactly one row, still the same one: a pending registration
      // whose instant has not arrived is the only record that it was ever
      // armed, and the late-fire pass has to be able to find it.
      final rows = await registrations();
      expect(rows.map((row) => row.osId), [osId]);
      expect(rows.single.state, AlertRegistrationState.pending.name);
    });
  });

  group('serialization', () {
    test('two reconciles run one after the other, not interleaved', () async {
      await seed();
      // Every singleton is resolved *outside* the zone: `PublicHolidayService`
      // opens the app database through `shared_preferences`, and a platform
      // channel reply never arrives under `FakeAsync`. The in-memory database
      // is opened outside it for the same reason.
      await PublicHolidayService.getInstance();
      final scheduler = schedulerOf();

      // The tail is seeded `null`, never a completed future built in a field
      // initializer: such a future schedules its continuations on the zone it
      // was born in, so a chain seeded in `setUp` would never advance under
      // the `FakeAsync` the body runs in and the very first turn would hang.
      fakeAsync((async) {
        final done = <String>[];
        scheduler
            .reconcileAll(AlertReconcileReason.launch)
            .then((_) => done.add('all'));
        scheduler
            .reconcileEvent('e1', AlertReconcileReason.eventChanged)
            .then((_) => done.add('event'));

        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(
          done,
          ['all', 'event'],
          reason: 'the chain advanced, in the order the turns were enqueued',
        );
      });
    });
  });
}
