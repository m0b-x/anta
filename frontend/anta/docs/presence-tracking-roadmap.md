# Presence Tracking Roadmap — ANTA

**Status: shipped (2026-08-16).** Everything below is implemented; this file
is the design record. Running behaviour:
`docs/calendar-events-feature.md` (schema-v26 addendum) and the calendar
bullets in `COPILOT_CONTEXT.md`. Verified at ship time: `dart analyze lib`
clean, full `flutter test` suite green (benchmarks skipped),
`flutter gen-l10n` clean with all ten keys in en/de/ro.

**Deviations from the plan as written:**

1. Drift's create path adds `CHECK ("is_deleted" IN (0, 1))` on booleans;
   the frozen v26 DDL — like every frozen DDL in this app — omits CHECKs,
   so upgraded databases lack them. Benign (Drift only writes 0/1); the
   parity test asserts names/nullability/defaults/PK, not constraints.
2. `EventPresenceService.forTesting(AppDatabase)` (`@visibleForTesting`)
   exists because `getInstance()` hardwires `AppDatabase.getInstance()`;
   the bloc test runs the real service stack over a temp-dir database —
   `CalendarBloc` has no injection seam, and none was added for a test.
3. The timeline also fades/hides **all-day chips**, filtering the event
   list before `DayTimelineLayout.compute` — all-day is the common presence
   case, and pre-layout filtering keeps the hour span and overlap columns
   honest in hidden mode.
4. `AgendaListView` drops a day header whose only occurrence is hidden.
   Known cosmetic gap, left deliberately: the agenda's panel-level count
   still counts hidden occurrences (an exact count would need an
   O(occurrences) presence pass per keystroke rebuild).
5. The editor switch sits after both When branches but **before** the Time
   subsection, beside the schedule it qualifies.
6. `tracks_presence` sits before `created_at` on fresh installs and last on
   upgraded databases — the divergence `retroactive`/`count_*` already
   have (`ALTER TABLE` appends); column order is outside the parity test.
7. The detail sheet's presence control anchors next to the date `_InfoRow`,
   which shows the series start date (pre-existing); the day being marked
   is the day the sheet was opened for.

Recurring events gain an opt-in **presence** mode: the user goes to the gym
almost every day, sometimes skips — a skipped day is marked *missed* and the
calendar renders it either faded or not at all (one global setting). Attendance
is the default and costs nothing; only the exceptions are stored. The absence
table is **cloud-ready from birth**: it carries the app's five CRDT columns
with live tombstone semantics, so cloud-sync phase-02 only wires transport —
no schema or write-path retrofit (decisions 1 and 8).

---

## Context

The calendar has one-time and recurring events (`RecurrenceRule`,
`lib/models/recurrence_rule.dart`), but no notion of "this occurrence was
scheduled and I did not show up". The two closest precedents in the codebase
point at the same shape:

- **v24 per-occurrence descriptions** — `calendar_event_occurrences`
  (PK `{event_id, day}`, only user deltas, a daily event costs zero rows until
  touched, static facade published by a `DatabaseLifecycle`-registered
  service). This is the template this feature copies almost mechanically.
- **Fasting skip/force dates** — per-day exceptions to a recurring rule, but
  stored as one settings-JSON blob. That was right there because the set is
  bounded (200), global and single-owner. Absences are unbounded and
  event-scoped → they get a table, not a settings key.

### Decisions taken

1. **Sparse absence table, attendance implicit.** A live row in
   `calendar_event_absences` means "this occurrence was missed"; no live row
   means present. Un-marking **tombstones** the row (`is_deleted = 1`, fresh
   HLC, `version + 1` — the `NoteDao.softDeleteNote` shape); re-marking
   resurrects the same row with `created_at` intact. A hard delete would be
   simpler locally, but mark/unmark is exactly the toggle that needs an
   ordered tombstone once devices merge — with PK `{event_id, day}` the
   table is a textbook last-writer-wins element set.
2. **Not a column on `calendar_event_occurrences`.** That table's contract is
   "a present row always wins, including when `description` is `''`" — a
   presence-only row would either blank the day's description or force a
   null-semantics rewrite of a freshly shipped invariant, and it would drag
   presence under the global per-occurrence-descriptions setting (default
   off). Separate table, both invariant sets stay independently checkable.
3. **Not recurrence exceptions.** A missed day is *not* a cancelled
   occurrence: `occursOn` still returns true, the occurrence still renders
   (faded), still numbers into `countOccurrences` labels (counts stay
   schedule-based — visit #47 missed means the next one is still #48), still
   exports to `.ics`. Presence is a **rendering + record** concern, never a
   membership concern.
4. **Opt-in per event** via a `tracks_presence` column on `calendar_events`.
   The gate for where presence applies is
   `tracksPresence && rule is! OneTimeRecurrence` — same rule as
   `OccurrenceDescriptions.appliesTo`: `SpecificDatesRecurrence` is a list of
   distinct occasions and **does** participate; never gate on the editor's
   `_RepeatMode`, which files specific-dates under one-time.
5. **One description.** The event's `description` is *the* description for
   every occurrence; absence rows carry no text. (Per-occurrence descriptions
   remain an orthogonal v24 feature that composes with this one untouched.)
6. **Display is one global setting**, `faded | hidden`, living on
   `CalendarAppearance` so it threads page → panel → leaves through the
   existing `appearance` parameter. Default **faded** — a mark the user just
   made should visibly do something, and hidden-by-default makes the first
   mark look like a delete.
7. **The day summary panel always shows missed occurrences (faded), even in
   hidden mode.** It is the toggle surface: a row that disappears the moment
   it is marked can never be un-marked. Grid markers, agenda and timeline
   follow the setting.
8. **Cloud-ready from birth.** `calendar_event_absences` carries the five
   CRDT columns of the shipped Notes/Folders pattern byte-for-byte —
   `hlc_timestamp` TEXT NOT NULL, `device_id` TEXT NOT NULL, `version`
   INTEGER NOT NULL DEFAULT 1, `is_deleted` INTEGER NOT NULL DEFAULT 0,
   `deleted_at` INTEGER NULL (`notes_table.dart:15-19`; **not**
   `ContentChunks`' four-column variant, which skips `deleted_at` and
   forgets the version bump on soft delete) — stamped at the DAO exactly as
   `NoteDao` does it: `db.generateHlc()`, `db.deviceId`, read-then-write
   `version + 1`. Stamping is live app-wide today (guarded by
   `query_count_test.dart:96`), so this copies a working pattern rather than
   scaffolding a dormant one. Deliberately out of scope: `owner_id`
   (meaningless until accounts exist — phase-02 backfills it and adds the
   column to events and absences together), `getAbsencesSince` /
   `mergeAbsence` delta feeds and any `SyncGateway` wiring (transport is
   phase-02's whole job), and `calendar_events`' own CRDT-ification (a
   whole-subsystem change phase-02 owns). Phase-02 renumbers to **v27**,
   and — unlike `calendar_event_occurrences`, which deliberately stays
   device-local — **absences sync**: the marks are the record this feature
   exists for, and a record that does not roam with its event is visibly
   wrong data.

---

## Files

**New**: `lib/database/tables/event_absences_table.dart`,
`lib/database/daos/event_absence_dao.dart`,
`lib/services/event_presence_service.dart`,
`lib/constants/event_presence.dart`,
`test/services/event_presence_service_test.dart`

**Modified**: `lib/database/migrations/database_schema.dart`,
`database_migrations.dart`, `lib/database/database.dart`,
`lib/models/calendar_event.dart`, `lib/models/calendar_appearance.dart`,
`lib/models/day_summary_entry.dart`, `lib/services/calendar_event_service.dart`,
`lib/services/day_bars_resolver.dart`, `lib/services/day_summary_resolver.dart`,
`lib/services/settings_service.dart`, `lib/services/backup_service.dart`,
`lib/constants/settings_keys.dart`, `lib/constants/calendar_colors.dart`,
`lib/bloc/calendar/` (all three), `lib/pages/calendar_page.dart`,
`lib/pages/calendar_settings_page.dart`, `lib/widgets/event_editor_sheet.dart`,
`lib/widgets/event_detail_sheet.dart`, `lib/widgets/day_summary_panel.dart`,
`lib/widgets/calendar_bottom_panel.dart`, `lib/widgets/agenda_list_view.dart`,
`lib/widgets/day_timeline_view.dart`, `lib/l10n/app_{en,de,ro}.arb`,
`test/database/{schema_parity,query_plan,query_count}_test.dart`

**Untouched**: `recurrence_rule.dart` (decision 3), `event_agenda.dart` scans,
`import_export_service.dart` (`.ics` and the notes archive), everything under
`lib/utils/` markdown, `calendar_event_occurrences` and its service/facade.

---

## 1. Data model & migration (schema v26)

`database_schema.dart`: `v26EventPresence = 26`, `currentVersion = 26`.
**Numbering collision**: `docs/cloud-sync-phase-02-calendar-sync.md` also
reserved v26 — that (still planned) migration becomes v27; note it in the
phase-02 doc when either ships.

`_migrateV25ToV26`, appended to `_migrations`, doc comment stating what
changed, why the defaults preserve pre-feature behaviour, and that it is
idempotent. Two statements, both existing house shapes:

- **Column** (v18→v19 shape, `database_migrations.dart:648-659`): read
  `PRAGMA table_info(calendar_events)`, guard, then
  `ALTER TABLE calendar_events ADD COLUMN tracks_presence INTEGER NOT NULL DEFAULT 0`.
- **Table** (v23→v24 shape, `:755-766`): raw DDL **frozen at v26**, never
  `m.createTable`:

```sql
CREATE TABLE IF NOT EXISTS calendar_event_absences (
  event_id      TEXT    NOT NULL,
  day           INTEGER NOT NULL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  hlc_timestamp TEXT    NOT NULL,
  device_id     TEXT    NOT NULL,
  version       INTEGER NOT NULL DEFAULT 1,
  is_deleted    INTEGER NOT NULL DEFAULT 0,
  deleted_at    INTEGER,
  PRIMARY KEY (event_id, day)
)
```

The default asymmetry is deliberate and matches the Drift declarations:
`hlc_timestamp`/`device_id` have **no** `DEFAULT` (they are `text()()` — every
insert must stamp them or fail), `version`/`is_deleted` carry the
`withDefault` values, and `deleted_at` is the single nullable column. This is
the first frozen-DDL table in the codebase to carry CRDT columns
(notes/folders are v1 `createAll`-only), so the parity test's blanket
`notnull == 1` loop is relaxed for `deleted_at` (§11).

No separate index: the composite PK's automatic index has `event_id`
leftmost and covers both the point lookup and the per-event cascade (proven
for the twin table by `query_plan_test.dart:145`). No partial
`is_deleted = 0` index either — unlike notes, this table is loaded once into
a service cache, never range-queried.

**Drift declarations**: `EventAbsences` in `event_absences_table.dart`
(`@DataClassName('EventAbsenceRow')`, `tableName => 'calendar_event_absences'`,
`day` a `DateTimeColumn` written date-only UTC — Drift stores unix **seconds**),
mirroring `event_occurrences_table.dart` minus `description`, plus the
five-line CRDT block copied verbatim from `notes_table.dart:15-19` (not
`content_chunks_table.dart`'s four-column variant). Register table +
dao in `@DriftDatabase` (`database.dart:40-64`) or `schema_parity_test.dart`
fails. `CalendarEvents` gains
`boolColumn get tracksPresence …withDefault(const Constant(false))`.
Then `dart run build_runner build --delete-conflicting-outputs`.

**Model**: `CalendarEvent.tracksPresence` (default `false`) — constructor,
`copyWith`, `props`. `CalendarEventService`: `_eventToCompanion`, `_fromRow`,
`exportData()` adds `'tracksPresence'`, `importData()` reads it with
`const Value.absent()` fallback so pre-v26 backups get the column default
(the `retroactive` precedent, `calendar_event_service.dart:207-211`).

## 2. DAO — `EventAbsenceDao`

The `EventOccurrenceDao` skeleton with `NoteDao`'s stamping discipline. All
CRDT stamping lives **here**, never in the service — `db.generateHlc()`,
`db.deviceId`, read-then-write `version + 1` (the `note_dao.dart:218-245`
idiom):

- `getActive()` — `WHERE is_deleted = 0`; feeds the service cache and facade.
- `markMissed(eventId, day)` — one transaction: SELECT by PK; no row →
  INSERT (`version 1`, fresh HLC, `db.deviceId`, `created_at`/`updated_at`
  now); tombstoned row → UPDATE `is_deleted → 0`, `deleted_at → NULL`,
  `updated_at → now`, fresh HLC/device, `version → existing + 1`,
  `created_at` masked (a resurrected day keeps the date it was first
  marked); already-live row → **complete no-op**, no version churn.
- `unmark(eventId, day)` — the `softDeleteNote` shape: UPDATE
  `is_deleted → 1`, `deleted_at → now`, `updated_at → now`, fresh
  HLC/device, `version + 1`. No row or already tombstoned → no-op.
- `importAbsence(companion)` — the `importNote` convention: preserves
  `created_at`/`updated_at` from the caller, stamps **fresh** HLC / device /
  `version 1` (backups are not a sync channel — §10).
- `deleteForEvent(eventId)` / `deleteAll()` — **hard** DELETEs. The parent
  event's delete is itself hard today; tombstoning children of a
  hard-deleted parent would strand orphans in every export. When phase-02
  converts event deletes to tombstones, this cascade flips in that change.
- Timestamps go through typed companions/`Variable<DateTime>` — never raw
  `millisecondsSinceEpoch` ints (Drift stores unix **seconds**; the raw-SQL
  cascade in `folder_dao.dart:~451` binds millis and is the known wrong
  example — do not copy it).

## 3. Service + facade

**`EventPresenceService`** (`lib/services/event_presence_service.dart`) —
the `EventOccurrenceService` shape verbatim, minus the enabled flag (opt-in is
per event, there is no global switch):

- `static Future<EventPresenceService> getInstance()` — loads all rows into
  `Map<String, Set<DateTime>> _byEvent`, publishes to the facade, registers
  `DatabaseLifecycle.registerResetHandler(reset)` in the first-time block.
- `static void reset()` — `_instance = null; EventPresence.resetCache();`
  (the contract: a reset clears the singleton **and** its facade).
- `markMissed(eventId, day)` / `unmark(eventId, day)` — normalize the day
  through the local `_dateOnlyUtc`, delegate to the DAO (which owns all CRDT
  stamping — the service never touches those fields), patch `_byEvent` in
  place, republish. `_byEvent` and the facade hold **live marks only**;
  tombstones stay below the service's waterline.
- `refreshAfterEventRemoval()`, `deleteAll()`, `clearAllForImport()`,
  `exportData()`, `importData(List)` (shapes in §10).

**`EventPresence`** (`lib/constants/event_presence.dart`) — static,
synchronous, the `OccurrenceDescriptions` facade shape:

- `bool appliesTo(CalendarEvent e)` => `e.tracksPresence && e.rule is! OneTimeRecurrence`
- `bool isMissed(String eventId, DateTime day)` — O(1) two-map probe; **the
  single read entry point**, or grid/panel/agenda/timeline drift apart.
- `int revision` — bumped by `updateCache`.
- `updateCache({required Map<String, Set<DateTime>> byEvent})`, `resetCache()`.

Published by the service, **never** configured from a page
(`PublicHolidayService` shape, deliberately not `FastingCalendar`'s
post-first-frame `configure` — see the v24 note in
`docs/calendar-events-feature.md` §6.6). Initialize it at the same call sites
that initialize `EventOccurrenceService` (grep `EventOccurrenceService.getInstance`).

**Cascade**: `CalendarEventService.deleteById` / `deleteAll` extend their
existing single transaction with `_db.eventAbsenceDao.deleteForEvent(id)` /
`.deleteAll()`, then refresh the presence service the way
`_refreshOccurrences()` refreshes occurrences. Deleting an event is the
**only** thing that deletes absence rows in bulk — turning the toggle off or
changing the rule leaves them dormant (the stored delta is the durable record
of a deliberate act; flipping the toggle back on restores every mark).

## 4. Bloc wiring

Two events, registered and handled next to the v24 pair
(`calendar_bloc.dart:37-38`, `:230`, `:250`):

- `SetOccurrenceMissed(String eventId, DateTime day)`
- `ClearOccurrenceMissed(String eventId, DateTime day)`

Handlers call the service, then
`emit(current.copyWith(occurrenceRevision: current.occurrenceRevision + 1))`.
**No `_invalidateDayCache()`** — that cache answers "which events occur on
this day" and presence is not an input (decision 3). The revision is what
lets the `Equatable` state through and what `AgendaListView`'s identity memo
keys on; widen `occurrenceRevision`'s doc comment
(`calendar_state.dart:32-39`) to "per-occurrence overlay data (descriptions,
presence)". `UpcomingAgendaView` keeps forwarding it and must still never
rescan on it.

## 5. Rendering

One new constant, `CalendarColors.missedEventAlpha = 0.35`
(`lib/constants/calendar_colors.dart`) — matches the existing outside-month
fade literals; no other alpha constant exists in `lib/constants/`, so this is
the first named one. Use it everywhere below; no inline literals.

- **Grid bars** — `EventDayBarProvider.barsFor`
  (`day_bars_resolver.dart:108-126`) is the one hook with the full
  `(event, day)` key. `DayBarsResolver.defaults(l10n)` gains a
  `missedDisplay` parameter, supplied from `_appearance` where the page
  builds it (`calendar_page.dart:604`). In the loop:
  `appliesTo && isMissed` → hidden: skip before `bars.add` (a hidden bar must
  not consume a `maxDayBars` slot); faded:
  `color.withValues(alpha: missedEventAlpha)`. The provider contract ("pure &
  cheap, called for every visible cell on every rebuild") holds: two static
  map probes, no I/O.
- **Day summary rows** — `EventSummaryProvider.summaryFor`
  (`day_summary_resolver.dart:139-162`) stamps two new `DaySummaryEntry`
  fields: `missed`, `presenceTracked` (**both into `props`**, or the agenda's
  identity memo serves stale rows). `DaySummaryPanel` dims a missed row
  (wrap the tile content in `Opacity(missedEventAlpha)`) — always visible,
  decision 7.
- **Agenda** — `AgendaListView` respects the setting: hidden → drop missed
  occurrences when building rows inside `_rowsFor`; faded → dim the row.
  `missedDisplay` joins the `_rowsFor` memo key (`agenda_list_view.dart:104-118`)
  alongside `occurrenceRevision`, which presence writes already bump.
- **Timeline** — `day_timeline_view.dart` blocks: hidden → skip the block;
  faded → wrap in `Opacity(missedEventAlpha)`.
- **Never** filter inside `CalendarBloc.eventsForDay`, `EventAgenda`
  scans, or `.ics` export — hidden is a render-time filter, or those surfaces
  silently disagree about what exists.

## 6. Marking UX

**Primary: the detail sheet** (`event_detail_sheet.dart`) — it already holds
the exact `(event, day)` pair (`widget.day`, `:58`) and a per-day callback
discipline. Add `void Function(DateTime day, bool missed)? onPresenceChanged`
(the `onOccurrenceChanged` shape, `:68-74`). When
`EventPresence.appliesTo(event) && onPresenceChanged != null`, render a
`SegmentedButton<bool>` — `eventPresencePresent` / `eventPresenceMissed` —
next to the date `_InfoRow` (`:325-328`), seeded from
`EventPresence.isMissed(event.id, widget.day)`. A discrete toggle needs no
debounce: fire the callback immediately with `HapticFeedback.lightImpact()`.
`_openDetailSheet` (`calendar_page.dart:106-149`) wires it to the bloc —
the `_dispatchOccurrenceResult` funnel pattern.

**Quick path: the day-panel row** (`day_summary_panel.dart:162-251`) — one
tap from the calendar. For entries with `presenceTracked`, replace the
decorative `chevron_right_rounded` in the trailing strip (`:215-241`) with an
`IconButton`: `Icons.event_busy_rounded` (tooltip `eventMarkMissed`) when
present, `Icons.event_available_rounded` (tooltip `eventMarkPresent`) when
missed. Replacing the chevron rather than adding a third widget keeps the
strip at two widgets max on phone width (the note button already claims one).
`DaySummaryPanel` is deliberately day-less: add an
`onToggleMissed(CalendarEvent event, bool missed)` callback that
`CalendarBottomPanel` binds with `loaded.selectedDay` — exactly how
`onShowEvent` gets its day (`calendar_bottom_panel.dart:197-198`).

No long-press or swipe affordances exist anywhere on these rows today; do not
introduce one for this.

## 7. Editor opt-in

`event_editor_sheet.dart`: a `Card` + `SwitchListTile` — the
count-occurrences block's shape verbatim (`:1723-1737`) — titled
`eventTrackPresence` with subtitle `eventTrackPresenceDesc`. Placement: end of
the **When** section after both branches (not inside the recurring spread),
gated `if (_ruleHasManyOccurrences)` (`:716`) so specific-dates participates
(decision 4). State `_tracksPresence` seeded from `initialEvent`; save-time
mirror follows the sibling flags (`:1086-1091`):
`tracksPresence: _ruleHasManyOccurrences && _tracksPresence`. Switching a
tracked event to one-time therefore writes the flag off while its absence
rows stay dormant; switching back re-offers the toggle with every mark intact
once re-enabled.

## 8. Settings

Copy the `calendarMarkerStyle` path end-to-end:

1. `settings_keys.dart`: `calendarMissedDisplay = 'calendar_missed_display'`,
   `defaultCalendarMissedDisplay = 'faded'`.
2. `calendar_appearance.dart`: `enum CalendarMissedDisplay { faded, hidden }`
   with `fromName(String?)` falling back to `faded`; field `missedDisplay` on
   `CalendarAppearance` — constructor, `copyWith`, `props`.
3. `settings_service.dart`: `getCalendarMissedDisplay()` /
   `setCalendarMissedDisplay()` (`:463-477` shape); one line in
   `getCalendarAppearance()` (`:715-726`).
4. `calendar_settings_page.dart`: a `SettingsEntry` in the **Events** section
   (`_buildEventsSection`, `:771` — it only matters for events, and it sits
   naturally beside the per-occurrence-descriptions switch) wrapping a
   `SegmentedButton<CalendarMissedDisplay>` with `showSelectedIcon: false`;
   `onSelectionChanged` does the exact three-step
   `_onHapticFeedback(); setState(copyWith); await _settings?.set…` order.
   `keywords: [eventTrackPresence, eventPresenceMissed]` so settings search
   finds it. One line in `_resetToDefaults()`.

## 9. Localization

All three ARB files together, then `flutter gen-l10n` and check
`untranslated.txt`. `@` metadata blocks in `app_en.arb` only.

| Key | en | de | ro |
| --- | --- | --- | --- |
| `eventTrackPresence` | Track presence | Anwesenheit erfassen | Urmărește prezența |
| `eventTrackPresenceDesc` | Mark the days you skip. The event keeps one description for every day. | Markiere ausgelassene Tage. Die Beschreibung gilt für jeden Tag. | Marchează zilele sărite. Descrierea rămâne aceeași pentru fiecare zi. |
| `eventPresencePresent` | Present | Anwesend | Prezent |
| `eventPresenceMissed` | Missed | Verpasst | Ratat |
| `eventMarkMissed` | Mark as missed | Als verpasst markieren | Marchează ca ratat |
| `eventMarkPresent` | Mark as present | Als anwesend markieren | Marchează ca prezent |
| `calendarMissedDisplayTitle` | Missed days | Verpasste Tage | Zile ratate |
| `calendarMissedDisplayDesc` | How missed days of a tracked event appear in the calendar | Wie verpasste Tage eines erfassten Termins im Kalender erscheinen | Cum apar în calendar zilele ratate ale unui eveniment urmărit |
| `calendarMissedDisplayFaded` | Faded | Abgeblendet | Estompat |
| `calendarMissedDisplayHidden` | Hidden | Ausgeblendet | Ascuns |

No plurals needed.

## 10. Backup & restore

`BackupService` (`lib/services/backup_service.dart`) — **additive key, no
version bump** (`'version'` stays 7; the v24 comment at `:107-111` states the
rule: bump only when an existing field changes meaning).

- Export: `'eventAbsences': EventPresenceService.exportData()` — **live rows
  only, no CRDT fields**: `{eventId, dayMs, createdAtMs, updatedAtMs}`
  (epoch-ms ints, the `eventOccurrences` shape minus `description`). The
  app's standing rule is that backups are not a sync channel: `BackupService`
  already excludes tombstones and CRDT identity for notes/folders
  (`backup_service.dart:40-55`), and identity is regenerated on restore.
- Import: after categories and events, through
  `EventAbsenceDao.importAbsence` — preserves `createdAt`/`updatedAt` from
  the backup (falling back to `DateTime.now()` when absent), stamps fresh
  HLC / `db.deviceId` / `version 1`, skips malformed rows individually.
  Tombstones therefore do not round-trip a backup — a restore is a fresh
  start, exactly as for notes.
- **The strand rule** (`:367-372` precedent): an *absent* `eventAbsences` key
  is not a no-op when `calendarEvents` was present — call
  `clearAllForImport()`, because the event import wipes and reinserts and
  stale absences would strand against unrelated event ids.

The notes `.zip` archive (`ImportExportService`) carries no calendar data —
untouched, `archiveVersion` stays 1. `.ics` export is untouched (decision 3;
RFC `EXDATE`/`STATUS:CANCELLED` mean "does not occur", which is not what
missed means).

## 11. Tests

- `test/database/schema_parity_test.dart` — a second frozen-DDL test for
  `calendar_event_absences` (exact nine-column set, `notnull = 1` on every
  column **except `deleted_at`**, defaults `version = 1` / `is_deleted = 0`,
  PK ordinals `event_id → 1`, `day → 2`), the `:64-93` shape. The
  table/index scrape tests pass via the `@DriftDatabase` registration.
- `test/database/query_plan_test.dart` — the `unmark` UPDATE and
  `deleteForEvent` must `SEARCH calendar_event_absences` via the composite
  PK, never `SCAN` (`:145` twin).
- `test/database/query_count_test.dart` — extend "deleting an event cascades
  in one statement per table" (`:114`): seed absence rows, assert
  `counter.matching('calendar_event_absences')` has length 1.
- `test/services/event_presence_service_test.dart` (new, against
  `NativeDatabase.memory()` like the database suite): mark → `isMissed` true,
  row has `version 1`, a non-empty HLC, `device_id = 'test-device'`; unmark
  keeps the row (count unchanged) with `is_deleted = 1`, `deleted_at` set,
  `version 2`, facade cleared; re-mark resurrects — `is_deleted = 0`,
  `deleted_at` NULL again, `version 3`, `created_at` unchanged; marking an
  already-live day and un-marking a never-marked day are complete no-ops (no
  version churn); `getActive()` filters tombstones; export omits tombstones
  and CRDT fields; import preserves `createdAt`/`updatedAt` but stamps fresh
  identity; facade republish bumps `EventPresence.revision`; `reset()`
  clears singleton + facade; `clearAllForImport` empties table and facade;
  event delete hard-cascades absences — tombstones included — in one
  transaction.
- Bloc: a focused test (fakes, the `test/bloc/sync_bloc_test.dart` pattern)
  asserting `SetOccurrenceMissed` bumps `occurrenceRevision` and leaves the
  day cache warm (same day queried before/after hits the memo).
- `CalendarMissedDisplay.fromName` falls back to `faded` on unknown input;
  `CalendarEvent` codec round-trips `tracksPresence` and defaults it to
  `false` when the backup key is absent.

## 12. Execution order

1. Schema: `database_schema.dart` → migration → table file → DAO →
   `@DriftDatabase` → `build_runner`.
2. `CalendarEvent.tracksPresence` + service codec/export/import.
3. `EventPresenceService` + `EventPresence` facade + delete cascades.
4. Bloc events/handlers + `occurrenceRevision` doc widening.
5. The three ARB files + `flutter gen-l10n`.
6. `CalendarMissedDisplay` + settings keys/service/page.
7. Rendering: bars provider, `DaySummaryEntry` fields, panel, agenda,
   timeline.
8. Detail sheet control + page wiring.
9. Day-panel quick toggle.
10. Editor opt-in switch.
11. Backup key + strand rule.
12. Tests.

## 13. Verification

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
Get-Content untranslated.txt      # no new event*/calendar* key listed
dart analyze lib
flutter test test/database
flutter test test/services/event_presence_service_test.dart
flutter test
flutter run -d windows
```

Manual: create a daily event with Track presence on; mark today missed from
the detail sheet → bar fades; toggle the setting to Hidden → bar disappears,
day panel still shows the faded row with the restore icon; un-mark from the
row → bar returns; agenda and timeline agree in both modes; count labels
unchanged by marking; delete the event → absences gone (re-create with same
title shows nothing stale); switch databases → no presence bleed-through;
backup → restore round-trips live marks (an un-marked day stays unmarked);
restore a pre-feature backup → no marks, no errors.

## 14. Risks

1. **Phase-02 handoff** — cloud-sync phase-02 is renumbered to v27 (its doc
   is amended alongside this roadmap). What it still owes this table:
   `owner_id` (added to events and absences together, backfilled at first
   sign-in), the `keyLastEventAbsenceHlc = 'last_event_absence_hlc'`
   watermark on `SyncDao`, `getAbsencesSince`/`mergeAbsence` in the
   `NoteDao.getNotesSince`/`mergeNote` shape, and pulls that republish the
   `EventPresence` facade + bump `occurrenceRevision` (never the day cache).
   The asymmetry is deliberate and documented on both sides: occurrence
   *descriptions* stay device-local, absence *marks* sync.
2. **Hidden-mode leakage** — the moment a "missed" check lands in
   `eventsForDay`, `EventAgenda` scans, or `.ics`, the surfaces disagree
   about existence and the day cache needs invalidation on every mark.
   Render-time only, forever.
3. **`props` omissions** — `DaySummaryEntry.missed`/`presenceTracked` and
   `CalendarAppearance.missedDisplay` are Equatable inputs; missing one means
   stale rows behind the agenda's identity memo or a dropped state emit.
4. **Editor mirror semantics** — writing
   `_ruleHasManyOccurrences && _tracksPresence` on save silently clears the
   flag when a tracked event is edited to one-time. Accepted for consistency
   with `retroactive`/`countOccurrences`; the rows survive, only the opt-in
   needs re-ticking.
5. **Date normalization** — `day` must be date-only UTC at every write and
   probe, or facade lookups miss by timezone. This is the third private
   `_dateOnlyUtc`; keep it identical to
   `event_occurrence_service.dart:239-245` rather than inventing a fourth
   shape.
6. **Backup strand rule** — forgetting the absent-key `clearAllForImport()`
   call leaves absences pointing at ids from a previous database after a
   restore.
7. **Tombstones accumulate** — no purge job exists anywhere in the app
   (notes' tombstones live forever too). Growth is bounded by days actually
   toggled; accepted, and any retention policy is an app-wide decision, not
   this feature's.
8. **The HLC clock is per-`AppDatabase` and not persisted** — the logical
   counter resets on every launch and database switch; ordering rests on the
   wall clock. An inherited app-wide property; do not "fix" it for absences
   alone.

---

## Deferred, not planned here

Recorded so they are not re-derived:

- **Adherence stats** ("went 22/26 this month", streaks). Cheap on top of
  this schema: expand `occursOn` over a month, subtract `isMissed`, count
  only days ≤ today. Natural homes: a chip in the detail sheet's upcoming
  section or a day-panel header line. Worth its own small design pass.
- **Attendance-based count labels** (a missed visit not advancing the
  `countOccurrences` number). Deliberately out (decision 3) — it would make
  labels depend on presence data and re-number history on every toggle.
- **Richer statuses** (partial, late). A `status` column on
  `calendar_event_absences` is additive later; row-presence semantics were
  chosen so the binary case never pays for it.
- **Per-event display override** (this event hidden, that one faded). The
  global setting ships first; an override column is additive if ever wanted.
- **Presence on one-time events.** An event that fires once has nothing to
  track — the gate excludes it on purpose.
- **Marking future dates** works implicitly (a planned skip renders faded
  ahead of time); no special casing, and none should be added.
- **Delta feeds** (`getAbsencesSince` / `mergeAbsence`) and the sync
  watermark. Pure additions to a schema already shaped for them; they belong
  to phase-02's gateway work, not here.
