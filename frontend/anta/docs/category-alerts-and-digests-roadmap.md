# Category alerts and digests — design record (2026-10-15)

**Status: IMPLEMENTED, REVIEWED and DEVICE-PASSED 2026-10-15 on `e54d752`,
uncommitted — the owner commits.** Five slices in one day: four code slices
each built by one implementer and reviewed by one reviewer with a fix pass
(the reviews' 69 findings and what became of each are in §9's ledger; the
record was corrected where the code exposed it — D4, D13, D15, D16, D17,
§3.3–§3.7, §5, §6), the fixture, the two flows and the docs, and a green
emulator pass with the digest's inbox notification on the shade and its tap
on the overview. Gate at the end: `dart analyze lib test` clean, `flutter
test` `+8046 ~10 -1` (`+7700` before; the one failure `host_devices_test`,
Windows-only, pre-existing), `untranslated.txt` `{}`. Open: §11.1's
residuals (the missing `qa fire` verb first), iOS through the alerts
roadmap's Sessions 8–9 on the Mac (§10). The owner asked for alerts that
follow every occurrence of a kind of event ("remind me before each birthday,
x time or x days before") and for one bundled notification on a cadence
("there will be x birthdays this month, like Facebook; configurable so
custom events are bundled in a single notification"). Decisions D1–D23 (§2)
were taken **as proposed (A each) on 2026-10-15**, the mock's M1–M6 as
recommended; §9 is the slice plan and ledger, §10 how it ran.
Mock (2026-10-15, one page, light and dark): "Alerts and digests mock",
https://claude.ai/artifact/3BRnAxW21fH7WsjdD1tPat — the hub, the digest
sheet, the category and event editors, the notification; its M1–M6 refine
D3, D5, D10 and D14 at the row level.

## Contents

0. [The ask and the reading](#0-the-ask-and-the-reading)
1. [What exists today](#1-what-exists-today-facts-2026-10-15)
2. [Decisions D1–D23](#2-decisions)
3. [Domain model](#3-domain-model)
4. [Persistence — schema v42](#4-persistence--schema-v42)
5. [Planner, scheduler, gateway](#5-planner-scheduler-gateway)
6. [Surfaces](#6-surfaces)
7. [Strings](#7-strings)
8. [Tests](#8-tests)
9. [Slices and the gate](#9-slices-and-the-gate)
10. [How to run this](#10-how-to-run-this)
11. [Deferred and not planned](#11-deferred-and-not-planned)
12. [Risks](#12-risks)
13. [Docs to update when it ships](#13-docs-to-update-when-it-ships)

## 0. The ask and the reading

Three sentences from the owner, two features:

1. **"Reminded of birthdays before each one of them, x time before or x days
   before."** An alert on one event already fires for each of its
   occurrences: `AlertPlanner` walks a recurring event's days through
   `occursOnUtcDay`, two occurrences per alert, 30 days ahead
   (`lib/utils/alert_planner.dart:78-154`), and an offset is 1–59 minutes,
   1–23 hours or 1–30 days, plus a time of day on an all-day event
   (`lib/utils/alert_offset.dart:9-12`, `event_alert.dart:53-61`). What is
   missing is **the rule for all of them**: every birthday carries its own
   alert rows, and a new one starts with none unless the owner set a default
   in Calendar settings — which applies to every event alike. The reading:
   **category alerts** — an alert attached to a category applies to every
   event in that category, the ones that exist and the ones to come.
2. **"A notification every month: there will be x birthdays this month, like
   Facebook; configurable so custom events are bundled in a single
   notification."** A **digest**: a scheduled, bundled notification on a
   cadence (monthly, weekly, daily) over a span, scoped by a category
   allowlist, its lines the span's entries, its tap the overview on that span.
3. **"Set recurring jobs."** Read as the digests' cadence, which is what the
   owner described. A background re-plan that runs without the app being
   opened is a different thing; §11 weighs it and D21 leaves it out of this
   record.

"Perfect, even native" means here: Android's own inbox-style notification on
a channel of its own, every word written at arm time on the UI isolate as
every alert's is, late delivery handled as a reminder's, the tap a deep link
into the overview, both new tables synced and backed up, every surface on
the UI language with its robot and its suite.

## 1. What exists today (facts, 2026-10-15)

- **Alert model**: `EventAlert {id, eventId, mode: notify|ring, offsetMinutes,
  daysBefore, dayMinute?, sound?, enabled}` (`lib/models/event_alert.dart:46-77`);
  `describe` is the one formatter (`:161`); `kMaxAlertsPerEvent = 5`
  (`lib/constants/event_alerts.dart:21`); `kDefaultAlertDayMinute = 540`
  (`:12`). Presets: timed `[0, 5, 10, 15, 30, 60, 1440]` min, all-day
  `[0, 1, 7]` days (`alert_editor_sheet.dart:189-200`); the Custom sub-sheet
  steps a number in a unit, days up to 30 (`alert_offset.dart:9-12`).
- **Facade** `EventAlerts`: `alertsFor(eventId)` `:104`, `hasAlarm(eventId)`
  `:109`, `hasReminder(eventId)` `:113`, `revision`, `configureDefaultDayMinute`
  `:72`. Read synchronously by `EventAlertBadges`
  (`lib/widgets/event_alert_badge.dart:37-38`, used by `day_summary_panel.dart:290`
  and `agenda_list_view.dart:1246`), the editor's seed
  (`event_editor_sheet.dart:694-696`), the detail sheet (`:263`) and the hub
  toggle (`calendar_bloc.dart:1082`).
- **Planner**: `AlertPlanner.plan({events, alertsByEvent, defaults, horizon,
  now})` (`alert_planner.dart:78-84`), pure; `PlannedFire {event, alert, day,
  fireAt, kind, sound}` (`:18-45`); `fireInstant` (`:206-211`); only enabled
  alerts (`:93-96`); `candidateDaysIn` prunes the walk (`:168-187`); sort and
  `sublist(0, horizon.total)` (`:143-154`). `kAlertHorizon = (perAlert 2,
  days 30, total 48)` (`alert_constants.dart:33-37`).
- **Scheduler** `_reconcile` (`alert_scheduler.dart:830-1055`): resolves the
  services quietly (`:845-853`), sweeps (`:866`), applies moves (`:873`),
  `refreshArmContext` (`:888`), builds `alertsByEvent` from
  `EventAlerts.alertsFor` (`:890-896`), `_settlePastFires` (`:898`, body
  `:1230`), the OS-truth pass when `tracksPending` (`:914-922`), plans
  (`:924-930`), `_assignOsIds` (`:940`; an existing registration is matched by
  **(alert, day, kind)** — `:1292-1308`), then per entry: the signature
  (`alertArmSignature` `:83-92`: a notify fire returns the bare context, a ring
  fire adds sound, clock token, snooze, notice lead), skip-if-unchanged,
  `_gateway.schedule(fire, payload, noticeAt:)`, `_dao.put(...)`
  (`:948-1034`); cancels live rows not desired (`:1041+`).
- **Settle rules for a row past its instant** (`:1230-1300`): under grace or
  while anything rings → in flight; process alive at the instant → `fired`;
  ≥ 24 h late → `cancelled` + OS cancel; no event, no alert, or
  **a notify-mode alert → `cancelled`, no notice**; a ring → `missed` +
  `showMissed`.
- **Registry** `alert_registrations(os_id PK, alert_id, event_id, day,
  fire_at, kind 'scheduled'|'snooze', state, backend, created_at, updated_at)`
  (`database_migrations.dart:1620-1633`), device-local, hard deletes; DAO
  `put/pending/firedOsIds/byOsId/forEvent/markState/recent/sweep/deleteForEvent`
  (`alert_registration_dao.dart:27-139`); `os_id = fnv1a32("$db|$alertId|$dayIso|$kind")`
  masked, probed (`alert_constants.dart:130-138`).
- **Gateway** interface `AlertGateway` (`alert_gateway.dart:104-325`): `schedule`
  `:213`, `cancel` `:226`, `pendingEntries` `:233`, `showMissed` `:245`,
  `labels` `:201`, `launchIntent` `:290`, the session chip `:313-323`; the no-op
  binding `:330-370`. Android (`android_alert_gateway.dart`): channels
  `alerts_reminder` (high), `alerts_quiet` (low, no sound), `alerts_alarm_v2`
  (max) created at `:1124-1160` with localized names; the reminder's details
  `alertReminderDetails` `:530-552` (`BigTextStyleInformation`, actions, the
  group key with no summary on Android 16+ — `_reminderGroup` `:515-519`,
  `_groupsReminders` `:1981-1992`, `kAlertGroupKey = 'anta.alerts'`
  `alert_constants.dart:254`); `_scheduleNotification` `:1994-2055`
  (`zonedSchedule`, `exactAllowWhileIdle`); `_handleResponse` `:1576-1620`
  decodes the payload and enqueues an `AlertIntent`
  (`pending_navigation.dart:9-126`: `OpenEventIntent`, `OpenAlarmIntent`,
  `SkipNextFireIntent`, `OpenSessionIntent`, `OpenAlertsHubIntent`,
  `QuickAlarmIntent`). Words only from `alertNotificationContent`
  (`alert_notification_content.dart:88-95`, kinds `:5-28`); times only from
  `AlertLabels` (`alert_labels.dart:25-162`).
- **Payload** `AlertPayload` (`alert_payload.dart:65-191`): `database, eventId,
  alertId, dayUtcMs, osId, mode, title, timeLabel, colorValue, tintIcon,
  iconKey, categoryId, removeAfterAlert, snooze, snoozeMinutes, excerpt,
  notice, fireAtMs, reRing, whenLabel, tintValue, glyphKey, languageCode,
  iconFile, grouped`; a new fact is an optional field.
- **Categories**: `calendar_categories(id, name, color_value, icon_key,
  sort_order, is_built_in, is_hidden, created_at, updated_at)` — **no CRDT
  block** (`calendar_categories_table.dart:15-38`); `CalendarCategory`
  (`calendar_category.dart:16-54`); `CategoryService` `create :196,
  updateCategory :259, reorder :287, setHidden :309, deleteCategory :327,
  exportData :341, importData :375`; built-in `birthday` seeded with `cake`
  (`calendar_categories.dart:62`), `kBirthdayCategoryId`
  (`calendar_event.dart:28`); the editor pre-fills yearly + counting for it
  (`event_editor_sheet.dart:1487-1496`). The category editor sheet has one
  group of three rows — name, icon, colour (`category_editor_sheet.dart:284-353`)
  — and saves through the service directly (`:200-237`). The alerts roadmap
  deferred "a per-category default alert" because categories have no CRDT
  (`docs/event-alerts-roadmap.md` §12).
- **Hub** `AlertsPage` (`alerts_page.dart`): loads `AlertScheduler.hubEntriesOrEmpty`
  + `recentEntriesOrEmpty` (`:119-123`), reloads on `registryRevision` (`:93`)
  and every bloc state (`:200`), builds under `CalendarPageLoaded` (`:203`);
  body `:226-339`: banners, empty state, rows grouped by fire day (`:272-280`,
  `_AlertHubRow :383`, switch `:534`), Recent (`:297`, `_AlertHistoryRow :547`).
  Still Card/InkWell on `AppSpacing` — Tier 4 of the language adoption, not
  started (`docs/calendar-language-adoption-roadmap.md:518-530`). Rule: owns no
  data, writes only via `CalendarBloc` (`ToggleEventAlert :1076`,
  `DeleteCalendarEvent`), never an alert-creation affordance.
- **Overview**: `OverviewPeriod` kinds year · rolling · custom
  (`overview_period.dart:29-250`; a custom span is a look, never persisted —
  `encode :194`); `OverviewView {id, name, period, options, categoryIds,
  sortOrder}` (`overview_view.dart:16-45`) on `overview_views` v41
  (`database_migrations.dart:1659-1675`, DDL frozen, CRDT block);
  `_applyView` (`calendar_overview_page.dart:2037-2068`) switches to List,
  sets `_period = _home`, `_categoryIds`, persists mode, period, options,
  categories (`setCalendarOverviewCategories :2073`). No seam opens the
  overview on a given period: `toCalendarOverview` (`app_navigator.dart:559`)
  takes nothing; `pendingCalendarOccurrence` (`:461-462`) serves the calendar
  only (`calendar_page.dart:412-415, 593-603`).
- **Occurrences in a span**: `EventAgenda.occurrencesInRange({events, from,
  to, hiddenCategoryIds, priorities, query, categoryLabels, labelTextOf,
  eventType, categoryIds, collapseRecurring, hideMissed})` →
  `List<EventOccurrence {event, day, occurrenceCountInWindow}>`
  (`event_agenda.dart:18, 265-278`); `categorySummariesOf` `:641`
  (`eventCount` "the number worth leading a digest with", `:54-57`);
  `compareWithinDay` `:957`; `maxRangeDays = 366` `:240`.
- **Backup**: export `'eventAlerts'` `:159`, `'overviewViews'` `:172`
  (`backup_service.dart`); import: `overviewViews` absent → untouched
  (`:482-487`); `eventAlerts` absent beside `calendarEvents` → cleared
  (`:563-571`); then `reconcileAll(backupRestored)` (`:585`).
- **Templates** carry no alerts (`event_template.dart:15-45`); the quick alarm
  mints one event + one alert (`quick_alarm.dart:107-126`).
- **Dependencies**: the `alarm` fork, `flutter_local_notifications ^22.3.1`,
  `timezone`, `flutter_timezone` (`pubspec.yaml:84-88`); no `workmanager`, no
  `android_alarm_manager_plus`; the boot receiver re-registers the plugin's
  own entries (`AndroidManifest.xml:92-97`).
- **Android 16 bundling** (`docs/alert-surfaces-redesign-roadmap.md` §3.7):
  two loose notifications in a section are bundled ~200 ms after the second
  and every child goes silent; a group key with no summary is not bundled at
  post, so the child sounds and peeks; an app summary would stay behind as a
  row; notifications under a minute apart are attenuated.
- **Plural precedent**: `eventAlertDaysBefore` en/de/ro with the Romanian
  `few` form (`app_en.arb:3645`, `app_de.arb:1938`, `app_ro.arb:864`);
  `categoryEventCount` with `=0`.

## 2. Decisions

The recommended option is listed first; "A" answers it. Decisions a later
line calls a rule (D4, D9, D16, D22) are stated here so they are agreed once.

| Id | Question | Proposed (A) | Alternatives | Why |
| --- | --- | --- | --- | --- |
| D1 | Vocabulary | **Category alerts** — "Alerts" group in the category editor; on an event "From Birthdays". **Digests** — en *Digest / Digests*, de *Zusammenfassung / -en*, ro *Rezumat / Rezumate*; code `EventDigest`, `DigestCadence`. | B: en "Summary"; C: en "Round-up" | "Alerts" is the owner's word (A1 of the alerts roadmap); "Digest" is what every mail client calls a bundled periodic notice and keeps "Summary"/"Overview" free — the overview page and the day summary panel already own those words. |
| D2 | How a category alert reaches an event | **Evaluated, never copied**: the planner, the badges, the detail sheet and the hub read `EventAlerts.effectiveFor(event)` = the event's own alerts + the category's, at read time. Nothing is written onto the event. | B: materialize rows into `calendar_event_alerts` per event with a deterministic id (`uuid5(categoryAlertId, eventId)`) and keep them in step on every membership change | B has a long tail — events moving category, `deleteCategory` reassigning, `.ics` and backup imports, templates, sync — and each miss is "my birthday reminder did not fire". A is how recurrence already works: computed from current data, consistent by construction. |
| D3 | Per-event opt-out | **Yes**: `calendar_events.category_alerts` (bool, default on), a `FormSwitchRow` "Category alerts" in the editor's Alerts group, shown only when the category has at least one alert. Off drops every inherited alert for that event. | B: no opt-out (move the event to another category) | One birthday the owner does not want reminders for should not need a second category. One additive column, one switch. |
| D4 | Dedupe | An inherited alert that would fire at the same instant as one of the event's own is dropped; the event's own wins (its id, its sound). The key is **the offset set the event uses** (S1 review #2, 2026-10-15): a timed event compares `(mode, offsetMinutes)`, an all-day one `(mode, daysBefore, dayMinute ?? defaultDayMinute)` — both sets are always stored (§2.1 of the alerts roadmap) and the unused one says nothing. | — | Two fires at the same instant for one occurrence is a defect, not a feature. |
| D5 | The hub switch on an inherited fire's row | **Toggles the event's `category_alerts` flag** (the D3 switch), the row captioned "From {category}". An opted-out event keeps its inherited rows in the hub with the switch off — `hubEntries()` imagines them as it imagines disabled own alerts — so the hub is never a one-way switch (S3 review #2). | B: toggles the category alert's `enabled` for every event in the category; C: no switch on inherited rows | In the hub the owner looks at *this* occurrence; B silently silences thirty other birthdays. The category's own master switch is the row's `enabled` **switch in the category editor** (S3 fix pass: the trailing control of each category alert row; removal through the alert sheet's Remove); a paused category alert is skipped by the hub and invisible on its events. |
| D6 | Caps | `kMaxAlertsPerCategory = 5` (the event cap, `kMaxAlertsPerEvent`); effective ≤ 10 per event; the 2 / 30 / 48 horizon unchanged. | — | Google's cap per calendar; the horizon's `total` already bounds the work. |
| D7 | Category alerts and the settings defaults | A category alert is **not** a pre-fill: a new event in Birthdays shows the inherited rows and still gets the Calendar-settings default as its own first alert, if one is set. | B: suppress the settings default when the category has alerts | D2's model — the inherited rows are visible from the first frame, so a duplicate default is obvious and D4 collapses an identical one. |
| D8 | Digest fields | `EventDigest {id, name ('' = derived), cadence daily/weekly/monthly, anchor (weekly: ISO weekday 1–7; monthly: 1–28; daily: 0), minute, leadDays 0/1, categoryIds (empty = every category, as the overview lists them — archived included), includeEmpty, enabled, sortOrder}`; notify tier only. | B: also an alarm-tier digest | A ringing list is not a thing anyone wants at 09:00; the model keeps `mode` out so nothing needs to be migrated if that changes. |
| D9 | The span a digest covers | Starts on `fireDay + leadDays`, lasts one unit: a day; 7 days; from that day-of-month to the day before the same day next month. So "monthly on the 1st" is the calendar month, "weekly on Monday" the calendar week, "weekly on Sunday evening, from the next day" the week ahead. | B: always the calendar unit containing the fire day | B makes "monthly on the 25th" a digest of a month mostly gone. Anchor ≤ 28 keeps every month valid. |
| D10 | Content | Title: the digest's name, else the allowlist's label (one category → its label; none → "Events"; several → "3 categories"). Text: "{count} events {period}" (plural) then the first lines inline. Expanded (InboxStyle): up to 5 lines "{Sat 4 Oct} · {Ana}", then "+N more" as the summary; a line of an event that counts occurrences appends its count label ("30th") through `RecurrenceFormatter.countLabel`. Every occurrence in the span is a line (the overview's every-occurrence rows), sorted by day then `compareWithinDay`. | B: `BigTextStyle` with one paragraph; C: lines without the count | InboxStyle is the native shape for "a list in a notification"; the count is what makes "Ana · 30th" a birthday line and costs one call to the one count formatter. |
| D11 | An empty span | Not armed, unless **Also when empty** is on — then the title over "No events this month" (the `=0` form), no lines. | B: always armed | "No birthdays this month" is noise for most digests and reassurance for some; a switch, off by default. |
| D12 | Channel | A fourth channel **`alerts_digest`, importance default** (sound, no heads-up), localized name "Digests", created beside the three; a digest carries `kAlertGroupKey` on Android 16+ like a reminder, never a summary. | B: importance high (heads-up); C: post on `alerts_reminder` | A morning digest should sound and sit in the shade, not interrupt; the owner can raise the channel in system settings. Importance is frozen at creation, so the id is chosen once. |
| D13 | What a tap opens | The overview in **List mode on the span with the digest's allowlist**: the allowlist and the mode persist as picks, **the period is a look that writes nothing** — the look path skips `_persistPeriod` (S2 review #3: `encode` returns null for a custom span and the setter then *deletes* the stored key, so "a look" through `_applyView`'s path lost a saved "Last 90 days"); a look also clears the live search query and the session-only Missed only, and keeps Order and Rows as the owner set them (S2 review #7). | B: the calendar on the span's first day; C: a look that persists nothing | The digest *is* an overview query; landing on the same list the hub's row names is the "native" tap. |
| D14 | Where digests live | **The Alerts hub**: a "Digests" group at the top on the UI language (`FormRowGroup`, a `FormPickerRow` per digest with a switch, `FormActionRow` "Add digest"), the digest fires among the day-grouped rows, deliveries under Recent. The hub rule gains "…never an *event-alert*-creation affordance; digests are created here, they have no other owner." | B: Calendar settings → a Digests page; C: a bar button on the overview | The hub is "what the phone will say and when"; a digest is exactly that. B hides a daily-use list under settings; C ties digests to one page's state. |
| D15 | Digest horizon | `kDigestHorizon = (perDigest: 2, maxDigests: 10)`: the next two fires of each digest whatever their distance, outside the alerts' 48; `maxDigests` is a product cap on the plan (the service refuses past it, the planner takes the first ten enabled in order). | B: one fire each; C: inside the 48 | Two fires survive a month without the app. *Corrected 2026-10-15 (S1 review #5):* 48 + 20 is not under iOS's 64; the alerts' notices already exceed it on their own, so the later Darwin binding owns a rolling window of its own (alerts roadmap §6.2) — nothing here promises to fit. |
| D16 | A digest row past its instant | **`fired`, in every band** (S2 review #8, 2026-10-15): the notification plugin delivers at the instant whether or not the app runs, so the row is settled as delivered — never `cancelled`, never an OS cancel (which would pull a digest the owner keeps in the shade), never `missed`, never a notice, never a snooze. (Before the review: "settled like a notify-mode alert's", whose 24 h branch cancels the OS entry.) | — | The OS delivers a late `zonedSchedule` itself; a Missed notice for information already shown is noise, and a cancel is data vanishing. |
| D17 | Persistence | Schema **v42**: `calendar_category_alerts` (the v40 alert row shape keyed by `category_id`, the v29 CRDT block), `event_digests` (the `overview_views` shape + `enabled`), `calendar_events.category_alerts` (guarded, default 1), `alert_registrations.source` (guarded, default `'event'`). Backup keys `categoryAlerts` and `eventDigests`; the event's flag rides in its JSON, absent → on; backup version stays 7. *Corrected 2026-10-15 (S1 review #1):* `categoryAlerts` follows **`eventTemplates`' rule** (`backup_service.dart:469-481`), the category-keyed twin — present → imported, absent beside `calendarCategories` → **cleared** (the import wipes and replaces the categories, so alerts keyed to the old custom ids would orphan and the device's built-in-category alerts would silently apply to the restored events), absent with no categories → untouched; `eventDigests` keeps `overviewViews`' rule (absent → untouched). The twins' import is a wipe-and-reinsert, not a merge. | B: a `default_alerts` JSON column on `calendar_categories` | B has no CRDT and would not sync; a table with its own block references categories by their stable ids, built-ins included — the reason §12 of the alerts roadmap deferred this falls away. |
| D18 | `.ics` and export | Effective alerts export as `VALARM` on the event (an inherited one like an own one); digests have no `.ics` form. | B: own alerts only | A consumer of the export expects the alarms the phone will ring. |
| D19 | Categories page | A bell glyph on a category's row when it has an enabled alert; the picker untouched. | B: nothing | One glance answers "which categories remind me"; cheap. |
| D20 | Tiers and sound | A category alert may be an Alarm with a sound (the same `AlertEditorSheet`, `showSound: true`); the remove-after switch stays the one-time event's own, never inherited. | B: reminders only | "x time before" for a timed training category is a plausible alarm; the sheet exists. |
| D21 | A background re-plan job | **Not in this record.** The horizon's gap (a phone not opened for 30 days misses alerts beyond it) exists today for every alert and is unchanged; the second digest fire covers two months. A `workmanager` daily `reconcileAll` means a headless isolate opening the database, against the rule that no scheduling pass runs outside the UI isolate; its own record if wanted. | B: `workmanager` periodic now | §11 has the costs; the owner opens the app daily. |
| D22 | Reconcile triggers | Category alerts saved or removed, a digest saved, toggled or deleted, `deleteCategory` (which tombstones the category's alerts) → `reconcileAll`; an event's category or opt-out change → `reconcileEvent` as any update. | — | A category alert touches many events; a full plan is what the scheduler does anyway (`reconcileEvent` is a full re-plan with one forced refresh). |
| D23 | How it is built | Opus 5.5 implementation sessions; one `implementer` and one `reviewer` per slice (§9); `qa-runner` for the pass; `docs-writer` for placement; no workflow; the owner commits after each slice. | B: one session, no reviewer | The budget rules; §10. |

## 3. Domain model

### 3.1 `CategoryAlert` (`lib/models/category_alert.dart`)

```
CategoryAlert(
  id: String,            // uuid v4
  categoryId: String,    // a calendar_categories id, built-ins included
  mode: AlertMode,
  offsetMinutes: int,    // timed events in the category
  daysBefore: int,       // all-day events in the category
  dayMinute: int?,       // null = the settings default (EventAlerts.defaultDayMinute)
  sound: String?,        // Alarm tier only, the EventAlert meanings
  enabled: bool,
)
```

The `EventAlert` row shape minus `eventId`: both offset sets are stored and
the planner picks by the event's `time == null`, exactly as §2.1 of the
alerts roadmap has it, so one category alert serves a category that mixes
timed and all-day events. `Equatable`, `copyWith` with `clearSound` /
`clearDayMinute`, the same `_nonNegative` / `_clampMinute` decode.
`CategoryAlert.toEventAlert(eventId)` projects it onto an event:
`EventAlert(id: this.id, eventId: eventId, …, categoryId: this.categoryId)`.

### 3.2 `EventAlert.categoryId` — the one model change

`EventAlert` gains `String? categoryId`, **in memory only**: null on the
event's own alerts, the category's id on a projected one. The DAO never
writes it; `copyWith` passes it through; `describe` ignores it; `Equatable`
props include it. Everything downstream — `PlannedFire.alert`,
`AlertHubEntry.alert`, the payload's `alertId`, the editor's rows — stays on
`EventAlert`, and reads `alert.categoryId != null` where the source matters
(the registry's `source`, the id seed, the "From {category}" caption, the hub
switch's meaning).

### 3.3 Effective alerts — the facade (`lib/constants/event_alerts.dart`)

```
EventAlerts.alertsFor(eventId)            // unchanged: the event's own rows
EventAlerts.categoryAlertsFor(categoryId) // unmodifiable, O(1)
EventAlerts.effectiveFor(event)           // own ∪ inherited, deduped (D4)
EventAlerts.hasAlarm(event) / hasReminder(event)   // over effectiveFor (signature: the event)
EventAlerts.revision                      // bumps on category-alert writes too
```

`effectiveFor(event)`:
`own + (event.categoryAlerts ? categoryAlertsFor(categoryOf(event)) : [])`
minus every inherited alert that would fire at the same instant as an own
one (D4: the offset set the event uses, `dayMinute` null read as the
default); disabled rows on either side stay in the list (the planner and
the badges already filter on `enabled`); the inherited tail keeps the
category's order. `categoryOf(event)` is `CalendarCategories.resolve(
event.categoryId).id` — the rendering rule, unknown → `other` (S1 review
#3): an event drawn as Other inherits Other's alerts, whether its id went
stale through a `deleteCategory` reassignment the event cache has not
re-read yet or through a restore that lacked the category. `hasAlarm` /
`hasReminder` take the event because the answer needs its category and its
flag; the badge calls `effectiveFor` once per build and derives both flags
and both tooltips from that list (`event_alert_badge.dart`).

`EventAlertService` owns both tables (the `EventSkipService` shape it already
has): `categoryAlertsFor`, `replaceForCategory(categoryId, alerts)` (one
transaction: tombstone missing, upsert present), `tombstoneForCategory`,
`exportCategoryAlerts` / `importCategoryAlerts` / `clearCategoryAlertsForImport`;
every write republishes the facade and bumps `revision`.

### 3.4 `EventDigest` (`lib/models/event_digest.dart`)

```
EventDigest(
  id: String,
  name: String,                 // '' = derived (§3.6)
  cadence: DigestCadence,       // daily | weekly | monthly; fromName, unknown → monthly
  anchor: int,                  // weekly 1..7 (DateTime.monday..sunday), monthly 1..28, daily 0; clamped
  minute: int,                  // 0..1439, clamped
  leadDays: int,                // 0 | 1 in the sheet; stored 0..7, clamped
  categoryIds: Set<String>,     // empty = every category, as the overview lists them
  includeEmpty: bool,
  enabled: bool,
  sortOrder: int,
)
```

Stored as `overview_views` stores a view: one `payload` JSON through one
codec (`OverviewView`'s `_kind*` style, forward-compatible), `name`,
`enabled` and `sort_order` as columns (§4). **An unreadable or empty
payload, or a cadence this version does not know, decodes to a digest
that is `enabled = false` whatever the row's flag says** (S1 review #8): a
later version's digest kind must never fire monthly on an older app —
nothing arms what nobody configured; the hub shows the row off and a
re-save from the sheet makes it this version's. `EventDigest.derivedTitle(l10n,
categories)` and `describe(l10n)` ("Monthly on the 1st, 09:00 ·
Birthdays") are the two formatters, used by the hub row, the sheet's caption
and the notification alike — the `EventAlert.describe` rule.

`EventDigestService` is `OverviewViewService` verbatim (`getInstance` /
`forTesting` / `reset` / `reload`, `create`, `update`, `delete` soft,
`reorder`, `exportData` / `importData`, `isFull` at `kDigestHorizon.maxDigests`),
registered with `DatabaseLifecycle`; a facade `EventDigests.all` read by the
hub under `CalendarPageLoaded`.

### 3.5 Fire instants and the span (`lib/utils/digest_planner.dart`)

Pure, `now` injected, the alert planner's twin:

```
DigestPlanner.plan({digests, events, horizon, now})   // the allowlist alone; never hiddenCategoryIds
  → List<PlannedDigest {digest, fireAt (local), spanStart, spanEnd (date-only UTC, inclusive),
                        entries: List<EventOccurrence>}>
```

- Candidate fire days from `today` (date-only UTC of `now`): daily — every
  day; weekly — days whose `weekday == anchor`; monthly — days whose `day ==
  anchor`. Walk forward until `horizon.perDigest` instants strictly after
  `now` are found (at most two months for monthly).
- `fireAt = DateTime(y, m, d, 0, minute)` — the wall-clock constructor, never
  `midnight.add` (the DST rule, alerts roadmap §2.4, memory
  `dart-local-midnight-add-dst-trap`).
- `spanStart = fireDay + leadDays` (date-only UTC arithmetic);
  `spanEnd`: daily `spanStart`; weekly `spanStart + 6`; monthly
  `DateTime.utc(y, m + 1, d) − 1 day` from `spanStart`.
- `entries = EventAgenda.occurrencesInRange(events: events, from: spanStart,
  to: spanEnd, categoryIds: digest.categoryIds, eventType:
  AgendaEventType.all, collapseRecurring: false)` — the overview's own call
  (`calendar_overview_page.dart:845-850`): the allowlist alone, **no
  `hiddenCategoryIds`** (that set is the grid filter's denylist, which the
  overview ignores; an archived category's events still list and still
  digest), every occurrence a line, already sorted by day then
  `compareWithinDay`. A digest whose entries are empty and whose
  `includeEmpty` is off yields no `PlannedDigest`.
- Work budget: `occurrencesInRange` walks `candidateDaysIn` per event, so a
  yearly birthday costs one check per span; a test pins the count like the
  alert planner's "work budget" case.

### 3.6 Words — `digestNotificationContent` (`lib/utils/digest_notification_content.dart`)

A pure top-level function beside `alertNotificationContent`, called on the
UI isolate at arm time with `AlertLabels` for every day and time:

```
digestNotificationContent(PlannedDigest fire, AppLocalizations strings, AlertLabels labels,
                          {required String Function(String categoryId) categoryLabel})
  → DigestNotificationContent {title, text, lines (≤ kDigestMaxLines = 5), summary?}
```

- `title`: `digest.name`, else one allowlisted category → its label; none →
  `digestAllCategories` ("Events"); several → `digestCategoriesCount`.
- `period` phrase: `digestPeriodToday` / `Tomorrow` (daily, lead 0 / 1);
  `ThisWeek` / `NextWeek` when weekly and `spanStart.weekday` is **the app's
  week start** (`CalendarWeekStart`, `SettingsService.getCalendarWeekStart()`,
  default Monday — the calendar never reads the locale's first weekday, and
  neither does this; the planner takes `weekStart` as a parameter);
  `ThisMonth` / `NextMonth` when monthly and **`spanStart.day == 1`** (S2
  deviation 1: `anchor == 1` with lead 1 spans "2 Oct – 1 Nov", which is not
  next month — with `leadDays ≤ 7` "next" is always the following unit);
  otherwise `digestPeriodSpan(start, end)` ("from Nov 4 to Nov 10", S2 review
  #15) with the ends through `AlertLabels.spanLabel` / `DateFormat.MMMd`
  (`AlertLabels` had no range formatter, `alert_labels.dart:53` only `MMMEd`;
  `spanLabel` writes one day when start equals end).
- `text`: `digestCountPeriod(count, period)` ("3 events this month"), then
  " · " and the entries inline as `{date} · {title}` with the date **without
  the weekday** (`AlertLabels.entryDateLabel`, `MMMd` — English day labels
  carry commas, so the inline list is joined by ", " on dates alone), the OS
  cutting the collapsed row.
- `lines`: `alertsDayThenWhen`'s grammar, `{day} · {title}` with
  `AlertLabels.entryDayLabel(day)` ("Sat 4 Oct", `DateFormat.MMMEd` as
  `_dayOf` already does); when `event.countOccurrences`, ` · {countLabel}`
  through `RecurrenceFormatter.countLabel(event, day, l10n)`
  (`recurrence_formatter.dart:48`), the one count entry point — it writes
  what the rows write ("Year 30", "Day 12"), never an ordinal; the mock's
  "30th" is that label. Beyond five: `summary = digestMoreCount(count − 5)`.
- Empty (D11): `text = digestCountPeriod(0, period)` (the `=0` form), no lines.

### 3.7 Registry identity and os ids

- A registration's identity is **(alert_id, event_id, day, kind)**.
  `_assignOsIds` (`alert_scheduler.dart:1292-1308`) matches on the tuple; an
  event alert's `event_id` was always filled, so every existing row still
  matches its own entry and nothing is re-armed by the upgrade.
- The hash seed: event-sourced **unchanged**, `"$db|$alertId|$dayIso|$kind"`
  (standing entries and standing snoozes keep their ids); category-sourced
  `"$db|$alertId|$eventId|$dayIso|$kind"`; a digest
  `"$db|$digestId|$spanStartIso|digest"`. The probe and the mask are the
  same.
- `source TEXT NOT NULL DEFAULT 'event'` (`event | category | digest`),
  `kind` gains `digest`; a digest row has `alert_id = digestId`,
  `event_id = ''` (the global-counter convention), `day = spanStart`,
  `backend` = the signature.
- The signature of a digest entry: `'$context~d#' + fnv1a32(digestId | title
  | text | lines | summary | tint | glyph | allowlist | spanStart | spanEnd)`
  in hex (`digestArmSignature`; the context already carries
  `kAlertArmGrammarToken`) — content frozen at arm time reaches a standing
  entry only through its signature, so an event added to the month re-arms
  the digest on the next pass, and so does a category added to the allowlist
  with nothing in the span (S2 review #6: the platform entry's `cat=` would
  otherwise stay stale and the tap would open the old set);
  `kAlertArmGrammarToken` still moves when the digest's *grammar* changes
  (one token for every entry, as the rule says).
- A category-sourced fire's payload carries **`inherited`** (JSON `inh`,
  written only when true; `_payload` from `alert.categoryId != null`,
  `_payloadForRow` from the row's `source`): the payload alone cannot tell
  an inherited alert from an own one (`categoryId` is the event's category),
  and both snooze paths need to — the background re-post seeds with the
  event when `inherited` (S2 review #2: two inherited reminders snoozed from
  the shade on one day otherwise land on one id) and
  `cancelSnoozeForAlert(alertId, eventId, day)` matches the event too (S2
  review #1: one event's Stop otherwise cancels another event's snooze of the
  same category alert). Event-sourced seeds and matches are unchanged.

### 3.8 Rules carried over unchanged

A skipped occurrence, a deleted event, a disabled alert and an occurrence
past `endDate` never ring — inherited or not (`occursOnUtcDay` is the one
filter, §2.6 of the alerts roadmap). Presence never matters. The quick
alarm's event is `other`: an `other` category alert applies to it like to any
event in `other` — expected, and the hub shows it. A hidden (archived)
category's events still occur, so its alerts still fire; archiving hides
from pickers, not from time.

## 4. Persistence — schema v42

DDL frozen for the migration (`_migrateV41ToV42`; `DatabaseSchema.currentVersion
= 42`, `v42CategoryAlertsAndDigests`), after the v41 step at
`database_migrations.dart:211`:

```sql
CREATE TABLE IF NOT EXISTS calendar_category_alerts (
  id             TEXT    NOT NULL PRIMARY KEY,
  category_id    TEXT    NOT NULL,
  mode           TEXT    NOT NULL DEFAULT 'notify',
  offset_minutes INTEGER NOT NULL DEFAULT 0,
  days_before    INTEGER NOT NULL DEFAULT 0,
  day_minute     INTEGER NULL,
  sound          TEXT    NULL,
  enabled        INTEGER NOT NULL DEFAULT 1,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL,
  hlc_timestamp  TEXT    NOT NULL,
  device_id      TEXT    NOT NULL,
  version        INTEGER NOT NULL DEFAULT 1,
  is_deleted     INTEGER NOT NULL DEFAULT 0,
  deleted_at     INTEGER NULL
);
CREATE INDEX IF NOT EXISTS idx_calendar_category_alerts_category
  ON calendar_category_alerts(category_id);

CREATE TABLE IF NOT EXISTS event_digests (
  id            TEXT    NOT NULL PRIMARY KEY,
  name          TEXT    NOT NULL DEFAULT '',
  payload       TEXT    NOT NULL,
  enabled       INTEGER NOT NULL DEFAULT 1,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  hlc_timestamp TEXT    NOT NULL,
  device_id     TEXT    NOT NULL,
  version       INTEGER NOT NULL DEFAULT 1,
  is_deleted    INTEGER NOT NULL DEFAULT 0,
  deleted_at    INTEGER NULL
);

-- both behind the PRAGMA table_info guard of the v40 step (:1635-1645)
ALTER TABLE calendar_events     ADD COLUMN category_alerts INTEGER NOT NULL DEFAULT 1;
ALTER TABLE alert_registrations ADD COLUMN source          TEXT    NOT NULL DEFAULT 'event';
```

- Drift tables `calendar_category_alerts_table.dart`, `event_digests_table.dart`;
  the two columns on their tables; `build_runner`. The index goes in the
  creator whose tables exist when it runs (`createAlertIndexes` runs in the
  v40 step at `:1647`, so the v42 step calls its own creator, listed in
  `createAllIndexes` as well). No backfill: `category_alerts = 1` is what
  every existing event already meant.
- DAOs: `CategoryAlertDao` (the `EventAlertDao` shape: HLC / device / version
  stamps, soft delete, `replaceForCategory` in one transaction,
  `tombstoneForCategory`, `getAllActive`); `EventDigestDao` (the
  `OverviewViewDao` shape); `AlertRegistrationDao.put` writes `source`,
  `pending` reads it.
- `CalendarEvent.categoryAlerts` (bool, default true) → DAO mapping →
  `copyWith` → the editor switch → backup JSON (`categoryAlerts`, absent → true)
  → `.ics` untouched (the flag changes which `VALARM`s are written, not the
  grammar).
- Backup: `BackupService` exports `'categoryAlerts'` beside `'eventAlerts'`
  and `'eventDigests'` beside `'overviewViews'`; import: `categoryAlerts`
  present → imported (a wipe-and-reinsert, as the twins do), absent beside
  `calendarCategories` → cleared, absent with no categories → untouched
  (`eventTemplates`' rule, D17 as corrected); `eventDigests` present →
  imported, absent → untouched; categories still import before events,
  category alerts right after categories; then the existing
  `reconcileAll(backupRestored)`.
- `CalendarBloc._onLoad` awaits `EventDigestService.getInstance()` beside
  the eight calendar services in its one wrapped `Future.wait` (S1 review
  #4 — nine services from S1 on; the skill's rule line moves with it in
  S5), so `EventDigests.all` is published under `CalendarPageLoaded` for
  the hub; the scheduler resolves it quietly as well (S2).
- Sync: both tables carry the v29 block, so the calendar-sync phase
  (now `docs/cloud-sync-phase-02-own-space.md`) takes them as it takes
  `overview_views`; `alert_registrations` stays device-local.
- `DatabaseLifecycle`: `EventDigestService` registers as `OverviewViewService`
  does; `EventAlertService.reset` clears the category cache too.

## 5. Planner, scheduler, gateway

- **`AlertPlanner.plan` is unchanged.** The scheduler builds `alertsByEvent`
  from `EventAlerts.effectiveFor(event)` instead of `alertsFor(event.id)`
  (`alert_scheduler.dart:890-896`); the planner sees projected `EventAlert`s
  and plans them as it plans any. `PlannedFire.props` keeps `alert.id` — two
  events on one day with the same category alert differ by `event.id`, which
  the props already carry.
- **`DigestPlanner.plan`** runs after the alert plan (`:924-930`), over
  `EventDigests.all` and the same `events` (the allowlist alone, no hidden
  set); its result is assigned ids through the same `_assignOsIds` (the
  tuple of §3.7, over one `PlannedEntry` interface both `PlannedFire` and
  `PlannedDigest` satisfy; an unknown entry type is logged and skipped, never
  a throw mid-pass), signed (§3.7), and armed through
  `AlertGateway.scheduleDigest(PlannedDigest fire, AlertPayload payload)` —
  abstract, the no-op binding answering `true` as its `schedule` does
  (Darwin binds it in its own phase); the registry row is written as an alert's is. The
  OS-truth pass (`:914-922`) sees digest ids like any; the notice, the snooze
  and `showMissed` never apply (D16; `_settlePastFires` gains the explicit
  digest branch so Recent can list a delivery).
- **Payload**: optional fields `digestId`, `spanStartMs`, `spanEndMs`,
  `categoryIds` (CSV), `lines` (list), `summary`, `isDigest` (JSON `dg`,
  written only when true); `title` and `timeLabel` carry the title and the
  fire time as every payload does; absent → the old behaviour for good.
- **Android** (`AndroidAlertGateway`): the channel `alerts_digest`
  (`Importance.defaultImportance`, `alertsDigestChannel` / `…Desc`, created at
  `:1124-1160` with the others — the name rewritten from the current strings
  at every start, the id and importance frozen); `_scheduleDigest`:
  `zonedSchedule(id: osId, title, body: text, AndroidScheduleMode.exactAllowWhileIdle,
  AndroidNotificationDetails(kAlertDigestChannelId, …, importance default,
  category: AndroidNotificationCategory.event, icon: kAlertSmallIcon,
  largeIcon: the single category's avatar through the existing
  alertLargeIconFileName machinery, else none, styleInformation:
  InboxStyleInformation(lines, contentTitle: title, summaryText: summary),
  groupKey / groupAlertBehavior: the reminder's rule, actions: none))` —
  all of it in pure top-level functions beside the gateway
  (`alertDigestDetails(strings, content, decor, grouped)`), the words from
  `alertNotificationContent(AlertNotificationKind.digest, payload, strings)`
  which only places the payload's strings. `_handleResponse` (`:1576-1620`): a
  payload with `isDigest` enqueues `OpenOverviewIntent(payload)` (a new
  `AlertEntryIntent`); the cold-start path (`:2280-2283`) the same.
- **Navigation**: `main.dart`'s drain routes `OpenOverviewIntent` to
  `AppNavigator.toCalendarOverviewLook({required DateTime start, required
  DateTime end, required Set<String> categoryIds})`: it sets
  `pendingOverviewLook` (a `ValueNotifier`, the `pendingCalendarOccurrence`
  twin at `app_navigator.dart:461-462`) and collapses onto a live overview
  route, else pushes one (`toAlertsFromPlatform`'s shape, `:649`). The
  overview page listens as the calendar does (`calendar_page.dart:412-415`),
  consumes once (`:593-603`) and applies it like `_applyView`
  (`calendar_overview_page.dart:2037-2068`): List mode, `_period = _home =
  OverviewCustomPeriod(start, end)`, `_categoryIds = allowlist`, `_land()`,
  persist mode and categories, **never the period** (D13 as corrected: the
  look path skips `_persistPeriod`, which would delete the stored key), and
  clear the live query and the session-only Missed only first (the shared
  body is `_listLook`, which `_applyView` also uses — a view still persists
  its period as a pick). While a ring is in progress the drain routes only
  `OpenAlarmIntent`s — the overview intent waits in the queue (unchanged).
- **Reconcile triggers** (D22) are wired where the writes are: the category
  editor's save → `EventAlertService.replaceForCategory` →
  `AlertScheduler.reconcileAllQuietly(eventChanged)` (the Alarm-sound row's
  precedent, `calendar_settings_page.dart:926`); `CategoryService.deleteCategory`
  tombstones the category's alerts **inside its own transaction** through
  the DAO (the `deleteById` precedent), refreshes a live `EventAlertService`,
  and requests the reconcile `unawaited` **after** its serialize chain, never
  inside it (S1 review #6 — a category write must not wait behind a platform
  pass); that pass may read an event cache the page has not re-read yet, and
  the next pass heals it (every resume runs one). The hub's digest writes go through
  `CalendarBloc` (`SaveEventDigest(digest)`, `DeleteEventDigest(id)`,
  `ToggleEventDigest(id, enabled)` → `EventDigestService` →
  `reconcileAll`, then an emit with `occurrenceRevision + 1` as
  `_onToggleEventAlert` does at `:1105`, so the hub and the rows re-read).
  After a category-alert save the calendar's row badges must be current
  without a restart: the sheet's callers (`calendar_categories_page.dart:144,
  150`, `category_picker_sheet.dart:200`) dispatch a new
  `CategoryAlertsChanged` bloc event when a `CalendarBloc` is in scope (the
  same emit), and `EventAlerts.revision` carries the hub.

## 6. Surfaces

Every new row is a kit primitive (`ui-language`); every sheet is a
`FormSheetFrame` form sheet with the clearance-test entry and its robot.

### 6.1 Category editor — the Alerts group (`category_editor_sheet.dart`)

```
✕  Edit category                                   Save
───────────────────────────────────────────────────────
┌ FormRowGroup ──────────────────────────────────────┐
│ Birthdays                               Built-in   │  (as today)
│ ⌘ Icon                                   cake  ›   │
│ ■ ■ ■ ■ ■ ■ ■ ■                                    │
└────────────────────────────────────────────────────┘
ALERTS                                                   FormSectionLabel
┌ FormRowGroup ──────────────────────────────────────┐
│ 🔔 The day before, 09:00             Reminder  ✕   │  FormPickerRow, tap → AlertEditorSheet.show (edit)
│ 🔔 On the day, 09:00                 Reminder  ✕   │  trailingButton = remove, as the event editor's rows
│ + Add alert                                        │  FormActionRow, hidden at 5
└────────────────────────────────────────────────────┘
  Every event in this category gets these alerts.        caption (categoryAlertsHint)
```

**As built (S3, 2026-10-15):** each category alert is a **two-line row** —
title the all-day wording, caption "Timed events: {timed wording} · {tier}"
(both through `EventAlert.describe` on a preview event of each shape: a
category alert carries both offset sets and serves both shapes) — with a
trailing **enabled switch** (D5's master switch; a paused alert is skipped by
the hub and invisible on the events); tap edits in `AlertEditorSheet.show(
forCategory: true)`, which shows **two** When rows (`alertsDefaultTimed`,
`alertsDefaultAllDay` — the existing words), no remove-after, and the
sheet's own Remove row for removal. Save writes the category, then
`replaceForCategory` when the alerts were touched, then the shared
permission check (the first alert ever saved may need
`POST_NOTIFICATIONS` — S3 review #3) and `reconcileAllQuietly` unawaited,
and dispatches `CategoryAlertsChanged` itself; ✕ after a written row pops
the saved category (never a stray row behind a `null`). The sheet stays an
unguarded sub-sheet. The built-in name row stays read-only; the group shows
for built-ins and customs alike. Ids: `category-alert-<i>`,
`category-alert-switch-<i>`, `category-alert-add`; robot
`CategoryEditorRobot`; the alert sub-sheet is `AlertSheetRobot`.

### 6.2 Event editor — inherited rows and the switch (`event_editor_sheet.dart`)

```
ALERTS
┌ FormRowGroup ──────────────────────────────────────┐
│ 🔔 10 min before                       Reminder ✕  │  own (as today)
│ 🔔 The day before, 09:00 · From Birthdays          │  inherited: dim, onTap null, no ✕
│ + Add alert                                        │  counts own rows only
│ ⊘ Category alerts                              ⟷   │  FormSwitchRow, only when the category has alerts
│ ⌫ Remove after it rings                        ⟷   │  (as today)
└────────────────────────────────────────────────────┘
```

Inherited rows come from `EventAlerts.categoryAlertsFor(categoryOf(…))`
(the enabled ones; re-read when the category row changes, synchronously),
two-line and read-only, captioned `eventAlertFromCategory(label)` + the
tier; the Category alerts switch is **last in the group** (the mock's M4 · A,
not this sketch), and when it is off the inherited rows **stay and draw
disabled** — they never leave, nothing moves under the finger (S3 review
#6; the sketch above is superseded); the switch writes `categoryAlerts` on
the result's event (the dirty fingerprint includes it). An inherited alert
D4 would shadow is still listed (the owner sees the duplicate and may remove
the own one — D7). `_canSave` unchanged. Ids: `eventCategoryAlerts`,
`eventInheritedAlert(i)`.

### 6.3 Detail sheet, badges, categories page

- `EventDetailSheet._buildAlertRows` (`:704-736`) lists
  `EventAlerts.effectiveFor(event)`; an inherited row carries the "From
  {category}" caption; tap still opens the editor.
- `EventAlertBadges` reads `hasAlarm(event)` / `hasReminder(event)` — the
  day panel and the agenda rows show the bell for inherited alerts too.
- `CalendarCategoriesPage` rows: a trailing bell glyph when
  `categoryAlertsFor(id)` has an enabled row (D19), tooltip
  `categoryHasAlerts`.

### 6.4 The Alerts hub (`alerts_page.dart`)

```
Alerts
[ banners as today ]
DIGESTS                                                  FormSectionLabel
┌ FormRowGroup ──────────────────────────────────────┐
│ ▤ Birthdays                                    ⟷   │  FormPickerRow + switch (enabled); caption:
│   Monthly on the 1st, 09:00 · next Sat 1 Nov       │  describe + next fire; tap → DigestEditorSheet
│ ▤ This week                                    ⟷   │
│   Weekly on Monday, 08:00 · next Mon 20 Oct        │
│ + Add digest                                       │  FormActionRow, hidden at kDigestHorizon.maxDigests
└────────────────────────────────────────────────────┘
Mon 20 Oct
  08:00  This week                               ▤      digest fire row: caption "4 events this week"; tap → the sheet
  18:00  Leg day · 10 min before            🔔  ⟷      (as today)
Sat 1 Nov
  09:00  Birthdays                               ▤      "3 events this month"
  09:00  Ana · The day before · From Birthdays  🔔 ⟷   inherited: the switch is the event's flag (D5)
RECENT
  Wed 1 Oct  Birthdays · 2 events this month   Delivered
```

The Digests group is on the language from the first day (the hub itself is
Tier 4 of the adoption roadmap; its other rows stay as they are until then),
and the page's ground is `pageGround` so the group reads against it in the
light theme (the kit's page ground; the day rows keep their widgets). A
digest row is the kit's two-line picker row with a trailing switch
(`FormPickerSwitchRow`, promoted from the category editor's alert row in the
S4 fix pass — the one primitive this rework added); a switched-off digest
dims and drops its "next …" caption; a digest this version cannot read
shows "Saved by a newer version of the app" with its switch disabled, and
the toggle writes the `enabled` column alone — never the payload (S4 review
#1). A digest fire row is `_AlertHubRow`'s shape with the digest's glyph
(`Icons.summarize_rounded`) and no switch of its own (the group's switch is
the one control); it comes from `AlertScheduler.digestEntries()`
(`DigestHubEntry {digest, fireAt, spanStart, spanEnd, count}`), merged into
the day groups by `fireAt` (a digest first on a tie); its id carries the
fire instant (two fires, two ids). Recent lists a digest delivery through
`AlertHistoryEntry` with a nullable digest beside its nullable event, as
"Delivered · {describe}" — the registry holds no count, and the describe is
the digest's *current* settings (the sketch's "2 events this month" is
superseded). The page still owns no data: the group's writes are the three
bloc events of §5. Ids: `alertsDigestAdd`, `alertsDigestRow(id)`,
`alertsDigestSwitch(id)`, `alertsDigestFire(id, fireAt)`.

### 6.5 `DigestEditorSheet` (`lib/widgets/digest_editor_sheet.dart`)

```
✕  New digest                                      Save
───────────────────────────────────────────────────────
│ Name                                   Birthdays     │  FormTitleRow, optional; hint = the derived title
┌ FormRowGroup ──────────────────────────────────────┐
│ ◷ Categories                           Birthdays ›  │  FormPickerRow → CategoryPickerSheet.pickMulti (never collapses empty)
│ ↻ Every                                   Month ▾   │  FormMenuRow: Day · Week · Month
│ ▦ On                                    the 1st ▾   │  FormMenuRow: 1–28 (monthly) / the locale's weekdays (weekly); absent for daily
│ ◔ At                                      09:00 ›   │  FormPickerRow → TimePadSheet.pick
│ ⇥ Covers                        From that day ▾     │  FormMenuRow: From that day · From the next day
│ ◻ Also when empty                              ⟷   │  FormSwitchRow
└────────────────────────────────────────────────────┘
  Next: Sat 1 Nov, 09:00 · 3 events this month           caption from DigestPlanner on the draft (pure, now = DateTime.now() once)
  Delete digest                                          FormActionRow (existing only), the kit's destructive confirm
```

`FormSheetFrame`, `_leave()` with the discard dialog on a dirty draft,
`_blur()` before every modal, `!mounted` after awaits;
`DigestEditorSheet.show(context, {EventDigest? initial, required events,
required weekStart})` (the caption needs the bloc's events and the app's week
start; a sheet route sits outside the page's providers) →
`DigestEditorSaved(digest)` | `DigestEditorDeleted(id)` | `null` (also for
a clean edit — a no-op save never bumps a CRDT version). **The service owns
a new digest's id and position** (`create` mints both; the sheet hands back
`id = ''`). Weekday names from `intl`, never an ARB matrix; the week's order
from the app's `CalendarWeekStart`, never the locale (as §3.6). The caption
is the first `PlannedDigest` of the draft (the planner's own empty rule, so
the sheet and the hub agree; none within twelve fires → "Nothing to send
yet"), memoized on the draft, in a `FormCaptionSlot` whose candidates are
every phrase the locale can produce at its widest — the slot never changes
height. The name row is a plain title field (no preview avatar: the kit
reserves the title-row avatar for an event). Ids: `digestSheetClose/Save`,
`digestName`, `digestCategories`, `digestCadence`, `digestAnchor`,
`digestTime`, `digestLead`, `digestIncludeEmpty`, `digestDelete`. Robot:
`DigestSheetRobot` in `test/widgets/support/`.

### 6.6 The notification (Android)

```
▣ ANTA · Digests · 09:00
Birthdays
3 events this month · Sat 4 Oct · Ana, Sun 12 Oct · Mihai, …     (collapsed)
──── expanded ────
Sat 4 Oct · Ana · 30th
Sun 12 Oct · Mihai
Mon 27 Oct · Ioana · 1st
+2 more                                                            (summaryText, beyond five)
```

Tap → the overview, List mode, 1–31 Oct, Birthdays. No actions. The quiet
kinds stay on `alerts_quiet`; nothing else moves channel.

## 7. Strings

ARB ×3 (`l10n` skill; Romanian `few` on every plural). Keys, en values:

- Category alerts: `categoryAlertsHint` "Every event in this category gets
  these alerts.", `categoryAlertTimedCaption` "Timed events: {when}",
  `categoryHasAlerts` "Has alerts", `eventAlertFromCategory` "From
  {category}", `eventCategoryAlerts` "Category alerts",
  `eventCategoryAlertsDesc` "Use the alerts set on {category}"; the section
  label, Add alert and the two When rows reuse `eventAlerts`,
  `eventAlertAdd`, `alertsDefaultTimed` and `alertsDefaultAllDay` — never a
  key whose wording an existing key already carries (the owner's
  2026-10-11 duplicate-wording rule; S3 review #10).
- Digests: `digestsTitle` "Digests", `digestsAdd` "Add digest", `digestNew`
  "New digest", `digestEdit` "Edit digest", `digestName` "Name",
  `digestCategories` "Categories", `digestEvery` "Every", `digestEveryDay`
  "Day", `digestEveryWeek` "Week", `digestEveryMonth` "Month", `digestOn`
  "On", `digestOnDayOfMonth` "the {day}" (ordinal through `intl`'s
  `DateFormat.d` — no hand-made ordinals), `digestAt` "At", `digestCovers`
  "Covers", `digestCoversSameDay` "From that day", `digestCoversNextDay`
  "From the next day", `digestIncludeEmpty` "Also when empty",
  `digestIncludeEmptyDesc` "Send it when nothing is due", `digestNext`
  "Next: {when} · {count}", `digestDelete` "Delete digest",
  `digestDeleteConfirm` "Delete this digest?", `digestLimitReached` "You can
  keep up to {count} digests", `digestDescribeDaily` "Daily at {time}",
  `digestDescribeWeekly` "Weekly on {weekday}, {time}",
  `digestDescribeMonthly` "Monthly on {day}, {time}", `digestAllCategories`
  "Events", `digestCategoriesCount` plural "{count} categories",
  `digestCountPeriod` plural "{count, plural, =0{No events {period}} one{1
  event {period}} other{{count} events {period}}}", `digestPeriodToday`
  "today", `digestPeriodTomorrow` "tomorrow", `digestPeriodThisWeek` "this
  week", `digestPeriodNextWeek` "next week", `digestPeriodThisMonth` "this
  month", `digestPeriodNextMonth` "next month", `digestMoreCount` plural
  "+{count} more", `alertsDigestChannel` "Digests", `alertsDigestChannelDesc`
  "Bundled summaries of upcoming events", `alertsOutcomeDelivered`
  "Delivered" (if Recent lacks the word).

## 8. Tests

- Models: `category_alert_test.dart` (codec, clamps, `toEventAlert`),
  `event_digest_test.dart` (payload round-trip, unknown cadence → monthly,
  anchor / minute / lead clamps, `describe`, `derivedTitle`).
- Facade: `event_alerts_facade_test.dart` — `effectiveFor` merge order,
  D4 dedupe (own wins), the opt-out, disabled rows kept, caps,
  `hasAlarm(event)` over inherited rows, `revision` on category writes.
- `digest_planner_test.dart`: the next two fires per cadence; anchor 28 in
  February; weekly anchors; lead 1; DST days (the wall-clock rule); the
  span bounds; entries sorted, the allowlist honoured (archived categories
  still digest), every occurrence a line; the empty rule and `includeEmpty`; the work
  budget.
- `digest_notification_content_test.dart`: title fallbacks, period phrases
  (the first-weekday rule, anchor 1), the `=0` form, five lines + more, the
  count label, locale-written day labels (fixed labels in the test).
- `alert_planner_test.dart`: unchanged signature; one case over projected
  alerts (two events, one category alert, one day → two fires).
- `alert_scheduler_test.dart` (the `FakeAlertGateway` at `:43`): the tuple
  identity — v41-shaped rows survive a pass with no cancel and no schedule;
  two events on one day under one category alert get distinct ids; a
  category alert edit re-arms; an opt-out cancels; digest rows pending →
  fired / cancelled, never missed, no notice, no snooze; a content change
  re-arms by signature; the OS-truth pass covers digest ids; `maxDigests`.
- `alert_os_id_test.dart`: the three seeds, event-sourced unchanged.
- Database: `category_alerts_migration_test.dart`, `event_digests_migration_test.dart`
  (the v41 → v42 chain, guards idempotent, `category_alerts = 1`,
  `source = 'event'` on existing registrations); schema parity.
- Backup: both keys round-trip; absent keys leave the tables; an event JSON
  without `categoryAlerts` imports as on; `clearXForImport` paths.
- `.ics`: an inherited alarm exports as `VALARM`; an opted-out event
  exports none of them.
- Widgets: `category_editor_sheet_test.dart` (the group, add / edit / remove
  through `AlertSheetRobot`, save writes `replaceForCategory`, the cap);
  `event_editor_*` (inherited rows, the switch, the dirty fingerprint, the
  cap counting own rows); `event_detail_sheet` rows; `event_alert_badge`
  over inherited rows; `alerts_page_test.dart` (the Digests group, toggles
  dispatch, the fire rows, Recent); `digest_editor_sheet_test.dart` through
  `DigestSheetRobot` (every row, the anchor row's presence per cadence, the
  caption, delete, discard); `sheet_bottom_clearance_test.dart` entry;
  `android_alert_notifications_test.dart` (the digest details: channel,
  importance, inbox style, group, no actions); `alerts_channel_test.dart`
  (the fourth channel); `pending_navigation` / drain for
  `OpenOverviewIntent`; the overview's look consumption; l10n parity.
- QA: `tool/qa/fixtures/alerts.json` gains a yearly birthday "Ana" two days
  out, a Birthday category alert, a monthly digest (also when empty) and a
  daily digest "Next days" timed `{{minute+9}}` after the relaunch with a
  two-day lead (`test/qa/alerts_fixture_test.dart` pins all four); flows
  `alerts/03_category_alerts.txt`, `alerts/04_digests.txt`, the one `expect`
  in `calendar/18_category_editor.txt`; the ring part is the runner's hand
  sequence in 04's header — **there is no `qa fire` verb** (the alerts
  roadmap's Session 7 was never built; S5 found this out), so the timed
  daily digest stands in for it; the inbox-style notification and the new
  surfaces in the matrix screenshots (light / dark, de / ro, 200 % text).

## 9. Slices and the gate

Each slice: one `implementer` → the gate (`dart analyze lib`, the whole
`flutter test`, `flutter gen-l10n` + empty `untranslated.txt` when ARBs
changed, the must-not-change list re-read against the diff) → one
`reviewer` → the implementer fixes → the owner commits. Sequential: S3 and
S4 share the ARBs and the hub.

| Slice | Scope | Done means |
| --- | --- | --- |
| S1 Persistence and domain | v42 migration + Drift tables + columns; `CategoryAlert`, `EventDigest`, `EventAlert.categoryId`; DAOs; `EventAlertService` category half, `EventDigestService`; the facades (`effectiveFor`, `hasAlarm(event)`, `EventDigests`); backup keys; `.ics` effective alerts; `deleteCategory` cascade | **IMPLEMENTED and REVIEWED 2026-10-15, uncommitted** (42 files + this record): gate `dart analyze lib test` clean, `flutter test` `+7810 ~10 -1` (`+7700` before; the one failure `host_devices_test`, Windows-only, pre-existing). The review's 17 findings: #1 backup twin, #2 dedupe key, #3 unknown → other, #4 the bloc never loaded `EventDigestService`, #5 D15's arithmetic, #6 reconcile inside the write chain, #7 in-flight creation, #8 unreadable digest armed, #12 doc contradiction, #13 redundant default, #15 badge allocation, #16 projected alerts into `replaceForEvent` — all fixed (F1–F12) and the record amended; #9 (cap guards `create` only — the planner bounds the plan), #10 (`replaceForCategory` refuses another category's id — S3 mints ids), #11 (order within a second, the event alerts' own), #14 (column order, the `remove_after_alert` precedent) kept by decision. Decisions beyond the record, sound: the cascade through the DAO inside the transaction; the twins' import is a wipe-and-reinsert; `create(draft)`; `fromRow` on plain values; `source` declared last; the badge tooltip on `effectiveFor`; category alerts import right after categories, before templates. |
| S2 Planning and delivery | `DigestPlanner`, `digestNotificationContent`, `AlertLabels.entryDayLabel` / `spanLabel`; the registry tuple, `source`, the seeds; the scheduler's digest pass and settle branch; `AlertGateway.scheduleDigest`; the payload fields; the Android channel, details, `_scheduleDigest`, `_handleResponse`; `OpenOverviewIntent`, `toCalendarOverviewLook`, `pendingOverviewLook`, the overview's consumption | **IMPLEMENTED and REVIEWED 2026-10-15, uncommitted**: gate `dart analyze lib test` clean, `flutter test` `+7915 ~10 -1` (`+7810` after S1), `untranslated.txt` `{}`. The review's 16 findings: #1 `cancelSnoozeForAlert` keyed on alert + day (one event's Stop cancelled another's snooze of the same category alert), #2 the background Snooze re-post seeded without the event, #3 a digest tap deleted the stored overview period, #4 the notice's Skip dead for an inherited alarm on a one-time event, #6 the signature without the allowlist, #7 the landing keeping the query / Missed only, #8 a late digest pulled off the shade, #9 `digestEntries` under the cap, #10 the rebuilt snooze's `source`, #11 a throw mid-pass, #12 unclamped anchors, #13 test gaps, #14 format, #15 copy — all fixed (G1–G14; the payload gained `inherited`, `inh`); #5 (the hub's inherited switch a no-op until S3) is S3's; #16 (wording before the skip check) kept. Deviations beyond the brief, all sound: `spanStart.day == 1` for the month phrases, `AlertLabels.strings`, the computed title, `eventId` empty only with `dg`, no avatar for several categories, tint and glyph in the signature, disabled digests planned as if on for the hub. Device: the inbox notification and its tap are S5's pass. |
| S3 Category alerts' surfaces | the category editor group; the editor's inherited rows and switch; the detail sheet; badges; the categories page bell; the hub's inherited caption and switch meaning; `CategoryAlertsChanged`; ARB ×3 | **IMPLEMENTED and REVIEWED 2026-10-15, uncommitted**: gate clean, `flutter test` `+7976 ~10 -1` (`+7915` after S2), `untranslated.txt` `{}`. The review's 15 findings: #1 a stray category behind a `null` after a failed alert write (✕, back and the scrim now hand the written row back; a drag-close still returns `null` — residual, low), #2 the hub's way back (`hubEntries` imagines an opted-out event's inherited rows; `EventAlerts.inheritedFor`), #3 no permission check for a category's first alert (`AlertPermissionCheck.afterSave`, shared with the flow, which now checks effective alerts), #4 hub keys colliding for twins, #5 paused category alerts shown "on" (the master switch exists now; the hub, the editor and the detail sheet skip paused ones), #6 rows leaving under the finger (they dim), #7 the hub switch resurrecting a deleted event (press-time state read), #8 no `CategoryAlertsChanged` on delete, #9 the bell for TalkBack and at 2.0 (a 24 dp slot on every row — the one geometry change, uniform), #10 four duplicate-wording keys dropped for the existing ones, #11 the sheet dispatches `CategoryAlertsChanged` itself, #12 stale class doc, #13 inherited-row ids, #15 test gaps — all fixed (H1–H13); #14 kept (LF endings git normalises, pre-existing format drift, no revision listener on the categories page). Deviations beyond the brief, sound: a new category alert drafts without the settings defaults (D7); the category editor stays unguarded; `_CategoryAlertRow` composed from the picker row and a switch rather than a new shared primitive. |
| S4 Digests' surfaces | the hub's Digests group, fire rows, Recent; `DigestEditorSheet` + robot; the three bloc events; ARB ×3 | **IMPLEMENTED and REVIEWED 2026-10-15, uncommitted**: gate clean, `flutter test` `+8038 ~10 -1` (`+7976` after S3), `untranslated.txt` `{}`; the first implementer run hit its turn limit and was resumed. The review's 21 findings: #1 the hub's toggle re-encoding the stored payload (now `setEnabled` writes the column alone; a clean Save writes nothing; an unreadable digest's switch is disabled with "Saved by a newer version"), #2 tests reaching the real service (a `digestWriter` seam), #3 the caption ignoring Also when empty (the draft's first planned fire), #4 the caption slot not fixed (candidates from the locale's widest phrases), #5 two fires one id, #6 the page ground (`pageGround`, the bar too), #7 the avatar on the name row (a glyph instead), #8 the caption planned per keyboard frame (memoized), #9 de/ro "Am … am 1." (the bare day form, the preposition in the describe), #10 the sheet-minted id and position (the service owns both), #11 a dead `missed` branch, #12 Recent by current settings (kept, noted), #13 a switched-off row reading live (dims, no "next"), #14 the duplicated row (`FormPickerSwitchRow` in `form_rows.dart`, the one primitive added), #15 the empty state's centring, #16 format, #17 re-entry guards (the category editor's too), #18 a failed write's switch (kept, the precedent), #19 test gaps — all fixed (J1–J17). Deviations, sound: the seven reused keys, `digestOnDayOfMonth` as an ICU `select`, `show(…, events:, weekStart:)`, `FormSheetSemanticsRefresh` on the sheet. |
| S5 Device pass and docs | fixture + flows; the matrix screenshots; §13's docs; this record's status | **Fixture, flows and docs DONE 2026-10-15; the device pass is running.** Fixture: Ana (yearly birthday, today + 2, numbered), the Birthday category alert, the monthly digest (also when empty), the daily "Next days" digest timed `{{minute+9}}` with a two-day lead; `alerts_fixture_test` 14 green, the suite `+8042 ~10 -1`. Flows `alerts/03_category_alerts.txt`, `alerts/04_digests.txt` (its header carries the hand ring sequence and the timing window — 04 must reach the hub within the nine minutes, the relaunch before 23:50), one `expect` in `calendar/18_category_editor.txt`. Docs: the feature-doc addendum, the skill's rule lines (nine services, effective alerts, the registry tuple, the digest rules, the hub rule's amendment, the file map, the recipe), `references/subsystems.md`'s new section with each rule's why, `schema-lineage.md` v42, `context-log.md`, the alerts roadmap's §2.3 / §3.3 / §5.6 / §12 pointers, `qa-harness.md` and `qa-emulator`'s alerts pass, the adoption roadmap's Tier 4 cell, the calendar-ui id catalogue (`cloud-sync-roadmap.md` lists no tables — nothing placed). **Device pass 2026-10-15, emulator-5554 (`Pixel_9_Pro`), green**: `qa flows alerts` 5 / 5 (00–02 the alarm pass, 03 category alerts, 04 digests, 36 steps); the ring part by hand — "Next days" fired at +9 min, the shade held the inbox notification (collapsed "Next days · 1 event from Oct 17 to Oct 17 · Oct 17 ·…", expanded "Sat, Oct 17 · Ana · Year 1"), its tap landed on the overview's list with `overview-row-qa-alert-birthday-2026-10-17` present and the options sheet's Categories reading "Birthday"; `qa errors` clean in `run.log`, logcat and the agent; 100 matrix shots (five surfaces × light / dark × ro / de × 100 % / 200 % × 427 dp / 360 dp) under `build/qa/shots/20261015_17*`. Seen at 200 %: the hub's old day rows wrapped "09:00" as "09:0 / 0" (fixed the same day — the time slot scales with the text in the alert, digest-fire and Recent rows; a 12-hour time at 200 % in a Recent row is the one case that could still clip, unchecked on a device), the sheet headers ellipsize ("Editează cat…", the known header-at-200 % kit trap), the alert sheet's Type row shows an empty band under its caption (pre-existing), the digest rows' captions ellipsize their "next …" (by the kit's rule); the light theme's group edges are visible on `pageGround`. Shade traps for the runner: the shade opens only with `swipe down --via native --from 540,8 --dist 1400`, and `look --all` cannot read it (uiautomator, the known trap) — written into 04's header. |

**Must not change**: `calendar_event_alerts` rows, codec and backup
semantics (absent clears); `AlertPlanner.plan`'s signature, `fireInstant`,
the 2 / 30 / 48 horizon; the event-sourced id seed and every standing
snooze; `AlertPayload`'s existing fields and their JSON keys; the alarm
page, the ring paths, the fork, `_settleEndedRing`'s causes; the three
existing channels' ids and importance; `EventAlert.describe` as the one
formatter and `alertNotificationContent` as the one words module; "nothing
formats a time in the background isolate"; the hub owning no data; the
quick alarm's builders; `OverviewPeriod.encode`'s persisted kinds; the
categories table.

## 10. How to run this

- This record was written on Fable 5.1; the session ends at the approved
  decisions. Implementation sessions run on **Opus 5.5 at high**.
- Per slice: `implementer` (Opus 5.5, default effort — every slice needs
  judgement; `effort: medium` only if S5's fixture work is split off) with a
  brief that names this record's sections (§3–§6 for S1–S4, §8 for the
  tests, the must-not-change list verbatim), the files by `file:line` from
  §1, the skills to load (`calendar-events` + `drift-migrations` for S1;
  `calendar-events` + `flutter-principles` for S2; `ui-language` +
  `calendar-ui` + `l10n` for S3–S4; `qa-emulator` + `verify` for S5), and
  "no commit, no new docs, no scope growth, Windows".
- `reviewer` (Opus 5.5) per slice with the same sections and the
  must-not-change list; findings CONFIRMED / PLAUSIBLE into this record's
  review block.
- `qa-runner` (Sonnet 5.5) for S5; `docs-writer` (Sonnet 5.5) places §13's
  text once the lead has written it; `explorer` (Haiku) for any lookup a
  brief still needs.
- No workflow, no `fable-max` unless the owner names the final review.
- Check-ins: after each slice, the number of uncommitted files and a ready
  commit line; the owner commits.
- **Which machine** (agreed 2026-10-15): S1–S5 run on Windows against the
  Android emulator — four of the five slices are platform-neutral Dart and
  the gateway half of S2 is Android. iOS comes after, on the Mac, as the
  alerts roadmap's Sessions 8 and 9 (the runner that has never been built,
  then `DarwinAlertGateway`), which bind the whole gateway interface at once
  with `scheduleDigest` as one more method; nothing fires on iOS until then
  (`injection.dart:173-182` registers the Android gateway only). Doing the
  Mac phase first would touch the Darwin gateway twice and still prove
  digests on Android only.

## 11. Deferred and not planned

- **A background re-plan job (D21).** What it would buy: alerts beyond the
  30-day horizon and a digest's third fire on a phone that does not open
  the app for a month. What it costs: `workmanager` (or
  `android_alarm_manager_plus`), a headless Dart entry that initializes
  `DatabaseLifecycle` and the eight calendar services in a second isolate,
  Drift on two isolates against one file, and an exception to the rule that
  no scheduling pass runs outside the UI isolate. If wanted, its own record;
  the cheapest shape is a 24 h periodic work request calling
  `reconcileAll(AlertReconcileReason.periodic)` with the database opened
  read-mostly and every write serialized through the existing chain.
- Per-occurrence alert overrides (the alerts roadmap's §12 still stands).
- Alarm-tier digests; digests over holidays and fasting (`holidayDaysInRange`
  and `fastingRunsInRange` exist — a later `kinds` axis on the model).
- A per-event "today is Ana's birthday" is the daily cadence with the
  Birthdays allowlist — not a separate feature.
- iOS: `DarwinAlertGateway` is the alerts roadmap's Phase 4 (the Mac);
  `scheduleDigest`'s Darwin details fall into the body (no inbox style) —
  written when that phase runs.
- The categories table's own CRDT block: unchanged; the alert table carries
  its own and references categories by id.
- Repeating "nag" reminders until Done (the OS roadmap's §12) stay out.

### 11.1 Residuals left by the slices (2026-10-15), with the intended fix

- **`qa fire` / `qa alerts` do not exist** — the alerts roadmap's Session 7
  stayed a prompt; this record and its briefs assumed the verb. The pass
  proves the digest through the fixture's timed "Next days" row instead.
  Building the verbs (an app seam under `DevOptions`, an agent op, two
  harness verbs) is a harness change for the owner to OK; it would also give
  the monthly digest a provable ring.
- **A one-day span reads "from Sep 28 to Sep 28"**: `digestPeriodOf` takes
  `digestPeriodSpan` whenever no calendar-unit word applies, although
  `AlertLabels.spanLabel` collapses a single day. Reachable only through a
  stored lead above 1 (the sheet offers 0 and 1). Fix: a `digestPeriodOn`
  "on {date}" key ×3 when start equals end, in `digest_notification_content.dart`.
- **The category editor's drag-close** returns `null` after a failed alert
  write (the bottom sheet's own drag pops past the `PopScope`), so the
  written category is listed only after the page is reopened; ✕, back and
  the scrim hand it back. Fix: route the drag-close through the same result.
- **Recent describes a digest by its current settings**: the registry keeps
  no count and no snapshot of the digest; an edited digest's old deliveries
  read with the new describe. Fix, if wanted: a `label` column on
  `alert_registrations` written at arm time.
- **The hub's inherited row before S3's fix had no way back** (fixed) and
  **a failed write leaves a switch at the user's value** (the alert rows'
  precedent, kept).
- **`02_remove_after.txt`'s header** ("Two things are left standing") no
  longer lists everything the seed leaves armed (the inherited reminder
  tomorrow at 09:00, the monthly digest); the existing flows were on S5's
  must-not-change list. Fix: the header line, next time 02 is touched.
- **Column order** of `calendar_events.category_alerts` differs between a
  fresh and an upgraded database (the `remove_after_alert` precedent; reads
  are by name). **Alerts saved in one call share a `created_at` second**, so
  their order holds within a session only (the event alerts' own).
- **No revision listener on the categories page**: the bell is fresh after
  the editor returns and stale after an import until the page is reopened.
- **The bell takes 24 dp from every category row's title** (the slot is on
  every row so no row grows at 200 %); the row geometry is otherwise the
  Tier 4 one.

## 12. Risks

- **The registry tuple.** A matching bug re-arms or orphans standing
  entries; the scheduler suite's "v41 rows survive a pass" case is the
  guard, run before the gateway work.
- **Seed collisions** between the three seed grammars land on the probe
  (`kAlertOsIdMaxProbes = 64`); `alert_os_id_test` covers a forced one.
- **Reconcile cost.** Ten digests × two spans × every event: `candidateDaysIn`
  prunes yearly and monthly rules to one check per span; the budget test
  pins the number; a thousand events stay well under a frame.
- **Attenuation.** A digest and a birthday reminder both at 09:00: Android
  attenuates the second notification posted within a minute (§3.7 of the
  alert-surfaces record); both still show. The hub's rows make the clash
  visible; the owner can stagger.
- **Two idioms on the hub** until Tier 4: the Digests group on the language
  over Card rows. Accepted — the adoption roadmap already lists the hub.
- **Strings.** Ordinal day-of-month in three languages: `intl`'s `d` with
  the locale's pattern, no ordinal suffixes; weekday names from `intl`.
- **The opt-out column's default** is read by every event decode; a wrong
  default would silence every inherited alert — the migration test pins
  `1`.

## 13. Docs to update when it ships

- `docs/calendar-events-feature.md`: an addendum (category alerts, digests,
  v42, the hub).
- `docs/event-alerts-roadmap.md` §12: the per-category item delivered here;
  §2.3 the tuple and `source`; §3.3 the seeds; §5.6 the hub.
- `.claude/skills/calendar-events/SKILL.md`: rule lines — effective alerts
  through the facade, the registry tuple, the digest rules (D9, D16), the hub
  rule's amendment, the file map; `references/subsystems.md` (the hub and
  the sheet sections); `references/schema-lineage.md` (v42);
  `references/context-log.md` (dated entry).
- `.claude/skills/drift-migrations/references/` (the lineage pointer),
  `.claude/skills/qa-emulator/` references and `docs/qa-harness.md` (fixture
  and flows); `.claude/skills/calendar-ui/references/` (the semantics-id
  catalogue, the device pass).
- `docs/calendar-language-adoption-roadmap.md`: the Tier 4 row (the Digests
  group already on the language).
- `docs/cloud-sync-roadmap.md` if it lists the synced tables.
- This record's status line.
