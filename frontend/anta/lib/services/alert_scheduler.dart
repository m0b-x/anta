import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../constants/alert_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_alerts.dart';
import '../database/daos/alert_registration_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/alert_hub_entry.dart';
import '../models/alert_payload.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/recurrence_rule.dart';
import '../utils/alert_os_id.dart';
import '../utils/alert_planner.dart';
import 'alert_gateway.dart';
import 'calendar_event_service.dart';
import 'database_manager.dart';
import 'event_alert_service.dart';
import 'event_skip_service.dart';
import 'event_time_formatter.dart';
import 'public_holiday_service.dart';
import 'settings_service.dart';

/// Why a reconcile is running. Logged, never branched on — the pass is the
/// same whatever provoked it, and a reason that changed the work would be a
/// second definition of "what the OS should hold".
enum AlertReconcileReason {
  launch,
  resumed,
  eventChanged,
  occurrenceChanged,
  backupRestored,
  ringHandled,
}

/// Reconciles one event's alerts. The seam `CalendarBloc` holds, so a bloc
/// test can watch the call without standing up a database.
typedef AlertReconciler =
    Future<void> Function(String eventId, AlertReconcileReason reason);

/// Keeps what the operating system holds in step with what the plan says it
/// should hold.
///
/// **A diff, never a rebuild.** Cancelling everything and re-registering would
/// be far simpler and is exactly what must not happen: an alarm is a promise
/// the phone already made, and a reconcile provoked by an unrelated edit
/// would briefly disarm every alert on the device — a window a process death
/// turns into a permanent loss.
///
/// **The OS is the truth, in both directions.** A `.db` file imported from
/// another device brings that device's registrations along, so a registry row
/// the platform does not know is dropped before diffing; and the event-import
/// wipe hard-deletes every registration while the platform keeps its entries,
/// so a platform entry naming the **active** database that the plan does not
/// contain is cancelled. Entries naming another database are never touched
/// (A9) — switching databases must not silently disarm the one left behind.
///
/// A plain singleton on the `DatabaseLifecycle` contract rather than a GetIt
/// registration: it holds a DAO, and GetIt holds the *object*, so after a
/// database switch a lookup would hand back one bound to a closed database.
/// The gateway it talks to is the opposite — stateless and global — so that
/// one does come from GetIt.
class AlertScheduler {
  static AlertScheduler? _instance;

  late final AlertRegistrationDao _dao;
  late final AlertGateway _gateway;

  /// Active database name at construction. Every os id is namespaced by it and
  /// every payload carries it, which is what keeps two databases from
  /// cancelling each other's alarms.
  late final String _databaseName;

  late final DateTime Function() _clock;

  late final AlertHorizon _horizon;

  /// Tail of the serialized write chain, or null when nothing is in flight.
  ///
  /// Seeded `null`, never a completed `Future.value()`: a future built in a
  /// field initializer schedules its continuations on the zone it was born in,
  /// so a chain seeded during a widget test's `setUp` never advances under the
  /// `FakeAsync` the body runs in and the first reconcile hangs forever. The
  /// `CategoryService._serialize` rule, for the same reason.
  Future<void>? _writes;

  /// Bumped after every turn of the serialized chain — a reconcile, a stop, a
  /// snooze, a cancelled snooze — which is every way the registry can change.
  ///
  /// Process-global rather than per instance because the one surface that
  /// listens, the Alerts hub, outlives a database switch's singleton reset and
  /// must not be left holding a notifier nobody bumps any more. A turn that
  /// changed nothing still bumps: the hub's re-read is one indexed query, and
  /// telling a no-op from a write would mean threading a flag through every
  /// branch of the pass for a page that is rarely open.
  static final ValueNotifier<int> registryRevision = ValueNotifier<int>(0);

  AlertScheduler._();

  /// Whether there is a platform binding to schedule against at all.
  ///
  /// Checked **before** anything opens a database or reads preferences, and
  /// that ordering is the whole point. [reconcileEventById] runs unawaited from
  /// `CalendarBloc`, and many widget suites build that bloc under a
  /// `path_provider` stub without registering a gateway; reaching
  /// `AppDatabase.getInstance()` there would claim the app-wide database
  /// singleton — and create a real file in the test's temp directory — out from
  /// under the in-memory database the test is actually using, before the GetIt
  /// lookup ever got the chance to fail.
  ///
  /// `configureDependencies()` registers the binding before the first frame,
  /// so on device this is always true.
  static bool get _hasGateway => GetIt.I.isRegistered<AlertGateway>();

  /// Resolves the singleton, binding it to the active database and the
  /// registered gateway.
  ///
  /// Throws a [StateError] — touching nothing — when no gateway is registered.
  /// Every caller already logs and carries on: alerts are best-effort, and a
  /// build with no binding is a build where they are simply inert.
  static Future<AlertScheduler> getInstance() async {
    if (_instance != null) return _instance!;
    if (!_hasGateway) {
      debugPrint('[AlertScheduler] no AlertGateway registered; alerts inert');
      throw StateError('AlertGateway is not registered');
    }
    final db = await AppDatabase.getInstance();
    final manager = await DatabaseManager.getInstance();
    return _create(
      dao: db.alertRegistrationDao,
      gateway: GetIt.I<AlertGateway>(),
      databaseName: manager.getActiveDatabaseName(),
      clock: DateTime.now,
      horizon: kAlertHorizon,
    );
  }

  /// Binds the singleton to an explicit database, gateway, clock and horizon.
  ///
  /// Never use it in app code — the singleton is what the `DatabaseLifecycle`
  /// reset contract is built on. The clock is a parameter for the same reason
  /// the planner's `now` is: a scheduler that reads the wall clock cannot be
  /// tested against a horizon at all.
  @visibleForTesting
  static AlertScheduler forTesting({
    required AppDatabase db,
    required AlertGateway gateway,
    required String databaseName,
    DateTime Function()? clock,
    AlertHorizon horizon = kAlertHorizon,
  }) {
    return _create(
      dao: db.alertRegistrationDao,
      gateway: gateway,
      databaseName: databaseName,
      clock: clock ?? DateTime.now,
      horizon: horizon,
    );
  }

  static AlertScheduler _create({
    required AlertRegistrationDao dao,
    required AlertGateway gateway,
    required String databaseName,
    required DateTime Function() clock,
    required AlertHorizon horizon,
  }) {
    final scheduler = AlertScheduler._();
    scheduler._dao = dao;
    scheduler._gateway = gateway;
    scheduler._databaseName = databaseName;
    scheduler._clock = clock;
    scheduler._horizon = horizon;
    _instance = scheduler;
    DatabaseLifecycle.registerResetHandler(reset);
    return scheduler;
  }

  /// Drops the cached singleton. The registrations themselves belong to the
  /// closed database and go with it; the platform entries stay armed, and the
  /// next database's first reconcile leaves them alone because their payloads
  /// name another database.
  static void reset() {
    _instance = null;
  }

  /// The default [AlertReconciler]: resolves the singleton and reconciles one
  /// event, swallowing every failure.
  ///
  /// Swallowing is deliberate — this runs from `CalendarBloc` handlers that
  /// have already persisted the user's edit, and a platform that refused to
  /// schedule must not turn a saved event into an error. The next launch or
  /// resume reconciles again.
  static Future<void> reconcileEventById(
    String eventId,
    AlertReconcileReason reason,
  ) async {
    // The gateway check comes first and on its own, before `getInstance()` can
    // reach a database — see [_hasGateway]. An existing singleton is honoured
    // even without one, because `forTesting` binds a gateway directly.
    if (_instance == null && !_hasGateway) {
      debugPrint('[AlertScheduler] no AlertGateway; skipped $eventId');
      return;
    }
    try {
      await (await getInstance()).reconcileEvent(eventId, reason);
    } catch (e) {
      debugPrint('[AlertScheduler] reconcileEvent($eventId) failed: $e');
    }
  }

  /// Marks a ringing registration `fired`, swallowing every failure.
  ///
  /// The static twin of [markFired], for the ring wiring in `main.dart`: it
  /// runs before a navigator exists and before anything is on screen, so a
  /// missing gateway or an unopened database must be silent rather than
  /// crash the ring it was called for.
  static Future<void> markFiredById(int osId) async {
    if (_instance == null && !_hasGateway) return;
    try {
      await (await getInstance()).markFired(osId);
    } catch (e) {
      debugPrint('[AlertScheduler] markFired($osId) failed: $e');
    }
  }

  /// Re-derives the whole horizon and makes the platform match it.
  Future<void> reconcileAll(AlertReconcileReason reason) =>
      _serialize(() => _reconcile(reason));

  /// The same pass, provoked by one event.
  ///
  /// **Also a full re-plan**, and it has to be: the horizon's `total` cap is
  /// global, so adding an alert to one event can push another event's fire out
  /// of the window and dropping one can pull a later fire in. A plan restricted
  /// to a single event could not be diffed against a registry that holds the
  /// truncated global list. [eventId] is carried for the log and as the
  /// guarantee a caller actually wants: an event that no longer exists has no
  /// plan entries, so this is what cancels its leftovers.
  Future<void> reconcileEvent(String eventId, AlertReconcileReason reason) =>
      _serialize(() => _reconcile(reason, eventId: eventId));

  /// Stops a ringing alert, then re-arms the event so the next occurrence is
  /// registered.
  ///
  /// The re-plan runs as its own turn on the chain rather than inside this
  /// one: nesting [_serialize] would wait on a tail this very call owns.
  Future<void> stop(int osId) async {
    final eventId = await _serialize(() => _stop(osId));
    if (eventId == null) return;
    await reconcileEvent(eventId, AlertReconcileReason.ringHandled);
  }

  /// Re-arms one alert `snoozeMinutes` from now as a registration of its own
  /// (`kind = snooze`, **A8**).
  ///
  /// Its own row is the entire point: every `scheduled` entry is re-derived
  /// from the plan on each pass, so a snooze folded into one would be wiped by
  /// the next unrelated edit. The diff skips `snooze` rows outright.
  Future<void> snooze(int osId) => _serialize(() => _snooze(osId));

  /// Drops a snooze the user changed their mind about.
  Future<void> cancelSnooze(int osId) => _serialize(() async {
    await _gateway.cancel(osId);
    await _dao.markState(osId, AlertRegistrationState.cancelled.name);
  });

  /// Records that a registration is ringing **right now**.
  ///
  /// Called the moment `Alarm.ringing` emits, before the alarm page is pushed
  /// and before anything else touches the row, and it goes through the same
  /// serialized chain as every other write so it cannot interleave with a
  /// reconcile. That ordering is the whole point: [_settlePastFires] leaves a
  /// row under [kLateFireGrace] late exactly as it found it — *in flight* —
  /// and the ring handler is the only thing allowed to settle one. Without
  /// this the row stays `pending` until it ages past the grace window and is
  /// then reported as Missed, for a ring the user actually heard.
  Future<void> markFired(int osId) => _serialize(() async {
    await _dao.markState(osId, AlertRegistrationState.fired.name);
  });

  /// Cancels a standing snooze of the same alert on the same occurrence day.
  ///
  /// **Deliberately not part of [stop].** `stop` is about one platform entry;
  /// this is about the user's intent, and the two differ in exactly one case:
  /// an alert snoozed at 07:00 and then stopped at its 07:10 ring would leave
  /// the 07:20 snooze armed to ring a third time for a session already
  /// acknowledged. The alarm page's Stop calls both; a reconcile calls
  /// neither, because a snooze is never the plan's to cancel.
  Future<void> cancelSnoozeForAlert(String alertId, DateTime dayUtc) {
    return _serialize(() async {
      final dayMs = DateTime.utc(
        dayUtc.year,
        dayUtc.month,
        dayUtc.day,
      ).millisecondsSinceEpoch;
      for (final row in await _dao.pending()) {
        if (row.alertId != alertId) continue;
        if (row.day != dayMs) continue;
        if (AlertKind.fromName(row.kind) != AlertKind.snooze) continue;
        await _gateway.cancel(row.osId);
        await _dao.markState(row.osId, AlertRegistrationState.cancelled.name);
      }
    });
  }

  /// When each of [eventId]'s alerts is next due, as the registry holds it.
  ///
  /// A read, so it deliberately does **not** join the serialized write chain:
  /// the detail sheet asks once while it is opening, and queueing behind a
  /// reconcile would make a sheet wait on a platform round trip to draw a line
  /// of text. A row the OS has since forgotten is answered by the next
  /// reconcile, not here — this reports what the app believes is armed.
  ///
  /// Keyed by alert id and filtered to the future: a row still `pending` with
  /// a fire instant in the past is one the ring handler has not settled yet,
  /// and calling that "next" would be a lie on the one surface that names a
  /// time.
  Future<Map<String, DateTime>> nextFiresForEvent(String eventId) async {
    final now = _clock();
    final next = <String, DateTime>{};
    for (final row in await _dao.forEvent(eventId)) {
      if (AlertRegistrationState.fromName(row.state) !=
          AlertRegistrationState.pending) {
        continue;
      }
      final fireAt = DateTime.fromMillisecondsSinceEpoch(row.fireAt);
      if (!fireAt.isAfter(now)) continue;
      final current = next[row.alertId];
      if (current == null || fireAt.isBefore(current)) {
        next[row.alertId] = fireAt;
      }
    }
    return next;
  }

  /// [nextFiresForEvent] for a surface that holds no scheduler, swallowing
  /// every failure into an empty map.
  ///
  /// Swallowing is the point: on desktop, in a widget test and in any build
  /// without a gateway there is no registry to read, and a detail sheet that
  /// threw rather than simply omitting "Next …" would be a crash in service of
  /// a subtitle.
  static Future<Map<String, DateTime>> nextFiresForEventById(
    String eventId,
  ) async {
    try {
      return await (await getInstance()).nextFiresForEvent(eventId);
    } catch (e) {
      debugPrint('[AlertScheduler] next fires for $eventId failed: $e');
      return const {};
    }
  }

  /// Everything the Alerts hub lists (§5.6), soonest first.
  ///
  /// Two sources, because the hub answers two questions. What **will** the
  /// phone do: every `pending` registration with a fire instant still ahead —
  /// the registry, not a fresh plan, so a fire the `total` cap pushed out of
  /// the horizon is not promised here. And what **could** it do: each disabled
  /// alert's next occurrence, planned on the spot with the switch imagined on,
  /// because a registry-only list would make the hub's own switch a one-way
  /// door — the row would vanish with the registration and take the way back
  /// with it.
  ///
  /// A read outside the serialized chain, for [nextFiresForEvent]'s reason. A
  /// test ring is left out: it has no event to show and nothing to toggle.
  Future<List<AlertHubEntry>> hubEntries() async {
    await _resolveQuietly(EventSkipService.getInstance(), 'skips');
    await _resolveQuietly(PublicHolidayService.getInstance(), 'holidays');
    await _resolveQuietly(EventAlertService.getInstance(), 'alerts');

    final CalendarEventService eventService;
    final AlertSettings settings;
    try {
      eventService = await CalendarEventService.getInstance();
      settings = await (await SettingsService.getInstance())
          .getAlertSettings();
    } catch (e) {
      debugPrint('[AlertScheduler] hub setup failed: $e');
      return const [];
    }

    final now = _clock();
    final events = eventService.events;
    final eventsById = {for (final event in events) event.id: event};
    final entries = <AlertHubEntry>[];

    for (final row in await _dao.pending()) {
      final fireAt = DateTime.fromMillisecondsSinceEpoch(row.fireAt);
      if (!fireAt.isAfter(now)) continue;
      final event = eventsById[row.eventId];
      if (event == null) continue;
      final alert = _alertOf(row.eventId, row.alertId);
      if (alert == null) continue;
      final day = DateTime.fromMillisecondsSinceEpoch(row.day, isUtc: true);
      final snoozed = AlertKind.fromName(row.kind) == AlertKind.snooze;
      // Switched off a moment ago, and the reconcile that cancels this row has
      // not landed yet: the imagined entry below already speaks for it.
      if (!alert.enabled && !snoozed) continue;
      entries.add(
        AlertHubEntry(
          event: event,
          alert: alert,
          day: day,
          fireAt: fireAt,
          originalFireAt: snoozed
              ? AlertPlanner.fireInstant(
                  event: event,
                  alert: alert,
                  day: day,
                  defaults: settings,
                )
              : null,
          snoozeOsId: snoozed ? row.osId : null,
        ),
      );
    }

    final disabled = <String, EventAlert>{};
    final imagined = <String, List<EventAlert>>{};
    for (final event in events) {
      for (final alert in EventAlerts.alertsFor(event.id)) {
        if (alert.enabled) continue;
        disabled[alert.id] = alert;
        (imagined[event.id] ??= <EventAlert>[]).add(
          alert.copyWith(enabled: true),
        );
      }
    }
    if (imagined.isNotEmpty) {
      final plan = AlertPlanner.plan(
        events: events,
        alertsByEvent: imagined,
        defaults: settings,
        horizon: AlertHorizon(
          perAlert: 1,
          days: _horizon.days,
          total: _horizon.total,
        ),
        now: now,
      );
      for (final fire in plan) {
        entries.add(
          AlertHubEntry(
            event: fire.event,
            alert: disabled[fire.alert.id]!,
            day: fire.day,
            fireAt: fire.fireAt,
          ),
        );
      }
    }

    entries.sort((a, b) {
      final byInstant = a.fireAt.compareTo(b.fireAt);
      if (byInstant != 0) return byInstant;
      final byEvent = a.event.id.compareTo(b.event.id);
      if (byEvent != 0) return byEvent;
      return a.alert.id.compareTo(b.alert.id);
    });
    return entries;
  }

  /// [hubEntries] for a page that holds no scheduler, swallowing every failure
  /// into an empty list — the [nextFiresForEventById] rule.
  static Future<List<AlertHubEntry>> hubEntriesOrEmpty() async {
    if (_instance == null && !_hasGateway) return const [];
    try {
      return await (await getInstance()).hubEntries();
    } catch (e) {
      debugPrint('[AlertScheduler] hub entries failed: $e');
      return const [];
    }
  }

  /// [cancelSnooze] for the same page, swallowing every failure.
  static Future<void> cancelSnoozeById(int osId) async {
    if (_instance == null && !_hasGateway) return;
    try {
      await (await getInstance()).cancelSnooze(osId);
    } catch (e) {
      debugPrint('[AlertScheduler] cancelSnooze($osId) failed: $e');
    }
  }

  /// Arms the settings page's `Test alarm in 10 s` (§5.7).
  ///
  /// Registered like anything else so it can be stopped, swept and — after a
  /// process kill — found again, but recorded as `kind = snooze`, because the
  /// diff owns only what the planner produced and a `scheduled` row it cannot
  /// re-derive would be cancelled by the very next reconcile. The payload
  /// carries [AlertPayload.testEventId], which is what the alarm page titles
  /// itself from and what keeps the Missed path from resolving an event that
  /// was never there.
  ///
  /// Returns the os id it was armed under, or null when the platform refused.
  Future<int?> scheduleTestAlarm({
    required String title,
    required Duration delay,
  }) {
    return _serialize(() async {
      final AlertSettings settings;
      try {
        settings = await (await SettingsService.getInstance())
            .getAlertSettings();
      } catch (e) {
        debugPrint('[AlertScheduler] test alarm setup failed: $e');
        return null;
      }
      final now = _clock();
      final fireAt = now.add(delay);
      final day = DateTime.utc(fireAt.year, fireAt.month, fireAt.day);
      final event = _testEvent(day, title: title);
      // A fresh alert id per arming, so two test alarms on the same day do not
      // land on the same os id. They would otherwise: the seed is a hash of
      // (database, alert, day, kind), which is exactly the determinism a real
      // alert wants and exactly what an ad-hoc ring must not have — the second
      // one is then swallowed by every dedupe between the platform and the
      // navigation queue, and rings with no page.
      final alert = _testAlert(
        '${AlertPayload.testEventId}:${fireAt.millisecondsSinceEpoch}',
      );
      final fire = PlannedFire(
        event: event,
        alert: alert,
        day: day,
        fireAt: fireAt,
        kind: AlertKind.snooze,
      );
      final osId = resolveAlertOsId(
        seed: alertOsIdSeed(
          database: _databaseName,
          alertId: alert.id,
          dayUtc: day,
          kind: AlertKind.snooze,
        ),
        isTaken: (_) => false,
      );
      final payload = _payloadFor(fire, osId, settings.snoozeMinutes);
      if (!await _gateway.schedule(fire, payload)) return null;
      await _dao.put(
        AlertRegistrationsCompanion(
          osId: Value(osId),
          alertId: Value(alert.id),
          eventId: Value(event.id),
          day: Value(day.millisecondsSinceEpoch),
          fireAt: Value(fireAt.millisecondsSinceEpoch),
          kind: Value(AlertKind.snooze.name),
          state: Value(AlertRegistrationState.pending.name),
          backend: Value(_gateway.backendName),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return osId;
    });
  }

  /// The event a test ring stands in for.
  ///
  /// [title] is empty everywhere but the arming call, because every surface
  /// that draws a test alarm titles it from `AlertPayload.isTest` and its own
  /// localizations rather than from the payload's text.
  static CalendarEvent _testEvent(DateTime dayUtc, {String title = ''}) {
    return CalendarEvent(
      id: AlertPayload.testEventId,
      title: title,
      categoryId: CalendarCategories.fallback.id,
      startDate: dayUtc,
      rule: const OneTimeRecurrence(),
    );
  }

  static EventAlert _testAlert(String alertId) => EventAlert(
    id: alertId,
    eventId: AlertPayload.testEventId,
    mode: AlertMode.ring,
  );

  // ── The pass ─────────────────────────────────────────────────────────

  /// Awaits one service's construction, logging rather than rethrowing — the
  /// `CalendarBloc._resolveQuietly` rule, so a single unavailable facade
  /// degrades the plan instead of cancelling the reconcile outright.
  static Future<void> _resolveQuietly(Future<Object?> init, String label) async {
    try {
      await init;
    } catch (e) {
      debugPrint('[AlertScheduler] $label unavailable: $e');
    }
  }

  Future<void> _reconcile(
    AlertReconcileReason reason, {
    String? eventId,
  }) async {
    final now = _clock();

    // Every facade the plan reads has to be configured before it is read — an
    // unconfigured read is silent, and here "silent" means a cancelled
    // occurrence ringing or a workdays event planning straight through a
    // public holiday. All of them resolve through `getInstance()`, never GetIt,
    // so a database switch cannot hand back one bound to a closed database.
    //
    // Resolved one at a time, each quietly, for the reason `CalendarBloc`
    // gives: one unavailable service must not silence the whole pass. The two
    // the plan cannot be built without are awaited separately below.
    await _resolveQuietly(EventSkipService.getInstance(), 'skips');
    await _resolveQuietly(PublicHolidayService.getInstance(), 'holidays');
    await _resolveQuietly(EventAlertService.getInstance(), 'alerts');

    final CalendarEventService eventService;
    final AlertSettings settings;
    try {
      eventService = await CalendarEventService.getInstance();
      settings = await (await SettingsService.getInstance())
          .getAlertSettings();
    } catch (e) {
      debugPrint('[AlertScheduler] reconcile(${reason.name}) setup failed: $e');
      return;
    }

    await _dao.sweep(now: now, retention: kAlertRegistrationRetention);

    final events = eventService.events;
    final eventsById = {for (final event in events) event.id: event};
    final alertsByEvent = <String, List<EventAlert>>{};
    for (final event in events) {
      final alerts = EventAlerts.alertsFor(event.id);
      if (alerts.isNotEmpty) alertsByEvent[event.id] = alerts;
    }

    final settled = await _settlePastFires(
      await _dao.pending(),
      now,
      eventsById,
      settings.snoozeMinutes,
    );
    final live = settled.live;

    // OS truth, but only from a binding that can actually answer. Applying it
    // against the no-op gateway — which knows nothing, always — would cancel
    // and re-register the entire horizon on every pass.
    //
    // In-flight rows are deliberately outside this too: a ring the app has not
    // been told about yet may already have left the platform's pending list,
    // and dropping its row would hand the ring handler nothing to settle.
    var osEntries = const <PendingAlertEntry>[];
    if (_gateway.tracksPending) {
      osEntries = await _gateway.pendingEntries();
      final osIds = {for (final entry in osEntries) entry.osId};
      for (final row in live) {
        if (osIds.contains(row.osId)) continue;
        await _dao.markState(row.osId, AlertRegistrationState.cancelled.name);
      }
      live.removeWhere((row) => !osIds.contains(row.osId));
    }

    final plan = AlertPlanner.plan(
      events: events,
      alertsByEvent: alertsByEvent,
      defaults: settings,
      horizon: _horizon,
      now: now,
    );

    // In-flight rows occupy ids the probe must route around, even though they
    // are not part of the diff.
    final desired = _assignOsIds(plan, [...live, ...settled.inFlight]);
    var scheduled = 0;
    var cancelled = 0;

    for (final entry in desired.entries) {
      final osId = entry.key;
      final fire = entry.value.fire;
      final existing = entry.value.existing;
      // The registry stores the instant and the backend, not the payload — so
      // a rename, a recolour, a new icon or a flipped "remove after it rings"
      // changes what the OS should be holding without changing anything the
      // fast path can see. A pass provoked by one event therefore re-schedules
      // that event's entries unconditionally, under the ids they already have;
      // every other event keeps the fast path, which is what makes an unrelated
      // edit — and every `reconcileAll` — cost nothing.
      final refresh = eventId != null && fire.event.id == eventId;
      if (!refresh &&
          existing != null &&
          existing.osId == osId &&
          existing.fireAt == fire.fireAt.millisecondsSinceEpoch &&
          existing.backend == _gateway.backendName) {
        continue;
      }
      final payload = _payloadFor(fire, osId, settings.snoozeMinutes);
      if (!await _gateway.schedule(fire, payload)) continue;
      await _dao.put(
        AlertRegistrationsCompanion(
          osId: Value(osId),
          alertId: Value(fire.alert.id),
          eventId: Value(fire.event.id),
          day: Value(fire.day.millisecondsSinceEpoch),
          fireAt: Value(fire.fireAt.millisecondsSinceEpoch),
          kind: Value(fire.kind.name),
          state: Value(AlertRegistrationState.pending.name),
          backend: Value(_gateway.backendName),
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
        ),
      );
      scheduled++;
    }

    // Seeded with the in-flight ids and with whatever the gateway says is
    // ringing right now: a ring in progress is not the plan's to cancel from
    // either direction. The two sets differ once the ring handler has marked
    // a row `fired` — it is then neither pending nor in flight, but the
    // `alarm` package still holds it until Stop.
    final handled = {
      for (final row in settled.inFlight) row.osId,
      ..._gateway.ringingIds,
    };
    for (final row in live) {
      // A snooze belongs to the user, not to the plan: an unrelated reconcile
      // of the same event must leave it exactly where it is.
      if (AlertKind.fromName(row.kind) == AlertKind.snooze) {
        handled.add(row.osId);
        continue;
      }
      if (desired.containsKey(row.osId)) continue;
      await _gateway.cancel(row.osId);
      await _dao.markState(row.osId, AlertRegistrationState.cancelled.name);
      handled.add(row.osId);
      cancelled++;
    }

    for (final entry in osEntries) {
      // A9: an entry belonging to another database is not ours to cancel.
      if (entry.payload.database != _databaseName) continue;
      // A snooze belongs to the user, not to the plan — the rule the registry
      // loop above already applies to `kind = snooze` rows, restated here
      // because a snooze can exist on the platform with no row at all: the
      // reminder tier's Snooze action runs in a background isolate that has no
      // database to write one. Cancelling it would silently disarm the ten
      // minutes the user just asked for.
      if (entry.payload.snooze) continue;
      if (desired.containsKey(entry.osId)) continue;
      if (!handled.add(entry.osId)) continue;
      await _gateway.cancel(entry.osId);
      await _dao.markState(entry.osId, AlertRegistrationState.cancelled.name);
      cancelled++;
    }

    debugPrint(
      '[AlertScheduler] reconcile(${reason.name}'
      '${eventId == null ? '' : ', $eventId'}) '
      'backend=${_gateway.backendName} planned=${plan.length} '
      'scheduled=$scheduled cancelled=$cancelled',
    );
  }

  /// Sorts the pending registry into the three things a past instant can mean
  /// (**A10**), and settles the one that is genuinely over.
  ///
  /// **The app cannot see a delivery**, and everything here follows from that.
  /// The `alarm` plugin relaunches the process and emits on `Alarm.ringing`
  /// only a second or two later — well after the launch reconcile the relaunch
  /// itself provoked — and the notification tier never calls back at all, so a
  /// past-due reminder row that rang and a past-due reminder row that was
  /// dropped are the same row. Three bands:
  ///
  /// - **ahead of [now]** — armed, and the diff's only input.
  /// - **past by less than [kLateFireGrace]** — *in flight*. Left `pending`,
  ///   kept out of the diff entirely: never cancelled, never re-scheduled,
  ///   never reported. Session 3's ring handler is what marks it `fired` or
  ///   `stopped`; a reconcile that touched it would cancel a ring in progress
  ///   and post "Missed" over the noise it was still making.
  /// - **past by more** — over. Marked `cancelled`, and reported once, quietly,
  ///   while it is still inside [kMissedAlertWindow] **and** the alert is in
  ///   the ring tier. A reminder that was simply not tapped is not a missed
  ///   appointment, and reporting every one of them would turn each launch
  ///   into a pile of notifications; an alert that no longer exists has nothing
  ///   to say either.
  ///
  /// This is the **only** Missed source, for both tiers. The `alarm` package
  /// does drop a boot-recovered alarm older than `androidStaleAfter` (passed
  /// as the same [kLateFireGrace]), but its `AlarmDropped` event carries an id
  /// and nothing else, and the alarm is already gone from the plugin's storage
  /// when the event is delivered — so there is no payload to post from. The
  /// row here is, by construction, past the grace window at the very launch
  /// that delivers the drop, and this pass reports it.
  Future<({List<AlertRegistrationRow> live, List<AlertRegistrationRow> inFlight})>
  _settlePastFires(
    List<AlertRegistrationRow> rows,
    DateTime now,
    Map<String, CalendarEvent> eventsById,
    int snoozeMinutes,
  ) async {
    final live = <AlertRegistrationRow>[];
    final inFlight = <AlertRegistrationRow>[];
    for (final row in rows) {
      final fireAt = DateTime.fromMillisecondsSinceEpoch(row.fireAt);
      if (fireAt.isAfter(now)) {
        live.add(row);
        continue;
      }
      final lateness = now.difference(fireAt);
      if (lateness < kLateFireGrace) {
        inFlight.add(row);
        continue;
      }
      await _dao.markState(row.osId, AlertRegistrationState.cancelled.name);
      if (lateness >= kMissedAlertWindow) continue;
      final event = eventsById[row.eventId];
      if (event == null) continue;
      final alert = _alertOf(row.eventId, row.alertId);
      if (alert == null || alert.mode != AlertMode.ring) continue;
      await _gateway.showMissed(
        _payloadForRow(row, event, fireAt: fireAt, snoozeMinutes: snoozeMinutes),
      );
    }
    return (live: live, inFlight: inFlight);
  }

  /// Gives every planned fire the id the platform will hold it under.
  ///
  /// An alert that already has a registration for the same (alert, day, kind)
  /// keeps that row's id, whatever the hash says — the row *is* the memory of
  /// where a collision probe landed, and re-deriving it would move an entry the
  /// OS is already holding. Everything else takes the deterministic seed and
  /// probes past ids another key has taken.
  Map<int, ({PlannedFire fire, AlertRegistrationRow? existing})> _assignOsIds(
    List<PlannedFire> plan,
    List<AlertRegistrationRow> live,
  ) {
    final byKey = <String, AlertRegistrationRow>{};
    final taken = <int, String>{};
    for (final row in live) {
      final key = _registrationKey(
        row.alertId,
        DateTime.fromMillisecondsSinceEpoch(row.day, isUtc: true),
        AlertKind.fromName(row.kind),
      );
      byKey[key] = row;
      taken[row.osId] = key;
    }

    final desired = <int, ({PlannedFire fire, AlertRegistrationRow? existing})>{};
    for (final fire in plan) {
      final key = _registrationKey(fire.alert.id, fire.day, fire.kind);
      final existing = byKey[key];
      final osId =
          existing?.osId ??
          resolveAlertOsId(
            seed: alertOsIdSeed(
              database: _databaseName,
              alertId: fire.alert.id,
              dayUtc: fire.day,
              kind: fire.kind,
            ),
            isTaken: (candidate) {
              final holder = taken[candidate];
              return holder != null && holder != key;
            },
          );
      taken[osId] = key;
      desired[osId] = (fire: fire, existing: existing);
    }
    return desired;
  }

  static String _registrationKey(
    String alertId,
    DateTime dayUtc,
    AlertKind kind,
  ) => '$alertId|${alertDayIso(dayUtc)}|${kind.name}';

  // ── Ring handling ────────────────────────────────────────────────────

  /// Returns the event whose horizon now has room again, or null when the
  /// registration is unknown.
  Future<String?> _stop(int osId) async {
    final row = await _dao.byOsId(osId);
    await _gateway.stopRinging(osId);
    await _gateway.cancel(osId);
    await _dao.markState(osId, AlertRegistrationState.stopped.name);
    return row?.eventId;
  }

  Future<void> _snooze(int osId) async {
    final row = await _dao.byOsId(osId);
    if (row == null) return;

    final CalendarEventService eventService;
    final AlertSettings settings;
    try {
      await EventAlertService.getInstance();
      eventService = await CalendarEventService.getInstance();
      settings = await (await SettingsService.getInstance())
          .getAlertSettings();
    } catch (e) {
      debugPrint('[AlertScheduler] snooze($osId) setup failed: $e');
      return;
    }

    final day = DateTime.fromMillisecondsSinceEpoch(row.day, isUtc: true);
    CalendarEvent? event;
    for (final candidate in eventService.events) {
      if (candidate.id != row.eventId) continue;
      event = candidate;
      break;
    }
    var alert = _alertOf(row.eventId, row.alertId);
    // A test ring has no event row and no alert row — that is what the
    // sentinel means — so it is rebuilt from the registration instead. Without
    // this, Snooze is the one button on the alarm page that silently does
    // nothing for the only alarm the settings page can arm.
    if (event == null && row.eventId == AlertPayload.testEventId) {
      event = _testEvent(day);
      alert = _testAlert(row.alertId);
    }

    await _gateway.stopRinging(osId);
    await _dao.markState(osId, AlertRegistrationState.fired.name);
    if (event == null || alert == null) return;

    final now = _clock();
    final fire = PlannedFire(
      event: event,
      alert: alert,
      day: day,
      fireAt: now.add(Duration(minutes: settings.snoozeMinutes)),
      kind: AlertKind.snooze,
    );
    // Probed against the live registry for the same reason the plan is: the
    // seed is deterministic, so re-snoozing the same alert on the same day
    // lands on its own row, and a collision with someone else's id does not
    // silently replace it.
    final occupied = {
      for (final other in await _dao.pending())
        if (other.alertId != alert.id ||
            other.day != day.millisecondsSinceEpoch ||
            AlertKind.fromName(other.kind) != AlertKind.snooze)
          other.osId,
    };
    final snoozeOsId = resolveAlertOsId(
      seed: alertOsIdSeed(
        database: _databaseName,
        alertId: alert.id,
        dayUtc: day,
        kind: AlertKind.snooze,
      ),
      isTaken: occupied.contains,
    );
    final payload = _payloadFor(fire, snoozeOsId, settings.snoozeMinutes);
    if (!await _gateway.schedule(fire, payload)) return;
    await _dao.put(
      AlertRegistrationsCompanion(
        osId: Value(snoozeOsId),
        alertId: Value(alert.id),
        eventId: Value(event.id),
        day: Value(day.millisecondsSinceEpoch),
        fireAt: Value(fire.fireAt.millisecondsSinceEpoch),
        kind: Value(AlertKind.snooze.name),
        state: Value(AlertRegistrationState.pending.name),
        backend: Value(_gateway.backendName),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  // ── Payloads ─────────────────────────────────────────────────────────

  AlertPayload _payloadFor(PlannedFire fire, int osId, int snoozeMinutes) {
    return AlertPayload(
      database: _databaseName,
      eventId: fire.event.id,
      alertId: fire.alert.id,
      dayUtcMs: fire.day.millisecondsSinceEpoch,
      osId: osId,
      mode: fire.alert.mode,
      title: fire.event.title,
      timeLabel: _timeLabel(fire.fireAt),
      colorValue: fire.event.colorValue,
      iconKey: fire.event.iconKey,
      categoryId: fire.event.categoryId,
      removeAfterAlert: fire.event.removeAfterAlert,
      snooze: fire.kind == AlertKind.snooze,
      snoozeMinutes: snoozeMinutes,
    );
  }

  AlertPayload _payloadForRow(
    AlertRegistrationRow row,
    CalendarEvent event, {
    required DateTime fireAt,
    required int snoozeMinutes,
  }) {
    final alert = _alertOf(row.eventId, row.alertId);
    return AlertPayload(
      database: _databaseName,
      eventId: row.eventId,
      alertId: row.alertId,
      dayUtcMs: row.day,
      osId: row.osId,
      mode: alert?.mode ?? AlertMode.notify,
      title: event.title,
      timeLabel: _timeLabel(fireAt),
      colorValue: event.colorValue,
      iconKey: event.iconKey,
      categoryId: event.categoryId,
      removeAfterAlert: event.removeAfterAlert,
      snooze: AlertKind.fromName(row.kind) == AlertKind.snooze,
      snoozeMinutes: snoozeMinutes,
    );
  }

  /// One alert of one event by id, or null once it has been removed. A plain
  /// loop over an unmodifiable list of at most five.
  static EventAlert? _alertOf(String eventId, String alertId) {
    for (final candidate in EventAlerts.alertsFor(eventId)) {
      if (candidate.id == alertId) return candidate;
    }
    return null;
  }

  /// Wall clock of the fire instant, formatted here on the UI thread. §11: the
  /// app never sets `Intl.defaultLocale`, so a label composed in a background
  /// isolate would render in the system locale rather than the app's.
  static String _timeLabel(DateTime fireAt) =>
      EventTimeFormatter.formatMinuteOfDay(fireAt.hour * 60 + fireAt.minute);

  // ── Serialization ────────────────────────────────────────────────────

  Future<T> _serialize<T>(Future<T> Function() write) async {
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Already surfaced to whoever issued it; one failure must not stop
        // the queue.
      }
    }
    try {
      return await write();
    } finally {
      done.complete();
      registryRevision.value++;
    }
  }
}
