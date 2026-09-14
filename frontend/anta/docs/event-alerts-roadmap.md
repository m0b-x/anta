# Event Alerts — Roadmap & Phase Prompts (2026-09-14)

**Status: PROPOSED, nothing shipped. Phase 0 DONE on the emulator
(2026-09-14, branch `spike/event-alerts-ring`, commit `359f317`, results in
§10); the owner's phone pass of the same spike is owed (§9, §10.4).**
Phases 1–4 are planned and not started. Decisions A1–A14 (§1) were
proposed on 2026-09-14 and are to be confirmed by the owner at the Phase 1
kickoff; A5 is now backed by the spike; A15 (the Windows build) was found
by the spike and **settled the same day** — the ATL component is installed
and the spike branch builds for Windows.
Design source: the studies artifact (both themes, 360 dp frames):
https://claude.ai/code/artifact/27747ab0-bb8c-463f-b6cf-5b5449db01c5
Research: five read-only Opus passes on 2026-09-14 (events model and
services, UI tokens and surfaces, platform plumbing and bootstrap, the
2026 Android/iOS alarm landscape, prior art in `docs/`). Line numbers below
are as of `4610292` and will drift — re-grep before editing.

Companion docs: `calendar-events-feature.md` (§11 lists reminders as
"intentionally deferred" — this roadmap resolves that row), the
`calendar-events` skill (schema lineage, currently v39), `presence-tracking-
roadmap.md` (the "nothing marks on its own" rule the alarm page inherits),
`category-scaling-roadmap.md` (per-event defaults belong to templates, not
categories), `cloud-sync-connections-design.md` (the push design that will
share the notification plugin), `qa-harness.md` (the verbs Phase 3 extends).

---

## 0. What an alert is, and is not

An **alert** is a property of an event: *when* the phone should speak up,
relative to an occurrence, and *how*. Two tiers, one row in the editor:

- A **Reminder** is a notification. It respects silent mode and Focus,
  sits in the shade, and carries Snooze and Done. Tap opens the event.
- An **Alarm** rings until stopped or snoozed. It plays on the alarm
  stream, shows a full-screen page on a locked phone, a persistent heads-up
  on an unlocked one, and carries Stop and Snooze.

Everything except the moment of firing is shared: one table hung off
`calendar_events`, one pure planner, one reconcile loop, one gateway to
the platform, one backup key, one `.ics` VALARM mapping. That sharing is
the scalability argument: adding an alert costs one row, the amount of
work a ring or an app resume does is bounded by a horizon and never by the
number of events, and swapping the platform backend touches one file.

- **Not a second calendar.** There is no list of reminder items. The
  Alerts hub (§5.6) is a view over events' alerts.
- **Not a timer.** The inline rest timer idea in `markdown-feature-ideas.md`
  is a live in-note countdown with no OS scheduling. It stays separate.
- **Not presence.** Marking a day missed changes nothing about its alerts;
  cancelling a day (`calendar_event_skips`) does. Alerts follow the skip
  rule ("does not exist"), never the presence rule ("still occurs"). The
  alarm page may later *ask* whether you went (A13); it never marks.
- **Not push.** Everything is scheduled on the device from local data. The
  cloud push design stays a later stage; both share `flutter_local_
  notifications`.
- **Not a critical alert.** Apple's critical entitlement is for medical and
  safety apps and would be refused; iOS alarms are AlarmKit on 26+ and
  time-sensitive notifications below.

## 1. Decisions (proposed 2026-09-14; confirm at Phase 1 kickoff)

| Id | Question | Proposed | Why |
| --- | --- | --- | --- |
| A1 | Vocabulary | Row **Alerts**; each alert is a **Reminder** or an **Alarm**. Code: `EventAlert`, `AlertMode { notify, ring }`. | "Alarm" is the owner's word and translates cleanly (de *Alarm*, ro *alarmă*); "Ring" is already `todayStyleRing` in the appearance vocabulary. |
| A2 | Cardinality | Up to **5** per event, one card each in the editor. | Google Calendar's cap; a row per alert keeps `calendar_events` narrow. |
| A3 | Remove after it rings | A flag on the **event** (`remove_after_alert`), off by default, on for quick alarms. Stop/Done on the first acknowledged alert soft-deletes the event through `CalendarEventService.deleteById` (cascade + tombstone) with a 5 s Undo. Cancelling such an alarm before it rings deletes the event too. | It is a statement about the event's purpose, not one alert's; a soft delete syncs and survives a mistake. |
| A4 | All-day events | Each alert carries `days_before` + `day_minute`; default **09:00 on the day**, changeable in Calendar settings. | The model has no anchor for all-day events; Apple and Google both default to 09:00. |
| A5 | Ringing backend — **emulator spike confirms, phone pass owed** | `alarm` 5.13 for the Alarm tier; `flutter_local_notifications` 22.3 for the Reminder tier. Fallback, proven in the spike (§10.3 S7): an insistent alarm-stream notification from the reminder plugin (`AndroidScheduleMode.alarmClock`, `fullScreenIntent`, `additionalFlags [4]`), switchable in the gateway alone. | Purpose-built, actively maintained (13 releases in 2026), holds the foreground service Android 17 now demands for background audio, owns the audio, degrades under Total Silence to screen + vibration; the fallback needs no second plugin. Caveat (§10.1): `alarm` uses `setExactAndAllowWhileIdle`, the fallback `setAlarmClock`. |
| A6 | Exact-alarm permission | Declare `USE_EXACT_ALARM` (no prompt). | Play policy allows it for "a calendar app that shows event notifications"; the `alarm` plugin's manifest declares it anyway. |
| A7 | Horizon | Next **2** occurrences per alert, **30** days, **48** registrations total, soonest first. | Survives a week without opening the app; stays under iOS's 64 pending and far under Samsung's 500. |
| A8 | Snooze | One button, length from settings, default **10 min**; a snooze is its own registration (`kind = snooze`). | Google Clock's default; per-ring choices add taps to a screen used half asleep. |
| A9 | Other databases | Every database's alarms ring. The alarm page names the database when it is not the active one; Open switches (the restart flow of `database_settings_page.dart:787-821`). Reconcile touches only OS entries whose payload names the active database. | An alarm is a promise the phone made; switching databases must not silently cancel it. |
| A10 | Late rings | Ring if under **30 min** late; otherwise a quiet "Missed: {title}" notification (only if under 24 h late), never a ring at boot for a session that ended. | A phone that was off should not ring a 07:00 alarm at 09:30. Mechanism per backend in §3.4. |
| A11 | Quick alarm category | `other`, with `iconKey = 'alarm'` as the event's own icon override. | No new built-in to seed and migrate; the icon carries the meaning on every row. |
| A12 | Where a tap opens | Reminder → the calendar on the event's day with the detail sheet open. Alarm → the alarm page. | A reminder is about the event; an alarm is about stopping the noise. |
| A13 | Presence prompt | Phase 3, opt-in per tracked event, the page only **asks** and dispatches `SetOccurrencePresence`. | `presence-tracking-roadmap.md`: nothing marks on its own. |
| A14 | Time semantics | Floating local time, exactly as the calendar already is: 07:00 rings at 07:00 wherever the phone is; a spring-forward gap rolls to the next valid instant (Dart's local `DateTime` constructor normalizes forward). No timezone column. | The app records no timezone (`ics_serializer.dart:9-12`); adding one for alerts alone would split the model. |
| A15 | Windows build with the notification plugin — **DONE 2026-09-14**: the owner installed the ATL component and `flutter build windows --debug` of the spike branch produced `anta.exe` (41.9 s) | Install the Visual Studio component **C++ ATL for the installed toolset** once on the dev machine — component id `Microsoft.VisualStudio.Component.VC.ATL`, which the installer labels by toolset: *"C++ ATL for latest v145 build tools (x86 & x64)"* on this machine's **Visual Studio Build Tools 2026** (18.9, MSVC v145; there is no VS 2022 here, so the v143 label does not apply) — and record it under CLAUDE.md's commands; the `verify` skill gains the prerequisite. Alternative: a local stub package overriding `flutter_local_notifications_windows` (Dart-only `dartPluginClass`, no FFI) under `dependency_overrides`. Rejected: dropping the plugin and doing reminders on `alarm` (it always plays on the alarm stream). | The Windows implementation is an FFI plugin compiled unconditionally (§10.1); a one-time component install is cheaper and less fragile than a shadow package, and it leaves the door open to desktop reminders later. |

## 2. Domain model

### 2.1 `EventAlert` (`lib/models/event_alert.dart`)

```
EventAlert(
  id: String,                 // uuid v4
  eventId: String,
  mode: AlertMode,            // notify | ring
  offsetMinutes: int,         // >= 0, timed events: minutes before start
  daysBefore: int,            // >= 0, all-day events
  dayMinute: int?,            // all-day events: minute of day; null = settings default
  sound: String?,             // null = default; alarm tier only
  enabled: bool,              // the hub switch; disabled = kept, never registered
)
```

Both offset sets are always stored, and the planner picks by
`event.time == null` (the derived `allDay`, never the persisted column —
`calendar_event.dart:288`). An event switched from timed to all-day keeps
alerts that still mean something. `Equatable`; `copyWith` with
`clearSound`/`clearDayMinute`. `EventAlert.describe(l10n, event)` is the
**one** formatter for "10 min before" / "The evening before, 20:00" /
"At start", used by the editor card, the detail row, the hub row and the
notification body; never a second switch.

### 2.2 `remove_after_alert` on `calendar_events`

`bool removeAfterAlert` on `CalendarEvent`, default false, written by the
editor's switch (only offered while the event is one-time and has at least
one alert) and by the quick-alarm sheet. `EventAgenda`, `occursOn`, presence,
skips and the grid never read it. The subtitle segment "removed after it
rings" comes from `EventSummaryProvider._subtitleFor`
(`day_summary_resolver.dart:191-218`) so the day panel, the agenda and
`agenda_search_text.dart` stay in step.

### 2.3 `AlertRegistration` — device-local (`alert_registrations`)

The mirror of what the OS holds, per device, rebuilt by reconcile at any
time. **Not** in backups, **not** in sync, no CRDT block, hard deletes
allowed (the sanctioned device-local category: `cloud-sync-roadmap.md:133`,
`calendar-cloud-readiness-roadmap.md:81-84`, pairing keys in
`BackupService._exportSettings`).

```
os_id      INTEGER PRIMARY KEY   -- 31-bit id handed to the platform (§3.3)
alert_id   TEXT NOT NULL
event_id   TEXT NOT NULL
day        INTEGER NOT NULL      -- occurrence day, date-only UTC epoch ms
fire_at    INTEGER NOT NULL      -- local instant, epoch ms
kind       TEXT NOT NULL         -- 'scheduled' | 'snooze'
state      TEXT NOT NULL         -- 'pending' | 'fired' | 'stopped' | 'cancelled'
backend    TEXT NOT NULL         -- 'alarm' | 'notification'
created_at INTEGER NOT NULL
updated_at INTEGER NOT NULL
```

Indexes: `idx_alert_registrations_pending (fire_at) WHERE state = 'pending'`
and `idx_alert_registrations_event (event_id)`. Rows in `fired`/`stopped`/
`cancelled` older than 7 days are swept by reconcile.

**The OS is the truth for `pending`.** A `.db` file imported from another
device (`DatabaseManager.importDatabase`) brings that device's rows along;
reconcile checks every pending row against the platform's pending list
(`pendingNotificationRequests()`, `Alarm.getAlarms()`) and drops rows the
OS does not know before diffing. Never trust the table alone.

### 2.4 Fire instant

Nothing in the app composes a UTC day and a `startMinute` into an instant
today (`calendar_event_service.dart:429-439` exists only because Drift
hands int-epoch columns back as *local* `DateTime`). The planner is the
first and only place that does:

```
timed:   fireAt = DateTime(day.year, day.month, day.day)          // local
                    .add(Duration(minutes: time.startMinute - offsetMinutes))
all-day: anchor = day − daysBefore (date-only UTC arithmetic, then local)
         fireAt = DateTime(anchor.year, anchor.month, anchor.day)
                    .add(Duration(minutes: dayMinute ?? defaults.allDayMinute))
```

`day` is the date-only UTC occurrence day from `occursOnUtcDay`; the
`y/m/d` fields are read off it and rebuilt as a **local** midnight. The
`timezone` package's `tz.TZDateTime.from(fireAt, tz.local)` is used only at
the gateway boundary for the notification plugin. Never store `fireAt` on
the alert.

### 2.5 Horizon and caps (A7)

`AlertHorizon(perAlert: 2, days: 30, total: 48)` in `lib/constants/
alert_constants.dart`. The planner walks each event with an enabled alert
from `today` (date-only UTC of `now`) for at most `days` days through
`event.occursOnUtcDay` — which already subtracts `endDate` and skips
(`calendar_event.dart:447-450`) — collects up to `perAlert` occurrence days
per alert whose `fireAt` is after `now`, merges every candidate by
`fireAt`, and truncates to `total`. Cost: one pass over events that have
alerts, at most 30 `occursOnUtcDay` calls each; a database with a thousand
events and twenty alerted ones plans in well under a millisecond. Rules
that read `PublicHolidays` (`WorkdaysRecurrence`, `PublicHolidaysOnly
Recurrence`) are re-planned on every resume, which is what makes a holiday
profile change reach the OS; nothing caches the plan.

Occurrences whose `fireAt` already passed are not registered — the OS
late-delivery path (§3.4) is the only source of late rings.

### 2.6 What must never ring

- A skipped occurrence (`EventSkips.isSkipped`, through `occursOnUtcDay`).
- A deleted event (tombstoned; `deleteById` cascades the alert rows and
  the registrations, then reconciles).
- A disabled alert (`enabled = 0` keeps the row, registers nothing).
- An occurrence after `endDate`.
- Anything from a database the payload does not name (A9) — the ring page
  still shows it, reconcile just never cancels or re-registers it.

A missed/assume-absent occurrence **does** ring: presence is about the past.

## 3. Architecture

Layering is the usual `Page → BLoC → Service → DAO`, with the alarm page
allowed to be service-direct like `CalendarCategoriesPage`.

### 3.1 Pieces

| Piece | File | Role |
| --- | --- | --- |
| `EventAlertDao` | `lib/database/daos/event_alert_dao.dart` | All SQL. Stamps HLC/device/version like `calendar_event_dao.dart:8-11`; soft delete; `replaceForEvent(eventId, alerts)` in one transaction (tombstone missing, upsert present); `tombstoneForEvent`; `getAllActive()` one read with the `is_deleted = 0` literal. |
| `AlertRegistrationDao` | `lib/database/daos/alert_registration_dao.dart` | Hard writes; `pending()`, `markState`, `sweep()`. |
| `EventAlertService` + `EventAlerts` facade | `lib/services/event_alert_service.dart`, `lib/constants/event_alerts.dart` | The `EventSkipService` shape verbatim (`getInstance` / `forTesting` / `_create` / `reset` clearing the facade / `exportData` / `importData` / `clearAllForImport` / `refreshAfterEventRemoval`). The facade is `abstract final class EventAlerts` with `alertsFor(eventId)` (unmodifiable, O(1)), `hasAlarm(eventId)`, `hasReminder(eventId)`, `revision`, `updateCache`, `resetCache`; read synchronously by the row badges. Registered with `DatabaseLifecycle`, **never GetIt** (`injection.dart:79-91`). |
| `AlertPlanner` | `lib/utils/alert_planner.dart` | Pure. `plan({events, alertsByEvent, defaults, horizon, now}) → List<PlannedFire>`. The codebase's first clock seam: `now` is a parameter, the caller reads `DateTime.now()` once. |
| `AlertScheduler` | `lib/services/alert_scheduler.dart` | `reconcileAll(reason)`, `reconcileEvent(id, reason)`, `stop(osId)`, `snooze(osId)`, `cancelSnooze`. Awaits `EventSkipService`, `PublicHolidayService`, `CalendarEventService`, `EventAlertService` before planning (an unconfigured facade is silent and wrong — see the calendar skill's "seven services" rule). Serialized on one chain like `CategoryService._serialize`, tail seeded `null`. Diffs against the registry, never cancels wholesale. |
| `AlertGateway` | `lib/services/alert_gateway.dart` | Interface: `schedule(PlannedFire, payload)`, `cancel(osId)`, `pendingIds()`, `permissions()`, `requestNotifications()`, `openFullScreenIntentSettings()`, `stopRinging(osId)`, `ringing` stream, `launchIntent()`. Bindings: `AndroidAlertGateway` (Phase 1), `DarwinAlertGateway` (Phase 4), `NoOpAlertGateway` (desktop, web, tests). Registered in GetIt like `AuthService`/`NoOpAuthService` (`injection.dart:136-137`) behind `AlertAvailability.isSupported` (`sync_availability.dart` shape). |
| `AlertPayload` | `lib/models/alert_payload.dart` | Self-describing JSON: `db, eventId, alertId, dayUtcMs, osId, mode, title, timeLabel, colorValue, iconKey, categoryId, removeAfterAlert, snooze`. The alarm page draws from it alone. |
| `PendingNavigationQueue` | `lib/services/pending_navigation.dart` | `enqueue(AlertIntent)`; drained by `_MyAppState` after the restore post-frame callback (`main.dart:266-270`) and immediately once `AppNavigator.navigatorKey.currentState` exists (`app_navigator.dart:50` force-unwraps, so a cold-start tap must wait). |
| `AlarmPage` | `lib/pages/alarm_page.dart` | Full-bleed, the onboarding skeleton (`onboarding_page.dart:31-83`); pushed with `AppNavigator.rootPushInstant`, **not recorded** as a `NavDestination`. |
| `AlertRingController` | `lib/controllers/alert_ring_controller.dart` | Page-owned plain class: Stop / Snooze / Open / Keep, talking to the scheduler and, for A3, to `CalendarEventService.deleteById`. |

### 3.2 Reconcile triggers

| Trigger | Where | Scope |
| --- | --- | --- |
| App launch | `main.dart` after `configureDependencies()`, post-frame, `unawaited` | all |
| App resumed | new `resumed` branch in `_MyAppState.didChangeAppLifecycleState` (`main.dart:233`, today only `paused|inactive|detached`), debounced 2 s | all |
| Event create / update / delete | `CalendarBloc._onCreateEvent` `:685`, `_onUpdateEvent` `:719`, `_onDeleteEvent` `:747` | event |
| Alerts edited | the editor result's `alerts` handled in the same three handlers via `EventAlertService.replaceForEvent` | event |
| Hub switch | `ToggleEventAlert` handler | event |
| Skip / unskip | the skip handlers | event |
| Backup restore, `importData` | end of `BackupService.importFromJson` | all |
| Database switch | the app restarts (`SystemNavigator.pop`), so launch covers it | all |
| Ring stopped / snoozed | `AlertRingController` | event |
| Boot | both plugins re-register their own alarms; the next launch reconciles | all |
| Time zone / clock change | not handled in v1 beyond the next resume; documented limitation | — |

`CalendarEventService.externalRevision` is **not** bumped by any of this
(its contract is restore/switch only, `calendar_event_service.dart:55-68`).

### 3.3 OS ids and the payload

`os_id = fnv1a32("$db|$alertId|$dayIso|$kind") & 0x7fffffff`, collision
resolved by linear probe and recorded in the registry. Deterministic ids
make reconcile idempotent across process deaths; namespacing by database
name keeps two databases from cancelling each other's alarms. The payload
also carries `db`, and reconcile ignores platform entries whose `db` is not
the active database name (`DatabaseManager.getActiveDatabaseName()`).

### 3.4 Firing

- **Reminder (notification plugin):** `zonedSchedule(androidScheduleMode:
  exactAllowWhileIdle)` on a high-importance `alerts_reminder` channel,
  actions Snooze / Done. Done is handled in the background isolate
  (`@pragma('vm:entry-point')`, no database access: it only cancels).
  Snooze re-schedules from the payload alone. Tap → `PendingNavigationQueue
  .enqueue(openEvent)`.
- **Alarm (`alarm` plugin, A5):** `Alarm.set` with `loopAudio`, `vibrate`,
  `androidFullScreenIntent`, `androidStaleAfter: 30 min` (A10),
  `notificationSettings.stopButton`, the JSON payload. `Alarm.ringing` →
  `AlarmPage`. `Alarm.set()` **throws** `AlarmException` since 5.9.0 while
  still typed `Future<bool>`; the gateway catches and reports.
- **Fallback alarm (notification plugin):** `alarmClock` mode,
  `fullScreenIntent: true`, `category: alarm`, `audioAttributesUsage:
  alarm`, `additionalFlags: Int32List.fromList([4])`, `ongoing: true`,
  `timeoutAfter: silenceAfter`; a `max`-importance `alerts_alarm` channel.
  No stale cut-off is possible (the system posts it), so A10's "Missed"
  path is done by reconcile on the next launch.
- **Late fire (A10):** `alarm` reports a boot-recovered alarm older than
  `androidStaleAfter` (set to 30 min) as `AlarmDropped(cause: staleAtBoot)`
  on `Alarm.events`; the gateway maps it to the "Missed" notification. On
  launch/resume, any pending registration whose `fire_at` is in the past
  and not `fired` is marked `cancelled`; if it is under 24 h old a one-shot
  "Missed: {title} at {time}" notification is posted; then the horizon is
  re-planned. A user **Force stop** cancels every pending alarm on both
  backends (§10.1); the next launch's reconcile is the only recovery, so
  the settings section says so in one line.
- **Delivery hygiene (§10.5):** a cold-start tap arrives twice
  (`onDidReceiveNotificationResponse` + `getNotificationAppLaunchDetails`)
  — the queue dedupes on `osId`; a handled full-screen-intent notification
  is cancelled immediately, or it re-launches the activity the next time
  the screen turns off; `Alarm.ringing`'s initial empty set is ignored.

### 3.5 Remove after it rings (A3)

Stop (alarm) or Done/tap (reminder) on an event with `removeAfterAlert`:
`AlertRingController.acknowledge` → `CalendarEventService.deleteById`
(tombstone + cascades: absences, occurrences, skips, **alerts**,
registrations) → `reconcileEvent` → snackbar "Removed · Undo" on the
calendar page (Undo = `upsert` of the captured event, which resurrects the
tombstone by the DAO's existing rule, `calendar_event_dao.dart:51`). On
the alarm page "Keep the event" clears the flag before Stop.

### 3.6 Multi-database (A9)

The alarm page renders from the payload, so it never needs the right
database open. It shows a chip "From database *work*" when
`payload.db != active`; Open sets the active name and shows the existing
restart dialog. Reconcile is scoped to the active database's entries by
payload, so a switch leaves the other database's registrations intact.
QA builds share the package and therefore the OS namespace (`qa_mode.dart`);
the QA database name in the payload is what keeps a QA alarm from
touching the owner's, and Phase 3's `qa alerts --cancel` clears them.

## 4. Persistence

### 4.1 Schema v40 (frozen DDL for the migration)

```sql
CREATE TABLE IF NOT EXISTS calendar_event_alerts (
  id TEXT NOT NULL PRIMARY KEY,
  event_id TEXT NOT NULL,
  mode TEXT NOT NULL DEFAULT 'notify',
  offset_minutes INTEGER NOT NULL DEFAULT 0,
  days_before INTEGER NOT NULL DEFAULT 0,
  day_minute INTEGER NULL,
  sound TEXT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  hlc_timestamp TEXT NOT NULL,
  device_id TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  deleted_at INTEGER NULL
);
CREATE INDEX IF NOT EXISTS idx_calendar_event_alerts_active
  ON calendar_event_alerts (event_id) WHERE is_deleted = 0;

CREATE TABLE IF NOT EXISTS alert_registrations (
  os_id INTEGER NOT NULL PRIMARY KEY,
  alert_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  day INTEGER NOT NULL,
  fire_at INTEGER NOT NULL,
  kind TEXT NOT NULL DEFAULT 'scheduled',
  state TEXT NOT NULL DEFAULT 'pending',
  backend TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_alert_registrations_pending
  ON alert_registrations (fire_at) WHERE state = 'pending';
CREATE INDEX IF NOT EXISTS idx_alert_registrations_event
  ON alert_registrations (event_id);

ALTER TABLE calendar_events ADD COLUMN remove_after_alert INTEGER NOT NULL DEFAULT 0;
```

Recipe: `DatabaseSchema.v40EventAlerts` (`database_schema.dart:4-44`); the
two table classes added to the `@DriftDatabase(tables: …)` list
(`database.dart:50-86`) **and** the DDL above spelled out in
`_migrateV39ToV40` (`database_migrations.dart`, the `_migrateV29ToV30`
shape at `:1158`), guarded column via `PRAGMA table_info` like
`_migrateV36ToV37` (`:1391`); indexes through `DatabaseIndexes` so
`schema_parity_test.dart` (which scrapes the source for `CREATE … IF NOT
EXISTS`) sees both paths. `hlc_timestamp`/`device_id` are **default-less**
on a new table (`event_skips_table.dart:53-54`), never the `''` artifact of
`calendar_events`. `dart run build_runner build --delete-conflicting-outputs`.

### 4.2 Backup

Key `eventAlerts` in `BackupService.exportAllData` (`backup_service.dart:
128-152`): live rows only, no CRDT fields. **Strand rule keyed to
`calendarEvents`**, the `eventSkips` shape at `:522` — an absent
`eventAlerts` alongside a present `calendarEvents` clears the table,
because the event import wipes and reinserts and a stale alert would fire
for whatever event later takes that id. Import order: after
`calendarEvents`, next to `eventSkips`. No version bump (7 stays 7): an
old backup has no alerts, which is what that install had. `remove_after_
alert` rides `calendarEvents` as an additive key, absent = 0. The
registrations table is **never exported**.

### 4.3 `.ics`

`IcsSerializer` emits one `VALARM` per enabled alert: `ACTION:DISPLAY`
for notify, `ACTION:AUDIO` for ring, `TRIGGER:-PT{n}M` for timed offsets,
`TRIGGER;VALUE=DATE-TIME` computed per the all-day rule for the first
occurrence. Imports are out of scope (the app has no `.ics` import).

### 4.4 Settings

Through `SettingsService` + `SettingsKeys`, one bulk read
`getAlertSettings()` over `_alertKeys` with pure decoders, added to
`_calendarPageKeys`; reset-to-defaults on the calendar settings page.

| Key | Default | Meaning |
| --- | --- | --- |
| `alert_default_timed` | `notify:10` | mode and offset for a new timed event's first alert; `none` = no default |
| `alert_default_all_day` | `notify:0:540` | mode, days before, minute of day |
| `alert_sound` | `''` | default alarm sound id |
| `alert_snooze_minutes` | `10` | 5–30, step 5 |
| `alert_silence_after_minutes` | `10` | 1–30 |

Permission state is queried live from the gateway, never stored (it is
per device and can change in Settings).

## 5. UI

Every string in `app_en.arb` + `app_de.arb` + `app_ro.arb` together, then
`flutter gen-l10n`; keys prefixed `eventAlert*` (per-event surfaces),
`alarm*` (the alarm page), `alerts*` (hub and settings), `quickAlarm*`.
Romanian plurals need the `few` arm.

### 5.1 Editor (`event_editor_sheet.dart`)

Inside the *Time* zone, after the end-time tile (`:2376`) and before
`_GroupHeader(eventSectionDetails)` (`:2378`): `_SectionLabel(eventAlerts)`,
one `_PickerTile` per alert (`CircleAvatar` alarm/bell glyph, title =
`EventAlert.describe`, subtitle `eventAlertRingsUntilStopped` /
`eventAlertNotification`, trailing `close_rounded` remove), an `ActionChip`
`eventAlertAdd` (hidden at 5), the hint `eventAlertHint`, and — only while
the event is one-time and has an alarm — a `Card > SwitchListTile`
`eventAlertRemoveAfter` / `eventAlertRemoveAfterHint`. A new event is
seeded from `alert_default_timed` / `alert_default_all_day`. The sheet's
result record gains `alerts` and `removeAfterAlert`. Save stays gated only
by `_canSave`.

### 5.2 Alert sheet (`lib/widgets/alert_editor_sheet.dart`)

Draft-and-Save, `FractionallySizedBox(0.7)`, header close | `eventAlert`
title | Save. Sections: Type (`SegmentedButton<AlertMode>` with a hint that
changes per mode and warns when full-screen alarms are off), When (timed:
`ChoiceChip`s At start / 5 / 10 / 15 / 30 min / 1 h / 1 day / Custom… →
an `_IntervalStepper`-shaped minutes + unit row; all-day: On the day /
The day before / A week before + a time-of-day `_PickerTile` through
`showTimePicker`), Sound (alarm only, `_PickerTile` → a sound picker sheet
that plays a 2 s preview through the gateway), and the remove switch
(one-time only). Footer `Remove alert` (`FilledButton.icon` in
`errorContainer`). Pads by `max(viewInsets, viewPadding)` and joins
`sheet_bottom_clearance_test.dart`.

### 5.3 Detail sheet (`event_detail_sheet.dart`)

One `_InfoRow` per alert after the time row (`:537`), glyph in `primary`
for alarms, text `EventAlert.describe` + ` · ` + `eventAlertNext` with the
next `fire_at` from the registry (through the scheduler, resolved once in
`initState` like `_upcoming`, never in `build`). Tap = `edit`.

### 5.4 Day panel and agenda rows

A 14 dp badge beside the title, exactly the description badge
(`day_summary_panel.dart:275-285`, `agenda_list_view.dart:1141-1151`):
`notifications_active_rounded` in `onSurfaceVariant` for reminders,
`alarm_rounded` in `primary` for alarms, `Tooltip` = the describe string.
Read from `EventAlerts.hasAlarm/hasReminder` synchronously. The trailing
strip is at capacity (`:210-212`) and is not touched. `showInDayRail` and
the grid are untouched: no cell marker.

### 5.5 Alarm page (`lib/pages/alarm_page.dart`)

Eyebrow `alarmPageTitle`, the fire time in `displayLarge` weight 300, the
date line, the event row (48 dp tinted avatar), the database chip (A9),
then `Spacer`, then `FilledButton.icon` Stop (56 high), `OutlinedButton.icon`
Snooze {n} min, `TextButton` Open event; for `removeAfterAlert` a caption
and `TextButton` Keep the event. `SafeArea`, `PopScope(canPop: false)`
(back = Stop is wrong; back does nothing while ringing), screen kept on
through the plugin. Because it resumes the app it inherits the stale-inset
hazard (`COPILOT_CONTEXT.md` UX §): it has no keyboard, so nothing to do,
but note it in the widget test.

### 5.6 Alerts hub (`lib/pages/alerts_page.dart`)

Drawer row under CALENDAR after `calendarSettingsRow`
(`app_drawer.dart:122-140`), `NavDestinationKind.alerts` appended to the
enum (append-only, `nav_destination.dart:19-33`). `SettingsAppBar(title:
alertsTitle)`; permission banners (notifications off, full-screen alarms
off) each with a Turn on action through the gateway; rows grouped by day
(`AgendaListView.dayHeaderLabel`), leading time (tabular), title, subtitle
glyph + describe, `Switch` bound to `enabled` (`ToggleEventAlert`), snoozed
rows show the snoozed time with the original below. Tap = detail sheet;
long-press on a `removeAfterAlert` event = Cancel (deletes the event, A3).
Reads the registry through the scheduler; `EventAlerts.revision` and the
registry revision drive rebuilds.

### 5.7 Calendar settings (`calendar_settings_page.dart`)

A seventh section `_buildAlertsSection` (`alarm_rounded`,
`calendarAlertsSection`): three permission rows (notifications, full-screen
alarms, battery — each a status chip or a Turn on action), default for
timed events, default for all-day events, alarm sound, Snooze slider,
Silence after slider, and `Test alarm in 10 s` (`OutlinedButton.icon`,
schedules a ring with a synthetic payload that the alarm page labels
`alertsTestAlarm`). Reset-to-defaults covers the five keys.

### 5.8 Quick alarm

`EventTemplatePickerSheet` (`event_template_picker_sheet.dart:60-113`)
gains a neutral row `quickAlarmRow` above `templateBlankEvent`; with no
templates the FAB long press still opens the sheet (today it falls through
to the editor, `calendar_page.dart:1223-1226` — change that branch so the
row is always reachable). `QuickAlarmSheet` (`lib/widgets/quick_alarm_sheet.
dart`): big time (tap → `showTimePicker`, default next quarter hour), three
`ChoiceChip`s In 20 min / In 1 hour / Tonight 21:00, a name field
(`quickAlarmName`, default text "Alarm"), Type segmented (Alarm default),
the remove switch (on). Save → `CreateCalendarEvent` on the selected day
(`categoryId: 'other'`, `iconKey: 'alarm'`, `time: EventTime(startMinute)`,
`removeAfterAlert: true`) with one alert (`offsetMinutes: 0`) → snackbar
`quickAlarmSet` with Undo (the existing template-add pattern, `:1246-1256`).

## 6. Platform

### 6.1 Android (Phase 1)

Dependencies: `alarm ^5.13.0`, `flutter_local_notifications ^22.3.1`,
`timezone ^0.11.1`, `flutter_timezone ^5.1.0` (its `getLocalTimezone()`
returns a `TimezoneInfo`; use `.identifier`). The exact build steps that
worked are §10.2: desugaring in `build.gradle.kts`, the notification
plugin's **three** receivers (the action receiver included), the
permission list, `showWhenLocked` + `turnScreenOn` on `MainActivity`,
`tools:node="remove"` on the `READ_EXTERNAL_STORAGE` that `alarm`'s own
manifest merges in, the regenerated desktop registrants committed, and the
A15 prerequisite for the Windows build. Resources: a monochrome `ic_alert`
small icon under `drawable*/`, the default alarm sound under `assets/` (the
`alarm` plugin plays assets, not `res/raw`). Channels: `alerts_reminder`
(high) and, for the fallback path only, `alerts_alarm` (max, `USAGE_ALARM`);
`alarm` creates its own `alarm_plugin_channel` at importance 4 and does not
let Dart configure it. Names localized at creation, ids fixed forever
(channel settings are immutable after creation).

Permission flow follows `cloud-sync-connections-design.md:444-449`: never
at app start. `POST_NOTIFICATIONS` is requested the first time an alert is
saved; `USE_FULL_SCREEN_INTENT` is never a prompt (Android has none) — the
editor hint, the hub banner and the settings row link to
`requestFullScreenIntentPermission()`. Battery optimisation is a status
row with a link to the app's settings page, never a request
(`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is Play-policy-restricted).
A denial degrades: alerts are still saved and still register; an alarm
without full-screen shows as a persistent heads-up.

Facts that shaped this (2026-09-14): Android 17 = API 37 (2026-06-16)
requires a non-`shortService` foreground service for any background
audio, waiving only the while-in-use requirement for exact-alarm holders
on `USAGE_ALARM`; Play requires target 36 since 2026-08-31; `USE_EXACT_
ALARM` is policy-allowed for calendar apps with event notifications;
`USE_FULL_SCREEN_INTENT` is auto-granted on Play only to alarm and calling
apps (since 2025-01-22), granted by default when installed outside Play,
and without it a full-screen intent degrades to a 60 s heads-up on the
lock screen; from API 33 a full-screen intent never launches while the
user is using the device (heads-up instead); revoking `SCHEDULE_EXACT_ALARM`
silently deletes every exact alarm and sends no broadcast, so reconcile
re-checks `canScheduleExactNotifications()`.

### 6.2 iOS (Phase 4, needs the Mac)

The iOS runner has never been built (no `Podfile`, no entitlements,
deployment target 15.0, no usage strings). Reminders: the notification
plugin with `interruptionLevel: timeSensitive` (capability only, no Apple
approval), a rolling window under the 64-pending cap (A7 already fits),
`willPresent` implemented or foreground notifications vanish. Alarms:
`flutter_alarmkit ^0.4` on iOS 26+ (`NSAlarmKitUsageDescription`, a WidgetKit
extension, weekly-by-weekday native recurrence — the planner keeps
materialising per occurrence, so the mapping is one `fixed` alarm per
`PlannedFire`), a runtime version check, and below 26 a time-sensitive
notification with a ≤30 s sound. Background-audio ringing on older iOS is
a Guideline 2.5.4 rejection risk and is **not** attempted. Critical alerts
are not requested (A-not-critical, §0).

### 6.3 Desktop and web

`AlertAvailability.isSupported = !kIsWeb && (Android || iOS)`; the
`NoOpAlertGateway` reports `unsupported` permissions, schedules nothing,
and every alert surface still edits and persists (they ring on the phone
after sync). The l10n key `notSupportedOnPlatform` already exists for the
settings rows.

## 7. Tests

`tests-explicitly-welcome` applies. Every `path_provider` channel stub in
`test/` (about 38 files) needs the same for the two new plugins **or**, far
better, the `NoOpAlertGateway` is what tests get through GetIt so no
widget test ever touches a plugin channel.

- `test/models/event_alert_test.dart` — codec, `describe` table, both
  offset sets surviving an all-day flip.
- `test/utils/alert_planner_test.dart` — table tests under an explicit
  `now`: timed / all-day / one-time / weekly with skips and `endDate` /
  workdays with a holiday profile / horizon caps (per-alert, days, total)
  / past-today exclusion / spring-forward gap / disabled alert / five
  alerts on one event.
- `test/services/alert_scheduler_test.dart` — `FakeAlertGateway` recording
  `schedule`/`cancel`: diff semantics (an unrelated edit leaves a snooze
  alone), OS-truth pruning, multi-database payload filter, late-fire
  "Missed" path, serialized chain (`FakeAsync` — seed the tail with `null`).
- `test/services/event_alert_service_test.dart` — in-memory DB
  (`openTestDatabase`), CRDT stamping, `replaceForEvent` tombstones,
  cascade on `deleteById`, backup round-trip incl. the strand rule.
- `test/database/` — parity, the two partial indexes in `query_plan`,
  statement count for `getAllActive` (one statement).
- `test/bloc/calendar_alerts_test.dart` — create/update/delete/skip each
  call `reconcileEvent` exactly once; `ToggleEventAlert`.
- `test/widgets/alert_editor_sheet_test.dart`, `alarm_page_test.dart`,
  `quick_alarm_sheet_test.dart`, `alerts_page_test.dart`; the alert sheet
  and the quick sheet join `sheet_bottom_clearance_test.dart`.

## 8. Phases and prompts

Execution model: Fable plans and reviews; Opus implements each phase from
the prompt below; Sonnet takes the mechanical parts (ARB ×3, DDL, gen-l10n).
Each phase ends with `dart analyze lib`, `flutter test`, `flutter run -d
windows` still launching, and a device pass through the QA harness. The
owner's real phone is needed for Phase 0's OEM questions and for every
"ring" acceptance; the emulator cannot answer battery or vendor behaviour.

### Phase 0 — Investigation (started 2026-09-14)

Branch `spike/event-alerts-ring`, throwaway. Both plugins added,
permissions declared, a `lib/spike/` service with four Developer Options
buttons (ring via `alarm`, ring via an insistent notification, a reminder,
a permission dump), a minimal ring page. Scenarios S1–S11: permission
defaults on install; ring with the app in front; screen off and locked;
app killed (`am kill`, not force-stop); Doze (`deviceidle force-idle`);
silent ringer and Do Not Disturb; the insistent-notification alarm locked
(activity launch, sound loop, background Stop); reminder actions and a
cold-start tap; the `restricted` standby bucket; reboot before the fire
time (if the harness rules allow a guest reboot); late fire. Evidence:
`qa state` (awake/locked), screenshots, `dumpsys alarm`, `dumpsys
notification --noredact`, `dumpsys audio` / `media.audio_flinger`, `[spike]`
logcat lines. Deliverable: the report in §10 and a verdict on A5. The
owner's phone repeats S2–S7 and S9 (§9).

### Phase 1 — One-time alerts (3 sessions)

Paste-ready prompt for Opus:

> Implement Phase 1 of `docs/event-alerts-roadmap.md` on top of the current
> `main`. Read that roadmap's §1–§7 and §10 first, then `COPILOT_CONTEXT.md`,
> the `anta-context`, `calendar-events`, `drift-migrations` and `l10n`
> skills, and `docs/calendar-events-feature.md` §3, §6 and §10. Scope: the
> v40 schema and migration (§4.1) with parity and query-plan tests; `EventAlert`
> + `EventAlertDao` + `EventAlertService` + the `EventAlerts` facade (§3.1);
> `AlertRegistrationDao`; `AlertPlanner` (pure, explicit `now`) and
> `AlertScheduler` for **one-time events only** (horizon rules still apply
> but the walk may stop at the first occurrence); `AlertGateway` with
> `AndroidAlertGateway` on the backend §10 chose and `NoOpAlertGateway`,
> registered in `injection.dart` behind `AlertAvailability`; `AlertPayload`;
> `PendingNavigationQueue` drained from `main.dart` after the restore
> post-frame callback plus a `resumed` lifecycle branch that reconciles;
> `CalendarPage(initialDay:, initialEventId:)` optional parameters that
> select the day and open the detail sheet after `CalendarPageLoaded`
> (through the shared bloc — `getIt<CalendarBloc>()` is a factory and must
> not be used); the editor Alerts rows and `AlertEditorSheet` (§5.1–5.2)
> including the remove switch; the detail-sheet rows (§5.3); the row badges
> (§5.4); `AlarmPage` + `AlertRingController` (§5.5) with Stop / Snooze /
> Open / Keep and the A3 removal + Undo; the Calendar settings Alerts
> section (§5.7) with the three permission rows, the two defaults, snooze
> and silence sliders and the test button; settings keys (§4.4) with a bulk
> getter and decoders; backup key `eventAlerts` with the strand rule (§4.2);
> `.ics` VALARM (§4.3); ARB keys ×3; the tests in §7 that apply to one-time
> events. Copy the build steps from §10.2 and the API gotchas from §10.5
> verbatim: `warningNotificationOnKill: false`, `androidStaleAfter: 30
> min`, ignore `Alarm.ringing`'s initial empty set, dedupe the cold-start
> payload, cancel handled full-screen notifications at once, hoist the
> non-const `Int32List`, `cancel({required id})`, strip `READ_EXTERNAL_
> STORAGE` with `tools:node="remove"`. A15 must be settled first or
> `flutter run -d windows` fails on `atlbase.h`. Hard rules: never GetIt
> for DB-backed services; every plugin call behind the gateway;
> `Alarm.set()` throws — catch it; permission requests only from a user
> action; no code comments beyond `///` doc comments; no new markdown
> docs. Before finishing: `dart run build_runner build
> --delete-conflicting-outputs`, `flutter gen-l10n` (check untranslated.txt),
> `dart analyze lib`, `flutter test`, `flutter run -d windows` reaches the
> browser, and a `qa run` device pass: create a one-time event 2 minutes
> ahead with an alarm, lock the screen (`adb shell input keyevent
> KEYCODE_SLEEP`), confirm the alarm page appears (`qa state`, screenshot),
> Stop, confirm the registration is `stopped` and the event still exists;
> repeat with the remove switch on and confirm the event is tombstoned and
> Undo restores it. Report every deviation from the roadmap in a
> "Deviations" list, and do not edit the roadmap yourself.

### Phase 2 — Recurring, re-arming, hub, quick alarm (2 sessions)

> Implement Phase 2 of `docs/event-alerts-roadmap.md` on the Phase 1 tree.
> Scope: the full horizon planner (§2.5) over every `RecurrenceRule`
> including skips, `endDate`, retroactive and the holiday-reading rules,
> re-planned on every resume; re-arm on Stop; snooze registrations (§2.3
> `kind = snooze`, A8) that survive unrelated reconciles; the late-fire
> "Missed" path (§3.4, A10); the Alerts hub page and drawer row (§5.6) with
> `ToggleEventAlert`; the quick-alarm row and sheet (§5.8); alerts inside
> event templates (`calendar_event_templates` gains an `alerts` JSON column
> in a v41 migration — additive, backup key rides `eventTemplates`); the
> agenda's `EventSummaryProvider` subtitle segment for `removeAfterAlert`;
> the planner and scheduler table tests for recurring rules (§7). Device
> pass: a Mon/Wed/Fri event with an alarm, confirm two registrations in
> `dumpsys alarm`, fire the first (set it 2 minutes ahead), Stop, confirm
> the third occurrence is now registered; cancel Wednesday through Skip
> this day and confirm its registration is gone; snooze once and confirm an
> unrelated event edit leaves the snooze in place. Deviations list, no
> roadmap edits.

### Phase 3 — Power and harness (1–2 sessions)

> Implement Phase 3 of `docs/event-alerts-roadmap.md`: sound picker with
> preview, volume fade-in and vibration pattern through the gateway (only
> what the chosen backend supports), the presence prompt on the alarm page
> for `tracksPresence` events (A13: an "I was there" tonal button that
> dispatches `SetOccurrencePresence` and nothing else), per-template
> defaults, `DevOptions.fireNextAlertInTenSeconds`, and the QA verbs
> `qa alerts` (list pending registrations from `dumpsys alarm` and the
> plugin's pending list, `--cancel` clears the QA database's entries) and
> `qa fire` (schedules the next pending registration 10 s ahead via a
> `--define`-gated seam). Update `docs/qa-harness.md` and the qa-emulator
> skill for the two verbs.

### Phase 4 — iOS (2–3 sessions, on the Mac)

> First make the iOS runner build at all (Podfile, deployment target,
> usage strings, Firebase pods). Then implement `DarwinAlertGateway` per
> §6.2: reminders through the notification plugin with `timeSensitive`,
> alarms through `flutter_alarmkit` on iOS 26+ with a runtime check and the
> time-sensitive fallback below, `willPresent` handling, the 64-pending
> window (A7 already fits), the widget extension, and the device pass on a
> real iPhone (lock screen, Focus, silent switch, reboot).

## 9. Verification checklist (owner's phone, after each phase)

Before Phase 1: the **phone pass of the spike itself** (§10.4 recipe —
release-signed build of `spike/event-alerts-ring`, never uninstall):
PIN keyguard, overnight Doze, reboot before the fire time, Force stop,
DND access, audibility. Note the vendor and OS version in §10.

- [ ] Fresh install: no permission prompt at launch; the first saved alert
      asks for notifications; denying leaves the alert saved.
- [ ] One-time alarm, phone locked, silent switch on: rings, page shown,
      Stop stops, event remains.
- [ ] Same with *Remove after it rings*: event gone from the day list, Undo
      restores it.
- [ ] Alarm with the app swiped away from Recents (not force-stopped).
- [ ] Alarm after a reboot with the app not opened since.
- [ ] Alarm under Do Not Disturb and with battery set to Restricted (the
      OEM question; note the vendor and OS version).
- [ ] Reminder banner with Snooze / Done; tap opens the detail sheet on the
      right day after a cold start.
- [ ] Recurring: Stop on Monday leaves Wednesday and Friday registered
      (`adb shell dumpsys alarm | grep -i anta`); Skip this day on
      Wednesday removes it.
- [ ] Database switch: the other database's alarm still rings, the page
      names it, Open switches.
- [ ] Backup restore: alerts return, no duplicate registrations after the
      next launch.
- [ ] Windows: `flutter run -d windows` launches; alert rows edit and save;
      settings rows read "Not supported on this platform".

## 10. Phase 0 — investigation results (2026-09-14)

Run by an Opus agent on `emulator-5554` (Google Play image, **API 36 /
Android 16**, 427×952 dp, **no secure lock** — "locked" below means
screen-off plus the swipe keyguard), 15:05–15:37 EEST, always against the
isolated `qa` database through `tool/qa/qa.cmd run --fresh --seed
tool/qa/fixtures/basic.json`. Branch `spike/event-alerts-ring`, commit
`359f317` (14 files: pubspec, gradle, manifest, `lib/spike/`, a Developer
Options card, the regenerated desktop registrants, a generated 2 s WAV).
`main` untouched. Resolved: `alarm` 5.13.0, `flutter_local_notifications`
22.3.1 (+ `_windows` 3.x, `_linux` 8.0.1, `_web` 1.0.0), `timezone` 0.11.1,
`flutter_timezone` 5.1.0, new transitive `rxdart` 0.28.0. The spike debug
APK is still installed on the emulator (next `flutter run` from `main`
reinstalls the stock build); DND, ringer, volumes, battery, idle state and
standby bucket were restored; no pending alarms were left.

### 10.1 The three surprises

1. **`flutter_local_notifications` breaks `flutter build windows` here.**
   Its endorsed Windows implementation is an **FFI plugin**, compiled by
   CMake regardless of any Dart-side platform guard, and its `plugin.cpp`
   includes `atlbase.h`, which this machine does not have (the Visual
   Studio *C++ ATL* component is not installed): `error C1083: Cannot open
   include file: 'atlbase.h'`. `alarm` declares only `android`/`ios` and is
   desktop-clean. See A15.
2. **The two backends use different AlarmManager tiers.** `alarm` schedules
   `RTC_WAKEUP flags=0x5` (`STANDALONE|ALLOW_WHILE_IDLE`, i.e.
   `setExactAndAllowWhileIdle`, no `Alarm clock:` block). The notification
   plugin's `AndroidScheduleMode.alarmClock` schedules `flags=0x3`
   (`STANDALONE|WAKE_FROM_IDLE`) **with** an `Alarm clock:` block and
   becomes the system's *next wake from idle* and *next alarm clock*
   (the status-bar icon). `setExactAndAllowWhileIdle` is Doze-exempt but
   rate-limited in deep idle (about one per nine minutes per app); the
   `alarm` package does not let the app choose. Upstream lever, not ours.
3. **`am force-stop` cancels every pending alarm of both backends** —
   `dumpsys alarm` shows `Reason=pi_cancelled` at the force-stop
   timestamp; nothing rings until the app is opened again and reconciles.
   A background `am kill` is fully survivable. Architectural, not a plugin
   bug; it goes in the settings copy and the hub banner ("Force stop
   disarms alarms").

Runner-up: a **cold-start tap delivers the payload twice** — once through
`onDidReceiveNotificationResponse`, once through
`getNotificationAppLaunchDetails()`, within 8 ms. Dedupe on the id.

### 10.2 Build checklist (copy into Phase 1)

- `flutter build apk --debug` succeeded first try (63 s), no merge
  conflicts. **PowerShell 5.1 eats the `^`** in `flutter pub add
  alarm:^5.13.0` (pins an exact version); add from Git Bash or fix by hand.
- `android/app/build.gradle.kts`: `isCoreLibraryDesugaringEnabled = true`
  in `compileOptions` + `coreLibraryDesugaring("com.android.tools:desugar_
  jdk_libs:2.1.4")` — mandatory for the notification plugin even if
  nothing is scheduled. No multidex change. `gradle.properties` already
  carries `android.builtInKotlin=false` / `android.newDsl=false`, which
  `alarm` needs; keep them. Kotlin 2.2.20 already satisfies `alarm`.
- Manifest: the notification plugin's three receivers
  (`ActionBroadcastReceiver` — without it Stop/Snooze actions do nothing —
  `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` with
  `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` / `QUICKBOOT_POWERON`
  filters); permissions `POST_NOTIFICATIONS`, `USE_EXACT_ALARM`,
  `SCHEDULE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `VIBRATE`, `WAKE_LOCK`,
  `RECEIVE_BOOT_COMPLETED`; `showWhenLocked` + `turnScreenOn` on
  `MainActivity` (merged intact; `alarm` ≥ 5.0 no longer needs them, the
  notification-plugin full-screen intent does).
- `alarm` brings its **own** manifest: all of the above plus
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`,
  `ACCESS_NOTIFICATION_POLICY`, **`READ_EXTERNAL_STORAGE`**, its
  `AlarmReceiver`, `BootReceiver` (`BOOT_COMPLETED`) and `AlarmService`
  (`foregroundServiceType="mediaPlayback"`). Strip `READ_EXTERNAL_STORAGE`
  with `tools:node="remove"`; `SCHEDULE_EXACT_ALARM` stays (moot while
  `USE_EXACT_ALARM` holds, but Play-Console-visible).
- `alarm` needs an audio asset under `flutter: assets:` (or
  `assetAudioPath: null` for the device default); a 2 s 880 Hz WAV from a
  15-line Python `wave` script looped fine at 44.1 kHz.
- `flutter pub get` rewrites the tracked desktop registrants
  (`windows/`, `linux/`, `macos/`); commit them with the change.
- One warning: `alarm` and `flutter_timezone` apply the Kotlin Gradle
  Plugin like `google_sign_in_android` already does — on the built-in-
  Kotlin migration watchlist, not a failure.
- `dart analyze lib` stayed clean throughout.

### 10.3 Scenarios

| # | Scenario | Observed | Verdict |
| --- | --- | --- | --- |
| S1 | Permissions after install | `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `WAKE_LOCK`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, the FGS pair and `ACCESS_NOTIFICATION_POLICY` all `granted=true` at install; `POST_NOTIFICATIONS` false until the runtime dialog (accepted via `tap id:permission_allow_button`). `canScheduleExactNotifications()` true with no prompt; `requestExactAlarmsPermission()` and `requestFullScreenIntentPermission()` return true without leaving the app. | pass |
| S2 | `alarm`, foreground | Ring 145 ms after due; `Alarm.ringing` → `rootPush` ring page with payload; `MediaPlayer` in our process, `usage=USAGE_ALARM`, `state:started`, a 2 s asset looping 62 s; Stop stops. Channel `alarm_plugin_channel` importance 4, `ONGOING|NO_CLEAR|FOREGROUND_SERVICE`, `category=alarm`, full-screen intent set. | pass |
| S3 | `alarm`, screen off + keyguard | 53 ms late; FGS start allowed (`ALARM_MANAGER_WHILE_IDLE`); screen on, app resumed, full-screen ring page. PIN keyguard untested (none on the image). | pass |
| S4 | `alarm`, app killed (`am kill`) | Native FGS at +315 ms, new process, Flutter engine up, `Alarm.ringing` at +1,783 ms with the payload; ring page shown. `getNotificationAppLaunchDetails()` says `didLaunch=false` — the `alarm` relaunch is invisible to the notification plugin. | pass |
| S5 | Doze | Deep idle not reachable on this AVD (`mMotionSensor=null`, stuck at INACTIVE). At INACTIVE, screen off, unplugged: `alarm` 29 ms late, notification posted. | partial — phone |
| S6 | DND + silent | *Total silence* (`zen_mode=2`) mutes `STREAM_ALARM` for everyone: `alarm` still shows the page and vibrates (`mutedState:opPlayAudio`), the insistent notification posts with no audio at all; `bypassDnd` refused (needs user-granted DND access). *Priority* (`zen_mode=1`): both audible — `alarm` from our process, the notification from SystemUI on `USAGE_ALARM`. | partial by design |
| S7 | Notification-plugin insistent alarm, screen off | Full-screen intent launched the activity from screen-off at +55 ms with the payload; `INSISTENT` flag real (`additionalFlags [4]`), importance 5, 36 s of looping from a one-shot channel sound; the **Stop action ran in the background isolate** (`showsUserInterface: false`) and killed the sound. | pass |
| S8 | Reminder | Banner, `AUTO_CANCEL`, `category=reminder`; Snooze action → background isolate; cold-start body tap → payload delivered twice (§10.1). | pass |
| S9 | Standby bucket `restricted` | Not forceable: `am set-standby-bucket` reports success, `get-standby-bucket` stays WORKING_SET for a just-foregrounded app. Both fired on time. | partial — phone |
| S10 | Reboot before fire | **Not run**: the qa-emulator skill forbids restarting the emulator. Both boot receivers are registered (`dumpsys package` shows `BootReceiver` filters); `alarm`'s `androidStaleAfter` never exercised. | not run — phone |
| S11 | Late fire | Best datum is S4 (+315 ms native, +1.8 s Dart cold start). Nine firings, nothing dropped, median ~40 ms, worst warm 145 ms. | partial |
| S12 | `am force-stop` with alarms pending | Both `pi_cancelled` at the force-stop instant; nothing rang. | fail, both |

### 10.4 Verdict and amendments

**A5 stands: `alarm` for the Alarm tier, the notification plugin for the
Reminder tier**, subject to the owner's phone pass. The `alarm` package was
the only path that produced a full-screen ring with its own looping audio
and a working Stop in every state tested (foreground, screen-off, killed),
owns the audio (fade, enforced volume, loop, per-alert sound without a
channel per sound), degrades under Total Silence to screen + vibration
rather than to nothing, and is desktop-clean. The notification plugin's
insistent path is a **proven fallback** (S7) and is the stronger
*scheduling* tier (`setAlarmClock`); if the phone shows `alarm`'s
`setExactAndAllowWhileIdle` deferring overnight, the gateway switches the
Alarm tier to it in one place. The Reminder tier cannot be built on
`alarm` (it always plays on the alarm stream, which breaks the silent-mode
contract), so the notification plugin stays, which makes A15 a
prerequisite of Phase 1.

Only a real phone can still answer: deep Doze overnight (and whether
`setAlarmClock` is measurably better), the `restricted`/`rare` bucket, a
reboot with the stale-after policy, a **PIN keyguard** (the single most
important untested thing — whether the page shows above the lock), OEM
battery managers, audibility/fade/volume, and the DND-access flow. Recipe
for the phone: build the spike branch **release-signed** (`.\build_release
.bat arm64`, then `adb install -r`; a debug APK cannot install over the
release app and uninstalling would wipe data), run S2–S7 and S9–S10 by
hand, then reinstall `main`.

### 10.5 API gotchas to carry into Phase 1

- `alarm`: `AlarmSet` and `AlarmException` are not exported from
  `package:alarm/alarm.dart` (import `utils/alarm_set.dart` and
  `utils/alarm_exception.dart`); `AlarmException.code` is an
  `AlarmErrorCode`; `Alarm.set` both returns `Future<bool>` and throws;
  `warningNotificationOnKill` defaults **true** (set false, or declare
  `NotificationOnKillService`); `androidStaleAfter` defaults to 15 min and
  drops stale alarms as `AlarmDropped(cause: staleAtBoot)` on
  `Alarm.events` — pass 30 min for A10 and map the drop to the "Missed"
  notification; `Alarm.ringing` emits an **empty set on subscribe**
  (rxdart `ValueStream`) — guard `isEmpty` or every launch pushes a ring
  page; its channel is created lazily at importance 4 and cannot be
  configured from Dart.
- Notification plugin: everything is named, including
  `cancel({required int id})`; `additionalFlags: Int32List.fromList([4])`
  is not const, so hoist it and drop `const` from the details;
  `bypassDnd` is silently downgraded without DND access (one warning at
  init); `AndroidNotificationAction(id, title, showsUserInterface: false)`
  routes to the background isolate even while the app is in front; a
  posted full-screen-intent notification **keeps the right to launch the
  activity later** (a leftover one re-fired when the screen went off) —
  cancel them as soon as they are handled; the cold-start double delivery.
- `flutter_timezone`: `getLocalTimezone()` returns `TimezoneInfo`; use
  `.identifier` (`Europe/Bucharest` here) with `tz.getLocation`.
- Harness: `cmd media volume` does not exist on API 36 — use `cmd audio
  set-volume <stream> <index>` / `get-stream-volume` / `set-ringer-mode`;
  `dumpsys deviceidle force-idle` cannot reach deep idle on this AVD;
  remember `dumpsys battery reset`; a process kill **loses the
  developer-mode unlock** (five taps again); `qa scroll-to` needs `--up`
  for targets above the viewport; run `qa steps` from Git Bash.

## 11. Risks

- **OEM battery killers.** Samsung, Xiaomi and Huawei delay or drop alarms
  from apps they consider idle. Mitigation: the settings row, the hub
  banner, and the spike's measurements on the owner's phone.
- **Plugin churn.** `flutter_local_notifications` broke its API in 18, 19,
  20 and 21; `alarm` started throwing in 5.9. Pin caret ranges, wrap every
  call in the gateway, and keep the fallback path alive.
- **First plugin, first permission.** Nothing in the app has ever declared
  a permission or handled a channel; the `NoOpAlertGateway` is what keeps
  `flutter test` honest. The Windows build is a separate matter (A15):
  the notification plugin's FFI implementation compiles no matter what
  Dart does.
- **Force stop disarms everything** (§10.1, both backends, by Android
  design). Recovery is the next launch; there is no background path.
- **Deep Doze is unmeasured.** The `alarm` package's
  `setExactAndAllowWhileIdle` is rate-limited in deep idle; two alerts
  inside nine minutes (a reminder at 06:50 and an alarm at 07:00) may see
  the second deferred. The fallback path's `setAlarmClock` is not. Only
  the phone pass can tell; the gateway keeps the switch cheap.
- **Cold-start navigation.** `_navigator` force-unwraps
  (`app_navigator.dart:50`); the queue must never push before the first
  frame, and the alarm page must not be restored as a last location.
- **`EventSkips` is a process-global static.** Any planning outside the
  main isolate would see it empty; the background notification handler is
  therefore payload-only and never plans.
- **Intl.defaultLocale is never set** (`event_time_formatter.dart:69`), so
  any context-free time formatting in a notification body renders in the
  system locale; format the payload's `timeLabel` on the UI thread at
  schedule time.
- **iOS is unbuilt.** Phase 4 starts with a plain build.

## 12. Deferred, not planned here

- Negative offsets (after start), "time to leave" and location triggers.
- A per-category default alert (categories have no CRDT; templates own
  defaults — `category-scaling-roadmap.md:826-828`).
- Per-occurrence alert overrides (would inherit the sparse-delta table
  shape and its device-local status).
- A "now" line or overdue styling in the day panel (the clock-free read
  path rule; `hideEnded` is the only axis that reads the clock).
- Time zone and clock-change broadcasts on Android (resume covers the
  common case).

## 13. Docs to update when a phase ships

`CLAUDE.md` commands section and the `verify` skill (the A15 prerequisite
for `flutter run -d windows`, and `qa alerts` once it exists);
`COPILOT_CONTEXT.md` (a calendar bullet for alerts: the two tiers, the
planner/registry split, the never-ring list, the multi-database rule);
`.claude/skills/calendar-events/SKILL.md` (schema lineage v40, the seven
services become eight — `EventAlertService` joins the `Future.wait`, the
hard rules for `EventAlerts`, the reconcile-trigger table); `docs/calendar-
events-feature.md` (§11 row replaced by a pointer here and a new §12 "Event
alerts"); `docs/qa-harness.md` and the qa-emulator skill (Phase 3 verbs);
`CLAUDE.md` if a new command (`qa alerts`) becomes routine.
