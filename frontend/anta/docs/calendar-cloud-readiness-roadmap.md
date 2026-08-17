# Calendar Cloud Readiness Roadmap — ANTA

**Status: shipped (2026-08-16).** Everything below is implemented; this file
is the design record. Running behaviour: `docs/calendar-events-feature.md`
(schema-v27 addendum) and the calendar bullets in `COPILOT_CONTEXT.md`.
Verified at ship time: `dart analyze lib` clean; full `flutter test` suite
green (252 passed, benchmarks skipped); `flutter gen-l10n` clean in en/de/ro.

**Deviations from the plan as written:**

1. Beyond plan: `calendar_event_crdt_test.dart` gained a real v26→v27
   migration group — it rebuilds the v26 table + full index, runs
   `DatabaseMigrations.runMigrations(…, 26, 27)`, and pins the identity
   backfill, the partial-index swap, and re-run idempotence (risk 3's
   upgrader divergence had no other coverage).
2. `upsert`'s **insert** branch stamps only HLC/device/version —
   `isDeleted`/`deletedAt` fall to the column defaults; the explicit clears
   live on the update branch, where the resurrect case exists.
3. The presence-service cascade test reproduces the service transaction
   inline — `CalendarEventService` has no `forTesting` seam and none was
   added for a test.
4. `reassignCategory`'s SET-clause column order follows `setNotePositions`
   (cosmetic).
5. `CalendarEventDao.deleteById` and `EventAbsenceDao.deleteForEvent` are
   now caller-less hard variants, retained per the `hardDeleteNote`
   precedent.
6. `AgendaListView` became a `StatelessWidget` — its memo state moved out
   entirely.
7. The agenda-rows test pins holidays with 2026-01-01 (the uninitialized
   fixed-date fallback); arbitrary dates resolve no holiday without a
   configured profile.
8. Two facade doc comments naming `AgendaListView` as the revision-memo
   owner were corrected to `UpcomingAgendaView` in the docs pass.

The plan as written follows. It set out three debts to clear before any
cloud phase touches the calendar:

1. **`calendar_events` is not CRDT-shaped** — every hard-deleted event
   destroys information no future migration can reconstruct, and no write
   stamps merge metadata. Schema **v27** fixes both, with zero transport.
2. **The agenda's panel-level count lies in hidden mode** — it counts
   scanned occurrences while `AgendaListView` drops hidden rows.
3. **The detail sheet's date row shows the series start**, not the
   occurrence day the sheet (and its presence toggle) is about.

No sync features ship here: no `owner_id`, no delta feeds, no gateway. Cloud
phase-02 (renumbered **v28**) keeps transport, backfill and consent.

---

## Context

Presence tracking (v26) made `calendar_event_absences` CRDT-shaped from
birth. Its parent table still hard-deletes: `CalendarEventDao.deleteById` is
a plain `DELETE`, `reassignCategory` stamps nothing, and `getAll()` has no
`is_deleted` concept. Until that changes, every day of normal use erases
merge history that phase-02 can never recover — this is the tech debt with a
daily interest rate, so it goes first, before transport exists.

The two UI items are presence-ship leftovers, both flagged in
`docs/presence-tracking-roadmap.md`'s deviations.

### Decisions taken

1. **`calendar_events` gains the five CRDT columns in v27** —
   `hlc_timestamp`, `device_id`, `version`, `is_deleted`, `deleted_at` —
   with one deliberate deviation from the notes declaration:
   `hlc_timestamp`/`device_id` are `withDefault(const Constant(''))` instead
   of default-less `text()()`, because SQLite's `ALTER TABLE … ADD COLUMN
   NOT NULL` demands a default on a populated table, and the Drift
   declaration must match the migrated shape. The migration **backfills real
   identity immediately** (one `UPDATE` stamping `_db.generateHlc()` +
   `_db.deviceId` on every existing row), and the DAO stamps every
   subsequent write — `''` never survives contact with a write path. Side
   benefit: `CalendarEventsCompanion.insert` call sites (test seeds) keep
   compiling.
2. **Single-event delete becomes a tombstone** (`softDeleteById`, the
   `NoteDao.softDeleteNote` shape). Its cascade flips with it: absences are
   **bulk-tombstoned** (`EventAbsenceDao.tombstoneForEvent`, one shared HLC,
   the `FolderDao.softDeleteFolderWithDescendants` idiom), occurrence
   descriptions stay **hard-deleted** — they are device-local by phase-02
   decree, carry no CRDT columns, and "delete this event" is exactly the
   deliberate act v24 says cascades. A remote resurrection (phase-02) brings
   the event back without its per-day texts; accepted for a device-local
   data class.
3. **Bulk wipes stay hard.** `deleteAll()` backs "Delete all events", whose
   copy promises "Permanently remove … can't be undone" — tombstoning it
   pre-transport would accumulate dead rows for zero benefit. `importData`'s
   wipe **must** stay hard forever (see the resurrection trap, risk 1).
   Phase-02 owes the synced-wipe story; its doc now says so.
4. **`upsert` becomes read-then-write** (the `EventAbsenceDao.markMissed` /
   `NoteDao.updateNote` idiom): miss → INSERT `version 1`; hit → UPDATE
   `version = existing + 1`, fresh HLC/device, `createdAt` masked, **and
   `isDeleted: false` + `deletedAt: null` written explicitly** — so writing
   an event over its own tombstone resurrects it instead of updating an
   invisible row. One extra SELECT per save on a table that writes at human
   speed.
5. **`reassignCategory` cannot read-then-write** (unbounded rows): it uses
   the SQL-expression idiom — one `customUpdate` with
   `version = version + 1`, one shared `generateHlc()`,
   `Variable<DateTime>` for `updated_at` (never raw millis — Drift stores
   unix seconds), and `AND is_deleted = 0` so it never touches tombstones.
6. **`getAll()` filters `is_deleted = 0`**, and because it is the single
   read path, the month grid, day panel, agenda, timeline, money refresh,
   `exportData()` and `.ics` all inherit the filter for free. The backing
   index becomes **partial** (`WHERE is_deleted = 0`, same
   `idx_calendar_events_start_date` name); the v27 migration must
   `DROP INDEX IF EXISTS` first or upgraders keep the full index while
   fresh installs get the partial one — create-vs-migrate drift the
   name-only parity scrape cannot see. The DAO predicate must restate the
   index's expression exactly (the `NoteDao` partial-index precedent).
7. **The domain model stays clean.** `CalendarEvent` gains nothing; CRDT
   lives at the row/DAO level only, exactly as `Note` (domain) vs `Note`
   (row) and `EventAbsenceRow` already work. Nothing above the DAO sees a
   tombstone. Backup shape unchanged, version stays 7 — live rows only,
   no identity fields (backups are not a sync channel).
8. **Agenda count = the rows actually built.** The row computation moves
   out of `AgendaListView` into a public pure builder; `UpcomingAgendaView`
   owns the memo (same six keys as today), derives the header count from
   the computed entry rows, and passes the rows down. One computation, one
   truth, exact in both modes, zero added passes. Semantic shift accepted:
   the count now counts **visible entries** (a day with two holidays counts
   two, hidden occurrences count zero) — which is what "N entries" claims.
9. **The day summary panel's count deliberately does not change.** That
   panel always shows missed rows (it is the toggle surface — presence
   decision 7), so `entries.length` already equals what is on screen.
   Internally consistent; not a bug.
10. **The detail sheet's date row shows `widget.day`** — the occurrence the
    sheet was opened for and the day the presence toggle directly beneath
    it marks. A recurring event whose series start differs gains one
    label-less `_InfoRow` — `Icons.event_repeat_rounded`,
    "Repeats since {date}" — placed **directly after the recurrence-pattern
    row** (pattern + anchor read as one cluster). One-time events render
    identically to today (`widget.day == startDate`).

---

## Files

**New**: `test/database/calendar_event_crdt_test.dart`,
`test/widgets/agenda_rows_test.dart`

**Modified**: `lib/database/migrations/database_schema.dart`,
`database_migrations.dart`, `database_indexes.dart`,
`lib/database/tables/calendar_events_table.dart`, `lib/database/database.g.dart`
(generated), `lib/database/daos/calendar_event_dao.dart`,
`event_absence_dao.dart`, `lib/services/calendar_event_service.dart`,
`lib/widgets/upcoming_agenda_view.dart`, `lib/widgets/agenda_list_view.dart`,
`lib/widgets/event_detail_sheet.dart`, `lib/l10n/app_{en,de,ro}.arb`,
`test/database/{schema_parity,query_plan,query_count}_test.dart`,
`test/services/event_presence_service_test.dart`

**Untouched**: `lib/models/calendar_event.dart` (decision 7), all bloc files,
`lib/pages/` (both fixes are widget-internal), `backup_service.dart`,
`import_export_service.dart`, `event_occurrences` table/DAO/service,
`calendar_categories` (its CRDT story is a phase decision, not taken here).

---

## 1. Migration v27

`database_schema.dart`: `v27CalendarEventsCrdt = 27`, `currentVersion = 27`.

`_migrateV26ToV27`, appended to `_migrations`, doc comment stating what
changed, why the defaults preserve pre-feature behaviour, and that it is
idempotent. Steps, in order:

1. `PRAGMA table_info(calendar_events)` guard, then five `ALTER TABLE`s:

```sql
ALTER TABLE calendar_events ADD COLUMN hlc_timestamp TEXT NOT NULL DEFAULT ''
ALTER TABLE calendar_events ADD COLUMN device_id TEXT NOT NULL DEFAULT ''
ALTER TABLE calendar_events ADD COLUMN version INTEGER NOT NULL DEFAULT 1
ALTER TABLE calendar_events ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0
ALTER TABLE calendar_events ADD COLUMN deleted_at INTEGER
```

2. Identity backfill — one statement, one migration-moment HLC shared by
   every pre-existing row (they were all "last modified locally" then):

```sql
UPDATE calendar_events SET hlc_timestamp = ?, device_id = ?
  WHERE hlc_timestamp = ''
```

   bound to `_db.generateHlc()` and `_db.deviceId`. The `WHERE` keeps the
   step idempotent.

3. `DROP INDEX IF EXISTS idx_calendar_events_start_date`, then
   `await DatabaseIndexes(_db).createCalendarIndexes();` (the v24→v25
   delegate-to-shared-definition idiom — never a private DDL copy).

`database_indexes.dart` — `createCalendarIndexes()` body becomes partial,
same name:

```sql
CREATE INDEX IF NOT EXISTS idx_calendar_events_start_date
  ON calendar_events(start_date) WHERE is_deleted = 0
```

**Drift declaration** (`calendar_events_table.dart`): the five columns —
`text().withDefault(const Constant(''))` ×2, `integer().withDefault(const
Constant(1))`, `boolean().withDefault(const Constant(false))`,
`dateTime().nullable()` — matching the migrated shape exactly (decision 1).
Then `dart run build_runner build --delete-conflicting-outputs`.

## 2. DAO — `CalendarEventDao`

All stamping lives here; the service never touches CRDT fields.

- `_byId(String id)` — private `getSingleOrNull` by PK.
- `upsert(entry)` — one transaction: `_byId`; null → `into().insert` with
  `hlcTimestamp: Value(db.generateHlc())`, `deviceId: Value(db.deviceId)`,
  `version: const Value(1)`; found → UPDATE writing the entry with
  `createdAt: const Value.absent()`, fresh HLC/device,
  `version: Value(existing.version + 1)`,
  `isDeleted: const Value(false)`, `deletedAt: const Value(null)`
  (resurrect-safety — decision 4).
- `softDeleteById(String id)` — the `softDeleteNote` shape: `_byId`; absent
  or already tombstoned → no-op; else UPDATE `is_deleted → 1`,
  `deleted_at → now`, `updated_at → now`, fresh HLC/device, `version + 1`.
- `deleteById` stays as the hard variant (the `hardDeleteNote` precedent —
  retained, currently caller-less), `deleteAll` stays hard (decision 3).
- `getAll()` — adds the `is_deleted = 0` predicate, constructed exactly as
  `NoteDao` does so the partial index matches.
- `reassignCategory(fromId, toId)` — one `customUpdate`:

```sql
UPDATE calendar_events SET category = ?, updated_at = ?, hlc_timestamp = ?,
  version = version + 1, device_id = ?
  WHERE category = ? AND is_deleted = 0
```

  `Variable<DateTime>` for `updated_at`, one `generateHlc()` for the batch,
  `updates: {calendarEvents}`. Signature/return unchanged.

`EventAbsenceDao` gains `tombstoneForEvent(String eventId)` — bulk UPDATE
(`is_deleted → 1`, `deleted_at`/`updated_at` as `Variable<DateTime>`, fresh
shared HLC, `version = version + 1`, `WHERE event_id = ? AND
is_deleted = 0`). `deleteForEvent` stays hard for the wipe paths; its doc
comment (whose "the parent event's own delete is hard today" premise dies
here) is rewritten to describe the split.

## 3. Service — `CalendarEventService`

- `deleteById(id)`: the transaction becomes `softDeleteById(id)` +
  `eventAbsenceDao.tombstoneForEvent(id)` +
  `eventOccurrenceDao.deleteForEvent(id)`; cache patch and the two facade
  refreshes (`_refreshOccurrences`, presence) unchanged in shape. The bloc's
  `_onDeleteEvent` flow — cache removal, `_invalidateDayCache()` — is
  untouched; nothing above the service can tell a tombstone from a delete.
- `deleteAll()` / `importData()` unchanged (hard wipes — decisions 3, risk 1).
- `exportData()`/`importData()` shapes unchanged; backup stays version 7.

## 4. Agenda count (fix A)

`agenda_list_view.dart`:

- `_AgendaRow`/`_AgendaHeaderRow`/`_AgendaEntryRow` become public top-level
  types (`AgendaRow`, `AgendaDayHeaderRow`, `AgendaEntryRow`), same fields.
- `_buildRows` becomes a public top-level pure function in the same file:

```dart
List<AgendaRow> buildAgendaRows({
  required List<EventOccurrence> occurrences,
  required List<DateTime> holidayDays,
  required AppLocalizations l10n,
  required bool showRecurrenceLabels,
  required CalendarMissedDisplay missedDisplay,
})
```

  identical body (hidden-drop, empty-day-header suppression, per-day count).
  Doc note: pure *given the `EventPresence`/`OccurrenceDescriptions`
  facades* — any memo over it must key `occurrenceRevision`.
- `AgendaListView` slims to a renderer: takes `rows` (plus `colorPalette`,
  the three callbacks, empty-state strings, `padding`); loses
  `occurrences`/`holidayDays`/`occurrenceRevision`/`missedDisplay`/
  `showRecurrenceLabels` and its entire memo state. Today/Tomorrow labels
  stay in its item builder (`dayHeaderLabel` calls `DateTime.now()` — it
  must not enter the pure function).

`upcoming_agenda_view.dart`:

- State gains the row memo, keyed on the same six fields the child used:
  `identical(occurrences)`, `identical(holidayDays)`, `localeName`,
  `showRecurrenceLabels`, `occurrenceRevision`, `missedDisplay`. Computed in
  `build` on key mismatch, exactly like the child did.
- The header (currently `_occurrences.length + _holidayDays.length`)
  becomes `rows.whereType<AgendaEntryRow>().length` fed to the same
  `daySummaryEntryCount` key — correct by construction in both modes.
- `AgendaListView` receives `rows`.

Performance is unchanged by design: same memo keys, same recompute triggers
(scan-identity changes and revision bumps), one row build instead of a
parent scan-count plus a child row build.

## 5. Detail sheet occurrence day (fix B)

`event_detail_sheet.dart`:

- The date `_InfoRow` formats **`widget.day`** (`DateFormat.yMMMMEEEEd`,
  unchanged format). The presence toggle stays directly beneath it — the
  adjacency is the point.
- Directly after the recurrence-pattern `_InfoRow`, gated
  `if (isRecurring && !dateOnlyEquals(widget.day, event.startDate))`:
  `_InfoRow(icon: Icons.event_repeat_rounded, text:
  l10n.eventDetailsSeriesStart(DateFormat.yMMMd(localeName)
  .format(event.startDate)))`. Compact `yMMMd` because the date is embedded
  in a sentence (the occurrence-chip precedent), unlike the bare long-form
  date rows.
- Both dates are date-only UTC already; plain `==`/`isAtSameMomentAs`
  suffices — no new normalization helper.

Row order after the fix: identity → **occurrence date** → presence toggle →
time → recurrence pattern → **series start (when it differs)** → end date →
priority → note → description → next occurrences.

## 6. Localization

One key, all three ARBs together, `@` metadata + `placeholders`
(`date`, String) in `app_en.arb` only; then `flutter gen-l10n`.

| Key | en | de | ro |
| --- | --- | --- | --- |
| `eventDetailsSeriesStart` | Repeats since {date} | Wiederholt sich seit {date} | Se repetă din {date} |

## 7. Tests

- `schema_parity_test.dart` — new test: the five `calendar_events` CRDT
  columns on a fresh install match the v27 shape — `notnull`, `dflt_value`
  (`''`, `''`, `1`, `0`), `deleted_at` nullable. (Create and migrate paths
  agree by construction; this pins the declared shape.)
- `query_plan_test.dart` — `:136` ("events are read in start-date order
  without sorting") must stay green through the partial index — it is the
  canary for a predicate/index mismatch. New: "tombstoning a single event
  is a primary-key update" (`containing: 'UPDATE'`, `SEARCH
  calendar_events`, no SCAN); "the absence tombstone cascade is a prefix
  search" (same shape against `calendar_event_absences`).
- `query_count_test.dart` — the cascade test's expectations become:
  `calendar_events` exactly 2 statements (one `isSelect` — the intended
  read; `StatementCounter` counts SELECTs), occurrences 1 (DELETE),
  absences 1 (UPDATE). New: `reassignCategory` over 20 seeded events issues
  exactly 1 statement; `upsert` issues exactly 2.
- New `test/database/calendar_event_crdt_test.dart` — insert stamps
  `version 1` + non-empty HLC + `device_id 'test-device'`; edit bumps to 2,
  preserves `created_at`, changes the HLC; `softDeleteById` tombstones
  (row survives, `is_deleted = 1`, `deleted_at` set, version bumped) and is
  a no-op when repeated or when the id is absent; `upsert` over a tombstone
  **resurrects** (`is_deleted` back to 0, `deleted_at` NULL); `getAll()`
  filters tombstones; `reassignCategory` bumps versions with one shared HLC
  and skips tombstoned rows.
- `event_presence_service_test.dart` — the event-delete cascade assertions
  flip: absences are now tombstoned (rows survive with `is_deleted = 1`,
  facade cleared), occurrences still hard-deleted; `deleteAll` still
  hard-cascades everything.
- New `test/widgets/agenda_rows_test.dart` — `buildAgendaRows` against
  `AppLocalizationsEn()`: hidden drops missed entries and suppresses a day
  header whose only entry was missed; faded keeps them; entry-row count is
  the header-count basis; holiday entries appear as entry rows.
- Fix B is formatting-only; the full suite + manual check cover it.

## 8. Execution order

1. Schema: constants → migration (ALTERs + backfill + index swap) → table
   declaration → `build_runner`.
2. `CalendarEventDao` (upsert stamping, `softDeleteById`,
   `reassignCategory`, filtered `getAll`) + `EventAbsenceDao.tombstoneForEvent`.
3. `CalendarEventService.deleteById` cascade flip.
4. Data-layer tests (§7 first five bullets).
5. Agenda extraction (§4) + its test.
6. Detail sheet (§5) + the ARB key + `flutter gen-l10n`.
7. Full suite.

## 9. Verification

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
dart analyze lib
flutter test test/database
flutter test
flutter run -d windows
```

Manual: delete an event → gone from grid/panel/agenda/timeline/`.ics` and
stays gone after an app restart (the filter, not the cache, is doing the
work); re-create one with the same title → fresh row, no stale marks;
restore a backup taken *before* the delete → the event returns (backups
carry live rows; the wipe clears tombstones); delete a category with events
→ events land in the target category, still visible; mark days missed,
switch the display setting to Hidden → the agenda header count equals the
rows shown; open a recurring event from a non-start day → the date row
shows that day, "Repeats since …" shows the anchor, and the presence toggle
sits under the day it marks.

## 10. Risks

1. **The resurrection trap.** `importData` wipes hard and re-inserts backup
   ids via `upsert`. If anyone ever "improves" that wipe into a tombstoning
   one, every re-imported id hits the UPDATE branch against a tombstone —
   without decision 4's explicit `isDeleted: false` write, the row imports
   invisible. The explicit write is the belt; the hard wipe is the
   suspenders. Keep both forever.
2. **Partial-index predicate mismatch** — if the DAO predicate doesn't
   restate the index expression, SQLite silently falls back to a scan +
   temp B-tree; `query_plan_test.dart:136` is the tripwire, not a
   formality.
3. **Upgrader index divergence** — skipping the `DROP INDEX` leaves old
   installs on the full index (`IF NOT EXISTS` is satisfied) while fresh
   installs get the partial one; the name-only parity scrape cannot detect
   it. The DROP in the migration is mandatory.
4. **`''` identity is transitional, not valid.** It exists only between the
   ALTER and the backfill inside one migration run. If a future code path
   ever observes `hlc_timestamp == ''`, something skipped the DAO.
5. **`reassignCategory` had no guard test** — forgetting its stamping would
   break nothing today and corrupt merge ordering in phase-02. The new
   statement-count test pins it.
6. **The count's meaning shifts** (decision 8): visible entries, holiday
   entries counted individually. Matches the label; note it in release
   notes if the number moves for someone.
7. **`deleteAll` stays hard** — a post-transport synced wipe would
   resurrect from the partner device; phase-02's doc now owns that
   conversion decision explicitly.
8. **HLC clock persistence** remains app-wide debt (counter resets per
   launch; ordering rests on the wall clock) — phase-01's concern, not
   patchable here for one table.

---

## Deferred, not planned here

- **`calendar_categories` CRDT-ification** — phase-02 currently implies
  categories stay local (unknown ids render as `other`). A deliberate
  decision for that phase, not a default.
- **`getAll(includeDeleted:)`** — nothing needs tombstones above the DAO
  yet; phase-02's `getEventsSince` reads them unfiltered, the notes way.
- **Tombstone GC / retention** — still an app-wide decision.
- **`deleteAll` tombstone conversion** — phase-02, with transport in hand.
