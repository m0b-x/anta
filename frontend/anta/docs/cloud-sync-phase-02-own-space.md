# Cloud Sync Phase 02 — Own Space on N Devices

**Status: BUILT 2026-11-06, FINAL REVIEW 2026-11-06, FIX PASS 2026-11-07 —
S1–S6 on `main` (S4b-2 and S6 in `4632602a` … `ed966d7a`, every slice gated
and reviewed); the final review (§4 after S6: five agents on snapshots of
`caa60b05`, GO WITH CONDITIONS, no blocker — one H on the order of the
first two binds, F-1, six M, X-3 on a rename and three design items) and
its fix pass on the owner's "fix anything you find" (`d2b3da32` …
`a69a65d0`, §4 "Fix pass as built": every H and M, the reviews' rounds and
the design re-measures built; D-6, W-1, W-2, X-5 and the kit-wide RC2-1
deferred in §8; whole suite 13,868 green; the four saved device suites
green on the build); left: what only the owner does (§7, with the pre-bind
checklist): the rules and indexes deploy, then the real check on the phone.
Planned 2026-10-24 (Fable 5.1); decisions D1–D8 all A, taken 2026-10-28 on
the owner's decision sheet (§2).** The transport phase
of `docs/cloud-sync-roadmap.md`: one Google account, every device shows the
same folders, notes, calendar, counters and alert definitions. Builds on the
readiness phase (`docs/cloud-sync-readiness-roadmap.md`, DONE 2026-10-23,
all in `39b0c7d`): the eighteen CRDT-shaped tables with `owner_id`, the
outbox, the persisted clock, the tombstoning wipes, the unbinding restore
and the engine seams (`SyncGateway` + `FakeSyncGateway`, `SyncStatus`,
`SyncBindingService`, `SyncSuspension`, `requeueAll`). Its decisions D1–D19
stand; where this record refines one it says so. No migration of this
phase's own (the analytics run's v44 and v45 arrived beside it in November;
the schema the engines report is 45). The August version of this file (calendar sync,
ownership, consent) described what is now Phase 03; its one still-live
point — the resurrection trap of a restore — became readiness D9/R4.

**Review (2026-10-26; REVIEWED and FIXED 2026-10-28):** `docs/cloud-sync-phase-02-review-2026-10-26.md`
read everything built so far as a whole — the pre-existing app with no
bound space, the engine, the wire, the gateway, the cross-module
scenarios — in overnight sessions A0–A9, then built the fixes in
`27eb38a`, `8c14215` and `b7c87ea`, the two unbuilt review lists (S4b-1b,
S5b) among them. Its ledger is the truth for what the review changed; the
paragraph at the end of §4 carries the carry-overs' new state.

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
12. The drawer's account row (2026-11-07)

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

**Taken 2026-10-28 on the owner's decision sheet (`fable-max`, with the
review's letters): D1 A, D2 A, D3 A, D4 A, D5 A, D6 A, D7 A, D8 A.** The
eleven sync commits and the review's fixes were built on them; a flip
before S4b-2 starts is written here.

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
  *(F5, F8, F11)*. A space **name is 1..100 code points** (CEL's `size()`,
  which the fake counts with `runes`, not `String.length`) —
  `validSpace()` is the only place that cap lives, so a name outside it is
  refused as `permissionDenied`, and the fake refuses it the same way *(A8
  R95, R154)*.
- `SyncGatewayFailure` gains `invalidData` — strictly what the server
  reports as `invalid-argument` (a document over 1 MiB). A rule refusal of a
  malformed row arrives as `permission-denied`, so the engine tells the two
  apart by reading the space document after a denied push (§3.5) *(F4)*.
- **Firestore specifics settled by the S5 review:** `watchSpace` forwards
  only snapshots that are neither from the cache nor carrying pending
  writes — offline, the SDK's first snapshot for an unwatched document says
  `exists: false, fromCache: true`, which would read as a missing space and
  pause the engine for good (H1); and the device's own write snapshot
  carries null server timestamps (L8). `pushBatch` and `createSpace` write
  through `runTransaction`, never a plain `WriteBatch.commit()`: with
  persistence off the SDK still queues a write in memory while offline, the
  commit waits until the 60 s timeout, is reported as `offline`, lands on
  reconnect anyway and every retry adds a copy — a transaction fails fast
  offline and is never queued (M4). The pusher also caps a batch by bytes
  (about 8 MiB; the request cap is 10 MiB) so a slow uplink cannot time a
  valid batch out forever (M5). A `noAccess` pause is re-checked with one
  `readSpace` on resume and on "Sync now", so a transient refusal does not
  hold until a relaunch.

### 3.4 The merge (S2)

One method per table, `mergeRemote(envelope)` on its DAO beside the
existing `NoteDao.mergeNote` (`note_dao.dart:927`), `FolderDao.mergeFolder`
(`folder_dao.dart:743`) and `ContentChunkDao.mergeChunk`
(`content_chunk_dao.dart:316`), all with one contract, in one transaction:

1. Load the local row by key. Absent → insert the remote row with its
   stamps verbatim (`MergeOrigin.remote`: no outbox entry, no new stamp).
   **The clock advance is per page, not per branch** (A7 review R65): the
   merge only reports the remote stamp, and `SyncPuller._apply` calls
   `CrdtMerge.advanceClock` once with the page's highest stamp after the
   page transaction commits, so a page that rolls back leaves the clock
   where it was and a local edit cannot out-stamp a remote row this device
   never merged. The seed `crdt_write.dart` persists is written **inside**
   the page transaction, so no committed row ever carries a stamp above
   the stored value (A7 review R132). `ContentChunkDao.mergeChunk` is the
   one method that still advances in its own transaction; it has no caller.
2. Present → compare the HLC strings (the string embeds the device id, so
   equal means the same write — bar the one **seed stamp**
   `000000000000:0000:seed` every device writes on a built-in category it
   seeds, final review F-2: there equal means "an untouched default", the
   catalog fields are identical by construction and the rows' `createdAt`,
   `updatedAt` and `deviceId` differ and never converge, harmlessly; a seed
   sorts below every minted stamp, so any real edit wins it, and the floor
   branch below never yields to a remote seed, RA1-1). **Remote newer:** write the remote row over
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
   follow through `reconcileAll(sync)`, not here. The accepted consequence
   (A3b/A5 review R77): a delete on one device and a concurrent edit on
   another **half-resurrect** the row. Per-row LWW brings the edited row
   back while its descendants stay tombstoned everywhere — an edited event
   returns without its presence marks, per-day descriptions, skips or
   alerts and will never ring again; an edited *day* row stays live under a
   tombstoned parent, which no surface shows and every backup still
   carries. A merge-side re-tombstone would be the cascade this clause
   forbids, so the outcome is written down rather than coded. A live child
   *folder* under a remotely-tombstoned parent is the one case that is
   repaired, because nothing shows it at all: `mergeFolder` re-parents the
   local row to the nearest live ancestor and requeues it (R64), and cuts a
   `parent_id` cycle two concurrent moves closed (R63) — both are local
   repairs stamped above the move they repair, skipped while
   `bind_merge_pending` is set, never a cascade. Inside one later page, a
   folder whose parent is a local tombstone and whose parent's live
   envelope arrives later in the same page is re-parented to the nearest
   live ancestor and the move is pushed — a one-level flattening after a
   delete raced edits to both folders on another device; nothing is lost.
   The repair after the page's merges (`SyncTableBinding.afterPage` + a
   public `FolderDao.repairMergedParents`) is the fix when wanted (review
   R130). The repair's own clock raise keeps the drift guard where the
   puller's page advance gives it up: the raise runs inside a transaction
   that can still roll back with nothing stored, so an unguarded one would
   leave the clock arbitrarily above everything committed (review R157) —
   and a writer more than `maxDrift` ahead therefore still out-sorts the
   repair (review R131).
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
   pushes are denied, so nothing ever rewrites them. A key added to a table
   after that table's first synced schema (v43 for the seventeen first
   tables, v44 for `calendar_category_profiles` — final review W-6: that
   table is wholly strict, nothing below v44 ever pushed one of its rows)
   therefore decodes to its column default when absent, even on a live
   envelope — `WireFields` gains a lenient accessor for such columns when
   the first one appears (none exists today); every column of a table's
   first synced schema stays strict — **bar `preview`**, the first lenient column
   (A3a review R70): it crosses for backup-format parity and the merge
   recomputes it from the body, so a live envelope without it decodes to
   `''` instead of parking. Row keys are validated for tombstones too: a
   day key must split at `|` into an id and a **UTC midnight** epoch-ms, or
   the envelope is a `FormatException` and parks (F2, F3; tightened from
   "a whole second" by A3b review R79, so the three day tables cannot grow
   a second primary-key row for one calendar day). A local row stored at
   some other instant — none exists in the owner's export, where all 96 day
   rows are at UTC midnight — is normalised **on the way out**, in `encode`
   only: its own column, its row key and its outbox entry are untouched, so
   the push cannot park forever (A7 review R133).
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
  stamped over the merged value — and **right after that page** (in
  `afterPage`, not at the end of the run) `reload()` plus the service's
  change signal (`CounterService.changes`; the counter blocs reload on it).
  `reload()` keeps the taps made during the page: the service holds each
  dirty counter's pending **delta** since its last flush and re-applies it
  over the freshly read value instead of flushing a stale absolute number
  (S2a review F4; S3c review H1 — a tap between the page and a run-end
  reload overwrote the other device's value on both devices). A `flush()`
  that **fails** is swallowed and the page merges anyway (A1b review R27):
  no value is lost — the restore plus `afterPage`'s reload re-apply the
  delta — but the local row merges un-pushed and so loses an HLC race it
  would have won. **Vocabularies** are the exception to "after a page":
  `VocabularyService.reload()` runs **once per run**, on the
  `vocabularies` invalidation class, so an open vocabularies page waits for
  the whole 17-table run rather than for its own page (A1b review R32).
  **Categories** are reloaded through `CategoryService.reload()`, which
  reseeds the built-ins before loading, so a merged built-in tombstone does
  not leave a nameless category for the session (A3b review R80); the seed
  stands back entirely while `bind_merge_pending` is set, so it can never
  overwrite the space's renamed or recoloured built-ins (R76). An
  **alerts-only** page ends in `notifyExternalChange()` too (A3b review
  R78) — without it the phone rang for a badge the open screen did not
  show. **Merged notes and folders reach the UI** through
  the storage services' change events emitted by the engine per merged row
  — the browser, the search index and an open editor (§3.9) listen there.
- **Per-envelope faults.** Decode and merge run per envelope under a catch:
  **any exception that is not a `SyncGatewayException`** (a
  `FormatException`, a `TypeError`, drift's `InvalidDataException`, a
  `StateError`, a `SqliteException` on a constraint) parks that envelope
  (`parkedCount`, logged with its type) and the page goes on — an exception
  that escaped would roll the page back and the next run would hit the same
  cursor forever, stalling every later table and every push (S3b review
  M3); a gateway failure ends the pull. **Two exceptions are never
  parked:** drift's `CouldNotRollBackException` and any `SqliteException`
  other than a constraint violation (`resultCode != 19`) — a disk-full or
  I/O error aborts SQLite's whole transaction, so the savepoint is gone,
  the remaining statements would run in autocommit and the cursor would
  commit past rows that were rolled back; such a page fails as a whole and
  is retried (S3d review H1). The app opens its database with
  `NativeDatabase.createInBackground`, so a SQLite error reaches the engine
  wrapped in drift's `DriftRemoteException` — the check unwraps
  `remoteCause` first, and one engine case runs on a background-isolate
  database (S5 review M3). **Under the bind floor a parked envelope
  retires the local row's outbox entry when the local stamp is at or below
  the floor** (the floor says the local row loses; pushing it would
  overwrite the space with the loser), and pull-parked keys stay out of the
  drain for the session (S3d review H2). A table whose pull failed for a
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
  beyond the current page, and a never-started engine ignores it. "Did not
  complete" means a background cut: a run in which every table was
  **reached** (pulled to its end or faulted and recorded) drains the
  non-faulted tables, since each was pulled in full under the floor; the
  flag clears only when every table ended without fault, so a faulting
  table keeps the floor rule for its retries (S3d review M3 — otherwise one
  deterministic fault held every push forever). The foreground state is
  tracked whether or not the engine is started, and `start()` reads the
  real lifecycle state — a stop/start across a leave must not restart an
  engine that cuts every pull and attaches no signal (M4).
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
- **Clock.** The puller advances the clock once per pulled page, from the
  page's highest stamp, after the page transaction commits
  (`CrdtMerge.advanceClock` → `hlc.adopt`, review R65); the seed goes in
  **with** the rows, inside that transaction (review R132), so no committed
  row ever carries a stamp above the stored value. The page advance is
  **not** held to the drift guard: a stamp this device has already stored on
  a row of its own is followed however far ahead it is, because holding it
  only made this run mint below rows it holds and lose those edits with no
  park and no copy (review R98). `receive`, `update` and the folder repair's
  in-transaction raise keep the guard of readiness R5.

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
  (`sync_bound_spaces` — not through `SettingsService`, whose store is the
  per-database `user_settings`; a QA build's `SharedPreferences` prefix
  covers it) of `{spaceId, ownerUid, databaseName}`; `bind` refuses a space
  another database of this install holds, with a visible reason.
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
repairs client-side. Full text in S1. Deploy, rules and indexes in one
command (the 18 `data` field exemptions ride with it; final review W-3):
`firebase deploy --only firestore:rules,firestore:indexes --project alexs-note-tracking-app`
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
receives both the note and the copy. Nothing is lost either way. A remote
**delete** of the open note: a clean editor closes with a notice; a dirty
one files its text as a new note it keeps editing (a save to a deleted
note is refused by design, so the text cannot ride the next autosave). A
widget test pins every branch; S6 drives it on two devices. **What counts
as "arriving text"** (S4a review H1): the merged body is compared with the
text the editor last loaded or saved — never with the live unsaved text,
which differs by definition when the page is dirty — so a remote move,
rename, label, reorder or re-save that left the body alone files nothing;
the body is carried with the event (or captured at the event) and saves are
held until the copy is filed, because a debounced autosave landing in the
window between the page commit and the copy would otherwise overwrite the
merged row and the remote text would be gone on both devices (M4); a copy
that fails is caught, shown and holds the autosave rather than escaping
(M3). **The pop on a remote delete** acts only when the editor's route is
current; buried under a dialog or another page it defers to `didPopNext`
and never marks itself exiting or disables saves until the pop really
targets it — `Navigator.pop(context)` pops the navigator's top route
whatever the context (H2); the notice is shown only on the current route
(L6). **Rules from the S4b-1 review:** a held or slow save that returns
success re-checks the live text — keystrokes made while the write waited
stay pending and re-arm the debounce, otherwise the page reads clean with
unsaved text and the next reload wipes it (H1; a pre-existing window the
hold widened); the gate waits until no remote work is pending at all
(`while busy`), not for the chain it first saw, or a second merge during the
wait reopens the race (H2); the leave/pause bypass never applies while the
unfiled item is the keep-as-new filing — a write to a deleted note returns
normally and vanishes (M3), and a delete arriving while the page is already
exiting still files a dirty page's text; the exit flag is cleared when the
pop does not happen, and move/share use a plain flush (M4); a delete that
waited behind a covering route re-checks dirtiness before closing (M5); a
pending **title-only** edit is not a body conflict: when the body equals
the saved baseline the body reloads in place and the title stays pending
(M6); unfiled filings are a list, not one slot (L7); the merged body's hash
travels on `announceMerged` so the page compares against what the merge
wrote rather than re-reading a row a save in flight may already have
overwritten (the S4b-1 known limit and H2 share this fix). The editor tells a
merge from its own autosave by the change event's origin: `NoteChange`
carries `remote: true` only when `announceMerged` emits it (S3c review F5);
a remote move is announced as `moved` with its source folder beside the
`updated` (the browser's old-folder list refreshes on `moved`, the search
index on `updated`; F2), from the pre-merge row the merge already read
(`MergeOutcome.previousParent` → `SyncAppliedRow`). A conflict copy created
inside the page transaction is announced only after the page commits (the
hook writes it through a repository method that caches and emits nothing;
the engine lists the copy among the page's rows), so a rolled-back page
never told a listener about a row that does not exist (F10).

**Exactly one copy, and who files it** (A5 review R99, A7 review R129). The
engine's loser rule fires on the same four conditions the editor's does, so
a conflict on an open dirty note used to file **two** copies: the hook's,
holding the editor's *stored* body, and the editor's, holding the arriving
remote body. The hook now stands back, and the editor files the one copy —
chosen over the opposite because suppressing the editor would leave the
arriving remote text nowhere, overwritten by the next autosave. The seam is
`OpenNoteRegistry` (`lib/services/sync/open_note_registry.dart`), a static
probe in `DrawerHostRegistry`'s shape that the page registers in `initState`
and drops in `dispose`; an unbound database never reaches it. The condition
the two sides share is a **claim, not a question**: the page answers on its
*body* being unsaved, latches that it owes a copy, and files whatever it
reads when the announcement arrives — because the hook asks at merge time,
inside the page transaction, and the page acts after the commit, and the
three branches that return without filing (a pending title-only edit under
M6 above, a save that lands in the window and leaves the page reading
clean, a page that goes clean between the two moments) each used to drop
the losing body with no copy and no log line. The merged body also rides
`announceMerged` as text now rather than being re-read from the row (A1a
review R4), which closes the same window on the comparison side and keeps a
pulled page of up to 499 bodies out of the 50-slot content cache (R6).

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
  DI points Auth and Firestore at the ports
  `ANTA_QA_FIREBASE_AUTH_PORT` / `ANTA_QA_FIREBASE_FIRESTORE_PORT` name,
  `:9099` and `:8080` by default — defines rather than constants so a stray
  emulator holding one does not need a rebuild (A8 R93)
  (`useAuthEmulator` / `useFirestoreEmulator`) and
  `FirebaseAuthService.signInWithGoogle` signs in with a QA identity the
  emulator accepts without Google (`ANTA_QA_ACCOUNT=<uid>:<email>`; the
  implementer verifies the emulator's fake-token form against the Firebase
  docs and falls back to the emulator's email sign-in). Compiled out
  without `ANTA_QA`. **Under the emulator the app initialises Firebase with
  `projectId: 'demo-anta'`** (`DefaultFirebaseOptions.currentPlatform` copied
  with the demo id): the suite runs `--project demo-anta`, the Auth emulator
  mints tokens for it, and Firestore requests under the app's real project
  id are only warned about — whether the startup rules apply to that second
  id is unverified, so a pass under the real id would prove nothing about the
  rules (S5 review H2). **Superseded by S5b:** on Android the native
  default app is created by the google-services plugin from
  `google-services.json` before Dart runs, and `Firebase.initializeApp(options:)`
  hands back that existing app (it compares only apiKey, databaseURL and
  storageBucket), so a Dart-side `projectId: 'demo-anta'` changes nothing.
  **The emulator suite therefore runs under the app's real project id**
  (`firebase emulators:start --project alexs-note-tracking-app`, and the
  probe with `-Project alexs-note-tracking-app`): the id is a label the
  local emulator serves, nothing reaches the real backend while the app
  points at the emulator host, and the rules load for that id. A QA build
  with `ANTA_QA_CLOUD=true` and NO emulator host would talk to the real
  project with a real account — S6 always passes both defines. The
  `ANTA_QA_ACCOUNT` first field is the Google `sub`; the Auth emulator
  assigns its own Firebase uid, so nothing in a flow may assume
  `users/<sub>/…` (L12).
- `firebase.emulators.json` at the package root (tracked; the CLI refuses
  rules outside the config's folder — S1 as built): the emulator suite —
  auth 9099, firestore 8080 with `firestore.rules`, UI 4000 — and
  `tool/firebase/emulators.cmd` / `.sh` running `firebase emulators:start
  --project <id> --config firebase.emulators.json`, the project id
  defaulting to the app's real one (§3.8, S5b). Node 26, Java 25 and
  firebase-tools 15.27 are on the Windows machine.

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

**S3c review (2026-10-24, one independent reviewer on a snapshot, three
behaviour probes against the real repositories and services, the
migration half of the rehearsal re-run; 1 high, 5 medium, 10 low; "the
commit stands").** **H1** a counter tap between a counter page and the
run-end `reload()` was flushed over the merged value (probe: 3 → merged 8 →
tap → 4 on both devices) → §3.5 "Counters" as amended (reload in
`afterPage`; pending deltas re-applied over the fresh value). Mediums: F2
a remote move never refreshed the browser's old folder (no page uses the
drift streams; the blocs refresh on `folderId == current` or `moved` with
`sourceFolderId`) → `moved` beside `updated`, from the pre-merge row
(§3.9); F3 a loser title near 500 characters plus the suffix failed the
column's `withLength` — under in-transaction filing the page would roll
back forever → the title is shortened to fit; F4 a lone `inactive` (a
notification shade, a permission dialog, every desktop focus change)
counted as leaving the app: a drain plus a full 17-table pull on return →
a leave is `hidden`/`paused` only (the test pinned the wrong behaviour);
F5 the editor rule cannot tell a merge from its own autosave →
`NoteChange.remote` (§3.9); F6 nothing restarts the engine after a lifecycle
reset (`start()` runs once from DI; the next `getInstance()` builds an
unstarted engine — the "download into a new database" switch meets it) →
`getInstance()` starts the engine when DI enabled it. Lows: F7
`RefreshSyncStatus` replaces the engine-owned fields (a showing `noAccess`
vanishes) → overlay `engine.current`; F8 two mutations survived (a
`{calendar}`-only hook case and a resurrection case are missing); F9
`reset()` leaves the status stream open (acceptable once F6 is fixed); F10
the copy's `created` event and cache entry escape a page rollback → §3.9
(announce after commit); F11 title details (an empty loser title gives a
leading space, the ` (n)` suffix is a literal, `yMd` puts slashes in a
title — check the export/share file-name path); F12 `VocabularyService`
has no change signal (an open vocabulary page or the pills keep the old
list until re-read); F13 a hard-coded "Counter not found" now reachable;
F14 `CounterBloc._onRefreshCounters` keeps the old `pickedNoteValues`; F15
the hooks and the blocs obtain `CounterService` two ways (same object per
database lifetime); F16 `seedMissing` would revive a tombstoned built-in
after a pull — moot, no device can tombstone a built-in. **S5 notes:** the
gateway must be registered before the engine-start line in DI; a QA build
syncs only with `ANTA_QA_CLOUD` (the availability gate). **Fixed in S4a**
(the next run after S3d): H1, F2–F8, F10, F11, F13, F14; F12 as
`VocabularyService.changes` with the vocabulary page refreshing on it.

**S3d as built (2026-10-24, one implementer; gate: `dart analyze lib test`
clean, whole suite once — 10,388 passed, the one Windows-only failure;
review pending, fixes at the head of S4b).** Every S3b-review item has its
fix and a named test (the implementer's table of item → test is in its
report; the tests live in the three engine suites and
`app_sync_apply_hooks_test`). The engine is now one library in three files:
`sync_engine.dart` (902 lines, the root), `sync_puller.dart` (275, part),
`sync_pusher.dart` (262, part). Shapes chosen, each sound: request modes
`drain < stale < full` (`_RunMode`); `bind_merge_pending` forces a full
run and a pending run whose pull fell short, or a drain-only run, does not
drain (H1); before any signal every table is stale; the async
`_checkHalt(bound)` checks stopped, suspension, the binding (same space)
and the user before each page, after `beforePage`, before each batch and
before each send (M6) — a suspension that begins inside `beforePage` now
stops that page (stricter than the old test); the copy is filed inside the
page transaction after the merges and before the cursor (H2); **each merge
runs in its own savepoint** so a parked envelope leaves no partial writes,
still one transaction and one `persistClock` per page; anything that is not
a `SyncGatewayException` parks the envelope, `ArgumentError` logged as a
probable bug (M3, L16); **a table whose pull failed for a local reason
pushes none of its own rows in that run** while the other tables still
drain (a failed copy followed by a push of the local note would re-create
H2's loss on the other device) and the run reports `unknown` and backs off
so the page is retried; a pull that did not complete writes no
`last_pull_at`; the quota pause lifts on a run's first successful call
(`quota_paused_at` deleted) while `lastFailure` and the back-off reset only
after a run whose calls all succeeded (L9); `start()` has a generation
guard (L10); the signal detaches on `onDone` (L11) and re-attaches on its
own back-off without a run (L13); the lifecycle calls are no-ops unless
started (L12); `onAppBackgrounded` drains only and any pull stops before
its next page while `_foreground` is false (L14); `afterRun` wrapped (L17);
parked push rows keyed by stamp (L7); warnings through
`debugPrint('[SyncEngine] warning: …')` (no leveled logger exists). The
conflict copy goes to the root (`folderId ''`, reachable through All notes
and search) when the loser's folder is tombstoned — S4a refines it to the
nearest live ancestor. Test support: `recording_sync_apply_hooks`
`onAfterRun` / `onConflict`; `sync_pair` `tables:` and the comparator's
exact ignore list; the fake's `failWatches` / `endWatches` and `watchSpace`
forwarding `onDone`. Not verified by the implementer: that the new tests
fail on the old engine (by reasoning, not by a run — the S3d review
mutates); that M5's diagnosis runs once per drain (the fake does not log
`readSpace`).

**S3d review (2026-10-24, one independent reviewer on a snapshot, nine
brief mutations plus five more, four behaviour probes incl. a disk-full
database; 2 high, 2 medium, 7 low, 5 test gaps; "the commit stands as the
base").** Both highs are second-order effects of M3's catch-all: **H1** a
`SqliteException` that aborts the whole transaction (SQLITE_FULL — probe
with `PRAGMA max_page_count`) was parked, the savepoint rollback failed
(`CouldNotRollBackException`), the cursor and `persistClock` ran in
autocommit and the row was lost for good along with the page's earlier
rows; **H2** an envelope parked under the floor still counted the pull as
complete, the flag cleared and the bind's re-queue pushed the pre-bind
local row over the space (H1's loss one row at a time). Mediums: M3 one
table faulting every run under the flag held every push forever and the
flag never cleared (probe: a category pulled in full stayed unpushed over
three runs); M4 `_foreground` survived `stop()`/`start()`, so an engine
restarted across a leave cut every pull and attached no signal ("Sync now"
made no call and reported a clean run) — S4's bind flow around an external
sign-in activity would meet it. All four are rules in §3.5 now. Lows: L5
`_drainIfQueued` unguarded (a closed database → an uncaught zone error
through `whenIdle`); L6 `_signal` never cleared on detach or on a space
change (a stale snapshot picks the tables; `pull_seen` of a new space
written from the old space's `touched`); L7 a leave mid-pull runs
`afterRun` before the drain the leave exists for; L8 a signal error's
`lastFailure` outlives a healthy re-attach; L9 `onDone` detaches without
scheduling a re-attach (an idle session hears nothing until an edit or a
resume); L10 the pull side's parked set never drops a key; L11 every
debounced drain before the first snapshot is a full pull (accepted,
bounded). Test gaps T1–T5: stale-before-signal, the per-merge savepoint
(a merge failing part-way), the user checks in `_checkHalt`, the signal's
own step counter, the once-per-drain diagnosis (the fake must log
`readSpace`). **Fixed at the head of S5** (S4a is editing the puller for
the copy rows): H1, H2, M3, M4, L5–L10, T1–T5; the reviewer's probe file is
at `scratchpad\snap\frontend\anta\test\zz_probe\review_probe_test.dart`
for the implementer to port into real tests.

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

Run as two implementer runs (decided 2026-10-24 after the S3c review):
**S4a** needs no letters — the S3c review fixes (H1, F2–F8, F10–F14), the
editor rule §3.9 with `NoteChange.remote`, the bloc's refresh overlay, the
engine restarted after a reset; **S4b** needs D1, D2, D4, D5, D6 and D8 —
the Sharing page's Sync section, the picker, the install registry, the
space service, the strings. S5 (the Firestore gateway) runs between them if
the letters are still out. After S5: **S4b-1** (no letters) carries the
S4a-review fixes, the dirty-delete branch, the engine restart after a
switch and the test gaps; **S4b-2** (letters) the Sync section, the picker,
the registry, the space service, the strings.

**S4a as built (2026-10-24, one implementer resumed once at its turn cap;
gate: `dart analyze lib test` clean, gen-l10n `{}`, the implementer's
whole-suite run green but for one test its own `moved` field broke in the
shared merge contract — fixed, `test/database` 806 green — and the lead's
own whole-suite run before the commit; review pending, fixes at the head of
S4b).** The S3c fix pass: H1 — `CounterService` keeps each unflushed value
as a delta (taps) or an absolute (set/reset) over the shown value,
`reload()` re-reads and puts the pending deltas back, `flush()` reads the
stored value inside its own write transaction and writes stored + delta,
flush and reload share one queue, `afterPage` reloads counters right after
their page, the per-note bloc flushes before a refresh (tests incl. an
engine-level case with the real service against the pair); F2 —
`MergeOutcome.moved` + `previousParent` (a folder at the root has parent
null, so a flag is needed), `SyncAppliedRow` carries both,
`announceMerged(ids, inserted:, previousParents:)` emits `moved` with its
source beside `updated`, the browser bloc refreshes the old folder; F3 —
`lib/services/sync/conflict_copy_title.dart` shared by the engine and the
editor, `AppConstants.maxNoteTitleLength = 500`, an empty title becomes
`untitledNote`; F4 — a leave is `hidden`/`paused` only, a lone `inactive`
does nothing; F5 — `NoteChange.remote` / `FolderChange.remote`; F6 — a
static `SyncEngine.autoStart` DI sets, every `getInstance()` builds and
starts (no test: `getInstance()` reaches `AppDatabase.getInstance()`); F7 —
`SyncBloc._withEngine` overlays the engine-owned fields on a refresh; F8 —
the resurrection doc and the two tests; F10 — `fileConflictCopy` returns the
copy's id, `NoteRepository.createMergedCopy` stamps and queues but caches
and emits nothing, the puller hands the copies to `afterPage` as inserted
`notes` rows apart from the pulled count; F11 — `yMMMd`+`Hm` (no slash in
any language; the export sanitizer turns `/` into `_`), the ` (n)` suffix
literal like `_createNoteWithUniqueTitle`; F12 — `VocabularyService.changes`
(after reload, import and clear), `VocabulariesPage` refreshes (service
tests; no page test); F13 — `CounterPerNoteError(CounterPerNoteFailure)`
with `counterNotFound` / `loadFailed`, the page words them (`counterNotFound`
en/de/ro; the raw `e.toString()` gone); F14 — the card picks re-read;
the copy goes to the nearest live ancestor, else the root. **The editor
(§3.9):** one subscription to `NoteStorageService.changes` in `initState`,
`_onStorageChange` returns unless `remote` and the id is the page's note;
dirty = `_saves.hasChanges.value || saveStatus == saving` (a save in flight
counts as dirty); clean update → `_reloadContentIfChanged` through
`_adoptLoadedContent(keepCaret: true)` (caret kept at the same line and
column, clamped), a keystroke during the read falls through to the dirty
branch; dirty update → the arriving text filed through `createNote` under
D3's title in the merged row's folder and label, ` (n)` on a clash; a remote
move also updates the page's folder; snackbars through `CustomSnackbar.show`
(the overlay road): `syncNoteUpdatedElsewhere`, `syncNoteConflictCopyFiled`,
`syncNoteDeletedElsewhere`; clean delete → saves off, the notice, pop;
dirty delete → keeps the text and the editor **but the next autosave cannot
save it** (writing to a deleted note is refused by `NoteDao.updateNote` on
purpose) — the §3.9 rule now says the text is filed as a new note the page
keeps editing; **S4b builds that branch.** Tests: five editor cases in
`optimized_note_editor_page_test` driving the real DAO merge +
`announceMerged`; the counter, hooks, engine, bloc, bridge and vocabulary
suites listed in the implementer's report.

**S4a review (2026-10-25, one independent reviewer on a snapshot, three
editor probes against the real DAO merge and `announceMerged`; 2 high, 3
medium, 7 low; "the commit stands as a base").** **H1** a dirty editor
filed a conflict copy whenever any remote change arrived — it compared the
merged body with the live unsaved text (probe: type, then merge the same
body under a newer stamp → one junk copy of the user's own old text, synced
everywhere; every reorder on the other device re-stamps the folder's
notes); **H2** a remote delete of a clean note whose editor was under a
dialog or another page popped the wrong route (`AppNavigator.pop` =
`Navigator.pop(context)`) and left the editor marked exiting with saves off
— anything typed afterwards silently unsaved (probes with a dialog and
with a page above). Mediums: M3 a failure while filing the copy was an
uncaught async error and the next autosave then lost the arriving text;
M4 a debounced autosave landing between the page commit and the copy's
`loadNoteContent` reads back the user's own text or overwrites the merged
row first — no copy, remote text lost; M5 nothing calls
`SyncEngine.getInstance()` after a lifecycle reset except the bloc thunk,
so a switched database does not sync until the Sharing page loads (S4b's
in-place switch meets it). Lows: L6 a buried editor shows the notice over
the page on top; L7 a save in flight that already committed counts as
dirty (a copy identical to the note; with an engine copy, three notes for
one conflict) — removed by H1's baseline; L8 `_flushDirty` clears the
pending map before its try, so a thrown transaction drops every delta →
merge the snapshot back on catch; L9 a flush onto a remotely tombstoned
*value* row resurrects it (LWW; recorded as accepted); L10 `_withEngine`
only on `RefreshSyncStatus` and its precedence inverted against the
engine's `_emit` → one rule in both places; L11 `_liveFolderFor` fills the
folder cache inside the page transaction (a rolled-back page leaves a
tombstone in the cache) → read through the DAO; L12 the vocabulary page
keeps listening to an old instance across a switch; the merged copy is
announced `remote: true` though local (S4b must not key on it);
`SyncEngine.getInstance` racing a database switch keeps an engine on the
closed database as `_instance`. All in §3.9 now where they are rules.
**Fixed at the head of S4b** (after S5; the editor, the bloc, the hooks and
the counter service are outside S5's files): H1–H2, M3–M5, L6, L8, L10,
L11, L12, plus the dirty-delete branch (the text filed as a new note the
page keeps editing) and the F6/F12/F13 test gaps.

**S4b-1 as built (2026-10-25, one implementer resumed once at its turn
cap; gate: `dart analyze lib test` clean, gen-l10n `{}`, whole suite once —
10,472 passed, the one Windows-only failure; review pending, fixes at the
head of S4b-2).** Every S4a-review item landed with a named test (eleven
editor cases in `optimized_note_editor_page_test`, a coordinator group, bloc,
hooks, counter, database-instance, two new page suites and
`sync_engine_switch_test`). **The editor:** the baseline is
`AutoSaveService`'s saved hash + length exposed as
`NoteSaveCoordinator.isSavedContent`; a dirty page files nothing when the
merged body equals the baseline or the live text, and after filing a copy
`adoptStoredContent(arriving)` makes the merged text the new baseline and
re-arms the save so the user's text overwrites it; the coordinator takes a
`beforeWrite` gate asked at the top of every write (before the note id is
read, so a held write lands on a retargeted id), the page raises the hold
synchronously inside the change event (`_remoteBusy`) and runs handlers one
after another on `_remoteWork`; a held write throws `_WriteHeld` and
`AutoSaveService` keeps the text unsaved and retries on its own steps; a
failed copy shows `syncNoteConflictCopyFailed` once, holds the save, and is
retried at the next change event and before the next write; **a write is
let through on leave and on lifecycle pause even with an unfiled copy** (a
copy that failed even then costs the other device's text, holding the
write would cost the on-screen text — the implementer's call A, kept); the
remote delete acts only when `ModalRoute.of(context).isCurrent` (then
`Navigator.of(context).pop()` can only take this route), otherwise sets
`_deletedWhileCovered` and acts later from `didChangeDependencies` and
`didPopNext`; notices only on the current route; the kept-as-new note
takes the editor's current title (` (n)` on a clash, the field updated),
the tombstone's label, and the page re-points its save target, reading
position, counter context and shortcut handler to the new id
(`syncNoteKeptAsNew`). **Elsewhere:** `SyncEngine.pauseOver` is the one
pause rule used by the engine's `_emit` and the bloc's `_withEngine`, now
applied in `_emitStatus` too; `FolderRepository.nearestLiveFolderId` reads
through the DAO and caches nothing (the hooks and the page use it);
`CounterService._flushDirty` puts the pending snapshot back under any taps
made meanwhile when the write fails; `VocabularyService`'s change stream
is shared by all instances and a new instance announces itself, the page
re-resolves `getInstance()` on every event; `DatabaseLifecycle.registerSwitchedHandler`
/ `notifyDatabaseSwitched` fired by `AppDatabase._open` after a switched-to
database opens, and `SyncEngine._register` adds `_rebuildAfterSwitch`
(builds and starts when `autoStart` is set and no engine exists).
**Known limit, for S4b-2:** a save already in flight when the event arrives
can still commit after the merge and overwrite the merged row before the
page reads it — the page then sees its own text and files nothing; the fix
is to carry the merged body (or its hash) on `announceMerged` and compare
against it. Also noted: a clean remote delete of an editor that is the
navigator's root route pops the only route (as before).

**S4b-1 review (2026-10-25, one independent reviewer on a snapshot, a
probe of `AutoSaveService`, two mutants; 2 high, 4 medium, 8 low; "keep
the commit as a base, fix the highs before S4b-2"; fixed in S4b-1b below).** **H1** text typed
while a write is held is marked saved but never written (`_performSave`
reads the text, `onSave` now waits for the whole remote chain, success sets
the baseline to the text it read and clears pending — probe: writes `[A]`,
pending false, status saved, "AB" on screen); a later reload wipes it; **H2**
the gate reads `_remoteWork` once, so a second merge during the wait lets
the held save overwrite the row the second merge wrote before its handler
reads it. Mediums: M3 decision A's bypass writes to the deleted note when
the unfiled item is the keep-as-new filing (`NoteDao.updateNote` returns
normally for a deleted row, so the page reads clean and the text is gone;
the same when the delete arrives after `_isExiting` is set); M4 `_exiting`
is set and never cleared, and `saveBeforeExit` is also the flush behind
move and share, so after any move or share the hold is off for the page's
life; M5 a delete deferred behind a covering route closes a page that
became dirty meanwhile (a heading menu or rename dialog edits as it
closes); M6 a pending title-only edit counts as a body conflict (the
remote body is reverted on both devices and survives only as a copy).
Lows: L7 a second failed filing replaces the first; L8 the failure notice
only once and only when current, `syncNoteConflictCopyFailed` says "copy"
for a failed keep-as-new; L9 overlapping pauses clear `_pausing` early;
L10 the `getInstance` race is worse with `_rebuildAfterSwitch` (a stale
call can register an engine on the closed database — compare a generation
after the awaits); L11 a throw after `createNote` in the keep-as-new closure
makes the retry create a second note; L12 a vocabularies page open across a
switch keeps the old service until something calls `getInstance()`; L13 a
misplaced `///` in `folder_storage_service.dart` (`getFolderById` lost its
doc); L14 the busy-counter mutant survives and the engine side of
`pauseOver` is unpinned. All rules in §3.9 now. **Fixed in S4b-1b** (an
editor run right after S5b, no letters needed): H1, H2, M3–M6, L7–L11,
L13, L14, plus the merged-body hash on `announceMerged`; L12 noted for
S4b-2's in-place switch.

**S4b-1b as built (2026-10-25, one implementer; gate: `dart analyze lib
test` clean, gen-l10n `{}`, whole suite — 10,509 passed, the one
Windows-only failure; the suite ran twice because the first run exposed a
missing autosave wait in the implementer's own new test; review pending,
fixes at the head of S4b-2).** H1 — `AutoSaveService` compares the live
text and title with what a successful write carried and, while tracking,
stays unsaved and re-arms the debounce when they differ. H2 — the gate's
final rule: `do { while (_remoteBusy > 0) await _remoteWork; await
_retryUnfiled(); } while (_remoteBusy > 0); return _unfiled.isEmpty ||
(leaving && !_holdsDeletedNotesText);` — a filing is listed before it runs,
so that alone holds a write. **The merged body rides the event as
`NoteChange.remoteContent`** (a string, not a hash — the page files the
copy from it and never re-reads the row); `announceMerged` reads all live
bodies in one `loadContentForNotes` call before the first event. M3 — the
leave/pause path never bypasses a keep-as-new filing: the exit retries it
once (`_keptDeletedNotesText`) and keeps the page with
`syncNoteKeptAsNewFailed` if it fails; a delete arriving while already
leaving still files dirty text; the wrong "reads as null" comment fixed.
M4 — the coordinator's `flush()` for move/share and `exitAborted()` when the
pop does not happen. M5 — a deferred delete re-checks dirtiness and files
instead of closing (`_deletedWhileCovered` holds the change). M6 —
`_adoptLoadedContent(titlePending: true)` reloads the body in place and
keeps the title pending; the autosave makes only what a write carried the
baseline. L7 — `List<_Filing>` retried in order, a retry joining a running
attempt; L8 — a failure while covered owes one notice shown when current
(keep-as-new wins over copy); L9 — a pause counter and a write-sequence
number decide whether a write is the pause's own; L10 —
`DatabaseLifecycle.generation` (bumped in `notifyDatabaseSwitching`),
`getInstance()` retries once when it changed and throws `StateError` on a
second change; L11 — the created note remembered across retries; L13 the
docs; L14 the busy counter kept (the wait loop depends on it) and an
engine-level `pauseOver` test. The gate is `beforeWrite({required bool
leaving})` with the bypass policy in the page. **Residual, for S4b-2's
head:** the body is read when the merge is *announced* (after the page
commits); an autosave that reaches the database while the merge
transaction is still open commits before that read and the copy is missed
— the merge already holds the remote content (`mergeNoteDocument(note,
content)`), so `SyncAppliedRow` carries it to `announceMerged` (a hooks +
puller change). Also noted: every DB-backed singleton's `getInstance` has
the race L10 fixed for the engine, so the engine's retry can still pick a
binding or status service bound to the closing database; `announceMerged`
now reads every live body per pulled page (one batched query).

**S4b-1b review (2026-10-25, one independent reviewer on a snapshot, two
mutants, one exit/delete race probe; 0 high, 3 medium, 9 low; "the
commit stands as a base").** Mediums: M1 `_keptDeletedNotesText` checks
`_holdsDeletedNotesText` at once and never waits for `_remoteBusy`, so an
exit write landing before the delete handler has listed its filing lets
the page leave and the text is never kept (probe: the only write went to
the tombstone, no kept-as-new note); M2 a write that lands on the
tombstone between the delete merge's commit and its event is lost —
`NoteDao.updateNote` returns normally for a deleted row, the autosave
marks the page clean, the event finds a clean page → `updateNote` must
*report* the refused write (the refusal itself stays) so the page stays
dirty; M3 `announceMerged` reads and decompresses every live body of every
pulled page and puts each in the 50-entry content LRU (evicting the user's
working cache; up to 499 bodies held at once) — the `SyncAppliedRow` carry
removes the read, and the cache put goes. Lows: L4 `_retryEachUnfiled`
re-runs a filing that finished during its iteration (a duplicate copy or
notice); L5 filings completing out of order move the baseline backwards →
stop at the first failure; L6 the exit path shows the keep-as-new failure
twice; L7 the title-pending reload replaces the body's undo history and a
concurrent remote rename loses to the pending local title silently (LWW,
to be stated); L8 a held write burns the autosave's retry ladder and shows
`SaveStatus.error` for a hold that is on purpose → a typed hold that
re-arms without counting; L9 the residual's wording (the window runs from
the merge commit to the end of `announceMerged`'s reads, not only while
the transaction is open); L10 the gate-once mutant is killed by one delete
case only; L11 no widget test pins H1 end to end; L12 a `readGate` that now
gates nothing and no repository test for `remoteContent` (null for a
tombstone, `''` for an empty body, absent on `moved`). Decision A kept
(a copy failing on exit lets the write through; one last attempt from
`remoteContent` first). **Fixed at the head of S4b-2:** M1–M3, L4–L8,
L10–L12, with the merge handing the body to `SyncAppliedRow`.

**Pre-bind slice P as built (2026-11-06, one implementer; gate: `dart
analyze lib test` clean, whole suite 13,487 passed, 12 skipped, none
failed — the first fully green run on Windows, `host_devices_test` now
expects the host's path separator; review pending).** Four data fixes that
a bound database would copy to every device: **P1** a restore files
per-note counter values, pins, positions and owners under the restored
note's new id (`CounterService.importData(noteIdMap:)`, the map
`BackupService` already built for the bar assignments; a missing id keeps
its archived one, the global `''` is never translated); **P2** every folder
sort ends on `id`, as the note sorts did, so a position tie from concurrent
creates (R71) lists alike on every device — the position plan gains `USE
TEMP B-TREE FOR LAST TERM OF ORDER BY` over one parent's ties; **P3** a live
note that arrives under a folder that is a tombstone here is re-filed under
that folder's nearest live ancestor, the root when every ancestor is a
tombstone (`NoteDao._repairMergedFolder`, the notes twin of the folder
repair R64, on its rules: a folder not yet received stands, never under
`bind_merge_pending`, stamped inside the page above the edit, the outcome
`moved`) — only where the live note arrives, never as a sweep when a
folder's tombstone lands, which would re-stamp a note whose own tombstone
is still in the notes pull and resurrect it; **P4** the editor's menu and
the folder picker never name a tombstone (a data-less one's name is its
id). Found, not fixed: `FolderStorageService.getAncestors` includes
tombstones, so the picker's breadcrumbs can name a locally known deleted
ancestor (by its real name).

**P review (2026-11-06, one independent reviewer on a snapshot of
`4632602a`, probes and mutants; 0 high, 5 medium, 5 low; fixed in the P
fix pass below).** **PR1 (M, confirmed)** the repair resurrects a note
another device deleted when that device's folder tombstone lands before
the note's own: the drain orders one stamp's rows `folders` before `notes`
(`SyncOutboxDao.pending`), a cascade of more than 498 rows spans batches,
and the other device's space listener pulls between them — a note whose
live envelope it had not pulled yet is re-filed and stamped above the
delete, so the note's tombstone then loses. The reviewer's fix (repair
only an edit newer than the delete) would leave hidden for good a note
moved into the folder on one device while the folder was deleted on the
other, where no tombstone of the note is coming — **the lead's rule:**
repair when the note's stamp is above the folder tombstone's (an edit after
the delete), **or** when this device wrote the tombstone (its own cascade
would have tombstoned the note had it been inside, so a live one arriving
under it is a move nobody deleted). **PR2 (M, confirmed)** the folder
picker opened inside a tombstoned ancestor (through `getAncestors`), named
it by its id, listed its subfolders and offered "Move to" it — a move a
bound database copies everywhere. **PR3 (M, confirmed)** search results and
All notes name a tombstoned folder by its id (`folderPathSegments`).
**PR4 (M, confirmed)** a device that holds only the data-less tombstone of
the folder (parent unknown) re-files at the root while one that knew the
folder re-files under its parent; the space converges on the later repair.
**Accepted:** visibility first — a device can only answer what it knows,
and a fresh device's initial merge skips the repair anyway. **PR5 (M,
plausible)** a note that misses its one merge-time chance (the device that
made the edit, which merges the folder's tombstone, not the note; a note
skipped under `bind_merge_pending`) stays hidden until someone edits it →
a sweep after a complete pull. **PR6 (L)** the conflict copy files a chain
that runs into an unknown folder at the root while the note stands —
**accepted:** a new copy must be visible, the original waits for what is
known. **PR7 (L)** a restore writes the per-note counter values of
soft-deleted notes (not in the archive) under ids that exist nowhere, and
a note whose folder is not in the archive restores under a folder that
exists nowhere. **PR8 (L)** `getFoldersByParent` has no order and
`watchFoldersByParent` orders by name alone. **PR9 (L)** a re-filed note
keeps its position and title in its new folder and its `updatedAt` moves —
**accepted**, as the folder repair does and as §8 accepts for concurrent
creates. **PR10 (L, confirmed)** two P3 mutants survive (an unknown parent
of a tombstone; two live ancestors), and P1's unmapped id, P3's
already-moved note and the real export path are untested. Also accepted,
for both repairs: a repair is a stamped write, so one minted after a
concurrent delete of the same row on a device it has not heard from can
win that row by last-writer-wins — the half-resurrection §3.4 already
accepts for an edit.

**S4b-2a as built (2026-11-06, one implementer; the bind flow below the
UI; gate: `dart analyze lib test` clean, whole suite 13,559 passed, 12
skipped, none failed; review with S4b-2b).** `SyncSpaceRegistry`
(`lib/services/sync/sync_space_registry.dart`, `SharedPreferences` key
`sync_bound_spaces`): claimed by `bind()` and released by `unbind()` after
their transactions commit, so Stop syncing and the restore's unbind both
release; `DatabaseManager.deleteDatabase` releases and `renameDatabase`
carries the claim; a holder whose file is gone is ignored; a registry write
failure is logged, never thrown (a restore must still clear its queue and
write its floor). R39: the two refusals are `SyncBindRefusal(suspended |
alreadyBound)`, still checked inside the transaction (R38).
`SyncSpaceService` (gateway interface only): `start(accountUid)` decides D1/D2
— no space: create one named after the active database and bind; nothing
local and one space no other database holds: bind it; else the picker
data, with `heldBy`; "holds data" = a live row in any synced table but
`content_chunks` and built-in categories; spaces most recently written
first; a name trimmed to 1..100 code points, checked before the gateway;
the download creates `DatabaseManager.suggestDatabaseName(space.name)`,
switches in place, binds, and on a failure switches back and deletes the
new file; Stop syncing on an unbound database writes nothing (an unbind
would raise a restore's floor). The bloc: `SyncThisDatabaseRequested`,
`MergeIntoSpaceRequested`, `DownloadSpaceRequested`,
`UploadAsNewSpaceRequested`, `BindFlowDismissed`, `StopSyncingRequested`;
`SyncSignedIn` and `SyncSignedOut` carry a sealed `SyncBindFlow` (idle with
`switchedToDatabase`, checking, picking, binding, stopping, failed with a
`SyncBindFailure`) through every emit; after a bind or an unbind the engine
is stopped and started (its rebind pair — `syncNow()` would keep the
previous space's `appOutdated` pause); a step in flight ignores further
taps; an account change drops the flow; no space service (desktop, a QA
build without `ANTA_QA_CLOUD`) ignores the bind events. Found, not fixed:
a database name from a non-ASCII space name is all underscores; a space
created by a bind that then fails stays in the account (D6: no delete
until Phase 04) and shows in the next picker.

**S4b-2b as built (2026-11-06, one implementer; the Sharing page's Sync
section and the picker; gate: `dart analyze lib test` clean, gen-l10n,
`untranslated.txt` `{}`, whole suite 13,633 passed, 12 skipped, none
failed; review and design review pending).** The Sync section sits
between Account and Pairing and is always rendered. Unbound: one row,
"Sync this database" (`sharing-sync`) — enabled signed in, disabled with a
reason signed out or unavailable, a spinner in place of the glyph while
checking or binding (no height change), a failure's reason as its
description plus one snackbar. Bound: a status row (`sharing-sync-status`)
whose line is a pause first (quota, signed out, another account, app
outdated, no access), then a run (sending n, downloading n so far,
receiving), then the last failure (offline, retrying), else n waiting or up
to date, with the last sync time, the waiting count and the parked count
beneath; "Sync now" (`sharing-sync-now`) only signed in, unpaused and idle;
"Stop syncing this database" (`sharing-sync-stop`) always — signed out and
on another account included — behind a confirm that says the cloud copy
stays (`sharing-sync-stop-confirm`; `AppDialogs.confirm` gained an
optional id). The picker (`SyncSpacePickerSheet`, a content-tall form
sheet): with several spaces a "Cloud spaces" list of exclusive rows (the
first one no other database holds is selected; a held one disabled with
the database that syncs it), then — when this database holds data — Merge
into / Download into a new database for the selected space, and always
Upload as a new space; an empty database binds on the tap of a space; with
one space no list, and "Sync with <space>" when nothing is local; a close
without a choice sends `BindFlowDismissed`. A download ends on the
Databases page's restart prompt (its strings unchanged; it cannot be
dismissed, so the dismiss is sent as it opens). D8: `sharingSettings` is
"Sync & sharing" / "Sync & Teilen" / "Sincronizare și partajare". Ids:
`sharing-sync*` on the page, `sync-picker`, `sync-picker-close`,
`sync-picker-space-<spaceId>`, `sync-picker-merge` (also on "Sync with"),
`sync-picker-download`, `sync-picker-upload`. Not shown: `clockAhead`,
`clampedRemotes`. Found, not fixed: a disabled `FormCheckRow` dims its
caption to 38 %, so a held space's reason reads faint (a primitive change);
a picker left open across an account change shows stale spaces (the bloc
ignores what it then sends); a failed sign-in carries no status, so a bound
database shows the bind row until the sign-in succeeds.

**P fix pass as built (2026-11-06, two implementers in separate worktrees,
patched into main together; gate: `dart analyze lib test` clean, whole
suite green bar one red that predates it — the timeline's now line
swallowed taps, fixed beside it).** Sync side: the merge-time rule of PR1
— a note under a folder tombstone is re-filed only when its stamp is above
the tombstone's or this device wrote the tombstone, else it stands (the
walk's first row reads both); one walk shared with **the sweep** (PR5,
`NoteDao.refileNotesUnderDeletedFolders`, run by `SyncPuller` only after a
complete pull, after `bind_merge_pending` clears, on the same predicate in
SQL; idle it is one query through the folder index and writes nothing; the
clock adopts the stored stamp before stamping, R98's reasoning; the moved
notes announced through `afterPage('notes', …)` as merged rows, so the
browser and an open editor follow; a failing sweep is logged and retried by
the next complete pull). Two-device scenarios on `sync_pair.dart` pin the
split-batch resurrection (B pulls between D's folder batch and note batch:
the note stands, then its tombstone applies) and the move-in (the deleting
device re-files, both converge), the editing device's sweep, a pull failing
part-way (nothing re-filed), and the initial merge's skipped note re-filed
after the clear. Browser side: the folder picker opens at the nearest live
folder and its crumbs stop at the first tombstone (`getAncestors(…,
stopAtDeleted:)`); `folderPathSegments` omits tombstoned segments; the
editor's "Open folder" opens the nearest live folder, the root browser when
there is none (a root note's "Open folder" now pops to the root browser
instead of pushing a page for folder `''`); the browser's crumbs stop at
the first tombstone (a live folder under a tombstoned parent is reachable
from a page opened before the pull or by launch restore); a restore drops a
per-note counter value whose note the archive did not carry (when it
carried notes) and files a note whose folder is neither in the archive nor
live here at the root (the restore appends, so a live local folder keeps
its note); `getFoldersByParent` orders by position then id and
`watchFoldersByParent` by name then id. Found, not fixed: the move undo
checks its destination with tombstones included, so an undo can file into
a deleted folder (`move_coordinator.dart:429,508`); a restored folder whose
parent the archive did not carry keeps a parent id that exists nowhere
(`FolderDao.importFolders`, the folder twin of the note fallback); a
browser page whose own folder becomes a tombstone while open has no
handling; a note whose tombstoned folder's chain runs into a folder not yet
received costs the sweep one walk per complete pull until it arrives.

**Review round 2 (2026-11-06; three reviewers and one design reviewer on
snapshots of `d59ca563`, `6ef9b848` and `77688ee8`).** Dispositions: a
letter names the fix stream (A the sync rule, B1 the bind service and the
database layer, B2 the bloc and the engine, C the UI).
*S4b-2a:* **BA-H1** (confirmed) a raw `.db` import of a bound database
stays bound — two databases of one install in one space, one `device_id`;
a kill between the bind's commit and the claim, or a swallowed registry
write, leaves a bound database with no claim → **B1**, a heal when the
binding service is built: bound with no claim, claim it when no other live
database holds the space, else unbind this one (logged). **BA-H2**
(confirmed) a download whose new database fails to open leaves the app on
closed repositories → **B1**, `AppDatabase.getInstance` remembers a
torn-down instance so the next successful open notifies the switched
handlers. **BA-M1** get_it singletons keep the old database after the
in-place switch → accepted: the download ends on the restart prompt, and
**C** keeps the page from being left while a step runs. **BA-M2** a kill
between the switch and the bind relaunches onto the empty new database →
**B1**, a download marker; at launch a marker left behind switches back.
**BA-M3** the download reads nothing in the cloud first → **B1**,
`readSpace` before anything changes. **BA-M4** with **BB-M2** the engine
stops after the binding changed and the flow goes idle on a stale status →
**B2**, stop the engine before the change, stay busy through stop → change
→ start → refresh, one emit at the end; the puller re-checks the binding in
each page transaction. **BA-M5** an account change mid-step drops the busy
flow → **B2**, an in-flight guard outside the state. **BA-M6** a rename of
the active bound database leaves a stale claim → **B1**. **BA-L1** a stale
self-claim blocks Download but not Merge → **B1**. **BA-L2** the main
database's first space is named `gym_notes`, the load-bearing directory
name, and spaces cannot be renamed (§8) → **B1**, the default database's
space takes the app's name (lettered). **BA-L3** a QA build's prefixed
registry cannot see the owner build's claims → accepted (QA cloud runs on
the emulator suite with fake accounts). **BA-L4** `bind()` itself does not
consult the registry → **B1**. **BA-L5** tests → with each fix.
*S4b-2b:* **BB-M1** Sync now is disabled during the quota and no-access
pauses it exists to end → **C**. **BB-M3** leaving the page during a
download loses the restart prompt → **C** (with BA-M1). **BB-M4** a bound
database reads as unbound while signing in, on the first frame and after a
failed sign-in → **C**, the view keeps the last known status. **BB-L5** up
to date beside not synced yet → **C**. **BB-L6** the status precedence is
unpinned → **C**. **BB-L7** with every space held the first shows selected
and disabled → **C**. **BB-L8** the bloc accepts a choice with no picker up
→ **B2**. **BB-L9** a failure leaves the status unrefreshed → **B2**.
**BB-L10** a failure's wording follows the binding, not the step →
deferred (B2's busy-until-refreshed closes the window it was seen in).
**BB-L11** the unavailable text names platforms → **C**. **BB-L12** the
Settings hub's search misses the section → **C**. **BB-L13** the restart
prompt's action has no id → **C** (space rows keep the Firestore id; the
device pass runs with one space). **BB-L14** the drawer flow's `--absent
"Sharing"` → **C**. **BB-L15** `SystemNavigator.pop` does nothing on iOS →
deferred with iOS. **BB-L17** same-named spaces → partly BA-L2; accepted.
*Design:* **DR1** (severity 3) the status row's height changes at runtime
and moves Sync now and Stop under the finger → **C**, one height for every
bound state, one count per detail line (DR10). **DR2** (3) a held space's
reason at 38 % (1.94:1) and cut at 2.0 → **C**, `FormCheckRow` dims label
and control and keeps the caption whole, as `FormPickerRow` does (rule AO).
**DR3** (2) picking a space resizes the sheet → **C**, fixed labels while
the list shows. **DR4** (2) the sheet's title clips in de/ro → **C**.
**DR5** (2) help-text captions under the choices → **C**, the labels carry
the outcome and the captions go (lettered — the owner may want them back).
**DR6** (2) a disabled row's reason at 38 % → **C**, on this page's disabled
rows (Sync and Pairing); the kit's other pages deferred. **DR7** (2) an
empty database's spaces look like a selection and commit on tap → **C**,
action rows. **DR8** (1) a sentence as a section label → **C**. **DR9** the
picker rows lack the button role (the `FormPickerRow` primitive) → deferred;
the device pass listens. **DR11** very tall rows at 2.0 → deferred (owner
call). **DR12** long names break mid-word → accepted. **DR13** the reason
repeated → **C**.
*P fix pass:* **PF-H1** (confirmed) sorting, renaming or repositioning a
folder another device deleted re-stamps its tombstone with this device's
id, which the rule's second condition trusts — the sweep then resurrects
that folder's cascade everywhere; the premise also fails for notes an old
cascade (Dec 2025) left live under this device's tombstones, for two
devices deleting one folder, and after a restore drops a queued cascade →
**A**: the rule is the first condition alone — a note is re-filed only when
its stamp is above the folder tombstone's (an edit after the delete), at
merge time and in the sweep — and the three folder writes refuse a
tombstone. **Accepted in exchange:** a note moved into a folder while
another device deleted that folder stays under the tombstone, findable by
search, until it is edited or moved. PF-M2–M5 and PF-L6 are moot with the
condition gone. **PF-L7** a cut pull is untested → **A**. **PF-L8** bar
assignments and currencies keep unmapped note ids → accepted (settings stay
local). **PF-L9** paths and crumbs disagree on a live folder under a
tombstone → **A**.

**Review round 2 fixes as built (2026-11-06; four implementers in
worktrees, patched into main together; gate: `dart analyze lib test`
clean, gen-l10n, whole suite 13,743 passed, 12 skipped, none failed).**
**A** (`7c3735b3`): one condition — a note is re-filed when its stamp is
above its folder tombstone's, at merge time and in the sweep;
`updateFolder`, `updateFolderPosition` and `updateFolderSortPreferences`
refuse a tombstone (no write, stamp or outbox entry); `folderPathSegments`
cuts where the crumbs cut; the sort-between-batches resurrection, the old
cascade's notes and a cut pull are pinned. **B1** (`5e9ad554`): the heal in
`SyncBindingService._build` (skipped under the suspension) — bound with no
claim: claim when free, unbind when another existing database holds the
space; `AppDatabase` announces the switch after an open that failed past a
teardown; the download writes `sync_download_in_flight` before the switch
and clears it after the bind or on the way back, and the first
`DatabaseManager.getInstance()` of a process switches back from a marker
left behind (the new file stays); the space is read before anything
changes; the claim follows the name at write time and through a rename;
one holder rule for Merge and Download; the main database's first space is
named "ANTA" (`kAppName`); `bind()` refuses a held space inside its
transaction. Two consequences fixed in the same commit: `DatabaseManager.getInstance`
is one memoized future and `SettingsService.getInstance` publishes its
instance only once its database is set — both used to hand a second caller
a half-built instance, which 46 widget tests hit once the manager awaited
one step more; the alarm suite's two-rings case scripts the ring it stops,
because it had passed only while that half-built manager made the real
Stop fail at once. **B2** (`b6a680cf`): every binding step stops the
engine first, stays busy through the change, the restart and the status
read, and settles in one emit; a failed step restarts a running engine and
reads the status; the puller refuses a page whose run began on another
binding; an in-flight guard outlives an account change; picker choices only
from the picker. **C** (`080bbb16`): the status row's title and both detail
lines sized from templates, one height in every bound state; this page's
disabled rows keep their reason at full strength; Sync now in the quota and
no-access pauses; the page held while a step runs; the last known status
kept through a sign-in; "Waiting for the first sync"; the precedence
pinned; a neutral unavailable line; the hub's keywords; the restart
prompt's id; the drawer flow re-pointed; a disabled `FormCheckRow` keeps
its caption whole and wrapping; under a list the actions read "…the
selected space"; no help captions; the sheet's own title; an empty
database's spaces as action rows; nothing selected when every space is
held. Found, not fixed: the heal trusts the registry, so a stale claim of
another database unbinds a really bound one; the puller's post-pull writes
(`pull_seen`, `last_pull_at`, the `bind_merge_pending` clear, the sweep)
sit outside the binding check — the bloc's stop-first covers its own steps;
a failed stop still adds a line under Stop; the Account row's unavailable
description still names platforms (must-not-change); a real
`AlertRingController`'s best-effort calls now wait on the manager's first
open instead of failing fast, so a service that hung would hold the alarm
page on Stop — worth a timeout, the alarm area's call.

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
  `permissionDenied`, `invalid-argument` → `invalidData`,
  `failed-precondition` (a missing index) → `unknown` with its own log
  line, else `unknown`. Persistence off in DI (§3.8). DI binds the
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

**S5 as built (2026-10-25, one implementer; gate: `dart analyze lib test`
clean, whole suite once — 10,451 passed, the one Windows-only failure;
review pending, fixes at the head of S4b-2).** **Part 1, the S3d-review
fixes**, each confirmed by breaking it and watching its test go red: H1
`_abortsTransaction` (`CouldNotRollBackException`, or a `SqliteException`
whose `resultCode != 19`) rethrows out of the per-merge catch — the
disk-full test uses `PRAGMA max_page_count`; H2 `_yieldToFloor` retires the
local entry at its stamp when at or below the floor, and the pusher keeps
every pull-parked key out of the drain (not only floor runs — the device
lacks the space's version either way); M3 `_PullOutcome.cut` / `reached`,
a run drains when `!initial || pulled.reached`, the flag clears only on a
complete pull; M4 the lifecycle calls set the foreground before the
started check and the bridge drops its `isStarted` guard; L5–L10 as the
record states (`_signalOf(space)` for stale tables and `pull_seen`, a cut
pull defers `afterRun` until after the drain, a healthy snapshot clears a
signal failure, `onDone` re-attaches on the signal's back-off, a merged
envelope leaves the parked set); T1–T5 pinned (`_FaultyMerge.partWay`,
`FakeSyncGateway.readSpaceCalls` outside `calls`).
`SyncRunReport.parked` now counts newly parked keys through an engine
counter (the set-size difference went negative once keys could leave).
**Part 2:** `lib/services/sync/firestore_sync_gateway.dart` —
`FirestoreSyncGateway` (lazy instance, `maxBatch` 499, §3.1 paths, one
`WriteBatch` with the space document merged in, the ten-second overlap on
`resumed`, the error mapping; `_guard` adds a **60 s timeout mapped to
`offline`** since the engine runs one request at a time; a malformed
document is skipped with a debug log and the cursor moves past it —
gateway decoding sits outside the engine's per-envelope catch;
`invalid-argument` alone maps to `invalidData`, `failed-precondition` to
`unknown`; `createSpace` reads the document back for the real `createdAt`,
one extra read) with the pure helpers in `FirestoreSyncWire` and a static
`configure({emulatorHost})` that sets the emulator and
`persistenceEnabled: false`, so DI never imports `cloud_firestore`; DI
registers `SyncGateway` before the engine-start line when `canSync`;
`QaMode.firebaseEmulatorHost` (`ANTA_QA_FIREBASE_EMULATOR`), `qaAccount`
(`ANTA_QA_ACCOUNT`, `uid:email`) and the const `useFirebaseEmulator`;
`FirebaseAuthService.useEmulator(host)` and `_signInQaAccount()` with the
**unsigned JSON id token** `GoogleAuthProvider.credential(idToken:
jsonEncode({sub, email, email_verified: true}))` — the documented form
(firebase.google.com/docs/emulator-suite/connect_auth); no email/password
fallback. `qa build --define K=V` / `qa run --define` feed the defines.
**The rules probe** `tool/firebase/rules_probe.ps1` starts the emulator on
18080 (the strays hold 8080), signs requests with unsigned JWTs in the
`rules-unit-testing` form and judged 16 cases, **all PASS**: owner create /
read / push / read row / list; stranger read and push denied; signed-out
denied; tombstone with `data: null` allowed and without the key denied;
`ownerId` null denied; lower-schema merge denied, equal and higher allowed;
a push to a missing space denied; an unknown table denied; `pushedAt` not
`request.time` denied. One INFO row: a row written alone under a missing
space, with no space write, is allowed — the rules never check the parent
exists; the gateway always writes the space document in the same batch,
which is what the denial rests on. Tests: `firestore_sync_gateway_test` 12
(cursor codec incl. row keys containing `|`, overlap, both document
mappings, the merge payload, error codes, `maxBatch`, the `cloud_firestore`
import scan). Not run from the app yet: the emulator sign-in and the live
gateway — S6. Every Android build with Firebase now constructs and starts
the engine; it syncs only a bound database, and binding arrives in S4b-2.

**S5 review (2026-10-25, one independent reviewer on a snapshot, twelve
mutations, the suites also run on background-isolate databases, the
plugin's cursor code read; 2 high, 5 medium, 8 low; "the commit stands as
the base").** **H1** `watchSpace` forwarded cache snapshots: offline, the
first snapshot of an unwatched document is `exists: false, fromCache: true`
→ `noAccess` with the listener detached and nothing to lift it (launch
offline with a bound database, or leave the app, lose signal, come back);
**H2** the emulator pass would run under the app's real project id while
the suite, the Auth tokens and the probe use `demo-anta` — the rules might
not apply, and the pass would prove nothing. Mediums: M3 the
`SqliteException` branch of the disk-full fix can never match in the app —
the production database runs in a background isolate and the error
arrives as `DriftRemoteException` (probe; the whole-transaction case is
still caught through `CouldNotRollBackException`, a statement-level error
is not); M4 offline, the SDK queues a `commit()` in memory even with
persistence off, the call waits out the 60 s timeout, is reported
`offline`, lands on reconnect and every retry adds a copy — `createSpace`
the same, giving duplicate spaces; M5 a multi-MiB batch on a slow uplink
times out and is retried whole forever (the request cap is 10 MiB); M6 the
pusher's pull-parked exclusion and M7 the `onAppBackgrounded` foreground
write are surviving mutants (no test), and `start()` does not read the real
lifecycle state. Lows: L8 the device's own write snapshot has null server
timestamps (covered by H1's filter); L9 a page of only skipped documents is
re-read every pull (unreachable past the rules); L10 a resumed page's
`next` can fall below the stored cursor when 499+ documents share the 10 s
window (progress-safe); L11 no empty-batch guard; L12 the define's "uid" is
the Google `sub`; L13 a missing-index error (`failed-precondition`) is
retried quietly; L14 the S5 plan text said `failed-precondition →
invalidData`, the build and §3.3 say `invalid-argument` alone (the plan is
corrected here); L15 a vacuous ordering test, the import scan missing
`cloud_firestore_platform_interface`, four probe cases missing (upsert with
`data: null`, tombstone with map data, a client `createdAt`, a `createdAt`
change), no port-free check, indexes never enforced by the emulator.
Verified: `startAfter` takes a plain string for the document-id component
(the plugin's `_assertQueryCursorSnapshot` / `_assertQueryCursorValues`);
`Settings.copyWith` keeps the emulator host; the watch error path; `ackThrough`
only after a returned push; `pushBatch` the only row writer. All settled in
§3.3, §3.5 and §3.8. **Fixed in S5b** (a short gateway run after S4b-1,
before S4b-2): H1, H2, M3–M7, L11, L12, L15; L9/L10 accepted, L13 as a
log line.

**S5b as built (2026-10-25, one implementer; gate: `dart analyze lib test
test_driver` clean, whole suite once — 10,486 passed, the one Windows-only
failure; review pending, fixes at the head of S6).** `watchSpace` listens
with `includeMetadataChanges: true` and forwards only server snapshots
without pending writes (so the server's first answer arrives even when it
equals the cache; `FirestoreSyncWire.shouldForwardSnapshot`); `pushBatch`
and `createSpace` write through a write-only `runTransaction` with
`maxAttempts: 1` (nothing to re-read; the engine's back-off is the retry;
the 60 s guard stays a backstop) — the plugin documents "transactions must
be performed while online … the final commit will fail", read from
`firestore.dart:254`; fail-fast offline rests on that contract and is not
yet device-verified; the empty-batch `ArgumentError`; `failed-precondition`
logs its own line; `pullPage` takes `next` by `compareCursors`. The puller
unwraps nested `DriftRemoteException.remoteCause` before the abort test
(`package:drift/isolate.dart`); the disk-full case passes on a background
database even without the unwrap (SQLite aborts the whole transaction and
`CouldNotRollBackException` arrives), so the pinning test is a statement
SQLite refuses (`SELECT` from a missing table) — without the unwrap the row
was parked, with it the page fails whole. The pusher caps a batch at
`maxBatchBytes` = 8 MiB in order (ten 850 KB notes go out as nine and one;
a 3 MiB row is parked by the 900 KB check first). `noAccess` is re-checked
by `syncNow()` and `onAppResumed()` with one `readSpace` — only a pause a
readable space can disprove (missing or unreadable space, a pull or watch
denial); "more than twenty refused rows" keeps holding (`recheckable:
false`). `start()` seeds the foreground from an optional `lifecycleState`
reader (the singleton passes `WidgetsBinding.instance.lifecycleState`; null
keeps what the lifecycle calls tracked) and the bridge takes `initial:`
through the shared `isLeave` (hidden or paused). `QaMode.firebaseEmulatorProject`
/ `emulatorFirebaseOptions()` and the main.dart demo-options branch were
built as briefed but are **ineffective on Android** (above) — a warning
prints when the returned app keeps another id; S6 runs the suite under the
real id instead. The probe gained four cases and a port-free check (exit
101 naming the held ports): 20 judged cases PASS plus the INFO row, on
18080; its emulator stopped, the six strays remain. Tests: gateway +5,
failures +3 (incl. `sync_pair.open(background:)` on temp files), lifecycle
+4, bridge +1, `test/core/qa/qa_mode_test.dart` new. Noted: `_prepare` holds
up to 499 encoded rows in memory (pre-existing).

**S5b review (2026-10-25, one independent reviewer on a snapshot, six
mutations — five killed, one survived — the plugin sources read from the
pub cache; 0 high, 3 medium, 7 low; "the commit stands").** Mediums, all
S6 wiring: M1 the `demo-anta` branch in `main.dart` and
`QaMode.emulatorFirebaseOptions()` is dead on Android and, where Dart
creates the default app itself (iOS, no tracked plist), would reintroduce
the mismatch the other way; its doc comments say the opposite of the
record → delete it, initialise with `DefaultFirebaseOptions.currentPlatform`
on every path, drop the `firebase_core` import from `lib/core/qa` (L8); M2
the tooling still hard-codes `demo-anta` (`tool/firebase/emulators.cmd|sh`,
`rules_probe.ps1` with no `-Project` parameter, `test/firestore/rules_test.dart`)
→ a project argument defaulting to `alexs-note-tracking-app`, and confirm
firebase-tools starts a non-demo project offline and logged out; M3 the
emulator port is a const 8080 and the strays hold it — a guest's `10.0.2.2`
is the host's loopback, so the app would talk to a stray suite of unknown
project and rules → S6 stops the strays first and checks the suite's own
PIDs own 8080 and 9099 before installing. Lows: L4 `createSpace` on a slow
link (the Android transaction timeout bounds only the native wait for Dart's
commands) can report failure after the commit landed → one server `get` of
the drawn id before giving up; L5 a `pushBatch` commit stalled over 90 s
can land after the back-off re-push and overwrite a newer version (the
real fix, a monotonic `hlc` in the rules, is must-not-change — recorded as
a risk); L6 `_regainsAccess` lifts the pause on a readable space whose
`schema` is above ours (one wasted pull and a denied push before
`appOutdated`) → set `appOutdated` there; L7 the `watchSpace` call site is
untested (`isFromCache: false` survived) → S6 drives an offline launch with
a bound database: the pause stays `none`, the first server snapshot starts
a stale run; L9 whether the old 500-writes-per-commit limit counts
transforms (one 499-row drain in S6); L10 record drift (`tool/firebase/firebase.json`
→ `firebase.emulators.json` at the package root; the define doc). Decision C
agreed. Verified: the Android listener errors then ends the stream and the
engine's detach makes `onDone` a no-op; a duplicate server snapshot is a
no-op run; `Transaction.set` carries `merge`; a handler with no reads is
allowed; `_Queued.bytes` is UTF-8 bytes; per-write overhead ≈ 0.25 MiB on a
full batch. **S6 carries** M1–M3, L4, L6, L10 and the two device checks L7,
L9.

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

**S6 as built (2026-11-06; one `qa-runner` on `anta_qa_1`/`anta_qa_2`
against `tool/firebase/emulators.cmd`).** The first sign-in failed with a
bare "Sign-in failed": a debug build had no cleartext allowance, and
Android refuses `http://10.0.2.2` since API 28 — fixed in `ed966d7a` (a
debug-only `network_security_config_debug.xml` for `10.0.2.2`,
`localhost`, `127.0.0.1`; release builds keep the platform default) with
`FirebaseAuthService._guard` now logging the cause it maps. Then green:
A (the `basic.json` seed) signed in as `qa1`, "Sync this database" created
the space and read "Up to date" within about 15 s; B (empty) signed in as
`qa1`, bound in one tap with no picker and showed A's three root folders; a
line typed on B reached A's note within about 10 s; a folder deleted on A
left B; with the suite stopped A read "Offline — will retry" and the
Pairing row its offline line; a `qa2` build on B over its bound database,
signed out, read "Paused — signed out", and signed in as `qa2`, "Paused —
this database syncs with another account" with Stop offered (D5). The
saved suites on a normal QA build at `ed966d7a`: browser 3/3, settings
20/20, calendar 35/35, alerts 5/5. Noted, not fixed: a persisted Firebase
session outlives a reinstall with another `ANTA_QA_ACCOUNT` (sign out
first); `firebase_firestore` logs a `MissingPluginException` for
`cancel` on a transaction stream at teardown.

**Final review (2026-11-06; HEAD `caa60b05`; five agents in parallel, each
probing only in its own `git archive` snapshot — `fable-max` on the owner's
path end to end (F), three `reviewer`s on the four fix commits the second
round left un-reviewed (X: `7c3735b3`, `5e9ad554`, `b6a680cf`,
`ed966d7a`), on the Sync section, the picker and `SyncBloc` as a state
machine (U) and on the wire, the rules and the v44/v45 migrations with the
`calendar_category_profiles` table the analytics run added after the last
sync review (W), and one `design-reviewer` on the section after C (D); the
owner's word relaxed the one-reviewer rule. The whole suite was not re-run
(13,743 at `86ac800e`); the agents ran the sync, bloc, widget, guard and
rules suites in their snapshots, all green, `dart analyze lib` clean.**
**Verdict: GO WITH CONDITIONS — no blocker.** The phone's own data is not
at risk on its first bind: its first pull meets an empty space, so no local
row changes (only `owner_id`, the outbox, the binding keys and
`sync_metadata` are written), and the first upload is idempotent across
kills and retries. Every data-loss path found is on the **second** device's
bind and is decided by the order of the two binds and by the picker's
choice, which §7's checklist controls. Rehearsed by W on a copy of the
owner's export: v42→v45 in 64 ms, `user_version` 45, every table's
live/tombstone count equal to §11 (`calendar_category_profiles` 0/0, skips
0/0, `sync_outbox` empty, `last_hlc` seeded, no floor); the bind queued
312 rows, one `pushBatch` of 312 in 108 ms, an empty second database pulled
312 in 174 ms, 39 of 39 note texts equal, categories and counter values
equal, `content_chunks` 14/0 on the puller by design; `rules_probe.ps1`
20/20 and `test/firestore/rules_test.dart` 55/55 against the emulator;
`firestore.indexes.json` holds the 18 `data` exemptions. Dispositions
below are the lead's recommendations; the owner's word decides the fix
pass. **Recommended before the bind:** F-2 (the seed stamp), X-1 (the
heal's unbind), X-3 (the rename's registry write), U-1 and U-2 (the bind
flow across a sign-out and on the first frame), F-1's caption, F-4's
wording, W-3's one command (its docs half done with this review). The rest
is a fix pass after the phone check, or deferred.

*F — the owner's path (four probes on `sync_pair.dart`, all passing as
predicted):* **F-1 (H, confirmed, probes P1/P10)** the order of the first
two binds decides whose data survives and nothing in the UI says so: a
never-bound database floors at bind (`sync_binding_service.dart:306`,
`writeBindFloor` when none exists), so every row it holds is ≤ `bind_floor`,
under which `CrdtMerge.mergeRemoteRow` lets any remote twin win, older
included (`crdt_merge.dart:66-69`), retires the local outbox entry and
files no conflict copy (`note_dao.dart:988-990`). The owner's order (the
phone first and drained, the emulator holding an older copy with the same
ids) is right for the copy, but every edit or delete made on the copy
after it was taken vanishes silently (P1: B's newer edit reverts, B's
newer delete is undone, no conflict, converged); the reverse order loses
the phone's newer edits and deletes on both devices with its outbox entries
retired (P10) — only the export recovers. Readiness D15 by design; the
picker's rows ("Merge this database into …", "Sync with …") carry no
caption since DR5 → the checklist's order, and a caption or confirm on
Merge and Sync with: "rows this database and the cloud both hold take the
cloud's version". **F-2 (M, confirmed, P9; the right order pinned by
P9b)** the floor protects a second device only against rows already in the
space at its first pull: if the phone is bound but its upload has not
landed when the emulator binds, the emulator's empty complete pull clears
`bind_merge_pending` (`sync_puller.dart:132-135`) and the two devices'
rows then meet by plain LWW — the emulator's seeded built-in categories
(stamped "now" at its first open, `CategoryService._seedBuiltIns`) beat the
phone's categories (one migration-time stamp, `database_migrations.dart:1878`):
the export's five hidden built-ins (`competition`, `measurement`,
`mobility`, `other`, `rest`) un-hide on both devices and renamed or
recoloured built-ins revert → seed built-ins with an epoch-floor stamp so a
seed loses every LWW to a real edit; until then, the checklist's order.
**F-3 (M, plausible)** a JSON restore on a bound device is not a rollback
of the cloud: `BackupService._importFromJson` unbinds, appends note and
folder copies under fresh ids, wipes and re-inserts the calendar under the
archive's ids and writes the floor after (`:380-381`); the next Merge
yields the calendar back to the space and pushes the fresh-id copies beside
the originals on every device → the checklist's fallback (a `.db` import as
a new database + Upload as a new space; Download on the other device), one
line for §8. **F-4 (L, confirmed)** `syncFailedPermission` ("check you're
signed in to the right account") is exactly what a tap before the rules
deploy shows (`listSpaces` → `permission-denied`,
`sync_space_service.dart:413-417`); nothing is written and the next tap
proceeds → add "…or sync isn't set up in the cloud yet". **F-5 (L,
confirmed; = W-3)** the deploy command disagreed across the docs (rules only
in §3.7, the analytics roadmap and `firestore.rules:8`; rules and indexes
in the reference); `firebase.json` holds only the `flutter` block and there
is no `.firebaserc`, so the `firestore` block and `--project` are both
needed; a rules-only deploy breaks nothing (the pull's `orderBy` pair and
`listSpaces` use automatic single-field indexes) and costs the 18 `data`
exemptions → one command everywhere (the docs with this review; the rules
header comment with the fix pass). **F-6 (L, D8 by design)** counter taps
on both devices between two syncs do not add up. **F-7 (L, known)** a kill
between `createSpace` and `bind` leaves an empty "ANTA" space; the next tap
shows the picker — Merge is the right choice there, Upload would make a
second "ANTA" nothing can delete before Phase 04. **F-8 (L, by design)**
`databaseHoldsData()` counts any live row outside the built-ins
(`sync_space_service.dart:182-194`): an emulator with leftover data gets
the picker, and Merge uploads that data and its tombstones into the space.
**F-9 (L)** two accounts on the two devices give two silent "ANTA" spaces,
"Up to date" on both. **F-10 (L)** a stale quick-boot snapshot mints stamps
in the past until the clock corrects → cold boot. Clean on this path: the
first batch (312 rows + the space document = 313 writes in one write-only
transaction, under 500), kills mid-drain and mid-pull, the empty first pull
storing no cursor (`sync_puller.dart:229-230`), `bind_merge_pending`
clearing on an empty complete pull, tombstones for never-seen notes
(inserted with no chunks and no FTS row, `note_dao.dart:981-984`), the
read-back, loops (a `keptLocal` re-queue converges in one round), the
heal, mismatch, sign-out, quota, `appOutdated`, Stop → rebind; the export
holds no live note under its tombstoned folder, no event on a deleted
category, built-ins at their seed names.

*X — the four fix commits (every ledger claim found in the code; 25
revert probes, 23 red, two vacuous; the caller table and the probe table in
the review's report):* **X-1 (M, plausible)** the heal's unbind
(`sync_binding_service.dart:165` → `unbind()` `:321-327`) is the full Stop
path — it clears the outbox and writes the floor at the current clock — so
the recorded stale-claim case (another existing database's stale claim
unbinds a really bound one) also loses that database's unpushed edits: at
its next Merge every local row is ≤ the new floor and yields silently → the
heal's unbind clears the binding and the claim but keeps the outbox and
writes no floor. **X-2 (L)** a heal that unbinds is a `debugPrint`
(`:161-165`) and the Sync section reads "not syncing" with no reason → a
one-shot note the section shows once. **X-3 (L–M, plausible, every user,
bound or not)** B1 moved `spaceRegistry.rename` between the `.db` rename
and the `-wal`/`-shm` renames (`database_manager.dart:266`) with no catch
(`SyncSpaceRegistry._write` throws; with no claims it still calls
`_prefs.remove`): a failing `SharedPreferences` write splits an open
database from its WAL — Android lets the active database be renamed and
the WAL may hold un-checkpointed pages → try/catch and log the registry
rename, never between the sidecar moves. **X-4 (L)** the marker recovery
(`database_manager.dart:88-103`) trusts the marker: a bind that commits
but whose `clearDownloadInFlight` fails (logged only,
`sync_space_service.dart:289-295`) puts the user back on the old database
at the next launch after a session's work on the new one; a `from` that no
longer exists is created empty → switch back only when the active name is
`marker.to` and `from` exists. **X-5 (L)** the claim follows the active
name, not the opened database's (`sync_binding_service.dart:113-118`): a
bind or unbind between a Databases-page switch and the restart writes the
claim under the other name; low because the restart prompt cannot be
dismissed and the bloc stops the engine first → answer the name
`AppDatabase` opened, updated by a rename. **X-6 (L)**
`SettingsService._open`'s `mayRetry: false` pass publishes without
re-checking the generation (`settings_service.dart:84-95`): a second switch
during the retry registers a service over the closing database after its
reset fired → throw or loop. **X-7 (L)** `DatabaseManager`'s `_instance ??=
_create()` memoizes a failed open forever (no generation retry despite the
round-2 wording; not worse than before) → clear on failure. **X-8 (L)**
`deleteAllData` (`database.dart:253`) sends the switching notice without
setting `_switchUnannounced`; the static flag is never reset between tests
→ set it there, a `@visibleForTesting` reset. **X-9 (L)** a step waits on
`engine.stop()` → `whenIdle` up to the 60 s gateway timeout per in-flight
call (bounded; U-3's bounded half). **X-10 (L, confirmed)** the binding
check on an all-skipped page (`sync_puller.dart:231-234`) is unpinned —
removed, `test/services/sync` stays green (+442); `_checkStillBound`
reports `unbound` for a rebind to another space too → a cursor-only page
meeting a rebind. **X-11 (L, confirmed)** the `DatabaseManager` publish-once
is effectively unpinned (reverted, the widget suite's one red was load; the
`SettingsService` half is well pinned, −37 with 56
`LateInitializationError`s) → two concurrent `getInstance()` calls reading
the active name. **X-12 (L)** `_guard`'s new lines print in release
(`debugPrint` is never swapped) and `GoogleSignInException.toString()` can
name an account → `kDebugMode`, or `e.code` only. **X-13 (L)** `readSpace
== null` throws `permissionDenied` (`sync_space_service.dart:255-257`), so
a space deleted from the cloud reads as no access. **X-14 (L)** a notes
page halted by `_checkStillBound` skips `afterPage`, so `_pageStrings`
stays until the next notes page (as on any throwing page). **X-15 (L)**
`updateFolderPosition` has no caller in `lib`. **X-16 (info)**
`alarm_page_test.dart` keeps what its case pinned (the lower ring ending
elsewhere closes its own page, the upper keeps ringing) and never pinned
"Stop stops two rings"; a real controller's Stop through the scheduler is
the recorded alarm item. Checked clean: the heal under a restore (skipped
under the suspension; `BackupService:419-420` unbinds inside it with the
generation unchanged), the heal on launch for unbound users (one read), a
normal launch and a Databases-page switch announce once, the puller's halt
is the page transaction's first statement (no merge, cursor, clock advance
or registry claim; `bind_merge_pending` untouched; `_Halted` rethrown out
of the run), live-folder writes unchanged (`stampLocal` defaults to
upsert; the drag reorder and the labels already skipped tombstones in
SQL), `folderPathSegments` unchanged without a tombstone above a live
segment, `ed966d7a` touches `src/debug` only (the main manifest's last
change `cffc5c0e`, no `networkSecurityConfig`; a `--profile` run against
the suite would be refused cleartext), the background isolate never
touches `DatabaseManager`.

*U — the Sync section, the picker and the bloc as a state machine (the
five suites +385 green; `flutter gen-l10n` clean, `untranslated.txt` `{}`,
the generated files equal to the tree's; the four C pins red under their
reverts; the state table in the review's report):* **U-1 (M, confirmed by
a bloc probe; H if BA-M1's stale singletons can write)** the Account row
stays enabled during a step: a sign-out (or an account change from the
auth stream) while a Download, Merge, Upload or Stop runs makes
`_emitAccount` (`sync_bloc.dart:500-513`) show the new account with an
idle flow, the `BlocSelector` releases the `PopScope`
(`sync_settings_page.dart:88-92`, `:286-299`), `_settle` sees another
account and emits nothing — the download finishes but
`SyncBindIdle(switchedToDatabase:)` never arrives, no restart prompt, the
page can be left; BA-M1 was accepted only because both held → disable
sign-in and sign-out while `flow.isBusy`, defer `SignOutRequested` while
`_stepInFlight`, settle a download's `switchedToDatabase` whatever the
account (or hold the page on the bloc's in-flight flag). **U-2 (M,
confirmed at the bloc)** `_emitAccount` emits the account with
`SyncStatus.empty` before the status read; the page stores it as
`_lastStatus` (`sync_settings_page.dart:133-139`, `:403-406`), so C's fix
covers only the `SyncInitial`/`SyncSigningIn`/`SyncFailure` frames and a
bound database draws the enabled "Sync this database" row until the read
lands — for good when the 3 s read times out, where a tap answers "already
syncs — stop syncing it first" with no Stop row → the placeholder never
overwrites the last status (the bloc carries the database half of the
status across accounts, or marks it unknown); C's pin drives a fake bloc
that never emits this state. **U-3 (M, plausible)** a step has no overall
time limit and the page is held for its length: `listSpaces` + `readSpace`
+ `createSpace` at 60 s each (`firestore_sync_gateway.dart:404`) plus the
10 s read ≈ 3 min on a slow network, and `before?.stop()` → `whenIdle` (a
run's apply hooks), `_resolveEngine()` and the download's switch are
unbounded → a limit on the engine stop and on the step, settled as failed.
**U-4 (L, confirmed by C's own pin)** a bound database after a failed
sign-in (`SyncFailure`) shows Sync now and Stop disabled with no reason
(`sync_settings_page.dart:509-519`; the test "Sync now and Stop wait for an
answer" asserts it); D5 promises Stop whatever the account → enable Stop on
the last known binding. **U-5 (L)** after an account change mid-step the
new account's rows draw enabled with no spinner and every tap is ignored
until the hidden step ends (`sync_bloc.dart:35`, `:257-262`, `:328`) →
expose the in-flight flag in the state (closes U-1's hold too). **U-6 (L,
confirmed)** the page imports `sync_gateway.dart` (`SyncGatewayFailure`)
and `sync_status.dart`, the sheet `sync_gateway.dart` (`SyncSpaceInfo`) —
value types, against the letter of "the page talks to `SyncBloc` only" →
re-export from `sync_state.dart` as `SyncBindFailure` is. **U-7 (L,
confirmed)** no saved flow drives `sharing-sync-status`, `-now`, `-stop`,
`-stop-confirm`, `-restart` or any `sync-picker*` id (only
`settings/09_hub_sharing.txt:16`); S6 ran ad-hoc verbs → save S6's step
list as a flow suite. **U-8 (L)** the hub's keywords are the three section
names (`settings_hub_page.dart:364-368`); "merge", "download", "stop",
"devices" miss → `_keywords(l10n.syncKeywords)`. **U-9 (L)** the German
restart prompt says "Sie" among "du" strings (shared with the Databases
page). **U-10 (L)** `syncThisDatabaseUnavailable` ("isn't available in this
version") is also what a failed Firebase init shows. **U-11 (info)** the
`FormCheckRow` change reaches `category_goal_sheet.dart:327` (a disabled
row's reason now at full strength and unclamped — fits the intent; D for
the look). Checked clean: `pauseOver` used alike by the engine, the bloc
and the page (pause → run → failure → pending → waiting → up to date);
double taps guarded synchronously; a stale picker choice ignored; ✕, the
barrier and system back send `BindFlowDismissed`; the restart prompt cannot
be dismissed and carries `sharing-sync-restart`; the stop confirm says the
cloud copy stays in three languages; one snackbar per failure; the ids
match the record; the pairing files unchanged since `b2f04731`; the page's
one Pairing hunk is DR6's `_disabledTile`; the browser and editor hunks are
the §3.9 rule and the P slice's folder fixes, no sync chrome.

*W — the wire, the rules, the migrations (nothing at H or M; 311 guard
tests green across 16 files; the profiles codec covers every column, a
tombstone, a required key, a mismatched id and export parity; the profiles
merge suite runs the shared contract; the drain orders
`calendar_categories` before `calendar_category_profiles` within a stamp,
and a profile arriving first is stored as an orphan the category then makes
whole; a category delete tombstones its profiles through `CrdtWrite` with
an outbox entry each; the v45 sweep writes `is_deleted`, `deleted_at`,
`updated_at`, `version + 1`, the hlc and the device id, seeds the clock
from `last_hlc` and queues on bound and unbound databases alike; the
engine and the space service report `DatabaseSchema.currentVersion` = 45):*
**W-1 (L)** the v45 sweep's pull side — a v44 device bound to a space still
at schema 44 (no v45 push yet) pushes a live skip on an event that later
becomes a one-off, or a fresh v45 install downloads one, and nothing sweeps
on pull; `schema >= stored` and `appOutdated` close it only after the first
v45 push; unreachable at the owner's bind (skips 0/0, both devices v45) →
accept, or refuse a space below this build's schema until it is raised.
**W-2 (L)** backup v8 shipped with v44 and v45 kept it, so a v8 archive
from a v44 build carries converted-series leftover skips a v45 restore
keeps (`backup_service.dart`, `< 8`) → v9 at v45, or accept as a dev-only
window. **W-3 (L, confirmed; = F-5)** the deploy command. **W-4 (L,
confirmed)** `sync_pair.dart:33-34`'s `syncSchema = 43` is stale (used
relatively, nothing masked; no test pins that `SyncEngine.getInstance`
passes `DatabaseSchema.currentVersion`) → `DatabaseSchema.currentVersion`.
**W-5 (L)** neither emulator suite writes a profiles document; membership
is pinned textually by `firestore_rules_tables_test` → one probe case over
the newest table. **W-6 (L, doc)** "a column added after v43 decodes to its
default" (§3.4, the reference) should read "a column added to a table
after that table's first synced schema" — the profiles table is wholly
after v43 yet strict, rightly (B parked four planted malformed envelopes
and merged a minimal live one and a data-less tombstone with defaults).
**W-7 (L, beside the diff)** `FolderDao.importFolders`
(`folder_dao.dart:292-294`) restores a subfolder whose parent is neither
archived nor live under the dangling id (the notes got a root fallback in
`3561409c`) → the same live check for folders. **W-8 (info)** two devices
creating the first profile of one category keep both live until the next
local save, serving the same active row; a concurrent clear against an
edit ends live (R77).

*D — the look after C (the spec checklist passes: one height across the 17
bound states at en/de/ro × 1.0/1.3/2.0 × 360/412, Sync now and Stop still,
one count per detail line, DR2/DR6 reasons at 8.88:1 light and 9.56:1
dark, the picker one size while a space is picked, the title whole at
de/ro 2.0, no captions, action rows, the ids present, targets ≥ 48 dp;
`sync_section_test` +92):* **D-1 (2, confirmed)** the fixed height leaves
the row half empty — 118 dp at en 1.0/360, 404 dp at de or ro 2.0/360 on
a 780 dp screen — because the title slot and the details slot are each
sized to their own tallest template, so the blank stacks in two places and
the centred glyph lines up with the details, not the status
(`sync_settings_page.dart:463-485`, `:529-546`, `:549-590`) → one slot for
title and details so the blank falls under the last line,
`titleAlignment: top`; DR11 (tall rows at 2.0) stays the owner's call.
**D-2 (2, confirmed)** busy states and status changes are never announced:
the spinner (`_RowBusyIndicator`, `:1041-1051`) has no `semanticsLabel`,
nothing uses `liveRegion`; while checking or binding `sharing-sync` reads
as an enabled non-button with its idle label (WCAG 2.2 SC 4.1.3) → a busy
label or a "Checking…" value, the pauses and the bind/stop results
announced politely. **D-3 (2, confirmed)** `sync_section_test.dart` has no
`meetsGuideline` matcher (the review's own 84 passes over 12 page states,
the dialog and 6 picker states) → add the three. **D-4 (1–2, confirmed;
known)** a failed stop grows the Stop row (48→62 dp en 1.0, 144→288 dp de
2.0) and pushes Pairing → a caption slot that always exists, or the failure
in the snackbar only. **D-5 (1, confirmed)** the unbound row's height
differs between its states (80 dp signed in/checking/binding against 62 dp
signed out/unavailable at en 1.0) and a failure grows it 36 dp at de 2.0
right after the tap. **D-6 (1, confirmed)** a sign-out moves Sync now and
Stop 40 dp at ro 2.0/412 through the Account row above. **D-7 (1)** the
empty database's "Sync with" rows take the `FormPickerRow` shape (about
76 dp, the caption a line below) while the list mode's check rows are
62 dp. **D-8 (1)** the pre-selected space is the first free one in list
order (`sync_space_picker_sheet.dart:96-104`) — right because the service
sorts most recently written first (S4b-2a). **D-9 (1)** the snackbar's ✕ at
48×16 dp and its text at 1.4:1 were captured mid-entrance → device check.
**D-10 (0, exempt)** disabled picker labels at 2.35:1. **D-11 (0)** Sync
now dims and returns on every run. **D-12 (not verified)** the pressed
ripple did not show in the layer capture → device. Device-only for the
qa-runner: TalkBack order and phrasing on the page and in the picker (DR9),
what is spoken during a run, a bind and a stop (D-2), the ripple (D-12),
the settled snackbar (D-9), Android's non-linear 2.0 in de/ro on the 360
AVD, the restart prompt after a real download and the insets under the
picker's last row, a sign-out with the page open (D-6).

**Fix pass as built — the data and service streams (2026-11-07; three
implementers in detached worktrees at once, one reviewer each, the
reviews' follow-ups built before the merge; gate: `dart analyze lib test`
clean, `flutter gen-l10n` with `untranslated.txt` `{}`, whole suite
13,767 passed, 12 skipped, none failed; commits `d2b3da32` B, `67eaca7f`
A1, `9498843b` A2).**
*B (`d2b3da32`):* **W-3** the rules header names the one deploy command.
**W-5** `test/firestore/rules_test.dart` walks `syncTableBindings` — an
upsert under every synced table allowed, the same under `<table>_x` denied
(36 cases, 91 in the suite), and `rules_probe.ps1` gains a
`calendar_category_profiles` case (21 judged + 1 INFO; the Dart loop owns
the follows-the-list check). **W-7** `FolderDao.importFolders` keeps a
parent only while it is a restored copy or a live folder here, else the
folder restores at the root where its position appends (the notes twin of
`3561409c`; a tombstoned parent → root; the old pin of the dangling parent
in `sync_outbox_test` updated). **X-12** `FirebaseAuthService._guard` and
the sign-out catch log under `kDebugMode` only the mapped cause and the
exception's code, through `_logCause` (RB-1); the two `StateError`s became
`NoIdTokenException` and `QaAccountFormatException`, whose type names are
the diagnosis so no message is ever logged (RB-4); `_foldersParentsFirst`'s
comment follows W-7 (RB-2). Review RB-1…RB-8: RB-3's docs placed; RB-5 (no
test on the mapping), RB-6 (the deny loop repeats the `secrets` case) and
RB-8 accepted.
*A1 (`67eaca7f`):* **F-2** `HlcTimestamp.seed` = `000000000000:0000:seed`
and `CrdtWrite.seedStamp()`, never minted from the clock and never moving
it; `CalendarCategoryDao.seedMissing` reads the seeded ids first, inserts a
missing built-in under the seed stamp through `enqueueIn`, revives a
tombstoned one under a minted stamp as HEAD already did since `14c92505`
(no local path can tombstone a built-in: `_deletable` refuses, categories
have no `tombstoneAll`, the archive is `isHidden`), and writes nothing when
nothing is missing (one SELECT); the R76 wait during `bind_merge_pending`
stands. Pinned on `sync_pair.dart`: a fresh device whose first pull meets
an empty space never overwrites a renamed built-in with its seed; and
(RA1-1) `CrdtMerge`'s floor branch never yields to a remote seed, so a
rename below a raised floor survives a Stop and a rebind. The guard test
matches `seedStamp(` and allow-lists `HlcTimestamp.seed` to the DAO, the
write helper and the merge (RA1-3). Accepted: equal seed stamps leave
`createdAt`, `updatedAt` and `deviceId` unconverged (RA1-2, §3.4); the
`rebound` halt detaches the signal the queued run re-attaches (RA1-4); the
public `raiseFloor` parameter (RA1-6). **X-1** `unbind({raiseFloor =
true})` → the private `_unbind({raiseFloor, healedFrom})` in one
transaction; the heal unbinds with `raiseFloor: false`, so a copy's edits
since its original bind merge by last-writer-wins at its next bind, with
conflict copies for notes; Stop syncing and the restore still raise.
**X-2** `SyncDao.keyHealUnboundFrom`, written in the heal's transaction
with the holder's name, read as `SyncStatus.unboundAsCopyOf`, deleted by
`bind()` and by any plain `unbind()` (RA1-7); the page shows it in the
surface stream. **X-10** `SyncRunSkip.rebound` from both binding checks
(`SyncEngine._haltUnlessStillBound`); a cursor-only page meeting a rebind
halts without storing its cursor (pinned through
`FakeSyncGateway.onPullPage`). **X-13** `SyncBindFailure.spaceGone` when
`readSpace` returns null, `syncFailedSpaceGone` in three languages, the
page maps it. **X-14** `beforePage` clears `_pageStrings`. **W-4**
`syncSchema = DatabaseSchema.currentVersion`; `SyncEngine.schemaForTesting`
pins that the real singleton passes it.
*A2 (`9498843b`):* **X-3** `renameDatabase`: after the `.db` rename the
sidecar renames run in a `try`, and a `finally` moves the registry claim
(in its own try/catch, logged) and the active name, so both follow the
`.db` whether or not a sidecar throws, and nothing runs between the file
and its sidecars (RA2-1: left on the old name, the next launch would create
that name empty and the heal would unbind the renamed database); pinned
with a throwing registry and a throwing sidecar. **X-4** the marker
recovery switches back only when the active name is `marker.to`, `from`
exists and the registry holds no claim for `to` (RA2-3: a bind that
committed while both clears failed stays put); otherwise the marker is
dropped with a logged case; `clearDownloadInFlight` retries once and
treats Android's `false` like a throw (RA2-2). **X-6** `SettingsService._open`
loops while the generation moved, three attempts, then throws a
`StateError` rather than publish a stale service (RA2-4 accepted: the
three-move race is not on the launch path). **X-7** a failed
`DatabaseManager._create` clears the memoized future; `resetForTesting()`.
**X-8** `deleteAllData` sets `_switchUnannounced`;
`resetSwitchAnnouncementForTesting()` in the two suites that fail an open.
**X-11** two concurrent `getInstance()` calls on a held store resolve to
one built instance (`test/support/scripted_prefs_store.dart`, a scripted
`InMemorySharedPreferencesStore`; `shared_preferences_platform_interface`
now a dev dependency). Noted: a `setActiveDatabaseName` that throws inside
the `finally` replaces the sidecar's error — both fail the rename.

*C1 (`97e6896d`; one implementer, one reviewer over three rounds; gate:
analyze clean, whole suite 13,786 passed, 12 skipped, none failed):*
**U-1** the Account row's sign-in and sign-out are disabled while a step
is in flight; a `SignOutRequested` or sign-in that arrives mid-step is
deferred behind the step and runs once it settles (never dropped, never
mid-step); an account change from the auth stream mid-step does not end
the step, and a download's `SyncBindIdle(switchedToDatabase:)` is emitted
whatever the account state when it settles; the page's hold reads the
bloc's in-flight flag. **U-2** every emit goes through one `_put` that
remembers the status of the last account state shown; an account change
shows that status carried — binding, counts, times, last failure — with
only the pause recomputed (`SyncPause.forAccount`, now also the status
service's one source of the account pause); a failed or timed-out read
keeps the status on screen; the known status resets when a download
switches the database. **U-3, as it ended** (review RC1 → RC1b → RC1c): a
service call cannot be cancelled, and a page released mid-step would let a
fresh `SyncBloc` (`registerFactory`) overlap the running step and let a
Databases-page switch run under a bind still to land, which would bind the
database switched to — so **the page holds until the step settles**; what
is bounded is every engine wait (`SyncLimits.engineStop`, 15 s, on
resolve, stop and start — logged and carried on when it passes) and the
gateway's own 60 s per call; a step runs resolve → stop → change → start →
settle straight through, and finishes its side effects even if the bloc
closed meanwhile (the engine is never left stopped because a page was
left; only the settle's emit is skipped). The 2-minute give-up built in the
first two rounds, with `SyncBindFailure.timedOut` and its strings, was
removed again. **U-4** under `SyncFailure` with a known binding Stop is
enabled and Sync now disabled; the bloc's stop path accepts `SyncFailure`
(it first puts up the account `currentUser` reports, so the stop's progress
is visible). **U-5** `SyncState.stepInFlight` on the two account states,
cleared in the settle's emit or by a `finally` re-emit; the rows draw busy
from it when the shown flow is idle. **U-6** `sync_state.dart` re-exports
`SyncGatewayFailure`, `SyncSpaceInfo`, `SyncActivity`, `SyncPause` and
`SyncStatus`; the page, the sheet and `sync_event.dart` import no service
file. Also: `_accountChangesPending` refuses a step between a settle and a
deferred sign-in/out's own emit (RC1-5); a hung Google sign-out is bounded
by `engineStop` and shows the account the identity still reports (RC1b-4;
the user is told in C2, RC1c-2); a thrown sign-out releases the counter
(pinned, RC1c-1). Accepted: a download's page removed by something other
than back skips the settle, so its restart prompt would not come (RC1b-6,
very unlikely under the hold).

*C2 (`edec7d5d`; one implementer, one reviewer over two rounds; gate:
analyze clean, gen-l10n `{}`, whole suite 13,829 passed, 12 skipped, none
failed):* **F-1** every Merge of a data-holding database asks first
(`AppDialogs.confirm`, id `sync-picker-merge-confirm`): "Merge into
“<space>”? — Rows this database and the cloud both hold take the cloud's
version. Rows only here are uploaded." (lettered A: a confirm rather than
a caption, since DR5 removed captions; the plain confirm style as the Stop
confirm's); an empty database binds at once; a cancel leaves the picker as
it was. **F-4** `syncFailedPermission` says "…or that sync is set up in the
cloud". **X-2** the unbound row reads `syncUnboundAsCopyOf(name)` while the
heal's note stands, signed in only (lettered B; a failure wins). **U-8**
the hub's Sharing row searches by `syncKeywords`. **U-9** the German
restart prompt in the du-form (the Databases page's older strings stay
Sie — RC2-11, §8). **D-2** the spinner is `ExcludeSemantics` and the busy
row carries `Semantics(value: syncBusyLabel)`, so TalkBack reads the name
first (RC2-5); `SemanticsService` announces politely when a step ends —
"Syncing with “<space>”" or, when the page knows no name,
`syncAnnounceBoundUnnamed` (lettered C), "Stopped syncing" — and when a
bound status's pause changes to a non-none value, never for the ticking
run line, never for a pause present when the page opens (the first
engine-overlaid status seeds the baseline, RC2-4), once even when the
settle's read failed (`_awaitedBinding`, RC2-3); a bind or stop failure is
not announced because its snackbar is already a live region (lettered D,
pinned). **D-3** the kit's `settings_kit_guidelines_test.dart` runs its
three guidelines over five Sync states, three picker states and the Merge
confirm in both cells; its contrast leg skips nodes whose every merged
flag is disabled (lettered F — WCAG 1.4.3's exemption; a stock skip one
level down), and the Sync section pins its disabled reasons' and its
enabled descriptions' colour tokens itself (RC2-1: Flutter's matcher never
judges a merged two-line row — §8). **RC1c-2** a timed-out sign-out takes
the thrown sign-out's failure path; `SyncSigningIn` goes up before the
wait on a landing sign-out, so Retry cannot start a second Google flow
(RC2b-1, pinned at exactly one call), a sign-in waits on every landing
sign-out (RC2b-2), and a sign-in while one is up is ignored.

*C3 (`a69a65d0`; one implementer over five batches, one code reviewer over
three rounds, the design reviewer over four measuring rounds; gate: analyze
clean, gen-l10n `{}`, whole suite 13,868 passed, 12 skipped, none failed —
two alarm-page cases had cast the dialog's title to `Text` and now read the
first `Text` beneath it):* **D-1 → D3-1** the status row's line and details
share one slot and one line budget (`_StatusLines`: the tallest status-line
template's lines + 1; the details get what the current line leaves,
ellipsized only past that), the details on one line "last sync · n held
back · n waiting" (the waiting count left out when the status line already
gives it; RC3b-3 puts the held-back count, said nowhere else, before the
waiting one), counts grouped by `NumberFormat.decimalPattern` (D2-7), the
glyph on the status line (`titleAlignment: top`, also on Sync now and Stop,
D2-8); the de/ro "another account" pause strings shortened so one five-line
pause no longer sets every state's height (D3-4). Measured by the design
reviewer across en/de/ro × 1.0/1.3/2.0 × 360/412: one height per bound
state in every cell, 82 dp at 1.0 (was 118), 220 dp at 2.0/360 (was 404),
the time never cut, Sync now and Stop at one y; DR10's "one count per
detail line" is superseded by the budgeted line; DR11 (tall rows at 2.0, the
en "Up to date" keeps 132 dp blank at 2.0/360 because the row is sized for a
four-line pause) stays the owner's call. **D-4** the Stop row carries no
failure line — one height, the failure in the snackbar and, after it, as the
row's semantics value (RC3-7) — and its label is "Stop syncing" (D2-10).
**D-5** the unbound row's description slot is sized from its three fixed
texts (`_FixedLinesSlot`, a `TextPainter` in the drawn style and width); a
failure's reason or the heal note takes the slot ellipsized with the whole
text in the semantics label; one height across its states (the heal note
shortened, RC3-2/D3-5; a long database name still cuts its last word,
D2-4/D4-4, §8). **D-7** the picker's "Sync with" rows take `FormCheckRow`'s
two-line shape through `FormPickerRow.checkRowShape`, both rows drawing one
private `_CheckRowLines` (RC3-8). **D-6** deferred (§8). **The sign-out
wording:** `SyncFailure` carries `action` (sign-in / sign-out) and, for a
sign-out, the `user`; the page says `authSignOutFailed` ("Sign-out failed";
de "Nicht abgemeldet", ro "Nu s-a deconectat" — short enough to keep the
row's height, D4-1) with the account's name, email or uid beneath, the
snackbar `authSignOutFailedRetry`, the row acting as Sign out again (id
`sharing-sign-out`); the section reads that failure as signed in (RC3-4,
D2-2: the bind row enabled, Sync now per the carried status), the bloc puts
the account up before a repeat sign-out, a bind or Sync now from it (RC3-1,
RC3b-1), so no outcome is swallowed as an equal state. **Dialogs (D2-1,
D3-3, D4-2, RC3c-2 — every `AppDialogs` builder):** the body scrolls, the
title is clamped at `FormMetrics.dialogTitleMaxTextScale` (1.2) at weight
500, the actions at `dialogActionMaxTextScale` (1.6), so de/ro 2.0 no
longer clip the body or break a word. Accepted: a past-year date with two
counts still cuts the count word at 2.0 when the status line takes three
lines (D4-3; the semantics whole); the dialog title at 2.0 is close to the
body's size (D4-2's weight is the remedy).

**Device pass after the fix pass (2026-11-07, `a69a65d0`, two
`qa-runner`s).** The four saved suites green on a normal QA build on
`anta_qa_1`: browser 3/3, settings 20/20 (`09_hub_sharing`, the Sharing
flow, 10 s), calendar 35/35, alerts 5/5. The two-device sync pass green on
the emulator suite with the cloud-define build (`qa build --define …` then
`qa fleet install`): A (the `basic.json` seed) bound and read "Receiving
changes / Not synced yet · 22 waiting" then "Up to date / Last synced 4:38
AM" within about 8 s; B (empty) bound in one tap with no picker and showed
A's three root folders; B's Stop ("Stop syncing this database?" →
"Stop syncing") returned the unbound row, the next tap opened the picker,
Merge opened the new confirm ("Merge into “qa”?" → "Merge") and the rebind
read "Up to date" after a short "Receiving changes"; a line typed on B
reached A's browser preview within the wait and a folder deleted on A left
B. Noted: a persisted Firebase session survives a reinstall and `relaunch
--fresh` and, against a restarted Auth emulator, shows the account row with
a bare uid and behaves offline until a sign-out and a sign-in (the S6 note's
family; the device reading is in §8); a note open in A's editor did not show
B's text within a 30 s wait while B stayed in its own editor — the drain
runs 30 s after the last outbox write, so that wait was marginal; the §3.9
in-place reload is pinned by the editor's widget tests and is step 6 of the
owner's checklist.

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

**Review 2026-10-26** (`docs/cloud-sync-phase-02-review-2026-10-26.md`,
REVIEWED and FIXED 2026-10-28). Nine review sessions read S1–S5 whole after
the fact and filed R1–R106; three fix passes built every H, M and
co-located L in `27eb38a` (the editor, the counters, the app around the
engine), `8c14215` (the engine, the wire, the merge, the hooks) and
`b7c87ea` (the gateway, the rules, the seam, the tooling), each pass
reviewed in turn for R107–R156 — 156 ids, 11 H, 36 M, 109 L; the whole
suite and the three saved device suites are green on `b7c87ea`. **The two
carry-over lists are built.** S4b-1b: M1 = R3, M2 = R2, L4 = R5, L5 = R7,
L6 = R8, L7 = R9, L8 = R10, L10 = R13, L11 = R12 and L12 = R11 in
`27eb38a`, M3 = R6 in `8c14215` — L7 closed as documentation rather than
code (the undo reset on a title-dirty merge and the silent title LWW both
stand, review R118) and L8's trade recorded for the owner (a held write's
first retry is now the 5 s debounce, R121). S5b: M1 = R37, M2 = R89, M3 =
R93, L4 = R87 and L10 = R94 in `b7c87ea`, L6 = R88 in `8c14215`; L9 is
answered rather than built — `maxBatch` 499 is safe, the live limit being
500 field transformations per document (review A4). What the review
changed in this record is marked `(A<n> review R<id>)` in place (§3.3,
§3.4, §3.5, §3.9); what it deferred — R98's far-future stamp, R130's
second half, R148, R96 with the rules deploy, R67's counter share behind
v44, R17/R43/R83 under D4 A, R39 to S4b-2 — is the review's §6. S4b-2 and
S6 follow it unchanged.

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
4. The backup: the export of 2026-10-24 is the fallback for the phone's
   v42→v45 migration and the first bind; the checklist below asks for a
   fresh one first — it is the only recovery if the two binds run in the
   wrong order (final review F-1).
5. The real check after S6: install the build on the phone, Sharing →
   "Sync this database"; on the Pixel 9 Pro emulator sign in with the same
   Google account (the owner types the credentials), Sharing → "Sync this
   database" → the picker → merge; then edit on each and watch the other —
   in the order and with the readings of the checklist below.
6. Only on D7 B: a free Cloudflare account and one `wrangler login`.
7. Commits are the lead's for this phase (owner's word 2026-10-24): one per
   slice after its gate, short subject, no ledger.

**The pre-bind checklist (final review 2026-11-06, F). The order of steps
3–5 is the one load-bearing instruction: a never-bound database yields
every row it shares with the space, and a second device whose first pull
meets an empty space loses even that protection (§4 F-1, F-2).**

0. A fresh export of the phone (Settings → Backup); keep
   `C:\Users\mobx3\Downloads\gym_notes_anta.db` too.
1. **Already done — verified 2026-11-07 through the Firebase Rules API:
   the `cloud.firestore` release of 2026-11-05 carries
   `match /users/{owner}/spaces/{spaceId}` and `calendar_category_profiles`
   (the `2661c8de` text; HEAD differs only in the header comment), and
   `firebase firestore:indexes` lists all 18 `data` exemptions. Skip this
   step unless step 3 reads "The cloud refused this".** The command, kept
   for that case: deploy, from `frontend/anta`: add `"firestore": {"rules":
   "firestore.rules", "indexes": "firestore.indexes.json"}` beside the
   `flutter` block of the gitignored `firebase.json` (there is no
   `.firebaserc`, so `--project` stays), then
   `firebase deploy --only firestore:rules,firestore:indexes --project alexs-note-tracking-app`.
   If the CLI offers to delete indexes or field overrides that exist live
   but not in the file, answer No unless sure (the `pairs` composite index
   is in the file, so it should not be offered). Verify in the console:
   Rules shows `match /users/{owner}/spaces/{spaceId}`; Indexes → Single
   field lists the `data` exemptions (cost only, not correctness).
2. Install the build on the phone and open it. The first open migrates
   v42→v45 (rehearsed on the export: 64 ms, every count kept). Check the
   data before anything else — 2 folders ("2026" with 7 notes, "General"
   with 4), 22 categories with the five hidden ones still hidden, 2
   counters, the calendar. Anything off: stop here; nothing has reached
   the cloud.
3. Sign in (Settings → Sync & sharing → Account), then "Sync this
   database". Expected: no picker; the row becomes the status row —
   "Waiting for the first sync" → "Sending n changes" → "Up to date" with
   a time, no parked count, no failure line. "The cloud refused this —
   check you're signed in to the right account" means the rules are not
   deployed (F-4): redo step 1 and tap again. "You're offline": connect
   and tap again. A picker means an earlier tap already created the space:
   choose "Merge this database into "ANTA"" (not Upload — F-7) and confirm
   "Merge" in the dialog that names the rule (the fix pass's F-1: the
   space is empty, so nothing yields). Verify in
   the console: `users/<uid>/spaces/<id>` with `name: ANTA`, `schema: 45`,
   a `touched` map, and the subcollections `notes` (39 = 11 live + 28
   tombstones), `calendar_events` (76), `calendar_categories` (22),
   `folders` (3), `counters` (2), `counter_values` (2), `vocabularies` (3),
   `vocabulary_items` (47), `calendar_event_occurrences` (5),
   `calendar_event_absences` (91), `calendar_event_alerts` (14),
   `calendar_event_templates` (1), `calendar_filter_presets` (6),
   `overview_views` (1) — 312 documents. "Sync now" once more: still "Up to
   date".
4. Do not touch the emulator until step 3 reads "Up to date" and the
   console shows those subcollections. If the phone's upload fails, fix it
   on the phone first.
5. The Pixel 9 Pro: cold boot (`-no-snapshot-load`) and let the clock
   settle (F-10); install the same build; if its database holds anything
   you do not want in the space, clear it first so it binds in one tap
   (F-8); sign in with the same Google account (F-9); "Sync this
   database". Expected with an empty database: binds at once (or one "Sync
   with "ANTA"" row) → "Downloading n so far" → "Up to date". If the picker
   appears because the emulator holds data: prefer "Download "ANTA" into a
   new database" (the Databases page's restart prompt; restart; the active
   database is "ANTA"); choose Merge only to upload that data too, knowing
   every row both hold takes the cloud's version, edits made on that copy
   since it was taken included (F-1 — the confirm dialog says so; it asks
   only when the database holds data). Verify the same folders, notes,
   categories (hidden ones hidden), counters and events; the alert
   definitions arrive and ring on the emulator too (readiness D11).
6. Edit on each and watch the other: about 30 s while the writer stays in
   the note (the drain runs 30 s after the last write), sooner once the
   writer leaves it; a note open on the reader reloads in place when the
   change lands (§3.9); a note open on both before a sync gives one
   conflict copy on both (D3);
   counters are last-writer-wins, not a sum (F-6); a folder deleted on one
   while a note in it is edited on the other re-files the note under the
   nearest live folder (the P fix pass).
7. If the space ends up wrong, never restore a JSON backup over the bound
   database (F-3): "Stop syncing" (the Sync section's last row) on every
   device, confirmed in its dialog (the cloud copy stays until Phase 04);
   on the phone import the fresh `.db` export
   as a new database (Settings → Databases), make it active, "Sync this
   database" → the picker → "Upload this database as a new space"; on the
   emulator "Sync this database" → the picker → Download the new space into
   a new database — never Merge the old database into the new space, its
   newer tombstones would delete the restored notes again. The old space
   stays listed in pickers.

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
- The readiness §8 items left as found (two HLCs per event-editor save, the
  held far-future remote, `restartable()`).
- From the S2a review, accepted: a tap between the counters flush and the
  reload of one pulled page shows the pre-merge number for a few
  milliseconds — the tap itself is **not** lost, on either the global or
  the per-note path, because the delta path re-applies it over the merged
  row (review 2026-10-26, R34, probe-confirmed and pinned by
  `test/services/counter_service_test.dart:200-287`); the one real loss in
  that window is `resetGlobal`'s memory guard (R24, fixed in A6);
  concurrent creates give one folder two notes of the same title (the
  per-folder uniqueness backstop does not run on merge; ids differ) **and
  the two rows the same `position`**, which travels verbatim — since the
  pre-bind slice P every folder sort ends on `id` as the note sorts did, so
  both devices list the tie in one order and renumber it alike on a drag
  (review 2026-10-26, R71) — and one vocabulary two items for the same term
  (`saveItems` tombstones one later; the suggestion bar offers the term
  once either way since review 2026-10-26 R35 deduped `updateCache` on the
  folded term, so the pair is invisible until the next save collapses it);
  `requeueRow` on a composite key scans its table.
- The calendar deliberately exports every live day row, orphans included: a
  half-resurrected event (review 2026-10-26, R77) makes them meaningful
  again, and the import normalises what stays orphaned (review R83).
- A pull envelope that parks (a malformed document) is skipped at that
  cursor for good and `parkedCount` resets at the next launch, so the
  device silently lacks that one row until the row is pushed again — the
  persistent park list above would make it visible and retryable.
- A row created after the bind keeps `owner_id` NULL locally (NULL means
  "mine", readiness D12) while the device that merges it stores the uid;
  harmless in Phase 02, and Phase 03 — which needs foreign rows told apart
  — decides whether local writes on a bound database stamp the uid.
- From the final review (2026-11-06), accepted or deferred: **F-3** a JSON
  restore on a bound device is not a rollback of the cloud — the restore
  unbinds, appends note and folder copies under fresh ids, re-inserts the
  calendar under the archive's ids and writes the floor after, so a Merge
  of that database back into its space yields the calendar to the space
  and pushes the copies beside the originals everywhere; the §7
  checklist's fallback (a `.db` import as a new database + Upload as a new
  space; Download on the other device) is the procedure, and the confirm
  on Merge (F-1) names the rule. **W-1** the v45 skip sweep's pull side — a
  v44 device still bound to a space at schema 44 can push a live skip on an
  event that later becomes a one-off, and a fresh v45 install downloads it
  unswept; `schema >= stored` and `appOutdated` close it after the first
  v45 push; both of the owner's devices run v45. **W-2** backup v8 shipped
  with v44 and v45 kept it, so a v8 archive written by a v44 build carries
  converted-series leftover skips a v45 restore keeps — a dev-only window
  (no v44 build reached a device); a v9 bump would be the fix. **X-5** the
  install registry's claim follows the active database name, not the
  opened database's; a bind or unbind between a Databases-page switch and
  the restart would write the claim under the other name — low while the
  restart prompt cannot be dismissed and the bloc stops the engine first.
  **X-15** `FolderDao.updateFolderPosition` has no caller in `lib`; its
  tombstone guard stands. **U-7** no saved QA flow drives the Sync section
  or the picker (the device pass runs S6's explicit verbs); a two-device
  suite needs a harness that alternates devices. **U-10**
  `syncThisDatabaseUnavailable` is also what a failed Firebase init shows,
  reading permanent for a transient fault. From the fix pass's reviews:
  **RC2-1** Flutter's `textContrastGuideline` (and the kit's
  `_KitContrastGuideline` over it, `test/widgets/settings_kit_guidelines_test.dart`)
  looks a node's text up by its merged label, and a two-line row's label
  is "title\ndescription", which no single `Text` matches — so no
  description of any kit row is ever judged for contrast; the Sync
  section pins its descriptions' colour tokens instead, and the kit-wide
  fix (evaluate each `Text` under a node) is the settings area's call.
  **RC2-11** the Databases page's older German strings are in the
  Sie-form while the Sync section's and the restart prompt's are du — an
  l10n register pass. **RC2-6** the bind failure's snackbar is keyed on
  the flow, so a failed stop whose binding then drops changes the row's
  wording without a snackbar. **X-5**, **RC1b-6** stand as recorded above.
  From the design re-review after C3: **D-6 / D2-9 / RC3-3** the Account
  row moves the bound rows below it when its content changes (a sign-out
  at ro 2.0/412: 40 dp; a sign-out failure: 4 dp at en 1.0) — it is a
  `SettingsYieldingTile` signed in and a `ListTile` otherwise, its title is
  the user's name and the yielding value's place is measured, so a
  template slot needs a new parameter on that primitive. **D2-6** the
  picker's Merge and Download action rows sit on `FormActionRow`'s
  minimum-height rule (6 dp above and below the label against the check
  rows' 11) — the UI-language area's rule. **D2-4** the heal note is cut by
  the unbound row's slot when the database name is long (the semantics
  label carries it whole; the string was shortened). **DR9 / D2-11** the
  picker rows have no button role (`FormPickerRow`). **D2-12** the test
  font renders the snackbar and the uid as boxes (no `fontFamily`) — an
  artefact. From the device pass after the fix pass: a Firebase session the
  backend no longer knows (the QA Auth emulator restarted; on a device a
  revoked session) keeps the account row up with a bare uid and reads as
  "offline" — the token refresh fails as a network error — instead of as
  signed out, until the user signs out and in; a "session expired" reading
  would need the auth error told apart from a network one in
  `FirebaseAuthService`.

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

---

## 12. The drawer's account row (2026-11-07)

**Status: BUILT AND REVIEWED 2026-11-07 — the mock accepted ("okay, this
looks good"; the recommended direction, not a dedicated page); one
`implementer` in three rounds, `reviewer` and `design-reviewer` in
parallel with every finding fixed or recorded ("As built" at the end of
this section), the whole suite green (13,917), the device pass in the same
ledger; uncommitted until the owner's word.** After the sync status question the
owner asked for "somewhere to see what is happening, what last sync was"
and then for a mock of the left drawer. The lead's reading, accepted: no
new drawer entry (the drawer lists places — settings rework D3, the
rejected drawer-as-navigator of 2026-09-03), no account page yet (§12 (p)):
the header's hidden avatar badge becomes the drawer's **first list row** —
avatar, account name, one status line — opening Sync & sharing exactly as
the badge does. Mock: https://claude.ai/artifact/3nhPAHTWWTGGb9tMYVJTYi
(`designer` agent, 2026-11-07, a real-font render of the drawer in both
schemes at 1.0 / 1.3 / 2.0, en and de; the renders and `measures.txt` were
in that session's scratchpad only).

**What the render found in today's badge (`app_drawer.dart:364-400`).**
A 29 × 29 dp unlabelled target: `labeledTapTargetGuideline` and
`androidTapTargetGuideline` both fail signed in (the drawer test runs on
`NoOpAuthService`, so it never sees it); its hit box (62,60)–(91,89)
overlaps the icon's five-tap unlock node (20,24)–(81,85); it carries no
status; a 22 dp disc on a 61 dp tile sits on no step of the ramp — which
answers the comment that chose the badge over "a second row at a
mismatched scale": the row *is* a drawer row, same tile, same metrics.
`UserAvatar`'s defaults (a `primaryContainer` disc, 1.17:1 on the drawer's
`surfaceContainerLow`, a 12 px glyph) read as a pale hole beside 24 dp
glyphs. The Sync page's own lines do not fit the drawer's 196 dp text
column (the drawer is 304 dp wide on a 360 phone): four of the five pause
lines cut at 1.0 en, most lines at 1.3 de.

**Decisions — the designer's defaults, accepted by the owner 2026-11-07;
each reversible.** (a) the row appears only when signed in; signed out the
drawer is today's (alternative: always present, "Not signed in"). (b) The
badge is retired — one identity mark. (c) The row is the first child of the
drawer's `ListView`, above the CALENDAR label, with no label of its own;
`RowMetrics.groupGap` separates it (alternative: drawn on the header). (d)
One status line, not line + details (80 dp). (e) Text only; `error` colour
for the three pauses that need the user; no cloud glyph. (f) "Not syncing".
(g) "Last synced 3:09 PM" reuses the page's words (alternative "Up to date
· 3:09 PM", a new key). (h) Four short drawer pause strings rather than the
page's lines cut off. (i) The pending count only; the sending and held-back
counts stay on the page. (j) 1 / 2 / 3 status lines below text scale 1.3 /
from 1.3 / from 1.8, never one line cut off. (k) A blank reserved line
before the first status lands, not a placeholder. (l) The avatar fallback
is an `onSurfaceVariant` disc with a `surfaceContainerLow` person. (m) No
TalkBack hint. (n) The page's `_lastSyncOf` moves to one shared
`SyncStatus.lastSyncAt` getter. (o) No live region. (p) **No dedicated
account page now** — the account stays the first section of Sync & sharing
(the auth service has only sign in and sign out); the page earns its place
with Phase 04 (delete the cloud copy, manage spaces) and Phase 03 (grants,
consent), when Account (identity, switch, sign out, disconnect, delete
cloud data, spaces) splits from Sync (per database).

**Spec.**

- *Presence and data.* The row exists while `AuthService.authStateChanges`
  (`initialData: currentUser`, as the badge reads it) gives a user. Title =
  `displayName ?? email ?? l10n.accountSection` (the page's precedent,
  `sync_settings_page.dart:270`). Status from a `SyncBloc` created for the
  row's subtree — `BlocProvider(create: (_) => getIt<SyncBloc>()..add(const
  LoadSyncStatus()))`, guarded by `getIt.isRegistered<SyncBloc>()` (the
  `PermissionService` pattern at `app_drawer.dart:424`); it closes with the
  drawer; settings pages have no drawer, so two never run at once. The row
  reads `SyncSignedIn.status`; every other bloc state leaves the line blank
  with its slot reserved. `LoadSyncStatus` stays a read (the reviewer
  confirmed it: `FakeSyncEngine.calls` empty). A read that times out
  (`SyncBloc.statusTimeout`, 3 s) or fails leaves the slot blank for that
  drawer open rather than showing the placeholder status: the bloc's
  `SyncSignedIn.statusRead` (see "As built") flips only on a real read, a
  refresh or an engine status.
- *Words per state* (a pure function with its own test; the order mirrors
  the page's `_statusLine`): 1 `binding == null` (and `unboundAsCopyOf`) →
  "Not syncing", NEW `drawerAccountNotSyncing` (de "Wird nicht
  synchronisiert", ro "Nu se sincronizează"); 2 `pause == quotaExhausted` →
  "Paused — daily limit reached", NEW `drawerSyncPausedQuota` (de "Pausiert –
  Tageslimit erreicht", ro "În pauză — limita zilnică atinsă"); 3 `pause ==
  signedOut` → `syncPausedSignedOut`; 4 `accountMismatch` → "Paused —
  another account", NEW `drawerSyncPausedOtherAccount` (de "Pausiert –
  anderes Konto", ro "În pauză — alt cont"), `error`; 5 `appOutdated` →
  "Paused — update ANTA", NEW `drawerSyncPausedAppOutdated` (de "Pausiert –
  ANTA aktualisieren", ro "În pauză — actualizează ANTA"), `error`; 6
  `noAccess` → "Paused — no access", NEW `drawerSyncPausedNoAccess` (de
  "Pausiert – kein Zugriff", ro "În pauză — fără acces"), `error`; 7
  `activity == pushing` → `syncSending(0)` ("Sending changes"); 8 `pulling`
  → `syncReceiving`; 9 `lastFailure` offline → `syncOffline`, other →
  "Couldn't sync — will retry", NEW `drawerSyncRetrying` (de "Fehler – neuer
  Versuch", ro "Eșuat — se reîncearcă"; the page's German retry line cut at
  every scale, the fix pass); 10 `pendingCount > 0` → `syncPendingCount(n)`; 11
  `lastPullAt == null` → `syncNeverSynced`; 12 otherwise →
  `syncLastSynced(formatSyncMoment(context, status.lastSyncAt))`. All
  non-`error` lines in `onSurfaceVariant`. Six NEW keys in all three
  ARBs, `flutter gen-l10n`, `untranslated.txt` empty.
- *Elements.* The badge, the header's `Stack` and `Positioned` go; the
  icon's `Semantics` and `GestureDetector` stay byte-for-byte; the comment
  at `:256-258` says the account is the list's first row. The tile is
  `_buildMenuTile`'s geometry (`FormMetrics.settingsRowPadding`,
  `settingsRowVerticalPadding`, `RowMetrics.singleLineMinHeight`,
  `FormMetrics.settingsLeadingWidth`, `settingsTitleGap`, trailing
  `chevron_right_rounded` in `onSurfaceVariant`) — give `_buildMenuTile` a
  `Widget leading` and a `Widget? subtitleWidget` rather than a copy.
  Leading: `ExcludeSemantics(UserAvatar(user, radius:
  RowMetrics.drawerAvatarRadius, backgroundColor: onSurfaceVariant,
  foregroundColor: surfaceContainerLow))`, NEW `drawerAvatarRadius =
  drawerGlyphSize / 2` (12 → a 24 dp avatar filling the glyph slot; a photo
  fills the disc). Title: `RowMetrics.titleFontSize` 15 /
  `FormMetrics.labelLineHeight`, w400, `onSurface`, `maxLines: 1`,
  ellipsis. Status: `secondLineFontSize` 13 / `captionLineHeight`, w400,
  colour per state, inside `FormCaptionSlot(candidates: [Text(n lines of
  spaces, maxLines: n)], child: Text(line, maxLines: n, ellipsis))`
  (`form_rows.dart:3465`, an existing primitive — nothing new); before the
  first status the child is `SizedBox.shrink()`, never `Text('')` (1 dp
  taller at 1.3). Lines n: `factor =
  MediaQuery.textScalerOf(context).scale(13) / 13`; n = 1 below NEW
  `RowMetrics.drawerStatusTwoLineTextScale` (1.1), 2 below NEW
  `drawerStatusThreeLineTextScale` (1.7), else 3. Android's non-linear
  scaling at 13 sp is about 1.16 at the 115 % step, 1.54 at 150 %, 1.77 at
  180 % and 1.92 at 200 %; with the designer's 1.3 / 1.8 the design review
  found one line cutting most German lines at 115 % and two lines cutting
  "Zuletzt synchronisiert 15:09" at 180 %, so the thresholds sit under
  those steps. Tap: `_go(context,
  AppNavigator.toSyncSettings)` (`app_drawer.dart:77`: pop, then push, no
  await). Semantics: `Semantics(identifier: SemanticsIds.drawerAccount)`
  around the tile, NEW `drawerAccount = 'drawer-account'` beside
  `drawerCalendar`; the merged node reads the name then the status, button
  role, tap action; the template excluded by `FormCaptionSlot`.
- *Measured (the designer's render; ±1 dp).* Row height 62 / 96 / 172 dp
  at 1.0 / 1.3 / 2.0 in en and de, equal to the Calendar row's there only
  because its subtitle happens to wrap the same way (the design review: ro
  1.0 62 vs 80, 1.15 68 vs 89, de 1.8 156 vs 124 — cosmetic, not a rule) —
  identical across every state at every scale; the avatar 24 × 24 at every scale. Contrast on
  `surfaceContainerLow`, light / dark: `onSurfaceVariant` 8.47 / 10.02,
  `error` 5.93 / 10.00, `onSurface` 15.48 / 13.17. de at 1.0 cuts "Zuletzt
  synchronisiert 05.11.2025" (a previous year) and the retrying line's
  tail; at 1.3 nothing; at 2.0 the retrying tail only. ro not rendered —
  checked at implementation.

**Must not change.** The header's gradient, height, tile, five taps and
swipe, `drawerHeaderIcon` with label `appTitle` and the button role; the
nine places, their order, ids, glyphs, styles and group headings; the
Settings row's permissions line; `drawerList`; the About dialog; pop then
push; signed out the drawer is byte-for-byte today's; the Sync & sharing
page is untouched except for the shared `lastSyncAt` getter; every pin in
`test/widgets/app_drawer_test.dart` and
`test/widgets/settings_navigation_contract_test.dart` holds; the QA flows
`tool/qa/flows/settings/00_drawer.txt` and `01_drawer_places.txt` keep
passing (`test/qa/flows_lint_test.dart` needs the id first).

**Risks.** The drawer grows 62 dp at 1.0 (About ends 69 dp below a 780 dp
screen, was 7; the list scrolls). A `SyncBloc` per drawer open. German's
retrying line ellipsizes. The QA fixture has no signed-in account: a device
look needs the Firebase emulator path (`QaMode.firebaseEmulatorHost`).

**Design-reviewer matrix after the build.** Signed out: no
`drawer-account`, the nine rows at today's rects (Calendar 149–211 at
1.0). Signed in: every state, light and dark, 1.0 / 1.3 / 2.0, en and de —
the row's height equals the Calendar row's (62 / 96 / 172 ±1) and is
identical across states; the row sits above `drawerCalendar` at the list's
top; the avatar is 24 × 24; the header holds no `UserAvatar`; both
tap-target guidelines pass; tapping `drawer-account` closes the drawer and
lands on Sync & sharing, back lands on the host with the drawer closed; a
status change with the drawer open leaves the rect unchanged. Device: a
`qa screenshot` signed in at Android 200 % and in dark.

**As built (2026-11-07; uncommitted until the owner's word).** One
`implementer` (Opus 5.5) in three rounds, each gated on the focused suites,
the whole suite from the lead after the last: 13,917 passed, 12 skipped,
0 failed; `dart analyze lib` clean; `untranslated.txt` empty. *Round 1:*
the row as specified; `_buildMenuTile` gained `leading`, `subtitleWidget`
and `titleMaxLines`; `lib/widgets/drawer_sync_status.dart` holds the words
per state as a pure function returning `({text, isError})` (13 unit tests);
`SyncStatus.lastSyncAt`; `RowMetrics.drawerAvatarRadius` and the two
thresholds; `SemanticsIds.drawerAccount`; the keys; seven drawer cases; the
Account row in the navigation contract; `00_drawer.txt` pins `--absent
id:drawer-account`. *Round 2 (the implementer's own finding):*
`SyncSignedIn.statusRead` — `_onLoad` emitted the signed-in state with
`SyncStatus.empty` before the read landed, so a bound database read "Not
syncing" for up to 3 s; the flag is stamped in `_put` for the bloc's life,
set by a real read, a refresh or an engine status and never by a timeout or
a failure, and sits in `props` so an equal unbound status still flips
unread → read (20 bloc expectations updated, four cases gain one state; a
mutation run without the drawer's guard went red). *Code review
(`reviewer`, its own snapshot, mutation runs on every stamp):* nothing
loses data or crashes; (1) a timed-out read leaves the slot blank for that
drawer open — kept, the wording above corrected; (2) signed out, the
`SizedBox.shrink()` child counted in `drawer-list`'s `scrollChildCount`
(13 against HEAD's 12, TalkBack's "x of n" off by one) — fixed; (3) the
`BlocProvider` inside the list child was closed and rebuilt by a drag past
About at 2.0 — fixed with (2): `_buildAccountScope` lifts the
`StreamBuilder` and the lazy `BlocProvider` above the `ListView`, the row
an `if (user != null)` child, so signed out the children are HEAD's; (4)
one frame of the old status under a new name on an account change with the
drawer open — kept (the Sync page has no drawer); (5) the drawer imported
the picker sheet for `formatSyncMoment` — moved to
`lib/utils/sync_moment_format.dart`, the picker and the page follow; (6)
every drawer open resolves `SyncEngine.getInstance`, which only retries a
failed launch build — existing behaviour, kept; (7) four files were LF in
the working copy — CRLF now; (8) an empty `displayName` shows an empty
title, the page's precedent — kept. The extra emissions of an equal status
with `statusRead` flipped fire no listener on the Sync page (traced: the
pause message needs a prior binding, the bind message a falling
`_wasStepping`). *Design review (`design-reviewer`, 48 real-font cases,
light/dark × en/de/ro × eight scales):* every matrix item passes; (1,
severity 2) at the 115 % step one line cut most German lines and "Paused —
daily limit reached" — the two-line threshold 1.3 → 1.1; (2, severity 2)
at the 180 % step (≈ 1.77 at 13 sp) two lines cut "Zuletzt synchronisiert
15:09" — the three-line threshold 1.8 → 1.7; (3) the Calendar-row equality
is a coincidence of en/de — the claim above corrected; (4) the German
previous-year date breaks between "5." and "Nov. 2025" at 1.3 — deferred
(a no-break space in the shared `formatSyncMoment`); (5) the header
subtitle "Einstellungen" measures 4.48:1 on the light gradient at 1.3–2.0 —
pre-existing, likely the sampler's anti-aliasing, deferred; (6) no `de` and
no `AppTheme` in the drawer suite — a 24-case boundary matrix added
(light/dark × de/ro × 1.0, 1.15, 1.3, 1.5, 1.77, 2.0: every status line's
`didExceedMaxLines` false, the row's rect one across fourteen states, the
header subtitle untouched); (7) the avatar's weight — taste, kept per (l);
(8) "Paused — signed out" under a signed-in name — transient, kept. The
German retry line still cut at 1.77 with three lines, so the drawer got its
own short line, `drawerSyncRetrying`; the matrix's allow-list is one entry,
de 1.0's previous-year date. Also pinned: signed out `scrollChildCount` 12
and `scrollIndex` 0; at 2.0 a drag to About and back keeps one `SyncBloc`
and the line drawn. *Deferred:* the date's no-break space; the header
subtitle's measured contrast; the account-change frame; the empty
`displayName`. *Device pass (2026-11-07, one `qa-runner` on `anta_qa_1` /
`emulator-5556`):* the settings suite 20/20 on the normal QA build
(`00_drawer`'s `--absent id:drawer-account` held; `19_fasting_settings`
went red once only because the runner's own cloud install killed the app
mid-flow, green alone); the cloud QA build (`ANTA_QA_CLOUD`,
`ANTA_QA_FIREBASE_EMULATOR=10.0.2.2`, `ANTA_QA_ACCOUNT`) against the
Firebase emulators, signed in as `qa1@example.com` and bound: the row
present in every shot with "Last synced 1:19 PM" / "Zuletzt synchronisiert
13:19" — light en at font scale 1.0 (one line, the avatar and the chevron
on the Calendar row's edges), 1.15, 1.8 and 2.0 (two lines, "PM" alone on
the second — the shared `formatSyncMoment`'s plain space, deferred with
the date's no-break space), dark en at 1.0 and 2.0, de at 1.0 (one line)
and 1.8 ("Zuletzt / synchronisiert / 13:19", whole words); the email title
ellipsizes from 1.8 (a real account shows its display name); About needs a
scroll at 2.0; the accessibility dump gives one button node labelled
"qa1@example.com\nLast synced 1:19 PM" with a click action. Note for the
next pass: a cloud QA build is signed in as the QA account from launch
(`FirebaseAuthService`, `QaMode.qaAccount`), so the row shows "Not
syncing" on it before any Google sign-in — that is a signed-in identity,
not a signed-out row.
