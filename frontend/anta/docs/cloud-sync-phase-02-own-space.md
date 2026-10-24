# Cloud Sync Phase 02 — Own Space on N Devices

**Status: PLANNED 2026-10-24 (Fable 5.1). Decisions D1–D8 await the owner's
letters; the recommended default is marked on each.** The transport phase
of `docs/cloud-sync-roadmap.md`: one Google account, every device shows the
same folders, notes, calendar, counters and alert definitions. Builds on the
readiness phase (`docs/cloud-sync-readiness-roadmap.md`, DONE 2026-10-23,
all in `39b0c7d`): the eighteen CRDT-shaped tables with `owner_id`, the
outbox, the persisted clock, the tombstoning wipes, the unbinding restore
and the engine seams (`SyncGateway` + `FakeSyncGateway`, `SyncStatus`,
`SyncBindingService`, `SyncSuspension`, `requeueAll`). Its decisions D1–D19
stand; where this record refines one it says so. No migration is expected
(schema stays v43). The August version of this file (calendar sync,
ownership, consent) described what is now Phase 03; its one still-live
point — the resurrection trap of a restore — became readiness D9/R4.

**The line this phase draws:** Firestore enters the app here, behind the
gateway only — `lib/services/sync/firestore_sync_gateway.dart` and the
existing `pairing_gateway.dart` are the only files that import it. The
engine is built and proven against the fake first (S2–S4), the Firestore
gateway lands last (S5), the device pass runs against the local Firebase
emulator suite with fake accounts and then on the owner's phone with the
real one (S6). Android first; iOS waits on the Mac-side setup the master
roadmap lists; desktop stays local-only (`SyncAvailability.isSupported`).

## Contents

1. What the owner gets
2. Decisions for the owner (D1–D8)
3. Design — remote shape, the wire, the engine, bind, rules, QA seam
4. Slices S1–S6 (+ S7 optional)
5. Must not change
6. Risk register
7. What only the owner does
8. Deferred
9. How to run this
10. Definition of done
11. What it costs on the Spark plan (from the owner's export)

---

## 1. What the owner gets

- On the Sharing page, signed in, a **Sync** section: "Sync this database"
  turns it on; from then on every change made on this device reaches the
  account's space and every change made on another device of the same
  account arrives here — within seconds while the app is open (the space
  document is a live signal), and at launch or resume otherwise.
- A second device signs in with the same account and, if its database holds
  nothing, binds in one tap; if it already holds data, a picker offers
  "Merge this database into the space" or "Download the space into a new
  database" (readiness D3), or "Upload as a new space".
- Edits on both devices to different things merge; edits to the same thing
  resolve last-writer-wins by the hybrid clock (readiness D5); two devices
  editing the same **note** before syncing keep the losing text as a
  conflict copy (D7, §2 D3 below). Deletes propagate as tombstones.
  Counters merge per value (readiness D8).
- Alerts ring on every device: each device arms its own registrations from
  the synced definitions after every applied batch (readiness D11).
- The status row says what sync is doing: up to date, uploading n changes,
  downloading, offline and retrying, paused (daily limit, another account,
  app outdated), with "Sync now" and "Stop syncing this database".
- What stays as it is: pairing (Phase 01) and the `pairs`/`invites`
  collections, backups (format 7), the restore's unbind, every string of
  the rest of the app.

---

## 2. Decisions for the owner (D1–D8)

Answer with letters ("D1 A, D2 A, …"). A is the recommended default. Each
is reversible before the slice that builds it ships; the slice is named.

- **D1 — How a database starts syncing** (S4). **A:** an explicit "Sync this
  database" row on the Sharing page, enabled once signed in; nothing is
  uploaded before the tap. The first device with no space yet creates the
  account's first space and binds in that tap. **B:** automatic at first
  sign-in, as readiness D3 wrote it. A refines D3's trigger only — sign-in
  is global (pairing uses it too) while binding is per database, and an
  upload nobody asked for is the wrong surprise for a tracker that is
  someone's training log. One more tap, no surprise.
- **D2 — A second device whose database already holds data** (S4). **A:**
  the picker from readiness D3: "Merge this database into the space"
  (initial merge under the bind floor, D15), "Download the space into a new
  database" (creates and switches to a new local database, then binds it),
  or "Upload as a new space". An empty database skips the picker and binds.
  **B:** merge only, no new-database path, no new spaces beyond the first
  (drops the multi-database part of D3 for now). A is one sheet more; B
  would leave a tablet with its own notes no way to keep them separate.
- **D3 — The conflict copy** (S3). **A:** when a strictly newer remote
  note arrives over a note this device changed and has not pushed yet, and
  the texts differ (never during the initial merge under the bind floor),
  the losing text is saved as a new note in the same folder titled
  "`<title>` (conflict copy, `<date time>`)", which syncs like any note, so
  both devices show the original and the copy. Without a device name on
  hand the title carries the time rather than readiness D7's `<device>`
  (a device id is a uuid nobody recognises). **B:** copies go to a root
  folder named "Conflicts". A keeps the copy where the owner is looking.
- **D4 — Where sync status shows** (S4). **A:** the Sync section on the
  Sharing page only — state line, last sync time, pending count, Sync now.
  **B:** also a small cloud glyph in the browser's app bar while something
  is pending or paused. A adds no chrome to the two pages that carry the
  app; B can come with Phase 04's status work.
- **D5 — Sign-out on a bound database** (S4). **A:** the binding stays;
  sync pauses ("Paused — signed out") and resumes when the same account
  signs back in; a different account signing in shows "Paused — this
  database syncs with another account" with "Stop syncing this database" as
  the way out (readiness D3 ii, `SyncPause.accountMismatch` as built).
  **B:** sign-out unbinds (the next sign-in is a fresh bind with a full
  re-merge). A matches the pairing precedent and never discards a floor.
- **D6 — Removing data from the cloud** (S4 / Phase 04). **A:** this phase
  ships "Stop syncing this database" (local unbind, the space stays). A
  "Delete cloud copy" that deletes a space's documents in 500-document
  batches within the daily quota is Phase 04. **B:** "Delete cloud copy"
  now, as a resumable background job with its own status line. A keeps the
  phase on the engine; B is a slice of its own.
- **D7 — The push relay** (S7). **A:** not in this phase: while the app is
  open on both devices changes arrive within seconds through the space
  listener; a device not open catches up at launch and resume. A new alert
  created on the phone will not ring on a tablet that stays closed
  (readiness D11's honesty clause). **B:** the Cloudflare Worker from
  `docs/cloud-sync-connections-design.md` §Push as the last slice, sending
  a "pull now" data message to the account's other devices — needs the
  owner's free Cloudflare account and `firebase_messaging`. **C:** a
  periodic background pull with WorkManager instead of the Worker. A now;
  B when the owner has the account; C is the heavier road (a background
  isolate opening the database beside a live app).
- **D8 — The page's name** (S4). **A:** the Settings row and the page title
  become "Sync & sharing" (`sharingSettings`, en/de/ro), since the page now
  carries the owner's own devices as much as the partner link. **B:** stays
  "Sharing". A is one string in three languages.

Decided here without a question (engineering, reversible, each with its why
in §3): Firestore's local persistence is turned **off** app-wide; the pull
cursor follows **server arrival order** with a ten-second overlap instead
of the readiness `(hlc, rowKey)` cursor; the space document is the change
signal; a remote row older than the local one **re-queues the local row**;
a space written by a newer app schema pauses older devices
(`SyncPause.appOutdated`); no server-side last-writer-wins in the rules.

---

## 3. Design

### 3.1 Remote shape (readiness D1, concrete)

```
users/{uid}/spaces/{spaceId}                 // the space document = the signal
  name: string (≤ 100)                       // "Main" for the default database,
                                             // else the database name
  createdAt: server timestamp
  createdBy: deviceId
  schema: int                                // the highest DatabaseSchema.currentVersion
                                             // that ever pushed here (raised, never lowered)
  touched: { <table>: server timestamp }     // last push that wrote the table
  lastWriter: deviceId, lastWriteAt: server timestamp

users/{uid}/spaces/{spaceId}/{table}/{rowKey}   // seventeen subcollections; never
                                                // content_chunks (readiness D14)
  hlc, deviceId, version, op: 'upsert' | 'tombstone', ownerId: uid
  data: map | null                           // the backup serializer's map; null for a
                                             // tombstone; a note's data carries its body
  pushedAt: server timestamp, pushedBy: deviceId
```

The `rowKey` is the document id exactly as the outbox keys it (readiness
§3: ids as they are; `counterId|noteId`; `eventId|dayEpochMs`). `pairs` and
`invites` stay as shipped. A `users/{uid}/tokens/{token}` collection is the
Worker's (S7 only).

### 3.2 The wire

`SyncEnvelope` as built (`lib/services/sync/sync_gateway.dart:18-55`) is
the document minus the server fields. `SyncCodec` (S2) encodes a row with
its table's **backup serializer** — the wire format is the backup format,
master roadmap stance — and decodes with the same table's import parser;
dates cross as epoch-ms integers; a note's `data` carries `content` (the
chunks joined, readiness D14), so a note is one document and chunks are a
local storage detail the merge rewrites. A note whose document would exceed
Firestore's 1 MiB is refused with a visible reason and parked (§3.5), never
split.

### 3.3 The gateway contract, amended (S1)

The readiness `pullSince(space, table, {sinceHlc, sinceRowKey})` ordered by
`(hlc, rowKey)` (`sync_gateway.dart:99-108`) is replaced, because an HLC
cursor loses rows: a phone edits offline at 09:30 (stamp 09:30), the tablet
meanwhile pulls rows stamped 09:55 from elsewhere and stores that as its
cursor, the phone pushes at 10:05 — its 09:30 row sits below the tablet's
cursor for good. HLC order is write order, not arrival order; a pull must
follow arrival order. So:

- `pullPage(space, table, {SyncCursor? after, int limit, bool resumed}) →
  SyncPullPage(envelopes, next, hasMore)` with an opaque `SyncCursor`
  (`String value`) the gateway defines: Firestore orders by
  `pushedAt`, then document id, and encodes `<pushedAt micros>|<rowKey>`;
  the fake orders by an arrival sequence number. `ack` is dropped (it was a
  hint nobody kept). **Delivery is at least once:** the engine passes
  `resumed: true` on the first page of each table in a run (the cursor came
  from storage) and false for the pages that follow; the merge makes a
  repeated row a no-op. `hasMore` means "a further page may exist" — the
  Firestore gateway answers `page.length == limit`, so the engine accepts
  "hasMore, then an empty page". *(S1 review F1, F10.)*
- When a pull **resumes from a stored cursor** (`resumed: true`), the
  Firestore gateway starts ten seconds before it (`pullOverlap`):
  `request.time`, which `serverTimestamp()` resolves to, is the time a write
  was *received*, and a write received earlier can commit later than a query
  that already ran. The overlap re-reads a handful of rows the merge treats
  as no-ops (an equal stamp changes nothing). Pages inside one pull resume
  exactly, so a 499-row batch sharing one `pushedAt` cannot pin a pull in
  place. The fake has a `replayOnResume` switch (rows re-delivered on a
  resumed page) so the engine's tests see repeats.
- `pushBatch(space, batch, {pushedBy, schema})` writes every envelope with
  `pushedAt = serverTimestamp()` **and**, in the same batch, merges
  `touched[table] = serverTimestamp()` for each table in the batch,
  `lastWriter`, `lastWriteAt` and `schema = mine` into the space document.
  The stored row is replaced unconditionally — no HLC check (§3.7); a stale
  overwrite is repaired by the device holding the newer row (§3.4). The
  document always carries the `data` key (null for a tombstone) and
  `ownerId = space.ownerUid`; `SyncEnvelope.ownerId` is non-nullable and the
  engine fills it with the bound account's uid *(F2)*; a gateway **asserts**
  `envelope.ownerId == space.ownerUid` and throws `ArgumentError` otherwise
  (a programming error, never a remote condition — in Phase 03 a foreign
  row is pushed to its owner's space, so the equality holds there too), the
  fake the same *(S2b review F6)*. **Schema:** Firestore
  has no max transform, so the rule `schema >= stored` does the work — a
  push from an app older than the space's schema is **denied**, which is
  what we want (an outdated device must not write rows lacking columns);
  the fake denies the same way with `permissionDenied`; the engine's
  diagnosis of a denied push is in §3.5 *(F3)*. The gateway's `maxBatch` is
  an instance getter: 499 for Firestore (the space document takes the 500th
  slot), 500 for the fake.
- New: `createSpace(ownerUid, name, deviceId, schema) → SyncSpaceInfo`,
  `listSpaces(ownerUid)`, `readSpace(space)` (null when the document is
  gone), `watchSpace(space) → Stream<SyncSpaceSignal>` (`exists`, `touched`,
  `lastWriter`, `schema`; a missing space emits `exists: false`;
  `createSpace` emits to listeners already subscribed; the stream is
  broadcast on every path, errors included). A push to a space that does
  not exist is **denied** — Firestore's `set(merge: true)` on a missing
  document is a create that fails `validSpace()`; the fake denies the same
  *(F5, F8, F11)*.
- `SyncGatewayFailure` gains `invalidData` — strictly what the server
  reports as `invalid-argument` (a document over 1 MiB). A rule refusal of a
  malformed row arrives as `permission-denied`, so the engine tells the two
  apart by reading the space document after a denied push (§3.5) *(F4)*.

### 3.4 The merge (S2)

One method per table, `mergeRemote(envelope)` on its DAO beside the
existing `NoteDao.mergeNote` (`note_dao.dart:927`), `FolderDao.mergeFolder`
(`folder_dao.dart:743`) and `ContentChunkDao.mergeChunk`
(`content_chunk_dao.dart:316`), all with one contract, in one transaction:

1. Load the local row by key. Absent → insert the remote row with its
   stamps verbatim (`MergeOrigin.remote`: no outbox entry, no new stamp),
   `db.hlc.update(remote)`.
2. Present → compare the HLC strings (the string embeds the device id, so
   equal means the same write). **Remote newer:** write the remote row over
   the local one, stamps verbatim; drop a stale outbox entry
   (`SyncOutboxDao.ackThrough(table, rowKey, localHlc)`) so the overwritten
   local change is not pushed back as an echo. **Local newer:** keep the
   local row and make sure it is queued (`requeueRow(table, rowKey)`, an
   `INSERT … SELECT` of that one row at its own stamp, S2) — this is the
   repair for the lost-update window: a push that landed over a newer
   remote is corrected by the device that holds the newer row, next drain.
   **Equal:** nothing.
3. **Under the bind floor** (the initial merge only, readiness D15 amended):
   while `sync_metadata['bind_merge_pending']` is set, a present row whose
   local HLC is ≤ `bind_floor` yields to the remote even when the remote is
   older; the stale outbox entry is dropped the same way. The engine clears
   the flag after the first complete pull of every table.
4. A tombstone merges like any row (`is_deleted`, `deleted_at`, stamps);
   an upsert newer than a local tombstone resurrects. **No cascade** on a
   remote write: every descendant has its own envelope, because the local
   cascade enqueued each row (readiness R3). Device-local `alert_registrations`
   follow through `reconcileAll(sync)`, not here.
5. Notes: `mergeNoteDocument(note, content)` replaces the chunks when the
   remote wins (the `saveContent` shape without stamping or queueing), keeps
   FTS in step as `mergeNote` does, and returns the overwritten row **and
   whether it had an unpushed outbox entry** — the conflict-copy condition
   (D3). The loser is reported only when the remote is **strictly newer by
   stamp** AND the local row is **above the bind floor** (`floor == null ||
   local.hlc > floor`): at a rebind `requeueAll` has queued every row, so a
   pending entry at or below the floor is not an unpushed change but the
   pre-unbind or restored state the space already knew — a
   restore-then-rebind would otherwise file one copy per note the space has
   newer (S2a review F1, corrected by the S3a review F2: the first fix only
   covered the older-remote direction). A remote tombstone soft-deletes the note's chunks under the remote
   stamp, as a local delete does (F5). Folders and notes keep
   `createFolder`/`createNote`'s `ownerId`.
7. Decoding is strict for a live envelope: a missing or wrong-typed
   required key throws `FormatException` and the engine parks that envelope;
   only a tombstone (`data: null`) takes column defaults (F3). `loadByKeys`
   queries live in DAO methods (tombstones included), never in a binding;
   every binding calls its DAO directly, as the calendar tables do, and the
   engine's hooks call `NoteRepository.invalidateAll()` /
   `FolderRepository.invalidateAll()` after each page — the repositories'
   per-row merge wrappers had no caller and are removed (F2; decided over
   routing through the repositories because the engine's two-database tests
   would otherwise need two repository singletons).
8. **A column added in a later schema** (S2b review F1): rows pushed at an
   older schema stay in the space without the new key, and lower-schema
   pushes are denied, so nothing ever rewrites them. A key added after the
   space's first schema (v43) therefore decodes to its column default when
   absent, even on a live envelope — `WireFields` gains a lenient accessor
   for such columns when the first one appears (none exists today); every
   v43 column stays strict. Row keys are validated for tombstones too: a
   day key must split at `|` into an id and a whole-second epoch-ms, or the
   envelope is a `FormatException` and parks (F2, F3).
6. Returns a `MergeOutcome` (`applied` | `keptLocal` | `unchanged`, plus
   the loser for notes). Nothing above the DAO sees a tombstone (readiness).

Built-in categories (fixed ids) merge like any row. `owner_id` on a pulled
row is stored as received (always the account's uid in this phase).

### 3.5 The engine (S3) — `lib/services/sync/sync_engine.dart`

A singleton on the `DatabaseLifecycle` reset contract (a database switch
stops it; the next `getInstance` builds against the new database's
binding), constructed by DI only when `canSync` (`injection.dart:147`),
holding the gateway, `SyncBindingService`, `SyncStatusService`, the auth
stream and the `AlertScheduler`. It runs only while **bound ∧ signed in as
the bound account ∧ `!SyncSuspension.isSuspended` ∧ not paused**, and
checks all four before every pull, push and bind (readiness §7).

- **Pull.** Tables in dependency order (`calendar_categories`,
  `calendar_event_templates`, `calendar_events`, the three day tables,
  `calendar_event_alerts`, `calendar_category_alerts`, `event_digests`,
  `calendar_filter_presets`, `overview_views`, `folders`, `notes`,
  `counters`, `counter_values`, `vocabularies`, `vocabulary_items`); per
  table page after page from `sync_metadata['pull_cursor.<table>']`; each
  page is applied in **one transaction**: the merges, the cursor, then
  `persistClock()` once (readiness R5). After a page that changed rows, the
  hooks for the tables it touched: `NoteRepository.invalidateAll()`
  (`note_repository.dart:624`) and `FolderRepository.invalidateAll()`
  (`folder_repository.dart:520`), plus the storage services' change events
  (or `FolderSearchService.updateIndex`) for every merged note and folder
  so the browser and the search index see them — the drift streams refresh
  open lists on their own; the calendar services' `reload()`
  (`CategoryService` :104, `EventTemplateService` :70,
  `CalendarEventService` :114, `EventOccurrenceService` :71,
  `EventPresenceService` :74, `EventSkipService` :74, `EventAlertService`
  :131, `EventDigestService` :79, `FilterPresetService` :85,
  `OverviewViewService` :73) then `CalendarEventService.notifyExternalChange()`
  (`calendar_event_service.dart:85`); `CounterService.reload()` (S2 adds it;
  today only `_load()` :98) and `VocabularyService.reload()` (:71);
  `AlertScheduler.reconcileAll(AlertReconcileReason.sync)`
  (`alert_scheduler.dart:341`) once per run that touched the `calendar` or
  the `alerts` class — events and categories feed the planner as much as
  the definitions do (S2b review F7). Envelopes whose `deviceId` is this device's
  are applied like any other (the merge makes them no-ops). **Counters:**
  before a page that touches `counters` or `counter_values` the engine calls
  `CounterService.flush()` — a pending tap flushed afterwards would be
  stamped over the merged value — and after it `reload()` plus the service's
  change signal (S3 adds `CounterService.changes`; the counter blocs reload
  on it) (S2a review F4). **Merged notes and folders reach the UI** through
  the storage services' change events emitted by the engine per merged row
  — the browser, the search index and an open editor (§3.9) listen there.
- **Per-envelope faults.** Decode and merge run per envelope under a catch:
  **any exception that is not a `SyncGatewayException`** (a
  `FormatException`, a `TypeError`, drift's `InvalidDataException`, a
  `StateError`, a `SqliteException` on a constraint) parks that envelope
  (`parkedCount`, logged with its type) and the page goes on — an exception
  that escaped would roll the page back and the next run would hit the same
  cursor forever, stalling every later table and every push (S3b review
  M3); a gateway failure ends the pull. A table whose pull failed for a
  non-gateway reason does not cancel the other tables or the drain. An
  outbox entry whose row no longer exists (an import wipe) is retired; a
  row whose encode fails (a corrupt chunk) or whose document would exceed
  about 900 KB is parked before the push, so a Firestore `invalid-argument`
  is the exception, not the rule (F11). Parked push rows are keyed with
  their stamp, so a shortened note is retried at once (L7); a parked pull
  envelope is skipped for good at that cursor (§8).
- **The signal.** While running and the app is in the foreground, one
  listener on the space document (`watchSpace`). On every snapshot: a table
  whose `touched[table]` moved past `sync_metadata['pull_seen.<table>']` is
  pulled, then `pull_seen` stored. The device's own pushes move `touched`
  too, so its own rows are read back once (one read per row written —
  accepted, §11). A snapshot whose `schema` is above
  `DatabaseSchema.currentVersion` sets `SyncPause.appOutdated` ("Update ANTA
  on this device"), lifted when the app is updated.
- **Push (drain).** Triggered 30 s after the last outbox write (a drift
  `tableUpdates` stream on `sync_outbox`, debounced; readiness D19),
  **immediately** when the app goes to the background
  (`AppLifecycleListener`, the `permission_service.dart:106-120`
  precedent), after a pull, and by "Sync now". A drain: `pending(limit:
  gateway.maxBatch)` → load the current rows by key per table, tombstoned
  rows included (`loadByKeys` never filters `is_deleted`; an entry whose row
  no longer exists is retired, not pushed) → `encode(row, boundUid:)` →
  `pushBatch` → `ackThrough` each entry at the HLC the row had when read (an
  entry bumped by an edit during the push stays queued) → `last_push_at`.
  Repeat until the outbox is empty or a call fails. *(S1 review F2: a
  tombstone envelope needs the row's `deviceId`, `version` and owner, so
  the row is read like any other.)*
- **Failures.** `offline` / `unknown`: retry with back-off 30 s, 1, 2, 5,
  10 min (cap) while in the foreground, at once on resume. `quotaExhausted`:
  `SyncPause.quotaExhausted` with the time; retry hourly and on launch /
  resume, cleared by the first success (readiness D19). `invalidData` (the
  server's `invalid-argument`, a document over 1 MiB): bisect the batch
  (halves, then single envelopes) to find the refused envelope, **park** it
  for the session (in memory; `SyncStatus.parkedCount`; retried next
  launch) and continue — one oversized note must not stop every other row.
  **`permissionDenied` on a push is diagnosed before it is believed**
  *(F3, F4)*: the engine calls `readSpace` once — the document is gone or
  unreadable → `SyncPause.noAccess` until the next sign-in or launch; its
  `schema` is above `DatabaseSchema.currentVersion` → `SyncPause.appOutdated`
  (the rules denied an outdated app's write, by design); otherwise the rules
  refused a row's shape → the same bisect-and-park as `invalidData`, bounded:
  more than twenty parked rows in one drain means the rules themselves
  changed → `noAccess`. Inside the bisect `invalidData` and
  `permissionDenied` are both refusals to isolate (a batch holding one of
  each must not escape the bisect as a bare denial — M5); the diagnosis runs
  once per drain, on the first denial. `permissionDenied` on a pull or on
  `watchSpace` → `noAccess` directly. The gate that decides whether a run
  may start sits inside the run's own error handling, so a thrown gate (a
  closed database) completes the request with a failure instead of hanging
  `syncNow` or the background drain (M4).
- **Order within a run:** pull, then push — so a push never carries a row
  the device would have lost to a newer remote a moment later. **While
  `bind_merge_pending` is set every run is a full run** (all tables pulled
  before any push) and a run that cannot complete the pull does not drain:
  a drain before the floor pull would push the pre-bind rows over the space
  and the floor rule could never undo it (S3b review H1). Without a signal
  yet, every table counts as stale. A background drain (the app leaving the
  foreground) is drain-only and bounded: it never waits for a pull in flight
  beyond the current page, and a never-started engine ignores it.
- **The conflict copy is filed inside the page transaction**, before the
  cursor write: a copy that fails rolls the page back, so the losing text is
  never dropped (H2). The hook therefore only writes through the storage
  path (drift nests the transaction as a savepoint); invalidations stay in
  `afterRun`.
- **Halting re-checks everything cheap:** before each page and each batch
  the engine re-reads the binding and the user besides `stopped` and the
  suspension (an unbind during a run must not let merges, cursors or a
  re-queue land in an unbound database — M6); S4 stops the engine before it
  unbinds anyway.
- **Status.** `SyncStatus` (`sync_status.dart:20`) gains `activity` ∈
  {idle, pulling, pushing}, `lastPullAt`, `lastFailure` (failure + time),
  `parkedCount`, `downloadedRows` (the initial pull's progress), and
  `SyncPause` gains `noAccess`, `appOutdated`, `signedOut`.
  `SyncStatusService.read` keeps computing `accountMismatch`
  (`sync_status_service.dart:57`); the engine publishes the rest through a
  `Stream<SyncStatus>` the `SyncBloc` subscribes to.
- **The conflict copy (D3)** is filed by the engine from the note merge's
  returned loser: a local write through `NoteRepository` (stamped, queued),
  same folder, the loser's body, the title of D3; once per losing merge.
- **Clock.** Every applied envelope passes through `db.hlc.update` inside
  the merge (the drift guard of readiness R5 holds a far-ahead stamp);
  `persistClock()` once per applied page.

### 3.6 Bind, unbind, mismatch (S4)

- `SyncBindingService.bind({space, accountUid})`, one transaction:
  `setSyncBinding` (the four `sync_space_*` keys,
  `settings_keys.dart:405-411`); the `owner_id` backfill `UPDATE <table> SET
  owner_id = ? WHERE owner_id IS NULL` on the seventeen queued tables
  (readiness D17; `content_chunks` stays NULL as built);
  `SyncOutboxDao.requeueAll(boundUid:)` (`sync_outbox_dao.dart:68`); the
  pull cursors and `pull_seen` deleted; `bind_merge_pending := 1`;
  `writeBindFloor()` **only when no floor exists** (readiness D15: a
  never-bound database floors at bind time; a restored or unbound one keeps
  the floor R4 wrote). **A bind while a binding exists is refused**
  (`StateError`, "stop syncing first"): a direct rebind to another account
  would leave the first account's rows owned by it, unqueued and foreign
  under D17 — the unbind writes the floor and clears the queue, and only
  then may another space be bound (S3a review F1). The engine then runs:
  pull everything under the floor rule, drain the re-seeded queue. The
  unbind also clears `quota_paused_at`, `last_pull_at` and `last_push_at`
  (they describe the old space; F7).
- One database ↔ one space, and a space bound at most once per install
  (readiness D3 i): an install-wide registry in `SharedPreferences`
  (`sync_bound_spaces`, through `SettingsService` so the QA prefix applies)
  of `{spaceId, databaseName}`; `bind` refuses a space another database of
  this install holds, with a visible reason.
- **First device, no space:** `createSpace` then `bind`, in the tap (D1).
  **Any device, spaces exist:** the picker (D2) over `listSpaces`.
  "Download into a new database": `DatabaseManager.createDatabase(name)`
  (`database_manager.dart:104`), the switch the Settings database page
  already performs, then `bind` on the fresh database — nothing local to
  merge, the pull fills it.
- **Unbind** = `SyncBindingService.unbind()` as built (keys, outbox, floor,
  one transaction) plus the registry entry and the engine stopping; the
  space is untouched (D6 A).
- **Mismatch / sign-out** per D5. A restore keeps readiness R4's behaviour
  (unbinds inside the suspension, floors after); afterwards the Sharing
  page offers the picker again.

### 3.7 Rules (S1)

Owner-only, shape-checked, no deletes; `pairs`/`invites` untouched.
`pushedAt == request.time` so a client cannot backdate a row below every
puller's cursor. No `hlc` ordering clause: enforcing last-writer-wins in the
rules would fail a whole batch for one stale row in the race window §3.4
repairs client-side. Full text in S1. Deploy:
`firebase deploy --only firestore:rules --project alexs-note-tracking-app`
from `frontend/anta` after adding `"firestore": {"rules": "firestore.rules",
"indexes": "firestore.indexes.json"}` to the gitignored `firebase.json`
(today it holds only the `flutter` block). No composite index: the pull
orders by `pushedAt` then the document id.

### 3.9 The open editor (S4)

The same note open in the editor on two devices is the one case where
last-writer-wins alone loses text: device A's autosave would stamp a stale
body over the row B just merged, and B's edit would vanish on both. So the
editor page listens for the engine's change event on its note: with **no
unsaved modification** since load it reloads the body in place (the caret
kept where it still fits); with **unsaved modifications** it keeps the
user's text and files the *arriving* text as a conflict copy with D3's
title — the next autosave then wins and pushes, and the other device
receives both the note and the copy. Nothing is lost either way. A widget
test pins both branches; S6 drives it on two devices.

### 3.8 Firestore settings and the QA seam (S5)

- `FirebaseFirestore.instance.settings = Settings(persistenceEnabled:
  false)` once, in DI, before any use. The outbox is the one durable queue;
  with the SDK's own queue on, a `commit()` made offline never completes
  and a batch replayed by the SDK after a restart could overwrite a newer
  document. Pairing keeps working — its reads were server reads already
  (`PairingService` reports `offline` / `unavailable`,
  `pairing_service.dart:371,498`); S6 drives the Sharing page offline to
  confirm nothing new surfaces.
- `QaMode.firebaseEmulatorHost` (`ANTA_QA_FIREBASE_EMULATOR`, e.g.
  `10.0.2.2` from a guest) beside `allowCloud` (`qa_mode.dart:29`): when set,
  DI points Auth at `:9099` and Firestore at `:8080`
  (`useAuthEmulator` / `useFirestoreEmulator`) and
  `FirebaseAuthService.signInWithGoogle` signs in with a QA identity the
  emulator accepts without Google (`ANTA_QA_ACCOUNT=<uid>:<email>`; the
  implementer verifies the emulator's fake-token form against the Firebase
  docs and falls back to the emulator's email sign-in). Compiled out
  without `ANTA_QA`.
- `tool/firebase/firebase.json` (tracked): the emulator suite — auth 9099,
  firestore 8080 with `../../firestore.rules`, UI 4000 — and
  `tool/firebase/emulators.cmd` / `.sh` running `firebase emulators:start
  --project demo-anta --config tool/firebase/firebase.json`. Node 26, Java
  25 and firebase-tools 15.27 are on the Windows machine.

---

## 4. Slices S1–S6 (+ S7 optional)

Every slice: one `implementer` (Opus 5.5) from a brief built from its
section here plus §5, then one `reviewer`; the review's fixes ride at the
head of the next slice's run (the readiness recipe); gate = `dart analyze
lib` clean, the whole `flutter test` green, `flutter gen-l10n` with an empty
`untranslated.txt` when ARBs changed. Then one commit by the lead, short
subject, no ledger. The order is fixed: S2 needs S1's cursor, S3 needs S2's
merges, S4 and S5 need S3, S6 needs all.

### S1 — Record, gateway contract, rules

- This record; `docs/cloud-sync-roadmap.md` ladder row 02 and status line;
  `.claude/skills/anta-context/references/docs-index.md`;
  `sync-and-accounts.md` (the cursor amendment, the remote shape);
  the two old-name references (`category-alerts-and-digests-roadmap.md:527`,
  `presence-tracking-roadmap.md:168`).
- `sync_gateway.dart`: §3.3 — `SyncCursor`, `SyncPullPage`,
  `SyncSpaceInfo`, `SyncSpaceSignal`, `pullPage`, `createSpace`,
  `listSpaces`, `readSpace`, `watchSpace`, `maxBatch` as an instance getter,
  `invalidData`; `ack`/`pullSince` removed. `test/support/fake_sync_gateway.dart`
  follows (arrival-sequence cursor, a broadcast signal stream, `failNextWith`
  kept); `test/services/sync/fake_sync_gateway_test.dart` extended (a late
  arrival with a lower HLC is still pulled; a page boundary inside one
  batch; the signal fires once per push with the touched tables).
- `firestore.rules`: under `match /databases/{database}/documents`:

  ```
  match /users/{owner}/spaces/{spaceId} {
    function isOwner() { return signedIn() && uid() == owner; }
    function validSpace() {
      let d = request.resource.data;
      return d.keys().hasOnly(['name', 'createdAt', 'createdBy', 'schema',
                               'touched', 'lastWriter', 'lastWriteAt'])
          && d.name is string && d.name.size() > 0 && d.name.size() <= 100
          && d.schema is int && d.schema > 0
          && d.createdBy is string && d.createdBy.size() <= 64;
    }
    allow get, list: if isOwner();
    allow create: if isOwner() && validSpace()
                  && request.resource.data.createdAt == request.time;
    allow update: if isOwner() && validSpace()
                  && request.resource.data.createdAt == resource.data.createdAt
                  && request.resource.data.schema >= resource.data.schema;
    allow delete: if false;

    match /{table}/{rowKey} {
      function syncedTable() {
        return table in ['folders', 'notes', 'counters', 'counter_values',
          'calendar_events', 'calendar_categories', 'calendar_category_alerts',
          'calendar_event_occurrences', 'calendar_event_absences',
          'calendar_event_skips', 'calendar_event_alerts',
          'calendar_event_templates', 'calendar_filter_presets',
          'overview_views', 'event_digests', 'vocabularies', 'vocabulary_items'];
      }
      function validEnvelope() {
        let d = request.resource.data;
        return d.keys().hasOnly(['hlc', 'deviceId', 'version', 'op', 'ownerId',
                                 'data', 'pushedAt', 'pushedBy'])
            && d.hlc is string && d.hlc.size() > 0 && d.hlc.size() <= 80
            && d.deviceId is string && d.deviceId.size() <= 64
            && d.version is int
            && d.op in ['upsert', 'tombstone']
            && d.ownerId == uid()
            && (d.op == 'tombstone' ? d.data == null : d.data is map)
            && d.pushedAt == request.time
            && d.pushedBy is string;
      }
      allow get, list: if isOwner() && syncedTable();
      allow create, update: if isOwner() && syncedTable() && validEnvelope();
      allow delete: if false;
    }
  }
  ```

  `firestore.indexes.json` unchanged. Deploy only on the owner's yes (§7).
- Skills: `anta-context`, `flutter-principles`. Effort `medium` for the
  implementer: the record fully specifies it.

**As built (2026-10-24, one implementer at medium; gate: `dart analyze lib
test` clean, whole suite green — 9,897 passed, the one Windows-only
`host_devices_test` failure; review below).** Deviations from the plan,
each sound:

- **The emulator config lives at the app root as `firebase.emulators.json`**
  (tracked; the gitignore covers only `firebase.json`), with
  `tool/firebase/emulators.cmd` / `.sh` launching `firebase emulators:start
  --project demo-anta --config firebase.emulators.json` from `frontend/anta`:
  the CLI treats the config's folder as the project folder and refuses
  `../../firestore.rules` as "outside of project directory"; the only other
  shape keeps two copies of the rules.
- **The rules were verified through the emulator's rules endpoint**, not
  `emulators:exec` alone: `firebase emulators:exec … "echo ok"` prints ok
  even for a broken rules file, so the implementer uploaded the file to the
  running emulator (`PUT /emulator/v1/projects/demo-anta:securityRules`):
  the repo rules answer 200, a deliberately broken copy 400 with the line
  numbers. The record's block was placed word for word, one indent deeper.
  Nothing deployed.
- The fake: `touched` accumulates across pushes as a Firestore merge does
  (the test asserts the moved tables are exactly the push's); an empty pull
  returns the cursor it was given as `next` (null only when nothing was
  ever pushed and no cursor came in); a space pushed to before `createSpace`
  gets a signal (schema 0) but stays out of `listSpaces` / `readSpace`;
  `failNextWith` reaches `watchSpace` as a stream error. 13 cases in
  `fake_sync_gateway_test`.
- Housekeeping: on Windows each `emulators:exec` left its Firestore Java
  process alive (six, holding 8080 and 8085–8089); the agent's
  `Stop-Process` was denied by the permission system and the lead did not
  work around it — the owner stops them (`Get-Process java | Stop-Process`)
  before S5/S6 start the suite on 8080.

**S1 review (2026-10-24, one independent reviewer; 0 high, 5 medium, 11
low; "safe to commit as is" — committed as reviewed, the fixes ride at the
head of the S2b run).** The medium findings were contract gaps the engine
would have hit; each is now settled in §3.3/§3.5/§3.7 and marked *(F n)*:
F1 the overlap was inexpressible → `resumed` flag, at-least-once delivery,
the fake's `replayOnResume`; F2 nullable `ownerId` and the `data` key would
have had every tombstone denied → `ownerId` non-nullable, the gateway
always writes both, the pusher reads tombstoned rows; F3 `schema = max`
has no single-batch form → the rule denies a lower schema and the engine
diagnoses a denied push by reading the space; F4 a rule refusal is
`permission-denied`, not `invalid-argument` → `invalidData` narrowed to
size, the same diagnosis routes a malformed row to bisect-and-park; F5 the
fake accepted pushes to uncreated spaces → denied like Firestore,
`SyncSpaceSignal.exists`. Lows to fix in the same pass: F6 the
`touched`-accumulation assertion is mutation-blind (also assert the
untouched table's stamp is unchanged); F7 `failNextWith` untested on
`createSpace`/`listSpaces`/`readSpace`/`watchSpace`; F8 the scripted
`watchSpace` error is single-subscription → `Stream.multi(…, isBroadcast:
true)`; F9/F10 two-listener and exact-boundary cases, a `looseHasMore`
switch; F11 `createSpace` emits to existing watchers; F12 the test's table
`'events'` → `'calendar_events'`; F13 the `pushBatch` doc states the
unconditional replace; F14 `///` on `SyncCursor.value`,
`SyncSpaceSignal.lastWriter`, `SyncSpaceInfo.lastWriteAt`/`lastWriter`;
F15 `emulators.sh` committed with `--chmod=+x` (done at the S1 commit) and
`setlocal` + `pushd`/`popd` in `emulators.cmd`; F16 the rules probe owed in
S5 (listed there).

### S2 — The wire codec and the merge for every table

- `lib/services/sync/sync_codec.dart` (§3.2) and the per-table binding
  registry `lib/services/sync/sync_tables.dart` — one entry per
  `syncedTables` row (`synced_tables.dart:50-69`, minus `content_chunks`)
  with `loadByKeys`, `encode`, `mergeRemote`, the invalidation class and
  the pull order; a test pins that every `syncedTables` entry has one.
- The merge methods of §3.4 on each DAO; `SyncOutboxDao.requeueRow`;
  `mergeNoteDocument`; the floor rule behind `bind_merge_pending`;
  `MergeOutcome`.
- **S2 facts** (the explorer's sweep, 2026-10-24; verify a line before
  building on it). The backup export maps carry data fields only (never
  the clock fields); `JsonKeys` is `lib/constants/json_keys.dart:1`
  (`content` :9, `ownerId` :24), `EventAlertKeys`
  `lib/constants/event_alerts.dart:37`; the day tables write the literal
  key `dayMs` (`event_occurrence_service.dart:194`,
  `event_presence_service.dart:189`, `event_skip_service.dart:187`).
  `database.dart` sets no `PRAGMA foreign_keys` (:404-413), so the pull
  order is for the UI's sake only. Drift streams exist for notes
  (`note_dao.dart:1042`) and folders (`folder_dao.dart:806`) alone; every
  other table is cached in its service.
  - `folders`: export inline `backup_service.dart:75-90`; import appends
    through `createFolder` :400-413 (fresh ids — not the merge's shape);
    `FolderDao.mergeFolder` :743, `insertFolder` :133; cache
    `FolderRepository.mergeFolder` :490 / `invalidateAll` :520.
  - `notes`: export `backup_service.dart:59-73` with the body from
    `contentChunkDao.loadContent` :61 under `content` :66; import appends
    through `createNote` :415-434; `NoteDao.mergeNote` :927 (FTS kept
    :924-926), `insertNote` :147; `NoteRepository.mergeNote` :608 emits no
    `NoteChange`; `invalidateAll` :624 clears `_contentCache` too.
    `FolderSearchService.updateIndex(noteId, title, content)`
    `folder_search_service.dart:598-603`; its index otherwise learns of
    notes only through `_storageService.changes` (:506-519), so a merged
    note needs `updateIndex` or a `NoteChange`.
  - `content_chunks`: no export of its own; `ContentChunkDao.mergeChunk`
    :316 (no repository wrapper); `loadContent` is the read.
  - `counters`: export `counter_service.dart:379-420` as JSON strings
    (`Counter.toJson()` + `ownerId`, `lib/models/counter.dart:26`); import
    wipes (:424) then `insertCounter` (`counter_dao.dart:38`); no merge;
    cache `_counters` :31, `_counterIndex` :34, `_globalValues` :37,
    `_noteValuesCache` :41, `_load()` :98 — **no public reload** (S2 adds
    `CounterService.reload()`).
  - `counter_values`: no per-row map in the backup (folded into
    `globalValues` / `noteValues` / `noteValueExtras`, :417-419) — the codec
    defines the per-row map (`counterId`, `noteId`, `value`, `isPinned`,
    `position`, timestamps, `ownerId`); `CounterDao.upsertValue` :161; no
    merge.
  - `calendar_events`: export `calendar_event_service.dart:262-298`
    (`startDateMs`, `endDateMs`, `assumeAbsentFromMs`, …); import wipes
    :304 then `importAll` (`calendar_event_dao.dart:292`); `upsert` :56,
    `tombstoneEventCascade` :108; cache `_cache` :27, `reload()` :114,
    `notifyExternalChange()` :85.
  - `calendar_categories`: export `category_service.dart:370-387`; import
    `_persistImport` :409 (wipe :410, `importAll`
    `calendar_category_dao.dart:114`, reseed :469); `insertCategory` :139;
    cache `_cache` :45, `reload()` :104, publishes
    `CalendarCategories.updateCache` :116.
  - `calendar_category_alerts`: export `event_alert_service.dart:314`
    (`CategoryAlert.toJson` `lib/models/category_alert.dart:98`); import
    :329; `CategoryAlertDao.importAll` `category_alert_dao.dart:181`; no
    upsert; cache `_byCategory` :129, `reload()` :131.
  - `calendar_event_occurrences` (Dart `EventOccurrenceDescriptions`):
    export `event_occurrence_service.dart:188-201`; import :206 (wipe,
    `importAll` `event_occurrence_dao.dart:202`); `upsert` :42; cache
    `_byEvent` :77, `reload()` :71, facade
    `OccurrenceDescriptions.updateCache`.
  - `calendar_event_absences` (Dart `EventAbsences`): export
    `event_presence_service.dart:183-196` (`status`); import :201;
    `EventAbsenceDao.importAll` `event_absence_dao.dart:162`; no upsert;
    cache `_byEvent` :72, `reload()` :74, facade `EventPresence.updateCache`.
  - `calendar_event_skips` (Dart `EventSkips`): export
    `event_skip_service.dart:181-193`; import :198; `EventSkipDao.importAll`
    `event_skip_dao.dart:140`; no upsert; cache `_byEvent` :72, `reload()`
    :74, facade `EventSkips.updateCache`.
  - `calendar_event_alerts` (Dart `EventAlerts`): export
    `event_alert_service.dart:370-381` (`_rowToAlert(row).toJson()` +
    keys); import :386; `EventAlertDao.importAll` `event_alert_dao.dart:258`;
    no upsert; cache `_byEvent` :124, `_published` :179, `reload()` :131,
    facade `EventAlerts.updateCache`.
  - `calendar_event_templates`: export `event_template_service.dart:116-145`;
    import :151; `EventTemplateDao.upsertTemplate` `event_template_dao.dart:39`,
    `importAll` :124; cache `_cache` :66, `reload()` :70, facade
    `CalendarTemplates.updateCache`.
  - `calendar_filter_presets`: export `filter_preset_service.dart:213-227`;
    import :237; `FilterPresetDao.upsertPreset` `filter_preset_dao.dart:39`;
    cache `_cache` :76, `reload()` :85.
  - `overview_views`: export `overview_view_service.dart:186-200`; import
    :206; `OverviewViewDao.upsertView` `overview_view_dao.dart:35`; cache
    `_cache` :64, `reload()` :73.
  - `event_digests`: export `event_digest_service.dart:177-192`; import
    :198; `EventDigestDao.upsertDigest` `event_digest_dao.dart:33`; cache
    `_cache` :70, `reload()` :79, facade `EventDigests.updateCache`.
  - `vocabularies` / `vocabulary_items`: export
    `vocabulary_service.dart:198-227` with the items nested under `items`
    (:203-212 is the per-item map the codec uses); import :230 / `importItem`
    :277 (`vocabulary_dao.dart:299`); `upsertVocabulary` :53; cache `_cache`
    :31, `reload()` :71, facade `Vocabularies.updateCache`.
- Tests: per table `test/database/<table>_merge_test.dart` (absent → insert
  with verbatim stamps and no outbox row; newer wins and drops the stale
  outbox entry; older keeps local and re-queues it; equal is a no-op;
  tombstone applies; upsert resurrects; the floor rule; notes replace
  chunks and keep FTS; counters' `noteId == ''` key; day keys as epoch-ms);
  `sync_codec_test` round-trips every table's row through encode → decode,
  including a note with a 14 KB body and a composite key.
  `crdt_write_guard_test`'s allow-list grows by the merge helper only.
- Two implementer runs if the reviewer of S1 is still out: S2a browser-side
  (folders, notes, counters, counter values, vocabularies), S2b calendar
  (the rest), as R3a/R3b were. Skills: `drift-migrations`, `anta-context`,
  `calendar-events` for S2b, `flutter-principles`.

**S2a as built (2026-10-24, one implementer; gate: `dart analyze lib test`
clean, whole suite once — 10,014 passed, the one Windows-only failure;
review pending, its fixes ride at the head of S3).** Deviations from the
plan, each sound:

- **One shared merge decision**, `CrdtMerge.mergeRemoteRow` in
  `lib/database/crdt/crdt_merge.dart` (a static on an `abstract final
  class` — the guard scan needs a `x.hlc.update(` receiver and an extension
  would trip `unnecessary_this`): insert / unchanged / applied (+
  `ackThrough`) / keptLocal (+ `requeueRow`) and the floor rule, then
  `db.hlc.update`. `MergeResult` / `MergeOutcome` live in
  `lib/database/crdt/merge_outcome.dart` (DAOs return them; a DAO importing
  from `lib/services/` would invert the layering) and are re-exported by
  `lib/services/sync/sync_table_binding.dart`. The per-table bindings sit in
  `lib/services/sync/tables/<table>_binding.dart`; `sync_tables.dart` holds
  the six in pull order. There is no `sync_codec.dart`: the codec is the
  bindings' `encode`/`decode` plus small helpers in `sync_table_binding.dart`.
- `NoteDao.mergeNote(…, origin)` is gone; `mergeNoteDocument(Note, String?
  content, {floor})` replaces it (its only live callers used `remote`);
  `ContentChunkDao.replaceChunks` hard-deletes and rewrites the split body
  with the note's stamps, nothing queued; preview, length, chunk count and
  `isCompressed` are recomputed from the arriving body with `createNote`'s
  formula. `FolderDao.mergeFolder(Folder, {floor})` returns the outcome; the
  `MergeOrigin` path is gone (`MergeOrigin` stays for `mergeChunk`, which is
  unchanged and unused by the engine). `CounterDao.mergeRemoteCounter` /
  `mergeRemoteCounterValue`, `VocabularyDao.mergeRemoteVocabulary` /
  `mergeRemoteVocabularyItem`. `SyncOutboxDao.requeueRow(table, rowKey)`
  throws `ArgumentError` for an unknown table or one that travels with its
  parent. `CounterService.reload()` flushes pending counts, then `_load()`;
  it notifies nobody (as `importData` does) — refreshing an open counter
  bloc is the engine's (S3).
- **The wire maps gained `position` for notes and counters** (the backup
  leaves it out because a restore rebuilds order from the list; one document
  per row would lose it) under the folder map's existing key. A tombstone
  over an existing row writes only the stamps, `is_deleted`, `deleted_at`
  and `owner_id`; an unknown row's tombstone inserts the minimal decoded row
  (a folder takes its id as the name, the column refuses an empty one). The
  note loser is set when the remote wins over a live local note with a
  pending entry and a different text — a remote tombstone counts as the
  empty text, so an unpushed edit deleted elsewhere is still offered as a
  conflict copy. **To align at the head of S2b:** the implementer sent
  note and folder dates as UTC ISO strings (the backup's local strings
  carry no offset); the roadmap's wire stance is epoch-ms integers, so they
  become `createdAtMs` / `updatedAtMs` like every other table.
- Tests: `test/database/support/merge_contract.dart` (`runMergeContract`,
  eleven cases per table), `folder_merge_test` 13, `note_merge_test` 26,
  `counter_merge_test` 27, `vocabulary_merge_test` 25, `sync_codec_test` 14
  (keys compared with the real `exportData` output for counters and
  vocabularies; a 14 KB note merged into a second database comes back
  identical), `sync_tables_test` 8, `sync_outbox_test` +5 (`requeueRow`);
  the guard test's allow-list is now `CrdtMerge.mergeRemoteRow` and
  `mergeChunk`. Known: `requeueRow` on a composite key scans the table (fine
  at these sizes); no test of its own for `CounterService.reload()` or the
  repository wrappers.

**S2a review (2026-10-24, one independent reviewer; 0 high, 3 medium, 9
low; "the commit stands"). Settled above and fixed in S3a:** F1 under the
floor every differing note was a loser → the loser only when the remote is
strictly newer, a note floor case pins it (§3.4 (5), D3); F2 the bindings
built Drift queries in `lib/services` and skipped the repositories, whose
cache-dropping wrappers had no caller → `loadByKeys` moves into DAO methods
(`get…ByIdsIncludingDeleted`) for the six tables; the bindings keep calling
DAOs and the dead wrappers are deleted — the engine's hooks call
`invalidateAll` per class after a page (§3.4 (7)); F3 decode defaulted live envelopes' missing
keys (an empty body over real text) → strict decode, `FormatException`
parked by the engine (§3.4 (7)); F4 `CounterService.reload()` → the engine
flushes before a counters page and the service gains `changes` (§3.5); F5
a remote note tombstone left its chunks live → soft-deleted under the
remote stamp (§3.4 (5)); F6 a live value under a counter tombstoned
elsewhere reached the backup as an orphan → `exportData` filters values to
live counters, round-trip test; F7 counters sent `createdAt` as an ISO
string → `createdAtMs`; F8 an orphan note under a tombstoned folder → §8;
F9 tests: the clock advances on `inserted`/`applied`, `requeueRow`'s
`ArgumentError`s, the tombstone path writes owner/device/version, the
folder/note wire keys compared with `exportAllData`; F10 the
`crdt_merge.dart` doc on absent rows, `MergeOutcome.loser` typed `Note?`,
`///` on `MergeOutcome.result`, `SyncTableBinding.invalidation`, the
`SyncInvalidation` values; F11 the engine items in §3.5 (per-envelope
catch, retired entries for vanished rows, the size pre-check) and §3.9.
S2b was told mid-run to apply F2's DAO rule and F3's strict decode to its
eleven tables.

**S2b as built (2026-10-24, one implementer; gate: `dart analyze lib test`
clean, whole suite once — 10,209 passed, the one Windows-only failure;
review pending, fixes at the head of S3b).** The S1 fix pass a–j landed as
specified (`pullPage(…, resumed:)`, `ownerId` required, the schema and
missing-space denials in the fake, `SyncSpaceSignal.exists`,
`replayOnResume` / `looseHasMore`, the 23-case fake suite, `emulators.cmd`
with `setlocal`/`pushd`, note and folder dates as `createdAtMs` /
`updatedAtMs`). The eleven calendar tables: one `mergeRemote<Row>` per DAO
through `CrdtMerge.mergeRemoteRow` (unchanged — no table needed more),
`mergeRemoteEvent` never cascading; each id-keyed DAO gained
`getByIdsIncludingDeleted`, each day DAO `getByDayKeysIncludingDeleted`
(narrowed by `event_id IN`, the primary-key prefix, then matched through
`dayRowKey` in Dart); eleven bindings under `lib/services/sync/tables/`
whose wire `data` equals each service's real `exportData` map value for
value (no `sortOrder` had to be added — every table that has one exports
it); **`WireFields`** in `sync_table_binding.dart` is the strict decoder: on
a live envelope a missing or wrong-typed non-nullable field, a wrong-typed
nullable one, or an `id` / `eventId` / `dayMs` that disagrees with the row
key throws `FormatException('<table>: "<key>" is missing or not a
<Type>')`; a tombstone takes the column defaults; `dayKeyOf(rowKey)` splits
at the last `|`. Alert bindings write the raw columns under `EventAlertKeys`
so a mode this build does not know crosses unchanged. `sync_tables.dart`
holds the seventeen bindings in pull order; the completeness pin runs both
ways. Tests: eleven `<table>_merge_test` files (140 cases, each with the
eleven-case contract and a DST-day key for the day tables), `sync_codec_test`
48, `sync_tables_test` 19, `fake_sync_gateway_test` 23. Left for the S3
head pass, as planned: S2a's six bindings (`loadByKeys` into DAOs, strict
decode) and the counters' `createdAt` as epoch-ms.

**S2b review (2026-10-24, one independent reviewer on a `git archive`
snapshot of the commit, seven mutation probes; 0 high, 1 medium, 9 low;
"the commit stands").** Settled: F1 a column added in a later schema would
park every older row on a fresh device → §3.4 (8); F6 two sources for the
document's `ownerId` → the gateway asserts equality (§3.3); F7 a `calendar`
page also reconciles alerts (§3.5). **Fixed at the head of S3b:** F2
`dayKeyOf` throws `RangeError`, not `FormatException`, on a key without `|`
(and a non-numeric day decodes to 0) — both become `FormatException`; F3 a
day tombstone can be stored under a key other than its envelope's
(tombstones skip the key check and the merges recompute the key) — validate
the key for tombstones too and refuse digits that are not a whole second;
F4 in ten of eleven tables nothing pins that a tombstone keeps the data
columns (mutation: `replace(remote)` on the tombstone branch passed) — the
contract's tombstone case asserts the marker column; F5 the fake's denial
tests do not assert `lastWriter` / `touched` unchanged; F8 the day loads
narrow by `event_id IN` alone — add `day IN`; F9 `///` on `WireFields.table`
/ `data` / `live`; F10 `.gitattributes` with `*.cmd text eol=crlf` and
`*.sh text eol=lf` (the `.cmd` is LF in the index today). **Incident:** a
mutation probe used a relative path that resolved against the process's
working directory and wrote a cascade line into the tree's
`calendar_event_dao.dart` for about two minutes before the reviewer noticed
and `git restore`d the one file (verified clean afterwards; S3a's final
whole-suite run covers the window). Rule for every later reviewer brief:
probes run only in a scratch copy addressed by absolute path.

### S3 — The engine

Run as three implementer runs (decided 2026-10-24 after S2b: one run of
this size risks the agent's turn cap, and each part is a review point):
**S3a** foundations at `medium` — the S2a fix pass F1–F10, the bind core
(`SyncBindingService.bind`, §3.6, without the install registry and the
picker), `SyncStatus` / `SyncPause` additions, the `sync_metadata` keys
(`pull_cursor.<table>`, `pull_seen.<table>`, `bind_merge_pending`,
`last_pull_at`, `quota_paused_at`), `detached` constructors so a test can
hold two binding and status services; **S3b** the engine core against the
fake with the convergence suite, its app-facing effects behind an injected
`SyncApplyHooks` interface (`beforePage`, `afterPage`, `afterApplied`,
`fileConflictCopy`) with a recording fake; **S3c** the production hooks
(the invalidations, the storage services' change events for merged rows,
counters flush/reload/`changes`, the conflict copy with its l10n title),
`SyncBloc`, DI behind `canSync` and a registered gateway, the lifecycle
triggers and timers, and the rehearsal on the owner's export; **S3d** (added
after the S3b review) the engine fixes H1–H2, M3–M6 and the lows, with the
tests the review named, before S4 builds on the engine.

**S3a as built (2026-10-24, one implementer at medium; gate: `dart analyze
lib test` clean, whole suite once — 10,272 passed, the one Windows-only
failure; review pending, fixes at the head of S3c).** The S2a fix pass
F1–F3, F5–F7, F9, F10 landed as specified, with these shapes: one shared
`CrdtMerge.loadInChunks` (500 keys per statement) behind the six new DAO
loads (`FolderDao` / `NoteDao.getByIdsIncludingDeleted`,
`CounterDao.getCountersByIdsIncludingDeleted` /
`getValuesByKeysIncludingDeleted`, `VocabularyDao.getVocabulariesByIdsIncludingDeleted`
/ `getItemsByIdsIncludingDeleted`); the repositories' merge wrappers deleted;
a remote note tombstone soft-deletes the chunks through the existing
`softDeleteChunksForNote(noteId, CrdtStamp)` with the remote stamp (no new
method); `CounterService.exportData` filters the three value maps to live
counters (the `counters` list itself still comes from the in-memory cache —
S3c's flush/reload around counter pages keeps it honest); the counters wire
map is `Counter.toJson()` minus `createdAt` plus `createdAtMs`, an unknown
`scope` decodes to global as `Counter.fromJson` does; the folder/note wire
keys stay a literal list (`BackupService` cannot be pointed at a test
database — twelve singletons through `getInstance()`). **Bind core:**
`SyncBindingService.bind({space, accountUid})` is one transaction — the
binding keys, the `owner_id` backfill through `customUpdate` with each
table's `TableInfo` (watchers notified), `requeueAll`, the `pull_cursor.` /
`pull_seen.` keys deleted, `bind_merge_pending = '1'`, the floor only when
none exists; a bind while suspended throws `StateError`; `unbind()` also
clears the pull keys and the flag; rollback proven through a
`QueryInterceptor` that throws on the flag's insert. `SyncBindingService.detached`
and `SyncStatusService.detached` for two-database tests (`SettingsService`
has no detached form: `forTesting(db1)`, `reset()`, `forTesting(db2)` — the
first instance keeps its own database). **Status:** `SyncPause` +
`noAccess` / `appOutdated` / `signedOut`; `SyncActivity`; `SyncFailureInfo`
over `SyncGatewayFailure`; `SyncStatus` + `lastPullAt`, `activity`,
`lastFailure`, `parkedCount`, `downloadedRows`, `copyWith`; the status
service reports `signedOut` when bound with no user. **Keys:**
`SyncDao.keyBindMergePending`, `keyLastPullAt`, `keyQuotaPausedAt`,
`keyPullCursor(table)` / `keyPullSeen(table)` with public prefixes,
`deleteByPrefix` (matched with `substr`, not `LIKE` — `_` is a wildcard;
an empty prefix refused). Tests: `sync_codec_test` 56,
`sync_binding_service_test` 15, `sync_status_service_test` 10,
`sync_dao_test` 4, `note_merge_test` 29, `folder_merge_test` 16,
`counter_merge_test` 33, `sync_outbox_test` 58, `counter_service_test` 4;
all seventeen merge suites 269.

**S3a review (2026-10-24, one independent reviewer on a snapshot, two
mutations, four behaviour probes; 0 high, 4 medium, 10 low; "the commit
stands").** Settled: F1 a bind over an existing binding to another account
left the first account's rows owned, unqueued and foreign → `bind` refuses
while bound (§3.6); F2 the loser rule still filed a copy for every restored
note the space had newer → the loser needs the local row above the floor
(§3.4 (5)). Handed to S3b mid-run: F3 the counter export test compared JSON
strings whose key order differs between the creation-order cache and the
DB (one run in three failed) → compare decoded maps; F4 a `counter_values`
key without `|` threw `RangeError` → `FormatException` with a codec case;
F5 a live envelope that passes `WireFields` can still fail drift's
`withLength` check → `InvalidDataException` joins the engine's park list.
**Fixed at the head of S3c:** F1 and F2 above (with their tests); F6
`exportData` still mixed the in-memory `counters`/`globalValues` with the
DB's `noteValues` → everything from the live DB set after `flush()`; F7
`unbind`/`bind` kept `quota_paused_at`, `last_pull_at`, `last_push_at`; F8
the rollback test arms the interceptor only on the flag insert → also on
the first backfill `UPDATE` and the floor insert; F9 a `detached(db2,
settings1)` pair would write the binding into the other database → an
assert that the settings service's database is the bound one, and a doc
line; F10 `getValuesByKeysIncludingDeleted` narrows by `counter_id` alone →
add `note_id IN`; F11 a 128-character doc line in `crdt_merge.dart`; F12
`///` on `SyncFailureInfo.failure` / `.at` and the `SyncActivity` values;
F13 `sync_bloc_test` asserts a `signedOut` status reaches `SyncSignedOut`.
F14 (an unknown counter `scope` decodes to global) accepted — a newer enum
value can only come from a newer schema, which `appOutdated` already stops.

**S3b as built (2026-10-24, one implementer; gate: `dart analyze lib test`
clean, whole suite once — 10,322 passed, the one Windows-only failure;
review pending, fixes at the head of S4).** The S2b fix pass F2–F6, F8–F10
landed (a day key is refused unless `dayRowKey(id, day)` reproduces it byte
for byte, tombstones included; `WireFields` refuses an empty row key; the
day loads narrow by `event_id IN` and `day IN`; the fake asserts
`envelope.ownerId == space.ownerUid`; `.gitattributes` for `.cmd`/`.sh`),
plus the three S3a-review items handed over mid-run (the counter export
test compares decoded maps; a `counter_values` key without `|` is a
`FormatException`; drift's `InvalidDataException` joins the park list).
**The engine:** `lib/services/sync/sync_engine.dart` (one file of about
1,090 lines with private `_Puller` / `_Pusher`), `sync_apply_hooks.dart`
(`SyncApplyHooks`: `beforePage`, `afterPage`, `afterRun`,
`fileConflictCopy`; `SyncAppliedRow`, `SyncNoteConflict`,
`NoOpSyncApplyHooks`), `sync_scheduler.dart` (`SyncScheduler`,
`TimerSyncScheduler`); `SyncEngine.detached(…)`, `status` / `current` /
`whenIdle`, `start` / `stop` / `dispose`, `syncNow → SyncRunReport`
(`pulledRows`, `pushedRows`, `parked`, `failure`, `skipped ∈ SyncRunSkip`),
`onAppResumed` / `onAppBackgrounded`, static `reset()` and
`registerForTesting` through one `_register` that also registers with
`DatabaseLifecycle` (S3c's `getInstance` only constructs and registers).
The outbox trigger is `SyncOutboxDao.watchQueued()` (insert updates only;
the guard test forbids naming `syncOutbox` outside its owners). Shapes
chosen: a drain trigger (debounce, background) is a run that first pulls
the tables the latest signal marked stale, then drains; `pull_seen.<table>`
stores the signal value read *before* the table's first page, as
microseconds, so a push landing mid-pull leaves the table stale; an empty
page gets no transaction, no hooks, no `persistClock`; `afterRun` only when
something changed, in a `finally`; a suspension keeps the signal attached
(nothing announces its end), every other not-runnable state detaches it;
sign-in lifts `noAccess`; a quota hold is lifted by its retry, by resume and
by `syncNow` but shows until a call succeeds, and a stored `quota_paused_at`
at `start()` shows the pause and retries at once; `whenIdle` also waits for
re-evaluations and debounced drains; `syncNow` on a stopped engine reports
`skipped: suspended` (S4 head: a `stopped` value). Test support:
`recording_sync_apply_hooks.dart`, `manual_sync_scheduler.dart`,
`test/services/sync/support/sync_pair.dart` (two databases A/B, one
ms-ticking wall clock, the settings recipe, a per-table snapshot
comparator); the fake gained `refuse`, `deleteSpace`, `plant` and a `calls`
log. Tests: `sync_engine_test` 15 (convergence of all six row kinds,
different rows, LWW on an event, the conflict copy once on the loser's
device, tombstone + chunks, folder cascade, resurrection, late arrival,
`replayOnResume` no-ops, the lost-update repair, both floor cases, pull
before push, `persistClock` once per page over 501 rows, hasMore then
empty), `sync_engine_failures_test` 11 (back-off and its reset, quota,
bisect-and-park for `invalidData` and a refused row, > 20 refused →
`noAccess`, a deleted space, schema 44 → `appOutdated`, malformed and
empty-name documents, a hard-deleted row retired, a 950 KB note parked),
`sync_engine_lifecycle_test` 15 (the signal pulls only the moved table,
`appOutdated`/`noAccess` via the signal, single-flight, suspension
mid-page, the database switch, debounce and background drains, the hook
classes incl. `alerts` for a calendar page, the status sequence, signedOut,
accountMismatch, sign-back-in, unbound, `lastFailure` cleared);
`fake_sync_gateway_test` 27. Noted: a row created after the bind keeps
`owner_id` NULL locally while the merging device stores the uid — both mean
"mine" (readiness D12), the comparator ignores the key; §8.

**S3b review (2026-10-24, one independent reviewer on a snapshot, five
mutations, six behaviour probes against real in-memory databases; 2 high,
4 medium, 17 low; "the commit can stay as the base, fix 1 and 2 before the
hooks and the lifecycle are wired").** Both highs are data-loss paths that
need a trigger S3b's tests never produced: **H1** a run with no signal yet
(`onAppBackgrounded`, the debounced drain, any run before the first
snapshot) pulled nothing and drained, so under the bind floor a device's
pre-unbind rows overwrote the space and a newer edit vanished everywhere
(probe: the unbound-then-rebound case with a background drain in place of
`sync` ends with the stale text on both devices); **H2** the conflict copy
was filed after its page committed, so a copy that failed (a title clash,
a storage error, a database switch mid-run) lost the losing text for good
(probe: a throwing hook, zero chunks of the lost text afterwards). Mediums:
M3 an exception outside the park list stalls the table and every push
forever (probe: a `StateError` from one planted row, three runs at cursor
null); M4 the run gate outside the error handling hangs `syncNow` on a
closed database; M5 the bisect rethrows a refusal of another kind, so a
batch with one `invalidData` and one `permissionDenied` row ends in
`noAccess`; M6 the halt check ignores the binding and the user, so an
unbind during a run still writes cursors and merges into the unbound
database. All six are rules in §3.5 now. **Fixed in a dedicated run (S3d)
right after S3c, before anything else builds on the engine:** H1, H2, M3,
M4, M5, M6 and the lows — L7 parked push rows keyed with their stamp; L9
`quota_paused_at` deleted on any success; L10 a `stop()` during `start()`'s
first await leaks subscriptions; L11 the signal subscription needs
`onDone`; L12 a never-started engine answers the lifecycle calls; L13 the
signal's re-attach shares the run back-off; L14 `onAppBackgrounded` is
unbounded; L15 moot under H1's rule; L16 `ArgumentError` on the park list
also swallows programming errors — park but log at warning; L17 a throwing
`afterRun` in the `finally` masks a halt; L18 tests for every item above
plus a page that fails part-way (the cursor stays) and a halted table (no
`pull_seen`); L19 the comparator also ignores `deviceId`/`version` — say so
in its doc; L20 `///` on the `SyncRunSkip` values, the untrue comment at the
bisect, and the file split into `part` files. L8 (a parked pull envelope is
skipped for good) → §8. Handed to S3c mid-run: the bloc reads `current` and
survives a dead engine; hooks resolve per call; the copy hook must be
transaction-safe; the bridge is a no-op before `start()`.

**S3c as built (2026-10-24, one implementer; gate: `dart analyze lib test`
clean, gen-l10n with `untranslated.txt` = `{}`, whole suite once — 10,369
passed, the one Windows-only failure; review pending, fixes at the head of
S4).** The S3a fix pass F1–F13 landed (F9 as a doc line only —
`SettingsService` exposes no database handle), plus `SyncRunSkip.stopped`.
**Wiring:** `lib/services/sync/app_sync_apply_hooks.dart` — every target
resolved per call through injectable thunks (GetIt for repositories and
storage, `getInstance()` for the singletons); `beforePage` flushes counters;
`afterPage` announces merged notes and folders through the new
`NoteRepository.announceMerged(ids, inserted:)` /
`FolderRepository.announceMerged` (re-read the row, drop its caches, emit
`created` / `updated` / `deleted` — a remote folder move is announced as
`updated` under the new folder, the drift streams refresh the old list);
`afterRun` invalidates the repositories, reloads the ten calendar services
in order then `notifyExternalChange()`, reloads alerts and digests, one
`reconcileAll(sync)` for `calendar` or `alerts`, `CounterService.reload()`
(which fires the new `changes` stream the counter blocs refresh on, the
per-note bloc in place without a loading state), `VocabularyService.reload()`
— each cache effect guarded so one failing service is logged and the rest
run; `fileConflictCopy` is unguarded and transaction-safe (settings
language, the title check, the insert through `NoteStorageService.createNote`
with the loser's folder and label, the folder's next free position, a
` (n)` suffix when the same minute already holds the title), titled with
the new `syncConflictCopyTitle` (en/de/ro, placeholders `title`,
`dateTime` `yMd`+`Hm`) in the app's stored language, else the device
locale, else English. `SyncBloc`: an optional `engine` thunk resolved on
every load and sign-in (a generation counter drops an overtaken
resolution), starts from `engine.current`, applies an engine status only to
the shown account's state, `SyncNowRequested`, `SyncEngineStatusChanged`,
unsubscribes on close. `SyncEngine.getInstance()` (GetIt for the gateway and
identity, `StateError` without a gateway) and `isStarted`; `reset()`
disposes the bridge. `lib/services/sync/sync_lifecycle_bridge.dart` on
`PermissionService.appLifecycle()`: resumed → `onAppResumed`, one
`onAppBackgrounded` per leave, nothing before `start()` or after `stop()`.
DI: `_syncEngineEnabled` = a registered gateway ∧ `AuthService.isAvailable`
(false on `NoOpAuthService`, so it also covers a failed Firebase init);
the engine starts unawaited after auth and pairing; the bloc factory
passes the thunk or null; `resetDependencies()` resets the engine first.
Nothing registers a gateway until S5, so the app does not sync yet. Tests:
`app_sync_apply_hooks_test` 15, `sync_lifecycle_bridge_test` 6,
`counter_bloc_test` 3, `counter_per_note_bloc_test` 2,
`counter_service_test` 7, `sync_bloc_test` 35 (+14),
`test/support/fake_sync_engine.dart`. Noted for S4: `RefreshSyncStatus`
replaces the engine's own fields until its next emit — the reader should
merge `engine.current`; a conflict copy goes into the loser's folder even
when that folder was meanwhile tombstoned (S3d files it at the root then).
**The rehearsal** is in §11.

- `sync_engine.dart` per §3.5, with `sync_puller.dart` / `sync_pusher.dart`
  if it reads better; `SyncStatus` / `SyncPause` additions; the
  `Stream<SyncStatus>`; the engine registered in DI behind `canSync`
  (`injection.dart:145-156`) and on the lifecycle reset; `SyncBloc`
  (`sync_bloc.dart:35-39`) subscribes and gains `SyncNowRequested`.
- Tests: `test/services/sync/sync_engine_test.dart` with **two in-memory
  databases and one fake gateway** — the convergence suite: an edit on A
  appears on B; both edit different rows; both edit the same event (LWW);
  both edit the same note (conflict copy on the loser's device, then both
  show both notes); a tombstone and a cascade propagate; a resurrection;
  counters per value; the late-arrival case (A's lower-HLC row pushed after
  B pulled higher ones); the lost-update window (A overwrites B's newer
  row; B re-queues; convergence after B's drain); offline back-off; quota
  pause and clear; `invalidData` bisect and park; suspension stops a drain;
  a database switch stops the engine; `persistClock` once per page; the
  hooks called once per applied page; the pull-before-push order; the
  initial merge under the floor (never-bound, unbound-then-rebound,
  restored). Benchmarks carry the `benchmark` tag.
- **Rehearsal, local only, never committed:** a throwaway test opens a copy
  of the owner's export (`C:\Users\mobx3\Downloads\gym_notes_anta.db`,
  schema v42) through `AppDatabase` on a temp file — the v43 migration runs
  on real data — binds it against the fake with a second empty database,
  drains, pulls, and compares row counts per table. The numbers go into
  this record's §11 "as rehearsed"; the test file is deleted.
- Skills: `anta-context`, `calendar-events`, `flutter-principles`.

### S4 — Bind, the picker, the Sync section

- `SyncBindingService.bind` and the install registry (§3.6);
  `SyncSpaceService` (create / list through the gateway, the space name
  rule); `SyncBloc` events `BindRequested(space?)`, `UnbindRequested`,
  states carrying the picker's data; the Sharing page
  (`sync_settings_page.dart:150-186`): a **Sync** section between Account
  and Pairing with the status row (D4) and the bind / unbind row, the
  picker as a form sheet (`ui-language`: `FormSheetFrame`, choice rows, the
  semantics ids catalogue), D1/D2/D5/D6/D8 as lettered; strings in
  `app_en.arb` / `app_de.arb` / `app_ro.arb` together, `flutter gen-l10n`,
  `untranslated.txt` empty; the Settings row title per D8.
- The "download into a new database" path reuses the database page's
  create-and-switch; the new database binds with no local rows.
- The editor's behaviour on a merged note (§3.9): the note editor page
  listens to the storage service's change event for its note; clean →
  reload in place; dirty → keep the text, file the arriving text as a
  conflict copy through the same path S3 uses.
- Tests: `sync_binding_service_test` (+ bind: keys, backfill on seventeen
  tables with `content_chunks` untouched, `requeueAll`, cursors cleared,
  the floor only when absent, the registry refusal, one transaction — a
  failure leaves nothing bound); `sync_bloc_test` (+ bind / unbind /
  sync-now / mismatch / signed-out status); a widget suite for the Sync
  section and the picker against the robots in `test/widgets/support/`
  (every state line, the disabled row signed out, the picker's three
  choices, semantics ids, text scale 2.0 without overflow); the editor's
  two §3.9 branches as widget tests against a fake storage change.
- No `designer` run (the section is settings rows and a two-choice form
  sheet on existing primitives); a `design-reviewer` pass after the build.
  Skills: `ui-language`, `l10n`, `anta-context`, `flutter-principles`.

### S5 — The Firestore gateway and the emulator seam

- `lib/services/sync/firestore_sync_gateway.dart` per §3.1/§3.3: batches
  with the space document merged in, `pushedAt = serverTimestamp()`,
  `maxBatch = 499`; `pullPage` as `orderBy('pushedAt').orderBy(
  FieldPath.documentId).startAfter([ts, rowKey]).limit(n)` from `Source.server`,
  the ten-second overlap on a stored cursor; `watchSpace` over
  `snapshots()`; `FirebaseException.code` mapped the way
  `FirestorePairingGateway._guard` does (`pairing_gateway.dart:134-159`):
  `unavailable` / `deadline-exceeded` → `offline`, `resource-exhausted` →
  `quotaExhausted`, `permission-denied` / `unauthenticated` →
  `permissionDenied`, `invalid-argument` / `failed-precondition` →
  `invalidData`, else `unknown`. Persistence off in DI (§3.8). DI binds the
  gateway behind `canSync`.
- The QA seam and `tool/firebase/` (§3.8); `qa build` already passes extra
  defines (`tool/qa/src/apk_build.dart:20-21`, `runner.dart:11-12`).
- Tests: the pure parts extracted and unit-tested — the cursor codec, the
  envelope ↔ document map (both directions; a tombstone document carries
  the `data` key as null and `ownerId = space.ownerUid`; the space document
  merge payload with `schema = mine`), the error mapping, the overlap
  arithmetic on `resumed`; a source-scan test that no file outside the two
  gateways imports `cloud_firestore`. **A rules probe against the emulator**
  (S1 review F16): through the emulator's REST surface or
  `@firebase/rules-unit-testing`, the allow/deny cases — owner read and
  write; a stranger denied; a tombstone with `data: null` allowed and one
  without the key denied; `ownerId` null denied; a lower-schema merge
  denied, equal and higher allowed; a push to a missing space denied; an
  unknown table denied; `pushedAt` not `request.time` denied.
- Skills: `anta-context`, `qa-emulator` (for the defines), `flutter-principles`.

### S6 — Gate, device pass, docs

- The gate; `qa-runner` runs the two-device pass: the emulator suite on the
  host (`tool/firebase/emulators.cmd`), two fleet guests (`emulator-5556`,
  `emulator-5558`) with a QA build carrying `ANTA_QA_CLOUD=true`,
  `ANTA_QA_FIREBASE_EMULATOR=10.0.2.2`, `ANTA_QA_ACCOUNT=qa1:qa1@example.com`;
  the step list (explicit `qa` verbs by semantics id, alternating `-d`):
  sign in on both; "Sync this database" on A (creates the space); a note
  and an event created on A through the saved flows; B: sign in, "Sync
  this database" → the picker → merge; B shows the note and the event
  within the wait; an edit on B reaches A; a delete on A reaches B; the
  Sharing page offline on A shows the pairing row unchanged and the status
  "Offline"; a second QA account on B shows the mismatch state; finally the
  existing calendar, browser and alerts suites once each (no regression).
- The owner's real check (§7), then: `sync-and-accounts.md` (the engine as
  built), the `calendar-events` skill's sync note, `docs/cloud-sync-roadmap.md`
  ladder row 02 DONE, this record's status and "As built" blocks.
- Skills: `verify`, `qa-emulator`, `delegation`.

### S7 — The push relay (only on D7 B)

`docs/cloud-sync-connections-design.md` §Push, narrowed: the Worker
verifies the caller's ID token and sends an FCM data message `{type:
'pull', spaceId}` to `users/{uid}/tokens/*` minus the sender; the app
registers its token (`firebase_messaging` ^16.x, the token service off the
lifecycle contract as that design says), calls the Worker after each
successful drain, and on a message runs a pull if the app is alive — a
background isolate opening the database beside a live app is out of scope
(readiness D11's honesty clause stands for a closed app). Rules for the
tokens collection; the owner's Cloudflare account; `wrangler` on the
machine.

---

## 5. Must not change

- Everything in the readiness record §5: the `gym_notes` directory and the
  `device_id` file; backup format 7 (`owner_id` as the additive key, no
  clock fields); the HLC string encoding; soft-delete semantics, positions,
  sort preferences, `noteId == ''`, pinned counters; `AuthService` off the
  lifecycle reset contract, every sync singleton on it;
  `SyncAvailability.isSupported` the single platform gate; the pairing and
  binding keys out of backups.
- The readiness invariants as built: the outbox written only inside
  `CrdtWrite` (S2's `requeueRow` and the merges' `ackThrough` retire or
  re-seed entries without minting a stamp; the guard test's allow-list
  grows by the merge helper alone); `content_chunks` never queued;
  `requeueAll` never lowering a newer entry; the restore unbinding inside
  `SyncSuspension.run`; `tombstoneAll` for "Delete all events"; the clock
  seeded before the instance is handed out and persisted forward-only; the
  drift guard (`maxDrift`, one hour).
- Pairing: `pairs` and `invites` rules, the `PairingService` flows and the
  Pairing section untouched; with persistence off the page behaves offline
  as it does today (S6 drives it).
- No Firestore type outside `pairing_gateway.dart` and
  `firestore_sync_gateway.dart` (a source scan pins it); no Firebase type
  above the service layer (`AppUser` stays the boundary).
- Settings through `SettingsService` + `SettingsKeys`; every string through
  `AppLocalizations` in three languages; the `Page → BLoC → Service →
  Repository → DAO` layering — the engine is a service, the page talks to
  `SyncBloc` only.
- The two pages that carry the app gain no chrome (D4 A); no new
  state-management, persistence or navigation pattern.
- No migration unless a reviewer proves one is needed; if so, v44 with the
  `drift-migrations` recipe and the owner told first.

---

## 6. Risk register

- **High — a push overwrites a newer document (the race window).** Pull
  before push narrows it; the receiver's re-queue (§3.4) repairs it on the
  next drain; the convergence test pins both. Residual: both devices never
  come online again after the overwrite — the newer row then lives only on
  one device, as it would without sync.
- **High — the pull misses a row.** The HLC cursor would have (§3.3); the
  arrival cursor with the ten-second overlap is the answer; the late-arrival
  test pins it. Residual: `serverTimestamp()` semantics beyond ten seconds
  of receive-to-commit skew — unseen in practice; the overlap is a constant.
- **High — the same note open on two devices.** Without §3.9 an autosave
  on one device overwrites a merged body with stale text and the other
  device's edit vanishes on both. §3.9 keeps both texts (a clean editor
  reloads, a dirty one keeps its text and files the arriving text as a
  conflict copy); S4 pins it, S6 drives it.
- **High — the first install on the phone migrates real data to v43.** The
  gate's migration suite is green on synthetic shapes; S3's rehearsal runs
  the migration on the owner's export first. The owner's export of
  2026-10-24 is the fallback.
- **Medium — persistence off changes pairing's feel offline.** Its reads
  already reported `offline`; S6 drives the page offline before the owner's
  check.
- **Medium — schema skew between devices** (phone on v43, tablet on a later
  app). A newer app raises `schema` on its first push and older devices
  pause with "Update ANTA on this device"; the owner keeps both updated.
  The rule `schema >= stored` denies an outdated app's push outright (S1
  review F3), so an older device cannot drop the new columns on rows it
  writes; it pauses until updated.
- **Medium — a poison document.** Bisect-and-park (§3.5) keeps the queue
  moving; the parked count is visible; a row stays parked until the note
  is shortened. Deferred: a persistent park list.
- **Medium — the daily quota on a bad day.** `quotaExhausted` pauses with
  the reason and retries hourly; §11 shows the owner's space is far from
  the limits; the auto-save path still coalesces per row in the outbox.
- **Low — two local databases of one install in one space** (readiness D3
  i): the install registry refuses the second bind.
- **Low — the listener's cost**: one read per remote push plus the device's
  own rows read back once; §11.
- **Low — Google Sign-In on a Play-image emulator** needs the owner's
  account typed once; the QA pass uses the Auth emulator instead.

---

## 7. What only the owner does

1. The letters for D1–D8 (§2).
2. A **yes before the rules deploy** (S1) — it touches the live project the
   pairing feature uses; the deploy adds matches and changes none.
3. Nothing in the Firebase console is expected: Google Sign-In and
   Firestore exist since Phase 00/01; the CLI on this machine is logged in.
4. The backup is done: the export of 2026-10-24 is the fallback for the
   phone's v43 migration and the first bind.
5. The real check after S6: install the build on the phone, Sharing →
   "Sync this database"; on the Pixel 9 Pro emulator sign in with the same
   Google account (the owner types the credentials), Sharing → "Sync this
   database" → the picker → merge; then edit on each and watch the other.
6. Only on D7 B: a free Cloudflare account and one `wrangler login`.
7. Commits are the lead's for this phase (owner's word 2026-10-24): one per
   slice after its gate, short subject, no ledger.

---

## 8. Deferred

- Tombstone purge after every device acknowledged (needs device presence
  in the space document); a persistent park list; "Delete cloud copy" (D6
  A); the Worker (D7 A); a Wi-Fi-only switch (the volumes in §11 make it
  moot); a per-device "ring here" toggle (readiness D11 B); renaming a
  space; space row counts in the picker (would need maintained counters).
- iOS (the Mac-side work the master roadmap lists); desktop sign-in
  (readiness §8).
- Settings that are note data (money currency, markdown bar assignment)
  and the custom public holidays — readiness §8.
- The pre-existing per-note counter restore defect (readiness §8,
  `CounterService.importData` never applies `noteIdMap`) — unrelated to
  sync, one focused fix with a round-trip test when the owner wants it.
- The readiness §8 items left as found (two HLCs per event-editor save, the
  held far-future remote, `restartable()`).
- From the S2a review, accepted: a tap between the counters flush and the
  reload of one pulled page can be lost (milliseconds; the real fix is
  readiness D8 B's per-device ledger); a live note whose folder arrived as
  a tombstone shows that folder's id as its name where `getFolderById` is
  read without a tombstone filter (pre-existing for local tombstones);
  concurrent creates give one folder two notes of the same title (the
  per-folder uniqueness backstop does not run on merge; ids differ) and one
  vocabulary two items for the same term (`saveItems` tombstones one later);
  `requeueRow` on a composite key scans its table.
- A pull envelope that parks (a malformed document) is skipped at that
  cursor for good and `parkedCount` resets at the next launch, so the
  device silently lacks that one row until the row is pushed again — the
  persistent park list above would make it visible and retryable.
- A row created after the bind keeps `owner_id` NULL locally (NULL means
  "mine", readiness D12) while the device that merges it stores the uid;
  harmless in Phase 02, and Phase 03 — which needs foreign rows told apart
  — decides whether local writes on a bound database stamp the uid.

---

## 9. How to run this

- This record was written on Fable 5.1 at high; the Fable session wrote
  S1's brief and may run the slices as the lead (owner 2026-10-24: "I can
  delegate everything"), spawning per slice one `implementer` and one
  `reviewer` (Opus 5.5), `qa-runner` (Sonnet) for S6, `docs-writer`
  (Sonnet) for placements; the `explorer` (Haiku) for sweeps. Load
  `delegation` before spawning, `verify` for the gate, the slice's skills
  as listed. Briefs carry the slice section, §3's subsection it builds, §5
  and the test list — never the whole record.
- `flutter test` runs one at a time: implementers run sequentially; a
  reviewer overlaps only the next slice's implementer when their files are
  disjoint and the reviewer never writes.
- After every slice: the gate, the record's "As built" block under the
  slice (the truth over the plan), one commit by the lead. The letters are
  recorded at the top of §2 with the date.
- The record is read by section; the `references/` facts are updated in
  the slice that changes the behaviour (S1, S5, S6).

---

## 10. Definition of done

- The owner's phone and the Pixel 9 Pro, same account, show the same
  folders, notes, calendar, counters and alert definitions after edits on
  either, in both directions: within seconds while both are open, at open
  after offline edits; a note edited on both before syncing shows the
  original and the conflict copy on both.
- Alerts created on one device ring on the other once it has pulled.
- The gate green after every slice; the two-device emulator pass green; the
  calendar, browser and alerts suites unchanged; the rules deployed; no
  visible change anywhere but the Sharing page and the Settings row of D8.
- `docs/cloud-sync-roadmap.md` row 02 DONE, `sync-and-accounts.md` and this
  record's as-built blocks written, one commit per slice on `main`.

---

## 11. What it costs on the Spark plan (from the owner's export)

The export of 2026-10-24 (`gym_notes_anta.db`, 476 KB, schema v42): live
rows — 2 folders, 11 notes (21 KB of text in all, the largest 14 KB),
64 events, 90 presence days, 4 per-occurrence descriptions, 5 alert
definitions, 1 template, 22 categories, 4 filter presets, 1 overview view,
2 counters with 2 values, 2 vocabularies with 41 items; tombstones — about
60 across notes, events, alerts, presets and items. About **310 documents**
in all, each a few hundred bytes to a few kilobytes.

Spark (no card): 20,000 writes, 50,000 reads and 20,000 deletes per day,
1 GiB stored, 10 GiB egress per month. The first upload is about 310
writes; the second device's first download about 310 reads plus one per
table; from then on each change is one write on the writer and one read on
every other device plus one read of the space document per remote batch,
and one read per written row on the writer (its own rows read back through
the signal). A day of two hundred edits on two devices stays under a
thousand reads and writes. The listener adds nothing while idle. Daily
quotas reset at midnight Pacific time; the engine retries hourly when
paused.

**As rehearsed (S3c, 2026-10-24, a copy of the export, local only):** the
v43 migration ran on open in 66 ms — `user_version` 42 → 43, `sync_metadata`
gained only `last_hlc` (no floor), `sync_outbox` empty, the `deleted_at`
repair fixed the one folder tombstone above 10^12; no table changed its
live/tombstoned counts (folders 2/1, notes 11/28, chunks 14/25, counters
2/0, values 2/0, events 64/12, categories 22/0, occurrences 4/1, absences
90/1, alerts 5/9, templates 1/0, presets 4/2, overview views 1/0,
vocabularies 2/1, items 41/6; category alerts, skips and digests 0/0). The
bind queued **312 rows**; A's first drain pushed all 312 in **one batch in
92 ms**; B (empty) pulled the 312 in **179 ms**; every table's live and
tombstoned counts equal on B except `content_chunks` 14/0 — a tombstoned
note arrives without chunks, by design; all 39 notes' texts, the counter
values and the category names equal; an edit on B reached A on the next
run (A read its own 312 rows back once, the read-back §11 accepts). Two
`pushBatch` calls in all.
