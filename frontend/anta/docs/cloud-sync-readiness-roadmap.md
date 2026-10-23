# Cloud Sync Readiness Roadmap — ANTA

**Status: planned, 2026-10-23. Nothing here is implemented.** The phase
between Phase 01 (pairing, shipped 2026-08-17) and Phase 02 (transport) of
`docs/cloud-sync-roadmap.md`. It owns migration **v43** (schema is at v42,
`lib/database/migrations/database_schema.dart:4`). Decisions D1–D14 await the
owner's letters; the recommended default is marked on each. The recipe is the
one `docs/calendar-cloud-readiness-roadmap.md` used for `calendar_events` in
v27, repeated for the tables and write paths it did not cover.

**The line this phase draws:** it ends where `FirestoreSyncGateway` begins. No
row crosses the wire here. Everything below is local — schema, write paths,
the clock, the seams — so that Phase 02 can be built against a fake gateway
and switched to Firestore last.

## Contents

1. Why this phase exists
2. Decisions for the owner (D1–D14)
3. What syncs — table classification
4. Slices R1–R7
5. Must not change
6. Risk register
7. Carried into Phase 02
8. Deferred
9. How to run this
10. Definition of done

---

## 1. Why this phase exists

Two asks arrived on 2026-10-23 that the August design does not cover, plus
debt that accrues daily until transport exists.

**The asks.** (a) The *same* Google account on several devices — notes and
calendar identical on a phone and a tablet. (b) Sharing *selected* events
with another account, not only the whole calendar. The August remote shape
hangs every data collection under `pairs/{pairId}` (roadmap "Remote shape");
a second device of one account has nothing to sync from, and a per-event
share has no field to live in. Both need a decision before Phase 02, not a
retrofit after it (D1, D2).

**The debt** (facts verified 2026-10-23, `file:line` against the tree):

- Three tables that must sync carry no CRDT columns: `calendar_categories`
  (`lib/database/tables/calendar_categories_table.dart`), `counters`,
  `counter_values`. Every event references a category by id; a calendar
  synced without its categories points at nothing on the other device.
- Nothing records *what changed*. The push side of Phase 02 would have to
  scan every table for `hlc > last`, and a remote row merged with its remote
  HLC would be scanned straight back out — an echo. `SyncDao`'s
  `last_*_hlc` keys (`lib/database/daos/sync_dao.dart:11-15`) have no caller.
- The clock is not persisted: `HybridLogicalClock` is seeded from the wall
  clock with counter 0 at every launch (`lib/database/crdt/hlc.dart:6-8`,
  `lib/database/database.dart:116`). A device whose clock is set back issues
  timestamps older than rows it already pushed, and loses every merge it
  should win.
- Hard deletes remain on synced tables: the `deleteAll` family behind
  "Delete all events" (`lib/database/daos/calendar_event_dao.dart:175`, with
  its cascade in `lib/services/calendar_event_service.dart:172-181`) and the
  import wipes in every service's `importData`; chunk trimming in
  `ContentChunkDao.saveContent` (`content_chunk_dao.dart:239`).
- The dormant merge methods (`NoteDao.mergeNote` `note_dao.dart:838`,
  `FolderDao.mergeFolder` `folder_dao.dart:669`, `ContentChunkDao.mergeChunk`
  `content_chunk_dao.dart:301`) compare HLCs correctly but never touch the
  FTS index (`notes_fts`, maintained by hand — `database_indexes.dart:268-270`,
  `note_dao.dart:293-352`). A pulled title change would be unsearchable.
- `FolderDao.softDeleteFolderWithDescendants` binds `deleted_at` and
  `updated_at` as `millisecondsSinceEpoch` in raw SQL
  (`folder_dao.dart:548-549`, `:567-568`) where Drift stores unix seconds —
  the exact bug `calendar_event_dao.dart:146-150` warns about. Harmless to
  the UI today; a sync engine reads `deletedAt`.
- No shared stamping helper exists: each DAO inlines
  `hlcTimestamp / deviceId / version` at every write (the audit found no
  `stamp`/`crdt` helper). Stamping is nevertheless complete on the fifteen
  CRDT tables except by design (raw `insertNote`/`insertFolder` whose callers
  stamp; the merge methods). The outbox below needs one path, so the helper
  comes first.
- `docs/calendar-events-feature.md:33` and `:42` still promise "no sync" and
  "no account, no cloud".

What is already right and must stay so: all synced tables have text ids
except four composite keys (`event_absences`, `event_occurrence_descriptions`,
`event_skips` on `{eventId, day}`; `counter_values` on `{counterId, noteId}`);
built-in category ids are fixed names (`lib/constants/calendar_categories.dart:18`
`id => kind.name`), so two devices seed identical rows and merge trivially;
`alert_registrations` is a device-local mirror of the OS scheduler
(`alert_registrations_table.dart:1-24`) and stays out of sync by design; the
cache hooks a merge must call exist and are public
(`NoteRepository.invalidateAll` `note_repository.dart:627`,
`FolderRepository.invalidateAll` `folder_repository.dart:519`,
`CalendarEventService.reload` `calendar_event_service.dart:95`,
`EventOccurrenceService.reload` / `EventPresenceService.reload`,
`FolderSearchService.updateIndex` `folder_search_service.dart:598`,
`AlertScheduler.reconcileAll` `alert_scheduler.dart:337`), with one exception:
`CalendarBloc._invalidateDayCache` (`calendar_bloc.dart:581`) is private.

---

## 2. Decisions for the owner (D1–D14)

Answer with letters ("D1 A, D2 A, …"). A is the recommended default.

**Letters so far (2026-10-23):** the owner's go on slices R1–R3 takes the
decisions those slices embody as A — D4, D5, D7, D8, D12, D14. Still open:
D1, D2, D3, D6, D9, D10, D11, D13.

- **D1 — Where a row lives remotely.** **A:** an *owner space*,
  `users/{uid}/spaces/{spaceId}/{table}/{rowKey}`: each owned row exists
  exactly once; sharing is a grant on the space or on a row, checked by the
  security rules, never a second copy. **B:** the August shape — everything
  under `pairs/{pairId}`, with "my own devices" modelled as a self-pair and
  shared rows written twice. A halves the writes for shared rows, gives the
  same-account case a home, and makes a per-event share a field plus a
  filtered query. It changes the *placement* decided in the connections
  design (decision 9), not its "one calendar partner" policy — see D-notes
  in §7.
- **D2 — First transport target.** **A:** same-account multi-device first
  (one identity, no consent, no partner rules), then sharing. **B:** partner
  sharing first, as the August ladder reads. A exercises the whole engine on
  the simplest rules.
- **D3 — Local database ↔ remote space.** **A:** every local database can be
  bound to one space (`sync_space_id` in `user_settings`, per database like
  the pairing keys, excluded from backups); the default database creates the
  account's first space on first sign-in; a second device offers "download a
  space into a new database" or "bind this database to a space". **B:** only
  the default `gym_notes` database ever syncs. A costs two settings keys now
  and a picker in Phase 02.
- **D4 — What syncs.** **A:** the classification in §3. **B:** move rows
  between the sync and local columns as you see fit; the slices adapt.
- **D5 — How the engine learns what changed.** **A:** a `sync_outbox` table,
  written in the *same transaction* as every write to a synced table by one
  shared helper, keyed `(table, rowKey)` so repeated saves of one note
  coalesce into one entry. **B:** per-table `hlc > last_pushed` scans plus an
  origin flag to suppress echoes. A is what keeps a heavy editing day at a
  few hundred Firestore writes, gives a true "N pending" status, and makes
  "a write that skipped the push" structurally impossible.
- **D6 — Clock persistence.** **A:** persist the last issued HLC in
  `sync_metadata` and seed the clock from `max(stored, wall)` at launch.
  **B:** leave as is. A is a handful of lines and removes the clock-rollback
  failure.
- **D7 — Two devices edit the same note.** **A:** whole-note last-writer-wins
  by HLC, and the losing body is kept as a conflict copy in the same folder
  (title "`<title>` — conflict `<device>` `<date>`"). **B:** pure LWW, loser
  discarded. A costs nothing here (the merge method returns the overwritten
  row; the engine files the copy); B loses text silently.
- **D8 — Counter values.** **A:** `counter_values` gains the CRDT columns and
  merges LWW per `(counterId, noteId)`; two devices incrementing the same
  counter offline lose one increment. **B:** a per-device increment ledger
  (PN-counter). A matches every other table; B is deferred until the loss is
  seen.
- **D9 — Restoring a backup onto a synced database.** **A:** restore
  *unbinds*: the import clears `sync_space_id` and the outbox, runs the hard
  wipe it runs today, and the Sharing page then offers "upload as a new
  space" or "merge into space X". **B:** restore then diff against the
  remote and tombstone what the backup lacks. A turns the documented
  resurrection trap (Phase 02 doc, "Tombstone conversion") into one explicit
  step; B silently deletes the other device's unsynced work.
- **D10 — Settings.** **A:** `user_settings` never syncs in this generation;
  every setting is per database today (`SettingsService` writes only
  `user_settings`, `settings_service.dart`). Known cost: the per-note money
  currency and markdown-bar assignment live in settings, so they do not
  follow a note to the other device (§8). **B:** sync an allowlist of keys.
- **D11 — Alerts on synced events.** **A:** every signed-in device arms its
  own registrations from the synced alert definitions (`event_alerts`,
  `calendar_category_alerts`, `event_digests` all carry CRDT columns) — the
  phone and the tablet both ring. **B:** a per-device "ring here" toggle,
  default on. A now; B is a later setting.
- **D12 — `owner_id`.** **A:** add `owner_id TEXT NULL` to all eighteen
  synced tables in v43, backfilled to the local uid on first sign-in (Phase
  02), NULL meaning "mine, not yet signed in". **B:** add it in Phase 03 to
  the tables sharing needs. A is one migration and one parity-test update
  instead of two; the owner colour and the consent rule both read it.
- **D13 — "Delete all events".** **A:** becomes a tombstoning wipe of *own*
  rows across the five event tables with one shared HLC; the dialog copy
  (`app_en.arb:804`, "Permanently remove every event you created") stays
  true. **B:** stays a hard local wipe and never propagates. A is what the
  Phase 02 doc already owes.
- **D14 — The note on the wire.** **A:** one document per note — title,
  body, metadata — never per chunk; the 10 000-character chunks
  (`app_constants.dart:68`) stay a local storage detail, and the chunk
  hard-delete in `saveContent` and the chunk-less folder cascade stop
  mattering. Notes above Firestore's 1 MiB document cap are refused with a
  visible reason (none exist in practice). **B:** chunk documents keyed by
  index as Phase 03 wrote. A removes a class of merge bugs the Phase 03 doc
  itself names ("interleaving chunks from two devices").

---

## 3. What syncs — table classification

| Table | Class | Key | What this phase adds |
| --- | --- | --- | --- |
| `folders` | sync | text id | `owner_id`; helper + outbox; `deleted_at` unit fix |
| `notes` | sync (whole note, D14) | text id | `owner_id`; helper + outbox; merge re-indexes FTS, returns the loser (D7) |
| `content_chunks` | local storage of the note body | text id | `owner_id` for parity only; nothing else |
| `calendar_events` | sync | text id | `owner_id`; helper + outbox; tombstoning wipe (D13) |
| `event_absences` | sync | `{eventId, day}` | `owner_id`; rowKey `eventId\|dayEpochMs` |
| `event_occurrence_descriptions` | sync | `{eventId, day}` | same |
| `event_skips` | sync | `{eventId, day}` | same |
| `event_templates` | sync | text id | `owner_id`; helper + outbox |
| `event_alerts` | sync (definitions) | text id | `owner_id`; helper + outbox |
| `event_digests` | sync | text id | same |
| `calendar_category_alerts` | sync | text id | same |
| `calendar_filter_presets` | sync | text id | same |
| `overview_views` | sync | text id | same |
| `vocabularies`, `vocabulary_items` | sync | text id | same |
| `calendar_categories` | sync | text id (built-ins fixed) | **five CRDT columns**, `owner_id`, tombstone delete, stamped `setHidden`/reorder/`seedMissing` |
| `counters` | sync | text id | **five CRDT columns**, `owner_id`, tombstone delete cascading to values |
| `counter_values` | sync (D8) | `{counterId, noteId}` | **five CRDT columns**, `owner_id`, rowKey `counterId\|noteId` (`noteId == ''` for the global value, kept) |
| `alert_registrations` | device-local | `osId` | nothing — one device's OS scheduler |
| `sync_metadata` | device-local | key | gains `last_hlc` (D6) |
| `sync_outbox` | device-local, new | `{table, rowKey}` | the change feed (D5) |
| `user_settings` | device-local (D10) | key | gains `sync_space_id`, `sync_space_bound_at` (D3), excluded from backups |
| `public_holidays` | device-local in v1 | `{date, nameKey}` | nothing; the profile is a setting; custom and suppressed days are §8 |

The rowKey is also the remote document id, so a key must be deterministic
and filesystem-plain: text ids as they are; composite keys joined with `|`
and the day as epoch-ms, the way user-data dates already cross the backup
format (roadmap "Architecture stance").

---

## 4. Slices R1–R7

Each slice: one implementer, one reviewer, the gate (`verify` skill: `dart
analyze lib`, the whole `flutter test`, `build_runner` after a schema change,
`gen-l10n` only if an ARB changes — none is expected), then a check-in with
the uncommitted file count and a ready commit. Order: R1 → R2 → R5 → R3a →
R3b → R4 → R6 → R7. R5 sits early because it is small and touches the same
core files as R2.

### R1 — Record and pointers (docs only)

- This file; the master ladder row and status line in
  `docs/cloud-sync-roadmap.md`; the entry in
  `.claude/skills/anta-context/references/docs-index.md` — done by the lead
  on 2026-10-23.
- `docs/calendar-events-feature.md:33` "general-purpose calendar (no
  meetings, no invites, no sync)" → "general-purpose calendar (no meetings,
  no invites; sync is being added in phases — `docs/cloud-sync-roadmap.md`)";
  `:42` "with no account, no cloud, and survives device wipe via the JSON
  backup" → "without an account; an optional Google sign-in adds sync
  (`docs/cloud-sync-roadmap.md`); it survives device wipe via the JSON
  backup either way". Done by the lead on 2026-10-23 (the "single device"
  bullet became "your own devices").
- `references/sync-and-accounts.md` gains a "Readiness (v43)" bullet once R2
  ships, written by the lead from the as-built migration.

### R2 — Migration v43

Scope: the three tables become CRDT-shaped, `owner_id` lands everywhere, the
outbox table exists.

- **Declarations** (`lib/database/tables/`): the five CRDT columns on
  `calendar_categories`, `counters`, `counter_values` with the
  `withDefault(const Constant(''))` idiom for `hlc_timestamp`/`device_id`
  (`calendar_events_table.dart:131` precedent — SQLite's `ADD COLUMN NOT
  NULL` needs a default, and the declaration must match the migrated shape);
  `owner_id TEXT NULL` on all eighteen synced tables; a new
  `sync_outbox(table_name TEXT, row_key TEXT, hlc TEXT, op TEXT, enqueued_at
  INTEGER, PRIMARY KEY(table_name, row_key))`.
- **Migration** `_migrateV42ToV43` (`database_migrations.dart`, after `:1708`;
  constant `v43SyncReadiness` in `database_schema.dart`): every `ALTER`
  guarded with `PRAGMA table_info`; backfill one `UPDATE` per new-CRDT table
  stamping `generateHlc()` + `deviceId`, `version = 1`, as `_migrateV26ToV27`
  does (`database_migrations.dart:995`); `owner_id` stays NULL; partial
  indexes `WHERE is_deleted = 0` for the three tables, `DROP INDEX IF EXISTS`
  before replacing any full index (the v27 create-vs-migrate lesson).
- **DAOs of the three tables** (`counter_dao.dart:24-49`,
  `calendar_category_dao.dart:56-65`): every write stamps; `deleteCounter`
  tombstones the counter and its values with one shared HLC
  (`EventAbsenceDao.tombstoneForEvent` shape, `event_absence_dao.dart:181`);
  category delete tombstones (built-ins are only ever hidden —
  `category_service.dart:311`); every read path filters `is_deleted = 0`;
  `seedMissing` (`category_service.dart:128`) stamps the rows it seeds.
- **Backup**: live rows only, format version stays 7
  (`backup_service.dart:129`); import of the three tables keeps its
  wipe-and-insert semantics and stamps fresh HLCs like every other table
  (`calendar_event_dao.dart:194-201` precedent).
- **Tests**: `test/database/schema_parity_test.dart` to v43 including the
  partial indexes; `calendar_category_crdt_test.dart` and
  `counter_crdt_test.dart` modelled on `calendar_event_crdt_test.dart` (real
  v42→v43 migration group: backfill, index swap, idempotence; a
  write-over-tombstone resurrects).
- Skills: `drift-migrations` (persistence rules, the atomic-step contract),
  `anta-context`.

**As built (2026-10-23, one implementer, one independent reviewer, one fix
pass; the review found no data loss, crash or persisted-data break).**
Deviations from the plan above, each sound and reversible on its own:

- The folder-cascade `deleted_at` fix moved here from R3a so the binding fix
  and the repair ship together; the repair covers every folder and note row
  above 10^12 (live rows and `updated_at` too — no seconds value can reach it).
- `CounterService` tracks dirty `(counterId, noteId)` pairs, not whole notes;
  `CounterDao.upsertValue` is read-then-write, writes nothing when the value is
  unchanged, resurrects a tombstoned value, and drops the write when the parent
  counter is tombstoned; `deleteCounter` clears the counter's pending dirty
  entries. One HLC per user action: `insertCounterWithValue` and
  `setCounterPinned(positions:)`. `updateCounter` / `updateCategory` skip
  no-op edits; reorders write only rows that moved; `nextSortOrder` counts
  tombstones (gaps are harmless, `reorder` makes live rows dense).
- Built-ins can never be tombstoned: `CalendarCategoryDao.softDeleteById`
  returns `bool` and refuses built-in ids (by flag or by id),
  `CategoryService.deleteCategory` refuses before its transaction, import
  normalises `isBuiltIn` from the seed list regardless of the archive flag,
  and `seedMissing` resurrects a tombstoned built-in (`DoUpdate … where
  isDeleted`) keeping the user's name, colour and order.
- Indexes: `idx_counter_values_counter` is now
  `(counter_id, is_pinned DESC, position) WHERE is_deleted = 0` (the ordered
  read otherwise sorted in a temp B-tree); new `idx_counters_active` and
  `idx_calendar_categories_active`; v43 drops and recreates through the
  shared creators, so fresh and migrated shapes agree (`upgrade_chain_test`).
- Tests: `counter_crdt_test`, `calendar_category_crdt_test`,
  `folder_tombstone_time_test`, `test/services/counter_service_test.dart`,
  `test/database/support/v42_shapes.dart` (the real v42 shapes the parity and
  CRDT suites migrate from), query-plan tests on every counter and category
  read path. Older migration suites now run to `currentVersion`.
- Left as found, recorded in §8: the folder cascade's `customUpdate` passes no
  `updates:` (no stream notification, as before); `CounterValueRow` reaches
  the per-note bloc; fresh installs carry a `CHECK (is_deleted IN (0,1))`
  that migrated tables lack (v27 precedent); `getValuesForNote` scans.

### R5 — Clock persistence (D6)

- `generateHlc()` (`database.dart:218`) writes the issued value to
  `sync_metadata['last_hlc']` inside the caller's transaction when there is
  one, else directly; `AppDatabase.getInstance` seeds the clock from the
  stored value so the first `now()` is above it even when the wall clock is
  behind. `now()` (`hlc.dart:22-37`) already never goes below
  `_lastPhysicalTime` and bumps the counter instead; what is missing is a
  constructor that sets `_lastPhysicalTime`/`_logicalCounter` from a stored
  `HlcTimestamp` — today's ctor takes only `initialCounter` (`hlc.dart:6-8`).
- Tests in `test/database/hlc_test.dart`: wall behind stored → monotonic;
  restart preserves order; a `receive()` of a far-future remote is clamped
  per the existing drift guard.
- Small enough for the implementing session's main thread or an
  `implementer` at `medium`.

### R3a — The write helper and the outbox, browser-side tables

- **Helper** on `AppDatabase` (`lib/database/crdt/`): `stampLocal(table,
  rowKey, {tombstone})` returns `(hlc, deviceId)` and upserts the outbox row
  in the current transaction; `enqueueMany(table, rowKeys, hlc)` for the
  bulk SQL-expression paths (`note_dao.dart:643-649`, `folder_dao.dart:393-399`
  idiom); `SyncOutboxDao` with `pending()`, `count()`, `ackThrough(table,
  rowKey, hlc)` (compare-and-delete, so a write that lands during a push
  survives) and `clear()`.
- **Convert** every stamping write on `folders`, `notes`, `content_chunks`
  (parity only), `counters`, `counter_values`, `vocabularies`,
  `vocabulary_items` to the helper — the audit's list: `note_dao.dart` 153,
  202, 245, 355, 384, 424, 455, 619/635, 658, 944, 981, 994;
  `folder_dao.dart` 139, 182, 230, 255, 301, 325, 354, 383, 408/424, 449,
  505; `vocabulary_dao.dart` 52, 100, 172/276, 205; the R2 counter and
  category writes.
- **Merge methods** gain `origin` (remote merges never enqueue and call
  `hlc.update`, which they already do); `mergeNote` re-indexes FTS through
  the existing `_updateFtsIndex` (`note_dao.dart:316`) and returns the
  overwritten local row (`null` when it inserted) for D7.
- ~~Fix `folder_dao.dart:548-549` and `:567-568`~~ — done in R2 together
  with the stored-value repair.
- **Tests**: per table, one mutation → exactly one outbox row with the row's
  HLC and `op`; a second mutation of the same row coalesces; a remote merge
  → zero rows; a tombstone records `op = 'tombstone'`; the usage probe — 200
  simulated saves of one note leave one outbox row.
- Skills: `anta-context`, `flutter-principles`.

### R3b — The helper and the outbox, calendar-side tables

- Convert the audit's stamping writes on `calendar_events` (51, 86, 153),
  `event_absences` (76, 124, 181), `event_skips` (61, 102, 159),
  `event_occurrence_descriptions` (38, 78, 108), `event_templates` (37, 76),
  `event_alerts` (66, 162), `event_digests` (31, 72, 94, 127),
  `calendar_category_alerts` (40, 128), `calendar_filter_presets` (37, 78,
  123), `overview_views` (33, 72, 106) to the helper; rowKeys for the
  composite tables as §3.
- Same test shape as R3a per table; the shared-HLC cascades
  (`calendar_event_service.dart:155-159`) enqueue one row per affected row.
- Skills: `anta-context`, `calendar-events` (invariants of the event tables).

### R4 — Wipes, imports and the unbind (D9, D13)

- `CalendarEventService.deleteAll` (`calendar_event_service.dart:172-181`)
  becomes `tombstoneAll` across the five event DAOs with one shared HLC,
  enqueued; rows with a foreign `owner_id` are skipped (none exist yet). The
  dialog copy stays.
- `SyncSuspension` (`lib/services/sync_suspension.dart`): a static scope
  (`isSuspended`, `run()`); `BackupService.importFromJson`
  (`backup_service.dart:331`) runs inside it, clears the outbox and the
  binding keys first (the unbind), then performs today's hard wipes
  (`:482-603` and each service's `importData`) unchanged. The folder-archive
  import (`ImportExportService`) appends rows with fresh ids and needs no
  suspension.
- Tests: after a restore the outbox is empty and the binding keys absent;
  the tombstoning wipe leaves `getAll()` empty, `exportData()` rowless and
  the tombstones present; a pinned test that `_exportSettings`'s allowlist
  (`backup_service.dart:222-272`) never carries a pairing or sync key.
- Skills: `anta-context`, `calendar-events`.

### R6 — Engine seams, no network

- `lib/services/sync/sync_gateway.dart`: `SyncGateway` interface
  (`pushBatch(List<SyncEnvelope>)`, `pullSince(table, hlc)`, `ack`) and the
  `SyncEnvelope` value (table, rowKey, hlc, op, `exportData()` map — the
  backup serializers are the wire format, roadmap stance); a
  `FakeSyncGateway` under `test/support/`. Firestore types appear nowhere.
- `SyncStatus` value (pending count from the outbox, last push, paused
  reason) surfaced by `SyncBloc` states, extending
  `test/bloc/sync_bloc_test.dart`'s fake-service pattern.
- A public `CalendarBloc` event for an external change that runs
  `_invalidateDayCache` and bumps `occurrenceRevision`;
  `AlertReconcileReason.sync`; `SettingsKeys.syncSpaceId` /
  `syncSpaceBoundAt` next to the pairing keys (`settings_keys.dart:376-398`).
- Skills: `anta-context`, `calendar-events`, `flutter-principles`.

### R7 — Gate and device pass

- The full gate; then `qa-runner` on the emulator's QA database: folder and
  note CRUD, labels, reorder; global and per-note counters; category create,
  hide, delete; "Delete all events"; backup export → import round trip;
  vocabulary; `qa errors` clean. Nothing visible should have changed — the
  pass proves it.

---

## 5. Must not change

- The `gym_notes` directory and the `device_id` file
  (`database.dart:178-190`).
- Backup format version 7, live rows only, no identity fields; absent keys
  take column defaults; `importData`'s wipe stays hard, inside the
  suspension; folders and notes still import as copies with fresh ids
  (`backup_service.dart:122-124`).
- The HLC string encoding (`hlc.dart:110-113`, zero-padded hex, lexicographic
  order equals chronological) — every `since` comparison depends on it.
- Soft-delete semantics on the fifteen CRDT tables; positions and sort
  preferences; `noteId == ''` for global counter values; pinned counters.
- `AuthService` stays off the `DatabaseLifecycle` reset contract; the new
  outbox DAO and any sync singleton go on it (`database_lifecycle.dart:59`).
- `SyncAvailability.isSupported` remains the single platform gate; nothing
  in this phase consults the platform.
- The pairing keys stay out of backups (allowlist, `backup_service.dart:222`);
  the new binding keys join them there.
- No user-visible behaviour or string changes; `untranslated.txt` stays
  empty without a gen-l10n run.

---

## 6. Risk register

- **High — a write that commits without its outbox row.** That is the silent
  divergence the roadmap's register already names. Mitigation: the helper is
  the only way to obtain an HLC for a synced-table write (`generateHlc()`
  becomes private to the helper after R3b), plus the per-table suites.
- **High — the unbind on restore is forgotten.** A restore that keeps its
  binding re-pushes every re-created row as new and duplicates the other
  device. R4's test pins it.
- **Medium — the three new partial indexes.** Same create-vs-migrate trap as
  v27; the parity test must scrape index *definitions*, not names only.
- **Medium — tombstone growth.** Nothing purges tombstones in this phase; a
  purge after acknowledged push is §8. Rows are small; the free tier's 1 GiB
  is not in reach.
- **Medium — the `deleted_at` unit fix changes stored values** for
  descendants tombstoned before v43 (they hold milliseconds). A one-off
  repair in the v43 migration (`deleted_at > 10^12 → deleted_at / 1000` on
  tombstoned folders and notes) keeps the engine's reads honest; include it.
- **Low — composite rowKeys.** `|` and epoch-ms are safe in Firestore ids;
  the test suite round-trips every key through parse.
- **Low — `seedMissing` stamping on every launch.** It inserts only missing
  built-ins; stamping does not turn it into a write per launch. Verify with
  the statement-count test pattern in `test/database/`.

---

## 7. Carried into Phase 02 (not this phase)

- The remote shape under D1: `users/{uid}/spaces/{spaceId}/{table}/{rowKey}`,
  a `spaces/{spaceId}` document with members and grants, rules for owner and
  grantee, the per-event share field for selected events. The connections
  design's "one designated calendar connection" (decision 9) becomes a
  product choice rather than a merge necessity once a row has one home;
  revisit it there.
- The engine: drain the outbox in Firestore batches, back off on
  `resource-exhausted` into `SyncStatus.paused` until the daily reset, pull
  through filtered listeners (`hlc > last`), `HybridLogicalClock.receive()`
  on every pulled row, merge, then the invalidation hooks listed in §1 and
  `AlertScheduler.reconcileAll(sync)`.
- Space binding UI on the Sharing page; `owner_id` backfill on first
  sign-in; the conflict copy (D7) from the merge method's returned loser.
- The Phase 02/03 docs' migration numbers: Phase 02 may need **no** migration
  once `owner_id` ships in v43; Phase 03's `share_pair_id` becomes a grant on
  the space (v44). Renumber when those docs are revised.
- The push relay Worker and deep links (`docs/cloud-sync-connections-design.md`).

---

## 8. Deferred

- Per-device increment ledger for counters (D8 B).
- A per-device "ring here" toggle for alerts (D11 B).
- Settings sync, and in particular the per-note money currency and markdown
  bar assignment, which are note data stored as settings — candidates for
  `notes` columns before they can follow a note.
- Custom and suppressed public holidays (`public_holiday_service.dart:173-222`).
- Tombstone purge after acknowledged push plus a grace period.
- Tombstoning the chunks in `softDeleteFolderWithDescendants` and
  `saveContent` — moot under D14 A; revisit only if D14 B is chosen.
- Dialog copy for "Delete all events" naming the other devices.
- Desktop sign-in: relax the gate for macOS (the official plugin supports
  it), a loopback OAuth flow for Windows.
- Found by the R2 review, pre-existing: `softDeleteFolderWithDescendants`'s
  `customUpdate` passes no `updates:` so no stream fires (same as before);
  `CounterValueRow` (now carrying CRDT columns) reaches the per-note bloc;
  fresh installs carry a `CHECK (is_deleted IN (0,1))` migrated tables lack;
  `getValuesForNote` scans `counter_values` (no `note_id` index).

---

## 9. How to run this

- **This record** was written on Fable 5.1; the Fable session ends at the
  owner's letters for D1–D14. Record the letters at the top of §2 with the
  date.
- **Implementing sessions run on Opus 5.5 at `high`.** Per slice: one
  `implementer` (default effort; `medium` for R5 and R1's placement) briefed
  with goal, the `file:line` facts of its slice section, §5, the tests it
  must add and the gate; then one `reviewer` against this record, findings
  CONFIRMED or PLAUSIBLE; R7 to `qa-runner`; R1's rewording to
  `docs-writer`. Load `delegation` before spawning; `verify` for the gate.
- **Skills per slice** are named in §4. Read this record by section — the
  implementer gets its slice and §5, never the whole file.
- **Check in at every slice boundary** with the number of uncommitted files
  and a ready commit; the owner commits to `main`. R2's `build_runner` output
  is committed with R2.
- After R2 ships, add the v43 facts to
  `.claude/skills/anta-context/references/sync-and-accounts.md` and the
  `drift-migrations` persistence rules in the same change.

---

## 10. Definition of done

- All eighteen synced tables carry the five CRDT columns and `owner_id`;
  parity test green at v43; the three new tables have `*_crdt_test` suites.
- Every write to a synced table goes through the helper and leaves exactly
  one coalesced outbox row; remote-origin merges leave none; the usage probe
  holds.
- No hard delete on a synced table outside the import path, which runs
  suspended and unbound.
- The clock survives a restart and a wall-clock rollback.
- `SyncGateway`, `FakeSyncGateway`, `SyncStatus`, the external-change event
  and the binding keys exist with tests; no Firestore type outside the
  pairing gateway.
- `dart analyze lib` clean, the whole suite green, the device pass green with
  no visible change, the master roadmap and the feature doc updated.
