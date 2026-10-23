# Cloud Sync Readiness Roadmap — ANTA

**Status: DONE 2026-10-23 — every slice built and reviewed.** R1, R2, R3a
and R3b committed (`729a25f`, `14c9250`, `596998d`, `4fd26aa`); R5, R6 and
R4 built the same day, each with one implementer and one independent
reviewer (fixes folded into the next slice's run), uncommitted when this line
was written — the owner commits; R7's gate is green (9,584 tests) and the
emulator pass saw no regression (R7 as built). Every decision D1–D19 is
taken (§2; D15 amended: the bind floor is the clock at unbind). Each built
slice has an "As built" block under its section — that
block, not the plan above it, is the truth. The phase between Phase 01
(pairing, shipped 2026-08-17) and Phase 02 (transport) of
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

**Letters (2026-10-23) — all taken.** D4, D5, D7, D8, D12, D14 = A by the
owner's go on slices R1–R3 (built). D1, D2, D3, D6, D9, D10, D11, D13 = A on
the owner's instruction to decide with the most advanced reasoning: an
independent Fable decision memo at maximum effort, reconciled by the lead
(the memo verified every fact it relied on against the tree; its file:line
list is in the session record). D15–D19 below were found missing by that
memo and decided the same way. Refinements that bind the remaining slices:

- **D1 sub-rules.** A row's home is the space of its `owner_id`. A
  space-level share is `members`/`grants` on the space document, checked by
  the partner's rule through one `get()` of the space (one read per query or
  listener attach — open partner spaces lazily, only for granted tables). A
  per-event share is a `shared_with` uid array on the event document (a v44
  column locally), read by the grantee through one collection-group query
  (`shared_with array-contains me`, `hlc > last`) under a `/{path=**}/
  calendar_events/{id}` rule with no `get()`; it needs a collection-group
  index. `pairs` and `invites` stay as the consent plane: a grant on a space
  is authorised by a rules `get()` of the active pair, exactly as a pair is
  authorised by its invite today. A self-pair is impossible under the shipped
  rules (`members.size() == 2`, the invite's creator must differ), which is
  the structural reason B cannot serve one account's devices.
- **D2 scope.** Phase 02 becomes "own space on N devices, all eighteen
  tables" — notes included, since D14 and the outbox's coalescing already
  bound the write cost; Phase 03 becomes sharing (grants, folders, selected
  events, ownership, consent). A first pull of a large space costs one read
  per row: pull in dependency order (categories → events → day rows →
  notes), debounce the drain (D19), surface `SyncStatus.paused` on
  `resource-exhausted`.
- **D3 constraints.** (i) One database ↔ one space, and a space bound at
  most once per install: every database on an install shares the one
  `device_id`, so two local databases in one space would stamp the same node
  id and equal HLCs on one row key could not be told apart. (ii) The binding
  records the account uid (`sync_space_account_uid`, the `pairingAccountUid`
  precedent); a different account signing in on a bound database *suspends*
  sync with a visible reason — never re-owns rows. (iii) Binding a non-empty
  database is a union under D15. The QA database is already gated upstream
  (`SyncAvailability.resolve` is false for a QA build unless QA explicitly
  allows cloud).
- **D6 refinements.** Write `last_hlc` once per DAO transaction, not per
  stamp. Clamp the logical counter: when it would pass 0xFFFF, advance the
  physical millisecond by one and reset — order kept, encoding unchanged.
  When the stored value exceeds the wall clock by more than the drift guard,
  surface it in `SyncStatus` but do **not** cap the seed (the lead's
  disagreement with the memo: a capped seed would issue stamps below rows
  already pushed, which is the rollback D6 exists to prevent; `receive()`
  would pull the clock back up from the first remote row anyway).
- **D9 refinement.** The re-bind after a restore is governed by D15: imports
  mint fresh HLCs, so a plain "merge into space X" would let a month-old
  backup overwrite a month of the other device's edits. R4 also clears the
  outbox *after* the import (the inserts enqueue) and writes
  `sync_metadata['bind_floor']`.
- **D10 refinement.** The per-note money currency is note data mis-filed as
  a setting and becomes `notes.money_currency` in v44 (Phase 03, with the
  additive backup key); the markdown-bar assignment stays per device because
  it names a bar profile that exists only on the device that made it.
- **D11 honesty clause.** A device learns of a new alert only when it pulls,
  and pulls run while the app is alive or at launch and resume; nothing in
  the app runs in the background for this. Until the Worker relay sends a
  "pull now" data message — push's first use, Phase 02's last slice — a
  device not opened after the alert was created will not ring. Accepted. A
  periodic background pull (WorkManager) is the fallback if the Worker is
  declined.
- **D13 refinement.** Scope the wipe to `owner_id IS NULL OR owner_id =
  boundUid` (D17's "mine"); `alert_registrations` stays a hard delete;
  `CalendarEventDao.deleteAll` remains for `importData` alone.

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

Decided 2026-10-23, found missing by the decision memo:

- **D15 — The initial merge at bind** (any bind of a non-empty database,
  including the re-bind after a restore). **A (taken):** pull first; for a
  row present on both sides, remote wins when the local HLC is ≤
  `sync_metadata['bind_floor']`, ordinary last-writer-wins above it;
  local-only rows upload (the outbox is re-seeded from every live row and
  tombstone — `SyncOutboxDao.requeueAll`, R6); remote-only rows download.
  `bind_floor` = the maximum HLC in the database at every unbind (manual or
  restore, written by R4) or, for a never-bound database, at bind time.
  **Amended 2026-10-23 (R6 review): the floor is the clock at unbind —
  `persistClock()` then `last_hlc` — not the row maximum.** Merges store a
  remote stamp verbatim while the drift guard (R5) holds the clock below a
  far-ahead one, so a row-maximum floor could sit above every later local
  edit and this rule would hand them to the space; the clock is ≥ every stamp
  this device minted and < every later one, and a held row meets its remote
  twin as an equal. A
  never-synced database collides only on fixed ids (built-in categories),
  where the space should win; a restored database yields its snapshot but
  keeps the edits made after the restore. **B:** plain last-writer-wins —
  loses because a stale restore would overwrite a live space. Policy only;
  reversible. Changes R4 (write the floor), R6 (`requeueAll`), Phase 02
  (the bind flow).
- **D16 — `owner_id` in backups.** **A (taken):** export `owner_id` as an
  additive key and import it verbatim (absent → NULL; format stays 7 under
  the absent-keys-take-defaults rule — the implementer verifies an older
  app ignores the extra key); the push never enqueues rows with a foreign
  `owner_id`; a pull refreshes or drops them per the live grant. Without it
  a backup of a synced database turns partner rows into mine (D9). This
  narrows §5's "no identity fields" to the clock fields; `owner_id` is
  ownership, not identity. **B:** exclude foreign rows from exports — lossy
  for the offline keeper who ended a connection and was promised their
  copy stays. R4 can add it at zero risk (every row is NULL today).
- **D17 — When `owner_id` is backfilled.** **A (taken):** at **bind**,
  inside the bind transaction, `WHERE owner_id IS NULL`, with the bound
  account's uid; everywhere, "mine" means `owner_id IS NULL OR owner_id =
  boundUid`. **B:** at first sign-in, as D12 said — loses because sign-in is
  global and binding is per database: it would stamp unbound databases (a
  second local database, a QA database with cloud opt-in) and make every
  row foreign after an account change. Changes R4's D13 predicate and
  Phase 02.
- **D18 — Which child rows follow the event and which the person**
  (Phase 03). **A (taken):** skips and per-occurrence descriptions are event
  data → the event's space, written under the edit grant, `owner_id` = the
  event's owner; absences (presence) and alert definitions are personal →
  the author's space, keyed by the shared event's id; a partner's devices
  never arm the owner's alerts. Decides the rules' write clause per
  subcollection and the engine's routing by table class. Reversible before
  Phase 03 ships.
- **D19 — Drain cadence** (Phase 02 engine knob). **A (taken):** push ≥ 30 s
  after the last local write or immediately when the app goes to the
  background; ≤ 500 operations per batch (Firestore's batch cap); stop on
  `resource-exhausted` until the daily reset with `SyncStatus.paused`.
  Without a stated cadence the auto-save path decides it, and the roadmap's
  top risk is realised.

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

**As built (2026-10-23, committed `14c9250`; one implementer, one independent
reviewer, one fix pass; the review found no data loss, crash or
persisted-data break; gate: analyze clean, 9,381 tests green, the one failure
the known Windows-only `host_devices_test`).**
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

- `CrdtWrite.newStamp()` (`lib/database/crdt/crdt_write.dart`, the only
  local minting point since R3b; `migrationBackfillHlc()` in `database.dart`
  is the migrations' own) writes the issued value to
  `sync_metadata['last_hlc']` inside the caller's transaction when there is
  one, else directly; `AppDatabase.getInstance` seeds the clock from the
  stored value so the first `now()` is above it even when the wall clock is
  behind. `now()` (`hlc.dart:22-37`) already never goes below
  `_lastPhysicalTime` and bumps the counter instead; what is missing is a
  constructor that sets `_lastPhysicalTime`/`_logicalCounter` from a stored
  `HlcTimestamp` — today's ctor takes only `initialCounter` (`hlc.dart:6-8`).
- **Decided refinements (D6):** persist once per DAO transaction (the
  helper's transaction already pays one outbox statement; the clock write
  rides it), not per stamp; clamp the logical counter at 0xFFFF by advancing
  the physical millisecond and resetting, so the four-hex-digit encoding
  (§5) never breaks order; when the stored value exceeds the wall clock by
  more than the drift guard, report it through `SyncStatus` but never cap
  the seed.
- Tests in `test/database/hlc_test.dart`: wall behind stored → monotonic;
  restart preserves order; a `receive()` of a far-future remote is clamped
  per the existing drift guard.
- Small enough for the implementing session's main thread or an
  `implementer` at `medium`.

**As built (2026-10-23, uncommitted when written; one implementer, one
independent reviewer — 17 findings, none high — a fix pass carried at the
head of the R6 run, a second review that confirmed the fixes and found four
more, fixed at the head of the R4 run; gate: analyze clean, whole suite
green, the one failure the known Windows-only `host_devices_test`).**
Deviations from the plan above, each sound and reversible on its own:

- **The "existing drift guard" did not exist** — `receive()`/`update()` had
  no bound at all. R5 added `HybridLogicalClock.maxDrift` (one hour): a
  remote further ahead than `wall + maxDrift` *and* above the local clock is
  held at `max(local, wall + maxDrift)` and counted in `clampedRemotes`; a
  remote at or below the local clock passes unchanged. The price: after a
  held far-future remote, local stamps stay below that row's HLC until the
  wall catches up, so an edit to that row loses last-writer-wins — accepted
  over letting one wrong clock drag every device (§8).
- The logical counter is clamped at `0xFFFF` in every incrementing branch and
  wherever a counter is adopted (`seed`, `update`, `initialCounter`): one more
  tick advances the millisecond and resets, so the four-hex-digit encoding
  never breaks order.
- `seed(stored)` only raises the clock and records `seedAhead`; the seed is
  **never capped**. `AppDatabase.clockSeedAhead`, `clockClampedRemotes` and
  `clockMaxDrift` expose the facts to `SyncStatus` (R6) without naming the
  clock outside its owners (the guard test's allow-list is unchanged).
- Persistence rides the outbox write. The four `enqueue*` helpers persist
  **`hlc.last`** — the highest stamp minted so far, so an `importAll` that
  pre-mints N stamps persists once — through a forward-only upsert
  (`WHERE excluded.value > sync_metadata.value`), deduped in-process by
  `persistedUpTo` (a *claim*, forward-only, `claimPersisted` its only
  writer). `enqueue` and `persistClock()` claim after their statement lands,
  `enqueueMany` after its own batch, `enqueueIn` at build time (a caller
  never continues after a failed batch). `enqueueWrittenIn` (`seedMissing`,
  category `reorder`) writes the clock only `WHERE EXISTS` its outbox row, so
  an idle launch stores nothing. The three merges do not persist — dormant;
  **the Phase 02 engine calls `persistClock()` once per applied pull batch**
  (§7).
- Seeding: `seedClockFromStore()` runs in `getInstance` before the instance
  is handed out and at the start of `onUpgrade`; when `last_hlc` is absent (a
  v43 database from before R5) the clock seeds from the rows
  (`SyncOutboxDao.maxHlc()`, R6) and persists at once — in `onUpgrade` after
  the steps succeed, in `getInstance` after open. `onUpgrade` persists in a
  `finally`, so backfill stamps are covered even when a later step fails; a
  persist failure is rethrown only when the migration itself succeeded. A
  malformed stored value is deleted so persistence resumes. The
  `sqlite_master` guard was dropped: `sync_metadata` has had the same shape
  since v1.
- `getInstance` memoises the opening `Future` (`_instance` is gone):
  concurrent callers share one open; a switch awaits the in-flight open,
  notifies the lifecycle, then closes; a failed open clears the memo; a
  failed seed closes the half-open database; `deleteAllData` clears the memo
  only after the close. This also closed the pre-existing two-instances race
  at startup.
- Tests: `test/database/hlc_test.dart` (+12), `clock_persistence_test.dart`
  (store per write, once per action, the batch paths, rollback, a restart
  with the wall behind on a temp file, an upgrade seeds before its first step
  and from the rows when nothing is stored, a malformed value),
  `database_instance_test.dart` (the memo, an in-flight switch, a failed
  open). `StatementCounter.executions` now counts batched argument sets —
  the old `matching` count saw one SQL string per batch and would have
  passed with fifty upserts. Pins: one `sync_metadata` statement more on the
  first write of each new HLC (`query_count_test`, `counter_crdt_test`,
  `item_label_dao_test`, `calendar_category_crdt_test`).
- Recorded in §8: a whole-file database restore brings back an older
  `last_hlc`; `migrationBackfillHlc()` stamps are covered by the `finally`,
  not stored per stamp.

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

**As built (2026-10-23, committed `596998d`; one implementer, one independent
reviewer, two fix passes; the review confirmed every converted write commits
with its outbox entry; gate: analyze clean, 9,439 tests green, the one failure
the known Windows-only `host_devices_test`).** Deviations from the plan
above, each sound and reversible on its own:

- The helper is the `CrdtWrite` extension on `AppDatabase`
  (`lib/database/crdt/crdt_write.dart`): `stampLocal`, `newStamp` (one
  shared HLC for a multi-row action), `enqueue` / `enqueueIn(batch)` /
  `enqueueMany`, and `enqueueWrittenIn(batch, table, rowKeys, hlc)` for the
  two batched writes that cannot learn per-row results (`seedMissing`,
  category `reorder`). Every outbox upsert is monotonic (`DoUpdate …
  WHERE excluded.hlc > sync_outbox.hlc`): an entry can never be lowered, and
  every stamp is taken inside the transaction or batch it belongs to — the
  review found that a stamp taken before `transaction(...)` could write an
  older HLC over a newer row and lose a queued change to the in-flight
  `ackThrough`. Set-based writes learn their exact keys with `UPDATE …
  RETURNING` (SQLite ≥ 3.35, guaranteed because the app bundles SQLite
  through `sqlite3_flutter_libs`); HLC-equality selection was removed.
- `SyncOutboxDao`: `pending({limit})` by hlc, table, key; `count()`;
  `ackThrough` compare-and-delete returning `bool`; `clear()`. `OutboxOp`
  {`upsert`, `tombstone`}; `MergeOrigin` {`local`, `remote`};
  `counterValueRowKey`.
- The note body moved into `NoteDao.createNote` / `importNote` /
  `updateNote` (optional `content:` → `ContentChunkDao.writeChunks`), so one
  save is one transaction, one stamp, one `notes` outbox row;
  `ContentChunkDao.saveContent` is gone (it wrote chunks before the
  tombstone check and left preview/length/count stale). The repository
  caches a body only when the DAO wrote it.
- Merges: `origin` is required; a remote merge never enqueues; every merge,
  insert branch included, advances the clock (`hlc.update`) — the insert
  branch never did before; `mergeNote` / `mergeFolder` return the
  overwritten live row for D7 and `null` when the local row was a
  tombstone; a local-origin `mergeChunk` stamps the owning note only when
  the note's HLC is older than the chunk's.
- **FTS fix on the save path** (pre-existing, proven by a failing test
  first): `notes_fts` is an external-content FTS5 table, and `updateNote`
  ran `INSERT OR REPLACE` after writing the row, so the old title's tokens
  stayed and a renamed note still matched its old title. `_updateFtsIndex`
  now issues the FTS5 `'delete'` with the old values then inserts the new
  ones, only when title or preview changed; the bulk tombstone deletes FTS
  rows only for notes that were live. `test/database/note_fts_test.dart`.
  The v43 step also rebuilds `notes_fts` once (guarded on the table's
  existence) because every existing install carries the stale tokens.
- No-op guards: `updateFolder`, `updateFolderSortPreferences`,
  `softDeleteNote` / `softDeleteFolder` on a tombstone,
  `setNoteValuePinned`, `upsertVocabulary`; `setNotePositions` /
  `setFolderPositions` write only live rows that moved. One HLC per action:
  `softDeleteNoteWithChunks`, the vocabulary writes, the chunk tombstones;
  `NoteStorageService.deleteNotesInFolder` goes through the bulk tombstone;
  `NoteDao.deleteNotesInFolder` (no callers) removed.
- Tests: `test/database/sync_outbox_test.dart` (per-table one row,
  coalescing, tombstone op, remote merge → none, `ackThrough` boundary,
  monotonic entry, a throwing write leaves no entry, 200 saves through
  `NoteStorageService` → one `notes` row and no chunk rows, import rows,
  clock advance per merge, the guards), `note_fts_test.dart`; counts
  updated in `counter_crdt_test`, `calendar_category_crdt_test`,
  `query_count_test`, `item_label_dao_test`.
- Left as found, recorded in §8: the four-hex-digit HLC counter ceiling,
  restore wipes leaving outbox entries until R4, `MergeOrigin` at the
  repository layer, two test files unformatted at HEAD.

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

**As built (2026-10-23, committed `4fd26aa`; one implementer, one independent
reviewer, one fix pass; the review found no data loss and judged the no-op
comparison sound against every column type; gate: analyze clean, 9,493
tests green, the one failure the known Windows-only `host_devices_test`).** Deviations from the plan above, each sound
and reversible on its own:

- All ten calendar-side tables go through `CrdtWrite`; `dayRowKey(eventId,
  day)` joins the event id and the stored day's epoch-ms (normalised to the
  stored second) — the same integer the services' `exportData()` writes as
  `dayMs`; `changesNothing(existing, entry)` compares what SQLite would store
  (seconds for DateTimes, 0/1 for bools, absent fields never count as equal,
  `created_at`/`updated_at` ignored) so an unchanged save writes nothing and
  a save over a tombstone always writes.
- One HLC per user action: `CalendarEventDao.tombstoneEventCascade` (event,
  absences, descriptions, skips, alerts under one stamp, every row enqueued;
  the hard `alert_registrations` delete follows inside the same
  transaction); `CalendarCategoryDao.tombstoneCascade(id, reassignTo:)`
  (events moved with `UPDATE … RETURNING`, alerts tombstoned, the category
  tombstoned — refusals for built-ins and tombstones checked before any
  write); `replaceForEvent` / `replaceForCategory` queue removals as
  tombstones, edits as upserts, nothing for unchanged alerts; reorders only
  rows that moved; `importAll`s one stamp per row, every row enqueued.
- The fence: `generateHlc()` is gone; `migrationBackfillHlc()` exists for
  `DatabaseMigrations` alone; `CrdtWrite.newStamp()` is the only local
  minting point. `test/database/crdt_write_guard_test.dart` scans `lib/`
  (allow-list: `crdt_write.dart`, `hlc.dart`, `database.dart`,
  `database_migrations.dart`, `sync_outbox_dao.dart`) for any clock use,
  `HlcTimestamp` construction, outbox identifier or SQL literal, requires
  `hlc.update` in exactly the three merges, and requires an `enqueue` next
  to every `newStamp`. It is a heuristic; the per-table suites are the
  proof.
- Tests: `test/database/sync_outbox_calendar_test.dart` (per-table rows,
  coalescing, tombstone ops, imports, both cascades under one HLC,
  `reassignCategory` only moved events, alert tombstones vs upserts and
  resurrection, one-field edits of DateTime / bool / nullable columns, the
  key against `exportData()` across DST days, a throwing write leaves
  nothing), `crdt_write_guard_test.dart`; statement counts and plans
  re-pinned in `query_count_test` and `query_plan_test`.
- Hot paths: every single-row write costs one more statement (its outbox
  upsert); unchanged saves cost one fewer; the cascades one batched insert
  per child table.
- Left as found, recorded in §8: the editor saves an event and its alerts
  as two actions with two HLCs; a skip clears the day's presence through a
  second service call and HLC; three files unformatted at HEAD.

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
- **Decided additions (2026-10-23, D13/D15/D16/D17):** the wipe's predicate
  is `owner_id IS NULL OR owner_id = boundUid` (today every row is NULL, so
  every row); the import also clears the outbox *after* its inserts (they
  enqueue) and writes `sync_metadata['bind_floor']` = the maximum HLC in the
  database at the end of the import, as does a manual unbind; `owner_id` is
  exported as an additive backup key and imported verbatim (absent → NULL),
  with a test that an older-format backup still imports and that a backup
  carrying `owner_id` round-trips it. R4 does **not** backfill `owner_id` —
  that happens at bind (D17, Phase 02).
- Skills: `anta-context`, `calendar-events`.

**As built (2026-10-23, uncommitted when written; two implementer runs — the
wipe, the suspension and the unbind in one, which also carried R6's fix
pass; `owner_id` in backups in a second at medium effort — one independent
reviewer over both, 9 findings, none high, F1–F5 and F8 fixed in a third
short run, F6 and F7 recorded in §8; gate after each run: analyze clean,
whole suite green — 9,584 tests after the last run — the one Windows-only
failure).** Deviations from the plan above, each sound and reversible on its
own:

- **The wipe.** `CalendarEventService.deleteAll()` is `tombstoneAll()`: it
  reads the bound account (`SyncBindingService.read()?.accountUid`, null
  when unbound) and calls `CalendarEventDao.tombstoneAll(ownerUid:)` — one
  transaction, one `newStamp()`, `UPDATE … RETURNING` per table on live rows
  only under `ownedRowsWhere(ownerUid)` (`owner_id IS NULL` when unbound,
  `owner_id IS NULL OR owner_id = ?` when bound — D13/D17), every row
  enqueued as a tombstone, the four child DAOs' `tombstoneAll(stamp:,
  ownerUid:)` next to their `tombstoneForEvent`; the DAO returns the
  tombstoned event ids and only *their* `alert_registrations` are
  hard-deleted (`AlertRegistrationDao.deleteForEvents`, 500 ids per
  statement — device-local rows, rebuilt by the next reconcile); a surviving
  foreign event keeps its registration. The service **reloads** its cache
  (`_load()`) instead of blanking it, so a surviving foreign event stays
  shown and exported, and the page re-reads the count from the service.
  `CalendarEventDao.deleteAll()` survives for `importData` alone. Dialog
  copy, snackbar and count unchanged. A repeat on an empty calendar still
  mints one stamp and runs its five statements (F7, accepted — a pre-check
  would tax every real wipe).
- **The suspension** lives at `lib/services/sync/sync_suspension.dart` (not
  `lib/services/`): `SyncSuspension.isSuspended` / `run()`, depth-counted,
  re-entrant, released in `finally`. Nothing consults it yet — the engine
  checks it before every push, pull and bind (§7).
- **The restore.** `importFromJson` = `SyncSuspension.run(() =>
  _importFromJson(...))`; `unbind()` runs before the first write (keys,
  outbox, floor); today's wipes and inserts are unchanged; after the
  reconcile: `syncOutboxDao.clear()` (the inserts enqueued) →
  `writeBindFloor()` (the clock, D15 amended — it covers every stamp the
  import minted) → `notifyExternalChange()` once — **on success and on
  failure alike**: once the unbind has run, the wrapper clears, floors and
  notifies even when a row-level throw ended the restore half-written (a
  half-restored database is unbound, unqueued and floored above every
  partial row, so a later bind cannot push it over the space); a malformed
  file fails at the parse and never unbinds. The settings write-back
  skips every `pairing_` / `sync_space_` key (`SettingsKeys.pairingPrefix`,
  `syncSpacePrefix`): a hand-edited or foreign archive can neither pair nor
  bind the database it lands on — the export pin alone (R6) only covered
  archives this app wrote. The folder-archive import appends copies and does
  not unbind. The suspension is proven in the test through a
  `NoOpAlertGateway` subclass that records `isSuspended` during the
  restore's reconcile — no production seam.
- **`owner_id` in backups (D16).** Key `ownerId`, **emitted only when
  non-null** (today's exports stay byte-identical) and imported verbatim as
  `Value(null)` when absent; format 7. `JsonKeys.ownerId` /
  `EventAlertKeys.ownerId`; `createFolder` / `createNote` gained `ownerId`
  (the copies keep the archived ownership under their fresh ids);
  `CounterDao.upsertValue(..., ownerId:)` writes it on insert and resurrect
  only; every `importAll` already stamps with `entry.copyWith(...)`, so the
  field passes through unchanged. **Counter values deviate:** `globalValues`
  / `noteValues` hold bare ints that older importers read with `as int`, so
  a value's ownership rides `noteValueExtras` under the existing
  `counterId::noteId` key (`counterId::` for the global value) as
  `{'ownerId': …}` beside `isPinned` / `position`; an older app's extras loop
  reads only those two and writes nothing for an owner-only entry.
  `JsonKeys.ownerIdOf(map)` is the one reader — the key counts only when it
  is a string, so a hand-edited `42` imports as NULL and drops nothing.
- Tests: `test/database/tombstone_all_test.dart` (one HLC, one tombstone
  row per key, earlier tombstones untouched, unbound vs bound predicates,
  foreign rows kept and never queued, a repeat writes nothing, the service
  leaves no event / export / registration), `test/services/sync/
  sync_suspension_test.dart`, `backup_service_restore_unbind_test.dart`
  (unbound, unqueued, floored, suspended during the reconcile; a pairing or
  binding key in an archive's settings stays absent while an ordinary key is
  written), `backup_service_owner_id_round_trip_test.dart` (all seventeen
  exported tables round-trip `'them'` and keep NULL, a pre-D16 archive
  restores every row as mine, a clean database's archive carries no key);
  23 test call sites renamed `deleteAll` → `tombstoneAll`.
- Found and left (pre-existing, §8): `CounterService.importData` restores
  per-note values under the archived note ids while notes get fresh ids.

### R6 — Engine seams, no network

- `lib/services/sync/sync_gateway.dart`: `SyncGateway` interface
  (`pushBatch(List<SyncEnvelope>)`, `pullSince(table, hlc)`, `ack`),
  addressed by a space reference (`ownerUid`, `spaceId`) and never by a
  pairId (D1), and the
  `SyncEnvelope` value (table, rowKey, hlc, op, `exportData()` map — the
  backup serializers are the wire format, roadmap stance); a
  `FakeSyncGateway` under `test/support/`. Firestore types appear nowhere.
- `SyncStatus` value (pending count from the outbox, last push, paused
  reason) surfaced by `SyncBloc` states, extending
  `test/bloc/sync_bloc_test.dart`'s fake-service pattern.
- A public `CalendarBloc` event for an external change that runs
  `_invalidateDayCache` and bumps `occurrenceRevision`;
  `AlertReconcileReason.sync`; `SettingsKeys.syncSpaceId`,
  `syncSpaceOwnerUid`, `syncSpaceAccountUid`, `syncSpaceBoundAt` next to the
  pairing keys (`settings_keys.dart:376-398`), all excluded from backups by
  the allowlist and pinned by R4's test (D3); `SyncOutboxDao.requeueAll()`
  — re-seed the outbox from every live row and tombstone of every synced
  table for the initial merge at bind (D15).
- Skills: `anta-context`, `calendar-events`, `flutter-principles`.

**As built (2026-10-23, uncommitted when written; one implementer — the run
that also carried R5's fix pass — one independent reviewer, 14 findings,
none high, fixed at the head of the R4 run; gate: analyze clean, whole suite
green, the one Windows-only failure).** Deviations from the plan above, each
sound and reversible on its own:

- **Registry.** `lib/database/crdt/synced_tables.dart` lists the eighteen
  tables with the SQL that reproduces each outbox key byte for byte (`id`;
  `counter_id || '|' || note_id`; `event_id || '|' || (day * 1000)` — drift
  stores `day` as unix seconds) and `travelsWithParent` for
  `content_chunks` (never queued under D14, counted in `maxHlc`);
  `ownedRowsWhere(ownerUid)` builds the "mine" predicate of D17.
  `SyncOutboxDao.requeueAll({required String boundUid})` (non-nullable — a
  bind always has a uid; `owner_id = NULL` is never true) re-seeds the outbox
  with one `INSERT … SELECT` per table, foreign rows excluded, never lowering
  a newer entry, minting nothing; `maxHlc()` is the highest stamp across all
  eighteen.
- **Binding.** `SettingsKeys.syncSpaceId` / `syncSpaceOwnerUid` /
  `syncSpaceAccountUid` / `syncSpaceBoundAt` (`sync_space_*`) plus
  `pairingPrefix` / `syncSpacePrefix`; `SyncBinding` in `lib/models/`;
  `SettingsService.getSyncBinding` / `setSyncBinding` (transactional, null
  clears all four); `SyncBindingService` (`lib/services/sync/`, on the
  lifecycle) with `read`, `bindFloor`, `writeBindFloor`, `unbind` (keys →
  outbox clear → floor, one transaction). **D15 amended: the floor is the
  clock** — `writeBindFloor()` = `persistClock()` then `bind_floor :=
  last_hlc` (see D15 for why the row maximum was wrong). The export pin
  (`test/services/backup_service_sync_keys_test.dart`) proves no pairing or
  binding key leaves in a backup; R4 makes the import refuse them too.
- **Status.** `SyncStatus` (`pendingCount`, `lastPushAt`, `pause` ∈
  {`none`, `quotaExhausted`, `accountMismatch`}, `clockAhead`,
  `clampedRemotes`, `binding`), `SyncStatusReader`, `SyncStatusService`
  (`accountMismatch` only when a user is signed in and differs from the
  bound account; `quotaExhausted` is reserved for Phase 02). `SyncBloc`
  takes a lazy `statusReader` thunk (an eager future would be an unawaited
  error on unsupported platforms), emits the account state at once and the
  status as a second emit skipped when the state has moved on, with a 3 s
  timeout to `SyncStatus.empty`; the first emit carries the previous status
  only for the same account (`pause` is per account — a mismatch must not
  linger over the bound account's sign-in); `SyncSignedIn` / `SyncSignedOut`
  carry `status`; `RefreshSyncStatus`.
- **Calendar seam.** `CalendarEventService.externalChanges` (static
  broadcast) and `notifyExternalChange()` (also bumps `externalRevision`);
  `ExternalCalendarChange` → `_onExternalChange`, which re-runs `_onLoad`'s
  resolution (`_resolveAndReload`, snapshots read after the last await)
  without a loading state, under a load generation that drops a reload that
  lost the race, bumping `occurrenceRevision` and `membershipRevision`; a
  change that arrives while the *first* load is still in flight sets a
  pending flag the load honours with one more read, so the first loaded
  state already carries it (the generation is never bumped before the
  calendar is loaded, or the first load would never emit).
  `importData` keeps the bare revision bump; **`BackupService.importFromJson`
  notifies once at the end** — a mid-restore notify had reloaded the bloc
  before skips and alerts were imported and marked it fresh, so the page's
  `_reloadIfStale` would never have fired. `AlertReconcileReason.sync`.
- **Gateway.** `SyncSpaceRef`; `SyncEnvelope` (table, rowKey, hlc,
  deviceId, version, op, ownerId, `data` = the backup serializer's map, null
  for a tombstone); `SyncGatewayFailure` / `SyncGatewayException`;
  `SyncGateway.pushBatch` (≤ `maxBatch` = 500, D19), `pullSince(space, table,
  {sinceHlc, sinceRowKey, limit})` ordered by **`(hlc, rowKey)`** strictly
  after the cursor — one HLC stamps many rows, so a bare-hlc cursor dropped
  rows at a page boundary — and `ack(space, table, throughHlc,
  throughRowKey)`; `FakeSyncGateway` under `test/support/` with
  `failNextWith`. No Firestore type outside `pairing_gateway.dart` (grep).
- Tests: `sync_outbox_requeue_test`, `sync_binding_service_test`,
  `sync_status_service_test`, `backup_service_sync_keys_test`,
  `calendar_bloc_external_change_test`, `fake_sync_gateway_test`,
  `sync_bloc_test` (+8). `restartable()` was not used (no `bloc_concurrency`
  dependency; the generation guard covers bursts).

### R7 — Gate and device pass

- The full gate; then `qa-runner` on the emulator's QA database: folder and
  note CRUD, labels, reorder; global and per-note counters; category create,
  hide, delete; "Delete all events"; backup export → import round trip;
  vocabulary; `qa errors` clean. Nothing visible should have changed — the
  pass proves it.

**As built (2026-10-23; the gate after the last fix pass: `dart analyze lib`
clean, `flutter test` 9,584 green with the known Windows-only
`host_devices_test` the only failure, no ARB touched; the device pass by
`qa-runner` on `Pixel_9_Pro`, shots under `build/qa/shots/`).** No app
regression was seen; the pass was partial on the harness side:

- **Existing database first:** `qa run` without `--fresh` opened the QA
  database left by earlier passes (pre-v43, no stored clock) — the new build
  migrated and seeded it with `qa errors` clean and nothing on
  `migrat|sync_metadata|last_hlc` in the log; folder list, calendar, Calendar
  settings and the Sync page ("Not available on this platform" on a QA
  build) opened. That database held no rows, so data survival across the
  migration rests on the upgrade-chain and clock-persistence suites.
- **Saved calendar flows:** 24 of 26 green; `19_fasting_schedule` red at its
  `expect id:fasting-extra-days` because the row sits below the tall
  emulator's 2856 px fold and the flow scrolls only to `fasting-days-off`
  (green by hand with two more swipes — a flow fault); `23_overview_list`
  red once on counts after other flows had added events on the same seed,
  green alone on a fresh seed (state dependence in the flow). Both are
  harness items, not app ones.
- **Browser and counters** (basic seed): folder create / label / rename,
  note create with three typed lines that survive reopening, note label,
  reorder in Select mode (the `drag` verb selects the row; `swipe --via
  native` on the handle reorders — the known trap), note and folder delete,
  a global counter +1 +1 −1 and pin, a per-note value through "Values per
  Note" — all green, `qa errors` clean.
- **Categories:** create, hide and un-hide a built-in, delete — green.
- **Delete all events** (calendar seed): the row reads "Permanently remove
  every event you created. Holidays are kept." before and "No events to
  delete" (disabled) after, the "All events deleted" snackbar shows, the day
  panel's three rows are gone, and after a `relaunch` without `--fresh` the
  row still reads "No events to delete" — the tombstones persisted. `qa
  errors` clean. (The page shows no numeric count; the plan's "count 0" is
  that disabled row.)
- **Not run:** vocabulary (the "Manage vocabularies" button sits inside a
  folded section of the Markdown settings page the runner did not open —
  the vocabulary write paths are covered by `sync_outbox_test` and the
  backup suites); the backup export → import round trip (the export goes
  through the system share sheet, invisible to the harness — covered by the
  four backup round-trip suites and `backup_service_restore_unbind_test`);
  the matrix shots (nothing visual changed; the per-step shots stand in).
- Seen and judged not a regression: a new note with body text keeps the
  title "Untitled Note" — that string is the display fallback for an empty
  explicit title everywhere in the tree and no code derives a title from the
  body.

---

## 5. Must not change

- The `gym_notes` directory and the `device_id` file
  (`database.dart:178-190`).
- Backup format version 7, live rows only, no clock fields (`hlcTimestamp`,
  `deviceId`, `version` never travel); `owner_id` travels as an additive key
  from R4 on (D16); absent keys take column defaults; `importData`'s wipe
  stays hard, inside the suspension; folders and notes still import as
  copies with fresh ids (`backup_service.dart:122-124`).
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
  the only way to obtain an HLC for a synced-table write — R3b renamed
  `generateHlc()` to `migrationBackfillHlc()` for the migrations alone (Dart
  has no cross-library privacy, so the fence is
  `test/database/crdt_write_guard_test.dart`, a source scan of `lib/` for any
  other clock use or outbox write), plus the per-table suites.
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
  grantee, the per-event `shared_with` array for selected events (D1
  sub-rules). The connections design's "one designated calendar connection"
  (decision 9) becomes a product choice rather than a merge necessity once a
  row has one home; revisit it there.
- **Phase 02 is "own space on N devices"** (D2): the engine for all eighteen
  tables, the bind flow with the picker (bind this database / download into
  a new one), the `owner_id` backfill at bind (D17), the initial merge
  (D15), the drain cadence (D19), `SyncStatus`; the Worker's "pull now" data
  message as its last slice (D11). **Phase 03 is sharing**: grants on a
  space, shared folders, selected events, ownership colours and consent,
  the child-row routing of D18, `notes.money_currency` (D10) — v44.
- The engine: drain the outbox in Firestore batches, back off on
  `resource-exhausted` into `SyncStatus.paused` until the daily reset, pull
  through filtered listeners (`hlc > last`), `HybridLogicalClock.receive()`
  on every pulled row, merge, then the invalidation hooks listed in §1 and
  `AlertScheduler.reconcileAll(sync)`.
- **Engine contracts the built seams impose (R5/R6/R4 as built):** check
  `SyncSuspension.isSuspended` before every push, pull and bind (a restore
  runs inside it); call `persistClock()` once after each applied pull batch
  (the merges do not persist the clock); the pull cursor is the pair
  `(hlc, rowKey)` — one HLC stamps many rows, so a bare-hlc cursor drops
  rows at a page boundary; `requeueAll(boundUid:)` takes the bound account's
  uid and queues only `owner_id IS NULL OR owner_id = uid`; the initial merge
  compares against `bind_floor` = the clock at unbind (D15 amended), and a
  bind writes a floor the same way when none exists; call
  `CalendarEventService.notifyExternalChange()` and the repositories'
  `invalidateAll()` after each applied batch; `SyncStatus.quotaExhausted` is
  the engine's to set, `accountMismatch` is computed by the status service.
- Space binding UI on the Sharing page; `owner_id` backfill at **bind**
  (D17, inside the bind transaction, `WHERE owner_id IS NULL`); the conflict
  copy (D7) from the merge method's returned loser.
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
- Found by the R3a review, left as found: the HLC encoding pads the logical
  counter to four hex digits (`hlc.dart:112`), so string order breaks at
  0x10000 ticks inside one millisecond — reachable only in a long
  clock-behind stretch; the encoding is must-not-change, R5 should clamp or
  guard the counter instead. Restore's hard wipes leave outbox entries for
  rows that no longer exist until R4's unbind clears the outbox. The
  repositories import `MergeOrigin` (a CRDT type one layer above the DAO) and
  `NoteRepository.mergeNote` discards the loser row the DAO returns — the
  engine will consume it in Phase 02.
- Found by the R3b review, left as found: the event editor saves the event
  and then its alerts as two DAO transactions with two HLCs
  (`event_alert_service.dart`), and `EventSkipService.markSkipped` clears the
  day's presence through a second service call — one user action, two HLCs
  in both cases. Harmless for the engine (two outbox rows, both pushed); a
  single stamp would need the facades' write order to change.
- Found by the R5 reviews, recorded as designed or left as found: after a
  held far-future remote (`maxDrift`, one hour) local stamps stay below that
  row's HLC until the wall catches up, so an edit to that row loses
  last-writer-wins — the engine may want to flag a pulled row more than an
  hour ahead; a whole-file database restore (not the in-app backup) brings
  back an older `last_hlc`, so stamps this device already pushed can sit
  above the restored seed — the in-app restore unbinds and is safe; the three
  merges never persist the clock (the engine persists once per batch);
  `enqueueIn` claims at build time and a caller may not continue after a
  failed batch; the memo test cannot force every failure of `getInstance`
  (the retry after a failed seed is reasoned, not tested).
- Found by the R6/R4 reviews, left as found: nothing consults
  `SyncSuspension` yet (the engine will); if `importFromJson` fails part-way
  the database stays unbound with the floor written at the unbind, the
  outbox not cleared and no end-of-restore notify — a later bind's
  `requeueAll` re-seeds the queue regardless; the folder-archive import
  (`ImportExportService`) appends copies and deliberately does not unbind;
  `restartable()` is not available (no `bloc_concurrency` dependency), the
  load generation stands in; `content_chunks.owner_id` stays NULL because a
  note's chunks travel inside the note (D14) and never carry ownership of
  their own.
- **Pre-existing restore defect, found by the R4 `owner_id` run, not this
  phase's to fix:** `CounterService.importData` keeps per-note counter
  values under the archived note ids, but `BackupService` restores notes as
  copies with fresh ids (`noteIdMap`) and never remaps `noteValues` /
  `noteValueExtras`, so after a restore every per-note value points at a
  note that no longer exists (the global values are unaffected). Fix: apply
  `noteIdMap` to both maps in the counter import, with a round-trip test.
- **D16 consequence for Phase 03 (R4 review F6):** folders and notes restore
  as copies with fresh ids, so a foreign-owned copy can never meet its
  original in the space, is never requeued at bind (`requeueAll` and the
  wipe both exclude foreign rows) and stays local-only for good; an own note
  restored into a foreign folder is pushed with a `folder_id` the space never
  receives and is orphaned on the other device; `createNote` writes the
  body's `content_chunks` with `owner_id` NULL under a foreign note (never
  queued, but inconsistent). Consistent with D16 as written; Phase 03 decides
  whether a restore keeps foreign rows as read-only copies, re-homes them
  under the restoring account, or drops them.
- Accepted in the R4 fix pass (F7): an empty second "Delete all events"
  still mints one stamp, runs its five `UPDATE … RETURNING` and notifies the
  tables' streams — a pre-check would cost a statement on every real wipe
  and the repeat is a retap of a button the page disables.

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

Checked 2026-10-23, each against the as-built blocks:

- All eighteen synced tables carry the five CRDT columns and `owner_id`;
  parity test green at v43; the three new tables have `*_crdt_test` suites.
  **Done (R2).**
- Every write to a synced table goes through the helper and leaves exactly
  one coalesced outbox row; remote-origin merges leave none; the usage probe
  holds. **Done (R3a/R3b; the guard test fences it).**
- No hard delete on a synced table outside the import path, which runs
  suspended and unbound. **Done (R4): "Delete all events" tombstones; the
  restore runs in `SyncSuspension.run`, unbinds first and floors after.**
- The clock survives a restart and a wall-clock rollback. **Done (R5):
  persisted per action, seeded before the instance is handed out and before
  any migration step, never capped; counter and drift bounded.**
- `SyncGateway`, `FakeSyncGateway`, `SyncStatus`, the external-change event
  and the binding keys exist with tests; no Firestore type outside the
  pairing gateway. **Done (R6), plus `requeueAll`, `maxHlc`, the registry,
  `SyncBindingService.unbind`, `AlertReconcileReason.sync`.**
- `dart analyze lib` clean, the whole suite green, the device pass green with
  no visible change, the master roadmap and the feature doc updated. **Done
  (R7): 9,584 tests; the emulator pass saw no regression (two saved-flow
  faults on the tall emulator, vocabulary and the share-sheet backup round
  trip not driven — covered by suites); master roadmap, the sync reference,
  the persistence rules and the `calendar-events` skill updated in the same
  change.** Left for the owner: the commit, and the pre-existing per-note
  counter restore defect in §8.
