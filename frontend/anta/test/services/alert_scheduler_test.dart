import 'dart:io';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show Value;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
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
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/utils/alert_labels.dart';
import 'package:anta/utils/alert_os_id.dart';
import 'package:anta/utils/alert_planner.dart';
import 'package:anta/utils/digest_planner.dart';

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

  /// Run while the pass is waiting on this "platform" for its arm context —
  /// after it has read its clock, before it reaches its diff. Moving the
  /// test's clock here is an alarm coming due while its own pass runs.
  void Function()? onArmContextRead;

  @override
  Future<String> refreshArmContext() async {
    armContextReads++;
    onArmContextRead?.call();
    return armContext;
  }

  /// What this "platform" writes an entry's times and days with: 24-hour
  /// English, as the no-op binding answers, unless a test puts the phone on
  /// another clock or the app in another language.
  @override
  AlertLabels labels = AlertLabels.fixed;

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

  @override
  List<AlertPayload> get ringingPayloads => const [];

  @override
  Future<bool> isLockScreenUp() async => false;

  @override
  Future<bool> dismissLockScreen() async => true;

  void resetCalls() {
    scheduled.clear();
    scheduledDigests.clear();
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

  final List<PlannedDigest> scheduledDigests = [];

  @override
  Future<bool> scheduleDigest(PlannedDigest fire, AlertPayload payload) async {
    if (!accepts) return false;
    scheduledDigests.add(fire);
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
    bool linkedNote = false,
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
  late StatementCounter counter;
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
    EventDigestService.reset();
    SettingsService.reset();
  }

  setUp(() async {
    resetSingletons();
    // Counted only where a case asks: what one pass reads, as text.
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    gateway = FakeAlertGateway();
    SettingsService.forTesting(db);
    events = await CalendarEventService.forTesting(db);
    alerts = await EventAlertService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventOccurrenceService.forTesting(db);
    await CategoryService.forTesting(db);
    await EventDigestService.forTesting(db);
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
      expect(rows.single.day, DateTime.utc(2026, 9, 20).millisecondsSinceEpoch);
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

    test(
      'the platform is asked once per pass what a ring is armed under',
      () async {
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
      },
    );

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

    test('a moved arm context re-arms standing reminders too', () async {
      // The app switched to German while it was away. A reminder's words are
      // frozen into its platform entry when it is armed, and its signature is
      // the context and nothing more — so the context moving is the only
      // thing that can reach one already standing in the old language.
      await seed(eventAlerts: [alertOf(mode: AlertMode.notify)]);
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = (await registrations()).single;
      expect(before.backend, 'fake', reason: 'signed with the bare context');
      gateway.resetCalls();

      gateway.armContext = 'fake.de';
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.scheduled, hasLength(1));
      expect(gateway.scheduled.single.alert.mode, AlertMode.notify);
      final row = (await registrations()).single;
      expect(row.osId, before.osId, reason: 're-armed in place, not re-issued');
      expect(row.backend, 'fake.de');

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
      await (db.update(
        db.alertRegistrations,
      )..where((row) => row.osId.equals(before.osId))).write(
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

    test(
      'a changed alarm sound re-arms without anything dispatching',
      () async {
        await seed();
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        gateway.resetCalls();

        // What the Calendar settings row writes. The event is untouched, so the
        // fast path is all that stands between the user's choice and an alarm
        // that still rings the old sound.
        await (await SettingsService.getInstance()).setAlertSound(
          'content://media/7',
        );
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
      },
    );

    test('a reminder is not re-armed by a sound it cannot play', () async {
      // The reminder tier plays through a notification channel whose sound
      // Android froze at creation, so the setting can never change what one
      // does — and re-arming it would be work for nothing.
      await seed(eventAlerts: [alertOf(mode: AlertMode.notify)]);
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      await (await SettingsService.getInstance()).setAlertSound(
        'system:default',
      );
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

      await events.upsert(eventOf(time: const EventTime(startMinute: 19 * 60)));
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
      expect(gateway.scheduled.map((fire) => fire.event.id).toSet(), {'e1'});
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

    test(
      'a refused schedule records nothing, so the next pass retries',
      () async {
        await seed();
        gateway.accepts = false;
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        expect(await registrations(), isEmpty);

        gateway.accepts = true;
        await scheduler.reconcileAll(AlertReconcileReason.resumed);
        expect(await registrations(), hasLength(1));
      },
    );

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

    test('"Delete all events" cancels the entries it leaves behind', () async {
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;
      gateway.resetCalls();
      SyncBindingService.forTesting(db, await SettingsService.getInstance());
      addTearDown(SyncBindingService.reset);

      // The wipe runs from the settings page, below every bloc, so nothing
      // else asks for the pass — and until it does the phone still rings for
      // events that no longer exist.
      await events.tombstoneAll();
      await pumpEventQueue();

      expect(gateway.cancelled, contains(osId));
      expect(gateway.platform, isEmpty);
      expect(await registrations(), isEmpty);
    });
  });

  group('an alarm that comes due while its own pass runs', () {
    // A pass reads its clock once, at its top, and then waits on a dozen
    // things — the facades, the plugin's own start, the arm context — before
    // its diff. An entry whose instant passes in between is still "planned"
    // to that diff, and when its token has moved the diff used to arm it
    // again: over a ring that had just started. The plugin stops the ring it
    // replaces, the binding reads that as a Stop on the notification, and an
    // alarm nobody answered was settled as acknowledged — its page closed,
    // an event set to go after its alarm removed — while it started again
    // with no page.
    final due = DateTime(2026, 9, 20, 18);
    final aSecondBefore = DateTime(2026, 9, 20, 17, 59, 59);
    final aSecondAfter = DateTime(2026, 9, 20, 18, 0, 1);

    /// Arms the seeded alarm days ahead, as any earlier pass would have.
    Future<AlertRegistrationRow> armed(AlertScheduler scheduler) async {
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final row = (await registrations()).single;
      gateway.resetCalls();
      return row;
    }

    Future<void> expectLeftAlone(AlertRegistrationRow before) async {
      expect(gateway.scheduled, isEmpty, reason: 'armed over its own ring');
      expect(gateway.cancelled, isEmpty);
      expect(gateway.stopped, isEmpty);
      expect(gateway.platform.containsKey(before.osId), isTrue);
      // Still the ring handler's to settle, under the token it was armed
      // with: nothing reads a token once its instant is behind.
      expect(await registrations(), [before]);
      expect(before.state, AlertRegistrationState.pending.name);
    }

    test(
      'is left alone, though everything it was armed under has moved',
      () async {
        // The first pass of a build that changed what an entry says, or the
        // phone's volume across the floor: every token differs.
        await seed();
        final scheduler = schedulerOf();
        final before = await armed(scheduler);

        now = aSecondBefore;
        gateway.armContext = 'fake@floor';
        gateway.onArmContextRead = () => now = aSecondAfter;
        await scheduler.reconcileAll(AlertReconcileReason.resumed);

        await expectLeftAlone(before);
        expect(before.backend, 'fake#system:default~clock~10~n120');
      },
    );

    test(
      "is left alone by its own event's pass, which arms unconditionally",
      () async {
        await seed();
        final scheduler = schedulerOf();
        final before = await armed(scheduler);

        now = aSecondBefore;
        gateway.onArmContextRead = () => now = aSecondAfter;
        await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

        await expectLeftAlone(before);
      },
    );

    test('is left alone once the binding says it is ringing, whatever the '
        'clock reads', () async {
      await seed();
      final scheduler = schedulerOf();
      final before = await armed(scheduler);

      gateway.ringingNow.add(before.osId);
      gateway.armContext = 'fake@floor';
      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      await expectLeftAlone(before);
    });

    test('is armed all the same when nothing was ever armed for it', () async {
      // No registration, so nothing is being delivered: the platform holds
      // no entry a ring could come from, and skipping would leave an alarm
      // that never rings at all.
      await seed();
      now = aSecondBefore;
      gateway.onArmContextRead = () => now = aSecondAfter;

      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.scheduled.single.fireAt, due);
      final row = (await registrations()).single;
      expect(row.state, AlertRegistrationState.pending.name);
      expect(row.fireAt, due.millisecondsSinceEpoch);
    });

    test(
      'is armed all the same when an edit has just moved it there',
      () async {
        // What stands on the platform is the old instant, half an hour away:
        // the new one is ringing nowhere, and passing by mid-pass is no reason
        // to leave the alarm armed for a time the event no longer has.
        await seed();
        final scheduler = schedulerOf();
        final before = await armed(scheduler);
        final moved = DateTime(2026, 9, 20, 17, 30);

        now = moved.subtract(const Duration(seconds: 1));
        await events.upsert(
          eventOf(time: const EventTime(startMinute: 17 * 60 + 30)),
        );
        gateway.onArmContextRead = () {
          now = moved.add(const Duration(seconds: 1));
        };
        await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

        expect(gateway.scheduled.single.fireAt, moved);
        final row = (await registrations()).single;
        expect(row.osId, before.osId);
        expect(row.fireAt, moved.millisecondsSinceEpoch);
      },
    );
  });

  group('an occurrence moved later while it rings', () {
    // A ring's row is `fired` from its first second, so the diff holds no
    // registration for it, and a plan that has the occurrence again later
    // the same day — its time edited while it rings, from a calendar opened
    // over a second alarm's page — took the deterministic id, the ringing
    // one. Arming over a ring stops it, and the binding reads that as a Stop
    // on the notification: the page closed, the session chip posted, an
    // event set to go after its alarm removed, with nobody answering.
    final due = DateTime(2026, 9, 20, 18);
    final moved = DateTime(2026, 9, 20, 18, 30);

    /// Arms the seeded alarm, has it ring for half a minute — the ring
    /// handler's `fired` mark in place — and moves its event half an hour
    /// later.
    Future<AlertRegistrationRow> ringingThenMoved(
      AlertScheduler scheduler,
    ) async {
      await seed();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      await scheduler.markFired(armed.osId);
      now = due.add(const Duration(seconds: 30));
      await events.upsert(
        eventOf(time: const EventTime(startMinute: 18 * 60 + 30)),
      );
      gateway.resetCalls();
      return armed;
    }

    test('is armed under an id of its own, the ring left as it was', () async {
      final scheduler = schedulerOf();
      final armed = await ringingThenMoved(scheduler);
      gateway.ringingNow.add(armed.osId);
      final standing = gateway.platform[armed.osId];

      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      final rows = await registrations();
      expect(
        rows.singleWhere((row) => row.osId == armed.osId).state,
        AlertRegistrationState.fired.name,
      );
      expect(gateway.platform[armed.osId], standing);
      expect(gateway.cancelled, isEmpty);
      expect(gateway.stopped, isEmpty);
      // Still armed, so Stop on the ring leaves the new time standing.
      expect(gateway.scheduled.single.fireAt, moved);
      final next = rows.singleWhere((row) => row.osId != armed.osId);
      expect(next.state, AlertRegistrationState.pending.name);
      expect(next.fireAt, moved.millisecondsSinceEpoch);
      expect(next.alertId, armed.alertId);
      expect(next.day, armed.day);
      expect(gateway.platform.containsKey(next.osId), isTrue);
    });

    test('is armed under an id of its own while the ring\'s row is fired, '
        'though nothing rings there', () async {
      // A `fired` row whose id no longer rings is a ring nothing has settled
      // yet — above all one snoozed on its heads-up whose move the next pass
      // writes down, the plugin holding the alarm under that id, moved.
      // Armed over, the snoozed alarm was replaced: the snooze never rang,
      // and once the move was written onto the re-armed row the occurrence
      // was armed a second time and rang twice.
      final scheduler = schedulerOf();
      final armed = await ringingThenMoved(scheduler);
      final standing = gateway.platform[armed.osId];
      counter.reset();

      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      final rows = await registrations();
      expect(
        rows.singleWhere((row) => row.osId == armed.osId).state,
        AlertRegistrationState.fired.name,
      );
      expect(gateway.platform[armed.osId], standing);
      expect(gateway.cancelled, isEmpty);
      expect(gateway.scheduled.single.fireAt, moved);
      final next = rows.singleWhere((row) => row.osId != armed.osId);
      expect(next.state, AlertRegistrationState.pending.name);
      expect(next.fireAt, moved.millisecondsSinceEpoch);
      expect(gateway.platform.containsKey(next.osId), isTrue);
      // The pass needed the fired rows twice — for the fresh id, and when
      // the stray sweep reached the ring's own entry — and read them once.
      expect(
        counter.matching("state = 'fired'"),
        hasLength(1),
        reason: 'Issued:\n${counter.statements.join('\n')}',
      );
    });

    test("is armed under the ring's id once the ring is over", () async {
      final scheduler = schedulerOf();
      final armed = await ringingThenMoved(scheduler);
      await scheduler.stop(armed.osId);
      gateway.resetCalls();

      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.scheduled.single.fireAt, moved);
      final row = (await registrations()).single;
      expect(row.osId, armed.osId);
      expect(row.state, AlertRegistrationState.pending.name);
      expect(row.fireAt, moved.millisecondsSinceEpoch);
    });
  });

  group('OS truth', () {
    test(
      'a registry row the platform forgot is dropped and re-armed',
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
      },
    );

    test(
      'a platform entry the registry lost is cancelled (the import wipe)',
      () async {
        await seed();
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        final osId = (await registrations()).single.osId;

        // The backup import's hard wipe empties the registry while the OS
        // keeps its entries.
        await db.alertRegistrationDao.deleteAll();
        await alerts.deleteAll();
        await events.importData(const []);
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
      now = DateTime(2026, 9, 20, 0, fireAt).add(lateness);
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
        expect(
          (await rowOf(armed.osId)).state,
          AlertRegistrationState.pending.name,
        );
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
          // Written from the registry row, and stamped like the entry it
          // reports on: with the instant it was due at, not the one it was
          // found missing at.
          expect(
            gateway.missed.single.fireAtMs,
            DateTime(2026, 9, 20, 18).millisecondsSinceEpoch,
          );
          expect(gateway.missed.single.whenLabel, '');
          expect(
            gateway.missed.single.tintValue,
            CalendarCategories.resolve('gym').colorValue,
          );
          expect(gateway.missed.single.glyphKey, 'fitness_center');
          expect(gateway.missed.single.languageCode, 'en');
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

        expect(
          (await rowOf(armed.osId)).state,
          AlertRegistrationState.cancelled.name,
        );
        expect(gateway.missed, isEmpty);
      });
    }

    test(
      'an alarm held back behind another ring is in flight past the grace',
      () async {
        // The `alarm` host rings one alarm at a time: this one came due while
        // another sounded and waits in its queue, silent, for as long as that
        // ring lasts — which, for a ring sounding natively with no Dart up, has
        // no end. The host runs in the app's process, so the process was alive
        // at this alarm's instant, and the delivery evidence alone would read
        // the row as rung and cancel the entry out of the queue.
        await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
        gateway.startedAt = DateTime(2026, 9, 20, 17, 59, 58);
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        final held = (await registrations()).single;
        // Another alarm sounding: another event's, or another database's.
        gateway.ringingNow.add(held.osId + 1);
        gateway.resetCalls();

        // The app opened from that ring's heads-up, 31 minutes on.
        now = DateTime(2026, 9, 20, 0, fireAt).add(const Duration(minutes: 31));
        await scheduler.reconcileAll(AlertReconcileReason.launch);

        expect(
          (await rowOf(held.osId)).state,
          AlertRegistrationState.pending.name,
        );
        expect(gateway.cancelled, isEmpty);
        expect(gateway.missed, isEmpty);
        expect(
          gateway.platform.containsKey(held.osId),
          isTrue,
          reason: 'it rings when the ring in front of it ends',
        );
      },
    );

    test('with nothing ringing, the same alarm is settled as before', () async {
      await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
      gateway.startedAt = DateTime(2026, 9, 20, 17, 59, 58);

      final armed = await runLate(schedulerOf(), const Duration(minutes: 31));

      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.fired.name,
      );
      expect(gateway.cancelled, [armed.osId]);
      expect(gateway.missed, isEmpty);
    });

    test(
      'a reminder delivered more than a day ago is cleared from the shade',
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
      },
    );

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

    test('a process alive at the fire instant proves the alarm rang', () async {
      // The app's process already running when the alarm came due, kept in
      // the background with no engine: Android shows the ring as a heads-up,
      // the user stops it from there, and no Dart runs to mark the row. A
      // process alive at the instant was neither force-stopped nor switched
      // off, so the alarm was delivered.
      await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
      gateway.startedAt = DateTime(2026, 9, 20, 17, 59, 58);

      final armed = await runLate(schedulerOf(), const Duration(minutes: 40));

      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.fired.name,
      );
      expect(gateway.missed, isEmpty);
    });

    test('a process the alarm itself started proves it rang too', () async {
      // No process running when the alarm came due: its broadcast is what
      // started one, a moment after the instant. The ring is a heads-up, the
      // user stops it there with no engine attached to hear it, and nothing
      // durable records the Stop — this process coming up just after the
      // instant is the only trace of the delivery.
      await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
      gateway.startedAt = DateTime(
        2026,
        9,
        20,
        0,
        fireAt,
      ).add(const Duration(milliseconds: 150));

      final armed = await runLate(schedulerOf(), const Duration(minutes: 31));

      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.fired.name,
      );
      expect(gateway.missed, isEmpty);
    });

    test(
      'a process that came up past the delivery window proves nothing',
      () async {
        // The window is the delivery's latency and no more: a second past it
        // the process is the user's own launch, as the case below.
        await seed(eventAlerts: [alertOf(mode: AlertMode.ring)]);
        gateway.startedAt = DateTime(
          2026,
          9,
          20,
          0,
          fireAt,
        ).add(kRingStartGrace + const Duration(seconds: 1));

        final armed = await runLate(schedulerOf(), const Duration(minutes: 31));

        expect(
          (await rowOf(armed.osId)).state,
          AlertRegistrationState.missed.name,
        );
        expect(gateway.missed, hasLength(1));
      },
    );

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
      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.fired.name,
      );
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
      expect(
        (await rowOf(armed.osId)).state,
        AlertRegistrationState.cancelled.name,
      );
    });

    test(
      'a recurring event re-arms the next occurrence after a late fire',
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
        expect(
          pending.single.day,
          DateTime.utc(2026, 9, 16).millisecondsSinceEpoch,
        );
      },
    );
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
      // Stamped for its own instant — and, its due time no longer being the
      // event's, saying when the event itself is.
      final payload = gateway.platform[snoozed.osId]!;
      expect(
        payload.fireAtMs,
        DateTime(2026, 9, 20, 18, 10).millisecondsSinceEpoch,
      );
      expect(payload.timeLabel, '18:10');
      expect(payload.whenLabel, '18:00');
      expect(payload.reRing, isFalse);
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
        (await registrations())
            .singleWhere((row) => row.osId == armed.osId)
            .state,
        AlertRegistrationState.missed.name,
      );
      expect(gateway.missed, hasLength(1));
    });

    test(
      'recentEntries lists what settled, newest first, cancelled left out',
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
        now = DateTime.fromMillisecondsSinceEpoch(
          first.fireAt,
        ).add(const Duration(seconds: 1));
        await scheduler.markFired(first.osId);
        await scheduler.stop(first.osId);
        // Then a snooze, settled by its own ring being stopped.
        final after = await registrations();
        final next = after.firstWhere((row) => row.osId == second.osId);
        now = DateTime.fromMillisecondsSinceEpoch(
          next.fireAt,
        ).add(const Duration(seconds: 1));
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
      },
    );

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

    test(
      'a delivered reminder reads delivered, and a ring in progress is not history',
      () async {
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
        now = DateTime.fromMillisecondsSinceEpoch(
          alarm.fireAt,
        ).add(const Duration(seconds: 5));
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
        now = DateTime.fromMillisecondsSinceEpoch(
          alarm.fireAt,
        ).add(const Duration(minutes: 31));
        await scheduler.reconcileAll(AlertReconcileReason.resumed);

        final recent = await scheduler.recentEntries();
        expect(
          recent.map((entry) => (entry.alert?.id, entry.outcome)),
          containsAll([
            ('r1', AlertOutcome.delivered),
            ('a1', AlertOutcome.rang),
          ]),
        );
      },
    );

    test("the excerpt follows the day's own description", () async {
      await seed(
        event:
            eventOf(
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
    test(
      'a notice is asked for a planned alarm-tier fire, lead ahead',
      () async {
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
      },
    );

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

    test(
      'a lead of zero asks for none and still moves the signature',
      () async {
        await seed();
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        gateway.resetCalls();

        await (await SettingsService.getInstance()).setAlertNoticeLeadMinutes(
          0,
        );
        await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

        // Re-armed in place with no notice: the binding takes a standing one
        // down on exactly this call, which is how turning the setting off
        // clears the notices of alarms already armed.
        expect(gateway.scheduled, hasLength(1));
        final row = (await registrations()).single;
        expect(gateway.notices, containsPair(row.osId, isNull));
        expect(row.backend, 'fake#system:default~clock~10~n0');
      },
    );

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
        noticeInstantFor(
          fire: fire,
          leadMinutes: 120,
          now: DateTime(2026, 9, 20, 16),
        ),
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
    Future<void> ring(
      AlertScheduler scheduler,
      AlertRegistrationRow row,
    ) async {
      now = DateTime.fromMillisecondsSinceEpoch(
        row.fireAt,
      ).add(const Duration(seconds: 1));
      await scheduler.markFired(row.osId);
    }

    test(
      'a move turns the armed row into a pending snooze, same os id',
      () async {
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
      },
    );

    test('a Snooze on the heads-up while a pass is out is left to the next '
        'pass, which writes it down', () async {
      // The move reaches the registry only through the drain at the top of a
      // pass. A pass already past it when the Snooze lands finds the alarm
      // still on the platform — moved, under the payload it was armed with —
      // with its row `fired`, the ring gone from the binding's set and
      // nothing planned for it: to the stray sweep, an entry nobody holds.
      // Cancelled there, the move then met a cancelled row and was
      // acknowledged away, and the snooze never rang.
      await seed();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final armed = (await registrations()).single;
      await scheduler.markFired(armed.osId);
      gateway.ringingNow.add(armed.osId);
      now = DateTime.fromMillisecondsSinceEpoch(
        armed.fireAt,
      ).add(const Duration(minutes: 1));
      gateway.resetCalls();
      late AlertMove move;
      gateway.onArmContextRead = () {
        gateway.ringingNow.remove(armed.osId);
        move = moveOf(armed.osId);
        gateway.moves.add(move);
      };

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.cancelled, isNot(contains(armed.osId)));
      expect(gateway.platform.containsKey(armed.osId), isTrue);
      expect(
        (await registrations()).single.state,
        AlertRegistrationState.fired.name,
      );

      // The pass the snoozed ending provokes.
      gateway.onArmContextRead = null;
      await scheduler.reconcileAll(AlertReconcileReason.ringHandled);

      final row = (await registrations()).single;
      expect(row.osId, armed.osId);
      expect(row.kind, AlertKind.snooze.name);
      expect(row.state, AlertRegistrationState.pending.name);
      expect(row.fireAt, move.nextRingAt.millisecondsSinceEpoch);
      expect(gateway.acknowledged, [move]);
      expect(gateway.platform.containsKey(armed.osId), isTrue);
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

    test(
      'a move for an unknown os id is acknowledged and writes nothing',
      () async {
        await seed();
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        final before = await registrations();
        final stranger = moveOf(424242);
        gateway.moves.add(stranger);

        await scheduler.reconcileAll(AlertReconcileReason.resumed);

        expect(await registrations(), before);
        expect(gateway.acknowledged, [stranger]);
      },
    );

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

    test(
      'the arm signature moves with the snooze setting, alarm tier only',
      () async {
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
      },
    );
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

    /// What the alarm page hands Snooze for an alarm a labelled build armed:
    /// everything [payloadOf] carries, plus what the event that stands in for
    /// it on the platform call has no field for.
    AlertPayload stampedOf({String database = 'work'}) => AlertPayload(
      database: database,
      eventId: 'far-event',
      alertId: 'far-alert',
      dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
      osId: 424242,
      mode: AlertMode.ring,
      title: 'Standup',
      timeLabel: '09:00',
      colorValue: 0xFF00897B,
      tintIcon: false,
      iconKey: 'alarm',
      categoryId: 'work',
      removeAfterAlert: true,
      snoozeMinutes: 5,
      excerpt: 'Bring the laptop.',
      fireAtMs: DateTime(2026, 9, 20, 9).millisecondsSinceEpoch,
      reRing: true,
      tintValue: 0xFF757575,
      glyphKey: 'alarm',
      languageCode: 'en',
      iconFile: '/data/alert_icons/alarm_ff757575.png',
    );

    test('the snooze is the ringing payload, with only the new instant '
        'restamped', () async {
      now = DateTime(2026, 9, 20, 9, 0, 20);
      final ringing = stampedOf();

      await schedulerOf().snooze(ringing.osId, payload: ringing);

      final armed = gateway.platform.values.single;
      // The whole list of what changes: the id it is armed under, the snooze
      // flag, the new instant and its clock label, the re-ring mark gone,
      // and the old due time — the event's own, or the entry would have said
      // otherwise — kept as the event's time. Everything else is as it rang.
      expect(
        armed,
        ringing.copyWith(
          osId: armed.osId,
          snooze: true,
          fireAtMs: DateTime(2026, 9, 20, 9, 5, 20).millisecondsSinceEpoch,
          timeLabel: '09:05',
          reRing: false,
          whenLabel: '09:00',
        ),
      );
      expect(armed.osId, isNot(ringing.osId));
      // Spelled out: these three are what the rebuild used to drop, because
      // the stand-in event has no description, no time and no tint flag.
      expect(armed.tintIcon, isFalse);
      expect(armed.excerpt, 'Bring the laptop.');
      expect(armed.whenLabel, '09:00');
      expect(gateway.scheduled.single.fireAt, DateTime(2026, 9, 20, 9, 5, 20));
      expect(await registrations(), isEmpty);
    });

    test('an event time the entry already carries is not replaced', () async {
      // A "15 minutes before" alarm: its due time was never the event's.
      now = DateTime(2026, 9, 20, 9, 0, 20);
      final ringing = stampedOf().copyWith(whenLabel: '09:15 – 10:00');

      await schedulerOf().snooze(ringing.osId, payload: ringing);

      expect(gateway.platform.values.single.whenLabel, '09:15 – 10:00');
      expect(gateway.platform.values.single.timeLabel, '09:05');
    });

    test('the shape the entry was armed in is handed on as it came', () async {
      // Whether an entry's notification was armed in the app's group is the
      // platform binding's to decide and to stamp. A snooze made from the
      // payload is a copy: it neither sets the mark nor drops it.
      now = DateTime(2026, 9, 20, 9, 0, 20);
      final ringing = stampedOf().copyWith(grouped: true);

      await schedulerOf().snooze(ringing.osId, payload: ringing);

      expect(gateway.platform.values.single.grouped, isTrue);
      expect(
        gateway.platform.values.single,
        ringing.copyWith(
          osId: gateway.platform.values.single.osId,
          snooze: true,
          fireAtMs: DateTime(2026, 9, 20, 9, 5, 20).millisecondsSinceEpoch,
          timeLabel: '09:05',
          reRing: false,
          whenLabel: '09:00',
        ),
      );
    });

    test('an entry armed before the labels existed gains its instant, and '
        'nothing it never knew', () async {
      now = DateTime(2026, 9, 20, 9, 0, 20);
      final ringing = payloadOf();
      final scheduler = schedulerOf();

      await scheduler.snooze(ringing.osId, payload: ringing);

      final armed = gateway.platform.values.single;
      expect(
        armed,
        ringing.copyWith(
          osId: armed.osId,
          snooze: true,
          fireAtMs: DateTime(2026, 9, 20, 9, 5, 20).millisecondsSinceEpoch,
          timeLabel: '09:05',
        ),
      );
      // Its old due time is not known to be the event's — it may have been
      // "10 minutes before" — so it is not passed off as that.
      expect(armed.whenLabel, '');
      expect(armed.languageCode, isNull);
      expect(armed.tintValue, isNull);

      // Nor on the snooze after it, which now carries an instant: it still
      // names no language, and that is what says nobody wrote its lines.
      now = DateTime(2026, 9, 20, 9, 5, 30);
      await scheduler.snooze(armed.osId, payload: armed);

      final again = gateway.platform.values.single;
      expect(again.timeLabel, '09:10');
      expect(
        again.fireAtMs,
        DateTime(2026, 9, 20, 9, 10, 30).millisecondsSinceEpoch,
      );
      expect(again.whenLabel, '');
    });

    test('a ring of this database whose registration is gone is snoozed the '
        'same way, for as long as the setting says, and recorded', () async {
      now = DateTime(2026, 9, 20, 9, 0, 20);
      final ringing = stampedOf(database: 'gym_notes');

      await schedulerOf().snooze(ringing.osId, payload: ringing);

      final armed = gateway.platform.values.single;
      // This database's settings are open, so the snooze is as long as they
      // say — ten minutes, not the five the entry was armed with — and the
      // entry offers that length from now on.
      expect(
        armed,
        ringing.copyWith(
          osId: armed.osId,
          snooze: true,
          snoozeMinutes: 10,
          fireAtMs: DateTime(2026, 9, 20, 9, 10, 20).millisecondsSinceEpoch,
          timeLabel: '09:10',
          reRing: false,
          whenLabel: '09:00',
        ),
      );
      final row = (await registrations()).single;
      expect(row.osId, armed.osId);
      expect(row.kind, AlertKind.snooze.name);
      expect(row.eventId, 'far-event');
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

    test(
      'Stop on the notification settles it like the alarm page\'s Stop',
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
      },
    );

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
    test(
      'marks the registration stopped and arms the next occurrence',
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
      },
    );

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
    // Every locale's date tables, for the whole group. With none loaded, a
    // label that needs them is left out or falls back: a line that names a
    // day comes out empty and a time on the neutral 24-hour clock — which
    // German's own clock reads the same as, so for German only a line with a
    // day in it can tell the tables from their absence.
    setUpAll(initializeDateFormatting);

    test('carries the database, the event and the fire time', () async {
      await seed(event: eventOf(removeAfterAlert: true));
      await schedulerOf(
        database: 'work',
      ).reconcileAll(AlertReconcileReason.launch);

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
      // What the entry says about itself beyond its identity, resolved when
      // it is armed so that no surface has to open a database to draw it.
      expect(
        payload.fireAtMs,
        DateTime(2026, 9, 20, 18).millisecondsSinceEpoch,
      );
      // An alert at the event's start: the event's own time would only
      // repeat the due time.
      expect(payload.whenLabel, '');
      expect(payload.tintValue, CalendarCategories.resolve('gym').colorValue);
      expect(payload.glyphKey, 'fitness_center');
      expect(payload.languageCode, 'en');
      // Never armed into an entry: only a ring report can say it.
      expect(payload.reRing, isFalse);
      expect(payload.iconFile, isNull);
      // Round-trips through the wire form the platform actually stores.
      expect(AlertPayload.decode(payload.encode()), payload);
    });

    test('says nothing of the notification group, on either tier', () async {
      // Which Android the phone runs is not the plan's to know: the platform
      // binding decides whether a reminder is armed in the app's group, and
      // stamps the entry it arms.
      await seed(
        eventAlerts: [
          alertOf(),
          alertOf(id: 'a2', mode: AlertMode.notify, offsetMinutes: 10),
        ],
      );
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.platform.values, hasLength(2));
      for (final payload in gateway.platform.values) {
        expect(payload.grouped, isFalse, reason: payload.mode.name);
        expect(
          payload.toJson().containsKey('grp'),
          isFalse,
          reason: payload.mode.name,
        );
      }
    });

    test("an alert ahead of its event carries the event's own time", () async {
      await seed(eventAlerts: [alertOf(offsetMinutes: 30)]);
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final payload = gateway.platform.values.single;
      expect(payload.timeLabel, '17:30');
      expect(
        payload.fireAtMs,
        DateTime(2026, 9, 20, 17, 30).millisecondsSinceEpoch,
      );
      expect(payload.whenLabel, '18:00');
    });

    test('an event with an end carries its range, even at its start', () async {
      await seed(
        event: eventOf(
          time: const EventTime(startMinute: 18 * 60, durationMinutes: 90),
        ),
      );
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final payload = gateway.platform.values.single;
      expect(payload.timeLabel, '18:00');
      expect(payload.whenLabel, '18:00 – 19:30');
    });

    test('an all-day event alerted the day before names its day', () async {
      // Due on Saturday the 19th at the 09:00 default, for Sunday's event.
      await seed(
        event: eventOf(time: null),
        eventAlerts: [
          const EventAlert(
            id: 'a1',
            eventId: 'e1',
            mode: AlertMode.ring,
            daysBefore: 1,
          ),
        ],
      );
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final payload = gateway.platform.values.single;
      expect(payload.timeLabel, '09:00');
      expect(payload.fireAtMs, DateTime(2026, 9, 19, 9).millisecondsSinceEpoch);
      expect(payload.whenLabel, 'Sun, Sep 20 · All day');
      expect(payload.dayUtc, DateTime.utc(2026, 9, 20));
    });

    test("the colour and the icon are the avatar's own", () async {
      // An event with a colour of its own that does not tint its icon, and an
      // icon of its own: the avatar wears the category's colour around the
      // event's glyph, and the payload says exactly that.
      await seed(
        event: eventOf().copyWith(
          colorValue: 0xFFFF5722,
          tintIcon: false,
          iconKey: 'alarm',
        ),
      );
      await events.upsert(
        eventOf(id: 'e2', title: 'Swim').copyWith(colorValue: 0xFFFF5722),
      );
      await alerts.replaceForEvent('e2', [alertOf(id: 'b1', eventId: 'e2')]);
      await events.upsert(
        eventOf(id: 'e3', title: 'Run').copyWith(iconKey: 'no_such_icon'),
      );
      await alerts.replaceForEvent('e3', [alertOf(id: 'c1', eventId: 'e3')]);
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final byEvent = {
        for (final payload in gateway.platform.values) payload.eventId: payload,
      };
      final category = CalendarCategories.resolve('gym');
      expect(byEvent['e1']!.tintValue, category.colorValue);
      expect(byEvent['e1']!.glyphKey, 'alarm');
      // What every reader used to compute for itself is carried untouched
      // beside it, for the builds and the entries that still do.
      expect(byEvent['e1']!.colorValue, 0xFFFF5722);
      expect(byEvent['e1']!.tintIcon, isFalse);
      expect(byEvent['e1']!.iconKey, 'alarm');
      // A colour that does tint the icon is the avatar's colour.
      expect(byEvent['e2']!.tintValue, 0xFFFF5722);
      expect(byEvent['e2']!.glyphKey, category.iconKey);
      // An icon key that names nothing falls to the category's, as the row
      // in the day panel does.
      expect(byEvent['e3']!.glyphKey, category.iconKey);
      expect(byEvent['e3']!.iconKey, 'no_such_icon');
    });

    test("the lines are written by the binding's labels", () async {
      // A phone on the 12-hour clock, the app in German: the scheduler knows
      // neither, and stamps whatever its gateway's labels write.
      gateway.labels = AlertLabels(
        strings: lookupAppLocalizations(const Locale('de')),
        use24Hour: false,
      );
      await seed(event: eventOf(time: null));
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final payload = gateway.platform.values.single;
      expect(payload.languageCode, 'de');
      expect(payload.whenLabel, 'Ganztägig');
      // German writes no day period, so its due time is 24-hour on any phone.
      expect(payload.timeLabel, '09:00');
    });

    test("a German day name is written with German's tables", () async {
      // The case above cannot tell German's tables from none: "Ganztägig"
      // needs no table, and "09:00" is both German's clock and the neutral
      // fallback. A day name comes from the table or not at all. Due on
      // Saturday the 19th at the 09:00 default, for Sunday's event.
      gateway.labels = AlertLabels(
        strings: lookupAppLocalizations(const Locale('de')),
        use24Hour: false,
      );
      await seed(
        event: eventOf(time: null),
        eventAlerts: [
          const EventAlert(
            id: 'a1',
            eventId: 'e1',
            mode: AlertMode.ring,
            daysBefore: 1,
          ),
        ],
      );
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final payload = gateway.platform.values.single;
      expect(payload.whenLabel, 'So., 20. Sept. · Ganztägig');
      expect(payload.timeLabel, '09:00');
    });

    test("the due time is written on the phone's clock too", () async {
      // Until the arm context named the clock style this one label stayed on
      // a neutral 24-hour skeleton, whatever the binding's labels wrote.
      gateway.labels = AlertLabels(
        strings: lookupAppLocalizations(const Locale('en')),
        use24Hour: false,
      );
      await seed(eventAlerts: [alertOf(offsetMinutes: 30)]);
      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final payload = gateway.platform.values.single;
      expect(payload.timeLabel, '5:30 PM');
      expect(payload.whenLabel, '6:00 PM');
      expect(
        payload.fireAtMs,
        DateTime(2026, 9, 20, 17, 30).millisecondsSinceEpoch,
      );
    });
  });

  group('a test ring', () {
    test(
      'is stamped with a tint and a glyph of its own, and no event time',
      () async {
        final scheduler = schedulerOf();
        final osId = await scheduler.scheduleTestAlarm(
          title: 'Test alarm in 10 s',
          delay: const Duration(seconds: 10),
        );

        final payload = gateway.platform[osId]!;
        expect(payload.isTest, isTrue);
        // The fallback category's grey is the one avatar that all but vanishes
        // on the dark ground, so a test ring takes the app's own colour.
        expect(payload.tintValue, AppTheme.lightScheme.primary.toARGB32());
        expect(payload.glyphKey, 'alarm');
        // Its stand-in event has no time, and would otherwise read "All day".
        expect(payload.whenLabel, '');
        expect(
          payload.fireAtMs,
          now.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
        );
        expect(payload.languageCode, 'en');
        // Nothing an older reader draws from has moved: no colour of its own,
        // the fallback category, the title it was armed with.
        expect(payload.colorValue, isNull);
        expect(payload.iconKey, isNull);
        expect(payload.categoryId, CalendarCategories.fallback.id);
        expect(payload.title, 'Test alarm in 10 s');
        expect(payload.timeLabel, '12:00');
      },
    );

    test('and so is its snooze', () async {
      final scheduler = schedulerOf();
      final osId = await scheduler.scheduleTestAlarm(
        title: 'Test alarm in 10 s',
        delay: const Duration(seconds: 10),
      );
      final first = gateway.platform[osId]!;
      now = now.add(const Duration(seconds: 12));

      await scheduler.snooze(osId!, payload: first);

      // A test ring is registered as a snooze already, so its snooze is the
      // same alert, day and kind: re-armed under the id it rang under.
      final snoozed = gateway.platform.values.single;
      expect(snoozed.osId, osId);
      expect(snoozed, isNot(first));
      expect(snoozed.isTest, isTrue);
      expect(snoozed.snooze, isTrue);
      expect(snoozed.tintValue, AppTheme.lightScheme.primary.toARGB32());
      expect(snoozed.glyphKey, 'alarm');
      expect(snoozed.whenLabel, '');
      expect(
        snoozed.fireAtMs,
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
      expect(snoozed.timeLabel, '12:10');
    });
  });

  group('the sweep', () {
    test('settled rows older than a week go, the pending plan stays', () async {
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
      await (db.update(
        db.alertRegistrations,
      )..where((row) => row.osId.equals(osId))).write(
        AlertRegistrationsCompanion(updatedAt: Value(DateTime(2026, 1, 1))),
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

    test(
      'holds two occurrences, and Stop on the first arms the third',
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
      },
    );

    test(
      'skipping a day moves its registration on, and unskip brings it back',
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
      },
    );
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

    test(
      'a disabled alert keeps one row, so its switch stays reachable',
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
      },
    );

    test(
      'an alert switched off before its reconcile lands is listed once',
      () async {
        await seed();
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);

        await alerts.replaceForEvent('e1', [
          alertOf().copyWith(enabled: false),
        ]);
        final entries = await scheduler.hubEntries();

        expect(entries, hasLength(1));
        expect(entries.single.alert.enabled, isFalse);
      },
    );

    test('a snooze carries both instants and the id that cancels it', () async {
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

        expect(done, [
          'all',
          'event',
        ], reason: 'the chain advanced, in the order the turns were enqueued');
      });
    });
  });

  group('the registration tuple (v42)', () {
    test('rows a v41 build armed survive a pass untouched', () async {
      // An event's own alert, armed by a build from before the event joined
      // the key: the bare seed, the default `source`, the signature that
      // build recorded. The upgrade must re-arm nothing.
      await seed();
      final day = DateTime.utc(2026, 9, 20);
      final osId = resolveAlertOsId(
        seed: alertOsIdSeed(
          database: 'gym_notes',
          alertId: 'a1',
          dayUtc: day,
          kind: AlertKind.scheduled,
        ),
        isTaken: (_) => false,
      );
      await db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: Value(osId),
          alertId: const Value('a1'),
          eventId: const Value('e1'),
          day: Value(day.millisecondsSinceEpoch),
          fireAt: Value(DateTime(2026, 9, 20, 18).millisecondsSinceEpoch),
          kind: Value(AlertKind.scheduled.name),
          state: Value(AlertRegistrationState.pending.name),
          backend: const Value('fake#system:default~clock~10~n120'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      gateway.seedPlatform(
        AlertPayload(
          database: 'gym_notes',
          eventId: 'e1',
          alertId: 'a1',
          dayUtcMs: day.millisecondsSinceEpoch,
          osId: osId,
          mode: AlertMode.ring,
          title: 'Leg day',
          timeLabel: '18:00',
          categoryId: 'gym',
        ),
      );

      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled, isEmpty);
      final row = (await registrations()).single;
      expect(row.osId, osId);
      expect(row.source, AlertRegistrationSource.event.name);
    });

    test(
      'a standing snooze a v41 build armed survives a pass untouched',
      () async {
        await seed();
        final day = DateTime.utc(2026, 9, 20);
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        final snoozeId = resolveAlertOsId(
          seed: alertOsIdSeed(
            database: 'gym_notes',
            alertId: 'a1',
            dayUtc: day,
            kind: AlertKind.snooze,
          ),
          isTaken: (_) => false,
        );
        final snoozeAt = DateTime(2026, 9, 20, 18, 10);
        await db.alertRegistrationDao.put(
          AlertRegistrationsCompanion(
            osId: Value(snoozeId),
            alertId: const Value('a1'),
            eventId: const Value('e1'),
            day: Value(day.millisecondsSinceEpoch),
            fireAt: Value(snoozeAt.millisecondsSinceEpoch),
            kind: Value(AlertKind.snooze.name),
            state: Value(AlertRegistrationState.pending.name),
            backend: const Value('fake#system:default~clock~10~n120'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        gateway.seedPlatform(
          AlertPayload(
            database: 'gym_notes',
            eventId: 'e1',
            alertId: 'a1',
            dayUtcMs: day.millisecondsSinceEpoch,
            osId: snoozeId,
            mode: AlertMode.ring,
            title: 'Leg day',
            timeLabel: '18:10',
            categoryId: 'gym',
            snooze: true,
          ),
        );
        gateway.resetCalls();

        await scheduler.reconcileAll(AlertReconcileReason.resumed);

        expect(gateway.scheduled, isEmpty);
        expect(gateway.cancelled, isEmpty);
        final row = (await registrations()).firstWhere(
          (row) => row.osId == snoozeId,
        );
        expect(row.state, AlertRegistrationState.pending.name);
        expect(row.fireAt, snoozeAt.millisecondsSinceEpoch);
      },
    );
  });

  group('category alerts (v42)', () {
    Future<void> twoEventsUnderOneAlert({
      int offsetMinutes = 0,
      AlertMode mode = AlertMode.notify,
    }) async {
      await events.upsert(eventOf(id: 'e1'));
      await events.upsert(eventOf(id: 'e2', title: 'Arm day'));
      await alerts.replaceForCategory('gym', [
        CategoryAlert(
          id: 'ca1',
          categoryId: 'gym',
          offsetMinutes: offsetMinutes,
          mode: mode,
        ),
      ]);
    }

    final day = DateTime.utc(2026, 9, 20);

    int categorySnoozeSeed(String eventId) => resolveAlertOsId(
      seed: alertOsIdSeed(
        database: 'gym_notes',
        alertId: 'ca1',
        eventId: eventId,
        dayUtc: day,
        kind: AlertKind.snooze,
      ),
      isTaken: (_) => false,
    );

    Future<Map<String, int>> armedByEvent(AlertScheduler scheduler) async {
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      return {for (final row in await registrations()) row.eventId: row.osId};
    }

    List<AlertRegistrationRow> snoozesIn(List<AlertRegistrationRow> rows) => [
      for (final row in rows)
        if (row.kind == AlertKind.snooze.name) row,
    ];

    test('an inherited entry says so in its payload', () async {
      await twoEventsUnderOneAlert();
      final armed = await armedByEvent(schedulerOf());

      expect(gateway.platform[armed['e1']]!.inherited, isTrue);
    });

    test('two events snoozed on one day are two snoozes, each seeded by its '
        'event', () async {
      await twoEventsUnderOneAlert(mode: AlertMode.ring);
      final scheduler = schedulerOf();
      final armed = await armedByEvent(scheduler);
      now = DateTime(2026, 9, 20, 18);

      await scheduler.snooze(armed['e1']!);
      await scheduler.snooze(armed['e2']!);

      final snoozes = snoozesIn(await registrations());
      expect(
        {for (final row in snoozes) row.eventId: row.osId},
        {'e1': categorySnoozeSeed('e1'), 'e2': categorySnoozeSeed('e2')},
      );
      expect(snoozes.map((row) => row.state).toSet(), {
        AlertRegistrationState.pending.name,
      });
      expect(snoozes.map((row) => row.source).toSet(), {
        AlertRegistrationSource.category.name,
      });
    });

    test(
      "Stop on one event's ring leaves the other's snooze standing",
      () async {
        await twoEventsUnderOneAlert(mode: AlertMode.ring);
        final scheduler = schedulerOf();
        final armed = await armedByEvent(scheduler);
        final ringB = gateway.platform[armed['e2']]!;
        now = DateTime(2026, 9, 20, 18);
        await scheduler.snooze(armed['e1']!);

        await scheduler.settleEndedRing(ringB, answered: true);

        final snoozeA = snoozesIn(await registrations()).single;
        expect(snoozeA.eventId, 'e1');
        expect(snoozeA.state, AlertRegistrationState.pending.name);
        expect(gateway.cancelled, isNot(contains(snoozeA.osId)));
      },
    );

    test(
      'a snooze rebuilt from its payload is still the category\'s',
      () async {
        // The registration is gone and so is the alert: the payload alone
        // says the alert was inherited, which decides the seed and the source.
        await twoEventsUnderOneAlert(mode: AlertMode.ring);
        final scheduler = schedulerOf();
        final armed = await armedByEvent(scheduler);
        final ringA = gateway.platform[armed['e1']]!;
        await db.alertRegistrationDao.deleteAll();
        await alerts.replaceForCategory('gym', const []);
        now = DateTime(2026, 9, 20, 18);

        await scheduler.snooze(ringA.osId, payload: ringA);

        final snooze = snoozesIn(await registrations()).single;
        expect(snooze.osId, categorySnoozeSeed('e1'));
        expect(snooze.source, AlertRegistrationSource.category.name);
        expect(gateway.platform[snooze.osId]!.inherited, isTrue);
      },
    );

    test('one alert on two events of one day is two entries', () async {
      await twoEventsUnderOneAlert();

      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.scheduled, hasLength(2));
      final rows = await registrations();
      expect(rows.map((row) => row.eventId).toSet(), {'e1', 'e2'});
      expect(rows.map((row) => row.alertId).toSet(), {'ca1'});
      expect(rows.map((row) => row.osId).toSet(), hasLength(2));
      expect(rows.map((row) => row.source).toSet(), {
        AlertRegistrationSource.category.name,
      });
      for (final row in rows) {
        // The category alert's seed names the event; nothing collided.
        expect(
          row.osId,
          alertOsIdSeed(
            database: 'gym_notes',
            alertId: 'ca1',
            eventId: row.eventId,
            dayUtc: DateTime.utc(2026, 9, 20),
            kind: AlertKind.scheduled,
          ),
        );
      }
    });

    test('an edit of the category alert re-arms both in place', () async {
      await twoEventsUnderOneAlert();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = {
        for (final row in await registrations()) row.eventId: row.osId,
      };
      gateway.resetCalls();

      await alerts.replaceForCategory('gym', [
        const CategoryAlert(id: 'ca1', categoryId: 'gym', offsetMinutes: 30),
      ]);
      await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

      expect(gateway.scheduled, hasLength(2));
      expect(gateway.cancelled, isEmpty);
      final rows = await registrations();
      expect({for (final row in rows) row.eventId: row.osId}, before);
      for (final row in rows) {
        expect(
          row.fireAt,
          DateTime(2026, 9, 20, 17, 30).millisecondsSinceEpoch,
        );
      }
    });

    test("an event's opt-out cancels what it inherited", () async {
      await twoEventsUnderOneAlert();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final e1 = (await registrations()).firstWhere(
        (row) => row.eventId == 'e1',
      );
      gateway.resetCalls();

      await events.upsert(eventOf(id: 'e1').copyWith(categoryAlerts: false));
      await scheduler.reconcileEvent('e1', AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, [e1.osId]);
      final pending = (await registrations()).where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      expect(pending.map((row) => row.eventId), ['e2']);
    });

    test("the hub keeps an opted-out event's inherited row, its switch the "
        "event's flag, so the way back stays", () async {
      await twoEventsUnderOneAlert();
      await events.upsert(eventOf(id: 'e1').copyWith(categoryAlerts: false));
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      expect((await registrations()).map((row) => row.eventId), ['e2']);

      final entries = await scheduler.hubEntries();

      final e1 = entries.where((entry) => entry.event.id == 'e1').single;
      expect(e1.event.categoryAlerts, isFalse);
      expect(e1.alert.id, 'ca1');
      expect(e1.alert.categoryId, 'gym');
      expect(e1.alert.enabled, isTrue);
      expect(e1.fireAt, DateTime(2026, 9, 20, 18));
      expect(entries.where((entry) => entry.event.id == 'e2'), hasLength(1));
    });

    test('the hub lists no row for a category alert paused in the category '
        'editor', () async {
      await twoEventsUnderOneAlert();
      await alerts.replaceForCategory('gym', [
        const CategoryAlert(id: 'ca1', categoryId: 'gym', enabled: false),
      ]);
      await events.upsert(eventOf(id: 'e2').copyWith(categoryAlerts: false));
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);

      expect(await scheduler.hubEntries(), isEmpty);
    });
  });

  group('digests (v42)', () {
    final october = DateTime.utc(2026, 10, 1);

    Future<EventDigest> digestOf({
      String name = '',
      Set<String> categoryIds = const {'gym'},
      bool includeEmpty = false,
      bool enabled = true,
    }) async {
      final service = await EventDigestService.getInstance();
      final created = await service.create(
        EventDigest(
          id: '',
          name: name,
          categoryIds: categoryIds,
          includeEmpty: includeEmpty,
        ),
      );
      if (!enabled) await service.update(created!.copyWith(enabled: false));
      return created!;
    }

    Future<void> octoberBirthdays() async {
      await events.upsert(
        eventOf(
          id: 'b1',
          title: 'Ana',
          startDate: DateTime.utc(2026, 10, 4),
          time: null,
        ),
      );
      await events.upsert(
        eventOf(
          id: 'b2',
          title: 'Mihai',
          startDate: DateTime.utc(2026, 10, 12),
          time: null,
        ),
      );
    }

    test('a monthly digest is armed with its words and its span', () async {
      await octoberBirthdays();
      final digest = await digestOf();

      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      // November lists nothing and is not armed.
      expect(gateway.scheduledDigests, hasLength(1));
      expect(gateway.scheduled, isEmpty);
      final fire = gateway.scheduledDigests.single;
      expect(fire.fireAt, DateTime(2026, 10, 1, 9));
      final row = (await registrations()).single;
      expect(row.alertId, digest.id);
      expect(row.eventId, '');
      expect(row.day, october.millisecondsSinceEpoch);
      expect(row.kind, AlertKind.digest.name);
      expect(row.source, AlertRegistrationSource.digest.name);
      expect(row.backend, startsWith('fake~d#'));
      expect(
        row.osId,
        alertOsIdSeed(
          database: 'gym_notes',
          alertId: digest.id,
          dayUtc: october,
          kind: AlertKind.digest,
        ),
      );

      final payload = gateway.platform[row.osId]!;
      final gym = CalendarCategories.resolve('gym');
      expect(payload.isDigest, isTrue);
      expect(payload.eventId, '');
      expect(payload.alertId, digest.id);
      expect(payload.digestId, digest.id);
      expect(payload.mode, AlertMode.notify);
      expect(payload.snooze, isFalse);
      expect(payload.dayUtcMs, october.millisecondsSinceEpoch);
      expect(payload.spanStartMs, october.millisecondsSinceEpoch);
      expect(
        payload.spanEndMs,
        DateTime.utc(2026, 10, 31).millisecondsSinceEpoch,
      );
      expect(payload.categoryIdSet, {'gym'});
      expect(
        payload.title,
        CalendarCategories.labelOf(
          gym,
          lookupAppLocalizations(const Locale('en')),
        ),
      );
      expect(payload.timeLabel, '09:00');
      expect(payload.digestLines, ['Sun, Oct 4 · Ana', 'Mon, Oct 12 · Mihai']);
      expect(
        payload.digestText,
        '2 events this month · Oct 4 · Ana, Oct 12 · Mihai',
      );
      expect(payload.digestSummary, isNull);
      expect(payload.categoryId, 'gym');
      expect(payload.tintValue, gym.colorValue);
      expect(payload.glyphKey, gym.iconKey);
      expect(payload.languageCode, 'en');
    });

    test('a digest over every category wears no avatar', () async {
      await octoberBirthdays();
      await digestOf(categoryIds: const {});

      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      final payload = gateway.platform.values.single;
      expect(payload.title, 'Events');
      expect(payload.categoryId, '');
      expect(payload.tintValue, isNull);
      expect(payload.glyphKey, isNull);
      expect(payload.categoryIdSet, isEmpty);
    });

    test('an unchanged digest is skipped', () async {
      await octoberBirthdays();
      await digestOf();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.scheduledDigests, isEmpty);
      expect(gateway.cancelled, isEmpty);
    });

    test('an event added to the span re-arms it in place', () async {
      await octoberBirthdays();
      await digestOf();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final before = (await registrations()).single;
      gateway.resetCalls();

      await events.upsert(
        eventOf(
          id: 'b3',
          title: 'Ioana',
          startDate: DateTime.utc(2026, 10, 27),
          time: null,
        ),
      );
      await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

      expect(gateway.scheduledDigests, hasLength(1));
      expect(gateway.cancelled, isEmpty);
      final after = (await registrations()).single;
      expect(after.osId, before.osId);
      expect(after.backend, isNot(before.backend));
      expect(gateway.platform[after.osId]!.digestLines, hasLength(3));
    });

    test('a monthly digest arms its second fire too', () async {
      await octoberBirthdays();
      await digestOf(includeEmpty: true);

      await schedulerOf().reconcileAll(AlertReconcileReason.launch);

      expect(gateway.scheduledDigests.map((fire) => fire.fireAt), [
        DateTime(2026, 10, 1, 9),
        DateTime(2026, 11, 1, 9),
      ]);
      expect(
        gateway.platform.values
            .firstWhere(
              (payload) =>
                  payload.spanStartMs ==
                  DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
            )
            .digestText,
        'No events this month',
        reason: 'Also when empty arms the November digest over nothing',
      );
    });

    test('the OS-truth pass re-arms a digest the platform forgot', () async {
      await octoberBirthdays();
      await digestOf();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;
      gateway.platform.clear();
      gateway.resetCalls();

      await scheduler.reconcileAll(AlertReconcileReason.resumed);

      expect(gateway.scheduledDigests, hasLength(1));
      final pending = (await registrations()).where(
        (row) => row.state == AlertRegistrationState.pending.name,
      );
      expect(pending.single.osId, osId);
    });

    test(
      'a category added to the allowlist re-arms it, words unchanged',
      () async {
        // Named, and the new category lists nothing in October: every word
        // the notification shows is the same, and only what its tap opens
        // moved.
        await octoberBirthdays();
        final digest = await digestOf(name: 'Family');
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        final before = (await registrations()).single;
        gateway.resetCalls();

        await (await EventDigestService.getInstance()).update(
          EventDigests.byId(
            digest.id,
          )!.copyWith(categoryIds: const {'gym', 'travel'}),
        );
        await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

        expect(gateway.scheduledDigests, hasLength(1));
        final after = (await registrations()).single;
        expect(after.osId, before.osId);
        expect(after.backend, isNot(before.backend));
        final payload = gateway.platform[after.osId]!;
        expect(payload.categoryIdSet, {'gym', 'travel'});
        expect(payload.digestLines, hasLength(2));
      },
    );

    test('a disabled digest is cancelled', () async {
      await octoberBirthdays();
      final digest = await digestOf();
      final scheduler = schedulerOf();
      await scheduler.reconcileAll(AlertReconcileReason.launch);
      final osId = (await registrations()).single.osId;
      gateway.resetCalls();

      await (await EventDigestService.getInstance()).update(
        EventDigests.byId(digest.id)!.copyWith(enabled: false),
      );
      await scheduler.reconcileAll(AlertReconcileReason.eventChanged);

      expect(gateway.cancelled, [osId]);
      expect(gateway.platform, isEmpty);
    });

    group('past its instant', () {
      // The notification plugin posts a digest at its instant whether or not
      // the app runs, so a digest row behind now was delivered — in every
      // band, evidence or none — and a cancel would pull it off the shade.
      late AlertScheduler scheduler;

      Future<AlertRegistrationRow> runLate(
        Duration lateness, {
        DateTime? startedAt,
      }) async {
        await octoberBirthdays();
        await digestOf();
        scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        final armed = (await registrations()).single;
        gateway.resetCalls();
        gateway.startedAt = startedAt;
        now = DateTime(2026, 10, 1, 9).add(lateness);
        await scheduler.reconcileAll(AlertReconcileReason.launch);
        return (await registrations()).firstWhere(
          (row) => row.osId == armed.osId,
        );
      }

      test('is fired under the delivery evidence', () async {
        final row = await runLate(
          const Duration(minutes: 31),
          startedAt: DateTime(2026, 10, 1, 8),
        );

        expect(row.state, AlertRegistrationState.fired.name);
        expect(gateway.cancelled, isEmpty);
        expect(gateway.missed, isEmpty);
      });

      test('is fired without it, never missed and never cancelled', () async {
        final row = await runLate(const Duration(minutes: 31));

        expect(row.state, AlertRegistrationState.fired.name);
        expect(gateway.cancelled, isEmpty);
        expect(gateway.missed, isEmpty);
      });

      test('is fired inside the grace too', () async {
        final row = await runLate(const Duration(minutes: 5));

        expect(row.state, AlertRegistrationState.fired.name);
        expect(gateway.cancelled, isEmpty);
      });

      test('two days on, is still fired and left on the shade', () async {
        final row = await runLate(const Duration(days: 2));

        expect(row.state, AlertRegistrationState.fired.name);
        expect(gateway.cancelled, isEmpty);
        expect(gateway.missed, isEmpty);
      });

      test('Recent lists the delivery with its digest', () async {
        await runLate(const Duration(minutes: 31));
        final digest = EventDigests.all.single;

        final recent = (await scheduler.recentEntries()).single;

        expect(recent.digest, digest);
        expect(recent.event, isNull);
        expect(recent.alert, isNull);
        expect(recent.outcome, AlertOutcome.delivered);
        expect(recent.fireAt, DateTime(2026, 10, 1, 9));
        expect(recent.day, october);
      });

      test('Recent leaves out a delivery whose digest is gone', () async {
        await runLate(const Duration(minutes: 31));
        await (await EventDigestService.getInstance()).delete(
          EventDigests.all.single.id,
        );

        expect(await scheduler.recentEntries(), isEmpty);
      });
    });

    test(
      'digestEntries plans every digest; the hub lists no digest row',
      () async {
        await octoberBirthdays();
        final armed = await digestOf();
        final off = await digestOf(categoryIds: const {}, enabled: false);
        final scheduler = schedulerOf();
        await scheduler.reconcileAll(AlertReconcileReason.launch);

        final entries = await scheduler.digestEntries();

        // The armed one and the switched-off one, each at October's fire —
        // November lists nothing for either.
        expect(
          entries.map((entry) => (entry.digest.id, entry.digest.enabled)),
          unorderedEquals([(armed.id, true), (off.id, false)]),
        );
        for (final entry in entries) {
          expect(entry.fireAt, DateTime(2026, 10, 1, 9));
          expect(entry.spanStart, october);
          expect(entry.spanEnd, DateTime.utc(2026, 10, 31));
          expect(entry.count, 2);
        }
        expect(await scheduler.hubEntries(), isEmpty);
        expect(await scheduler.recentEntries(), isEmpty);
      },
    );
  });
}
