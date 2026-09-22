# Event Alerts — OS Integration Roadmap (2026-09-22)

**Status: OS-1 and OS-2 DONE 2026-09-22 (emulator API 36.1; the owner's
phone pass of §9 is owed). OS-3 to OS-6 PROPOSED.** Follow-up to
[event-alerts-roadmap.md](event-alerts-roadmap.md) (Sessions 1–5 shipped
there; 6–9 still open, and OS-5's tile depends on Session 6). This file does not reopen any A-decision of the
parent; it adds B-decisions on top of the shipped tree and orders the work by
the owner's stated priority (2026-09-22): **the phone must treat an ANTA alarm
as an alarm.** Everything else here is ranked below that.

Line numbers are as of `7a9c979` plus the 2026-09-22 sound/past-alert work
(uncommitted at the time of writing) and will drift — re-grep before editing.

## 0. What "the OS treats it as an alarm" means

Android has one API that carries alarm semantics all the way through the
platform: `AlarmManager.setAlarmClock(AlarmClockInfo, PendingIntent)`. An
entry armed with it is

- **exempt from Doze and from the standby buckets** by the platform's own
  definition, which is what every §11 risk of the parent roadmap is about
  (overnight deferral, the `restricted` bucket, OEM battery killers that
  only respect real alarms);
- **shown as the device's next alarm**: the alarm icon in the status bar, the
  "⏰ Tue 07:00" line on the lock screen and in Quick Settings, and
  `AlarmManager.getNextAlarmClock()` for everything that reads it (Bedtime
  mode, assistants, some launchers and watches);
- **openable**: the `AlarmClockInfo.showIntent` is what the lock-screen line
  and Quick Settings launch, so the user lands on ANTA's alarms, not on a
  cold app.

Today the Alarm tier is armed by the `alarm` plugin with
`setExactAndAllowWhileIdle` (`AlarmScheduler.kt:166` in the plugin), which is
exact but carries none of the above: no icon, no lock-screen line, and a
delivery the standby buckets are allowed to defer. The Reminder tier is
correctly *not* an alarm and must stay that way — a reminder must never
become the phone's "next alarm".

## 1. Decisions (proposed 2026-09-22)

| # | Decision | Choice | Why |
| --- | --- | --- | --- |
| B1 | How the Alarm tier gets alarm-clock semantics | **Fork the `alarm` plugin into `packages/alarm/`** (the `re_editor` precedent: owned, upstream watched) and make its `AlarmScheduler.setExactAlarm` arm with `setAlarmClock` unconditionally, keeping its inexact fallback for a revoked exact-alarm permission. No Pigeon wire change, so no generated code to touch. Open the same patch as an upstream PR. | The two alternatives lose more than they save. *Flipping `kAlarmTierUsesNotifications`* gets alarm-clock mode from the notifications plugin today but gives up the foreground-service ring: per-alert sound, the fade, the volume floor, native snooze, and it plays through a channel whose sound was frozen without an alarm sound (§6). *A shadow alarm-clock entry next to the plugin's own* would give the icon and wake the device, but two AlarmManager entries per alarm and a timing coupling nobody can test are not a foundation. |
| B2 | What the show intent opens | The **Alerts hub** (`NavDestinationKind.alerts`), through the existing `PendingNavigationQueue` as an `OpenAlertsHubIntent`. | It is the one screen that lists every armed alarm and offers the switch and *Cancel snooze*. The lock-screen line is the phone saying "you have an alarm"; the answer is the list, not one event. |
| B3 | Fork baseline and policy | Bump to **`alarm` 5.13.2** first (two Android fixes, neither on ANTA's paths), verify, then copy that exact version into `packages/alarm/` with the base version recorded at the top of the fork's `CHANGELOG.md`. Same rule as `re_editor`: cherry-picks are one-off decisions recorded here. | Forking the version we already run keeps the diff to the patch itself. |
| B4 | The `content://` copy | Fixed **in the same fork**: `AudioService.playAudio` gains a branch that hands a `content://` / `android.resource://` / `file://` path to `MediaPlayer.setDataSource(context, Uri)`. `MainActivity.resolveAlarmSound` and the `filesDir/alert_sounds` copies go. | The only reason the copy exists is the plugin's `setDataSource(String)`. Once the plugin is ours the reason is gone, and this is the last non-native step in the sound path. |
| B5 | Native snooze on the ring notification | Pass `androidSnoozeDuration` (the snooze setting) and a Snooze button; the registry learns the move from `Alarm.events` (`AlarmMoved`, cause snooze) and rewrites the row as `kind = snooze` under the same os id. | With the phone in use and ANTA not running, the ring is a heads-up whose only button is Stop. Snooze there must not need Dart. |
| B6 | Upcoming-alarm notice | A low-importance notification at `fireAt − lead` (setting, default 2 h, 0 = off), actions **Skip** and **Open**. Skip is a foreground action (opens the app, applies, shows "Skipped · Undo"). | Google Clock's "Upcoming alarm · Dismiss". Skipping tomorrow's 06:00 must not mean editing the event. The background isolate never writes the database (parent §3.4), so Skip opens the app. |
| B7 | Alarm log | The hub gains a **Recent** section over `alert_registrations`' settled rows (the 7-day retention already kept), and `AlertRegistrationState` gains `missed`, written where the Missed notice is posted. | "Did it ring?" answered from the phone's own record. The data is already there; only the state name is missing. |
| B8 | Session chip (Android 16 live update) | Posted natively **when a ring is acknowledged** (Stop on the alarm page or the notification), not at the event's start: a promoted ongoing notification with a chronometer, *Open note* and *Done*; an ordinary ongoing notification below Android 16. | The app is up at acknowledgement, so no third scheduling path is needed. The chip is the training log's "session in progress", which is the one live-update shape ANTA has a use for. |
| B9 | Quick-settings tile and app shortcut | A `TileService` and a static shortcut that launch the quick-alarm sheet of the parent's Session 6. | The most one-handed entry there is. Depends on Session 6 having shipped the sheet. |
| B10 | iOS | `DarwinAlertGateway` (parent Session 9) targets **AlarmKit** on iOS 26+, with the parent's time-sensitive-notification plan as the fallback below 26. | AlarmKit is the only way a third-party app rings a real alarm on iOS. The `alarm` plugin has nothing for it, so the gateway seam is where it lives. |

## 2. The fork (B1, B3, B4)

`packages/alarm/` is a copy of the pub package, referenced from `pubspec.yaml`
as `alarm: {path: packages/alarm}` exactly like `re_editor`. It keeps the
plugin's own Pigeon-generated bindings untouched; both patches are inside
Kotlin files that generated code never references.

**Patch 1 — alarm-clock scheduling** (`android/src/main/kotlin/com/gdelataillade/alarm/services/AlarmScheduler.kt`, `setExactAlarm`):

- the exact branch becomes `alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerTimeMillis, showIntent), pendingIntent)`;
- `showIntent` is `PendingIntent.getActivity` over
  `packageManager.getLaunchIntentForPackage(packageName)` with the action
  `com.gdelataillade.alarm.action.SHOW` and the alarm id as an extra, flags
  `UPDATE_CURRENT | IMMUTABLE`, request code `id`;
- the permission check stays: `setAlarmClock` needs the exact-alarm
  permission on Android 12–13 exactly like `setExactAndAllowWhileIdle`
  (ANTA holds `USE_EXACT_ALARM`, so on 13+ nothing is ever asked), and the
  inexact `setAndAllowWhileIdle` fallback is kept verbatim;
- the sub-5-second `Handler.postDelayed` path and the boot receiver's
  re-arm both go through `schedule`, so a reboot re-arms alarm-clock
  entries without another change;
- **only the Alarm tier reaches this code.** Reminders keep
  `zonedSchedule(exactAllowWhileIdle)` through the notifications plugin.

**Patch 2 — content URIs** (`services/AudioService.kt`, `playAudio`): before
the asset/path branches, `if (filePath.startsWith("content://") ||
filePath.startsWith("android.resource://") || filePath.startsWith("file://"))
mediaPlayer.setDataSource(context, Uri.parse(filePath))`. On the app side
`alarmAssetPathFor` hands `AlertSoundUri.uri` straight through,
`_resolvePickedSound`, the `resolveAlarmSound` channel method and the
`alert_sounds` directory are deleted (see the last line of the app side
below), and `android_alert_gateway_test.dart`'s "copied into" case becomes
"armed verbatim".

**App side of Patch 1.** The show intent is built inside the plugin from
`packageManager.getLaunchIntentForPackage(packageName)` (explicit component,
so a custom action is fine; `MainActivity` is `singleTop`, so a warm app gets
it through `onNewIntent`), with the action
`com.gdelataillade.alarm.action.SHOW`, the alarm id as an extra and
`FLAG_ACTIVITY_NEW_TASK`; a null launch intent means a null `showIntent`,
which `AlarmClockInfo` allows. `MainActivity` records the action from both
`onCreate` and `onNewIntent` into one field, answers a new
`consumeShowAlarmsRequest` method on the alerts channel (true once, then
false) and, for the warm case, pushes `showAlarms` to Dart through the same
channel's `invokeMethod` from the native side. `AndroidAlertGateway.
launchIntent()` asks `consumeShowAlarmsRequest` after the notification
launch details and answers `OpenAlertsHubIntent` when true; the warm push
enqueues the same. `AlertIntent` today assumes a payload (`osId` reads
`payload.osId`, and `PendingNavigationQueue` dedupes on it), so the hub
intent is a **payload-less** subtype: `payload` moves down to
`OpenEventIntent` and `OpenAlarmIntent`, the base gains an abstract
`dedupeKey` (the os id there, a constant for the hub) and the queue dedupes
on that. `main.dart`'s drain handles it by pushing `AlertsPage` with the
`alerts` destination stamp through the root navigator, the way
`AppNavigator.toCalendarOccurrence` already pushes without a context.
`MainActivity.configureFlutterEngine` deletes `filesDir/alert_sounds` once
(idempotent; nothing reads it any more).

## 3. Native snooze (B5)

`_scheduleAlarm` passes `androidSnoozeDuration: Duration(minutes:
settings.snoozeMinutes)` and `notificationSettings.androidSnoozeButton:
l10n.alarmSnoozeMinutes(settings.snoozeMinutes)` — the alarm page's own
"Snooze 10 min" plural, so no new key. The plugin then defers a ring from its own notification
with no Dart running (`SnoozeCoordinator.snooze`): same id, new instant,
storage updated, and an `AlarmMoved(cause: snooze)` on `Alarm.events` —
live when Dart is up, drained by the next `Alarm.init()` when it was not.

What the registry has to learn, and where:

- `AndroidAlertGateway` subscribes to `Alarm.events`, keeps every
  `AlarmMoved` whose cause is snooze in a list keyed by `(id, recordedAt)`
  (the stream is at-least-once), and exposes `takeMoves()`; nothing is
  applied from the subscription itself. The plugin is initialised with
  `acknowledgeEventsAutomatically: false`, so its durable marker outlives a
  process death until the registry row is written; the scheduler
  acknowledges each move after its write, and the gateway acknowledges
  every other event (drops, platform-refusal moves) on arrival, because an
  event never acknowledged is redelivered on every launch until it expires.
- `AlertScheduler._reconcile` calls `_gateway.takeMoves()` **first**, inside
  the serialized chain, before `_settlePastFires`, and for each move rewrites
  the row: same os id, `fireAt = newInstant`, `kind = snooze`, state
  `pending`. A row the registry does not know (another database's alarm)
  is ignored. Applying inside the chain is the whole point: an apply that
  went through `_serialize` from inside `initialize()` — which the reconcile
  awaits through `pendingEntries()` — would wait on the turn that is waiting
  on it.
- The existing rules then do the rest: a `kind = snooze` row is never the
  plan's to cancel, the hub already renders it with *Cancel snooze* and the
  original instant, `ringingIds` still protects the ring, and the alarm
  page's own Stop still cancels a standing snooze of the same alert.
- The in-app Snooze keeps its own registration (A8). Two snoozes of one ring
  cannot coexist because the page closes on Snooze and the notification's
  button is gone once the ring ends.

## 4. Upcoming-alarm notice (B6)

Armed by `AndroidAlertGateway.schedule` next to the alarm itself, under a
derived id (`osId ^ kAlertNoticeIdSalt`, masked like the Missed id) and a
payload carrying the alarm's own plus `notice: true`; cancelled by
`cancel(osId)` in the same breath, and **filtered out of `pendingEntries()`**
so the OS-truth pass never sees an id it did not plan. No registry row: the
notice is the alarm's shadow, not a registration. Only when `fireAt − lead`
is still ahead of now; never for a snooze; never for the Reminder tier.

Copy: title `alertsUpcomingTitle` ("Alarm at {time}"), body the event's
title, channel `alerts_reminder` at low importance. Actions: **Skip**
(`showsUserInterface: true`, so it launches the app and enqueues a
`SkipNextFireIntent`; the app dispatches `SetOccurrenceSkipped(eventId,
day)` for a recurring event or the hub's `ToggleEventAlert` off for a
one-time one, reconciles, and shows "Skipped {title} · Undo" — Undo is
`ClearOccurrenceSkipped` or the toggle back on) and **Open** (the existing `OpenEventIntent`). A tap
on the body is Open.

Setting: `alert_notice_lead_minutes`, default 120, 0 = off, on the Calendar
settings page under the Snooze slider; changing it is a `reconcileAll`
through the arm signature, which gains `~<lead>` so standing alarms re-arm
their notice.

## 5. Alarm log and richer content (B7)

`AlertRegistrationState.missed` is written by `_settlePastFires` on the row
it posts a Missed notice for, and by `settleEndedRing` for a timed-out ring;
`fromName` keeps mapping unknown values to `cancelled`, so an older build
reading a newer registry still behaves. The hub's **Recent** section lists
non-pending rows of the last 7 days newest first — rang (`fired`), stopped,
snoozed (`kind = snooze` and settled), missed, and cancelled rows are left
out (they are the plan changing, not history). Each row: event title,
`EventAlert.describe`, the instant, one glyph.

Richer content, same session: the alarm notification and the reminder get
the event's colour as `iconColor`/`color`, the category or event icon as the
large icon (drawn once per schedule into a `ByteArrayAndroidBitmap`), and
the description's first line as a `BigTextStyleInformation` body. The
payload gains `excerpt` (≤ 120 chars, stripped of markdown), stamped at
schedule time like `timeLabel`, so nothing has to open a database to draw it.

## 6. Session chip (B8), tile and shortcut (B9)

**Chip.** A `sessionChip` pair on the alerts channel — `show(payloadJson,
startedAtMs)` / `clear()` — posted from `AlertAcknowledgement.apply` and from
the alarm page's Stop (never from a reminder's tap), and cleared by *Done*,
by the event's end time when it has one, or by a new ring. On Android 16 (API 36) it
uses `Notification.Builder.setRequestPromotedOngoing(true)` with
`Notification.ProgressStyle` (elapsed over the event's duration when known,
indeterminate otherwise) behind
`NotificationManager.canPostPromotedNotifications()`; below 16, and when the
user has not allowed promotion, a plain ongoing `setUsesChronometer`
notification on `alerts_reminder`. Verify both names against the API 36
reference before writing OS-5's code; they are quoted from memory here. Two actions: *Open
note* (the event's linked note, else the event) and *Done*.

**Tile and shortcut.** `QuickAlarmTileService` (`onClick` →
`startActivityAndCollapse(PendingIntent)` — the `Intent` overload is
deprecated from API 34 — on the launcher intent with action
`com.alexzamfir.anta.QUICK_ALARM`) and a static `shortcuts.xml` entry with
the same action. `MainActivity` reports it like the SHOW action; the app
opens the quick-alarm sheet. **Blocked until the parent's Session 6 ships
the sheet.**

**Latent gap fixed on the way (found 2026-09-22).** `alerts_alarm`, the
fallback tier's channel, was created without a sound, so a flipped A5 switch
would ring the phone's default *notification* sound. Channel sounds are
frozen at creation, so the fix is a new id (`alerts_alarm_v2`) created with
`UriAndroidNotificationSound('content://settings/system/alarm_alert')` and
`audioAttributesUsage: alarm`; the old id is deleted at initialize. Done in
OS-1 while the gateway is open, so the switch stays a real mitigation.

## 7. iOS (B10)

For the parent's Session 9, replacing its §6.2 sketch: `DarwinAlertGateway`
rings through **AlarmKit** on iOS 26+ — authorization through
`AlarmManager.requestAuthorization`, one scheduled alarm per planned fire
with a fixed-date schedule, an alert presentation carrying Stop and Snooze
buttons, the event's title and colour in the attributes, and the system
sound or a named bundled sound (AlarmKit offers no picker, so `AlertSound`
degrades every URI to the system sound there). The `alarm` plugin has no
AlarmKit support, so this is Swift behind the gateway, not the plugin.
Below iOS 26 the time-sensitive notification plan stands. **Verify every API
name against the current AlarmKit reference before writing Session 9's
prompt** — this paragraph is direction, not a spec.

## 8. Sessions and prompts

Order is the owner's priority. OS-1 is independent of the parent's open
Sessions 7–9; OS-5 needs the parent's Session 6.

| Session | Scope | Needs | Device |
| --- | --- | --- | --- |
| OS-1 | The fork: alarm-clock scheduling, content URIs, the show intent, the fallback channel fix | nothing | emulator, then the phone (§9) |
| OS-2 | Native snooze | OS-1 | emulator |
| OS-3 | Upcoming-alarm notice | OS-1 | emulator |
| OS-4 | Alarm log, richer content | nothing | emulator |
| OS-5 | Session chip, tile, shortcut | parent Session 6 for the tile | emulator (API 36 image for the chip) |
| OS-6 | iOS through AlarmKit | parent Session 8 | the Mac + a device |

### 8.0 How a session runs

Every session is the same five steps, and a session is not done until all
five have happened. The prompts below are written to be pasted verbatim; the
only thing to change between sessions is the session id.

1. **Create** — one session, Prompt A of the session. Works on the committed
   tree, never commits (the owner commits), and ends by appending a
   *Session report* (template below) under the session's heading in this
   file.
2. **Review** — a **fresh** session (a different model where possible; the
   parent's precedent is Opus creating, Fable reviewing), Prompt B. Read-only:
   it edits nothing, and it reports findings in the format below.
3. **Fix** — the creating session or a new one, Prompt C, applies every
   finding the reviewer marked *must fix*, re-runs the gates, and appends a
   *Fix report* under the Session report.
4. **Verify** — the gates, run by whoever did the last edit, all green, plus
   the session's device pass with its evidence pasted into the report.
   "Not run" is a legal, recorded state (the parent's S10 precedent); a
   silent skip is not.
5. **Record** — the status line at the top of this file, the parent's
   status paragraph where it names this session, and the docs in §10.

**The gates** (from `frontend/anta`; every one must be green):

```
flutter gen-l10n                      # only when an .arb changed; then untranslated.txt must read {}
dart analyze lib test                 # zero errors; the two pre-existing warnings in label_appearance_service.dart are known
dart analyze packages/alarm/lib       # from OS-1 on
flutter test                          # whole suite; benchmarks stay skipped
cd android && ./gradlew :alarm:testDebugUnitTest   # from OS-1 on; the fork's own Kotlin tests
git status --short                    # only intended files; no generated file hand-edited; no key.properties, no keystore, no google-services.json
```

**Invariants every prompt inherits** (from `CLAUDE.md` and the parent):
layers never bypassed; settings only through `SettingsService` +
`SettingsKeys`; every user-visible string in all three `.arb` files; generated
files never hand-edited; the registry stays device-local and hard-deleted;
`Alarm.set` keeps `allowSameSecondScheduling: true`,
`warningNotificationOnKill: false`, `androidStopAlarmOnTermination: false`
and `androidStaleAfter: kLateFireGrace`; the Reminder tier never touches the
`alarm` plugin; nothing in a background isolate opens a database; comment
style follows the file being edited, with no new inline commentary; no new
markdown files.

**Session report** (append under the session heading; the reviewer reads it
first):

```
#### Session report — <date>, <model>
Shipped: <one line per §-item, "as specified" or the deviation and why>
Not shipped: <items and why>
Tests: <suite counts before/after; the new test names>
Gates: <each command and its result>
Device: <emulator image / phone model + Android version>; <each §-listed check with pass/fail/not run and the evidence — dumpsys excerpt, screenshot path, log line>
Open: <anything the reviewer should look at first>
```

**Prompt B — review (paste as is, change the session id):**

> Review session OS-N of `docs/event-alerts-os-integration-roadmap.md` on
> the current working tree (`git diff` against the last commit, plus the
> untracked files). Load the `anta-context` and `calendar-events` skills,
> read §§0–2 and the OS-N section of that roadmap, its Session report, and
> `docs/event-alerts-roadmap.md` §3.4 and §10.5. **Edit nothing.** Verify,
> in this order, and quote file:line for every claim: (1) each item in the
> OS-N scope is implemented as the roadmap specifies, or the Session report
> records the deviation and its reason; (2) each invariant of §8.0 holds on
> the diff; (3) every test the OS-N prompt lists exists, and for at least one
> behavioural test you have confirmed by reading it that it would fail
> without the change; (4) the gates in the Session report were actually run
> (re-run `dart analyze lib test` and the session's named test files
> yourself); (5) the device evidence in the report matches the checklist for
> OS-N and is specific (a dumpsys line, a screenshot path), not a claim;
> (6) the OS-N *Review focus* list, point by point; (7) what could now ring
> late, twice, never, or with the wrong sound — trace one alarm from
> `AlertPlanner.plan` through `AlertScheduler._reconcile` to the plugin and
> back through `Alarm.ringing`, and one reboot; (8) the docs in §10 that
> this session touches were updated. Report findings ranked most severe
> first, each as: file:line — the defect in one sentence — the concrete
> failure scenario (inputs → wrong outcome) — *must fix* or *should fix* —
> the fix you would make. Then one verdict: **ship** (no must-fix) or **fix
> first**. Do not restate what is correct beyond one line per checked area.

**Prompt C — fix (paste as is, change the session id):**

> Apply the review of session OS-N of
> `docs/event-alerts-os-integration-roadmap.md`: every *must fix* finding,
> and each *should fix* unless you record under the Fix report why not.
> Load the `anta-context` skill and read §8.0 of that roadmap first. For each
> finding, make the smallest change that removes the failure scenario, add
> or adjust the test that would have caught it, and re-run the gates of §8.0
> plus the session's device checks that the finding touched. Then append a
> *Fix report* under the Session report: one line per finding (fixed /
> declined and why), the gate results, and any new evidence. Do not commit.

### OS-1 — The fork and alarm-clock semantics

**Preconditions.** Working tree clean; `flutter test` green; the emulator
image is API 34 or newer (the alarm icon and lock-screen line are what is
being proven); the owner's phone available afterwards for §9.

**Prompt A — create:**

> Implement session OS-1 of `docs/event-alerts-os-integration-roadmap.md`
> on the committed tree. Load the `anta-context`, `calendar-events`,
> `qa-emulator` and `l10n` skills; read that roadmap §§0–2 and §6's last
> paragraph, `docs/event-alerts-roadmap.md` §3.4 and §10.5, `CLAUDE.md`'s
> architecture section (the `re_editor` fork rule), and the four files you
> will edit most: `lib/services/android_alert_gateway.dart`,
> `lib/services/pending_navigation.dart`, `lib/main.dart` (the drain and
> the launch-intent wiring) and
> `android/app/src/main/kotlin/com/alexzamfir/anta/MainActivity.kt`.
> Do the work in this order, running the gates of §8.0 after steps 2, 4
> and 7:
> 1. Set `alarm: ^5.13.2` in `pubspec.yaml`, `flutter pub get`, run the
>    alert suites (`test/services/alert_*`, `test/services/android_alert_gateway_test.dart`,
>    `test/utils/alert_planner_test.dart`, `test/widgets/alarm_page_test.dart`,
>    `test/widgets/alerts_page_test.dart`, `test/widgets/alert_sound_sheet_test.dart`).
> 2. Copy `~/.pub-cache/hosted/pub.dev/alarm-5.13.2/` to `packages/alarm/`
>    (everything the package ships), replace the dependency with
>    `alarm: {path: packages/alarm}` in the `re_editor` shape, `flutter pub
>    get`, and add at the top of `packages/alarm/CHANGELOG.md` a block
>    "ANTA fork of alarm 5.13.2 (2026-..)" listing the two patches below.
>    Nothing else in the fork changes.
> 3. Patch 1, in `packages/alarm/android/src/main/kotlin/com/gdelataillade/alarm/services/AlarmScheduler.kt`,
>    function `setExactAlarm`: keep the `canScheduleExactAlarms` guard and
>    the inexact fallbacks verbatim; replace the `setExactAndAllowWhileIdle`
>    / `setExact` calls with one
>    `alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerTimeMillis, showIntent), pendingIntent)`,
>    where `showIntent` is built as §2 "App side of Patch 1" describes (a
>    private `showIntent(context, id)` returning `PendingIntent?`). Add a
>    constant `ACTION_SHOW = "com.gdelataillade.alarm.action.SHOW"` next to
>    `AlarmService.ACTION_RING`. Keep the `SecurityException` fallback.
> 4. Patch 2, in `services/AudioService.kt`, `playAudio`: before the asset
>    and path branches, a branch for `content://`, `android.resource://` and
>    `file://` that calls `mediaPlayer.setDataSource(context, Uri.parse(filePath))`.
> 5. App side of Patch 2: `alarmAssetPathFor` returns `sound.uri` for an
>    `AlertSoundUri` (the `resolvedPath` parameter goes); delete
>    `_resolvePickedSound`, the `resolveAlarmSound` channel method,
>    `copyAlarmSound`, `sha1`, `soundExecutor`, `mainHandler` and
>    `ALARM_SOUND_DIR` from `MainActivity`; add the one-time
>    `filesDir/alert_sounds` deletion in `configureFlutterEngine`. Update
>    the doc comments that described the copy (gateway, `AlertSound`,
>    `MainActivity` KDoc, `settings_keys.dart`).
> 6. App side of Patch 1: `consumeShowAlarmsRequest` and the warm
>    `showAlarms` push in `MainActivity`; `OpenAlertsHubIntent` and the
>    `dedupeKey` refactor in `pending_navigation.dart`; the gateway's
>    `launchIntent()` and a `showAlarms` stream on `AlertGateway` (empty on
>    the no-op binding); the `main.dart` drain case pushing `AlertsPage`
>    with the `alerts` stamp through the root navigator.
> 7. The fallback channel: create `alerts_alarm_v2` with
>    `UriAndroidNotificationSound('content://settings/system/alarm_alert')`
>    and `audioAttributesUsage: alarm`, delete `alerts_alarm` in
>    `_initialize`, and point `kAlertAlarmChannelId` at the new id; update
>    every place that lists channel ids for the permission status query.
> 8. `CLAUDE.md`: `packages/alarm/` next to `packages/re_editor/` in the
>    architecture section and `dart analyze packages/alarm/lib` in the
>    commands; the docs of §10 that name the copy or the backend.
> Tests: in `android_alert_gateway_test.dart` — a picked sound arms verbatim,
> the system default still arms null, the channel ids test covers the new
> id; in `pending_navigation_test.dart` — the hub intent dedupes against a
> second hub intent and never against an alarm intent; in
> `alert_scheduler_test.dart` nothing changes (assert the suite is
> untouched). Device pass (emulator, through `qa`): `qa run --fresh`, arm
> the Calendar-settings test alarm, then `adb shell dumpsys alarm` shows
> the entry with an alarm-clock block and the 0x2/0x8 flags (§9 wording),
> `qa shot alarm-icon` shows the status-bar alarm icon, `adb shell
> settings get system next_alarm_formatted` names it, lock the screen and
> confirm the time is shown, tap the lock-screen line and confirm the hub
> opens; the ring still stops, snoozes and re-arms; pick a `content://`
> sound in Calendar settings and confirm the test alarm plays it with no
> file under `files/alert_sounds` (`adb shell run-as com.alexzamfir.anta ls
> files`). Append the Session report. Do not commit.

**Review focus (OS-1):**
- The inexact fallback paths in `setExactAlarm` are byte-for-byte what 5.13.2
  shipped; only the exact branch changed.
- `showIntent` uses request code `id` and `FLAG_UPDATE_CURRENT |
  FLAG_IMMUTABLE`, and a null launch intent yields a null show intent, not a
  crash.
- The Reminder tier still goes through `zonedSchedule(exactAllowWhileIdle)`;
  grep the gateway for `alarmClock` and confirm it appears only on the
  fallback-tier path that already used it.
- Patch 2 keeps the asset and absolute-path branches intact, and the
  `content://` branch runs before the `!startsWith("/")` rewrite that would
  otherwise mangle the URI.
- `alarmAssetPathFor(AlertSoundUri)` is the raw URI; no caller still passes
  `resolvedPath`.
- `AlertIntent.dedupeKey`: the queue's existing dedupe behaviour for two
  cold-start deliveries of one alarm is unchanged (the test in
  `pending_navigation_test.dart` that covers it still exists and passes).
- `alerts_alarm` is deleted before `alerts_alarm_v2` is created, and no
  string still names the old id.
- The fork's `CHANGELOG.md` names both patches and the base version.

#### Session report — 2026-09-22, Claude Fable 5.1 (single-run prompt, §8.7)

Shipped:
- Step 1 as specified: `alarm: ^5.13.2`, `flutter pub get`, the nine alert suites green (147 tests) before the fork.
- Step 2 as specified: `~/.pub-cache/hosted/pub.dev/alarm-5.13.2/` copied whole into `packages/alarm/` (`example/`, `help/`, `pigeons/`, `test/` included), `alarm: {path: packages/alarm}` in the `re_editor` shape, the fork block at the top of `packages/alarm/CHANGELOG.md` naming the base version and both patches.
- Patch 1 as specified, with one addition: `setExactAlarm(context, alarmManager, triggerTimeMillis, pendingIntent, id)` keeps the `canScheduleExactAlarms` guard, the `setAndAllowWhileIdle` fallback and the `SecurityException` fallback byte-for-byte, and arms with `setAlarmClock(AlarmClockInfo(triggerTimeMillis, showIntent(context, id)), pendingIntent)`. **Deviation:** the exact branch keeps a `setExact` arm below API 21 — `setAlarmClock` is API 21 and the plugin declares `minSdk 19`; the app's `minSdk 24` never reaches it. `showIntent` is `PendingIntent.getActivity` over `getLaunchIntentForPackage` with `AlarmService.ACTION_SHOW` (added beside `ACTION_RING`), the id under the existing `AlarmService.EXTRA_ALARM_ID`, `FLAG_ACTIVITY_NEW_TASK`, request code `id`, `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`; a null launch intent yields a null show intent.
- Patch 2 as specified, with one addition: `AudioService.playAudio` takes a `content://` / `android.resource://` / `file://` value to `setDataSource(context, Uri)` before the asset and path branches. **Deviation (found while removing the copy):** with the copy gone, a URI this device cannot open — a sound restored from another phone — would reach `setDataSource` at ring time and the plugin's catch would leave the alarm **silent**, which breaks the §5.2 never-silence rule the copy enforced at arm time. The URI branch therefore falls back to the device default (`defaultAlarmUri()`, the same resolution the null path uses) when `setDataSource` throws. The classification is the companion function `AudioService.isUriSource`, pinned by a new Kotlin test (`AudioServiceTest`, 2 cases, 48 → 50 fork tests).
- Step 5 as specified: `alarmAssetPathFor(AlertSound)` returns the raw URI; `_resolvePickedSound`, `resolveAlarmSound`, `copyAlarmSound`, `sha1`, `soundExecutor`, `mainHandler` and their imports are gone from `MainActivity`; the one-time `filesDir/alert_sounds` deletion runs from `configureFlutterEngine` on a plain thread. **Deviation:** the directory name survives as `LEGACY_ALARM_SOUND_DIR` because the deletion needs it. Doc comments updated in the gateway, `MainActivity`, `settings_keys.dart`; `alert_sound.dart` never described the copy and is unchanged.
- Step 6 as specified: `MainActivity` records `ACTION_SHOW` from `onCreate` and `onNewIntent` into `showAlarmsRequested`, answers `consumeShowAlarmsRequest` (true once) and pushes `showAlarms` on the alerts channel for the warm case; `AlertIntent` is now payload-less with an abstract `dedupeKey`, `payload`/`osId` moved down to a sealed `AlertEntryIntent` (the parent of `OpenEventIntent` and `OpenAlarmIntent`, so OS-3's `SkipNextFireIntent` can share it), `OpenAlertsHubIntent` keys on the string `'alerts-hub'`, and the queue dedupes on `dedupeKey`; `AlertGateway.showAlarms` is an empty stream on the base (so on the no-op binding), a broadcast stream fed by the gateway's method-call handler on Android; `launchIntent()` asks `consumeShowAlarmsRequest` only when the notification launch details yielded nothing; `main.dart` subscribes and its drain calls the new `AppNavigator.toAlertsFromPlatform()`, which collapses onto a live hub route the way `toCalendarOccurrence` does and otherwise root-pushes `AlertsPage` under the `alerts` stamp. The gateway sets its method-call handler in its constructor (no platform call is made there) so a warm push cannot land before `initialize()` finishes.
- Step 7 as specified: `kAlertAlarmChannelId = 'alerts_alarm_v2'`, created with `UriAndroidNotificationSound('content://settings/system/alarm_alert')` and `audioAttributesUsage: alarm`; `kAlertLegacyAlarmChannelId = 'alerts_alarm'` is deleted in `_initialize` before the new channel is created; `injection.dart` reads the constant, so the permission status query lists the new id; `COPILOT_CONTEXT.md` and the parent §6.1 name it.
- Step 8: `CLAUDE.md` (architecture bullet for `packages/alarm/`, the two commands), parent roadmap (status paragraph, A5 row, §3.4, §5.2, §6.1, §6.2 pointer, §11 Doze row closed), `calendar-events-feature.md` §12 (backend paragraph, copy sentence), `COPILOT_CONTEXT.md` (v40 bullet, permissions channel list), the `qa-emulator` skill and `docs/qa-harness.md` (the `dumpsys alarm` check — there is no `qa alerts` verb yet; the two read-only queries are documented as the sanctioned exception).

Not shipped: nothing in scope. The upstream PR for the two patches (§11's mitigation) is the owner's to open — it needs a GitHub identity this run does not have.

Name corrections (code wins): the roadmap's §9 wording expects the `0x8` (`ALLOW_WHILE_IDLE_UNRESTRICTED`) bit in the `flags` mask; on API 36 an alarm-clock entry prints `flags=0x3` (`STANDALONE | WAKE_FROM_IDLE`) and carries the exemption as `idle-options` with `temporaryAppAllowlistReasonCode=301` (`REASON_ALARM_MANAGER_ALARM_CLOCK`) plus a `Next wake from idle:` listing — the §9 checklist row should read the block, not the bit. `alert_scheduler_test.dart` is not byte-for-byte untouched: its `FakeAlertGateway` **implements** the interface, so the new `showAlarms` getter had to be added (3 lines, no test changed). `pending_navigation_test.dart`'s four existing assertions that read `.osId` off a drained `AlertIntent` now read `.dedupeKey` (a drained list is typed on the base class); the double-delivery test the Review focus names still exists and passes unchanged in meaning.

Tests: `flutter test` 5544 → 5546 (the two new `pending_navigation_test.dart` cases: "the hub intent dedupes against a second hub intent", "the hub intent never dedupes against an alarm intent"); `android_alert_gateway_test.dart`: "a picked sound arms verbatim" (replaces "arms with the file it was copied into"), "inherit never reaches the platform; it arms the phone's default" (replaces "a sound this device cannot resolve…"), "the channel ids are frozen" extended to the new and legacy ids and the channel sound URI; fork Kotlin: `AudioServiceTest` (2), 48 → 50. Baseline note: `test/database/vocabulary_crdt_test.dart` "stamping an edit bumps the version…" failed once in the baseline run and passed 3/3 alone — the known same-millisecond HLC flake, not touched.

Gates (after step 7, from a clean state):
- `flutter gen-l10n`: not run — no `.arb` changed in OS-1.
- `dart analyze lib test`: 2 issues, both the known `label_appearance_service.dart` warnings.
- `dart analyze packages/alarm/lib`: No issues found.
- `flutter test`: `+5546 ~7: All tests passed!`
- `cd android && ./gradlew :alarm:testDebugUnitTest`: `testDebugUnitTest: 50 tests, 0 failed, 0 skipped`, BUILD SUCCESSFUL.
- `git status --short`: `M CLAUDE.md`, `M COPILOT_CONTEXT.md`, `M .claude/skills/qa-emulator/SKILL.md`, `M android/app/src/main/kotlin/com/alexzamfir/anta/MainActivity.kt`, `M docs/calendar-events-feature.md`, `M docs/event-alerts-roadmap.md`, `M docs/qa-harness.md`, `M lib/constants/settings_keys.dart`, `M lib/main.dart`, `M lib/services/alert_gateway.dart`, `M lib/services/android_alert_gateway.dart`, `M lib/services/app_navigator.dart`, `M lib/services/pending_navigation.dart`, `M pubspec.lock`, `M pubspec.yaml`, `M test/services/alert_scheduler_test.dart`, `M test/services/android_alert_gateway_test.dart`, `M test/services/pending_navigation_test.dart`, `?? docs/event-alerts-os-integration-roadmap.md`, `?? packages/alarm/`. No generated file hand-edited; no `key.properties`, keystore or `google-services.json` anywhere in the diff (the `.gitignore` also refuses them).

Device: emulator-5554, AVD `Medium_Phone_API_36.1` (Android 16 / API 36.1, `google_apis_playstore` arm64), booted through `qa boot --avd`, driven through `qa -d android` (`--via agent` for the app, native for the shade and keyguard); `qa run --fresh` built and installed the fork (`build/alarm/tmp/kotlin-classes/debug/.../AlarmScheduler.class` carries `setExactAlarm(Context, AlarmManager, long, PendingIntent, int)` and `showIntent(Context, int)`).
- `dumpsys alarm` on the Calendar-settings test alarm — **pass**: `RTC_WAKEUP #4: Alarm{… com.alexzamfir.anta}` / `tag=*walarm*:com.alexzamfir.anta/com.gdelataillade.alarm.alarm.AlarmReceiver` / `flags=0x3` / `Alarm clock:` / `triggerTime=2026-09-22 20:52:13.014` / `showIntent=PendingIntent{1e2074a: PendingIntentRecord{8b1d6bb com.alexzamfir.anta startActivity}}` / `idle-options=Bundle[{… temporaryAppAllowlistReasonCode=301 …}]` and `Next wake from idle: Alarm{7cf74b5 … com.alexzamfir.anta}`. The `0x8` bit is not in the mask on this API (see the name correction above).
- Status-bar alarm icon — **pass**: `build/qa/shots/20260922_205205_os1_02_alarm_icon.png` (icon beside `8:52`); the native tree names it `ImageView "Alarm set for Tue 9:03 PM."`.
- `settings get system next_alarm_formatted` — **pass**: `Tue 8:52 PM` (test alarm), `Tue 9:03 PM` (its snooze), `Tue 9:02 PM` (the seeded recurring alarm).
- Lock screen shows the time — **pass**: keyguard enabled for the check with `locksettings set-disabled false` (a stock AVD has none; restored at the end of the run), `dumpsys window` → `isKeyguardShowing=true`, `build/qa/shots/20260922_205845_os1_13_lockscreen.png` shows `8:58 · Tue, Sep 22 · ⏰ 9:03`, native tree `TextView "Next alarm at 9:03" id=alarm_text_view`.
- Tap the lock-screen line → hub — **fail on this image, pass through Quick Settings**: tapping the keyguard's `alarm_text_view` at 20:59 started no activity at all (`logcat` has no `action.SHOW` START then), so on this Pixel image the keyguard line is not actionable; the Quick Settings tile `"Alarm, Tue 9:03 PM"` — the same show intent — logged `ActivityTaskManager: START u0 {act=com.gdelataillade.alarm.action.SHOW cat=[android.intent.category.LAUNCHER] flg=0x10000000 … cmp=com.alexzamfir.anta/.MainActivity}` at 20:56:22 and the app landed on the Alerts hub (`Header "Alerts"` in `build/qa/shots/20260922_205624_os1_07_hub.png`), which is the warm `onNewIntent` → `showAlarms` → `OpenAlertsHubIntent` path. The **cold** half (`consumeShowAlarmsRequest`) is **not run**: a `qa stop` is a force stop, which disarms every pending alarm by Android design (the tile then reads `"Alarm, No alarm set"`), and the harness has no verb that launches the app with a custom action.
- The ring still stops, snoozes and re-arms — **pass**: three rings stopped from the alarm page (`gone: "id:alarm-stop"`, `qa errors` clean each time); Snooze on the test alarm re-armed it as an alarm-clock entry at `triggerTime=2026-09-22 21:03:33.057`, which rang and was stopped; the seeded weekly event ("OS-1 recurring alarm", Tue/Thu 21:02) rang at 21:02:00 on a sleeping, locked emulator (`AudioService: Using device default alarm sound`, `AlarmService: Alarm rang notification for 1923492599 was processed successfully by Flutter`), and after Stop `[AlertScheduler] reconcile(ringHandled, qa-event-weekly-lift) backend=alarm planned=2 scheduled=2 cancelled=0` left alarm-clock entries at `2026-09-24 21:02:00.000` and `2026-09-29 21:02:00.000`, both listed in the hub with their switches (`build/qa/shots/…_os1_17_hub_recurring.png`).
- Force stop, then launch (§3.4's "only recovery") — **pass**: after the `qa stop` above the tile read `"Alarm, No alarm set"`; `qa relaunch` (pid 21168) logged `[AlertScheduler] reconcile(launch) backend=alarm planned=2 scheduled=0 cancelled=0` — the fork's `Alarm.init()` had already re-armed both stored alarms as alarm-clock entries (`next_alarm_formatted` → `Thu 9:02 PM`, `dumpsys alarm` lists `triggerTime=2026-09-24 21:02:00.000` and `2026-09-29 21:02:00.000`) and the OS-truth pass found nothing to redo; `qa errors` clean.
- `content://` sound — **pass**: Calendar settings → Alarm sound → *Choose from phone* → the Pixel Sounds picker → *Gems* → *Aquamarine* → SAVE; the row reads "Aquamarine"; the next test alarm logged `AudioService: Using URI sound: content://media/external_primary/audio/media/21?title=Aquamarine&canonical=1`; `adb shell run-as com.alexzamfir.anta ls files` → `datastore`, `flutter_callback_cache.json`, `profileInstalled` — no `alert_sounds`.

Open (for the reviewer first): the Patch 2 fallback deviation (never-silence moved into the plugin at ring time); the `AlertEntryIntent` layer; the keyguard-line result and the un-run cold half; the `0x8` wording in §9.

#### Fix report — 2026-09-22 (review by a fresh Fable subagent, Prompt B; verdict was *fix first*)

- **Finding 1 (must fix) — fixed.** The alarm-tier arm signature now ends in `kAlertArmClockToken` (`~clock`, `alert_constants.dart`), so `alertArmSignature` yields `alarm#<sound>~clock` for a ring-tier fire and the bare context for a reminder. A row a pre-fork build recorded (`alarm#<sound>`, armed with `setExactAndAllowWhileIdle` and, for a picked sound, with a copied file this build deletes) therefore differs from the fork's token and is re-scheduled under its existing os id on the first pass, before the plugin's own `Alarm.init()` re-set can matter; the second pass finds the fork's token and does nothing. Test added: `alert_scheduler_test.dart` "a row armed before the fork is re-armed once, in place" (seeds the old string through the DAO, asserts one schedule, same os id, the new token, then a quiet third pass); `android_alert_gateway_test.dart` "the arm signature ends in the fork token for the alarm tier only"; the four literal expectations moved to the new form. Device: the first launch of the fixed build on the emulator's standing QA database logged `[AlertScheduler] reconcile(launch) backend=alarm planned=2 scheduled=2 cancelled=0` (21:21:14, pid 21668) — both rows re-armed once — against `scheduled=0` on the launch before it.
- **Finding 2 (should fix) — fixed.** Parent §3.4 names `alerts_alarm_v2` (with the deletion of the old id); `CLAUDE.md`'s docs row no longer says "planned"; §9's `dumpsys` row now reads the `Alarm clock:` block, the `0x2` bit and the `idle-options` reason `301`, and says the `0x8` bit is absent on API 36; `android_permission_gateway_test.dart` passes `kAlertReminderChannelId` / `kAlertAlarmChannelId` instead of the retired literal.
- **Finding 3 (should fix, low) — fixed.** `MainActivity.onNewIntent` still records the request before pushing (the push can precede the Dart handler), but the `invokeMethod` carries a `MethodChannel.Result` whose `success` clears `showAlarmsRequested`, so a later `launchIntent()` — a hot restart's — answers false. Device: with *Reopen last screen* set to Off (so the last-location restore cannot reopen the hub on its own), the Quick Settings tile opened the hub (`Header "Alerts"`), and after `qa restart` the app showed the root folder page (`build/qa/shots/20260922_212408_os1_22_after_restart_off.png`, "3 folders") — no hub. The same sequence with restore on reopened the hub through the restore, which is why the check needed the setting off.

Gates after the fixes, from a clean state:
- `flutter gen-l10n`: not run — no `.arb` changed.
- `dart analyze lib test`: 2 issues, the two known `label_appearance_service.dart` warnings.
- `dart analyze packages/alarm/lib`: No issues found.
- `flutter test`: `+5548 ~7: All tests passed!` (5546 + the two tests above).
- `cd android && ./gradlew :alarm:testDebugUnitTest --rerun`: `testDebugUnitTest: 50 tests, 0 failed, 0 skipped`, BUILD SUCCESSFUL.
- `untranslated.txt` reads `{}`.
- `git status --short`: the OS-1 file list of the Session report plus `M test/services/android_permission_gateway_test.dart` and `M lib/constants/alert_constants.dart`.

### OS-2 — Native snooze

**Preconditions.** OS-1 shipped and committed; the emulator pass of OS-1
green.

**Prompt A — create:**

> Implement session OS-2 of `docs/event-alerts-os-integration-roadmap.md`
> on the committed OS-1 tree. Load the `anta-context`, `calendar-events` and
> `qa-emulator` skills; read that roadmap §3 and §8.0, `docs/event-alerts-roadmap.md`
> §3.4 (the in-flight band) and the plugin's own contract in
> `packages/alarm/lib/alarm.dart` — the doc comments on `events`,
> `acknowledgeEvent` and `init(acknowledgeEventsAutomatically:)` — before
> writing a line. Scope:
> 1. In `_scheduleAlarm`: `androidSnoozeDuration: Duration(minutes: settings.snoozeMinutes)`
>    (read once per pass like `silenceAfter`, never per fire) and
>    `notificationSettings.androidSnoozeButton: l10n.alarmSnoozeMinutes(settings.snoozeMinutes)`.
>    The snooze length then rides the arm signature (`AlertGateway.refreshArmContext`
>    appends `~<minutes>` on the alarm backend) so a changed setting re-arms
>    standing alarms.
> 2. `Alarm.init(acknowledgeEventsAutomatically: false)`. In `_initialize`,
>    subscribe to `Alarm.events` **before** `Alarm.init()`: an `AlarmMoved`
>    with cause `snooze` is appended to a private list keyed by
>    `(id, recordedAt)` (the stream is at-least-once; a duplicate key is
>    dropped); every other event — `AlarmDropped` of any cause, `AlarmMoved`
>    with another cause — is acknowledged immediately with
>    `Alarm.acknowledgeEvent` and otherwise ignored (the registry's own late
>    path already covers drops).
> 3. `AlertGateway` gains `Future<List<AlertMove>> takeMoves()` (returns and
>    clears the list; awaits `initialize()` on Android; empty on the no-op
>    binding) and `Future<void> acknowledgeMove(AlertMove)`, where
>    `AlertMove` is a record `({int osId, DateTime nextRingAt, DateTime recordedAt})`
>    in `alert_gateway.dart`.
> 4. `AlertScheduler._reconcile`: right after `_dao.sweep` and before
>    `refreshArmContext`, `for (final move in await _gateway.takeMoves())`:
>    read the row by os id; if there is none, or it names another database's
>    alarm, acknowledge and continue; else `put` it back with
>    `fireAt = nextRingAt`, `kind = snooze`, `state = pending`, `updatedAt =
>    now`, then acknowledge. This runs inside the serialized chain and must
>    not call `_serialize` itself.
> 5. Nothing else changes: the diff's snooze rule, `ringingIds`,
>    `cancelSnoozeForAlert`, `hubEntries` and `settleEndedRing` already do
>    the right thing for a `kind = snooze` row — confirm each by reading it
>    and say so in the report.
> Tests in `alert_scheduler_test.dart` (extend `FakeAlertGateway` with a
> `moves` list and an `acknowledged` list): a move turns the armed row into
> a pending snooze under the same os id and is acknowledged; a duplicate
> `(osId, recordedAt)` is applied once; a move for an unknown os id is
> acknowledged and writes nothing; an unrelated `reconcileAll` afterwards
> neither cancels nor re-schedules the snoozed row; the moved alarm's ring
> (`markFired` then `stop`) settles it and re-plans the event; a reminder
> registration is untouched by all of the above; the arm signature changes
> when the snooze setting changes and only for the alarm tier. In
> `android_alert_gateway_test.dart`: the signature token with `~10`.
> Device pass (emulator): `qa run --fresh`, set the snooze setting to 5,
> arm the test alarm, lock the screen so the ring is a heads-up (a force
> stop is forbidden by the harness rules), press Snooze on the plugin's
> notification, then `qa launch` the app: the hub shows the snooze with its
> original time and *Cancel snooze*; wait for the +5 ring; Stop settles it;
> `qa errors` is clean. Append the Session report. Do not commit.

**Review focus (OS-2):**
- The `Alarm.events` subscription exists before `Alarm.init()` and survives
  `_initialize` being retried after a failure.
- Every event kind that is not a snooze move is acknowledged; nothing is
  left to be redelivered on every launch for a week.
- `takeMoves()` cannot deadlock: it awaits `initialize()` only, never the
  scheduler's chain.
- A move applied to a row that the plan would otherwise cancel is protected
  by the existing `kind = snooze` branch, not by a new special case.
- The snooze length reaches the plugin from the settings read the pass
  already does; no new settings read per fire.

#### Session report — 2026-09-22, Claude Fable 5.1 (single-run prompt, §8.7)

Shipped:
- Item 1 with one deviation in mechanism: `_scheduleAlarm` arms `androidSnoozeDuration: Duration(minutes: payload.snoozeMinutes)` and `notificationSettings.androidSnoozeButton: l10n.alarmSnoozeMinutes(payload.snoozeMinutes)` — the payload's snooze length **is** the scheduler's once-per-pass settings read, so the gateway reads no setting of its own, per fire or per pass. The snooze length rides the arm signature as `~<minutes>` after `~clock` (`alarm#system:default~clock~10`), composed in `alertArmSignature` from a new required `snoozeMinutes` parameter (the scheduler's `settings.snoozeMinutes`) rather than appended by `refreshArmContext`: the token stays pure and testable with no gateway involvement, and every standing alarm re-arms once after the upgrade so it gains the button.
- Item 2 as specified: `_eventsSub = Alarm.events.listen(_handleAlarmEvent)` is (re)subscribed immediately before `Alarm.init(acknowledgeEventsAutomatically: false)`, so a retried `_initialize` re-subscribes and the buffered replay is absorbed by the `(id, recordedAt)` key; a snooze `AlarmMoved` goes into `_moves` (a map keyed on that pair, duplicates dropped), every other event — a drop of any cause, a platform-refusal move — is acknowledged on arrival.
- Item 3 as specified: `AlertMove` (`({int osId, DateTime nextRingAt, DateTime recordedAt})`), `takeMoves()` (awaits `initialize()` only, returns and clears) and `acknowledgeMove()` (rebuilds the `AlarmMoved` for `Alarm.acknowledgeEvent`, which reads only id and `recordedAt`) on `AlertGateway`, with empty/no-op defaults on the base so the no-op binding inherits them.
- Item 4 as specified: `_reconcile` drains `takeMoves()` right after `_dao.sweep` and before `refreshArmContext`, inside the chain, through `_applyMove`: the row is rewritten under the same os id as `kind = snooze`, `pending`, `fireAt = nextRingAt`, `updatedAt = now`, then acknowledged. Guards, all recorded: only a `pending` **or `fired`** row (the ring handler marks a ring `fired` before the user reaches the notification's Snooze), only the alarm tier (`_isMovable`), only towards an instant still ahead, and a move already applied — same instant, already a pending snooze — writes nothing, which is what makes the at-least-once stream harmless; an unknown id, a settled row, a past instant or a reminder's id is acknowledged and dropped.
- Item 5, confirmed by reading: the diff's `AlertKind.snooze` branch keeps a moved row out of the cancel set unless orphaned (`_isOrphanedSnooze`); `ringingIds` seeds the cancel set from the gateway; `cancelSnoozeForAlert` matches on `(alertId, day, kind = snooze)` and so takes a moved row with it after the page's Stop; `hubEntries` renders a `kind = snooze` row with `originalFireAt` from `AlertPlanner.fireInstant` and `snoozeOsId`; `settleEndedRing` is untouched. None changed.
- **Two additions the device pass forced.** (a) With Dart up, a native Snooze empties the alarm out of `Alarm.ringing` exactly like a Stop does, and `_handleRinging` would have reported a *dismissal* — `settleEndedRing` would then have cancelled the just-snoozed entry, marked the row `stopped` and run A3's removal. `AlertRingEndCause.snoozed` was added: `_handleRinging` reads `Alarm.scheduled.value.containsId(osId)` at the moment the ring is seen to end — the plugin's `_applyMove` republishes the ringing set *first* in source order, but both subjects deliver asynchronously and set `value` at `add`, so both are current before either listener runs (corrected at the review; the fork's `alarm_snooze_test.dart` pins it); `main.dart`'s `_settleEndedRing` answers `snoozed` with a `reconcileEventById(…, ringHandled)` (which drains the move) and nothing else, and an open alarm page closes on it as on any other ending. (b) A ring whose `OpenAlarmIntent` was queued while the app sat in the background — no frames, so no drain — and which the user then snoozed from the notification had its alarm page pushed on the next resume, offering Stop for a ring that was over; that Stop would have cancelled the snooze. `_drainPendingNavigation` now drops an `OpenAlarmIntent` the gateway no longer counts in `ringingIds` (`_isRinging`, answering yes when no gateway can say).

Not shipped: nothing in scope.

Name corrections (code wins): the prompt's "read once per pass like `silenceAfter`" — `_silenceAfterMillis` is in fact read per notification schedule; the snooze length is read once per pass by the scheduler and travels in the payload, which is what the arm uses. The prompt's device step "lock the screen so the ring is a heads-up" is inverted on API 33+: a locked phone gets the full-screen page, and the heads-up is the phone-in-use case — the pass sent the app to the background with the screen on instead.

Tests: `flutter test` 5548 → 5556. `alert_scheduler_test.dart`, group "native snooze (OS-2)" (the fake gained `moves` / `acknowledged`, `takeMoves`, `acknowledgeMove`): "a move turns the armed row into a pending snooze, same os id", "a duplicate (osId, recordedAt) is applied once" (asserted on an unchanged `updatedAt` across a later pass), "a move for an unknown os id is acknowledged and writes nothing", "an unrelated reconcile leaves the moved snooze alone", "the moved alarm's ring settles it and re-plans the event", "a reminder registration is untouched by all of the above", "the arm signature moves with the snooze setting, alarm tier only"; `android_alert_gateway_test.dart` "the arm signature carries the snooze length for the alarm tier" (`~10`, `5 ≠ 10`, a reminder unchanged); `alert_gateway_test.dart` extended (`takeMoves` empty, `acknowledgeMove` silent on the no-op). Every signature literal moved to `~clock~10`. The two additions have no unit test: the ring-end classification reads a plugin static (`Alarm.scheduled`) and the drain guard lives in `_MyAppState`; the device pass below is their evidence.

Gates (from a clean state):
- `flutter gen-l10n`: not run — no `.arb` changed (`alarmSnoozeMinutes` is reused); `untranslated.txt` reads `{}`.
- `dart analyze lib test`: 2 issues, the known `label_appearance_service.dart` warnings.
- `dart analyze packages/alarm/lib`: No issues found.
- `flutter test`: `+5556 ~7: All tests passed!`
- `cd android && ./gradlew :alarm:testDebugUnitTest --rerun`: `testDebugUnitTest: 50 tests, 0 failed, 0 skipped` (the fork is untouched by OS-2).
- `git status --short`: `M COPILOT_CONTEXT.md`, `M docs/calendar-events-feature.md`, `M docs/event-alerts-roadmap.md`, `M lib/main.dart`, `M lib/services/alert_gateway.dart`, `M lib/services/alert_scheduler.dart`, `M lib/services/android_alert_gateway.dart`, `M test/services/alert_gateway_test.dart`, `M test/services/alert_scheduler_test.dart`, `M test/services/android_alert_gateway_test.dart`.

Device: emulator-5554 (`Medium_Phone_API_36.1`, API 36.1). `qa run --fresh`, then `qa relaunch --fresh --seed` with a fixture whose `settings` map carries `alert_snooze_minutes: '5'` (the slider was not dragged) and a weekly Tue/Thu event with an at-start alarm three minutes out.
- Round 1 (build before the drain guard), event "OS-2 native snooze" at 21:34: `KEYCODE_HOME` sent the app to the background with the screen on, so the ring was a heads-up. `AlarmService: Alarm rang notification for 1923492599 was processed successfully by Flutter` (21:34:01); the shade held the notification "OS-2 native snooze" with `Button "Stop" id=action0` and `Button "Snooze 5 min" id=action0`; tapping Snooze logged `SnoozeCoordinator: Alarm 1923492599 snoozed until 1790102468331` (21:41:08) and, 0.1 s later, `[AlertScheduler] reconcile(ringHandled, qa-event-weekly-lift) backend=alarm planned=2 scheduled=2 cancelled=0` — the `snoozed` ring-end branch; `dumpsys alarm` then listed `triggerTime=2026-09-22 21:41:08.331`, `2026-09-24 21:34:00.000`, `2026-09-29 21:34:00.000`, `next_alarm_formatted=Tue 9:41 PM`. `qa launch` found the **stale alarm page** (`"21:34" · "OS-2 native snooze" · Stop · Snooze 5 min`) that addition (b) fixes — **fail, then fixed**; the page was left untouched (its Stop would have cancelled the snooze) and the app was rebuilt with the guard (`qa run`, launch reconcile `planned=2 scheduled=0`). The hub then showed "Today · 9:41 PM / 9:34 PM · Snoozed · At start" with *Cancel snooze* (`build/qa/shots/20260922_213935_os2_03_hub_snoozed.png`); the snoozed ring came at 21:41:09 with the page's clock still reading the original `21:34` (the plugin moved the payload as it was), Stop settled it (`gone: "id:alarm-stop"`, `reconcile(ringHandled, …) planned=2 scheduled=2`), `dumpsys` kept only 09-24 and 09-29; `qa errors` showed one `W/…Verification of java.lang.Throwable … took 157ms` ART line and nothing from the app.
- Round 2 (build with the guard), event "OS-2 drain guard" at 21:44: same steps; `SnoozeCoordinator: Alarm 1923492599 snoozed until 1790102952151` (21:49:12); `qa launch` landed on the root folder page (`"3 folders"`, `build/qa/shots/20260922_214423_os2_04_after_launch.png`) — **no alarm page, pass**; the hub: `"9:49 PM\n9:44 PM\nSnoozed · At start"` under `"Today"` with `Button "Cancel snooze"` (`build/qa/shots/20260922_214435_os2_05_hub_snoozed.png`); the ring at 21:49:12 (`found: Stop`), Stop → gone, `reconcile(ringHandled, qa-event-weekly-lift) planned=2 scheduled=2`, `dumpsys` `triggerTime=2026-09-24 21:44:00.000` and `2026-09-29 21:44:00.000`, the hub headed by Thursday, `qa errors`: `no errors in agent`.
- **Not run:** the drain of a marker recorded with **no Dart process** (`Alarm.init()` replaying it at the next launch). Both rounds had the app alive in the background, so the move arrived live; a force stop disarms every alarm (§3.4), and the harness has no way to kill the process without one. The ordering that covers it — subscription before `init`, the replay key — is the item-2 code; the owner's phone pass (§9) is where an app swiped away before a heads-up ring shows it. The roadmap's "set the snooze setting to 5" was done through the seed's settings map rather than the slider.

Open (for the reviewer first): the two additions — the `Alarm.scheduled` probe that tells a snooze from a Stop, and the `ringingIds` drain guard — and their lack of unit tests; the scheduler-side `~<minutes>` token; `_isMovable` accepting a `fired` row.

#### Fix report — 2026-09-22 (review by a fresh Fable subagent, Prompt B; verdict was *fix first*)

- **Finding 1 (must fix) — fixed.** `SettingsKeys.maxAlertSnoozeMinutes` is 25, one step under `kLateFireGrace`: a native snooze taken with no Dart running leaves the registry row at the original instant, and the snoozed ring is what launches the app, so at that launch the row is exactly the snooze length late — under the grace it is in flight and the ring handler settles it, at the grace it was reported missed and cancelled as a stray while it rang. The settings clamp and `AlertPayload.decode` follow the constant, so a stored 30 reads as 25. Guard test: `android_alert_gateway_test.dart` "the snooze length stays under the in-flight grace". Device (rebuilt QA build): the Calendar-settings slider pushed to its end reads "Snooze postpones an alert by 25 minutes" (agent dump, `build/qa/shots/20260922_220958_os2_07_snooze_slider.png` before the push).
- **Finding 2 (should fix) — fixed.** The gateway's `_handleRinging` doc, `calendar-events-feature.md` §12, `COPILOT_CONTEXT.md` and this Session report now state the real invariant: the plugin republishes `ringing` *before* `scheduled` in source order, and the probe holds because both subjects deliver asynchronously and set `value` at `add`. Pinned in the fork: `packages/alarm/test/alarm_snooze_test.dart`, group "ANTA fork: what a ringing listener can read" — a `ringing` listener that sees the alarm leave the set reads `Alarm.scheduled.value.containsId` true (`cd packages/alarm && flutter test test/alarm_snooze_test.dart` → `+14: All tests passed!`). That run writes `packages/alarm/build/` and two `pubspec.lock`s the package never shipped; `.gitignore` now lists them.
- **Finding 3 (should fix) — fixed.** Each `_applyMove` in the reconcile's move loop is wrapped: a failed write is logged and the pass continues with the next move and the rest of the turn; the failed move stays unacknowledged, so the plugin redelivers it at the next launch.
- **Finding 4 (should fix, low) — documented, not changed**, as the reviewer proposed: a natively snoozed platform entry keeps `snooze: false` and is protected by its registry row alone, so an event import between the snooze and its ring loses it where an in-app snooze survives; re-arming from `_applyMove` would cancel-and-re-arm the plugin's entry and report a spurious stop. Recorded in §12 and `COPILOT_CONTEXT.md`.
- Notes: the "duplicate applied once" test pins the scheduler's idempotence guard, not the gateway's `(id, recordedAt)` map, which has no seam — the Session report's wording above is to be read that way. The new `//` blocks follow each file's own style, as the reviewer noted, and are left. The Session report's `git status` list omitted this roadmap file, which was of course modified.
- **Outside the OS-2 scope, done for the gate:** the whole suite went red twice in this session on two different CRDT suites' "an edit bumps the version, keeps createdAt and moves the HLC" (vocabulary, then calendar event), each passing alone. The cause is in `lib/database/crdt/hlc.dart`, not the tests: `HybridLogicalClock.now()` compared `DateTime.now()` at microsecond precision but emitted milliseconds, so two stamps in one millisecond with a later microsecond reset the counter and came out equal — a real same-millisecond ordering tie in the sync CRDT, not only a flake. Comparisons are now made on the millisecond-truncated instant (`_wallMillis`, also in `receive`), pinned by the new `test/database/hlc_test.dart` (2000 back-to-back stamps strictly increasing; a received stamp is passed). The fork's `analysis_options.yaml` was found modified in the working tree (a wider analyzer exclude list nobody in this run authored; presumably a review pass's tooling) and was restored to the committed copy.

Gates after the fixes, from a clean state:
- `flutter gen-l10n`: not run — no `.arb` changed; `untranslated.txt` reads `{}`.
- `dart analyze lib test`: 2 issues, the known `label_appearance_service.dart` warnings.
- `dart analyze packages/alarm/lib`: No issues found.
- `flutter test`: `+5559 ~7: All tests passed!` (5556 + the guard test + the two HLC tests).
- `cd android && ./gradlew :alarm:testDebugUnitTest --rerun`: `testDebugUnitTest: 50 tests, 0 failed, 0 skipped`.
- `cd packages/alarm && flutter test test/alarm_snooze_test.dart`: `+14: All tests passed!`
- `git status --short`: the Session report's list plus `M .gitignore`, `M lib/constants/settings_keys.dart`, `M lib/database/crdt/hlc.dart`, `M packages/alarm/test/alarm_snooze_test.dart`, `?? test/database/hlc_test.dart`, and this roadmap.

### OS-3 — Upcoming-alarm notice

**Preconditions.** OS-1 shipped; OS-2 preferred but not required.

**Prompt A — create:**

> Implement session OS-3 of `docs/event-alerts-os-integration-roadmap.md`
> on the committed tree. Load the `anta-context`, `calendar-events`,
> `qa-emulator` and `l10n` skills; read that roadmap §4 and §8.0, and
> `docs/event-alerts-roadmap.md` §3.3 (os ids) and §3.4 (the notification
> tier's action handling). Scope:
> 1. `alert_constants.dart`: `kAlertNoticeIdSalt` (a different value from
>    `kAlertMissedIdSalt`), `noticeNotificationId(osId)` and
>    `isNoticeNotification(id, payload)` next to their Missed twins in
>    `android_alert_gateway.dart`; `AlertPayloadKeys.notice` and a
>    `notice: bool` field on `AlertPayload` (default false, round-tripped).
> 2. `SettingsKeys.alertNoticeLeadMinutes` (`alert_notice_lead_minutes`,
>    default 120, min 0, max 1440, step 30) through `AlertSettings`,
>    `SettingsService` getter/setter/reset, and a `SliderSettingRow` under
>    the Snooze slider on the Calendar settings page whose 0 reads as
>    "Off"; ARB keys ×3 for the row and the notice copy
>    (`alertsNoticeLead`, `alertsNoticeLeadDesc`, `alertsNoticeLeadOff`,
>    `alertsUpcomingTitle` with a `{time}` placeholder, `alertsSkipAction`,
>    `alertsOpenAction`, `alertsSkippedSnack` with `{title}`).
> 3. `AndroidAlertGateway.schedule`: for an alarm-tier, non-snooze fire
>    whose `fireAt − lead` is after now and lead > 0, `zonedSchedule` the
>    notice (`exactAllowWhileIdle`, `alerts_reminder`, low importance,
>    actions Skip with `showsUserInterface: true` and Open) after the
>    alarm itself; `cancel(osId)` and `stopRinging(osId)` also cancel
>    `noticeNotificationId(osId)`; `pendingEntries()` skips entries whose
>    payload says `notice`. The lead rides the arm signature as `~n<lead>`
>    (keep OS-2's `~<snooze>` token if it exists; the two must not collide).
> 4. `_handleResponse`: a response whose id is the notice id and whose
>    action is Skip enqueues `SkipNextFireIntent(payload)`; Open or a body
>    tap enqueues `OpenEventIntent`. `pending_navigation.dart` gains
>    `SkipNextFireIntent`; `main.dart`'s drain handles it by dispatching to
>    the calendar bloc: `SetOccurrenceSkipped(eventId: …, day: …)` for a
>    recurring event, the hub's `ToggleEventAlert` off for a one-time one,
>    then shows the calendar's snackbar with Undo (`ClearOccurrenceSkipped`
>    or the toggle back on, in the `alert_removal_notice.dart` shape), and
>    the reconcile the bloc already triggers cancels the alarm.
> Tests: `android_alert_gateway_test.dart` — id derivation never collides
> with the registration or Missed id spaces for a sample of ids, and the
> notice payload round-trips; `alert_scheduler_test.dart` — no notice for a
> snooze or a reminder is ever asked of the fake (extend the fake to record
> notices), the signature moves with the lead; a bloc test that a
> `SkipNextFireIntent` dispatches exactly one skip or one toggle;
> `pending_navigation_test.dart` for the new intent. Device pass
> (emulator): lead 30, an event 40 minutes ahead with an alarm — the notice
> appears at T−30 (use `qa log` to confirm the post), Skip opens the app,
> the snackbar shows, the hub no longer lists the alarm, Undo brings it
> back; a snooze produces no notice. Append the Session report. Do not
> commit.

**Review focus (OS-3):**
- The notice is never a registration: no DAO write, and `pendingEntries()`
  filtering is what keeps the OS-truth pass from cancelling it as a stray.
- Every path that removes an alarm from the platform removes its notice
  (`cancel`, `stopRinging`, the snooze's cancel in `_snooze`).
- Skip never runs in the background isolate.
- `lead = 0` schedules nothing and the signature token still changes, so
  turning the setting off clears standing notices on the next pass.

### OS-4 — Alarm log and richer content

**Preconditions.** None (independent of OS-1..3).

**Prompt A — create:**

> Implement session OS-4 of `docs/event-alerts-os-integration-roadmap.md`
> on the committed tree. Load the `anta-context`, `calendar-events`,
> `qa-emulator` and `l10n` skills; read that roadmap §5 and §8.0, and
> `lib/pages/alerts_page.dart` and `lib/models/alert_hub_entry.dart` in
> full. Scope:
> 1. `AlertRegistrationState.missed`, written in `_settlePastFires` on the
>    row it posts a Missed notice for and in `settleEndedRing` for a
>    timed-out ring; `fromName` still maps unknown values to `cancelled`.
> 2. `AlertScheduler.recentEntries()` (a read outside the chain, like
>    `hubEntries`): non-pending rows of the last `kAlertRegistrationRetention`,
>    newest `updatedAt` first, excluding `cancelled`, resolved to a new
>    `AlertHistoryEntry` (event, alert or null when removed, day, fireAt,
>    outcome enum rang/stopped/snoozed/missed). A row whose event is gone
>    is kept with the payload-free fallback title `alertsHistoryRemoved`.
> 3. The hub: a *Recent* section header after the live rows (ARB
>    `alertsRecent` ×3, plus one label per outcome), one glyph per outcome,
>    re-read on `registryRevision` like the rest of the page.
> 4. Richer content: `AlertPayload.excerpt` (≤ 120 chars, first non-empty
>    line of the description stripped of markdown by a pure helper next to
>    `agenda_search_text.dart`'s plain-text logic — reuse it if it already
>    strips), stamped in `_payloadFor`; on the alarm notification
>    `iconColor` from the event's resolved colour; on reminders and Missed
>    notices `color`, a large icon rendered once per schedule from the
>    category or event icon into a `ByteArrayAndroidBitmap`, and
>    `BigTextStyleInformation(excerpt)` when the excerpt is non-empty.
> Tests: scheduler — `missed` is written in both paths, `recentEntries`
> orders and excludes as specified and survives a removed event; payload —
> round trip with and without `excerpt`, and an older payload without it
> decodes; the stripping helper on headings, lists, links and money lines;
> a widget test that the hub renders a Recent row per outcome. Device pass
> (emulator): a ring stopped from the page, one stopped from the
> notification and one left to time out show up under Recent with the
> right glyphs; a reminder shows its big text and icon in the shade. Append
> the Session report. Do not commit.

**Review focus (OS-4):**
- The hub's live rows and their switch behaviour are byte-for-byte
  unchanged; Recent is additive.
- `recentEntries` issues one query and no per-row lookups (the
  `query_count_test` register).
- The large icon is rendered per schedule, not per frame, and never on the
  reconcile's inner loop more than once per fire.
- `excerpt` is stamped on the UI isolate; no background isolate composes it.

### OS-5 — Session chip, tile, shortcut

**Preconditions.** The parent's Session 6 shipped the quick-alarm sheet
(for the tile and shortcut); an API 36 emulator image (for the chip); the
promoted-notification API names verified against the API 36 reference.

**Prompt A — create:**

> Implement session OS-5 of `docs/event-alerts-os-integration-roadmap.md`
> on the committed tree. Load the `anta-context`, `calendar-events`,
> `qa-emulator` and `l10n` skills; read that roadmap §6 and §8.0, and
> `lib/services/alert_removal_notice.dart` (`AlertAcknowledgement.apply`).
> Scope: (1) the `sessionChip` pair on the alerts channel —
> `showSessionChip(payloadJson, startedAtMs, endsAtMs?)` and
> `clearSessionChip()` — implemented natively in `MainActivity` with the
> API 36 promoted path behind `canPostPromotedNotifications()` and the
> chronometer fallback, two actions routed back through the existing
> notification-response path (`Open note` → the event's linked note or the
> event; `Done` → clear); (2) `AlertGateway.showSessionChip/clearSessionChip`
> (no-ops on the no-op binding), called from `AlertAcknowledgement.apply`
> and the alarm page's Stop for the ring tier only, cleared by Done, by a
> new ring, and by the event's end time when it has one (a timer while the
> app is up; otherwise the next launch clears a stale chip); (3)
> `QuickAlarmTileService` + `shortcuts.xml` + the `QUICK_ALARM` action
> through `MainActivity` and a `QuickAlarmIntent` in
> `pending_navigation.dart` that the drain turns into the quick-alarm
> sheet; manifest entries for the tile service (with the
> `BIND_QUICK_SETTINGS_TILE` permission) and the shortcuts meta-data; ARB
> keys ×3 for the tile label, the chip's actions and the shortcut. Tests:
> the acknowledgement path asks the gateway for one chip per ring and
> never for a reminder; the new intent dedupes and decodes; a widget test
> that the drain opens the sheet. Device pass: API 36 emulator — after a
> ring's Stop the chip appears with a running timer, Done clears it; a
> pre-36 image shows the chronometer notification; the tile appears in the
> Quick Settings editor and opens the sheet; the shortcut too. Append the
> Session report. Do not commit.

**Review focus (OS-5):**
- No chip for a reminder, a test alarm, or another database's alarm.
- The chip is posted once per acknowledgement even when both the page's
  Stop and the platform's `ringEnded` fire for the same ring.
- The tile's `startActivityAndCollapse` uses the `PendingIntent` overload.

### OS-6 — iOS through AlarmKit

Written when the parent's Session 8 is done and the Mac can build the
runner; §7 is the direction, the prompt is owed. Its Prompt A must start by
verifying every AlarmKit API name against the current reference and
recording the iOS version tested.

### 8.7 The single-run prompt (OS-1 to OS-5)

For one session that carries the whole roadmap through at maximum effort.
It does not replace §8.0: it runs §8.0 five times, with the review done by
a fresh subagent so the reviewer has no memory of the creator's choices.
OS-6 is excluded (it needs the Mac runner and a verified AlarmKit
reference).

> You are implementing `docs/event-alerts-os-integration-roadmap.md` in
> full, sessions OS-1 to OS-5, at maximum effort, autonomously: nobody will
> answer questions mid-run, so every decision the roadmap leaves open is
> yours to take, record and move on from. Work from `frontend/anta`.
>
> **Read first, completely, before any edit:** `CLAUDE.md` at the repo
> root and in `frontend/anta`, the `anta-context`, `calendar-events`,
> `qa-emulator`, `l10n` and `drift-migrations` skills, the whole of
> `docs/event-alerts-os-integration-roadmap.md`, and of
> `docs/event-alerts-roadmap.md` §§2.3, 2.6, 3.1–3.4, 5.6, 10.5 and 11.
> Then the code the sessions name: `lib/services/alert_gateway.dart`,
> `android_alert_gateway.dart`, `alert_scheduler.dart`,
> `pending_navigation.dart`, `alert_removal_notice.dart`, `lib/main.dart`,
> `lib/utils/alert_planner.dart`, `lib/models/alert_payload.dart`,
> `lib/pages/alerts_page.dart`, `android/app/src/main/kotlin/com/alexzamfir/anta/MainActivity.kt`,
> and — after setting `alarm: ^5.13.2` in `pubspec.yaml` and running
> `flutter pub get` so the cache holds it —
> `~/.pub-cache/hosted/pub.dev/alarm-5.13.2/lib/alarm.dart` plus its
> `android/src/main/kotlin/com/gdelataillade/alarm/services/AlarmScheduler.kt`
> and `AudioService.kt`. The roadmap is the spec; where it and the code
> disagree about a name, the code wins and you note the correction in the
> Session report.
>
> **Preconditions you establish yourself:** `git status` clean apart from
> the pre-existing `pubspec.lock` drift (leave it); `flutter test` green
> (record the count); an Android emulator booted through `qa boot --avd`
> (`qa devices` first; never `adb` or `emulator` by hand). If no emulator
> can be booted, every device check in this run is recorded as *not run*
> with the reason — never described as passed.
>
> **Run these sessions in this order:** OS-1, OS-2, OS-3, OS-4, OS-5.
> For OS-5, implement the session chip in full; implement the tile and
> the shortcut only if the parent's Session 6 quick-alarm sheet exists in
> the code (`grep -ri quickalarm lib`); otherwise record that half as
> *blocked on Session 6* in the report and do not stub it.
>
> **For every session, exactly this loop, no step skipped:**
> 1. *Create* — follow the session's Prompt A verbatim, including its
>    tests, its device pass and its Session report. Do not start the next
>    step with a red gate.
> 2. *Review* — spawn a fresh subagent (the Agent tool, general-purpose,
>    no notes from you, no summary of what you did) with the roadmap's
>    Prompt B, the session id substituted, and the instruction to return
>    only its findings and verdict. If no subagent tool exists, close every
>    file, re-read the full diff from `git diff` as a stranger would, and
>    answer Prompt B yourself in writing, under the Session report, headed
>    *Self-review*.
> 3. *Fix* — apply Prompt C to the findings. A *must fix* you disagree with
>    is still fixed unless you can show, in the Fix report, a test that
>    proves the reviewer wrong.
> 4. *Verify* — run every gate in §8.0 from a clean state (`flutter test`
>    is the whole suite, not the session's files) and the session's device
>    checks that the fixes touched. Paste the exact results.
> 5. *Record* — the reports under the session heading, the status line at
>    the top of the roadmap, the parent roadmap's status paragraph, and the
>    §10 docs for that session. Then commit that session alone:
>    `git add -A && git commit -m "event alerts OS-N: <one line>"` ending
>    with the attribution line this environment prescribes. This prompt is
>    your authorisation to commit; do not push.
>
> **Rules that override convenience:** never weaken, skip or delete a
> test to get green — a test that is wrong is fixed with its reason in the
> report; never hand-edit a generated file; never reset or migrate away
> user storage; the registry stays device-local; nothing in a background
> isolate opens a database; the Reminder tier never touches the `alarm`
> plugin; every user-visible string lands in all three `.arb` files and
> `untranslated.txt` reads `{}`; comment style follows the file; no new
> markdown files beyond the reports you append; nothing that looks like a
> credential is read, printed or committed.
>
> **Stop conditions:** a gate that is still red after two honest fix
> attempts on the same finding; a device check that fails in a way the
> roadmap did not anticipate and that a fix would change a B-decision; a
> plugin API that turns out not to exist as the roadmap describes. On any
> of these, stop that session cleanly (tree consistent, gates of the
> previous session still green, nothing half-applied), write what you
> found and what you propose under the session heading, and continue with
> the next session only if it does not depend on the stopped one. Never
> paper over a stop.
>
> **At the end:** one consolidated report at the top of §8.7 in the
> roadmap — per session: shipped / blocked / stopped, the commit hash, the
> test count delta, the device evidence summary, and the open items for
> the owner's phone pass (§9). Then say, in your final message, which
> sessions are committed and what the owner has to do next, with nothing
> claimed that the reports do not show.

## 9. Verification checklist (owner's phone, after OS-1)

Copy the parent's §9 rows and add:

- [ ] `adb shell dumpsys alarm > alarm.txt`: every ANTA alarm-tier entry
      prints an `Alarm clock:` block (`triggerTime` and a `showIntent` into
      `com.alexzamfir.anta`) under the app's batch, its `flags` mask includes
      `WAKE_FROM_IDLE` (0x2) — printed as hex, so read the mask rather than
      grepping a name; on API 36 the mask is `0x3` and the
      `ALLOW_WHILE_IDLE_UNRESTRICTED` bit is **not** set, the exemption
      riding the entry's `idle-options` bundle as
      `temporaryAppAllowlistReasonCode=301` (`REASON_ALARM_MANAGER_ALARM_CLOCK`)
      instead — the entry is listed under `Next wake from idle:` when it is
      the soonest, and the reminder entries print no such block. `adb shell
      settings get system next_alarm_formatted` names the soonest one (a
      legacy key; may be empty on some ROMs, in which case the lock screen is
      the check).
- [ ] Status-bar alarm icon while an ANTA alarm is the soonest on the phone;
      the lock screen shows its time; Quick Settings shows it; tapping opens
      the hub.
- [ ] `adb shell am set-standby-bucket com.alexzamfir.anta restricted`, an
      alarm 3 minutes ahead, screen off: rings on time. Then
      `adb shell dumpsys deviceidle force-idle`, same test.
- [ ] Overnight: alarm at wake-up time with the phone untouched since the
      evening — the parent's open A5 question, now expected to pass.
- [ ] Reboot 5 minutes before an alarm, do not open the app: it rings and the
      icon is back after boot.
- [ ] A picked sound from the phone's list plays at the ring. (The absence
      of a copy under `files/alert_sounds` is checkable only on a debuggable
      build, `adb shell run-as com.alexzamfir.anta ls files` on the
      emulator; on the release-signed phone build the deleted code path is
      the evidence.)
- [ ] Vendor and OS version recorded here.

## 10. Docs to update when a session ships

- `event-alerts-roadmap.md` §3.4 (the Alarm-tier bullet names `setAlarmClock`
  and the fork), §5.2 ("Why a picked sound is copied" goes), §6.1, §11 (the
  Doze rows close or move), the Session 9 sketch in §6.2 (AlarmKit).
- `calendar-events-feature.md` §12: backend, snooze, notice, log.
- `COPILOT_CONTEXT.md` Calendar v40 bullet: backend and fork.
- `CLAUDE.md`: `packages/alarm/` in the architecture section; the docs row.
- The `qa-emulator` skill and `docs/qa-harness.md`: the `dumpsys alarm`
  check as part of `qa alerts`.

## 11. Risks

| Risk | Mitigation |
| --- | --- |
| A second forked plugin to carry | The patch is two Kotlin functions and never touches generated bindings; the upstream PR is opened in the same session, and a merge lets the fork go. |
| `setAlarmClock` on Android 12–13 without the exact-alarm permission | Same fallback as today (inexact); the permission page already explains and links it. |
| OEM surfaces showing ANTA in their own alarm lists (Samsung Clock, some launchers) | Expected and correct — it *is* the phone's next alarm. The show intent makes the tap land somewhere sensible. |
| Forty-eight alarm-clock entries | Only the soonest is ever shown; the count is unchanged from today and far under the 500 limit. |
| A native snooze arriving while the launch reconcile runs | Moves are applied inside the chain before anything else; the in-flight band covers the seconds in between. |
| Promoted notifications refused by the user (Android 16 permission) | The plain chronometer notification is the same feature minus the chip. |

## 12. Not planned

Dismiss challenges, location or travel-time alerts, smart wake windows,
watch-side alarms: other kinds of apps. Repeating "nag" reminders until Done
were considered and left out — the native snooze and the notice cover the
"remind me again" need without a fourth scheduling concept.
