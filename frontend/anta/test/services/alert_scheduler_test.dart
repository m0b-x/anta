import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/alert_hub_entry.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/alert_sound.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
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

  /// What this "platform" says a ring will be armed **under** — the token a
  /// real binding reads the phone's alarm volume into. Moving it between two
  /// passes is how a volume slider dragged across the floor is modelled.
  String armContext = 'fake';

  /// Asked once per pass, never once per fire.
  int armContextReads = 0;

  @override
  Future<String> refreshArmContext() async {
    armContextReads++;
    return armContext;
  }

  @override
  bool get supportsSoundPicker => false;

  @override
  Future<PickedAlertSound?> pickSystemSound(String? current) async => null;

  @override
  Future<String?> soundTitle(String value) async => null;

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
    notices.clear();
  }

  /// Arms an entry the app did not put there — an imported `.db` file's
  /// registrations, or another database's alarms.
  void seedPlatform(AlertPayload payload) => platform[payload.osId] = payload;

  /// The upcoming notice asked for beside each armed entry, by os id: the
  /// instant, or null when the scheduler asked for none (which a real
  /// binding answers by taking a standing notice down).
  final Map<int, DateTime?> notices = {};

  @override
  Future<bool> schedule(
    PlannedFire fire,
    AlertPayload payload, {
    DateTime? noticeAt,
  }) async {
    if (!accepts) return false;
    scheduled.add(fire);
    platform[payload.osId] = payload;
    notices[payload.osId] = noticeAt;
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
  Future<void> stopRinging(int osId) async => stopped.add(osId);

  @override
  Stream<AlertPayload> get ringing => const Stream<AlertPayload>.empty();

  @override
  Stream<AlertRingEnd> get ringEnded => const Stream<AlertRingEnd>.empty();

  @override
  Stream<void> get showAlarms => const Stream<void>.empty();

  /// Session chips posted (OS-5), by os id, and how many were taken down.
  final List<int> chips = [];
  int chipsCleared = 0;

  @override
  Future<bool> showSessionChip(
    AlertPayload payload, {
    required DateTime startedAt,
    DateTime? endsAt,
    int? progress,
    bool refresh = false,
  }) async {
    chips.add(payload.osId);
    return true;
  }

  @override
  Future<void> clearSessionChip() async {
    chipsCleared++;
  }

  /// Deferrals the "plugin" made on its own since the last [takeMoves].
  final List<AlertMove> moves = [];

  /// Every move the scheduler told the platform it had written down.
  final List<AlertMove> acknowledged = [];

  @override
  Future<List<AlertMove>> takeMoves() async {
    final taken = List<AlertMove>.of(moves);
    moves.clear();
    return taken;
  }

  @override
  Future<void> acknowledgeMove(AlertMove move) async => acknowledged.add(move);

  /// When the "process" started; null is a platform that cannot say.
  DateTime? startedAt;

  @override
  Future<DateTime?> processStartedAt() async => startedAt;

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
    EventOccurrenceService.reset();
    CategoryService.reset();
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
    await EventOccurrenceService.forTesting(db);
    await CategoryService.forTesting(db);
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
      // The sound is named for every alarm-tier fire, the phone's default
      // included, and the fork's arming shape closes it — see
      // `alertArmSignature`.
      expect(rows.single.backend, 'fake#system:default~clock~10~n120');
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

    test('the platform is asked once per pass what a ring is armed under', () async {
      // Two alerts, one pass: the alarm stream is one number for the whole
      // phone, and asking for it per fire would put a channel round trip on
      // the diff's inner loop.
      await seed(
        eventAlerts: [
          alertOf(id: 'a1'),
          alertOf(id: 'a2', offsetMinutes: 30),
        ],
      );
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.scheduled, hasLength(2));
      expect(gateway.armContextReads, 1);
    });

    test('a moved arm context re-arms standing alarms', () async {
      // The phone's alarm volume crossing the floor while the app was away.
      // Nothing about the event changed and nothing dispatches, so this is the
      // only thing that can reach an alarm already armed the old way.
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = (await registrations()).single.osId;
      gateway.resetCalls();

      gateway.armContext = 'fake@floor';
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.scheduled, hasLength(1));
      final row = (await registrations()).single;
      expect(row.osId, before, reason: 're-armed in place, not re-issued');
      expect(row.backend, 'fake@floor#system:default~clock~10~n120');

      // And settles again: the third pass has nothing left to do.
      gateway.resetCalls();
      await scheduler.reconcileAll(AlertReconcileReason.resumed);
      expect(gateway.scheduled, isEmpty);
    });

    test('a row armed before the fork is re-armed once, in place', () async {
      // What a pre-OS-1 build recorded for this fire: the same context and
      // sound, no `~clock`. Its platform entry was armed with
      // `setExactAndAllowWhileIdle` and, for a picked sound, with a copied
      // file this build deletes — and the plugin's own init re-sets it just
      // as it was. Only the signature can reach it.
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = (await registrations()).single;
      await (db.update(db.alertRegistrations)
            ..where((row) => row.osId.equals(before.osId)))
          .write(
            const AlertRegistrationsCompanion(
              backend: Value('fake#system:default'),
            ),
          );
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.launch);

      expect(gateway.scheduled, hasLength(1));
      final rearmed = (await registrations()).single;
      expect(rearmed.osId, before.osId, reason: 're-armed in place');
      expect(rearmed.backend, 'fake#system:default~clock~10~n120');

      // Once: the next pass finds the fork's own token and does nothing.
      gateway.resetCalls();
      await scheduler.reconcileAll(AlertReconcileReason.resumed);
      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled, isEmpty);
    });

    test('a changed alarm sound re-arms without anything dispatching', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      // What the Calendar settings row writes. The event is untouched, so the
      // fast path is all that stands between the user's choice and an alarm
      // that still rings the old sound.
      await (await SettingsService.getInstance())
          .setAlertSound('content://media/7');
      await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

      expect(gateway.scheduled, hasLength(1));
      expect(
        gateway.scheduled.single.sound,
        const AlertSoundUri('content://media/7'),
      );
      expect(
        (await registrations()).single.backend,
        'fake#content://media/7~clock~10~n120',
      );
    });

    test('a reminder is not re-armed by a sound it cannot play', () async {
      // The reminder tier plays through a notification channel whose sound
      // Android froze at creation, so the setting can never change what one
      // does — and re-arming it would be work for nothing.
      await seed(eventAlerts: [alertOf(mode: AlertMode.notify)]);
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      await (await SettingsService.getInstance())
          .setAlertSound('system:default');
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.scheduled, isEmpty);
      expect((await registrations()).single.backend, 'fake');
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

        // OS-4: the row a Missed notice is posted for reads `missed`, so the
        // hub's Recent section can say so; a reminder is not reported and
        // stays `cancelled`.
        expect(
          (await rowOf(armed.osId)).state,
          mode == AlertMode.ring
              ? AlertRegistrationState.missed.name
              : AlertRegistrationState.cancelled.name,
        );
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

    test('a reminder delivered more than a day ago is cleared from the shade',
        () async {
      // The notification plugin re-arms every reminder it held when the phone
      // boots and the OS fires a past one on the spot, so this row's
      // notification is up — and delivered, so no longer *pending*: the
      // OS-truth pass cannot see it, and only the settle can take it down.
      await seed(eventAlerts: [alertOf(mode: AlertMode.notify)]);
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      gateway.platform.remove(armed.osId);
      gateway.resetCalls();

      now = DateTime(2026, 9, 20, 0, fireAt).add(const Duration(hours: 25));
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.cancelled, [armed.osId]);
      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.cancelled.name,
      );
    });

    test('a reminder delivered this morning stays in the shade', () async {
      // Under a day late it may still be wanted — the session it announced can
      // be under way — and a reminder is never reported, so nothing touches
      // it.
      await seed(eventAlerts: [alertOf(mode: AlertMode.notify)]);
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      gateway.platform.remove(armed.osId);
      gateway.resetCalls();

      now = DateTime(2026, 9, 20, 0, fireAt).add(const Duration(minutes: 31));
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.cancelled, isEmpty);
      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.cancelled.name,
      );
    });

    test('a process alive at the fire instant proves the alarm rang',
        () async {
      // Phone in use, app not: Android shows the ring as a heads-up, the user
      // stops it from there, and no Dart ever runs to mark the row. The
      // process the alarm started is still the one the app opens in.
      await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
      gateway.startedAt = DateTime(2026, 9, 20, 17, 59, 58);

      final armed = await runLate(schedulerOf(), const Duration(minutes: 40));

      expect((await rowOf(armed.osId)).state, AlertRegistrationState.fired.name);
      expect(gateway.missed, isEmpty);
    });

    test('a process that started afterwards proves nothing', () async {
      // A force stop or a phone that was off: whatever is running now was
      // started by the user opening the app, after the instant had passed.
      await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
      gateway.startedAt = DateTime(2026, 9, 20, 18, 39);

      final armed = await runLate(schedulerOf(), const Duration(minutes: 40));

      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.missed.name,
      );
      expect(gateway.missed, hasLength(1));
    });

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

  group('alarm log (OS-4)', () {
    test('a timed-out ring is settled as missed', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      now = DateTime.fromMillisecondsSinceEpoch(
        armed.fireAt,
      ).add(const Duration(minutes: 10, seconds: 1));
      await scheduler.markFired(armed.osId);

      await scheduler.settleEndedRing(
        gateway.platform[armed.osId]!,
        answered: false,
      );

      expect(
        (await registrations()).singleWhere((row) => row.osId == armed.osId).state,
        AlertRegistrationState.missed.name,
      );
      expect(gateway.missed, hasLength(1));
    });

    test('recentEntries lists what settled, newest first, cancelled left out',
        () async {
      await seed(
        event: eventOf(
          rule: const DailyRecurrence(),
          startDate: DateTime.utc(2026, 9, 14),
        ),
      );
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final rows = await registrations();
      expect(rows, hasLength(2));
      final first = rows.reduce((a, b) => a.fireAt < b.fireAt ? a : b);
      final second = rows.firstWhere((row) => row.osId != first.osId);

      // Stopped from the page at its ring.
      now = DateTime.fromMillisecondsSinceEpoch(first.fireAt).add(const Duration(seconds: 1));
      await scheduler.markFired(first.osId);
      await scheduler.stop(first.osId);
      // Then a snooze, settled by its own ring being stopped.
      final after = await registrations();
      final next = after.firstWhere((row) => row.osId == second.osId);
      now = DateTime.fromMillisecondsSinceEpoch(next.fireAt).add(const Duration(seconds: 1));
      await scheduler.markFired(next.osId);
      await scheduler.snooze(next.osId);
      final snoozeRow = (await registrations()).singleWhere(
        (row) => row.kind == AlertKind.snooze.name,
      );
      now = now.add(const Duration(minutes: 10, seconds: 1));
      await scheduler.markFired(snoozeRow.osId);
      await scheduler.stop(snoozeRow.osId);
      // And one cancelled outright, which is the plan changing, not history.
      final pendingNow = (await registrations()).where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      await scheduler.cancelSnooze(pendingNow.first.osId);

      final recent = await scheduler.recentEntries();

      expect(recent.map((entry) => entry.outcome), [
        AlertOutcome.snoozed,
        AlertOutcome.stopped,
      ]);
      expect(
        recent.map((entry) => entry.settledAt).toList(),
        recent.map((entry) => entry.settledAt).toList()
          ..sort((a, b) => b.compareTo(a)),
        reason: 'newest first',
      );
      expect(recent.every((entry) => entry.event?.id == 'e1'), isTrue);
      expect(recent.every((entry) => entry.alert?.id == 'a1'), isTrue);
    });

    test('recentEntries keeps a row whose event is gone', () async {
      // The shape a tombstone written by another device leaves behind: a
      // settled registration naming an event this database no longer has.
      // An in-app delete hard-deletes the rows with the event, so the row is
      // written straight into the registry here.
      await db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: const Value(4242),
          alertId: const Value('a-gone'),
          eventId: const Value('e-gone'),
          day: Value(DateTime.utc(2026, 9, 14).millisecondsSinceEpoch),
          fireAt: Value(DateTime(2026, 9, 14, 18).millisecondsSinceEpoch),
          kind: Value(AlertKind.scheduled.name),
          state: Value(AlertRegistrationState.missed.name),
          backend: const Value('fake'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final recent = await schedulerOf().recentEntries();

      expect(recent, hasLength(1));
      expect(recent.single.event, isNull);
      expect(recent.single.alert, isNull);
      expect(recent.single.outcome, AlertOutcome.missed);
    });

    test('a delivered reminder reads delivered, and a ring in progress is not history', () async {
      await seed(
        eventAlerts: [
          alertOf(id: 'a1'),
          alertOf(id: 'r1', mode: AlertMode.notify),
        ],
      );
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final rows = await registrations();
      final alarm = rows.singleWhere((row) => row.alertId == 'a1');
      // The ring handler just marked the alarm: in flight, not settled.
      now = DateTime.fromMillisecondsSinceEpoch(alarm.fireAt).add(const Duration(seconds: 5));
      gateway.ringingNow.add(alarm.osId);
      await scheduler.markFired(alarm.osId);
      expect(await scheduler.recentEntries(), isEmpty);

      // The process dies mid-ring and the phone ends the ring on its own:
      // nothing settles the row, and the platform no longer holds the entry.
      gateway.ringingNow.clear();
      gateway.platform.remove(alarm.osId);

      // The delivery-evidence band settles the reminder as `fired` — which
      // for a notification means delivered, not rang — and the alarm's own
      // `fired` row, past the grace, reads as the ring it was.
      gateway.startedAt = DateTime(2026, 9, 15);
      now = DateTime.fromMillisecondsSinceEpoch(alarm.fireAt).add(const Duration(minutes: 31));
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      final recent = await scheduler.recentEntries();
      expect(
        recent.map((entry) => (entry.alert?.id, entry.outcome)),
        containsAll([('r1', AlertOutcome.delivered), ('a1', AlertOutcome.rang)]),
      );
    });

    test("the excerpt follows the day's own description", () async {
      await seed(
        event: eventOf(
          startDate: DateTime.utc(2026, 9, 1),
          rule: const DailyRecurrence(),
        ).copyWith(
          description: '# Squat and bench\n- [ ] warm up first',
          perOccurrenceDescriptions: true,
        ),
      );
      await (await EventOccurrenceService.getInstance()).setDescription(
        'e1',
        DateTime.utc(2026, 9, 15),
        'Deadlift day\n- [ ] belt on',
      );
      await schedulerOf(
        horizon: const AlertHorizon(perAlert: 2, days: 30, total: 48),
      ).reconcileAll(AlertReconcileReason.launch);

      final byDay = {
        for (final payload in gateway.platform.values)
          payload.dayUtcMs: payload.excerpt,
      };
      expect(
        byDay[DateTime.utc(2026, 9, 15).millisecondsSinceEpoch],
        'Deadlift day',
      );
      expect(
        byDay[DateTime.utc(2026, 9, 16).millisecondsSinceEpoch],
        'Squat and bench',
      );
    });

    test('a test ring is never history', () async {
      final scheduler = schedulerOf();
      final osId = await scheduler.scheduleTestAlarm(
        title: 'Test',
        delay: const Duration(seconds: 10),
      );
      await scheduler.markFired(osId!);
      await scheduler.stop(osId);

      expect(await scheduler.recentEntries(), isEmpty);
    });
  });

  group('upcoming notice (OS-3)', () {
    test('a notice is asked for a planned alarm-tier fire, lead ahead', () async {
      await seed(
        eventAlerts: [
          alertOf(id: 'a1'),
          alertOf(id: 'r1', mode: AlertMode.notify),
        ],
      );
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final rows = await registrations();
      final alarm = rows.singleWhere((row) => row.alertId == 'a1');
      final reminder = rows.singleWhere((row) => row.alertId == 'r1');
      // The shipped lead is two hours: 18:00 → 16:00 on the occurrence day.
      expect(gateway.notices[alarm.osId], DateTime(2026, 9, 20, 16));
      // A reminder announces nothing: the notice is about an *alarm*.
      expect(gateway.notices[reminder.osId], isNull);
      expect(alarm.backend, 'fake#system:default~clock~10~n120');
      expect(reminder.backend, 'fake');
    });

    test('no notice for a snooze or a test ring, ever', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      gateway.resetCalls();

      await scheduler.snooze(armed.osId);
      final snoozed = (await registrations()).singleWhere(
        (row) => row.kind == AlertKind.snooze.name,
      );
      expect(gateway.notices, containsPair(snoozed.osId, isNull));

      gateway.resetCalls();
      final testId = await scheduler.scheduleTestAlarm(
        title: 'Test',
        delay: const Duration(seconds: 10),
      );
      expect(gateway.notices, containsPair(testId, isNull));
    });

    test('a lead of zero asks for none and still moves the signature', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      await (await SettingsService.getInstance()).setAlertNoticeLeadMinutes(0);
      await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

      // Re-armed in place with no notice: the binding takes a standing one
      // down on exactly this call, which is how turning the setting off
      // clears the notices of alarms already armed.
      expect(gateway.scheduled, hasLength(1));
      final row = (await registrations()).single;
      expect(gateway.notices, containsPair(row.osId, isNull));
      expect(row.backend, 'fake#system:default~clock~10~n0');
    });

    test('a lead already behind now asks for none', () async {
      // now is 2026-09-15 12:00; the fire is 09-20 18:00, lead 1440 → 09-19
      // 18:00, still ahead. Move the clock past it and the notice goes.
      await seed();
      await (await SettingsService.getInstance()).setAlertNoticeLeadMinutes(
        1440,
      );
      now = DateTime(2026, 9, 19, 18, 30);
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final row = (await registrations()).single;
      expect(gateway.notices, containsPair(row.osId, isNull));
    });

    test('noticeInstantFor is the one rule', () {
      final fire = PlannedFire(
        event: eventOf(),
        alert: alertOf(),
        day: DateTime.utc(2026, 9, 20),
        fireAt: DateTime(2026, 9, 20, 18),
      );
      final at = DateTime(2026, 9, 20, 12);
      expect(
        noticeInstantFor(fire: fire, leadMinutes: 120, now: at),
        DateTime(2026, 9, 20, 16),
      );
      expect(noticeInstantFor(fire: fire, leadMinutes: 0, now: at), isNull);
      expect(
        noticeInstantFor(fire: fire, leadMinutes: 120, now: DateTime(2026, 9, 20, 16)),
        isNull,
      );
      expect(
        noticeInstantFor(
          fire: PlannedFire(
            event: eventOf(),
            alert: alertOf(),
            day: DateTime.utc(2026, 9, 20),
            fireAt: DateTime(2026, 9, 20, 18),
            kind: AlertKind.snooze,
          ),
          leadMinutes: 120,
          now: at,
        ),
        isNull,
      );
      expect(
        noticeInstantFor(
          fire: PlannedFire(
            event: eventOf(),
            alert: alertOf(mode: AlertMode.notify),
            day: DateTime.utc(2026, 9, 20),
            fireAt: DateTime(2026, 9, 20, 18),
          ),
          leadMinutes: 120,
          now: at,
        ),
        isNull,
      );
    });
  });

  group('native snooze (OS-2)', () {
    AlertMove moveOf(int osId, {DateTime? at, DateTime? recorded}) => (
      osId: osId,
      nextRingAt: at ?? now.add(const Duration(minutes: 5)),
      recordedAt: recorded ?? now,
    );

    /// The moment a ring is heard: one second past the row's instant, with
    /// the ring handler's `fired` mark in place. A native Snooze can only
    /// follow a ring, and a ring only follows its instant — a move applied
    /// with the instant still ahead is a state the platform cannot produce.
    Future<void> ring(AlertScheduler scheduler, AlertRegistrationRow row) async {
      now = DateTime.fromMillisecondsSinceEpoch(
        row.fireAt,
      ).add(const Duration(seconds: 1));
      await scheduler.markFired(row.osId);
    }

    test('a move turns the armed row into a pending snooze, same os id', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      // The ring handler marked it; then the user chose the notification's
      // Snooze, which the plugin recorded as a move.
      await ring(scheduler, armed);
      final move = moveOf(armed.osId);
      gateway.moves.add(move);
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.ringHandled);

      final row = (await registrations()).single;
      expect(row.osId, armed.osId);
      expect(row.kind, AlertKind.snooze.name);
      expect(row.state, AlertRegistrationState.pending.name);
      expect(row.fireAt, move.nextRingAt.millisecondsSinceEpoch);
      expect(row.alertId, armed.alertId);
      expect(row.day, armed.day);
      expect(gateway.acknowledged, [move]);
      // The platform holds that entry already (the plugin moved it, not us),
      // so nothing is scheduled or cancelled for it.
      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled, isEmpty);
    });

    test('a duplicate (osId, recordedAt) is applied once', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      await ring(scheduler, armed);
      final move = moveOf(armed.osId);
      gateway.moves.add(move);
      await scheduler.reconcileAll(AlertReconcileReason.ringHandled);
      final first = (await registrations()).single;

      // The stream is at-least-once: the same move again, a minute later.
      now = now.add(const Duration(minutes: 1));
      gateway.moves.add(move);
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      final second = (await registrations()).single;
      expect(second.updatedAt, first.updatedAt, reason: 'no second write');
      expect(second.fireAt, first.fireAt);
      // Acknowledged both times: a marker never acknowledged is redelivered
      // on every launch until it expires.
      expect(gateway.acknowledged, hasLength(2));
    });

    test('a move for an unknown os id is acknowledged and writes nothing', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = await registrations();
      final stranger = moveOf(424242);
      gateway.moves.add(stranger);

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(await registrations(), before);
      expect(gateway.acknowledged, [stranger]);
    });

    test('an unrelated reconcile leaves the moved snooze alone', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      await ring(scheduler, armed);
      gateway.moves.add(moveOf(armed.osId));
      await scheduler.reconcileAll(AlertReconcileReason.ringHandled);
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.resumed);
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, isEmpty);
      expect(gateway.scheduled, isEmpty);
      final row = (await registrations()).single;
      expect(row.kind, AlertKind.snooze.name);
      expect(row.state, AlertRegistrationState.pending.name);
    });

    test("the moved alarm's ring settles it and re-plans the event", () async {
      await seed(
        event: eventOf(
          rule: const WeeklyRecurrence(weekdays: {1, 3, 5}),
          startDate: DateTime.utc(2026, 9, 14),
        ),
      );
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final first = (await registrations()).reduce(
        (a, b) => a.fireAt < b.fireAt ? a : b,
      );
      await ring(scheduler, first);
      gateway.moves.add(moveOf(first.osId));
      await scheduler.reconcileAll(AlertReconcileReason.ringHandled);
      gateway.resetCalls();

      // The snoozed ring comes, and is stopped from the page.
      now = now.add(const Duration(minutes: 5, seconds: 1));
      await scheduler.markFired(first.osId);
      await scheduler.stop(first.osId);

      final rows = await registrations();
      final settled = rows.singleWhere((row) => row.osId == first.osId);
      expect(settled.state, AlertRegistrationState.stopped.name);
      expect(gateway.stopped, [first.osId]);
      // Re-planned: two occurrences pending again, the stopped day not among
      // them.
      final pending = rows.where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      expect(pending, hasLength(2));
      expect(pending.map((row) => row.day), isNot(contains(first.day)));
    });

    test('a reminder registration is untouched by all of the above', () async {
      await seed(
        eventAlerts: [
          alertOf(id: 'a1'),
          alertOf(id: 'r1', mode: AlertMode.notify),
        ],
      );
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final rows = await registrations();
      final alarm = rows.singleWhere((row) => row.alertId == 'a1');
      final reminder = rows.singleWhere((row) => row.alertId == 'r1');
      await ring(scheduler, alarm);
      gateway.moves.add(moveOf(alarm.osId));
      // A stray move naming the reminder's id: the tier cannot snooze
      // natively, so it is acknowledged and ignored.
      gateway.moves.add(moveOf(reminder.osId));

      await scheduler.reconcileAll(AlertReconcileReason.ringHandled);

      final after = await registrations();
      expect(after.singleWhere((row) => row.alertId == 'r1'), reminder);
      expect(
        after.singleWhere((row) => row.alertId == 'a1').kind,
        AlertKind.snooze.name,
      );
      expect(gateway.acknowledged, hasLength(2));
    });

    test('the arm signature moves with the snooze setting, alarm tier only', () async {
      await seed(
        eventAlerts: [
          alertOf(id: 'a1'),
          alertOf(id: 'r1', mode: AlertMode.notify, offsetMinutes: 30),
        ],
      );
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      await (await SettingsService.getInstance()).setAlertSnoozeMinutes(15);
      await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

      expect(gateway.scheduled, hasLength(1));
      expect(gateway.scheduled.single.alert.id, 'a1');
      final rows = await registrations();
      expect(
        rows.singleWhere((row) => row.alertId == 'a1').backend,
        'fake#system:default~clock~15~n120',
      );
      expect(rows.singleWhere((row) => row.alertId == 'r1').backend, 'fake');
    });
  });

  group('a snooze that outlived what it postpones', () {
    Future<AlertRegistrationRow> snoozeSeeded(AlertScheduler scheduler) async {
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      now = DateTime(2026, 9, 20, 18);
      await scheduler.snooze((await registrations()).single.osId);
      gateway.resetCalls();
      return (await registrations()).firstWhere(
        (row) => row.kind == AlertKind.snooze.name,
      );
    }

    test('is cancelled once its event is deleted', () async {
      // `deleteById` hard-deletes the event's registrations, the snooze row
      // included, so the platform entry is the only trace left — and a
      // deleted event never rings.
      await seed();
      final scheduler = schedulerOf();
      final snoozed = await snoozeSeeded(scheduler);

      await events.deleteById('e1');
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, contains(snoozed.osId));
      expect(gateway.platform.containsKey(snoozed.osId), isFalse);
    });

    test('is cancelled once its alert is removed from the event', () async {
      await seed();
      final scheduler = schedulerOf();
      final snoozed = await snoozeSeeded(scheduler);

      await alerts.replaceForEvent('e1', const []);
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, contains(snoozed.osId));
      expect(
        (await registrations())
            .firstWhere((row) => row.osId == snoozed.osId)
            .state,
        AlertRegistrationState.cancelled.name,
      );
    });

    test('survives its alert being switched off', () async {
      // The hub offers Cancel snooze for that; a switch flipped for next week
      // must not swallow the ten minutes asked for now.
      await seed();
      final scheduler = schedulerOf();
      final snoozed = await snoozeSeeded(scheduler);

      await alerts.replaceForEvent('e1', [alertOf().copyWith(enabled: false)]);
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, isNot(contains(snoozed.osId)));
      expect(gateway.platform.containsKey(snoozed.osId), isTrue);
    });

    test('a test ring is never an orphan', () async {
      final scheduler = schedulerOf();
      final osId = await scheduler.scheduleTestAlarm(
        title: 'Test',
        delay: const Duration(seconds: 10),
      );
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.cancelled, isNot(contains(osId)));
    });
  });

  group('snooze without a registration', () {
    AlertPayload payloadOf({String database = 'work', int osId = 424242}) =>
        AlertPayload(
          database: database,
          eventId: 'far-event',
          alertId: 'far-alert',
          dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
          osId: osId,
          mode: AlertMode.ring,
          title: 'Standup',
          timeLabel: '09:00',
          categoryId: 'work',
          snoozeMinutes: 5,
        );

    test('always silences the ring, whatever else it can do', () async {
      // The alarm page closes after Snooze either way; returning before the
      // stop left the phone ringing with no page to stop it from.
      await schedulerOf().snooze(424242);

      expect(gateway.stopped, [424242]);
      expect(gateway.scheduled, isEmpty);
    });

    test('re-arms another database\'s alarm from its payload', () async {
      now = DateTime(2026, 9, 20, 9);
      final payload = payloadOf();

      await schedulerOf().snooze(payload.osId, payload: payload);

      expect(gateway.stopped, [payload.osId]);
      expect(gateway.scheduled.single.kind, AlertKind.snooze);
      expect(gateway.scheduled.single.fireAt, DateTime(2026, 9, 20, 9, 5));
      final armed = gateway.platform.values.single;
      // Still the other database's entry, so this database's reconcile keeps
      // its hands off it — and no row here describes an event it lacks.
      expect(armed.database, 'work');
      expect(armed.snooze, isTrue);
      expect(armed.title, 'Standup');
      expect(await registrations(), isEmpty);
    });

    test('a reconcile leaves that snooze armed', () async {
      now = DateTime(2026, 9, 20, 9);
      final payload = payloadOf();
      final scheduler = schedulerOf();
      await scheduler.snooze(payload.osId, payload: payload);
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.cancelled, isEmpty);
      expect(gateway.platform, hasLength(1));
    });
  });

  group('a ring that ended outside the app', () {
    Future<AlertPayload> ringing(AlertScheduler scheduler) async {
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final row = (await registrations()).single;
      now = DateTime(2026, 9, 15, 18);
      await scheduler.markFired(row.osId);
      gateway.resetCalls();
      return gateway.platform[row.osId]!;
    }

    Future<void> seedDaily() => seed(
      event: eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const DailyRecurrence(),
      ),
    );

    test('Stop on the notification settles it like the alarm page\'s Stop',
        () async {
      await seedDaily();
      final scheduler = schedulerOf(
        horizon: const AlertHorizon(perAlert: 1, days: 30, total: 48),
      );
      final payload = await ringing(scheduler);

      await scheduler.settleEndedRing(payload, answered: true);

      final rows = await registrations();
      expect(
        rows.firstWhere((row) => row.osId == payload.osId).state,
        AlertRegistrationState.stopped.name,
      );
      final pending = rows.where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      expect(
        pending.single.day,
        DateTime.utc(2026, 9, 16).millisecondsSinceEpoch,
        reason: 'the next occurrence is re-armed',
      );
      expect(gateway.missed, isEmpty);
    });

    test('an unanswered ring is reported, and still re-arms', () async {
      await seedDaily();
      final scheduler = schedulerOf(
        horizon: const AlertHorizon(perAlert: 1, days: 30, total: 48),
      );
      final payload = await ringing(scheduler);

      await scheduler.settleEndedRing(payload, answered: false);

      final rows = await registrations();
      expect(
        rows.firstWhere((row) => row.osId == payload.osId).state,
        AlertRegistrationState.missed.name,
      );
      expect(gateway.missed.single.osId, payload.osId);
      expect(
        rows.where((row) => row.state == AlertRegistrationState.pending.name),
        hasLength(1),
      );
    });

    test('an answered ring takes its standing snooze with it', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final original = (await registrations()).single;
      now = DateTime(2026, 9, 20, 18);
      final payload = gateway.platform[original.osId]!;
      await scheduler.snooze(original.osId);
      final snoozed = (await registrations()).firstWhere(
        (row) => row.kind == AlertKind.snooze.name,
      );
      gateway.resetCalls();

      await scheduler.settleEndedRing(payload, answered: true);

      expect(gateway.cancelled, contains(snoozed.osId));
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

  group('a Mon/Wed/Fri alarm', () {
    DateTime dayOf(AlertRegistrationRow row) =>
        DateTime.fromMillisecondsSinceEpoch(row.day, isUtc: true);

    Future<List<DateTime>> pendingDays() async => [
      for (final row in await registrations())
        if (row.state == AlertRegistrationState.pending.name) dayOf(row),
    ]..sort();

    Future<void> seedWeekly() => seed(
      event: eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const WeeklyRecurrence(
          weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
        ),
      ),
    );

    test('holds two occurrences, and Stop on the first arms the third',
        () async {
      await seedWeekly();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      expect(await pendingDays(), [
        DateTime.utc(2026, 9, 16),
        DateTime.utc(2026, 9, 18),
      ]);
      final wednesday = (await registrations()).firstWhere(
        (row) => dayOf(row) == DateTime.utc(2026, 9, 16),
      );

      now = DateTime(2026, 9, 16, 18);
      await scheduler.markFired(wednesday.osId);
      await scheduler.stop(wednesday.osId);

      expect(await pendingDays(), [
        DateTime.utc(2026, 9, 18),
        DateTime.utc(2026, 9, 21),
      ]);
      expect(gateway.platform, hasLength(2));
    });

    test('skipping a day moves its registration on, and unskip brings it back',
        () async {
      await seedWeekly();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final friday = (await registrations()).firstWhere(
        (row) => dayOf(row) == DateTime.utc(2026, 9, 18),
      );
      final skips = await EventSkipService.getInstance();

      await skips.markSkipped('e1', DateTime.utc(2026, 9, 18));
      await scheduler.reconcileEvent(
        'e1',
        AlertReconcileReason.occurrenceChanged,
      );

      expect(gateway.cancelled, contains(friday.osId));
      expect(gateway.platform.containsKey(friday.osId), isFalse);
      expect(await pendingDays(), [
        DateTime.utc(2026, 9, 16),
        DateTime.utc(2026, 9, 21),
      ]);

      await skips.unskip('e1', DateTime.utc(2026, 9, 18));
      await scheduler.reconcileEvent(
        'e1',
        AlertReconcileReason.occurrenceChanged,
      );

      expect(await pendingDays(), [
        DateTime.utc(2026, 9, 16),
        DateTime.utc(2026, 9, 18),
      ]);
    });
  });

  group('the hub', () {
    test('lists what is armed, soonest first', () async {
      await seed(
        event: eventOf(
          startDate: DateTime.utc(2026, 9, 1),
          rule: const DailyRecurrence(),
        ),
      );
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);

      final entries = await scheduler.hubEntries();

      expect(entries.map((e) => e.fireAt), [
        DateTime(2026, 9, 15, 18),
        DateTime(2026, 9, 16, 18),
      ]);
      expect(entries.every((e) => !e.isSnoozed), isTrue);
      expect(entries.first.day, DateTime.utc(2026, 9, 15));
    });

    test('a disabled alert keeps one row, so its switch stays reachable',
        () async {
      await seed(
        event: eventOf(
          startDate: DateTime.utc(2026, 9, 1),
          rule: const DailyRecurrence(),
        ),
        eventAlerts: [alertOf().copyWith(enabled: false)],
      );
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      expect(await registrations(), isEmpty);

      final entries = await scheduler.hubEntries();

      expect(entries, hasLength(1));
      expect(entries.single.alert.enabled, isFalse);
      expect(entries.single.fireAt, DateTime(2026, 9, 15, 18));
    });

    test('an alert switched off before its reconcile lands is listed once',
        () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);

      await alerts.replaceForEvent('e1', [alertOf().copyWith(enabled: false)]);
      final entries = await scheduler.hubEntries();

      expect(entries, hasLength(1));
      expect(entries.single.alert.enabled, isFalse);
    });

    test('a snooze carries both instants and the id that cancels it',
        () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      now = DateTime(2026, 9, 20, 18);
      await scheduler.snooze((await registrations()).single.osId);

      final entry = (await scheduler.hubEntries()).single;

      expect(entry.isSnoozed, isTrue);
      expect(entry.fireAt, DateTime(2026, 9, 20, 18, 10));
      expect(entry.originalFireAt, DateTime(2026, 9, 20, 18));

      await scheduler.cancelSnooze(entry.snoozeOsId!);
      expect(await scheduler.hubEntries(), isEmpty);
    });

    test('a test ring is not an event and is left out', () async {
      final scheduler = schedulerOf();
      await scheduler.scheduleTestAlarm(
        title: 'Test',
        delay: const Duration(seconds: 10),
      );

      expect(await scheduler.hubEntries(), isEmpty);
    });

    test('every turn of the chain bumps the registry revision', () async {
      await seed();
      final scheduler = schedulerOf();
      final before = AlertScheduler.registryRevision.value;

      await scheduler.reconcileAll(AlertReconcileReason.launch);

      expect(AlertScheduler.registryRevision.value, greaterThan(before));
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
