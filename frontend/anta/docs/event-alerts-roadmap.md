# Event Alerts — Roadmap & Phase Prompts (2026-09-14)

**Status: PROPOSED, nothing shipped. Phase 0 DONE on the emulator
(2026-09-14, branch `spike/event-alerts-ring`, commit `359f317`, results in
§10); the owner's phone pass of the same spike is owed (§9, §10.4).**
Phases 1–4 were split on 2026-09-15 into the prerequisites P1–P5 and
Sessions 1–9 of §8; **Session 1 DONE 2026-09-15** (committed as
`69fd76d`) and **Session 2 DONE 2026-09-15** (Opus, Fable-reviewed with
three fixes, 5,153 tests green; deviations recorded under each prompt).
**Session 3 DONE 2026-09-16** — the plugins are in, `AndroidAlertGateway`
is registered on Android, and a test alarm rings on a slept emulator
screen (5,172 tests green; the owner's phone pass is owed). Session 4 is
next. Decisions A1–A14 (§1)
were proposed on 2026-09-14 and **confirmed as proposed on 2026-09-15**
(P1, P2, P5 in §8.1); A5 stands on the emulator spike alone because the
owner **waived the phone pass** (P3) — the §9 checklist after Session 4 is
the first real-phone evidence; A15 (the Windows build) was found by the
spike and **settled the same day** — the ATL component is installed and
the spike branch builds for Windows.
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

**Follow-up roadmap (2026-09-22):**
[event-alerts-os-integration-roadmap.md](event-alerts-os-integration-roadmap.md)
— the phone treating an ANTA alarm as an alarm (`setAlarmClock` through a
fork of the `alarm` plugin, which also ends the `content://` copy of §5.2),
native snooze, an upcoming-alarm notice, an alarm log, the Android 16
session chip and AlarmKit for Session 9. Nothing there reopens A1–A15.
**OS-1 DONE 2026-09-22**: the Alarm tier is armed by the local fork
`packages/alarm/` with `AlarmManager.setAlarmClock` (Doze-exempt, the
phone's next alarm, a show intent opening the Alerts hub), the `content://`
copy of §5.2 is gone, and the fallback channel is `alerts_alarm_v2` with a
real alarm sound; the §11 deep-Doze row is closed on the emulator and the
overnight phone check moved to that roadmap's §9. **OS-2 DONE 2026-09-22**:
native snooze on the plugin's own notification, the move written into the
registry by the next reconcile, a snooze seen with Dart up told from a Stop.
**OS-3 DONE 2026-09-22**: the upcoming-alarm notice at `fireAt − lead` with
Skip (a foreground intent the calendar applies with Undo) and Open.
**OS-4 DONE 2026-09-22**: the `missed` state, the hub's Recent section over
the settled registrations, and notifications carrying the event's colour,
icon and description excerpt. **OS-5 DONE 2026-09-23 (chip only)**: the session chip — one ongoing
notification per acknowledged alarm, promoted with a progress bar on
Android 16 where the user allows it, a chronometer otherwise, with *Open
note* and *Done* — through a native `SessionChip` behind
`AlertGateway.showSessionChip`. **Session 6 DONE 2026-09-23 for the quick
alarm** (§5.8: the picker's `Alarm…` row, always reachable, and
`QuickAlarmSheet`; the template-alerts half with its v41 migration is still
open) and **OS-5 completed the same day** with the Quick Settings tile and
the launcher shortcut into that sheet.

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

## 1. Decisions (proposed 2026-09-14; A1–A14 confirmed as proposed 2026-09-15, §8.1)

| Id | Question | Proposed | Why |
| --- | --- | --- | --- |
| A1 | Vocabulary | Row **Alerts**; each alert is a **Reminder** or an **Alarm**. Code: `EventAlert`, `AlertMode { notify, ring }`. | "Alarm" is the owner's word and translates cleanly (de *Alarm*, ro *alarmă*); "Ring" is already `todayStyleRing` in the appearance vocabulary. |
| A2 | Cardinality | Up to **5** per event, one card each in the editor. | Google Calendar's cap; a row per alert keeps `calendar_events` narrow. |
| A3 | Remove after it rings | A flag on the **event** (`remove_after_alert`), off by default, on for quick alarms. Stop/Done on the first acknowledged alert soft-deletes the event through `CalendarEventService.deleteById` (cascade + tombstone) with a 5 s Undo. Cancelling such an alarm before it rings deletes the event too. | It is a statement about the event's purpose, not one alert's; a soft delete syncs and survives a mistake. |
| A4 | All-day events | Each alert carries `days_before` + `day_minute`; default **09:00 on the day**, changeable in Calendar settings. | The model has no anchor for all-day events; Apple and Google both default to 09:00. |
| A5 | Ringing backend — **emulator spike confirms, phone pass owed** | `alarm` 5.13 for the Alarm tier; `flutter_local_notifications` 22.3 for the Reminder tier. Fallback, proven in the spike (§10.3 S7): an insistent alarm-stream notification from the reminder plugin (`AndroidScheduleMode.alarmClock`, `fullScreenIntent`, `additionalFlags [4]`), switchable in the gateway alone. | Purpose-built, actively maintained (13 releases in 2026), holds the foreground service Android 17 now demands for background audio, owns the audio, degrades under Total Silence to screen + vibration; the fallback needs no second plugin. Caveat (§10.1): `alarm` used `setExactAndAllowWhileIdle`, the fallback `setAlarmClock` — **resolved by the OS-1 fork (2026-09-22)**: the Alarm tier arms with `setAlarmClock` too. |
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
  sound: String?,             // null = follow the app setting; '' or
                              // 'system:default' = the phone's default alarm;
                              // or a content:// URI. Alarm tier only — §5.2.
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
timed:   fireAt = DateTime(day.year, day.month, day.day,            // local
                           0, time.startMinute - offsetMinutes)
all-day: anchor = day − daysBefore (date-only UTC arithmetic, then local)
         fireAt = DateTime(anchor.year, anchor.month, anchor.day,
                           0, dayMinute ?? defaults.allDayMinute)
```

**Wall-clock constructor, never `midnight.add(Duration)`** (corrected
2026-09-15 after a probe on this machine): local midnight carries the
offset in force *before* a DST transition and `add` is absolute time, so
`DateTime(y, m, d).add(Duration(hours: 7))` is 08:00 on the spring-forward
day and 06:00 on the fall-back day. The constructor form takes the minute
component out of range on purpose — Dart normalizes it, so `startMinute −
offsetMinutes < 0` lands on the previous day at the right wall time — and
rolls a time inside a spring gap forward to the next valid instant, which
is exactly A14.

`day` is the date-only UTC occurrence day from `occursOnUtcDay`; the
`y/m/d` fields are read off it and rebuilt as a **local** wall time. The
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
| `AlertPlanner` | `lib/utils/alert_planner.dart` | Pure. Walks only the days a rule can name (`RecurrenceRule.candidateDaysIn`, 2026-09-22) and skips an event whose end date is behind today, so the past costs no `occursOnUtcDay` at all (`alert_planner_test.dart`, "work budget"). `plan({events, alertsByEvent, defaults, horizon, now}) → List<PlannedFire>`. The codebase's first clock seam: `now` is a parameter, the caller reads `DateTime.now()` once. |
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
  still typed `Future<bool>`; the gateway catches and reports. **Since OS-1
  (2026-09-22) the plugin is the local fork `packages/alarm/`** (base
  5.13.2), whose `AlarmScheduler.setExactAlarm` arms with
  `AlarmManager.setAlarmClock`: exempt from Doze and the standby buckets by
  the platform's own definition, shown as the device's next alarm
  (status-bar icon, lock-screen line, Quick Settings,
  `getNextAlarmClock()`), and carrying a show intent
  (`com.gdelataillade.alarm.action.SHOW`) that `MainActivity` turns into an
  `OpenAlertsHubIntent` — the Alerts hub, cold or warm. The inexact fallback
  for a revoked exact-alarm permission is upstream's, unchanged. The
  Reminder tier never touches this plugin. **OS-2 (2026-09-22):** the entry
  also carries `androidSnoozeDuration` and a Snooze button, so the plugin's
  own notification defers a ring with no Dart running; the move reaches the
  registry through `Alarm.events` → `AlertGateway.takeMoves()` at the top of
  the next reconcile (`kind = snooze`, same os id), acknowledged after the
  write — see `calendar-events-feature.md` §12 "Native snooze". **OS-3
  (2026-09-22):** an upcoming notice is armed beside every planned alarm-tier
  fire at `fireAt − lead` (`alert_notice_lead_minutes`, default 2 h, 0 = off),
  never a registration and hidden from the OS-truth pass; its Skip opens the
  app and cancels the next fire with an Undo — §12 "Upcoming-alarm notice".
  **OS-4 (2026-09-22):** the row a Missed notice is posted for reads
  `missed`, the hub gains a *Recent* section over the settled rows, and the
  notifications carry the event's colour, icon and description excerpt —
  §12 "Alarm log and richer content".
  **OS-5 (2026-09-23):** an acknowledged ring posts the session chip (B8) —
  §12 "Session chip"; the tile and shortcut (B9) shipped the same day into
  Session 6's `QuickAlarmSheet` — §12 "Tile and shortcut".
- **Fallback alarm (notification plugin):** `alarmClock` mode,
  `fullScreenIntent: true`, `category: alarm`, `audioAttributesUsage:
  alarm`, `additionalFlags: Int32List.fromList([4])`, `ongoing: true`,
  `timeoutAfter: silenceAfter`; a `max`-importance `alerts_alarm_v2` channel
  (created with the phone's default alarm sound on the alarm stream since
  OS-1; the soundless `alerts_alarm` is deleted at initialize).
  No stale cut-off is possible (the system posts it), so A10's "Missed"
  path is done by reconcile on the next launch.
- **Late fire (A10; rule corrected 2026-09-15 at the Session 2 review,
  source corrected 2026-09-16 at the Session 3 review):** `alarm` drops a
  boot-recovered alarm older than `androidStaleAfter` (set to 30 min) as
  `AlarmDropped(cause: staleAtBoot)` on `Alarm.events`, but that event
  carries an id and nothing else and the alarm is already unsaved when it
  is delivered, so the gateway cannot compose a "Missed" from it and does
  not subscribe. The registry path on launch/resume is the **only** Missed
  source for both tiers; because `androidStaleAfter` equals
  `kLateFireGrace`, a dropped alarm's row is past the grace window at the
  very launch that delivers the drop. It measures lateness (`now −
  fire_at`) in three windows. **In flight** (under `kLateFireGrace`, 30 min): the row stays
  `pending` and is excluded from the diff — never cancelled, never
  re-scheduled, never reported — because the launch reconcile that the
  plugin's own relaunch of the app triggers is post-frame and lands
  *before* `Alarm.ringing` emits (§10.3 S4: +1.8 s); the ring handler is
  what marks it `fired` / `stopped`. A row the ring handler has marked
  `fired` is neither pending nor in flight, yet `alarm` keeps the entry in
  its storage until Stop, so reconcile also seeds its cancel set with
  `AlertGateway.ringingIds` — without that the resume reconcile the alarm
  page's own appearance provokes would find an entry nobody planned and
  silence it two seconds into the ring (Session 3 review). **Missed** (30
  min to 24 h): marked
  `cancelled`, and only an **alarm-tier** row (its alert resolves to
  `ring`) earns the quiet "Missed: {title} at {time}" — a reminder is
  delivered by the OS with no callback to the app, so a gone, past-due
  reminder row is indistinguishable from a delivered one and reporting it
  would turn every un-tapped reminder into a "Missed". **Stale** (over
  24 h): `cancelled`, quiet — **and its platform entry cancelled too
  (2026-09-22)**: the notification plugin re-arms every reminder it held when
  the phone boots and the OS fires a past one immediately, so a reminder for
  a session more than a day gone can be sitting in the shade, no longer
  *pending* and therefore invisible to the OS-truth pass; `AlertGateway.cancel`
  is what takes it down. Under a day it is left alone, like every other
  delivered reminder. Then the horizon is re-planned. A user
  **Force stop** cancels every pending alarm on both backends (§10.1); the
  next launch's reconcile is the only recovery, so the settings section
  says so in one line.
- **Changed-event payloads:** the registry stores no payload, and the
  payload carries the title, colour, icon, category and `removeAfterAlert`,
  so a pass provoked by `reconcileEvent(eventId)` re-schedules every
  planned entry of *that* event under its existing os id even when
  `fire_at` and backend match; other events keep the unchanged fast path
  and snooze rows are left alone.
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
| `alert_default_timed` | `none` | `mode:offsetMinutes` for a new timed event's first alert; `none` = no default |
| `alert_default_all_day` | `none` | `mode:daysBefore:minuteOfDay`; `none` = no default |

**Alerts are opt-in (owner decision, 2026-09-21).** Both defaults shipped as
`notify:10` / `notify:0:540` through Session 5 and every new event arrived
with a notification; they now ship as `none`, so an event carries an alert
only when the user adds one, and seeding is the opt-in made on the settings
page. An absent key reads as the shipped value, so installs that never
touched the setting flip with the build; a stored choice is kept. A corrupt
value also decodes to `none`. With no default, "Add alert" still opens on a
useful draft — `kDraftAlertOffsetMinutes` (10 min before) for a timed event,
on the day at `kDefaultAlertDayMinute` for an all-day one.
| `alert_sound` | `''` | `''` and `system:default` are both the phone's own default alarm — the app ships no sound of its own since **2026-09-22** — or a `content://` URI picked from the phone (**delivered 2026-09-21**) |
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
seeded from `alert_default_timed` / `alert_default_all_day` — which ship as
`none`, so as shipped it starts with no alert (§4). The sheet's
result record gains `alerts` and `removeAfterAlert`. Save stays gated only
by `_canSave`.

### 5.2 Alert sheet (`lib/widgets/alert_editor_sheet.dart`)

Draft-and-Save, `FractionallySizedBox(0.7)`, header close | `eventAlert`
title | Save. Sections: Type (`SegmentedButton<AlertMode>` with a hint that
changes per mode and warns when full-screen alarms are off), When (timed:
`ChoiceChip`s At start / 5 / 10 / 15 / 30 min / 1 h / 1 day / Custom… →
an `_IntervalStepper`-shaped minutes + unit row; all-day: On the day /
The day before / A week before + a time-of-day `_PickerTile` through
`showTimePicker`), Sound (alarm only — see below), and the remove switch
(one-time only). Footer `Remove alert` (`FilledButton.icon` in
`errorContainer`). Pads by `max(viewInsets, viewPadding)` and joins
`sheet_bottom_clearance_test.dart`.

**The Sound row (delivered 2026-09-21).** A `Card > ListTile` below the
timing section, shown **only while the alert is in the ring tier** — the
reminder tier plays through a notification channel whose sound Android froze
at creation, so a control there would do nothing. It opens
`AlertSoundSheet` (`lib/widgets/alert_sound_sheet.dart`), the **one** chooser
the Calendar-settings row opens too, in two variants: the editor's offers
*Use the app setting* and the settings one does not, because the settings row
*is* the app setting.

Three stored values, and one pure type that knows them —
`AlertSound` (`lib/models/alert_sound.dart`), table-tested:

| stored | on an alert | in `alert_sound` |
| --- | --- | --- |
| `null` | follow the app setting | *(impossible — the setting is never null)* |
| `system:default` (or `''`) | the phone's **current** default alarm sound, whatever the setting says | same — and the shipped value |
| `content://…` | a sound picked from the phone | same |

`null` and `system:default` are two different answers: the column is
nullable, so "defer" and "the phone's default" are distinguishable without a
further literal. `system:default` is stored as the literal rather than as the
default URI so the value keeps following the Clock app instead of freezing
the sound it named on the day it was chosen. **The app ships no sound of its
own (2026-09-22).** Until then `''` meant a 176 KB WAV bundled under
`assets/`, which was the shipped default; the phone already has alarm sounds
and that asset only added to the install size, so it was dropped, `''` now
reads as the phone's default (a legacy spelling the codec normalises to the
literal on write), and the *ANTA sound* row left the chooser. The `alarm`
plugin's iOS half has its own `default.m4a` for a null path, so Session 9
needs no asset either.

**Why a picked sound is no longer copied (OS-1, 2026-09-22).** Upstream
`alarm` puts `assetAudioPath` into `MediaPlayer.setDataSource(String)`, which
takes a Flutter asset or an absolute path and nothing else, so until OS-1
`MainActivity.resolveAlarmSound` copied a `content://` stream into
`filesDir/alert_sounds/<sha-1>` and armed the path. The fork's
`AudioService.playAudio` (Patch 2 of `packages/alarm/`) hands a `content://`,
`android.resource://` or `file://` value to
`MediaPlayer.setDataSource(Context, Uri)` before the asset and path branches,
so `alarmAssetPathFor(AlertSoundUri)` is the raw URI, the copy, its channel
method and its directory are gone (the directory is deleted once on the next
launch), and a URI the device cannot open falls back to the phone's default
alarm **inside the plugin, at ring time** — the same never-silence rule the
copy used to enforce at arm time. `AlertSoundSystemDefault` still arms with
**null**, which is how the package says "the device's default alarm sound".

**The cross-device degrade rule.** The value syncs and rides backups, so a
URI regularly lands on a phone whose provider never heard of that media id.
Every such value — an unresolvable URI, a copy that failed, a literal a newer
build wrote — decodes and arms as the **phone's default** alarm. Never
silence, never an exception, and never a refusal to arm: `alarmAssetPathFor`
is a pure function over exactly that, tested in
`android_alert_gateway_test.dart`. The UI says the same thing: a stored URI
this device cannot resolve reads "Not on this phone — plays the phone's
default alarm", never a raw URI.

Three Kotlin methods on the existing `com.alexzamfir.anta/alerts` channel,
all failure-tolerant: `pickAlarmSound` (the system `ACTION_RINGTONE_PICKER`
for `TYPE_ALARM`, its own Default row mapped to the literal, Silent hidden,
one pending `MethodChannel.Result` and a `picker_busy` error for a second
call, `no_picker` when the device has no picker activity at all),
`alarmSoundTitle` and `resolveAlarmSound`. `AlertGateway` gained
`supportsSoundPicker` / `pickSystemSound` / `soundTitle`, so *Choose from
phone* is simply **hidden** on the no-op binding rather than offered and
failing; the phone's default needs no picker and is offered everywhere.

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

The **Alarm sound** row sits between the two defaults and the Snooze slider
(delivered 2026-09-21): the same `AlertSoundSheet` as §5.2 minus *Use the app
setting*, its trailing text the resolved name, and — uniquely among the rows
here — writing it **also reconciles**
(`AlertScheduler.reconcileAllQuietly(eventChanged)`). Nothing about any event
changed, so nothing dispatches, and the arm signature below is the only thing
that can reach the alarms already standing on the old sound.

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

**Shipped (Session 6, 2026-09-23) — as above, with these decisions.** The
arithmetic lives in `lib/utils/quick_alarm.dart`, pure and tested: the
opening time is the next quarter hour strictly after now (23:50 opens on
00:00 tomorrow), *In 20 min* / *In 1 hour* round **up** to the whole minute
so the alarm is never less than the offset away, *Tonight* is disabled once
21:00 has passed rather than quietly meaning tomorrow night, and a time
already gone on the opened day rolls to today or tomorrow
(`quickAlarmDayFor`, the clock-app rule) with the sheet's caption naming
the day it will land on. A blank name saves as "Alarm"; a reminder never
carries `removeAfterAlert`. The sheet reports a `QuickAlarmDraft` and the
page mints the event and the alert (`buildQuickAlarmEvent`,
`buildQuickAlarmAlert`), so the bloc test is on the builders. The snackbar
names the time, and the day when it is not today (`quickAlarmSetOn`).
The tile and shortcut of the OS roadmap reach the same sheet through a
`QuickAlarmRequest` the page serves on today.

## 6. Platform

### 6.1 Android (Phase 1)

Dependencies: `alarm` as the local fork `packages/alarm/` (base 5.13.2,
OS-1 2026-09-22; `alarm ^5.13.0` before that), `flutter_local_notifications ^22.3.1`,
`timezone ^0.11.1`, `flutter_timezone ^5.1.0` (its `getLocalTimezone()`
returns a `TimezoneInfo`; use `.identifier`). The exact build steps that
worked are §10.2: desugaring in `build.gradle.kts`, the notification
plugin's **three** receivers (the action receiver included), the
permission list, `showWhenLocked` + `turnScreenOn` on `MainActivity`,
`tools:node="remove"` on the `READ_EXTERNAL_STORAGE` that `alarm`'s own
manifest merges in, the regenerated desktop registrants committed, and the
A15 prerequisite for the Windows build. Resources: a monochrome `ic_alert`
small icon under `drawable*/`; no sound asset — the alarm tier rings the
phone's own sounds (the bundled WAV was dropped 2026-09-22, §5.2). Channels:
`alerts_reminder`
(high) and, for the fallback path only, `alerts_alarm_v2` (max, `USAGE_ALARM`,
created with `content://settings/system/alarm_alert` as its sound — the
first id, `alerts_alarm`, had no sound and would have rung the phone's
*notification* default; it is deleted at initialize since OS-1);
`alarm` creates its own `alarm_plugin_channel` at importance 4 and does not
let Dart configure it. Names localized at creation, ids fixed forever
(channel settings are immutable after creation).

**`ic_alert` must be listed in `res/raw/keep.xml` (found on the owner's
phone, 2026-09-21).** The icon is named only from Dart (`kAlertSmallIcon`), a
reference the release resource shrinker cannot see, so a release APK shipped
without it — `aapt2 dump resources` on the 14:15 build had no `ic_alert`
entry at all. `FlutterLocalNotificationsPlugin.initialize` then throws
`invalid_icon`, which is the first platform call in
`AndroidAlertGateway._initialize`: no channel is created, `Alarm.init()` never
runs, nothing is scheduled, and **both tiers are silent** with no error on
screen. Debug builds do not shrink, so every emulator pass was green. Any
future resource named from Dart (a second icon, a `res/raw` sound) needs a
`tools:keep` entry too; `test/android/release_resources_test.dart` guards this
one. No ProGuard rules are needed — from v19 the plugin's Gson rules ship
with Gson itself.

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
notification with a ≤30 s sound. **Superseded as direction by
`event-alerts-os-integration-roadmap.md` §7 (2026-09-22):** AlarmKit lives
in Swift behind `DarwinAlertGateway`, not in the `alarm` fork, and every API
name is to be verified against the current reference before Session 9's
prompt is written. Background-audio ringing on older iOS is
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

## 8. Prerequisites, sessions and prompts

Execution model: Fable plans and reviews; Opus implements each session from
the prompt below; Sonnet takes the mechanical parts (ARB ×3, DDL, gen-l10n).
Every session ends with `dart analyze lib`, `flutter test`, `flutter run -d
windows` still launching, the device pass named in its row, a Fable review
of the diff, and **a commit** — the next session starts on a clean tree,
never on top of an uncommitted predecessor. The owner's real phone is
needed for the spike's OEM questions and for every "ring" acceptance; the
emulator cannot answer battery or vendor behaviour. Phase names stay as
the grouping the rest of this document refers to: Phase 1 = Sessions 1–4,
Phase 2 = Sessions 5–6, Phase 3 = Session 7, Phase 4 = Sessions 8–9.

### 8.1 Prerequisites

| Id | What | Who | Gates | Status |
| --- | --- | --- | --- | --- |
| P1 | Confirm the four decisions that shape the v40 DDL: A2 (up to five per event, one row each), A3 (`remove_after_alert` on the event, not the alert), A4 (`days_before` + `day_minute` per alert), A14 (no timezone column). Changing any of them after Session 1 means a v41. | owner | Session 1 | **confirmed 2026-09-15**, all four as proposed |
| P2 | Confirm the surface decisions: A1 (vocabulary), A8 (one snooze length), A12 (where a tap opens) before Session 3; A11 (quick alarms in `other` with the alarm icon) before Session 6. | owner | Sessions 3, 6 | **confirmed 2026-09-15**, all four as proposed |
| P3 | Phone pass of the spike (§10.4 recipe: release-signed build of `spike/event-alerts-ring`, `adb install -r`, never uninstall): PIN keyguard, overnight Doze, reboot before the fire time, Force stop, DND access, audibility, the `restricted` bucket; vendor and OS version recorded in §10. Its output is the A5 verdict — `alarm` for the Alarm tier, or the notification-plugin fallback if `setExactAndAllowWhileIdle` defers overnight. | owner | Session 3 | **waived 2026-09-15** by the owner: A5 stands on the emulator verdict alone (`alarm` for the Alarm tier), the §11 Doze and OEM risks stay open, and the gateway's one-file fallback switch is the mitigation. The first real-phone evidence is the §9 checklist after Session 4; a PIN-keyguard failure there reopens A5 |
| P4 | A15 — the Windows build with the notification plugin. | owner | Session 3 | **done 2026-09-14**; the CLAUDE.md / `verify` note lands with the dependencies in Session 3 |
| P5 | Planner scope: this split builds the **full horizon planner** in Session 2 rather than the one-t
ime-only cut the 2026-09-14 Phase 1 prompt asked for. The walk is `occursOnUtcDay` either way, so one-time-only saves no code and would leave Session 5 rewriting tested code; what is deferred to Session 5 is proving recurrence on a device, not planning it. | owner | Session 2 | **confirmed 2026-09-15**: full horizon |

Housekeeping, not gates: the spike's debug APK is still on the emulator
(the first `qa run` from `main` reinstalls the stock build); if the
emulator reports "Lost connection to device" after a launch, cold-boot it;
add dependencies from Git Bash (PowerShell 5.1 eats the caret, §10.2).

### 8.2 Session ledger

| # | Session | Phase | Needs | Device pass | Ends with |
| --- | --- | --- | --- | --- | --- |
| 1 | Persistence and domain — **DONE 2026-09-15** | 1a | P1 | none | v40 live, `EventAlertService` in the calendar `Future.wait`, backup + `.ics` round-trips green |
| 2 | Planner, scheduler, gateway seam — **DONE 2026-09-15** | 1b | S1, P5 | none (Windows launch only) | every reconcile trigger wired against `NoOpAlertGateway`; alerts exist only through tests |
| 3 | Android gateway and the ring — **DONE 2026-09-16** (emulator; owner's phone pass owed) | 1c | S2, P2, P3 | emulator + phone | Test alarm in 10 s rings on a locked screen, alarm page Stop / Snooze work, force-stop copy in place |
| 4 | Editor, detail, rows | 1d | S3 | emulator, then §9 rows 1–7 on the phone | the Phase 1 acceptance: one-time alarm end to end, remove-after + Undo |
| 5 | Recurrence proven, missed path, hub | 2a | S4 | emulator, §9 row 8 | Mon/Wed/Fri recipe passes, Alerts hub live |
| 6 | Quick alarm and templates — **quick alarm DONE 2026-09-23**; template alerts (v41) open | 2b | S5, P2 (A11) | emulator | FAB long-press → Alarm… → rings; v41 template alerts |
| 7 | Power and harness | 3 | S6 | emulator | sound picker, presence prompt, `qa alerts` / `qa fire` |
| 8 | iOS runner builds | 4a | S7, the Mac | simulator | `flutter run` on a simulator reaches the browser |
| 9 | `DarwinAlertGateway` | 4b | S8, an iPhone | iPhone | §6.2 acceptance |

### Phase 0 — Investigation (started 2026-09-14)

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

Every prompt below is preceded by the same preamble, which is not
repeated: *Read `docs/event-alerts-roadmap.md` §0–§7 and §10 first, then
`COPILOT_CONTEXT.md`, the `anta-context`, `calendar-events`,
`drift-migrations` and `l10n` skills, and `docs/calendar-events-feature.md`
§3, §6 and §10. Line numbers in the roadmap are as of `4610292` — re-grep
before editing. Hard rules: never GetIt for DB-backed services; every
plugin call behind the gateway; permission requests only from a user
action; no code comments beyond `///` doc comments; no new markdown docs.
Before finishing run what the change requires (`dart run build_runner
build --delete-conflicting-outputs`, `flutter gen-l10n` and check
`untranslated.txt`, `dart analyze lib`, `flutter test`, `flutter run -d
windows` reaches the browser). Report every deviation from the roadmap in
a "Deviations" list and do not edit the roadmap yourself.*

### Session 1 — Persistence and domain (Phase 1a)

Needs P1. No device. Nothing in this session imports a plugin.

> Implement Session 1 of `docs/event-alerts-roadmap.md` on top of the
> current `main`. Scope: the v40 schema and migration exactly as §4.1
> (`DatabaseSchema.v40EventAlerts`, both table classes in the
> `@DriftDatabase` list, `_migrateV39ToV40` with the guarded column,
> indexes through `DatabaseIndexes`); `EventAlert` + `AlertMode` (§2.1)
> with `copyWith`, the JSON codec, and `EventAlert.describe(l10n, event)`
> as the one formatter — its ARB keys ×3 now; `CalendarEvent.
> removeAfterAlert` (§2.2) through the model, the DAO and the JSON key,
> default false, read by nothing else; `EventAlertDao` and
> `AlertRegistrationDao` (§3.1) with the CRDT stamping of
> `calendar_event_dao.dart`; `EventAlertService` + the `EventAlerts`
> facade in the `EventSkipService` shape, registered with
> `DatabaseLifecycle` and added to the calendar services' `Future.wait`;
> `CalendarEventService.deleteById` cascading alerts and registrations;
> backup key `eventAlerts` with the strand rule keyed to `calendarEvents`
> and `removeAfterAlert` riding `calendarEvents` (§4.2, no version bump);
> `.ics` `VALARM` (§4.3); the five settings keys with `getAlertSettings()`
> and pure decoders (§4.4), added to `_calendarPageKeys` — no settings UI
> yet. Tests: `test/models/event_alert_test.dart` (codec, `describe`
> table, both offset sets surviving an all-day flip), `test/services/
> event_alert_service_test.dart` (in-memory DB, CRDT stamping,
> `replaceForEvent` tombstones, cascade on `deleteById`, backup round-trip
> including the strand rule), `test/database/` parity for both tables, the
> two partial indexes in the query-plan suite, one statement for
> `getAllActive`, and a `VALARM` case in the `.ics` suite. Update the
> `calendar-events` skill's schema lineage to v40 and its seven-services
> rule to eight. Acceptance: `flutter test` green, `flutter run -d windows`
> launches, and a fresh v39 database migrates with the three DDL
> statements applied once.

Shipped 2026-09-15 as written, 4,951 → 5,044 tests. Deviations that later
sessions must know: `alert_registrations.created_at` / `updated_at` are
Drift `DateTime` columns (unix seconds) while `day` / `fire_at` stay raw
epoch-ms ints, asserted in `schema_parity_test`; the all-day `VALARM`
absolute trigger is written in UTC (RFC 5545 allows no other form) while
`DTSTART` stays floating; `getAlertSettings()` returns the `AlertSettings`
record typedef (`lib/models/event_alert.dart`) with `TimedAlertDefault?` /
`AllDayAlertDefault?` sub-records, and `getCalendarPageSettings()` carries
it as `alerts:`; `EventAlertDao.replaceForEvent` takes companions and
re-homes an alert whose `eventId` disagrees with the argument; the `.ics`
test lives in its own `ics_serializer_alarm_test.dart`; the
`calendar-events` skill's lineage gained the missing v39 entry alongside
v40. Review finding for Session 2: `CalendarEventService.deleteAll` (the
event-import wipe) hard-deletes every registration while the OS still
holds the entries, so reconcile must cancel platform entries whose payload
names the active database but which the plan does not contain — the
registry alone cannot be trusted to know about them.

### Session 2 — Planner, scheduler and the gateway seam (Phase 1b)

Needs Session 1 committed and P5. No device: the only gateway is
`NoOpAlertGateway`, and alerts exist only through tests.

> Implement Session 2 of `docs/event-alerts-roadmap.md` on the committed
> Session 1 tree. Scope: `AlertHorizon` in `lib/constants/
> alert_constants.dart`; `AlertPlanner` (§2.4–§2.6) — pure, `now` a
> parameter, the **full horizon** over every `RecurrenceRule` through
> `occursOnUtcDay` (skips, `endDate`, retroactive and the holiday-reading
> rules included), both offset sets chosen by `event.time == null`, past
> `fireAt` never registered; `AlertPayload` (§3.1); the `os_id` hash and
> linear probe (§3.3); the `AlertGateway` interface, `NoOpAlertGateway`,
> `AlertAvailability`, and the GetIt registration in the `AuthService`
> shape — every platform gets the no-op this session; `AlertScheduler`
> (§3.1, §3.4) with `reconcileAll` / `reconcileEvent` diffing against the
> registry and never cancelling wholesale, OS-truth pruning of `pending`,
> the active-database payload filter (A9) applied in both directions —
> registry rows the OS does not know are dropped, and platform entries
> that name the active database but are absent from the plan are
> cancelled, because the event-import wipe empties the registry while the
> OS keeps its entries (Session 1 review finding) — `snooze` as its own
> registration (`kind = snooze`, A8) that an unrelated reconcile leaves
> alone, `stop`, `cancelSnooze`, the late-fire marking and the 7-day
> sweep, one serialized chain seeded `null`, and the await of the four
> services before planning; the reconcile triggers of §3.2 — launch
> post-frame `unawaited`, a new `resumed` branch in `_MyAppState.
> didChangeAppLifecycleState` debounced 2 s, `CalendarBloc` create /
> update / delete / skip / unskip calling `reconcileEvent` exactly once,
> the end of `BackupService.importFromJson` calling `reconcileAll`;
> `PendingNavigationQueue` drained from `main.dart` after the restore
> post-frame callback and deduped on `osId`; `CalendarPage(initialDay:,
> initialEventId:)` selecting the day and opening the detail sheet after
> `CalendarPageLoaded` through the shared bloc (`getIt<CalendarBloc>()` is
> a factory — do not use it). Tests: `test/utils/alert_planner_test.dart`
> as the §7 table (timed, all-day, one-time, weekly with skips and
> `endDate`, workdays with a holiday profile, the three horizon caps,
> past-today exclusion, spring-forward gap, disabled alert, five alerts on
> one event); `test/services/alert_scheduler_test.dart` with a
> `FakeAlertGateway` recording `schedule` / `cancel` (diff semantics,
> OS-truth pruning, multi-database filter, snooze survival, missed path,
> the serialized chain under `FakeAsync`); `test/bloc/
> calendar_alerts_test.dart` (each handler reconciles once); a widget test
> that `initialEventId` opens the detail sheet on the right day.
> Acceptance: `flutter test` green with no plugin channel stubbed anywhere,
> `flutter run -d windows` launches and logs one reconcile against the
> no-op gateway.

Shipped 2026-09-15, 5,044 → 5,153 tests. The review found three defects,
all fixed the same day: the late-fire rule (§3.4, corrected there — the
30 min in-flight band, "Missed" for alarm-tier rows only), stale payloads
on an event edit (§3.4 "Changed-event payloads"), and the default
reconciler reaching `AppDatabase.getInstance()` before checking for a
gateway (eighteen existing suites construct `CalendarBloc` under a
`path_provider` stub; the guard now comes first and `getInstance()` throws
`StateError` having touched nothing). Deviations later sessions must
know: `reconcileEvent(id)` is a **full re-plan** (the `total` cap is
global) that only uses the id for the log and the payload refresh;
`AlertGateway` has `pendingEntries()` (payloads, for A9) with
`pendingIds()` derived, `tracksPending` (false on the no-op, which is what
keeps OS truth from cancelling the horizon on desktop), `showMissed(
payload)` composed by the binding — so no ARB keys yet — and `backendName`
(`none` | `alarm` | `notification`); `payload.timeLabel` is the **fire
instant's** wall clock via the new `EventTimeFormatter.formatMinuteOfDay`;
`CalendarBloc` takes an optional `AlertReconciler` (default
`AlertScheduler.reconcileEventById`, which swallows failures) and calls
it `unawaited` after the emit-worthy write; `AlertScheduler` follows
`getInstance` / `forTesting` / `reset` with the gateway from GetIt and an
injectable clock, and awaits skips, holidays and alerts quietly but
aborts without `CalendarEventService` or `SettingsService`; the four
services are resolved one at a time; `AlertRegistrationDao` gained
`byOsId` / `forEvent`; `PendingNavigationQueue.instance` is a static
`ChangeNotifier` drained by `_MyAppState` after the restore post-frame
callback and on every resume, deduping on `osId` against the last drained
batch; `AppNavigator.toCalendarOccurrence` is a root push stamped as the
plain `calendar` destination; `CalendarPage(initialDay:, initialEventId:)`
is served once by a post-frame check or a `BlocListener`, whichever sees
`CalendarPageLoaded` first. Known gaps carried into the Session 3 prompt:
`stop` does not cancel a standing snooze, a warm reminder tap stacks a
second calendar route, and the ring handler must mark `fired` at once.

### Session 3 — Android gateway and the ring (Phase 1c)

Needs Session 2 committed, P2 (A1, A8, A12) and P3's A5 verdict. Device:
the emulator, then the owner's phone for the ring itself.

> Implement Session 3 of `docs/event-alerts-roadmap.md` on the committed
> Session 2 tree. Scope: the dependencies of §6.1 added from Git Bash and
> the §10.2 build steps verbatim (desugaring, the notification plugin's
> three receivers, the permission list, `showWhenLocked` + `turnScreenOn`,
> `tools:node="remove"` on `READ_EXTERNAL_STORAGE`, the regenerated
> desktop registrants committed, the `ic_alert` icon and the default sound
> asset); the two channels with localized names and fixed ids;
> `AndroidAlertGateway` on the A5 backend with the fallback path (§3.4)
> switchable in that one file, and the §10.5 gotchas applied:
> `warningNotificationOnKill: false`, `androidStaleAfter: 30 min` mapped
> to the "Missed" notification, `Alarm.ringing`'s initial empty set
> ignored, `Alarm.set()` caught, the cold-start payload deduped, handled
> full-screen notifications cancelled at once, the non-const `Int32List`
> hoisted, `cancel({required id})`; `permissions()`,
> `requestNotifications()`, `openFullScreenIntentSettings()`,
> `stopRinging`, the `ringing` stream and `launchIntent()`; the reminder
> tier's Snooze / Done actions in the background isolate, payload-only,
> never planning (§11); `AlarmPage` + `AlertRingController` (§5.5) —
> Stop, Snooze {n} min, Open event, Keep the event, the database chip
> (A9), `PopScope(canPop: false)`, pushed with `rootPushInstant` and never
> recorded as a `NavDestination`, the A3 removal through `deleteById`
> (the calendar-page Undo snackbar comes in Session 4); the Calendar
> settings Alerts section (§5.7) limited to the three permission rows, the
> Snooze and Silence-after sliders, the one-line force-stop note, and
> `Test alarm in 10 s` with the synthetic payload the page labels
> `alertsTestAlarm` — the two defaults and the sound row come later; ARB
> keys ×3; the A15 prerequisite recorded in `CLAUDE.md`'s commands section
> and the `verify` skill. Tests: `alarm_page_test.dart` (every button, the
> chip, the stale-inset note), a gateway unit test for the `os_id` /
> payload round trip, `flutter test` still plugin-free through the no-op
> gateway. Three items the Session 2 review hands you: the ring handler
> marks a registration `fired` through the scheduler's serialized chain
> the moment `Alarm.ringing` emits, before anything else, because the
> launch reconcile treats a row under 30 min late as in flight only until
> something settles it (§3.4); `AlertRingController.stop` cancels a
> standing `snooze` registration of the same alert and day, which
> `AlertScheduler.stop` deliberately does not; and
> `AppNavigator.toCalendarOccurrence` must reuse a calendar route that is
> already on the stack instead of pushing a second `CalendarPage` on a
> warm tap (the `_livePageRoutes` / `_collapseOnto` helpers exist for
> this). Device pass on the emulator: `qa run`, Developer Options on,
> Test alarm in 10 s, `adb shell input keyevent KEYCODE_SLEEP`, confirm the
> alarm page appears (`qa state`, screenshot), Stop, confirm the
> registration is `stopped`; Snooze with the slider at 5 min and confirm
> the second ring; `am kill` the app before a test alarm and confirm it
> still rings; confirm the leftover notification is gone after Stop.
> Owner's phone: the same four steps, plus a PIN keyguard.

Shipped 2026-09-16, 5,153 → 5,172 tests, emulator pass green (test alarm
rings from a slept screen in ~2 s, Stop leaves the registration `stopped`
and no notification behind, a 5-minute snooze re-rings, an `am kill` before
the fire time is survived). Deviations later sessions must know:
`AlertPayload` gained **`snoozeMinutes`** (key `snoozeMin`, clamped on
decode, defaulted for an older payload) because the reminder tier's Snooze
runs in a background isolate with no settings service, and a **test-alarm
sentinel** `AlertPayload.testEventId` with `payload.isTest` — a test ring
has no event row, no alert row and no occurrence, so the sentinel is what
the alarm page titles itself from and what keeps the Missed path from
resolving an event that was never there. `AlertScheduler` gained
`markFired` / `markFiredById` (the ring handler's first act, through the
serialized chain), `cancelSnoozeForAlert(alertId, dayUtc)` (the alarm
page's Stop calls it; `stop` still does not), `scheduleTestAlarm` — which
records its registration as **`kind = snooze`**, because the diff owns only
what the planner produced and a `scheduled` row it cannot re-derive would
be cancelled by the next reconcile — and a `_snooze` fallback that rebuilds
the synthetic event/alert pair for a test ring, without which Snooze was
the one button on the alarm page that silently did nothing. Two Session 2
semantics were **extended, not rewritten**, both found on the emulator: a
platform entry whose payload says `snooze` is never cancelled by reconcile
(the background isolate cannot write a registry row for the snooze it
posts, and the registry-row rule alone does not cover it), and
`PendingNavigationQueue`'s dedupe memory now expires after
`doubleDeliveryWindow` (5 s) — a snooze's os id is a hash of (database,
alert, day, kind), so snoozing the same alert twice on the same day re-arms
it under the *same* id and the unbounded memory dropped the second ring as
an echo, hours later, with the phone ringing and no page to stop it. The
binding is `lib/services/android_alert_gateway.dart` with
`kAlarmTierUsesNotifications` as the A5 switch; `cancel` asks **both**
backends, since a tier's backend can be switched under a standing entry.
`permissions().fullScreenIntent` and the battery status are answered by a
small `com.alexzamfir.anta/alerts` `MethodChannel` in `MainActivity.kt`:
the notification plugin's `requestFullScreenIntentPermission()` *navigates
to the settings page* when the answer is no, which a status row must not
do, and battery exemption has no Dart binding at all — that channel is also
what makes the §5.7 battery row a working link. The Alarm tier's
Silence-after is a gateway-held `Timer` (the `alarm` package has no
timeout of its own; the fallback path gets the platform's `timeoutAfter`).
Channel names and every notification string are localized from the app's
**stored** language, read once at gateway init — channel names are
immutable after creation anyway — and the background isolate falls back to
the device locale, because reading the setting there would mean a database.
`AlarmPage` takes a `@visibleForTesting` controller so the A9 chip is
reachable without `path_provider`, and `AlertRingController._resolveEvent`
requires the active database name to **equal** the payload's: an
unresolved name reads as "not ours", so a failed lookup never deletes the
event that happens to carry that id in the database which *is* open.
`AppNavigator.toCalendarOccurrence` now collapses onto a live calendar
route and publishes the request through
`AppNavigator.pendingCalendarOccurrence`, which `CalendarPage` serves and
clears; the cold path still takes the constructor arguments.

The Fable review (2026-09-16) found two defects and fixed them the same
day, 5,170 → 5,172 tests. **A real alarm was silenced two seconds into the
ring:** the ring handler marks the row `fired`, which takes it out of both
`pending()` and the in-flight band, while `alarm` keeps the entry in its
storage until Stop — so the `resumed` reconcile the alarm page's own
appearance provokes found a platform entry with a past fire instant that
nobody planned and cancelled it. The emulator pass could not see this
because the test alarm's payload says `snooze: true`, which the cancel loop
already skips. Fix: `AlertGateway.ringingIds` (default empty; the Android
binding reports what it has emitted and not yet stopped) seeds the
reconcile's cancel set next to the in-flight rows, with a scheduler test
that fails without it. **A tap on a "Missed" notice opened the ring page**
and marked the cancelled row `fired`: the notice carries the alarm's own
payload, so `isAlarm` routed it to `_emitRing`; `isMissedNotification`
now tells the two apart by the notification id (`missedNotificationId`) in
both the response callback and the cold-start launch details, and a Missed
tap is an `OpenEventIntent`. Also: the gateway's `AlarmDropped`
subscription was dead code — the event carries only an id and the alarm is
already unsaved when it arrives — so it was removed and §3.4 now names the
registry path as the only Missed source; the permission rows render
nothing rather than "Not supported" until the platform has answered, and
are re-read on app resume because the two "Open settings" links return
before the user has toggled anything; and `kAlertRingVolume` (0.8) is
documented as what it is — an override of the phone's alarm volume for the
duration of the ring — which is a product choice the owner may want to
revisit in Session 7. **Revisited and reversed, 2026-09-21** — see "Ring
volume" below. Owed: the owner's phone pass (§9 and the PIN
keyguard), and the §5.7 rows this session deliberately left out — the two
defaults and the sound row.

### Ring volume — follow the phone (2026-09-21)

`kAlertRingVolume` is **gone**. A ring is armed with `volume: null`, and
`AlarmService.kt` only calls its `VolumeService.setVolume` when a volume is
named (`if (alarmSettings.volumeSettings.volume != null)`), so a null one
never touches `AudioManager` at all: the ring plays at whatever the alarm
stream is set to and nothing is restored afterwards, because nothing was
changed. The 3 s fade is unaffected — `AudioService.startFadeIn` ramps the
plugin's own `MediaPlayer`, not the stream.

One exception, `kAlertRingFloorVolume` (0.3): a slider left at or near zero
would be an alarm that silently fails. `MainActivity.alarmStreamVolume`
reports `getStreamVolume(STREAM_ALARM) / getStreamMaxVolume(…)`, the pure
`alertRingVolumeFor(fraction)` buckets it into `AlertRingVolume.follow` /
`.floor` (null → follow: never block arming on a volume query), and only
`floor` names a volume.

**It is an arm-time decision and therefore goes stale by design** — the ring
may be days away, and it rings natively with no Dart running, so a ring-time
floor is impossible without forking the package. What closes the gap is the
**arm signature**, which is also what carries the sound:

`alert_registrations.backend` now holds `alertArmSignature(context, fire)`
rather than the bare backend name — no schema change, and the column was
already device-local, hard-deleted and never exported. `context` is the
platform's half, read **once per pass** through
`AlertGateway.refreshArmContext()` (`alarm` while following, `alarm@floor`
while floored; the binding caches what it read so the token cannot describe a
different ring from the one it armed); the fire's own half is its effective
sound, appended as `#<value>` for **every alarm-tier fire** (a reminder never
carries one). Until 2026-09-22 the app's own bundled sound was "the absence
of a choice" and left the bare backend name; dropping that asset made the
phone's default the everyday answer, and naming it (`#system:default`) is
precisely what re-armed every alarm the older builds had left standing on
the asset — once, on the first pass after the upgrade.

The diff's fast path compares that token alongside the instant, so a sound
moved in Calendar settings and a volume slider dragged across the floor both
re-arm exactly the affected registrations — **in place, under the ids they
already have** — on the very next pass, which for the volume is the resume
reconcile that already runs. Only the bucket is recorded, never the fraction,
or every nudge of the volume key would re-arm the whole horizon.

### Session 4 — Editor, detail and rows (Phase 1d)

Needs Session 3 committed. Device: the emulator, then §9 rows 1–7 on
the owner's phone. This closes Phase 1.

> Implement Session 4 of `docs/event-alerts-roadmap.md` on the committed
> Session 3 tree. Scope: the editor Alerts rows (§5.1) inside the Time
> zone, seeded from `alert_default_timed` / `alert_default_all_day`, the
> result record gaining `alerts` and `removeAfterAlert`, the remove switch
> only while the event is one-time and has an alarm; `AlertEditorSheet`
> (§5.2) without the Sound row (Session 7), padded by `max(viewInsets,
> viewPadding)` and added to `sheet_bottom_clearance_test.dart`;
> `CalendarBloc._onCreateEvent` / `_onUpdateEvent` persisting the result's
> alerts through `EventAlertService.replaceForEvent` before the
> `reconcileEvent` Session 2 wired; `POST_NOTIFICATIONS` requested the
> first time an alert is saved and never elsewhere, a denial leaving the
> alert saved; the detail-sheet rows (§5.3) with the next `fire_at`
> resolved once in `initState`; the row badges (§5.4) read synchronously
> from `EventAlerts`; the `EventSummaryProvider` subtitle segment
> "removed after it rings" (§2.2); the two default rows in the settings
> Alerts section and their reset; the A3 "Removed · Undo" snackbar on the
> calendar page after Stop / Done / tap (§3.5), Undo resurrecting the
> tombstone through `upsert`; ARB keys ×3. Tests: `alert_editor_sheet_
> test.dart`, the clearance suite, a bloc test that an edited alert list
> reaches `replaceForEvent` once, badge and subtitle tests. Device pass on
> the emulator: create a one-time event 2 minutes ahead with an alarm,
> lock the screen, confirm the alarm page, Stop, confirm the registration
> is `stopped` and the event still exists; repeat with the remove switch
> on and confirm the event is tombstoned and Undo restores it; create a
> reminder 2 minutes ahead, confirm the banner with Snooze / Done, and
> that a cold-start tap opens the detail sheet on the right day. Then
> update `COPILOT_CONTEXT.md` with the calendar bullet of §13 and replace
> `docs/calendar-events-feature.md` §11's reminders row with a pointer
> here plus a new §12.

### Session 5 — Recurrence proven, missed path, hub (Phase 2a)

Needs Session 4 committed and the owner's phone pass of §9 rows 1–7
reported. Device: the emulator, §9 row 8 on the phone.

> Implement Session 5 of `docs/event-alerts-roadmap.md` on the committed
> Session 4 tree. Scope: prove the Session 2 planner and scheduler on
> recurring events end to end — re-arm on Stop through `reconcileEvent`,
> the horizon re-planned on every resume so a holiday profile change
> reaches the OS, skip and unskip moving registrations, the late-fire
> "Missed" path on launch and from `AlarmDropped(cause: staleAtBoot)`
> (§3.4, A10) — and fix whatever the device disproves; the Alerts hub
> page and drawer row (§5.6) with `NavDestinationKind.alerts` appended,
> the two permission banners with Turn on actions, rows grouped by day
> through `AgendaListView.dayHeaderLabel`, the `Switch` bound to `enabled`
> through a new `ToggleEventAlert` that reconciles the event, snoozed rows
> showing both times, long-press Cancel on a `removeAfterAlert` event
> (A3); ARB keys ×3. Tests: `alerts_page_test.dart`, `ToggleEventAlert` in
> the bloc suite, and any planner or scheduler rows the device pass
> proves missing. Device pass: a Mon/Wed/Fri event with an alarm, confirm
> two registrations in `dumpsys alarm | grep -i anta`, fire the first
> (set it 2 minutes ahead), Stop, confirm the third occurrence is now
> registered; Skip this day on Wednesday and confirm its registration is
> gone; snooze once and confirm an unrelated event edit leaves the snooze
> in place; set the phone clock 40 minutes past a pending alarm with the
> app closed, open it, confirm a quiet "Missed" notification and no ring.

### Session 6 — Quick alarm and templates (Phase 2b)

Needs Session 5 committed and P2's A11. Device: the emulator. This
closes Phase 2.

> Implement Session 6 of `docs/event-alerts-roadmap.md` on the committed
> Session 5 tree. Scope: the `quickAlarmRow` in `EventTemplatePickerSheet`
> above `templateBlankEvent`, and the FAB long-press branch in
> `calendar_page.dart` changed so the sheet opens even with no templates
> (§5.8); `QuickAlarmSheet` (big time defaulting to the next quarter hour,
> the three chips, the name field defaulting to "Alarm", Type segmented
> with Alarm default, the remove switch on) saving a `CreateCalendarEvent`
> on the selected day with `categoryId: 'other'`, `iconKey: 'alarm'`,
> `removeAfterAlert: true` and one alert at `offsetMinutes: 0`, then the
> `quickAlarmSet` snackbar with Undo in the template-add pattern; alerts
> inside event templates — `calendar_event_templates` gains an `alerts`
> JSON column in a v41 migration (additive, guarded, backup rides
> `eventTemplates` with absent = none), the template editor gains the same
> Alerts rows as the event editor, and creating from a template seeds its
> alerts; ARB keys ×3. Tests: `quick_alarm_sheet_test.dart` and the
> clearance suite, v41 parity, a template round-trip with alerts through
> backup, a bloc test that a quick alarm creates exactly one event and one
> alert. Device pass: FAB long-press with no templates → Alarm… → In 20
> min → confirm the event on today with the alarm icon and one
> registration; set one 2 minutes ahead, lock, Stop, confirm the event is
> gone from the day list and Undo restores it; create a template with an
> alert and confirm an event made from it carries the alert.

#### Session report — 2026-09-23, Claude Fable 5.1 (the quick-alarm half; run with OS-5's tile and shortcut)

Shipped (§5.8, the half the owner asked for — the OS roadmap's tile needed it):
- `EventTemplatePickerSheet`: the `Alarm…` row (`EventTemplateQuickAlarm`, `SemanticsIds.quickAlarmRow`, `alarm_add_rounded` on a primary-container avatar) above *Blank event*; `CalendarPage._quickAddFromTemplateBody` always opens the picker — the `CalendarTemplates.isEmpty` fall-through to the editor is gone, and so is the page's import of `calendar_templates.dart`.
- `QuickAlarmSheet` (`lib/widgets/quick_alarm_sheet.dart`) — **as specified**, `showModalBottomSheet` at 0.7 with the alert editor's header (close | title | Save, `SemanticsIds.quickAlarmSave`), a `SingleChildScrollView` padded by the clearance rule: the big time as a `TextButton` (`displayLarge`, tabular figures, `quickAlarmPickTime` tooltip, `showTimePicker`), a caption naming the day it will land on (`AgendaListView.shortDayLabel`), the three `ChoiceChip`s, the name field (`TextField`, `eventTitle` label, seeded with `quickAlarmName` = "Alarm" in `didChangeDependencies`), the Type `SegmentedButton` with Alarm first and selected, the ring/notify hint, and the *Remove after it rings* card shown for the alarm tier only and cleared when the tier changes (the editor's rule). **Decisions the prompt left open:** the opening time is the next quarter hour *strictly after* now and rolls into tomorrow after 23:45; *In 20 min* / *In 1 hour* round **up** to the whole minute so the alarm is never less than the offset away; *Tonight 21:00* is disabled (`onSelected: null`) once 21:00 has passed rather than quietly meaning tomorrow night; a time already gone on the opened day rolls to today or tomorrow (`quickAlarmDayFor`, resolved at Save and in the caption); a blank name saves as "Alarm"; the chip label carries the time through `EventTimeFormatter.formatMinute`, so a 12-hour locale reads "Tonight 9:00 PM". The sheet takes a `now` seam for its tests.
- `lib/utils/quick_alarm.dart`: `QuickAlarmDraft` (day, minute, name, mode, removeAfterAlert), `quickAlarmDefaultFor`, `quickAlarmAfter`, `quickAlarmTonightFor`, `quickAlarmDayFor`, `buildQuickAlarmEvent` (one-time, `kFallbackCategoryId`, `kQuickAlarmIconKey` = `alarm`, `EventTime(startMinute)`, `removeAfterAlert` only for the alarm tier) and `buildQuickAlarmAlert` (at start, the draft's tier, the default sound). Every moment is the `DateTime(y, m, d, 0, minute)` constructor form.
- The page: `_quickAlarmBody` mints the two ids, dispatches `CreateCalendarEvent(event: …, alerts: [alert])` and shows `quickAlarmSet(title, time)` — `quickAlarmSetOn(title, time, day)` when the day is not today — with Undo → `DeleteCalendarEvent`, the template-add pattern; `_quickAlarm` is the guarded entry for a request that owns no sheet slot (the tile's, below).
- ARB ×3 (`quickAlarmRow`, `quickAlarmTitle`, `quickAlarmName`, `quickAlarmPickTime`, `quickAlarmIn20Min`, `quickAlarmIn1Hour`, `quickAlarmTonight{time}`, `quickAlarmSet{title,time}`, `quickAlarmSetOn{title,time,day}`); `untranslated.txt` reads `{}`. Semantics ids `quickAlarmRow`, `quickAlarmTime`, `quickAlarmName`, `quickAlarmSave`, `quickAlarmRemoveAfter`.

Not shipped: **the template-alerts half** — the v41 `alerts` JSON column on `calendar_event_templates`, the template editor's Alerts rows, seeding an event's alerts from its template, the backup round-trip and the v41 parity test. Not asked for in this run and untouched, so this session stays open on that half; the ledger row says so.

Tests: `flutter test` 5615 → 5648 (+33). `test/utils/quick_alarm_test.dart` (10): "is the next quarter hour strictly after now", "rolls into tomorrow after 23:45", "\"in N\" rounds up to the whole minute, and crosses midnight", "tonight is 21:00 today, and nothing once that has passed", "is the opened day while its time is still ahead", "rolls a time already gone to today or tomorrow", "is a one-time event in the fallback category with the alarm icon", "carries one alert at start in the chosen tier", "a reminder never removes the event, whatever the switch said", "the switch off keeps the event". `test/widgets/quick_alarm_sheet_test.dart` (10): "opens on the next quarter hour, today, as an alarm", "the presets move the time — rounded up, and tonight at 21:00", "tonight is disabled once 21:00 has passed", "a preset that crosses midnight lands on tomorrow", "a day still ahead keeps the day it was opened for", "the reminder tier hides the switch and never removes", "the switch off is reported, and back on again", "a typed name is the title; an emptied one falls back", "the big time opens the picker, and cancel keeps the time", "close reports nothing". `test/widgets/event_template_picker_sheet_test.dart` (2): "offers the quick alarm above the blank event with no templates", "the blank row still opens the form". `test/bloc/calendar_alerts_test.dart`, group "a quick alarm (Session 6)" (2): "creates exactly one event with one alert, reconciled once" (one write of one at-start ring alert, one `eventChanged` reconcile, `['write', 'reconcile']`), "Undo is the delete, which reconciles the event once more". `test/widgets/sheet_bottom_clearance_test.dart` "the quick-alarm sheet clears the navigation bar". The tile's four page tests are listed under the OS roadmap's OS-5 report.

Gates (from a clean state):
- `flutter gen-l10n`: run after the three `.arb` edits; `untranslated.txt` reads `{}`.
- `dart analyze lib test`: 2 issues, the known `label_appearance_service.dart` warnings.
- `dart analyze packages/alarm/lib`: No issues found (the fork is untouched).
- `flutter test`: `+5648 ~7: All tests passed!`
- `cd android && ./gradlew :alarm:testDebugUnitTest --rerun`: 50 tests, 0 failures, 0 errors (`build/alarm/test-results/testDebugUnitTest/*.xml`).
- `git status --short`: the files named above plus the OS-5 tile set; the four generated `app_localizations*.dart` by `gen-l10n`; no key, keystore or Firebase file (`google-services.json` and `GoogleService-Info.plist` show as ignored).

Device: emulator-5554, AVD `Medium_Phone_API_36.1` (Android 16 / API 36.1, `google_apis_playstore` arm64), `qa -d emulator-5554 run --fresh` (no seed: zero templates is the case §5.8 is about), driven `--via agent`.
- FAB long-press with no templates → Alarm… — **pass**: `longpress id:calendar-add-event` → the picker with `Button "Alarm…" id=quick-alarm-row` above "Blank event" (`build/qa/shots/20260923_111214_s6_01_picker.png`); tap → the sheet: `"11:33 AM / Change time" id=quick-alarm-time`, `"Today"`, `"In 20 min" click,selected` after the tap, `"In 1 hour"`, `"Tonight 9:00 PM"`, `EditText "Title" text="Alarm"`, `"Alarm" click,selected` / `"Reminder"`, `Switch "Remove after it rings …" click,checked` (`…_111215_s6_02_sheet.png`; the tap was at 11:12:15, so 11:33 is 11:12:15 + 20 min rounded up).
- In 20 min → the event on today with the alarm icon and one registration — **pass**: Save → the day panel row `"Alarm / 11:33 · removed after it rings / At start"` under "Wednesday, September 23 · 1 entry" with the snackbar `"Alarm set for 11:33 AM"` + `UNDO` (`…_111247_s6_03_saved.png`); `dumpsys alarm` holds exactly one ANTA entry — `RTC_WAKEUP #18 … com.alexzamfir.anta / tag=*walarm*:…AlarmReceiver / origWhen=2026-09-23 11:33:00.000 … flags=0x3 / Alarm clock: triggerTime=2026-09-23 11:33:00.000 showIntent=PendingIntent{… com.alexzamfir.anta startActivity} / idle-options … temporaryAppAllowlistReasonCode=301`; `next_alarm_formatted` = `Wed 11:33 AM`; the Alerts hub lists `Today · 11:33 AM · Alarm` with its switch (`…_111623_s6_04_hub.png`).
- Set one a few minutes ahead, Stop, the event gone from the day list, Undo restores it — **pass**, twice: the 11:33 quick alarm above rang on time (`11:33:00.365 AudioService: Using device default alarm sound: content://settings/system/alarm_alert`, `11:33:00.436 AlarmService: Alarm rang notification for 1064973210 was processed successfully by Flutter`), the alarm page showed (`Button "Stop" id=alarm-stop`, `build/qa/shots/20260923_113321_s6_05_ring.png`), Stop → `[AlertScheduler] reconcile(ringHandled, efce7f9f-…) backend=alarm planned=0 scheduled=0 cancelled=0` (11:33:19), and the calendar — opened afterwards, since the hub had been in front — showed `"No events for this day"` with the `"Event removed"` snackbar and its `UNDO` (`…_113353_s6_06_after_stop.png`); that snackbar was let expire, so the Undo was proven on a second quick alarm set **through the time picker** (the big time → *Switch to text input mode* → Hour `11`, Minute `39` → OK; `"Alarm set for 11:39 AM"`, `next_alarm_formatted` = `Wed 11:39 AM`, `…_113624_s6_10_second_saved.png`): rang at `11:39:00.113` (`…_113903_s6_11_ring2.png`), Stop at 11:39:03 → `reconcile(ringHandled, 2f4668d5-…)` → `"No events for this day"` + `"Event removed"` (`…_113904_s6_12_removed.png`) → UNDO tapped at once → `"1 entry"` and the row `"11:39 · removed after it rings / At start"` back on Wednesday, September 23 (`…_113904_s6_13_undone.png`), `reconcile(eventChanged, 2f4668d5-…) planned=0 scheduled=0 cancelled=0` (the fire is behind now, so nothing re-arms — correct), `dumpsys alarm` holding no ANTA entry, `qa errors`: `no errors in logcat`. Not locked: the emulator's keyguard was left disabled (the OS-1 lock check is a phone item). The `[main] ring … queued while …` diagnostic added in this run (§9 of the OS roadmap) was hot-reloaded into the running build before the rings but did not print — the subscribed closure kept the old body — so it is unexercised on device; the next build carries it.
- Create a template with an alert and confirm an event made from it carries the alert — **not run**: template alerts are not shipped.

Open (for the reviewer first): the picker is now always a step for a user with no templates (one more tap before the blank form than before — §5.8 asked for it); `quickAlarmDayFor` rolling a past time forward rather than refusing Save; the `now` seam on a widget; the tile's request served on today rather than the selected day; the reminder tier offered in a sheet named "Quick alarm".

#### Fix report — 2026-09-23 (review by a fresh Fable subagent, Prompt B over this half and OS-5's tile half together; verdict was *ship*, four should-fix findings, all taken)

- **Finding 1 (should fix) — fixed.** `QuickAlarmSheet` keeps the opened day as its base day (`_day = widget.day` in `initState`, and again in `_pickTime`). It used to adopt the opening moment's day, and then a preset's, so a hand-picked time still ahead tonight resolved on tomorrow (23:50 → *In 1 hour* → pick 23:58 → tomorrow 23:58, a day late, with no way inside the sheet to mean tonight). `quickAlarmDayFor` still rolls a time already gone, so 23:50 still opens on 00:00 tomorrow. Test: `quick_alarm_sheet_test.dart` "a time picked by hand is on the opened day, not the preset's" (23:50, *In 1 hour* → Tomorrow; then 11:58 PM through the picker's text input → Today, `startMinute` 1438).
- **Finding 4 (should fix, low) — fixed.** `AlertIntent.collapsesAfterDrain` (true) is what `PendingNavigationQueue.enqueue` consults before treating a repeat inside the five-second window as an echo; `QuickAlarmIntent` answers false, so a tile tapped again right after its sheet was dismissed opens the sheet again rather than nothing. The hub intent keeps its echo rule. Test: the quick-alarm case in `pending_navigation_test.dart` now asserts the second tap is queued and pins both intents' answers.
- **Finding 2 (should fix) — fixed.** §3.4's OS-5 sentence names the shipped tile and shortcut.
- **Finding 3 (should fix) — fixed.** The OS-5 tile report's cold-half line was wrong, see there.

Verify (from a clean state, after the fixes):
- `flutter gen-l10n`: not re-run — no `.arb` changed by the fixes; `untranslated.txt` reads `{}`.
- `dart analyze lib test`: 2 issues, the known `label_appearance_service.dart` warnings.
- `dart analyze packages/alarm/lib`: No issues found (untouched).
- `flutter test`: `+5649 ~7: All tests passed!` (5648 + the picked-time case).
- `cd android && ./gradlew :alarm:testDebugUnitTest --rerun`: 50 tests, 0 failures, 0 errors (run once this session; the fork is untouched).
- Device: the 11:39 ring above ran on the build before these fixes; neither fix touches the ring, the removal or the Undo path. The sheet fix changes only which day a hand-picked time lands on, pinned by its widget test; the queue fix is pure Dart, pinned by its test.

### Session 7 — Power and harness (Phase 3)

Needs Session 6 committed. Device: the emulator.

**The sound half of this session shipped early, on 2026-09-21**, together
with the ring-volume reversal — both out of order, on the Session 5 tree,
because the owner asked for them while the phone pass was outstanding. What
landed is in §5.2 ("The Sound row"), §5.7 and "Ring volume" above, and it is
**not** what the prompt below sketches: the chooser has no in-app preview
player (the system picker previews every sound it offers while the user
scrolls it, so a second one would be two audio sessions fighting), and the
sound is a stored value with four meanings rather than an id. What is left of
this session is the presence prompt, `DevOptions.fireNextAlertInTenSeconds`
and the two QA verbs.

> Implement Session 7 of `docs/event-alerts-roadmap.md` on the committed
> Session 6 tree. Scope: ~~the Sound row in `AlertEditorSheet` and the
> `alert_sound` settings row~~ (**delivered 2026-09-21**);
> ~~volume fade-in~~ (**delivered 2026-09-21**) and a vibration pattern
> through the gateway, only what the A5 backend supports; the presence
> prompt on the alarm page for `tracksPresence` events (A13: an opt-in per
> event, an "I was there" tonal button that dispatches
> `SetOccurrencePresence` and nothing else — the page never marks);
> `DevOptions.fireNextAlertInTenSeconds`; the QA verbs `qa alerts` (list
> pending registrations from `dumpsys alarm` and the plugin's pending
> list; `--cancel` clears the QA database's entries by payload) and
> `qa fire` (schedules the next pending registration 10 s ahead through a
> `--define`-gated seam); ARB keys ×3. Tests: ~~the sound picker~~ and the
> presence button in the widget suites, the seam under a fake gateway.
> Update `docs/qa-harness.md`, the qa-emulator skill and `CLAUDE.md`'s
> commands for the two verbs. Device pass: `qa fire` rings within 15 s of
> the call, a tracked event's alarm page shows the prompt and marks
> presence once, an untracked event's page does not show it.

### Session 8 — iOS runner builds (Phase 4a, on the Mac)

Needs Session 7 committed and the Mac. Device: a simulator.

> Make the iOS runner of the ANTA app build and launch at all: Podfile,
> deployment target, usage strings (`NSAlarmKitUsageDescription` included),
> the Firebase pods the sync feature already declares, signing for a
> simulator. Change nothing in `lib/`; `NoOpAlertGateway` still serves
> iOS this session. Acceptance: `flutter run` on a simulator reaches the
> folder browser, `flutter test` unchanged. Record every Xcode / CocoaPods
> version and workaround in a "Deviations" list for `docs/`.

### Session 9 — `DarwinAlertGateway` (Phase 4b, on the Mac)

Needs Session 8 committed and a real iPhone.

> Implement `DarwinAlertGateway` per §6.2 of `docs/event-alerts-roadmap.md`
> on the committed Session 8 tree: reminders through the notification
> plugin with `interruptionLevel: timeSensitive` and `willPresent`
> handled; alarms through `flutter_alarmkit` on iOS 26+ behind a runtime
> version check, one `fixed` alarm per `PlannedFire`, the widget
> extension, and a time-sensitive notification with a ≤30 s sound below
> 26; the 64-pending window (A7 already fits); `AlertAvailability`
> extended to iOS. Tests: the gateway behind the existing fakes, no
> planner or scheduler changes. Device pass on the iPhone: lock screen,
> Focus, the silent switch, and a reboot before the fire time; §9 rows 2,
> 3 and 7.

## 9. Verification checklist (owner's phone, after each phase)

The **phone pass of the spike itself** (§10.4 recipe — release-signed
build of `spike/event-alerts-ring`, never uninstall: PIN keyguard,
overnight Doze, reboot before the fire time, Force stop, DND access,
audibility) was **waived on 2026-09-15** (P3). The rows below, run after
Session 4, are therefore the first time a real phone sees a ring; note
the vendor and OS version in §10 when they run.

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
owns the audio (fade, an **optional** volume — the app arms `null` and
follows the phone's alarm slider since 2026-09-21, naming a level only under
`kAlertRingFloorVolume` — loop, and a per-alert sound without a
channel per sound, which is exactly what the notification tier cannot have
because Android freezes a channel's sound at creation), degrades under Total
Silence to screen + vibration
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
for the phone: build the spike branch **release-signed**
(`tool\release\release.cmd install`, which refuses to build without the
keystore; a debug APK cannot install over the release app and uninstalling
would wipe data), run S2–S7 and S9–S10 by hand, then reinstall `main`.

### 10.5 API gotchas to carry into Phase 1

- `alarm`: `AlarmSet` and `AlarmException` are not exported from
  `package:alarm/alarm.dart` (import `utils/alarm_set.dart` and
  `utils/alarm_exception.dart`); `AlarmException.code` is an
  `AlarmErrorCode`; `Alarm.set` both returns `Future<bool>` and throws;
  `warningNotificationOnKill` defaults **true** (set false, or declare
  `NotificationOnKillService`); `androidStaleAfter` defaults to 15 min and
  drops stale alarms as `AlarmDropped(cause: staleAtBoot)` on
  `Alarm.events` — pass 30 min for A10; the drop event carries only the id
  and the alarm is already unsaved, so the registry reports the miss
  (§3.4); `Alarm.ringing` emits an **empty set on subscribe**
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
- **Deep Doze — closed by OS-1 (2026-09-22).** Upstream `alarm` armed with
  `setExactAndAllowWhileIdle`, which deep idle rate-limits; the fork arms
  the Alarm tier with `setAlarmClock`, which the platform exempts from Doze
  and the standby buckets by definition (the emulator's `dumpsys alarm`
  prints the alarm-clock block and lists the entry as the next wake from
  idle). The Reminder tier keeps `exactAllowWhileIdle` and may still be
  deferred in deep idle — a reminder is not an alarm. The overnight and
  `restricted`-bucket checks on the owner's phone are §9 of the OS roadmap.
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
