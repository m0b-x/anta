# Description Scope Roadmap — ANTA

**Status: shipped (2026-08-16).** Everything below is implemented; this file
is the design record. Running behaviour: `docs/calendar-events-feature.md`
(schema-v28 addendum) and the calendar bullets in `COPILOT_CONTEXT.md`.
Verified at ship time: `dart analyze lib` clean; full `flutter test` suite
green (284 passed, benchmarks skipped); `flutter gen-l10n` clean in
en/de/ro.

**Deviations from the plan as written:**

1. The settings-page removal (decision 5) shipped with the **data** layer,
   not the UI layer — deleting the service's `setEnabled` hard-broke the
   page, and a broken intermediate build serves no one. Same end state.
2. `EventOccurrenceDao.getAll()` was removed outright rather than kept
   beside `getActive()` — the template (`EventAbsenceDao`) has no `getAll`,
   and `exportData` needs the filtered read anyway.
3. `upsert`'s insert branch relies on the column defaults for
   `isDeleted`/`deletedAt` (the explicit clears live on the update branch,
   where the resurrect case exists) — the `CalendarEventDao.upsert` shape.
4. The v26→v27 migration test group now reads via untyped `customSelect` —
   the typed mapper demands every current column and broke when v28 added
   one; untyped reads are immune to every future column.
5. The v27 absence-cascade verification (decision 8) found **no
   regression** — `deleteById` already tombstoned absences.
6. A stale editor comment claiming `OccurrenceDescriptions.enabled` "is
   safe to read synchronously" was rewritten — it named a deleted API.

The plan as written follows. Two changes that finish what v24 started:

1. **Per-occurrence descriptions become a per-event choice.** The global
   `eventPerOccurrenceDescriptions` setting retires; each recurring event
   carries its own `per_occurrence_descriptions` flag (the `tracks_presence`
   twin). One gym log can keep a different note per day while the weekly
   standup keeps one shared description that updates everywhere — side by
   side.
2. **`calendar_event_occurrences` becomes CRDT-shaped** (schema **v28**, the
   v27 playbook) — the last per-day user-data table without merge metadata.
   Cloud-sync phase-02's "occurrences stay device-local" decision is
   reversed: per-day text is user data on par with absence marks, and it
   syncs. Phase-02 renumbers to **v29**.

No transport ships here. No `owner_id`, no delta feeds, no gateway.

---

## Context

v24 shipped per-occurrence descriptions behind one global switch because the
per-event home didn't exist yet. It does now: v26 built exactly this shape
for presence (`tracksPresence` + `EventPresence.appliesTo(event)`), and v27
built the CRDT playbook for a populated table (`DEFAULT ''` identity +
backfill). This change is those two patterns applied to descriptions —
and it deletes a settings indirection users had to discover before the
feature did anything.

### Decisions taken

1. **Flag on the event**: `per_occurrence_descriptions INTEGER NOT NULL
   DEFAULT 0` on `calendar_events`; domain field
   `CalendarEvent.perOccurrenceDescriptions` (default false — constructor,
   `copyWith`, `props`); the four service codec lines mirror
   `tracksPresence` exactly (`is bool ? Value(...) : const Value.absent()`
   on import, so pre-v28 backups land at the column default).
2. **The gate moves into the facade.**
   `OccurrenceDescriptions.appliesTo(event)` becomes
   `event.perOccurrenceDescriptions && event.rule is! OneTimeRecurrence` —
   the `EventPresence.appliesTo` shape. Because `descriptionFor` calls
   `appliesTo` internally, the detail sheet, day-panel badge, agenda
   narrowing and both row surfaces update with **zero widget edits**. The
   facade's `enabled` getter and `updateCache`'s `enabled:` parameter are
   deleted.
3. **Migration backfill is settings-driven and capability-preserving.** The
   v28 step reads `user_settings` for the literal key
   `'event_per_occurrence_descriptions'` (bools are stored as
   `'true'`/`'false'`; the `_migrateV17ToV18` precedent reads settings from
   a migration). Exactly when the stored value is `'true'`:
   `UPDATE calendar_events SET per_occurrence_descriptions = 1 WHERE
   rule_kind != 'oneTime' AND is_deleted = 0`. Rationale: a global-ON user
   had the scope control on *every* repeating event, so every repeating
   event keeps it — observable behaviour and capability surface both
   preserved; they can now turn individual events off. Global off/absent →
   nothing flips; dormant rows stay dormant exactly as they render today.
   The migration uses the frozen string literal, so the `SettingsKeys`
   constants can be deleted outright.
4. **No archive heuristic.** The flag was never in
   `BackupService._exportSettings`'s allowlist, so no existing backup
   carries the intent — an archive that never recorded it cannot be mined
   for it. Pre-v28 backups restore with every flag off and rows imported
   dormant (re-enabling an event brings its days back; nothing is lost).
   Post-v28 backups carry the flag per event. Backup version stays 7.
5. **The setting retires completely**: the two `SettingsKeys` constants +
   doc block, the settings-page entry/state/reset lines and its
   `EventOccurrenceService.getInstance()` load, and the service's whole
   flag half (`_enabled`, `enabled`, `setEnabled`, `_readEnabled`, the two
   post-import re-reads and the publish-flag-with-data rationale in the
   class doc — the settings-replay coupling they solved dies with the
   flag). The orphaned `user_settings` row is harmless and stays.
6. **Occurrences get the five CRDT columns, v27-style** — populated table,
   so `DEFAULT ''` on `hlc_timestamp`/`device_id` + a
   `WHERE hlc_timestamp = ''` identity backfill (one statement, one shared
   HLC), `version DEFAULT 1`, `is_deleted DEFAULT 0`, nullable
   `deleted_at`. Drift declaration matches (`withDefault`). No new index —
   the composite PK covers, and the table is loaded once.
7. **"Reset this day" becomes a tombstone.** The v24 invariant transforms:
   *a **live** row always wins, including when `''`; reset **tombstones**
   the row and never writes `''`*. Observable semantics are unchanged
   (tombstone = no override = template renders, badge disappears), but the
   reset now survives a future merge instead of being pushed back by the
   partner. Re-setting a description resurrects the same row
   (`created_at` intact) — `upsert` goes read-then-write with the explicit
   `isDeleted: false` + `deletedAt: null` on the update branch (the v27
   resurrection guard).
8. **The event-delete cascade tombstones occurrences too.** v27 left them
   hard ("device-local by phase-02 decree") — that premise dies with this
   change, so all three tables now tombstone together on a single-event
   delete: event (`softDeleteById`) + absences (`tombstoneForEvent`) +
   occurrences (new `tombstoneForEvent`), one transaction, one statement
   each. Verify absences already tombstone in that transaction (v27 shipped
   it); if a hard `deleteForEvent` call is found there instead, that is a
   v27 regression — fix it in the same change and record it. Hard variants
   (`deleteForEvent`, `deleteAll`) stay for the wipe/import paths, which
   remain hard forever (the resurrection trap).
9. **Editor reads the draft, not the row.** The sheet's two
   `OccurrenceDescriptions.enabled` reads become a local
   `_perOccurrenceDescriptions` state field — otherwise toggling the
   switch would not reveal the scope control until after Save. A private
   `_scopeGateOpen` (= `_ruleHasManyOccurrences && _perOccurrenceDescriptions`)
   backs `_scopeControlVisible`, `_resolveOccurrenceOutcome`, and the
   generalized `_syncScopeToRule` guard, so flipping the switch off
   mid-edit parks the day text exactly as flipping to one-time does today
   — the field must never show a day's text while the control explaining
   it is hidden.
10. **The l10n keys are reused, re-subjected.** The switch takes over
    `eventPerOccurrenceDescriptions` / `…Desc`; the Desc's first sentence
    changes from "Repeating events keep…" to "This event keeps…" in all
    three locales (second sentences stay verbatim). `eventTrackPresenceDesc`
    loses its now-conditional second sentence ("The event keeps one
    description for every day") in all three locales.

---

## Files

**New**: `test/database/event_occurrence_crdt_test.dart`,
`test/services/event_occurrence_service_test.dart`

**Modified**: `lib/database/migrations/database_schema.dart`,
`database_migrations.dart`, `lib/database/tables/calendar_events_table.dart`,
`event_occurrences_table.dart`, `lib/database/database.g.dart` (generated),
`lib/database/daos/event_occurrence_dao.dart`,
`lib/services/calendar_event_service.dart`,
`lib/services/event_occurrence_service.dart`,
`lib/constants/occurrence_descriptions.dart`,
`lib/constants/settings_keys.dart`, `lib/models/calendar_event.dart`,
`lib/widgets/event_editor_sheet.dart`, `lib/pages/calendar_settings_page.dart`,
`lib/l10n/app_{en,de,ro}.arb`,
`test/database/{schema_parity,query_plan,query_count}_test.dart` (+ the
migration group in `calendar_event_crdt_test.dart` if that is where v27→v28
fits better)

**Untouched**: `event_detail_sheet.dart`, `day_summary_resolver.dart`,
`event_agenda.dart`, `agenda_list_view.dart`, all bloc files (decision 2
makes the gate swap invisible to them), `backup_service.dart` except the
occurrence-import re-read removal riding along in the service,
`event_absence_dao.dart` (unless the v27 cascade verification in decision 8
finds a regression), `.ics`, presence, categories.

---

## 1. Migration v28

`database_schema.dart`: `v28DescriptionScope = 28`, `currentVersion = 28`.

`_migrateV27ToV28`, after `_migrateV26ToV27`, doc comment in the v27 style
(what changed, why defaults preserve behaviour, the settings-driven
backfill rule, idempotency sentence). Two guarded blocks:

**(a) The event flag** — `PRAGMA table_info(calendar_events)` guard:

```sql
ALTER TABLE calendar_events ADD COLUMN per_occurrence_descriptions INTEGER NOT NULL DEFAULT 0
```

then the settings-driven backfill (decision 3): `customSelect` of
`SELECT value FROM user_settings WHERE key = 'event_per_occurrence_descriptions'`;
only when the value is exactly `'true'`:

```sql
UPDATE calendar_events SET per_occurrence_descriptions = 1
  WHERE rule_kind != 'oneTime' AND is_deleted = 0
```

Idempotent: the column guard covers re-runs (the UPDATE re-applying is
harmless but the guard skips the whole block anyway).

**(b) Occurrence CRDT columns** — `PRAGMA table_info(calendar_event_occurrences)`
guard, five ALTERs copied line-for-line from the v27 shape (`DEFAULT ''` on
identity, `version DEFAULT 1`, `is_deleted DEFAULT 0`, nullable
`deleted_at`), then the identity backfill:

```sql
UPDATE calendar_event_occurrences SET hlc_timestamp = ?, device_id = ?
  WHERE hlc_timestamp = ''
```

bound to `_db.generateHlc()` / `_db.deviceId`.

**Drift declarations**: `CalendarEvents` gains `perOccurrenceDescriptions`
(`boolean().withDefault(const Constant(false))`); `EventOccurrenceDescriptions`
gains the five-column block in the **v27 events shape** (`withDefault(const
Constant(''))` on identity — not the absence table's default-less shape;
this is the second populated-table conversion). Then `build_runner`.

## 2. DAO — `EventOccurrenceDao`

`EventAbsenceDao` is the template; `description` is the one extra column.
All stamping lives here (`db.generateHlc()`, `db.deviceId`, read-then-write
`version + 1`):

- `getActive()` — replaces `getAll()` as the service's load
  (`WHERE is_deleted = 0`).
- `upsert(entry)` — read-then-write via a `_byKey(eventId, day)` helper:
  miss → INSERT `version 1` + fresh identity; hit → UPDATE with `createdAt`
  masked, fresh HLC/device, `version + 1`, **explicit `isDeleted: false` +
  `deletedAt: null`** (re-describing a reset day resurrects its row,
  `created_at` intact).
- `tombstone(eventId, day)` — the `unmark` shape ("reset this day"):
  `is_deleted → 1`, `deleted_at`/`updated_at` → now, fresh identity,
  `version + 1`; absent or already-tombstoned → no-op.
- `tombstoneForEvent(eventId)` — the absence `tombstoneForEvent` shape: one
  bulk `customUpdate`, shared HLC, `Variable<DateTime>` binds,
  `WHERE event_id = ? AND is_deleted = 0`.
- `importOccurrence(entry)` — the `importAbsence` convention: caller's
  `created_at`/`updated_at` preserved, identity stamped **fresh**,
  `isDeleted false`/`deletedAt null` forced.
- `deleteFor` / `deleteForEvent` / `deleteAll` stay as the hard variants
  (wipe/import paths only); doc comments updated to describe the split.

## 3. Service + facade

`EventOccurrenceService`:
- Flag half deleted (decision 5). `_load()` reads `getActive()`;
  `_publish()` passes only `byEvent`.
- `setDescription` → `upsert` (unchanged surface); `clearDescription` →
  `tombstone` (was `deleteFor`); `importData` → `importOccurrence` per row
  (wipe first, unchanged); the two `_readEnabled` re-reads and their doc
  comments disappear.

`OccurrenceDescriptions` (facade): `enabled` deleted;
`updateCache({required byEvent})`; `appliesTo(event)` gains the event-flag
read (decision 2). Class doc rewritten — reuse `EventPresence`'s "opt-in
per event" wording; the live-row invariant re-stated per decision 7.

`CalendarEventService.deleteById` / `deleteAll` transactions: the occurrence
line flips to `tombstoneForEvent` in `deleteById` (hard in `deleteAll`);
the stale cascade doc comment (written for a hard-deleted parent) is
rewritten. Codec: the four `perOccurrenceDescriptions` twin lines
(export map, import `Value.absent()` fallback, `_rowToEvent`,
`_eventToCompanion`).

## 4. Editor

`event_editor_sheet.dart`:
- State: `bool _perOccurrenceDescriptions = false;` seeded
  `initial?.perOccurrenceDescriptions ?? false` beside `_tracksPresence`.
- `bool get _scopeGateOpen => _ruleHasManyOccurrences && _perOccurrenceDescriptions;`
  consumed by `_scopeControlVisible` (replacing the
  `OccurrenceDescriptions.enabled` term), `_resolveOccurrenceOutcome`
  (replacing its raw re-check), and `_syncScopeToRule`'s early-out
  (replacing bare `_ruleHasManyOccurrences`).
- The switch: in the Details section, between the group header's spacer and
  the `_buildDescriptionField` call — `if (_ruleHasManyOccurrences) ...[`
  `Card` + `SwitchListTile`, `Icons.event_note_outlined` (freed from the
  settings tile), title/subtitle = the reused keys, `onChanged: (v) =>
  setState(() { _perOccurrenceDescriptions = v; if (!v) _syncScopeToRule(); })`
  `]`. Above the field it governs — the sheet's own "a control that mutates
  content above itself reads as if nothing happened" rule.
- Save mirror on both paths:
  `perOccurrenceDescriptions: _ruleHasManyOccurrences && _perOccurrenceDescriptions`
  (the sibling-flag shape). Turning the switch off and saving writes the
  flag off and does **not** write the parked day text; rows stay dormant.

The settings page loses everything listed in decision 5; the detail sheet
needs no edit (decision 2).

## 5. Localization

All three ARBs together, then `flutter gen-l10n`. No new keys; three value
edits ×3 locales:

- `eventPerOccurrenceDescriptionsDesc` — first sentence re-subjected:
  en "This event keeps its own description for each day. The event's
  description becomes the template every day starts from." / de "Dieses
  Ereignis behält für jeden Tag eine eigene Beschreibung. Die Beschreibung
  des Ereignisses wird zur Vorlage, mit der jeder Tag beginnt." / ro "Acest
  eveniment păstrează câte o descriere pentru fiecare zi. Descrierea
  evenimentului devine șablonul de la care pornește fiecare zi."
- `eventTrackPresenceDesc` — second sentence dropped: en "Mark the days you
  skip." / de "Markiere ausgelassene Tage." / ro "Marchează zilele sărite."
- `eventPerOccurrenceDescriptions` (title) and the scope-control strings
  stay verbatim — they already read event-scoped.

## 6. Tests

- **Migration group** (in `calendar_event_crdt_test.dart`'s style, wherever
  v27→v28 fits): rebuild the v27 shapes, run
  `runMigrations(…, 27, 28)` — global `'true'` flips live recurring events
  only (a one-time event, a tombstoned event and a `'false'`/absent setting
  all stay 0); occurrence rows get real identity (`hlc_timestamp != ''`);
  re-run is idempotent.
- **`schema_parity_test.dart`** — the occurrence frozen-DDL test's expected
  set gains the five columns; the blanket `notnull` loop becomes the
  `deleted_at`-aware ternary; identity `dflt_value` asserts `''` (the v27
  events-test model, not the absence model). The events-table test uses
  `containsAll`, so `per_occurrence_descriptions` needs no edit there —
  add one `containsAll` entry anyway for the new column.
- **`query_plan_test.dart`** — "reset this day" tombstone is a PK `SEARCH`
  (`containing: 'UPDATE'`); the occurrence tombstone cascade is a prefix
  `SEARCH`.
- **`query_count_test.dart`** — the cascade test keeps "one statement per
  table" (UPDATE satisfies the count); occurrence `upsert` == 2 statements.
- **New `test/database/event_occurrence_crdt_test.dart`** — the
  `calendar_event_crdt_test` mirror: set → `version 1` + identity; edit →
  `version 2`, `created_at` kept; reset → tombstone (row survives,
  `getActive` drops it); re-set → resurrect (`version` continues,
  `created_at` intact, `deleted_at` NULL); double-reset / reset-of-nothing
  no-ops; `tombstoneForEvent` shared-HLC bulk; `importOccurrence` preserves
  audit timestamps, stamps fresh identity.
- **New `test/services/event_occurrence_service_test.dart`** (the
  `event_presence_service_test` shape with `forTesting` if needed —
  mirror `EventPresenceService.forTesting`): facade publish excludes
  tombstones; `appliesTo` follows the event flag (on/off, one-time
  excluded); `clearDescription` tombstones and the badge-driving
  `descriptionFor` falls back to the template; export omits tombstones and
  CRDT fields; import round-trip; `clearAllForImport`; the event-delete
  cascade leaves occurrence tombstones (not hard-deleted rows).
- `dart analyze` guards the settings-page and service removals.

## 7. Execution order

1. Schema constants → migration → both table declarations → `build_runner`.
2. `EventOccurrenceDao` rework + `CalendarEventService` cascade flip +
   codec lines + model field.
3. Service + facade flag removal (gate swap lands here).
4. Data-layer tests.
5. Editor switch + gate rewiring; settings-page removal; ARB value edits +
   `flutter gen-l10n`.
6. Full suite.

## 8. Verification

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
dart analyze lib
flutter test test/database
flutter test
flutter run -d windows
```

Manual: an event with the switch on keeps distinct day texts (scope control
visible in the editor from a day); a second event with it off edits one
shared description everywhere; toggling the switch off mid-edit swaps the
field back to the template and Save loses nothing (toggle back on — the
day text returns); "reset this day" still falls back to the template and
removes the badge; the settings page no longer shows the global entry;
after upgrading with the old global setting on, every repeating event still
shows its scope control; restore a pre-v28 backup → events import with the
switch off, and enabling one restores its imported day texts.

## 9. Risks

1. **The editor reading the saved row instead of the draft** — the switch
   would appear dead until Save. Decision 9's `_scopeGateOpen` over local
   state is the guard; the mid-edit flip test is manual (no widget tests).
2. **A missed `enabled` reader** — there are exactly two real ones, both in
   the editor sheet; `dart analyze` catches them the moment the getter is
   deleted.
3. **Backfill over-flagging** — scoping to `rule_kind != 'oneTime' AND
   is_deleted = 0` keeps one-time and deleted events off; specific-dates
   events are correctly included (they participate in the v24 gate).
4. **The reset-day invariant flip** — any code path still hard-deleting a
   single occurrence row would silently break future sync; after this
   change `deleteFor` has no live caller (wipes use `deleteForEvent` /
   `deleteAll`), and the new service test pins tombstone behaviour.
5. **Three-table cascade consistency** — decision 8's verification step:
   if v27's absence tombstone cascade is not actually in the `deleteById`
   transaction, fix and record it here rather than shipping a third state.
6. **Dormant-row surprise** — an event whose flag is off but which has
   rows renders the template everywhere by design; the rows are the user's
   data and return with the flag. This is v24's reversibility rule, kept
   verbatim.
7. **Old backups restore with flags off** (decision 4) — accepted; the
   alternative (guessing intent from an archive that never carried it)
   invents data.

---

## Deferred, not planned here

- **Transport** for occurrences (`getOccurrencesSince` / `mergeOccurrence`,
  watermark `keyLastEventOccurrenceHlc = 'last_event_occurrence_hlc'`) —
  phase-02 (v29), alongside absences and events.
- **`calendar_categories` CRDT-ification** — still a phase decision.
- **Per-event presence-display override** and the other presence deferrals
  — unchanged.
- **Tombstone GC / retention** — still app-wide.
