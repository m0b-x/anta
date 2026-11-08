# Scalability roadmap — design record (2026-11-07)

**Status: BUILT 2026-11-07 → 2026-11-08, all twenty slices merged into the
main tree and gated, UNCOMMITTED (298 files) — the whole suite 13,868 →
14,677 green; the four saved device suites green on `emulator-5556` (§8.3);
each slice's truth is its §8.2 note, the limits found during the build are
§11.1, the commit the owner makes is §8.4.** The owner delegated every
decision on 2026-11-07 ("you may decide and implement everything; focus is
quality, scalability; extra usage is not a problem"): D1–D14 stand at their
recommended options (§4), this Fable session led the build with one Opus 5.5
implementer and one reviewer per slice (§1), independent streams ran in
parallel worktrees where their files were disjoint and were merged into the
main tree by three-way patch, nothing is committed until the owner says so.
**The owner's steps before installing a build that holds S6:** the deploy
first (the space gains `content_chunks`): check that the gitignored
`firebase.json` still carries `"firestore": {"rules": "firestore.rules",
"indexes": "firestore.indexes.json"}` beside its `flutter` block
(`flutterfire configure` rewrites the file without it; found missing on
2026-11-08), then `firebase deploy --only "firestore:rules,firestore:indexes"
--project alexs-note-tracking-app`, the list quoted because PowerShell splits
it at the comma; then
install on BOTH phones the same day with the second phone's sync stopped or
offline until it runs the new build (§8.2 S6), then the two-device check by
the sync record's §7 checklist. Migrations as built: v46 (S4) → v47 (S16) →
v48 (S11) → v49 (S20) → v50 (S12) → v51 (§8.5, `sync_outbox.republish`); the wire version 45 → 46 in S6 only.
**First install 2026-11-08 (§8.5, §8.6):** the phone's first launch stalled
on spinners. §8.5 read it as the cutover's drain and whole-body re-read and
improved both the same day (body work off the database lock on both sides,
2 MiB parts, the `republish` flag so the re-queue files no spurious conflict
copy, "Finishing update" on the Sync page and in the drawer; committed in
`d9f34776`). The second install of the day stalled identically, and §8.6
found the stall itself: `onUpgradeStarting`'s `runApp` was the process's
first `scheduleFrame` and ran inside Drift's open-time zone, so every frame
of the session routed its reads to an executor the finished open had
retired. Fixed by binding the hook to the zone it is installed from;
UNCOMMITTED. Fable 5.1 wrote this on 2026-11-07 from the owner's
request "identify the app's limits
for the calendar and notes and make it scalable with the best practices apps
use; I heard a one-letter change resends the document". The audit ran as one
workflow the owner authorised for this session (515 Opus 5.5 agents: seven
readers over the subsystems, a merge step, three adversarial lenses per
finding, one designer and one critic per cluster, a completeness round):
186 raw findings, 62 confirmed, 28 plausible, 64 refuted. This record keeps
what survived, why the rest fell (§10), and the designs as the critics
amended them. Nothing in it is built. The implementing sessions run on Opus
5.5 (§1); this Fable session ends at the approved plan.

Contents: 1 How to run this · 2 Why — the limits found · 3 What the big
apps do · 4 Decisions for the owner (D1–D14) · 5 The design (5.1 foundations
· 5.2 the note body on the device · 5.3 the note body on the wire · 5.4 sync
correctness and runs · 5.5 search over bodies · 5.6 the calendar · 5.7
storage, lists, backup, import, counters) · 6 Behaviour — must not change,
deliberately changes · 7 Facts from the tree and the retire list · 8 Slices
· 9 Definition of done · 10 Checked and sound · 11 Deferred.

## 1. How to run this

- **Session model.** Each implementing session runs on **Opus 5.5 at
  high**, one slice per session as the normal pace (S6 takes two). The lead
  implements nothing over ~50 lines itself: it briefs one `implementer` per
  slice (the record section, the files from §7, the must-not-change list of
  §6, the pins the slice flips), runs the whole suite itself (never from an
  agent), then briefs one `reviewer` told to report by its 60th turn, then
  resumes the same implementer for the fix pass. `designer` → owner's yes →
  `design-reviewer` only for the two visual pieces (the Sync page's held-back
  row in S7, the upgrade screen in S16). `qa-runner` runs the saved browser,
  calendar and alerts passes once at the end of phases 4, 5 and 6; the sync
  phases (2 and 3) end with the owner's two-device check by the sync
  record's §7 checklist, the emulator seam first. `docs-writer` places the
  as-built notes into §8.2. No workflow, no `fable-max`, no second reviewer.
- **Skills per slice** (the table in §8.1 repeats them): `anta-context` +
  `drift-migrations` + `flutter-principles` for phases 0, 1 and 6;
  `markdown-engine` for S5; `calendar-events` (+ `calendar-ui`) for phase 5;
  `l10n` wherever copy changes; `ui-language` for S7, S16 and S19; `verify`
  for the gate; `qa-emulator` for the passes. The sync facts live in
  `docs/cloud-sync-phase-02-own-space.md` §3.4 (the merge), §3.5 (the
  engine, parks) and §11 (the Spark cost model) — read by section.
- **The gate per slice.** `dart analyze lib` clean, the whole suite green
  (one run at a time, nothing else running beside it), `flutter gen-l10n`
  with an empty `untranslated.txt` when ARBs changed, `dart format` clean,
  `flutter test test/database` after any DAO or migration change, the §6
  list re-read against the diff, the slice's acceptance numbers (§5) shown
  by the pins S3 lays down. Then the as-built note into §8.2 and a ready
  commit offered — the owner commits.
- **Order.** Phase 0 first (it changes no behaviour and makes every later
  number visible), then 1, 2, 3, 4, 5, 6 unless D14 says otherwise. Within a
  phase the slices are ordered; across phases only the dependencies in §8.1
  bind. The Firestore rules deploy (S6) and the same-day install on every
  device (D2) are the owner's steps and are named in the slice.
- **Kick-off prompt for the first session** (phase 0, after the owner's
  answers are written into §4):

  > Load `anta-context`, `drift-migrations`, `flutter-principles`, `verify`
  > and `delegation`. Open `docs/scalability-roadmap.md` §1, §4, §5.1, §6,
  > §7 and §8 — by section, never whole. Build S1 (the wire version
  > decoupled from the Drift schema), then S2 (surrogate-safe chunk cuts),
  > then S3 (scale fixtures, count pins, the benchmark tier), one
  > `implementer` and one `reviewer` each, the suite from this session. Do
  > not commit; at each slice boundary report the uncommitted file count
  > and a ready commit. Write each as-built note into §8.2.

## 2. Why — the limits found

Every line below was reproduced from the code by at least two independent
agents and judged to matter at the scales a personal tracker reaches over
years: a 100 KB to 3 MB note (a multi-year training log or journal), 5,000
notes in 300 folders, 20,000 calendar events over ten years, three devices,
a 500 MB database, a mid-range Android phone on a flaky link.

### 2.1 What the owner heard, measured

"A one-letter change resends the document" is true in substance, with two
corrections. A note travels as **one Firestore document carrying its whole
body as a plain JSON string** (`lib/services/sync/tables/notes_binding.dart`
`encode`, decision D14 in `docs/cloud-sync-readiness-roadmap.md:250`). The
outbox coalesces by `(table, rowKey)` (`sync_outbox_table.dart:32`), and the
engine pushes 30 s after the outbox goes quiet (`sync_engine.dart:117-137`),
so it is one upload per pause, not one per letter — but each upload is the
whole text, and there is **no maximum wait**: a continuous editing burst
never pushes until it stops. Then:

| Note | Today, per push (up) | Each other device (down) | Over the cap |
| --- | --- | --- | --- |
| 100 KB | ~100 KB, uncompressed | the same, plus the writer re-downloads its own push once | — |
| 300 KB | ~300 KB | the same | — |
| 900 KB | **never syncs**: a row over 900,000 JSON bytes is parked (`sync_pusher.dart:18`) | nothing | shown only as an anonymous "N held back"; the other devices never learn |
| 3 MB | never syncs | nothing | same |

A rename, move, label change or reorder re-pushes the whole body too
(`notes_binding.dart` `encode` reads the body for every row), so **one drag
in a folder of 300 notes uploads 300 bodies**, and a metadata edit that wins
the whole-row last-writer-wins race **overwrites a newer body edit** made on
another device. Readiness D14 promised that an oversized note is "refused
with a visible reason"; the Sync page shows a count only.

### 2.2 The note body on the device

- **Every save loads and decompresses every chunk to compare it.**
  `ContentChunkDao.writeChunks` (`content_chunk_dao.dart:141-268`) splits the
  text into fixed 10,000-character slices, reads all stored chunks,
  base64-decodes and gunzips each compressed one, compares, then gzips the
  changed ones — all on the UI isolate (Drift moves only the SQL to its
  isolate). A 300 KB note pays 30 inflates per 5-second pause.
- **Fixed-offset slices shift.** One character inserted near the top moves
  every later boundary, so every chunk after the caret is rewritten and
  re-compressed; the diff helps appends only. Per-chunk sync built on these
  slices would not help either.
- **Surrogate pairs are cut.** `_splitRaw` cuts at UTF-16 offsets with no
  surrogate check; an emoji straddling a 10,000 boundary becomes two lone
  surrogates, which `utf8.encode` writes as U+FFFD inside the gzip path. The
  character is corrupted on save and on remote apply, and the chunk never
  compares equal again. **Data corruption, independent of scale.**
- **Opening** decompresses every chunk and counts graphemes on the UI isolate
  before the first content frame; a save holds 6–10 transient full copies of
  the body; the character count joins and grapheme-walks the document
  300 ms after every pause; the 200-character preview splits the whole
  document into lines on every save; the search index re-tokenises the whole
  body and walks the whole corpus vocabulary on every save
  (`folder_search_service.dart`); find ships the whole document to its
  isolate per edit and maps matches in quadratic time; the content LRU is
  bounded by count (50), not bytes; nothing is released on memory pressure.

### 2.3 Sync correctness and runs

- **Offline conflicts lose text silently when the older edit was pushed
  first.** `mergeNoteDocument` files a conflict copy only when the losing
  local row *was still unpushed* (`note_dao.dart:987-1000`,
  `localHadPendingPush`), and the `keptLocal` branch drops the incoming body
  (`note_dao.dart:1033`). Device A edits at t1 and pushes; B edits at t2
  offline, comes online, pulls A's row — B's newer row wins, A's text is
  dropped with no copy; B pushes; A pulls t2 — A's t1 row was already
  pushed, so no copy either. A's text is gone everywhere. **Blocker, at
  every note size.**
- **Pull pages are 499 documents with no byte cap** under a fixed 60 s call
  deadline and no adaptive retry (`firestore_sync_gateway.dart:160-190`);
  push parts of 8 MiB (`sync_pusher.dart:23`) need over 1.1 Mbit/s inside
  60 s or are retried whole forever; a push batch loads and encodes up to 499
  bodies before it is cut by bytes; one page of up to 499 merges, FTS
  re-indexing included, runs as one transaction on the single Drift isolate.
- **A rebind re-uploads everything.** The initial merge queues every row
  (`sync_outbox_dao.dart:111`), and the `unchanged` pull branch never
  acknowledges the outbox entry, so a Merge of a database the space already
  holds re-pushes all of it; one document per row against Spark's 20k
  writes and 50k reads a day; the pull runs only in the foreground.
- **Steady state:** the writer re-downloads every note it just pushed (the
  echo); every resume runs a full pull of all 18 tables one request at a
  time before the user's edits are pushed; each run's first page per table
  re-reads a 10 s overlap window; nothing syncs while the app is closed.
- **Apply hooks reload whole caches.** Any pulled calendar row reloads every
  calendar service's whole store, the bloc re-reads all events a second
  time, and every alert is re-planned (`app_sync_apply_hooks.dart`).
- **Parked rows live in memory only**, so a parked pull row is skipped for
  good and, after a restart, its stale local version can be pushed over the
  space.

### 2.4 Search and the browser

- **Body search is an in-memory inverted index built from every note body**,
  one content query per note, rebuilt after each launch and each folder
  close, resident for the life of the process (`folder_search_service.dart`
  `buildIndex`, lines 559-585). At 5,000 notes it is tens of MB and seconds
  of build; at 500 MB of notes it cannot work.
- **Quick search scans only the 300 most recent notes** in Dart
  (`_quickSearchPageSize`, line 464), title and preview only; older notes and
  tags deep in a long note never appear while typing.
- **`notes_fts` indexes title and the 200-character preview, is maintained on
  every write, and no UI path queries it** (`note_dao.dart:348-375`; the
  `fullTextSearch` chain ends in `NoteStorageService` with no caller).
- **Dense integer positions**: one drag rewrites every row between the old
  and new index, each a sync entry carrying the full body; reorder assigns
  positions 0..k-1 to the loaded pages only, so unloaded notes keep colliding
  positions; a multi-select move runs one transaction per item.

### 2.5 The calendar

- **The whole event store is read and held in memory**
  (`calendar_event_service.dart`, `CalendarEventDao.getAll` at line 36); no
  date-windowed query exists. The measured cost at 2,000 events is fine; the
  limit is that **every routine change rebuilds it**: a delete reloads four
  child stores wholesale, nine page returns dispatch a full re-read, a sync
  pull carrying one event reloads every calendar service and re-reads the
  events again in the bloc, and the alert reconcile runs over the whole store
  on every launch, resume and save.
- **Scans outside the memoised 7-month window walk the whole store per
  cell** (date-picker months), the overview's year runs and the agenda expand
  recurrences on the UI isolate, and the report scans the whole scoped store
  once per category.
- `CalendarPageLoaded` carries the whole event list in its Equatable props.

### 2.6 Storage, backup, import, counters

- **Tombstones are never collected, and a deleted note keeps its whole
  compressed body** in `content_chunks`; `content_chunks` has only a partial
  index, so a `DELETE … WHERE note_id = ?` with a bound tombstone filter can
  scan the largest table; `sync_outbox` has no index on its push order.
- **Zip export and import are built and decoded whole in memory** on the UI
  isolate; the live `.db` share can copy a torn file if a write lands after
  the checkpoint (the window the owner logged in
  `docs/settings-rework-roadmap.md:584`).
- **Importing a database is one opaque `File.copy`**: no progress, no
  verification (a header-valid corrupt file, or a file from a newer schema,
  becomes the active database), a partial file left behind on failure.
- **Counter values merge last-writer-wins on an absolute number**
  (readiness D8 A): the losing device loses *every* increment since its last
  pull, not one; and values of a deleted note are never tombstoned.
- **There are no scale measurements.** No benchmark opens or saves a note
  over 14 KB, no sync benchmark exists, the calendar benchmark stops at
  2,000 events, and the only device is a Pixel 9 Pro profile on a desktop
  host. Nothing can show a remedy worked.

## 3. What the big apps do

From the researcher's pass (sources in the workflow output; the facts below
were read from official pages where one exists):

- **Firestore.** 1 MiB per document; 10 MiB per request; writes are billed
  per document, not per byte, so bytes cost only through egress (10 GiB a
  month free, then $0.12/GiB) and through whole-document delivery to
  listeners; Spark: 50k reads, 20k writes a day, 1 GiB stored; large blobs
  belong in Cloud Storage or in small immutable documents; cursors, never
  offsets; a listener reconnect after 30 min offline is a new query.
- **Obsidian Sync** syncs files in versioned chunks with published per-file
  caps and a history window; **Simplenote/Simperium** sends deltas with
  version numbers and pages the initial index; **Apple Notes/CloudKit** caps
  a record near 1 MB and moves anything larger to a `CKAsset` side channel;
  **Notion** syncs per block; **Google Docs/Firepad** keep an operation log
  with periodic snapshots; **Yjs** ships CRDT text deltas; **Joplin** tracks
  per-item sync state; **Standard Notes** encrypts whole items and therefore
  cannot delta. The common unit for large text is a **small immutable chunk
  identified by its content**, with a manifest naming the chunks.
- **Sync engines.** Replicache batches pushes and pulls by cookie, then
  rebases; PowerSync compacts buckets for a fast initial sync; Ditto bounds
  tombstones with a retention window; Google Calendar expands recurrences
  only inside a window and forces a full resync when a sync token expires;
  CalDAV servers cap recurrence horizons.
- **SQLite on mobile.** WAL with `synchronous=NORMAL` (ANTA has it); FTS5
  with a trigram tokenizer for substring search, external-content or
  contentless tables fed from the real rows; keyset pagination (ANTA has
  it); the database on a background isolate (ANTA has it); `PRAGMA optimize`
  on long-lived connections; incremental vacuum.
- **Large text editing.** VS Code's piece-tree buffer and CodeMirror's
  viewport-only rendering: cost proportional to the edit and to the visible
  lines, never to the file. ANTA's fork already virtualises layout and keeps
  its grammar passes incremental; the save path and the counters are what
  still scale with the file.
- **OS limits.** iOS caps pending local notifications at 64; Android exact
  alarms need the permission and OEMs cap per-app alarms around 500. ANTA's
  48 + 20 horizon (`alert_constants.dart:38-68`) is already under both.

## 4. Decisions for the owner (D1–D14)

Lettered options, the recommended one first, one line of why. A delegated
decision ("take it from me") means the recommended option stands. Answers
are written here with the date; later amendments append, never rewrite.

**Answers (2026-11-07, delegated by the owner: "you may decide and implement
everything").** D1 A (chunked, content-addressed), D2 A (one hard
cutover), D3 A (the wire version decoupled), D4 A (copies both ways; B stays
in §11), D5 A (trigram), D6 A (whole bodies, AND-ed from 2 characters),
D7 A (whole store, targeted maintenance), D8 A (PN-counter plus
tombstoning), D9 A (gapped positions), D10 3 min, D11 A (snapshot share),
D12 A (Spark until ~15k rows), D13 A (full hygiene), D14 A (every phase, in
order; independent streams in parallel worktrees where file ownership is
disjoint; every migration-bearing slice goes through the main tree in the
order S4 v46 → S16 v47 → S11 v48 → S20 v49 — S16 landed before S11, so the
two swapped numbers against the first draft of this line).

- **D1 — The note on the wire (supersedes readiness D14 A).**
  **A (recommended): chunked.** The body leaves the note document.
  `content_chunks` becomes a synced table of content-addressed, gzip-
  compressed, **immutable** chunk documents (id = SHA-256 of the chunk text),
  and the note document carries an ordered **manifest** of chunk hashes plus
  a body hash. A one-letter edit pushes the one or two chunks it touched
  (about 4–8 KB compressed) and the manifest; a rename pushes the manifest
  only; the 900 KB cap disappears (a 3 MB note is ~300 chunks and a 20 KB
  manifest); conflicts stay whole-note last-writer-wins on the manifest, so
  D14's worry ("interleaving chunks from two devices") cannot arise — no
  device ever merges two manifests, it takes the winner and fetches the
  chunks it lacks. This is what Obsidian, CloudKit and rsync-style systems
  do. **B: one compressed body document per note** beside the metadata
  document: 3–5× fewer bytes, the cap moves to ~2.5–5 MB of markdown,
  metadata edits stop carrying the body, but a one-letter edit still
  re-sends the whole compressed body (~75–100 KB for a 300 KB note), and the
  two-register split needs its own liveness rules (§5.3). **C: keep D14**
  and ship only S7 (held-back notes named, a push at most N minutes after
  typing starts).
- **D2 — The cutover.** **A (recommended): one hard cutover** through the
  existing `appOutdated` gate (`sync_engine.dart:1011`, `firestore.rules:193`):
  deploy the rules first, then install the new build on every device the
  same day; an old build pauses with "update the app" and loses nothing (its
  outbox is durable, its parks are retried). **B:** dual-format reading for a
  transition period — more code and a second cutover later, for a one-user
  space.
- **D3 — The wire version decoupled from the Drift schema.** **A
  (recommended):** a `syncSchemaVersion` constant (45 now) reported to the
  space instead of `DatabaseSchema.currentVersion`, pinned by a snapshot test
  over every binding's encoded field names, bumped only for D1. Without it
  **every local-only migration in this plan (hashes, indices, FTS, purges)
  would pause the owner's other devices as "app outdated"** — a critic found
  this in two designs that had claimed "zero wire risk". **B:** keep the
  coupling and update every device the same day at every migration.
- **D4 — Offline conflicts.** **A (recommended):** a conflict copy for every
  lost text in both directions — the `keptLocal` branch files the incoming
  text, and a per-note base stamp in `sync_metadata` lets the device that
  pushed first recognise the overwrite — plus durable pull parks; no wire,
  rules or schema change. **B:** also a `baseHlc` on the wire so the author
  files its own overwritten version (closes the three-device residual).
  **C:** leave last-writer-wins as it is; text loss stays.
- **D5 — Search.** **A (recommended): a persistent FTS5 trigram index over
  note bodies**, device-local, outside sync and backup, filled lazily off the
  UI isolate, used by the full search and the quick search; the in-memory
  corpus index and the dead title+preview table retire. Mid-word matching
  survives ("quat" finds squat; German compounds match); the index is about
  2–3× the text on disk (~15 MB for a 5 MB library). **B:** a unicode61
  prefix index, 0.3–0.5× the text, words match from their start only.
- **D6 — Quick search semantics** (with D5 A). **A (recommended):** quick
  hits search the whole body of every note, every typed word must appear,
  from 2 characters, ordered by bm25 with the title weighted 2×. **B:**
  title-only quick hits; bodies only in the full search.
- **D7 — The calendar store.** **A (recommended):** keep the whole-store
  cache and make every routine change cost O(changed rows): the window
  index, targeted cache maintenance, table-scoped sync reloads, a keyed
  patch per pulled event. The windowed store waits for a real store past
  ~10k event rows or a measured cold open over 500 ms on the phone at the
  20k benchmark (S3 adds it). **B:** build the windowed store now (XL, async
  all-of-time surfaces, silent-wrong-answer risk outside the window).
- **D8 — Counters across devices (reopens readiness D8 A).** **A
  (recommended):** a per-replica increment ledger inside the counter value
  row (a PN-counter: an epoch stamp and `{p, n}` per replica; the
  materialised `value` stays for old builds and the backup), so offline taps
  on two devices add up; plus per-note values tombstoned with their note.
  **B:** the note-delete tombstoning only; last-writer-wins stays and the
  losing device still loses every tap since its last pull.
- **D9 — Positions.** **A (recommended):** gapped 64-bit positions,
  direction-aware, folders and notes each their own sequence, negatives
  allowed, a drag writes only the moved rows, position-only writes leave
  `updatedAt` alone, bulk moves are one set-based transaction, move history
  is counted in undo units. **B:** dense renumbering kept, only the
  correctness fix (splice the loaded order into the full order).
- **D10 — Push cadence while typing.** A push at most N minutes after the
  first unpushed edit, beside the 30 s quiet debounce: **3 min
  (recommended)** / 2 min / 5 min. Under D1 A the cost of 3 min on a 900 KB
  note edited for an hour is a few hundred KB; under D1 B about 5 MB.
- **D11 — The `.db` share.** **A (recommended):** share a `VACUUM INTO`
  snapshot from Drift's isolate; the consistency window closes, free pages
  are dropped from the shared file, and a busy WAL no longer refuses the
  share (one pinned test flips). **B:** leave it.
- **D12 — The Firebase plan.** **A (recommended):** stay on Spark; move to
  Blaze with a budget alert (about $1–5 a month) when the synced database
  passes ~15k rows or a second person signs in — the budget table in §5.4 is
  the trigger. **B:** Blaze now.
- **D13 — Storage hygiene.** **A (recommended):** a tombstoned note's chunk
  bodies are deleted (its row stays, so soft-delete semantics hold), a one-
  off purge in the migration, the full chunk index, the outbox order index, a
  localized "Updating your data…" screen only while a migration runs, a
  "reclaimable: X MB" caption beside Optimize; no `PRAGMA optimize`/ANALYZE
  this release. **B:** indices only.
- **D14 — Order and scope.** **A (recommended):** the phases in the order of
  §8 (0 → 1 → 2 → 3 → 4 → 5 → 6), one slice per implementing session, a
  ready commit at every boundary. **B:** phases 0–2 and 4 this round
  (the note body and body search), 3, 5 and 6 later. **C:** another order
  the owner names.

## 5. The design

Each slice: what it builds, the files (full list in §7), schema and wire,
the tests it adds or flips, and the acceptance it must show. The critics'
amendments are folded in; where a critic found a blocker the design below is
the amended one.

### 5.1 Phase 0 — Foundations (no user-visible change)

**S1 — The wire version** (D3). `DatabaseSchema.syncSchemaVersion = 45`
(or a `SyncSchema.wireVersion`), passed at `sync_engine.dart:320` and
`sync_space_service.dart:329` in place of `currentVersion`; a test pins that
it never drops below 45 and a **snapshot test** of every `SyncTableBinding`'s
encoded field names fails when the wire changes without a bump; the sync
reference in `anta-context` says so. Must land in the same commit as the
first v46 migration (S4 or S16) and never run a v46 build against a bound
space without it. Size S.

**S2 — Surrogate-safe cuts.** `_splitRaw` and `replaceChunks` in
`content_chunk_dao.dart` step the cut back one code unit when
`codeUnitAt(end-1)` is a high surrogate. Test: a body with U+1F3CB at
offsets 9,999 and 19,999 round-trips (`loadContent(id) == body`); it is red
at HEAD, so it lands with the fix. Size S.

**S3 — Scale fixtures, count pins, the benchmark tier.**
`test/support/scale_fixtures.dart` (`bigBody(n)` with non-BMP characters at
every 10,000 boundary; ASCII, Romanian and German text). Default-suite pins
(counts only, exact, each remedy flips its own): `content_chunks` writes for
a local one-character save at 100,000 and 300,000 chars, counted with
table-qualified fragments (`UPDATE "content_chunks"`, `INSERT INTO
"content_chunks"`, `DELETE FROM "content_chunks"`); the receiving device's
apply of that save through `SyncPair` (today 1 DELETE + 11 / 31 INSERTs);
bytes per one-character save on the wire within [body, body + 4 KB] today;
the 900,000-byte park (no test covers it today; the constant is hard-coded in
the fixture with a `///` naming `sync_pusher.dart:18`, since `_Pusher` is
library-private); the batch shape at `maxBatch = 3` over ~10 outbox rows;
`FolderSearchService.buildIndex` content loads == 60 with a cold LRU.
Benchmark tier (`flutter test --tags benchmark --run-skipped
--concurrency=1`): open, save and remote apply at 100 KB / 300 KB / 900 KB /
3 MB on memory and on a file with the production pragmas; a (20,000 events,
10 years) tier in `volume_benchmark_test`; `buildIndex` at 500 and 5,000;
a sync volume run via `SyncPair.open(background: true)`. One gate timing with
`--file-reporter json:build/test/report.json` and a small summariser,
recorded in the `verify` skill (its "~6,800 / ~75 s" line is stale). The
500 MB padded database stays out of the default benchmark. Size M.

### 5.2 Phase 1 — The note body on the device

**S4 — Content-defined chunks with a per-chunk hash.** Migration v46
(local-only under S1): nullable `content_hash` on `content_chunks` (NULL =
legacy fixed slice) and `idx_content_chunks_hash(content_hash)`. A Gear-hash
content-defined cutter (minimum ~4 K, target ~8 K, maximum ~16 K code units;
tests the high bits of a 32-bit rolling hash; cuts before a high surrogate;
never exceeds the maximum). Chunk identity = **SHA-256** over the UTF-16
code units (`package:crypto`, promoted to a direct dependency) — the
designer's FNV-1a would do for a local diff, but under D1 A the hash becomes
the chunk's document id, where a cryptographic, global identity matters.
The planner: common hash prefix and suffix plus one arithmetic
`chunk_index` shift; a hash match is a `chunk_index`-only UPDATE, new
content an INSERT, a dropped chunk a DELETE. `writeChunks` compares hashes
and never decompresses; `replaceChunks` (the pull side) runs the same
planner instead of the hard-delete-all; the cut, hash and codec run in
`Isolate.run` above 64 K code units (below it the inline work is under 2 ms
and widget tests stay synchronous). `updateNote` plans first and stamps the
row only when the body text or metadata changed (no-op saves stop pushing a
body of up to 900 KB; this follows `crdt_write.dart`'s own rule). Legacy
notes are re-cut lazily on their next body save; a note with any NULL-hash
row is compared once through `loadContent`. gzip above 5,000 chars stays.
Tests: planner unit tests (insert at the top shifts indexes only; moved
paragraphs reuse chunks); `note_merge_test:84-88` relaxed from "all chunks"
to "written chunks" or kept with its I/O recorded as O(n) (owner's call in
the slice); `query_count_test`, `sync_outbox_test:242`,
`note_merge_test:609`, `sync_engine_failures_test:323/856/880` cross the
64 K threshold and are updated. Acceptance (S3 pins flip): a one-character
edit near the top of a 3 MB note = 0 inflates, ≤ 2 deflates, ≤ 4 row
operations; the remote apply of a one-character edit to a 300 KB note = ≤ 4
row operations instead of 1 DELETE + 31 INSERTs; save work above 64 K off
the UI isolate. Size L.

**S5 — Per-save and per-pause work in the editor.** The bloc's eager
`updateIndex`/`loadNoteContent` after a save go (the repository change
stream already marks the note stale; the index refreshes at the next
search); `addNote` removes the note's old terms first so the targeted
`removeNote` is safe; the preview strip stops after three lines; `shouldCompress`
uses the length shortcut with no `Uint8List` copies; the stats tracker is
skipped while the bar is hidden, and the fork's grapheme count is defined
per `CodeLine` with the separators added once; find: linear position
mapping, latest-wins coalescing in `_IsolateTasker`, no `CodeLines` on the
return trip, no cap; the ledger keeps a `_dirty` set filled synchronously in
`_onNoteChange` and refolds only dirty or new notes on a 1 s trailing
debounce; the content LRU is weighted by code units (8 MiB) beside the
50-entry cap, with full weight bookkeeping; `didHaveMemoryPressure` calls
the repository's `invalidateAll()`; the open path uses `codeLinesAsync`
above 256 K code units with a sequence guard after the await; the browser's
preload of the first three bodies checks `contentLength`. Tests: the five
search suites, the auto-save suite, the ledger suite; new pins: a save of a
300 KB note performs no tokenisation and no preview split beyond three
lines. Acceptance: at 300 KB the typing-pause work on the UI isolate is
under one frame; the per-save UI work is bounded by the join and the hash.
Size M.

### 5.3 Phase 2 — The note body on the wire

**S6 — Chunked sync** (D1 A; two sessions). *Rules:* `content_chunks` joins
`syncedTable()` (`firestore.rules:197-204`); optionally `validEnvelope`
bounds a chunk's `gz` field to 64 KB; **deployed before any device installs
the build**. *Wire:* a chunk document
`users/{owner}/spaces/{space}/content_chunks/{sha256}` with data `{hash, gz,
length}` — `gz` as a Firestore `Bytes` blob mapped in the impure gateway
(25 % smaller than base64; the local base64 form is decoded once at push) —
written once with the stamp of the note write that created it and never
rewritten (`op: upsert`, idempotent set). The note document's data drops
`content` and carries `chunks: [hash, …]` and `bodyHash`; the decoder
accepts a legacy document that still carries `content` (the space holds them
until the migration re-push). *Local:* `SyncedTable('content_chunks')` loses
`travelsWithParent` and gets `rowKeySql: content_hash`; the outbox entry per
new hash is acked once pushed (a re-pushed known hash is one idempotent
write). *Push:* the chunks of a note and its manifest go in the same commit,
chunks first, so a manifest never precedes its chunks in the space; a note
whose chunks exceed one 10 MiB commit pushes its chunks across commits and
the manifest last. *Pull:* `content_chunks` is pulled before `notes`
(`sync_tables.dart`), pages of 50 (bytes-aware after S10); a pulled chunk
lands in a device-local `sync_chunk_cache(hash, gz, received_at)`; the note
apply assembles the body from the note's own rows by hash, any note's rows,
then the cache, and **fetches missing hashes by document id** inside the run
(`whereIn(FieldPath.documentId, …)` in batches of 30, a new gateway method);
if a fetch cannot complete, the note is applied **body-pending** (row
written, chunk count 0, a `body_pending` mark; the editor shows "waiting for
sync" and `afterRun` resolves it when the chunks land). The cache is pruned
once a manifest consumed its hashes, and by age after 30 days. *Conflicts:*
the manifest is the LWW register; the loser's text becomes a conflict copy
under S8's rules; the delete-vs-rename race that broke design B does not
arise here, because a revived note's manifest names chunks the space keeps.
*Migration:* `syncSchemaVersion` goes to 46 (the cutover, D2); every live
note's manifest and the hashes of its chunks are queued once; the
`unchanged` ack of S9 makes the second and third devices retire their own
entries when they pull manifests equal to their bodies, so the upload happens
once per space, not once per device — S9 therefore lands before S6. *GC:*
none in this round; storage grows by a few KB per changed chunk per push
(§11 holds the trigger). Tests: wire codec round-trip; `SyncPair` scenarios
— a one-character edit near the top of a 300 KB note reaches B as ≤ 2 chunk
documents plus one manifest; a rename reaches B as one document under 4 KB;
two offline edits yield exactly one conflict copy; body-pending resolves on
the next run; a 5 MB note syncs; the rules emulator test for the new table;
the S3 bytes pin flips to ≤ 20 KB. Acceptance: those numbers, on the
emulator seam and on the owner's two devices. Size XL.

*If the owner takes D1 B instead:* a `note_bodies` register per note (gzip
body, `bodyHlc`), the body's liveness following its note (a note delete
writes only the `notes` tombstone and never tombstones the body; a live
remote meta over a local tombstone restores the chunks), body-pending for a
note that arrives before its body, the `notes` pull cursor cleared by the
migration, the migration stamping a pending note from
`MAX(content_chunks.hlc_timestamp)`, a page limit for `note_bodies`. Size L.

**S7 — Visibility and cadence.** `pushMaxWait` (D10) beside the 30 s quiet
debounce (amends readiness D19); held-back rows persisted under
`push_parked.` keys and retried at start (≤ 100) and on every build change;
the Sync page lists each held-back note **by name with the reason** (the
D14 promise), `designer` spec for the row, strings in en/de/ro. Under D1 A
an oversized body no longer exists, so the list carries only refused rows.
Size S–M.

### 5.4 Phase 3 — Sync correctness and runs

**S8 — Conflicts** (D4 A). A base stamp per note in `sync_metadata`
(`note_base.<id>`, no migration): the stamp of the last version this device
pushed or pulled for that note. Rule K, amended: on `keptLocal`, when
`remote.deviceId != db.deviceId && remote.hlc != base && (remote.hlc > base
|| local.deviceId == db.deviceId)`, the note is live, above the floor and
the bodies differ, the **incoming text is filed as a conflict copy**; the
device raises its base to the remote stamp before it pushes, so a copy is
filed exactly once per lost version. Durable pull parks under `pull_parked.`
hold back only entries at or below the parked stamp, '' parks (malformed
documents) are counted but never held across launches, all parks are retried
on the first start after a build change and 100 per start otherwise; the
gateway-skipped keys of the all-skipped page branch are persisted too.
Tests: `sync_pair` cases — the older edit pushed first gives one copy on
exactly one device; a lost ack then the echo gives no copy; a regression
healed by the requeue gives one copy; the existing conflict suites stay
green; the seed is gated on bound (`sync_engine_lifecycle_test:960`).
Acceptance: no two-device offline edit of one note loses text; copies do not
multiply. Size M. (D4 B adds `data.baseHlc` on the wire and Rule A later.)

**S9 — Runs and rebinds.** The equal-stamp ack: when a pulled row's stamp
equals the local one, `ackThrough(table, rowKey, localHlc)` inside the merge
savepoint, never for the seed stamp — a rebind, a restore-then-bind or a
Merge of identical data uploads nothing (`merge_contract`'s "same stamp"
case allows DELETEs on `sync_outbox` only). The Android backup exclusion of
`gym_notes/device_id` (`dataExtractionRules` for API 31+ and
`fullBackupContent` for 24–30, domain root, cloud backup and device
transfer) — the path itself is never renamed. The quota pause says
"continues at {local time of the next midnight Pacific}" and retries at
reset + 5 min. Signal-driven resume: pull only the tables the signal names,
a full run after 5 s without a snapshot and at most every 24 h, the
`full_pull_at` check inside `_reevaluate`. The settled overlap: the 10 s
overlap re-read is skipped for a table whose last server write — the max of
the live signal and a persisted server-time high-water mark (`server_seen`,
cleared on unbind) — is older than the cursor plus the overlap. Run counters
(rows and bytes pulled and pushed, pages, attempts, duration) in
`SyncRunReport` plus one debug log line. The echo skip (a clean-push mark
decided inside the push transaction) stays in §11 until the budget table
asks for it. Tests: engine suites; new cases — resume with no signal issues
no overlap re-read on a settled table; equal-stamp ack retires the entry;
the quota time. Acceptance: an idle resume costs one read instead of 18; a
rebind of identical data pushes zero documents. Size M.

**S10 — Paging and slow links.** `SyncGatewayException.timedOut()` typed
(failure stays "offline"); decrease-only adaptive sizes kept in memory: the
pull take halves on a timeout down to 1 and the push part budget halves
from a 2 MiB first part (8 MiB maximum, 1 MiB floor), both reset at launch
or when a drain empties the outbox; the `notes` binding pulls pages of 50
(other tables keep 499; `pullPage(limit:)` exists); `_prepare` stops
encoding when the accumulated bytes would pass the budget and returns that
prefix with at least one row, the rest stays queued (`_byBytes` is deleted),
so memory stays at one part plus one row; the persisted overlap scan cursor
(`pull_scan.<table>`, written in `_apply`'s transaction, deleted once the
walk passes the stored cursor) so a cut walk resumes; only the `pullPage`
call is timed. Tests: `failNextWithException` on the fake gateway; push
sizes pinned; `_FaultyMerge` forwards the limit. Acceptance: a 900 KB
document pulls on a 0.25 Mbit/s link after at most six halvings; the push of
a 5,000-note outbox never holds more than one part in memory. Size M.

**The budget table** (goes into the sync record's §11 as an addendum when
S9 lands): per ordinary day of use — autosave pushes, presence marks,
skips, descriptions, counter flushes, a drag in a 300-note folder — the
documents written and read, the bytes up and down per device, stored bytes
over a year, against Spark's 20k / 50k / 10 GiB / 1 GiB. It is the trigger
for D12, for the echo skip and for chunk GC.

### 5.5 Phase 4 — Search over bodies

**S11 — The body index** (D5 A). A device-local FTS5 **trigram** table
over a Dart **projection** of each body (today's `normalizeForSearch`
folding, tokens joined by spaces, so a word of 3+ characters matches as a
substring within a token and a 2-character word as a token prefix through
the leading-space trigram — the existing five search suites stay the
behaviour oracle), one row per note, plus a ledger table outside the
`notes_fts` prefix holding `indexed_hlc` and a body fingerprint (title,
`content_length`, `chunk_count`, max live chunk HLC). Staleness is keyed on
`notes.hlc_timestamp`, which every body write already moves in the same
transaction, so no write path gains a hook; label, move and reorder stamps
advance `indexed_hlc` with one SQL touch and never re-project. The backfill
is lazy and cooperative: pages of ~256 KiB by `contentLength` (an oversized
note alone in its page), a yield between pages, a pause while the editor is
dirty, the projection in `Isolate.run`, the SQL on Drift's isolate, a WAL
checkpoint at the end; a search during the backfill returns within 300 ms
plus one page with the line "Still indexing notes — some may be missing".
The virtual table is created defensively with a capability flag and the old
path as fallback; `release doctor` probes `sqlite_version()` and trigram on
Android (the bundled SQLite is 3.53 with FTS5). Full search runs on the
index with the folder and label filters in SQL; the in-memory corpus index
is no longer built. The table is derived and never synced or backed up as
data (it travels inside a `.db` share as a file, which is fine). Writes go
through `customUpdate`/`customInsert` with a positive control so the
`query_count` pins are real; the indexer has an injectable scheduler and a
`close()`. Acceptance: memory O(one page); no per-launch rebuild; a save does
no indexing work; a query is a constant number of statements; the 5,000 ×
15 KB corpus searches under 300 ms; note-open and folder-list latency during
a backfill are pinned. Size L.

**S12 — Quick search on the index, the old table retired** (D6). Quick
hits over the whole body, words AND-ed from 2 characters, bm25 with the
title weighted 2× and ties broken by `updatedAt`; terms under 3 characters
title-only; `#tag` narrowing as the tag roadmap asks; a non-blocking catch-up
when an in-memory dirty flag says the ledger moved. Then retire `notes_fts`:
the table, its upkeep in `NoteDao` and `FolderDao`, the uncalled
`fullTextSearch` chain, the Optimize page's rebuild call (about ten tests);
`SearchIndex` and the corpus build in `FolderSearchService` go with it (the
folder name index stays). Acceptance: a word deep in a note older than the
300 most recent appears while typing. Size M.

### 5.6 Phase 5 — The calendar

**S13 — The window index.** `EventWindowIndex`, identity-memoised on the
store's list: one-time events bucketed by month so any scan over a window
touches the recurring events plus that window's one-time events;
`occursOnUtcDay` stays the sole arbiter and `partitionForWindow` keeps its
order. Used by `occurrencesInRange`, the bloc's out-of-window and filtered
`allEventsForDay` paths, the overview's `_take`, `UpcomingAgendaView` and
`DigestPlanner.plan`. The report groups events once (`eventsByCategory`
from `byId` after one loop). `_dayCache` and `_unfilteredDayCache` are
bounded outside the window. The sync hook's `events` entry reloads only a
live instance. Acceptance at 20k events: a year run costs recurring + that
year's one-time events; a date-picker month 42 × (recurring + that day's
one-time events); the sync apply no longer loads the store twice. Size M.

**S14 — Targeted cache maintenance and scoped sync reloads** (D7 A).
Revisions before lists in `CalendarPageLoaded`'s props; delete and restore
patch the four child facades in place (live instances only, `_writes`
re-checked across the read) instead of four whole reloads;
`RefreshCalendarView` — a fresh `List.unmodifiable(service.events)` that
bumps both revisions — replaces `LoadCalendarEvents` on the nine page
returns, the Keep gate (`calendar_page.dart:615`) included;
`notifyExternalChange(cacheCurrent: true)` from the sync hooks and the
category delete so the bloc stops its second full read (restore, delete-all
and database switch keep the re-read; `_load`'s error path reports failure
instead of publishing an empty cache). The apply hooks reload only the
tables the run touched (categories always; `tables == null` falls back to
today's dispatch; templates, presets and views only when live) and re-plan
alerts on a presence or profile change only when a report digest is enabled
(the scheduler's own rule at `alert_scheduler.dart:1077`, extracted once).
`CalendarEventService.applyMerged` patches pulled events by id (replace in
place when the start day is unchanged, insert by start otherwise, one sorted
pass; over 500 ids or any parse or patch failure → full reload; ids cleared
in `afterRun`'s finally). `EventAlertService._load`'s clear-before-await is
fixed in its own small commit. Tests: a differential test against direct
DAO reads (ties unordered); the bloc and hook suites. Acceptance: a remote
presence tap costs one small table read, no event read and no re-plan; a
delete reloads nothing wholesale; a pulled event is one keyed read. Size M
(optionally split: maintenance first, `applyMerged` second).

**S15 — Alerts launch fast path** (optional). The "nothing can arm" path
skips `CalendarEventService.getInstance()` at launch and resume when no own
alert, category alert or digest is enabled and the registry holds no pending
rows. The bounded alert window read stays in §11 until a profile shows the
launch load matters for users who do have alerts. Size S.

### 5.7 Phase 6 — Storage, lists, backup, import, counters

**S16 — Storage v47** (D13; written as v46 when S4 and S16 were expected
to share a step — as built S4 is v46 and S16 is its own v47). Chunk rows are deleted at tombstone time on all four
paths (single, bulk, remote merge after the loser-content read, the folder
cascade over its RETURNING ids); the migration purges chunks of non-live
notes with an anti-join and then stray `is_deleted = 1` chunks; the partial
`idx_chunks_note_index` becomes a full `idx_content_chunks_note(note_id,
chunk_index)` (every chunk row is now live, so the partial predicate buys
nothing and the bound-parameter miss disappears on every SQLite);
`idx_sync_outbox_order` with the row-value resume in `pending()`; the
uncalled `getChunk`, `getChunkCount`, `getChunksSince` and `mergeChunk` go;
`_seedFromRows` in `onUpgrade` is gated on there being no stored `last_hlc`;
`journal_size_limit`; Optimize reordered to FTS rebuild → tombstone FTS
cleanup → VACUUM; the reclaimable caption (`freelist_count × page_size`);
the database opens after `QaBootstrap.beforeDependencies` and before
Firebase, `onUpgradeStarting` shows the localized "Updating your data…"
state only when `from < to`, and `AppBootstrap` shows the error state if the
open fails. The 41-site `is_deleted` literal sweep waits for a device
`sqlite_version()` probe (pubspec pins `sqlite3` 3.5.2, which bundles
3.53.4; the comments claiming an old Android SQLite are probably stale).
Must keep: `maxHlc` still counts `content_chunks`; no planner statistics
this release. Acceptance: a tombstoned note holds no body; chunk deletes by
`note_id` use the index; the post-bind drain's pending read is a range seek;
the v47 step measured on `emulator-5556` with the 500 MB fixture. Size M.

**S17 — Lists** (D9 A; two slices, correctness first). Reorder reads the
group's `(id, position)`, splices the loaded order into the full order and
plans inside **one DAO transaction per kind** (`applyOrder`), serialised per
parent; emits for moved ids only; set-based `moveNotes` / `moveFolders` in
one transaction with one HLC, the folder name-uniqueness check (root
included, in-batch dedupe), per-item outcomes kept; batch undo uses
`_firstAvailableFolderId` for a vanished source and reports duplicates per
item; history holds 20 undo units with a hard entry ceiling. Then gaps:
positions as gapped int64 (a stride, LIS-based minimal moves, a **local
window rebalance** with open ends on exhaustion, never the whole group),
direction-aware for `positionDesc` (today's dense write in a descending
custom order likely reverses the list on reload — a pre-existing bug the
slice pins), split per kind, new items at `max + stride`, negatives
allowed after the implementer's grep; position-only writes leave
`updatedAt` alone; the dead dense `reorderNotes`/`reorderFolders` chains and
`mergeByPosition` are removed; `sync_outbox_test.dart:852`'s expected
values updated. Acceptance: a drag in a 1,000-note folder writes ≤ 3 rows; a
200-item move is one transaction; order after reload equals the optimistic
order in both directions. Size M + M.

**S18 — Backup streaming and the share** (D11). Export through
`ZipFileEncoder.createWithStream(OutputFileStream(p), level:
DeflateLevel.bestSpeed)` entry by entry under a provisional name, renamed
after close; import consumes entries one at a time (`ArchiveFile.clear()`
after each, the manifest and `_folder.json` included; the top-level
`InputFileStream` closed in a finally); a mid-walk failure closes the
stream and deletes the partial zip; `BackupService.exportToFile`,
`shareBackup`, `exportAllData` (uncalled; `shareBackup` calls `SharePlus`
directly against the house rule) and `lib/utils/isolate_worker.dart`
(uncalled) are deleted. The `.db` share: `VACUUM INTO` into
`anta_db_share_<ts>/<name>.db` on Drift's isolate, under `PRAGMA temp_store
= FILE` for the statement, a deferred cleanup on desktop (share_plus 13.3.0
still copies the file on Android), a `SQLITE_FULL` failure cleans its folder
and shows `shareError`. Optional S3-sized add-on: the onboarding JSON
restore decodes once in `Isolate.run`. Acceptance: peak export memory is the
largest note; a 500 MB database shares without blocking writes. Size S–M.

**S19 — Import verification.** Copy to a temp name with a determinate
progress bar and Cancel (`<source>-wal` copied when present), then verify in
`Isolate.run` — header, `page_count × page_size == length`, `user_version ≤
DatabaseSchema.currentVersion` (a new `DatabaseImportTooNew`),
`quick_check`, the ANTA-shape check — under an indeterminate "Checking the
file…" step whose Cancel is disabled, then rename; stale temps swept before
`runApp`; the verifier is injected into `DatabaseManager` so widget tests
never run sqlite under `FakeAsync` (the real one tested in
`test/services/database_manager_import_test.dart`); `writeSqliteFile`
beside `writeSqliteHeaderFile`; the onboarding restore shares the dialog;
strings in en/de/ro. If S11 has not shipped yet, the in-memory search index
is cleared on `DatabaseLifecycle.generation` change at search entry (ten
lines; the house seam). Acceptance: a header-valid corrupt file and a
newer-schema file are refused with a message; a cancelled copy leaves no
file. Size S–M.

**S20 — Counters** (D8). Part B: per-note values are tombstoned with their
note in one set-based `UPDATE … RETURNING` plus `enqueueMany` (the
`query_count` pin moves from 4 to 6 deliberately); `applyCount` writes
nothing for a value whose note row is tombstoned (one PK read), so a pending
300 ms tap cannot resurrect it; `sweepOrphanValues` runs once in `afterRun`
when `notes` or `counters` were touched (never per page), plus a one-off
sweep in the migration and an export filter. Under D8 A, the PN-counter:
`epoch_hlc` and a per-replica `{p, n}` shard map on `counter_values`
(migration), `value` stays the materialised total; the merge joins shards
and restamps only when the join differs, **except under the bind floor,
where the remote state wins whole**; only absolute writes (reset, typed
value) mint an epoch, a resurrecting tap uses the tombstone's stamp; shards
are keyed by a **replica id minted per bind, rebind and database import**
(never the install `device_id`, which Android backup can clone);
`WireFields.nullable` decodes the new keys; today's build keeps reading
`value`. Acceptance: offline taps on two devices add up after sync; no
orphan values survive a note delete. Size M.

## 6. Behaviour

### 6.1 Must not change

- The `gym_notes` directory and the `device_id` file path (S9 only
  *excludes* the file from Android backup).
- Soft deletes and the CRDT fields (`hlcTimestamp`, `deviceId`, `version`,
  `isDeleted`) on every table and every row. **One deliberate exception,
  under D13:** the chunk *bodies* of a tombstoned note are deleted; the note
  row, its tombstone and its stamp stay. Chunks are local storage of the
  body (`travelsWithParent: true` today; immutable documents in the space
  under D1 A), so nothing the merge needs is lost.
- The envelope (`hlc`, `deviceId`, `version`, `op`, `ownerId`, `data`,
  `pushedAt`, `pushedBy`), `validEnvelope`, `allow delete: if false` on
  rows and spaces, and the `schema >= resource.data.schema` space rule.
- The merge contract: HLC last-writer-wins per row with the deviceId
  tie-break, the bind floor ("the space is authoritative at or below it"),
  the seed-stamp exclusion, tombstones win per HLC; no stamp is minted
  inside a merge except the two recorded exceptions (the refile, and S20's
  PN join above the floor).
- The outbox primary key `(syncedTable, rowKey)` and its coalescing; the
  30 s quiet debounce (S7 adds a maximum wait beside it); pull before push;
  the backoff ladder and the hourly quota retry (S9 changes only the
  quota's *time*); Firestore persistence off and `includeMetadataChanges:
  true` on the signal listener; the 10 s overlap as the late-commit guard
  (S9 skips it only for a table proven settled).
- Backups and archives: bodies exported as text, every new persisted field
  defaults when absent, `ImportExportService.archiveVersion` unchanged by
  this plan; `createX` stamps now, `importX` preserves.
- The auto-save cadence (5 s debounce, 30 s interval) and its length+hash
  no-op guard; the editor's incremental grammar passes, virtualised layout
  and 200-entry undo; the alert horizons (48 fires + 20 digests, 30 days);
  the OS alarm count.
- `SettingsService` + `SettingsKeys` for every setting; `AppLocalizations`
  for every string; the architecture layers; no new state-management or
  persistence pattern (the FTS table and the ledger are DAO-owned tables;
  the chunk cache is a DAO-owned table).
- Every existing test pin, unless the slice names the pin it flips and the
  new value.

### 6.2 Deliberately changes

- A note's body travels as content-addressed chunk documents plus a
  manifest (D1 A); the space schema becomes a sync version separate from
  the Drift schema (D3); a lost text always leaves a conflict copy (D4); a
  no-op save no longer stamps or pushes; a metadata edit no longer carries
  the body; held-back rows are named; a push comes at most N minutes after
  typing starts.
- Full search runs on a persistent body index; quick search covers whole
  bodies and AND-s its words from 2 characters, ordered by bm25 (D5, D6);
  `notes_fts` and the in-memory corpus index go.
- The live preview's large-note path (no offstage preload, no re-prepare
  after each pause, the lazy reveal on toggle) also applies to notes over
  100,000 code units, not only over 3,000 lines (S5 (h)).
- A deleted note's chunk bodies are deleted (D13); the empty body stores
  zero chunks (`chunkCount` 0, was clamped to 1); a no-op save stamps
  nothing (S4).
- Positions are gapped and per kind; a reorder writes the moved rows only;
  undo history counts units (D9).
- The calendar bloc trusts a current cache on sync and page returns; sync
  reloads only touched tables; alerts re-plan on presence changes only when
  a report digest is enabled.
- A tombstoned note's chunk bodies are deleted; the chunk and outbox
  indices change; an upgrade shows a screen while it runs (D13).
- The `.db` share is a snapshot (D11); zip export and import stream.
- Counter values carry a per-replica ledger (D8 A); per-note values die
  with their note.

## 7. Facts from the tree and the retire list (2026-11-07)

Re-grep before editing; line numbers move.

| Area | Entry points |
| --- | --- |
| Note on the wire | `lib/services/sync/tables/notes_binding.dart` (`encode` loads the body; `decode`; `contentOf`); `lib/database/crdt/synced_tables.dart:50-71` (`content_chunks` `travelsWithParent: true`); `lib/services/sync/sync_tables.dart` (pull order); `lib/services/sync/sync_gateway.dart:18-58` (`SyncEnvelope`), `:259` (`pullPage`) |
| Pusher / engine | `lib/services/sync/sync_pusher.dart:15-27` (900,000; 8 MiB; 20 refused), `_prepare`, `_byBytes`, `_isolate`; `lib/services/sync/sync_engine.dart:117-137` (timings), `:320` (schema reported), `:458` (outbox trigger), `:536-553` (drain on background), `:740`, `:1011` (`appOutdated`), `:946-960` (debounce), `_staleTables`; `lib/services/sync/sync_scheduler.dart` |
| Gateway / rules | `lib/services/sync/firestore_sync_gateway.dart:59` (persistence off), `:139` (`runTransaction`), `:160-190` (pull pages), `:327-350` (signal listener), `:451` (`pullOverlap`), `:562-585` (space merge, `schema`); `firestore.rules:178-222` (spaces, `syncedTable()`, `validEnvelope`), `:193` (`schema >=`) |
| Puller / outbox / merge | `lib/services/sync/sync_puller.dart` (`:221-235` all-skipped page, `:358` conflict), `lib/database/daos/sync_outbox_dao.dart:28` (`pending`), `:111` (`requeueAll`), `lib/database/tables/sync_outbox_table.dart:32`; `lib/database/daos/note_dao.dart:965-1050` (`mergeNoteDocument`; `:987-1000` the copy condition; `:1033` `keptLocal`), `:1230` (`_indexMergedBody`); `lib/database/crdt/crdt_merge.dart`, `crdt_write.dart`; `lib/services/sync/app_sync_apply_hooks.dart` (`:213` `fileConflictCopy`); `lib/services/sync/sync_space_service.dart:329` |
| Chunk store | `lib/database/daos/content_chunk_dao.dart:49-89` (`loadContent`), `:90` (`loadContentForNotes`), `:141-268` (`writeChunks`, `_splitRaw`), `:305` (`replaceChunks`); `lib/database/tables/content_chunks_table.dart`; `lib/utils/compression_utils.dart`; `lib/constants/app_constants.dart:60-70` (cache sizes, 10,000, 5,000) |
| Save path / editor | `lib/services/auto_save_service.dart:85-86`; `lib/database/daos/note_dao.dart:288-347` (`updateNote`), `:348-375` (FTS upkeep); `lib/pages/optimized_note_editor_page.dart` (`:1022` load path); `lib/bloc/optimized_note/`; `lib/services/note_money_ledger_service.dart` (`_onNoteChange`, `refresh`); `packages/re_editor/lib/src/_consts.dart:6` (undo 200); the fork's find and stats code; `lib/repositories/note_repository.dart` (LRU, change stream) |
| Search | `lib/services/folder_search_service.dart:464` (300), `:480` (`_staleRebuildThreshold`), `:559-585` (`buildIndex`, `compute`), `:696` (`quickSearch`); `lib/bloc/search/`; `lib/database/daos/note_dao.dart:870` (`fullTextSearch`); `lib/database/database.dart:386` (`rebuildFtsIndex`); `lib/database/migrations/database_indexes.dart:316` (`notes_fts`) |
| Browser / positions | `lib/services/mixed_reorder_service.dart` (`reorderMixed`), `lib/services/note_position_service.dart`, `lib/services/move_coordinator.dart`, `lib/services/move_history_service.dart`, `move_history_store.dart`; `lib/database/daos/note_dao.dart:703` (`reorderNotes`), `:723` (`setNotePositions`), `:1296` (`moveNote`); `lib/database/daos/folder_dao.dart` (~730-770 cascade) |
| Calendar | `lib/services/calendar_event_service.dart` (`_cache`, `_load`, `upsert`, `deleteById`, `restoreCascade`, `:400-446` child refreshes); `lib/database/daos/calendar_event_dao.dart:36` (`getAll`), `:322` (`getByIdsIncludingDeleted`), `:363`; `lib/bloc/calendar/` (`CalendarPageLoaded`, `_onExternalChange`); `lib/pages/calendar_page.dart:615` (Keep gate); `lib/pages/calendar_overview_page.dart` (`_take`, `_forgetMarked`); `lib/services/event_occurrence_service.dart`, `event_presence_service.dart`, `event_skip_service.dart`, `event_alert_service.dart` (`_load`); `lib/services/alert_scheduler.dart:1077`; `lib/services/calendar_report_service.dart`; `lib/constants/alert_constants.dart:38-68` |
| Storage / lifecycle | `lib/database/migrations/database_schema.dart:4` (`currentVersion = 45`), `database_migrations.dart:1793`, `database_indexes.dart`; `lib/database/database.dart:296`; `lib/database/database_lifecycle.dart:54-85` (`generation`); `lib/services/database_manager.dart:196-215` (`listDatabases`), `:250-263` (`importDatabase`), `:430` (`checkpoint`); `lib/main.dart:267` (launch sweep); `lib/core/di/injection.dart` |
| Backup | `lib/services/import_export_service.dart:371` (export walk), `lib/services/backup_service.dart:326` (`SharePlus` direct), `:331`, `:400`; `lib/pages/onboarding_page.dart:169-191`; `lib/pages/database_settings_page.dart` |
| Counters | `lib/database/daos/counter_dao.dart:542-567` (merge), `lib/services/counter_service.dart` (`_scheduleDirtyFlush`, `applyCount`, `:539-560` export); `lib/services/sync/tables/counter_values_binding.dart` |
| Tests that pin today | `test/database/query_plan_test.dart`, `query_count_test.dart` (`:692`), `volume_benchmark_test.dart`, `note_fts_test.dart`, `sync_outbox_test.dart` (`:242`, `:852`), `sync_outbox_requeue_test.dart:104`, `schema_parity_test.dart`, `upgrade_chain_test.dart`, `connection_pragmas_test.dart`, `note_merge_test.dart` (`:84-88`, `:609`), `crdt_write_guard_test.dart:66`; `test/services/sync/` (`sync_engine_test:899-912`, `sync_engine_failures_test:323/856/880`, `sync_engine_lifecycle_test:960`, `sync_pair.dart:155-161`); the five search suites and `index_invalidation_test`; `dart_test.yaml:7-9` (the `benchmark` tag) |

**Retire list** (dead today; each slice deletes what it names):
`BackupService.exportToFile`, `shareBackup`, `exportAllData` (no callers
outside the file; `shareBackup` bypasses `shareExport`); `lib/utils/
isolate_worker.dart` (no callers); `NoteDao.hardDeleteNote`,
`FolderDao.hardDeleteFolder` (no callers); `ContentChunkDao.getChunk`,
`getChunkCount`, `getChunksSince`, `mergeChunk` (no callers);
`NoteStorageService.deleteNotesInFolder` (no callers); the `fullTextSearch`
chain and `notes_fts` (S12); `SearchIndex` and the corpus `buildIndex`
(S12); the dense `reorderNotes`/`reorderFolders` chains and
`mergeByPosition` (S17); `_byBytes` (S10); the ARB key `largeNoteWarning`
(unused in `lib/`); the sync pusher's in-memory `parked` map as the only
record of a park (S7/S8).

## 8. Slices

### 8.1 The table

| Slice | Phase | What | Size | Depends on | Record | Skills | Agents |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | 0 | wire version decoupled (D3) | S | — | §5.1 | anta-context, drift-migrations | implementer, reviewer |
| S2 | 0 | surrogate-safe chunk cuts | S | — | §5.1 | drift-migrations | implementer, reviewer |
| S3 | 0 | scale fixtures, pins, benchmark tier | M | S2 | §5.1 | verify, flutter-principles | implementer, reviewer |
| S4 | 1 | content-defined chunks + hash (v46) | L | S1, S3 | §5.2 | drift-migrations, markdown-engine | implementer, reviewer |
| S5 | 1 | editor per-save / per-pause work | M | S3 | §5.2 | markdown-engine, flutter-principles | implementer, reviewer |
| S6 | 2 | chunked sync (D1 A) — two sessions | XL | S4, S9, rules deploy | §5.3 | anta-context (sync), drift-migrations, l10n | implementer, reviewer, owner's device check |
| S7 | 2 | held-back rows named, pushMaxWait (D10) | S–M | S8 | §5.3 | ui-language, l10n | designer, implementer, reviewer, design-reviewer |
| S8 | 3 | conflicts (D4) | M | S3 | §5.4 | anta-context (sync) | implementer, reviewer |
| S9 | 3 | runs and rebinds, equal-stamp ack | M | S3 | §5.4 | anta-context (sync) | implementer, reviewer |
| S10 | 3 | paging and slow links | M | S3 | §5.4 | anta-context (sync) | implementer, reviewer |
| S11 | 4 | body index (D5) | L | S1, S3 | §5.5 | drift-migrations, anta-context | implementer, reviewer |
| S12 | 4 | quick search on the index, `notes_fts` retired (D6) | M | S11 | §5.5 | anta-context, l10n | implementer, reviewer, qa-runner (browser pass) |
| S13 | 5 | window index | M | S3 | §5.6 | calendar-events | implementer, reviewer |
| S14 | 5 | targeted maintenance + scoped sync reloads (D7) | M | S13 | §5.6 | calendar-events | implementer, reviewer, qa-runner (calendar + alerts) |
| S15 | 5 | alerts launch fast path (optional) | S | S14 | §5.6 | calendar-events | implementer, reviewer |
| S16 | 6 | storage v47 (D13) | M | S1 | §5.7 | drift-migrations, ui-language | implementer, reviewer, designer (screen) |
| S17 | 6 | lists: splice + bulk move, then gaps (D9) | M + M | S3 | §5.7 | anta-context, drift-migrations | implementer, reviewer |
| S18 | 6 | backup streaming, `.db` snapshot share (D11) | S–M | — | §5.7 | anta-context | implementer, reviewer |
| S19 | 6 | import verification | S–M | — | §5.7 | anta-context, ui-language, l10n | implementer, reviewer |
| S20 | 6 | counters: tombstone with note, PN-counter (D8) | M | S1 | §5.7 | drift-migrations, anta-context | implementer, reviewer, qa-runner (browser pass) |

Migrations in this plan, as built: v46 (S4's `content_hash` + index), v47
(S16's indices and purge), v48 (S11's body-index tables, written as v47 in
its worktree and renumbered at merge), v49 (S20's counter columns); the sync
version bump to 46 in S6 only.

### 8.2 As built

Each slice's note: what shipped, the deviations from §5 and why, every
review finding and how it was resolved, what could not be verified, the pins
flipped with their new values, the commit (written by the owner).

**S1 + S2 — built 2026-11-07 (one implementer, one reviewer), uncommitted.**
S2: `_splitRaw` steps the cut back one code unit before a high surrogate
(`replaceChunks` shares it, so the pull side is covered); eight tests in the
new `test/database/content_chunk_dao_test.dart` in two layouts (pairs at
9,999/19,999 and 9,999/19,998), all red at HEAD (`Differ at offset 9999`,
U+FFFD in the stored chunk), green after. S1: `DatabaseSchema.syncSchemaVersion
= 45` beside `currentVersion`, reported by `SyncEngine.getInstance` and
`SyncSpaceService.createSpace`; the pusher's gate and `pushBatch(schema:)`
read the engine's `_schema`, so they follow; the `_wireKeys` snapshot (18
key sets, one per synced table, tombstones asserted `data == null`) runs
inside the live-row tests of `sync_codec_test.dart` through `expectWire`;
six test pins renamed from `currentVersion` to `syncSchemaVersion` (values
unchanged); one bullet in the anta-context sync reference. Deviations: the
S1 tests live in `sync_codec_test.dart`, whose full-column fixtures decide
which optional keys (e.g. `ownerId`) appear, rather than in a new file. Review
(no blocker): F1 — with both constants at 45 nothing yet proves the two call
sites use the sync version; the pins start to bite at the first v46
migration (S4), accepted. F2/F3 — the snapshot catches a key change but
cannot force the bump, and value-shape changes under a kept key are wire
changes too; the reference bullet now says so. F4 — the corruption also
happens uncompressed (SQLite binds text as UTF-8); the `_splitRaw` doc and the
test header now say so; the `isHigh`/`isLow` assertions in the test cannot
fail (the U+FFFD check does the work), left in place. F5 — two files were
already LF at HEAD, cosmetic. F6 — the `///` references to this record hold
once the record is committed with the slice. Also confirmed by the review:
`chunkCount` metadata (`ceil(length / 10000)`) can now be one lower than
the stored chunk count; every reader loads by stored chunks, only the
developer-option stats strip shows it — S4 derives it from the stored
chunks. Gate: `dart analyze lib` clean, whole suite 13,929 passed / 12
skipped (`04:55`), format clean. Ready commit: `sync: the space carries a
wire version apart from the Drift schema, frozen by a snapshot; chunk cuts
never split a surrogate pair` over the 12 changed files plus this record.

**S3 — built 2026-11-07/08 (one implementer, one reviewer), merged into the
main tree, uncommitted.** Tests and test support only. `test/support/
scale_fixtures.dart` (`bigBody`, the three edit helpers, `maxDocumentBytesToday`
= 900,000 and `maxBatchBytesToday` = 8 MiB with a `///` to
`sync_pusher.dart:18/23`); six exact default-suite pins, each under 1 s:
`note_body_write_budget_test` (a one-character save: UPDATE "content_chunks"
10 / 6 / 1 at 100,000 code units top / middle / end, 30 / 16 / 1 at
300,000, 0 INSERT, 0 DELETE — the baseline S4 flips), `sync_note_apply_budget_test`
(the receiving device: 1 DELETE + 11 / 31 INSERTs), `sync_note_wire_bytes_test`
(106,727 bytes for a 104,199-byte body, pinned within [body, body + 4 KB]
— S6 flips), `sync_document_park_test` (a 900,000-unit note is parked, the
gateway sees no envelope, the batch's other rows push — S6 removes the cap),
`sync_batch_shape_test` (ceil(pending / 3) at maxBatch 3),
`folder_search_build_index_loads_test` (60 body loads cold — S11 flips).
Benchmark tier (`--tags benchmark --run-skipped --concurrency=1`):
`big_note_benchmark_test` (open / save / remote apply at 100 KB–3 MB on
memory and on a file with the production pragmas for the local half),
`sync_volume_benchmark_test` (300 folders, 5,000 notes, 20,000 events through
`SyncPair`), `volume_benchmark_test` gained a (20,000 events, 10 years)
tier and `buildIndex` at 500 / 5,000. **Baseline (this machine):** save of a
3 MB note on file 376 ms, its remote apply 434 ms (second run 271 / 277 ms);
open 3 MB 21 ms; `buildIndex` 5,000 notes 981 ms (small bodies); reading
20,000 events 395–782 ms, skips 874 ms, occurrences 866 ms; the initial
sync of 25,300 rows: push 6.9 s in 51 batches, pull 26–52 s (without the
production pragmas, pessimistic). Deviations: `editNearTop` inserts at
offset 10,100 (the second slice) because S2's step-back aligns the first
boundary and an insert there would hide the shifting cost the pin exists
for; the planned gate-timing summariser was dropped — the verify skill's
suite line now carries the measured figure (13,929 tests, about 5 min on
Windows) instead. Review (no blocker): the `SyncPair` file databases run
without the production pragmas and their benchmark labels say otherwise
(fix: an optional `setup:` on `SyncPair.open` and honest labels); the
batch-shape pin derives its expectation from the run (make it `pending ==
10`, 4 pushes, with a reason); the park test's reason names S7 although
only S6 flips it; the apply pin leaves UPDATE unpinned (S4 pins all three
verbs); the fixture doc overstates the per-boundary step-back after S2;
`chunkCount` omits production's clamp (empty bodies only); the volume
benchmark's new group installs the test binding inside `setUpAll`. These
land in a small follow-up once S4 releases the main tree. Also noted: after
S2 the stored `chunkCount` can disagree with the stored chunk number — S4
derives it from the stored rows.

**S4 — built 2026-11-08 (one implementer, one reviewer, one fix pass, one
re-review), in the main tree, uncommitted.** Migration v46 (local-only;
`syncSchemaVersion` stays 45): `content_chunks.content_hash TEXT NULL` behind
a column guard and `idx_content_chunks_hash`, created by the step and by
`createAllIndexes`. `lib/database/chunking/`: a normalized content-defined
cutter (minimum 4,096, target 8,192, maximum 16,384 code units; a 32-bit
Gear hash over the last 32 code units with a frozen xorshift32 table; the
top 15 bits must be clear below the target and the top 11 above it; when no
cut appears before the maximum the chunk ends after the smallest hash
between target and maximum, so low-entropy text still cuts on content; never
after a high surrogate), `ChunkHasher` (SHA-256 over the UTF-16 code units
as 2-byte little-endian — lone surrogates hash distinctly — 64 lowercase
hex, frozen: it becomes S6's document id; `abc` →
`13e228567e8249fce53337f25d7970de3bd68ab2653424c7b8f9fd05e33caedf`,
verified independently), `BodyCut` (cut + hashes, in `Isolate.run` above
65,536 code units), `ChunkPlanner` (common prefix and suffix by hash, one
arithmetic `chunk_index` shift, hash matches as `chunk_index`-only UPDATEs,
uuid ids for new rows, legacy ids kept). `ContentChunkDao`: `prepareBody`
before the transaction (for a legacy note it reads the stored text and
encodes the new chunks off-isolate), `planWrite(prepared:)` reuses it only
when the live rows' `id|index|hash|hlc` signature is unchanged, `writeChunks`
compares hashes and never decompresses, `replaceChunks` runs the same
planner and returns the stored count; an undecodable legacy slice counts as
changed and is replaced; gzip above 5,000 chars stays; `defaultChunkSize`
and `_splitRaw` are gone (`AppConstants`' duplicates too; the one source is
`ContentChunkDao.compressionThreshold`). `NoteDao`: `createNote`,
`importNote` and `updateNote` take `chunkCount` from the cut (the parameter
is ignored when content is given); `updateNote` plans first and stamps and
queues only when the text or a passed column changed (a no-op save writes
nothing — the house rule in `crdt_write.dart`); a stale `chunk_count` is
corrected without a stamp; `mergeNoteDocument` cuts lazily, only in the
insert and overwrite branches (a kept-local or unchanged pull performs no
cut); the empty body stores zero chunks. `CompressionUtils.shouldCompress`
takes the length shortcut. `crypto` is a direct dependency. Pins flipped:
`note_body_write_budget_test` 10/6/1 and 30/16/1 UPDATEs → 0 UPDATE / 1
INSERT / 1 DELETE for every edit position at 100 K, 300 K and 3 M;
`sync_note_apply_budget_test` 1 DELETE + 11/31 INSERTs → 0/1/1; new pins: a
no-op save changes no HLC, version, `updatedAt` or outbox and writes no
statement; a kept-local pull is never cut; `query_plan_test` covers the
`planWrite` SELECT and the shift UPDATE; a seeded randomized round trip
(`content_chunk_round_trip_test`: 150 edits up to 600 K then 30 remote
applies, `loadContent == text`, indexes exactly 0..n-1, hashes equal the
decoded text, no stray rows). Distribution after normalization: a
one-character insert changes 1 chunk in 300 of 300 random texts; a 100 K
`| --- |` table 1–3 of 12 (every chunk before); `'a' * 100000` 2 of 12.
**Benchmark (this machine, best of three, ms):** save of a 3 MB note on
file 376 → 52; its remote apply 434 → 73; 900 K save 112 → 18; 100 K apply
70 → 29; open unchanged. Review: no data-loss or corruption finding (the
round trip under adversarial and random edits, the hash, the migration and
the stamp rules all confirmed); the first review's cost items (the cut
inside the puller's page transaction, the maximum-forced cascades, the
legacy first save inside the transaction) and the recoverability item
(undecodable slice) were fixed in the pass. Deviations: the gzip hop stays
inside the transaction for a create or a remote insert over 64 K (no stored
rows to plan against; not the typing path); `isCompressed` keeps its
meaning; backup restore passes `chunkCount: 1` and the DAO stores the real
count; `mergeChunk` still inserts remote chunks without a hash (legacy,
re-cut on the next save). Noted, not fixed: the new files are LF; the
`edited` check compares `preview` and `isCompressed`, so a restored note can
stamp once on its first unchanged save. The re-review of the fix pass
confirmed every fix by probe (cutter bounds, surrogate safety, determinism
and cross-isolate equality; the three changed-chunk figures; the lazy merge
cut; the prepare/plan re-check; the heal; the unstamped count correction; the
new pins) and left four low notes: the prepare's signature reuse relies on
every chunk write changing the row's HLC (a `///` line, and `mergeChunk`'s
retirement, go into S16); a DELETION can cascade further than an insert under
normalized cutting (1 chunk in 226 of 300 random deletions, up to 8 in 2 —
the docs should say so, S16); `prepareBody` adds one cheap SELECT per save
(accepted); `BodyCut.cutCount` is a `@visibleForTesting` static (accepted).

**S9 — built 2026-11-08 (one implementer, one reviewer, one fix pass, one
re-review), merged into the main tree, uncommitted.** The equal-stamp ack:
`CrdtMerge.mergeRemoteRow`'s `unchanged` branch calls `ackThrough(table,
rowKey, localHlc)` inside the merge savepoint, never for the seed stamp, so
a rebind, a restore-then-bind or a Merge of identical data pushes nothing
(except seed-stamped built-in rows, by design). The device id stays out of
Android backup: `android:dataExtractionRules` (`cloud-backup` and
`device-transfer`) and `android:fullBackupContent` exclude `root`
`app_flutter/gym_notes/device_id`; a guard test reads both files and the
manifest. The quota pause says when it ends: `SyncStatus.quotaPausedAt`
from the stored `quota_paused_at`, `quotaResetAfter(now)` the next midnight
in America/Los_Angeles (`lib/utils/sync_quota_reset.dart`, DST probed), the
retry at `min(1 h, reset + 5 min)`, copy `syncPausedQuotaUntil` /
`drawerSyncPausedQuotaUntil` while the reset is ahead and the reason-only
`syncPausedQuota` / `drawerSyncPausedQuota` after it, en/de/ro. The
signal-driven resume: only the tables the signal names, a full run after
`resumeSnapshotWait` (5 s) without a snapshot and at least every
`fullPullInterval` (24 h, `full_pull_at`); a resume that finds a pause or
failure waiting runs in full (it stands in for the retry it cancels);
`pull_seen` stored as a max; `_loseAccess` cancels the fallback. The settled
overlap, as built (this supersedes §5.4's wording): at the END of a complete
table pull, if the server time seen BEFORE the pull began (the max of the
live signal's `touched` values and the persisted `server_seen`) stood at
least `pullOverlap × settledOverlaps` (10 s × 6) past the cursor's time, the
pull stores `pull_settled.<table>` = that cursor; the next pull resumes
exactly only when the stored cursor equals the mark and the table's live
`touched` is not past the cursor; a cut walk writes no mark; bind and unbind
clear the marks, `server_seen` and `full_pull_at`. The safety argument: every
write stamped at or before the cursor committed at least 60 s before that
pull read, under the record's stated receive-to-commit bound; `touched` is
written with `serverTime` in the push's own transaction (a `///` on
`spaceMergeOf` says the proof depends on it). Counters on `SyncRunReport`
(rows and bytes pushed, pages, attempts, resume fallbacks, duration — no
pulled-bytes counter, which would need a second encode), one `[SyncEngine]
run …` line per run in debug builds, an injectable clock
(`SyncEngine.detached(now:)`) for the quota and full-pull times. The
gateway interface gained `resumeOverlap` and `cursorTime`. Pins: the
merge contract's "same stamp" case allows only `DELETE FROM "sync_outbox"`
plus three new contract cases; the quota retry pinned exactly under a pinned
clock; the drawer and section quota strings follow the new keys. Review: no
data-loss finding; the first review widened the exposure concern (hence the
×6 margin), found the `_loseAccess` fallback leak, the stale-run
`full_pull_at`, the quota time computed at render, the counter's re-encode
and the stale reference lines — all fixed; the re-review confirmed them.
Left for S10 (same files): a test for the stale-run `full_pull_at` refresh,
a Sync-page widget case for the "Paused until" form, a comment wrap, the
reference's field list. Not verified: the real Firestore quota reset time
and a device run of Auto Backup (the owner's checks). Noted: after an Auto
Backup restore the device mints a new id while its rows keep the old one
(intended); installs cloned before this slice keep a shared device id.

**S10 — built 2026-11-08 (one implementer, one reviewer, one fix pass, one
re-review), merged into the main tree, uncommitted.** A typed
`SyncGatewayException.timedOut()` (still an offline failure to the engine)
raised by a Dart `TimeoutException` and by Firestore's `deadline-exceeded`;
only the `pullPage` call is timed. Per-table pull pages
(`SyncTableBinding.pullPageLimit`: `NotesBinding.pageLimit` 50, the rest the
gateway's 499); a pull timeout halves that table's page
(`SyncEngine.pullTimeoutDivisor` 2, a second in a row
`repeatedPullTimeoutDivisor` 4, floor 1), the sizes reset only at `start()`
because a slow link usually lasts. The push: `_prepare` encodes in queue
order and stops at the budget, returning the prefix (at least one row) and
leaving the rest queued, so memory is one part plus one row; `_byBytes` is
gone; `firstPartBytes` 2 MiB, `minPartBytes` 1 MiB, `maxBatchBytes` 8 MiB
as the ceiling; the budget grows after a full part and halves on a timeout
(capped at the halved size until the outbox empties); `minPartSpacing` 1 s
only after a part cut by bytes, the timer kept and cancelled by `stop()`;
the 900,000 park unchanged. The overlap re-read: the scan position lives
ONLY inside one walk (`pullPage(scan:)`; two pure helpers `queryStart` /
`scanAfter` on the Firestore wire), so a walk cut by a timeout re-reads
the window from its start on the next run — the first design persisted the
scan across runs and the review proved it broke S9's settle proof (a write
received inside the first part of the window but committed after the cut
run was skipped for good). Pins: `sync_engine_failures_test` "a drain cuts
its batch at about 8 MiB" [10, 1] → [3, 4, 4] with two spacing waits; the
notes page 50 / folders 499; a 900 KB document pulls on a modelled
0.25 Mbit/s link after three halvings; a crowded window is re-read to its
end in one run with each document once and the cursor never back; the
reviewer's late-commit probe as a pin; the stale-run `full_pull_at`
refresh; two Sync-page cases for the live "Paused until" form and its
fallback. Benchmark: the 25,300-row initial push 6.9 → 3.5 s. Review: one
HIGH (the persisted scan) fixed; low notes recorded: an unsettled table's
whole-window re-read can cost about one window of reads per run during a
peer's 499-row bulk upload (the settle rule stops it after 60 s; the budget
table decides a cap); the floors (a page of 1 for a document the link cannot
carry in 60 s blocks the run — S6's chunked wire removes the big documents);
a `timedOut` inside the refusal bisect does not halve; one-row parts re-read
row metadata per part; a learned page size lasts the process.

**S13 + S14 — built 2026-11-08 (one implementer, two reviewers, two fix
passes, two re-reviews), merged into the main tree, uncommitted.** S13:
`EventWindowIndex` (lib/services/event_window_index.dart), memoised per
list object through an `Expando`, buckets one-time events by the UTC month
of their start day (a one-time event occurs only on its start day;
`endDate` only cuts it off) and keeps every rule in one recurring list;
`eventsPossiblyIn(from, to)` returns both in input order; `occursOnUtcDay`
stays the sole arbiter; `occurrencesInRange` iterates it, so the overview
runs, the upcoming agenda, `DigestPlanner.plan` and the report scans narrow
through it; the bloc's out-of-window and filtered `allEventsForDay` paths
use it; both day caches are capped at `CalendarCacheLimits.maxDayCacheEntries`
(512), evicting the oldest out-of-window day, never a window day; the
report groups its scope once; the sync hook's `events` entry reloads only a
live or half-built instance (`CalendarEventService._creating`,
`_reloadLive`). S14: `CalendarPageLoaded` props list the revisions first;
`RefreshCalendarView({refreshLedger})` (a fresh list identity, both
revisions bumped, no read) replaces `LoadCalendarEvents` on the nine page
returns; `notifyExternalChange({cacheCurrent, eventsMerged})` — the bloc's
light path emits from the service with no read when the cache is current and
refreshes the money ledger only when events merged; `_load()` reports
failure (`lastLoadFailed`) and keeps the previous cache; the apply hooks
gather tables per run through paired `beforePage`/`afterPage` (`_openPage`),
reload only the services whose tables merged (categories always, templates /
presets / views only when live), re-plan alerts on a presence or profile
change only when a report digest is enabled (`AlertScheduler.reportDigestEnabled`,
the one rule), and patch pulled events by id through
`CalendarEventService.applyMerged` (one keyed read, in-place when the start
day holds, one sorted merge, tombstones dropped, a full reload above
`CalendarCacheLimits.maxKeyedPatchIds` 500 or on any failure); delete and
restore patch the four child facades in place (`forgetEvent` /
`restoreEvent`, `getActiveForEvent` on the four DAOs) and the undo capture
does four keyed reads; `EventAlertService._load` and `_loadCategories`
build then swap under write counters; `_create` of the event, presence,
occurrence and preset services returns `_instance` first, keeps a
`Completer`-based `_creating`, and an overtaken construction (a reset or a
lifecycle generation change) restarts and hands back the current instance.
**Counts:** a remote presence tap: 11 whole-table reads + a second events
read + a full alert re-plan → 4 selects, no events read, no re-plan without
a report digest; a one-event pull → one keyed read; a delete → one select
instead of four whole child reads; a page return → zero statements. Review:
S13's index, window math, order and cap confirmed; the one race (a pull
during the first construction) closed with a deterministic held-read test;
S14's one regression (a category-alert save committed during a reload's
read was lost by the swap) fixed with a write counter; the run-table
carry-over through the refiled notes page fixed by page pairing. Deferred:
the alert reconcile and the ledger refresh stay O(store) when they run;
presence, skip and description pulls still re-read their whole (small)
table; `FilterPresetService` and the two child services' constructions
across a reset follow the same pattern as the event service now.

**S19 — built 2026-11-08 (one implementer, one reviewer, one fix pass, one
re-review, one touch-up), merged into the main tree, uncommitted.**
`DatabaseManager.importDatabase(…, {progress})` copies the source in 1 MiB
chunks to `<name>.db.import-<ms>` beside the target, with the source's
`-wal` and hot `-journal`; then the injected `verifyImport` (default
`verifyImportFile`, in `Isolate.run`): the header (magic, page size, format
bytes 1 or 2), open read-write never-create with the `-wal` folded and a hot
journal rolled back, `page_count × page_size == length`, `user_version ≤
currentVersion` else `DatabaseImportTooNew`, `quick_check`, ANTA's shape
(`user_version ≥ 1`; `notes`/`folders`/`content_chunks` with the first
schema's columns, plus `is_deleted`, `hlc_timestamp` and `content_chunks.
content_hash` at the current version) else `DatabaseImportNotAnta`; stale
sidecars beside the target deleted before the rename (a foreign WAL would be
replayed over the import); a late Cancel honoured; any failure or cancel
deletes the temp and its sidecars; `sweepStaleImports()` before `runApp`. A
two-phase `AppDialogs.progress` (step lines in an `IndexedStack` live
region, a determinate then indeterminate bar, Cancel with `sheetCancel`
disabled during the check, non-dismissible), shared by the Databases page
and the onboarding restore; four ARB keys. Review: the shape check was too
weak (any file with the three table names passed; fixed with the version
floor and column probes), the hot journal was ignored (fixed), a vacuous
height test (fixed), the late-Cancel window and the stale-sidecar guard
(fixed), the dialog moved into `AppDialogs`; the one red run the implementer
saw was an S18 test racing the loading dialog's exit (its wait fixed). Not
verified: a device run of the dialog and TalkBack on the step change.

**S7 — built 2026-11-08 in the sync worktree after S6 (one designer; two
implementers — the first stopped at its turn cap; one code reviewer and one
design reviewer), merged into the main tree, uncommitted.** **Cadence
(D10):** `SyncEngineTiming.pushMaxWait` = 3 minutes — a second timer armed
by the first write after a drain fires a drain at most 3 min later however
long typing continues, beside the 30 s quiet debounce; both timers are
cancelled at drain start, by `stop()` and by the background leave, and a
write during a drain re-arms both. **Push parks persisted:** a row the push
parks (the rules refused it after the bisect → `refused`; it could not be
encoded — an `ArgumentError`/`FormatException`, a chunk whose text no longer
hashes, a manifest whose chunk was refused → `unencodable`) is stored under
`sync_metadata` `push_parked.<table>.<rowKey>` = `<order>|<stamp>|<reason>`
as S8 stores pull parks; it holds its entry back at or below that stamp, is
released when the row lands or an edit raises the entry past the stamp, is
retried (dropped so the drain tries again; a repeat failure re-parks with a
new order so the rotation advances) for the 100 oldest at every start and
for all on a build change (`push_parked_build`); a park of a table this
build has no binding for survives until a build change; bind and unbind drop
them with the pull parks. Pull-park values gained the reason as a third
field (`awaitingText` for S6's missing chunks — `ChunksMissing extends
FormatException` — else `unreadable`; an old two-field value reads as
`unreadable`). **"Sync now" retries every stored park**, pull and push,
through the start path (the session's pull parks stay strict). **Visibility
(the D14 promise):** `SyncStatus.heldBack` is a list of `SyncHeldItem`
(table, rowKey, kind, name, deleted, reason) built by `SyncStatusService.
heldBack(parks)` — one item per row under the strongest reason
(`awaitingText` > `unreadable` > `refused` > `unencodable`; a pull park is
what holds a push back), a chunk park folded into every note holding the
hash (`ContentChunkDao.noteIdsByHash`) and a manifest park into its note,
names from the DAOs with tombstones flagged (`SyncOutboxDao.tombstonedKeys`
for the other tables), sorted notes by name, folders by name, then the other
kinds, oldest stamp first, cached per park set; `parkedCount` is the
deduplicated item count so the status row's "· n held back" and the list's
header agree. The Sync page (`sync_settings_page.dart`) gains one settings-
kit section appended LAST after Pairing, present only when bound, available
and non-empty, so nothing above it moves when parks come and go: header
`syncParkedCount(n)` (a level-2 heading), one top-aligned `ListTile` per
item — a kind glyph (`note_outlined`, `folder_outlined`, `event_outlined`,
`exposure_plus_1_rounded`, `format_list_bulleted_rounded`, `sync_rounded`)
in `onSurfaceVariant`, the name capped at `FormMetrics.syncHeldBackTitleLines`
(2) or the typed label `syncHeldBackKind`, the localized reason with the
"Deleted · " prefix (`syncHeldBackDeleted`, a Romanian gender select) for a
tombstone, no tap — then after `FormMetrics.syncHeldBackShown` (20) one
"And {n} more" row; no Retry control (Sync now retries); `SemanticsIds.
sharingHeldBackRow(table, rowKey)` and `sharingHeldBackMore`; one semantics
node per row reading name then reason. Seven strings in en/de/ro. Suites:
`sync_held_back_test` (11: a stored push park survives stop/start beyond the
100 retries and holds its entry back; an edit past the stamp releases it; a
new build retries all; a park refused again moves to the back; unbind drops
them; Sync now retries a stored push park and re-reads a pull park's
document; a refused chunk and its manifest give one item with `parkedCount`
1; writes every 10 s for 5 min push once at 3 min; one quiet write pushes at
30 s and cancels the 3-min timer; `stop()` cancels both),
`sync_status_service_test` (precedence, dedupe, the fold, names, the sort,
kinds), `sync_held_back_section_test` (44: 0/1/3/120 items, the cap row, the
PAIRING header's and the status details' y unchanged with and without the
list across light/dark × 1.0/1.3/2.0 × en/de/ro × 360×780/412×915, the
guideline matchers, one node per row, the header level, the ids); the
`crdt_write_guard` allow-list gained `tombstonedKeys` (a read-only select).
Lesson: a geometry pin on a lazy settings list must reveal the element before
measuring — in de and ro at 2.0 on 360 wide the PAIRING header sat past the
built extent, and the first version of the pin threw "0 widgets" instead of
measuring (`SyncSectionRobot.listRect` scrolls to the target and measures in
list coordinates). **Review history and the fix pass.** The code review
found a stuck state — Sync now retrying every stored push park at once, or a
start's 100-park rotation, could trip the 20-refusal `noAccess` pause for
the session (fixed: a retried park's refusal does not count toward
`maxRefusedPerDrain`, which detects a rules change on fresh rows; Sync now
and a start each retry at most the 100 oldest stored parks of either kind, a
build change all; a re-parked key moves to the end so repeated presses
rotate) — a restored chunk park not holding its chunk back in `_chunksFirst`
(fixed: `_holds`), the held-back read inside the status emit's try (now its
own try, falling back to the cached items), an empty list after a gated
start (the engine now reads the stored parks until it has restored them),
"Untitled note" / "An item" for rows this device never merged (now the kind
label; `untitledNote` only for an existing empty title; a chunk park whose
hash no live note holds is left out), the Romanian "Deleted" agreeing only
for notes (`Ștearsă` for category, view and vocabulary too), and a second
stale run when `pushMaxWait` fired inside the debounce run's pull (a
`_drainAhead` guard makes `_drainIfQueued` a no-op while a run is in flight).
The design review found the page jumping when parks cleared while the user
was scrolled to the list (+462 dp at 2.0; fixed: the page keeps every row
seen since it opened, in first-seen order, a row that lands stays in place
with a muted title, a `check_rounded` glyph and the reason "Synced" —
`syncHeldBackSynced(kind)`, a Romanian gender select — while the header
counts the live rows, reads "All synced" (`syncHeldBackAllDone`) with the
intro "Nothing is held back any more." once none is held, and the section
disappears only on the next open; new rows append at the end; the "more"
row reads the live count of unlisted rows still held — `syncHeldBackMoreHeld`
— or "The other {n} were synced" — `syncHeldBackMoreSynced`), nothing
saying what to do (the kit's `intro` under the header: "“Sync now” tries
these again.", quoting each locale's button; the kit now wraps every intro
in its own semantics node so the heading is read first — the fasting and
settings pages gained the same), the counter glyph not the app's
(`pin_rounded`), an unnamed folder titled "An item" (the `folder` kind
label), ids not kebab-case (now `sharing-held-back-<index>`), page search
flooding with held rows (no keywords on them), and missing pins (the landing
geometry, the ro select, every glyph kind, the fallbacks, the "more" row's
alignment — all added). The second code round found the stuck state still
reachable — `restoreParks` deleted a park's stored value at retry time, so an
offline retry turned the rows into fresh entries and the next Sync now
tripped `noAccess`, and the open page showed them as landed (fixed: a park's
stored value stays until an outcome — landed, raised or re-refused under a
new order — `_retried` is rebuilt from what is stored at every restore, and a
row being retried stays listed under its reason), a "neither timer fires"
case after a run halted mid-pull (a swallowed fire re-arms the debounce in
`_run`'s `finally` when no drain ran and no retry is scheduled), the pull
side's session parks starved behind 100 stored ones (the session's parks go
first), and the page's seen-rows set mutated inside `build` (moved to the
bloc listener; cleared when sync becomes unavailable). Recorded, no change: the glyph sits
8 dp high at 2.0 under `ListTileTitleAlignment.top`; row heights run
100–212 dp at 2.0; no saved device flow can reach the section (the QA
database is unbound, parks need a space) — the device-only bucket covers it;
the name sort is `toLowerCase().compareTo` (ș and ä after z); a build with
S8 but not S7 reading S7's three-field park values would hold a key back
until the park clears (downgrade only); the section icon
`sync_problem_rounded` (the kit does not draw it); a renamed held note shows
its old name until the park set changes. Not verified: a device run (TalkBack
on a row and on the header; Android's 200 % scale in Romanian).

**S6 — built 2026-11-08 in the sync worktree (five implementers across
S6a, the S6a finish, S6b and two fix passes; one reviewer, two rounds),
merged into the main tree, uncommitted. `syncSchemaVersion` 45 → 46 — the
one wire change of the round.** **The wire:** a chunk document
`users/{owner}/spaces/{space}/content_chunks/{sha256}` with data `{hash,
gz, length}` — `gz` a Firestore `Bytes` blob of gzip(UTF-8 text), mapped
`Uint8List` ↔ `Blob` in the impure gateway, at most 49.2 KB for the cutter's
16,384-code-unit maximum (3 bytes per code unit plus the gzip frame; the
rules refuse 65,536 and over) — an immutable upsert stamped with the note
write that created it; the note document drops `content` and carries
`chunks: [hash…]` in order and `bodyHash`; a legacy whole-body document
still decodes. Rules: `content_chunks` in `syncedTable()`, `validChunk()`
(`op == 'upsert'`, `data.gz is bytes`, `size() <= 65536`) inside
`validEnvelope()`, the `data` exemption in `firestore.indexes.json`, the
emulator suite and `tool/firebase/rules_probe.ps1` with the chunk cases —
**deployed by the owner before any device installs the build.** **Local:**
`SyncedTable('content_chunks', rowKeySql: 'content_hash', contentAddressed:
true)` with a push-only `ContentChunksBinding` (`pulls => false`; encode
refuses a hash mismatch or an oversized `gz`; static `textOf(envelope)`
inflates and checks length and hash); `queuedRowsSql` keys chunks by their
note's owner (D16: another account's note never ships its chunks, at bind,
at the cutover or on save — the push retires a foreign holder's entry
unsent and holds its manifest back); `ContentChunkDao.applyWrite(…,
inSpace:)` queues one outbox entry per inserted hash that no row of a note
of ours held before (`CrdtWrite.queueChunksIn`, announced as an update so
it arms no second drain) except the hashes the manifest the body came from
already names, and retires a hash's entry when a save deletes its last live
row (`retireChunksIn`); `hashLegacy` re-cuts a legacy fixed-slice note
lazily inside the notes `encode` under the note's own stamp (one short
transaction per legacy note during the cutover's drain) and updates
`chunk_count`; `BodyCut.wellFormed` maps a lone surrogate to U+FFFD before
cutting and hashing, because SQLite stores TEXT as UTF-8 and the hash must
describe what the row reads back. **Push** (`sync_pusher.dart`): a live
manifest's pending chunk entries are encoded before it, one at a time while
they fit the part's byte budget and `maxBatch` (the first that does not fit
waits in `_DrainState.chunkAhead`, so each chunk is encoded once per drain);
a manifest goes only after its last chunk, so the space never holds a
manifest without its chunks; the refusal bisect works in UNITS (a manifest
plus the chunks of the batch it names; a refused unit's chunks go first,
bisected among themselves; a manifest naming a refused chunk is parked
unsent — the one realistic trigger is the rules not yet deployed, and then
nothing lands half); `parked` is checked before `pushed`; a chunk entry is
acked at its own stamp (rows sharing a hash carry other notes' stamps).
**Pull** (`sync_puller.dart`): `content_chunks` is never pulled; at the
start of a `notes` page, outside the transaction, `NotesBinding.missingChunks`
collects the hashes the page's manifests name that no live local row holds
(skipping tombstones, legacy documents and merges that read no body),
fetched once each through `readRows(space, 'content_chunks', keys)` in
batches of `SyncGateway.rowReadBatch` (30) with a halt check per call; each
checked by `textOf`; the body assembled in manifest order and checked
against `bodyHash`, then `mergeNoteDocument(content:, inSpace:)` as before —
the merge is unchanged, conflicts under S8's rules; after a manifest merges
(not `keptLocal`) the chunk entries it names are retired, so the second
device pushes nothing the space holds. A chunk the space lacks or that
fails verification fails only that note's merge → S8's durable park with
the reason (`notes: N of M chunks are neither on this device nor readable in
the space`), retried at every start, where the fetch runs too; a chunk row
replaced by a local save between the fetch and the merge is `ChunkRowsMoved`:
the page rolls back and the table retries next run, nothing parked; a
`SyncGatewayException` from the fetch fails the run with back-off, no park.
A page whose missing hashes × the cutter's maximum exceed
`SyncEngine.chunkFetchBudget` (16 MiB) is halved and re-pulled from the same
cursor, down to one note, for that page only. `_readsNoBody` skips the body
only for an equal stamp or for our own newer local row ABOVE the bind floor
— under the floor the older remote wins, so its body is fetched (the first
build emptied the note: edit offline → Stop syncing → Sync again).
`NotesBinding.pageLimit` stays 50. **Cutover:** on the first run with
`sync_metadata.wire_version` below the schema, `_cutOverWire` requeues every
live note's manifest and every live chunk hash once, clears the `notes` pull
cursor and settle mark (one full `notes` re-read — the first phone to cut
over downloads the legacy notes collection whole once; the second re-reads
manifests only; a phone still on the old build that pulled a manifest it
could not decode passed it by for good, and the re-read brings it back),
stores the version once the `notes` table reaches its end, and a drain-only
run holds `notes` back while the cutover is pending; a legacy whole-body
document met at an equal stamp requeues the note (a narrow exception to
S9's equal-stamp ack, terminating after one manifest push), so the space
becomes manifest-only once both devices have cut over; the space `schema`
gate makes a 45 build `appOutdated`. **Measured:** an edit near the top of
a note pushes 2 documents — 2,016 B at 100 K code units, 3,155 B at 300 K,
6,572 B at 900 K, 18,699 B at 3 M, 30,558 B at 5 M (the manifest's hash
list dominates); the 5 MB note's first push 438 documents / 361 KB; B reads
1 chunk per edit, applies the 5 M edit in 192 ms; the 25,300-row fixture
pushes in 11–12 s (30,300 documents, 16.8 MB, 61 batches) and pulls in
13.6–14.9 s (156 pages, 5,000 chunks in 200 calls); the two-device cutover
with the space holding whole-body documents: A pushes one manifest and its
chunks per note, B pushes 0. Suites: `sync_codec_test` 102, `sync_chunk_
fetch_test` (the 300 KB edit ≤ 20 KB; a rename < 4 KB; the 5 MB note across
parts; a shared chunk fetched once; fetched chunks queue nothing; a legacy
document merges and queues; a missing chunk parks and is released by a
planted chunk; a forged chunk parks; a fetch timeout fails the run; the two
floor cases; the cutover on two devices; the moved rows; the lone surrogate
at 100 and 20,000 units; the budget halving), the S10 part pins re-pinned
with incompressible bodies, the manifest-after-chunks capture, the bytes
flip, the park flips, the cutover once per bump, the 46-space gate, the
refusal unit pins, the D16 pins; `test/services/sync` +566, `test/database`
+1101. Review history: round one found the own-older manifest emptying a
note under the floor (data loss), another account's chunks uploaded (D16),
a manifest landing without its chunk under a refusal bisect, the installed
build dropping manifests for good, chunks uploaded once per device, a save
between fetch and merge parking the note, a lone surrogate making a note
unsyncable, the unbounded fetch page, eager encoding, format, docs; round
two found a chunk first held by a foreign note never reaching the space, the
missing order pin, the halved page outliving its page, the cutover's early
store — all fixed. Deviations from §5.3: the durable park replaced the
"body-pending" row; per-id gets replaced `whereIn` and `sync_chunk_cache`.
Not verified: the Firestore emulator rules suite and the probe script (no
emulator in the session); real Firestore `Blob` and size behaviour; the
owner's phones.

**S12 — built 2026-11-08 in its own worktree (two implementers — the first
stopped at its turn cap — three passes; one reviewer, two rounds), merged
into the main tree as migration v50 (`v50QuickSearchIndex`; its v49
placeholder replaced by S20's real step at the merge), uncommitted.**
`notes_fts` is gone: the v50 step drops it with its shadow tables, recreates
`note_body_fts` as `fts5(title, body, tags, tokenize='trigram
case_sensitive 1', content='', contentless_delete=1)` through the shared
`DatabaseIndexes.createBodySearchTables()` when the table lacks a `tags`
column, and clears the ledger so the indexer re-projects every note lazily
(the step reads no body; idempotent; a SQLite without the trigram tokenizer
is swallowed as in v48); `NoteDao`/`FolderDao` lost every FTS upkeep call,
`fullTextSearch` and its repository/service chain are gone, `rebuildFtsIndex`
is gone and Optimize is VACUUM then checkpoint. The projection is `(body,
title, tags)` — tags stored with their `#` (`extractTags(text, cache:
false)`, folded with `normalizeForSearch`), so a typed `#l` becomes the
phrase `" #l"`, three characters a trigram can match. **Quick search** (per
keystroke, 3 statements warm, no `content_chunks` read): a title MATCH
(`title : …`, bm25 then `updated_at DESC`, LIMIT) so a note titled with the
query can never fall out of the cut, then the body MATCH (`{title body} :
"w"` for words of 3+ characters, `title : " w"` for 2-character words, ranked
by `bm25(note_body_fts, SearchConstants.quickTitleWeight 2.0,
quickBodyWeight 1.0, quickTagWeight 0.0)`, ties by `updated_at`, joined to
the ledger by rowid AND note id so a rowid a VACUUM gave to another note
never counts), then the scan of the 300 newest notes' titles and previews
for what the index has not projected yet; duplicates removed, title hits
first (one `QuickQuery` matcher — normalized, trimmed, tags stripped, every
word on a title token, 2-character words at a token start — shared by the
grouping, the scan and the bloc's titles/text split, so a trailing space or
a tag never moves a title hit), cut to the limit. `#tag` narrows both
phases: by prefix at a token start while typing (`#leg` finds `#legday` and
`#legdays`), by whole tag on submit and from a tag tap. A keystroke NEVER
starts a drain: the bloc's `SearchOpened` calls `catchUpIndex()` once (a
drain only when the dirty flag is set), `markActiveDirty()` on save and the
full search's `ensureFresh` stay; `quickSearchWithCoverage()` reports
`incomplete` only while a drain is running and the bloc re-runs the quick
query once on `SearchIndexSettled`, with no notice; a failing index read
(an `unknown` probe included) falls back to the scan with `incomplete` true,
logged once. `probeCapability()` names the `title` column, so a one-column
table left by a refused drop is recreated once. **Measured** (desktop, warm,
one sample): quick `squat` 5.4 ms at 500 × 1.5 KB, 8.7 ms at 5,000 × 1.5
KB, 18.9 ms at 5,000 × 15 KB; `squat bench` 37.6 ms at 5,000 × 15 KB; the
backfill 17.0 s at 5,000 × 15 KB; the FULL search's broad `squat` 11.0 s
there (S12b, §11.1). Suites: `folder_search_service_quick_test` (the
1,000th-newest note's deep word; 2-character title-only; bm25 title above
body; the title hit first over twelve heavier bodies; ties by `updatedAt`;
`#tag` prefix and whole; case- and diacritic-blind tags; a parked drain then
settled; no drain from a keystroke; 3 statements; the bloc's single pass and
its one re-run after a drain), `upgrade_chain_test` (a v49 database loses
`notes_fts` and re-projects lazily; a fresh install has none; the oldest
chain carries legacy `notes_fts` to v50), the parity suite unchanged (48),
`note_fts_test` deleted, `indexedHits()` replacing `fullTextSearch` in three
suites. Review history: the first review found the drain under the typing
path (a real regression — the all-notes page suite hung on the stranded
drain, and every keystroke after a save queued behind a page), a title hit
cut before the regrouping, tag narrowing on one phase only, the grouping
switched off by a trailing space or a tag, the scan not following the index's
2-character rule, a tag matching only once typed whole, a one-column table
undetected, the tag cache thrashed, a failing read emptying the results,
inline bm25 weights, stale docs; the re-review found the dirty-but-idle
double pass — all fixed. Decisions: the `tags` column weighted 0 narrows
without ranking; a tags-only query lists everything under "In text"; a
single-letter query finds nothing on the quick path, as on the full; the
scan is case-blind (`caseSensitive` only affects highlights); quick `#legday`
also lists `#legdays` while typing, submit excludes it. Known: a note
renamed by a sync pull with an old `updated_at` is a stale quick hit until a
drain runs; the page suites inject the inline indexer and build it in
`setUpAll` (no page suite runs during a drain). Not verified: a device run;
the whole-suite gate ran green after the merge (14,554).

**S20 — built 2026-11-08 in its own worktree (one implementer, three
passes; one reviewer, two rounds), merged into the main tree as migration
v49 (`v49Counters`; its placeholder v48 replaced by S11's real step at the
merge), uncommitted.** **Values die with their note:** `NoteDao._tombstone`
cascades the note's live values by `note_id`; `softDeleteNotesWithChunks`
and `FolderDao.softDeleteFolderWithDescendants` cascade by the transaction's
stamp (4 variables for 33,000 notes); one set-based `UPDATE … RETURNING`
plus `enqueueMany`, in the same transaction, same stamp and `deleted_at`;
the bulk-delete statement pin moved from 4 to 6; `idx_counter_values_note
ON counter_values(note_id) WHERE is_deleted = 0` serves the cascade (plan
pinned). `CounterDao.applyCount` writes nothing for a per-note value whose
note is tombstoned (one PK read), so a pending 300 ms flush cannot resurrect
it; `sweepOrphanValues()` runs in `SyncPuller` after every COMPLETE pull,
never while `bind_merge_pending` is set, and tombstones only values stamped
below their note's tombstone, under the note's own stamp, device and
`deleted_at` (a fresh stamp would beat a value another device wrote after
the delete on a note its newer edit revives — the review's probe lost the
count on both devices); the v49 step sweeps once by the same rule in frozen
SQL; the export (`getAllValues`) skips values of tombstoned notes. **The
PN-counter (D8 A):** `counter_values` gains `epoch_hlc`, `epoch_value`,
`shards` (`{replicaId: [p, n]}` as JSON with sorted keys); `value` always
equals `epoch_value + Σ(p − n)` (`PnCounterState` in
`lib/database/crdt/pn_counter.dart`: tap, a commutative join, the strict
readers); the migration makes every row the epoch of its own last write
(`epoch_value = value`, `epoch_hlc = hlc_timestamp`, no shards) so no number
changes. Writes: a tap adds |d| to this replica's p or n; an absolute write
(reset, typed value, restore, a counter's first value) starts a new epoch at
its stamp with no shards; a tap with no row starts at the genesis epoch from
the start value so two devices' first taps join; a tap on a tombstoned row
starts an epoch at the tombstone's stamp; nothing is written for a net-zero
change, an absolute equal to the live value, a tombstoned counter or a
tombstoned note. Merge (`mergeRemoteCounterValue` through `CrdtMerge` with a
`join` callback and `MergeJoin` ∈ echo / local / remote / stored, so the
DAO never names the outbox): both live and stamps differ → the greater
`epoch_hlc` wins whole, within one epoch max p and max n per replica, pin
and position from the newer stamp; the local already holds the join →
nothing written when the remote holds it too (echo), the local requeued
when the remote holds less; the remote holds the join → adopted under its
stamp; neither → stored under a fresh stamp raised toward the remote's
(held to the drift limit; convergence does not depend on it) and enqueued;
a tombstone on either side → stamp order; under the floor the remote wins
whole. **The wire** (`counter_values_binding.dart`): `epochHlc`,
`epochValue`, `shards` as optional keys read through `WireFields.nullable`;
an envelope WITHOUT them (an older build) never joins — it merges by stamp
order as an absolute state, so an old build's re-send or echo at an older
stamp is kept out (the review's probe had it wipe 5 → 2) and only a strictly
newer legacy write wins whole (the old LWW cost, inside the update window);
a `value` that does not equal its state's sum parks; `syncSchemaVersion`
stays 45. **The replica id:** `sync_metadata` `replica_id`, minted at bind,
unbind (a healed copy would tap under the original's id), the first tap of a
database that has none, and whenever `replica_id_device` names another
install than this one (an Android backup copies the database file whole but
not the install `device_id`, so a restored phone would otherwise join its
taps with the old phone's as one replica); `DatabaseManager`'s import
verifier drops `replica_id` from an imported file; never derived from
`device_id`; old shards stay in the join. **Backup:** unchanged (the archive
carries `value` maps; a restore is an absolute write under a fresh epoch; old
archives import). Suites: `counter_pn_test` (the join laws probed over
20,000 random triples by the reviewer; the legacy group), `counter_note_
delete_test` (the 33,000-note cascade statement, the sweep rules, the plan),
`counter_pn_migration_test`, `sync_counter_taps_test` (two devices' offline
taps add up; the revive race; the sweep across devices; the incomplete run
and the floor), updates to `query_count_test`, `counter_merge_test`,
`counter_service_test`, `sync_codec_test`, `counter_crdt_test`,
`crdt_write_guard_test`, `upgrade_chain_test`, `sync_binding_service_test`,
`database_manager_import_test`. Review history: the sweep's fresh stamp
(data loss on a revived note), the legacy envelope joined as an epoch (an
echo wiped later taps), the imported file keeping the source's replica id,
the backup-copied replica id, the sweep gated on touched tables, the missing
`note_id` index, docs — all fixed. Known (§11.1): an echo with equal
content and different stamps pushes the local entry once more; two genesis
rows with different start values keep the larger `epochValue` whole; the
mixed-version window's LWW cost. Not verified: a device run; a real Android
backup restore.

**S8 — built 2026-11-08 in its own worktree (one implementer, three passes;
one reviewer, two rounds), merged into the main tree, uncommitted.** The
rule as built amends §5.4's `note_base`: per note, `sync_metadata`
`note_seen.<id>` holds the highest FOREIGN stamp this device has merged for
it, raised (a raise-only upsert inside the page transaction) whenever
another device's version is applied over a local row or inserted live — not
for an inserted tombstone, whose row already records it. On
`MergeResult.keptLocal` (`NoteDao._keptOver`): nothing for a tombstoned
local row that is not a candidate under G, an own-device remote, or a
floored local; otherwise `seen` = the stored value (or the local row's stamp
when the row still carries a foreign version — rows accepted before this
build), and when the remote is live, `remote.hlc > seen` and the bodies
differ with trailing whitespace trimmed, the INCOMING text is filed as a
conflict copy (`MergeOutcome.loserIncoming`, `SyncNoteConflict.incoming`;
the loser is the local row with the remote's title and label, so
`fileConflictCopy` places it in the nearest live folder; the open editor's
claim is never asked, since the page never shows the remote text); the
remote's stamp raises `seen` in every such case. **Decision G:** a foreign
live edit kept out by a newer local TOMBSTONE files the remote text the same
way when `remote.hlc > seen`, by stamp alone (the chunks are gone) — a note
the user deleted comes back as a copy only when a concurrent offline edit
would otherwise vanish. Why `seen` and not a base moved by our own push:
S9's settle-window re-reads re-deliver a lost version minutes later; a base
moved to our stamp would file a second copy. Why recorded at acceptance and
not in the write paths: a bulk write (label, reorder, refile, cascade; S17's
`applyOrder`/`moveNotes`; S20's cascades) re-stamps a foreign row as ours
without a hook, and a later edit then sees "ours" — the review's probe filed
a false copy; one upsert per applied foreign note (500 on a 500-note initial
pull, no body read, no copy) buys every writer at once. `note_seen_space`
(`<ownerUid>/<spaceId>`) keeps the keys across a rebind to the same space
and drops them on a bind elsewhere; `valuesByPrefix`/`deleteByPrefix` use a
key range. **Durable parks:** `SyncPuller.parked` is a key → stamp map, plus
the stored parks `pull_parked.<table>.<rowKey>` = `<20-digit order>|<stamp>`
(a rising microsecond order restored by `restoreParks`), stored and released
inside the page transaction with the cursor; a stored park holds back only
outbox entries at or below its stamp (`holdsBack`, asked by the drain), an
empty-stamp park (an unparseable hlc or a key the gateway skipped —
`SyncPullPage.skipped`) is counted but holds nothing after a restart, and a
park never lowers a stamp; the first pull of each start retries the stored
parks' documents through the new `SyncGateway.readRows(space, table, keys)`
(the Firestore gateway reads in batches of `rowReadBatch` 30, each under its
own deadline) — every park when `SyncEngine.build` (`'$kAppVersion+
$syncSchemaVersion'`) changed or no build is stored, else the 100 oldest
(`maxParkRetries`), the build key written only after a complete pass; a
merged document releases its park, a failing one is stored again with a new
order so the rotation advances, a missing one is released; a gateway failure
ends the retry for the start, logged, and the pull goes on; `_deletePullState`
drops stored parks on bind and unbind. Suites: `sync_lost_edit_copy_test`
(18 cases: the older edit pushed first → one copy on one device and none on
a re-reading run; the lost ack then the echo; the regression healed by the
requeue; an edit on top of an accepted version then its re-delivery; a
label, a reorder, each delete path then a re-read → no copy; G per delete
path; the steady state reads no chunk and writes nothing; trailing-newline
differences file nothing) and `sync_durable_parks_test` (9: survival across
stop/start, the empty stamp, the gateway-skipped key, the build-change
retry with a cut read, the rotation across three starts with stamped and
with unreadable parks, unbind). Review history: the first round found the
bulk-write false copy, the park downgrade, the build key written mid-retry,
the unchunked `readRows` failing every pull, the exact body comparison, the
rebind to another space, the 1-second rotation; the second round found the
empty-stamp parks never rotating and a useless raise per inserted tombstone
— all fixed. Known limits (D4 B, §11.1): the cross-device lost ack gives two
copies; the newer device's drain-before-pull loses the older edit with no
copy; the three-device clock-skew loss; one false copy per row accepted
before this rule. Not verified: Firestore `readRows` against the emulator;
the copy landing in the nearest live ancestor through the engine (pinned at
the hook level only); a floored tombstone on the initial pull (reasoned, not
pinned).

**S15 — built 2026-11-08 in its own worktree (one implementer, two fix
passes; one reviewer, one re-review), merged into the main tree,
uncommitted.** `AlertScheduler.reconcileAll` takes a fast path for the
`launch` and `resumed` reasons only — every other reason (`eventChanged`,
`occurrenceChanged`, `backupRestored`, `ringHandled`, `sync`) runs in full,
because the delete-all and import-wipe sweeps need the pass their hard
deletes ask for. Under `_serialize`, `_nothingCanArm()` asks in order and
stops at the first hit: `AlertRegistrationDao.mayHoldEntries()` (one
statement — a registry row in any state OR the stray marker),
`EventAlertDao.hasEnabled()`, `CategoryAlertDao.hasEnabled()`,
`EventDigestDao.hasEnabled()` (EXISTS on the small tables, read from the
DAOs, never the facades, which nothing may have loaded yet), and last — only
when every table says nothing — the platform's `pendingEntries()` when the
gateway `tracksPending`: any entry naming the active database runs the full
pass. The fast path still takes the gateway's moves (`takeMoves()` →
`_applyMove`, acknowledged with no registry row; this also retries a failed
gateway start) and skips the facade warm-up, the event store load, the
settings reads, the registry sweep, the planners and the stray sweep. The
marker `SyncDao.keyAlertStraysPending` (`alert_strays_pending`, a UUID
value) is written in the same transaction as any registry hard delete that
removed rows (`deleteForEvent`, `deleteForEvents`, `deleteAll`) and cleared
by value once a completed pass has swept — a process death between a wipe
and its own pass would otherwise leave stray alarms armed; it lives in
`sync_metadata` (per database, never synced, not in the JSON backup; it
travels inside a .db share at the cost of one full pass). **Counts:** a
launch with events but nothing armable = 4 `SELECT EXISTS` statements and
one platform listing, no `calendar_events` read, `CalendarEventService`
never constructed, 0 arm-context reads; one registry row, one enabled own or
category alert or digest, the marker, or a platform entry naming this
database each run the full pass. Plans pinned: the registry probe covers on
`idx_alert_registrations_event` with a key seek on `sync_metadata`; the
own-alert probe on `idx_calendar_event_alerts_active`; the category and
digest probes scan their own small tables. 20 cases in the scheduler suite
plus the plan group. Review history: the first review found a database
recreated under an old name ("Delete all data", a delete then a create, an
import onto a deleted name) never sweeping its strays — the alarms rang in
turn and Stop found no row — fixed by the platform check, which also closes
the ring-delete race and a `fired` row dropped by the sweep; the gateway
start no longer retried (fixed: moves on the fast path); a marker value not
unique by construction (UUID); stale docs; missing pins — all fixed; the
re-review found no blocker. Decisions: any registry row counts (after the
last alert goes, launches run in full until the 7-day sweep clears the
settled rows — pinned to come back); digests judged on the stored `enabled`
column; the marker only when rows were removed, cleared by any completed
pass. Known: `pendingEntries()` is unbounded, as the full pass's listing
was; a live snooze or a ring in progress keeps launches on the full pass
until it fires; a launch with an entry lists the platform twice; a listing
the gateway swallowed reads as empty, as it would for the full pass. Not
verified: a device run (the plugin's listing cost at launch).

**S17 — built 2026-11-08 in its own worktree (one implementer across nine
passes, one reviewer across the same; merged into the main tree,
uncommitted).** Positions are gapped int64: `AppConstants.positionStride =
1 << 20`; a new row appends at `nextPosition(max)` — 0 for an empty group,
else `max + positionStride`, a tie instead of a wrap past ±2^61 — on every
create, import and move path. `planGappedPositions`
(`lib/utils/position_plan.dart`) works in keys (the position, negated under
`positionDesc`): the longest strictly increasing run stays put, so one drag
moves one row, and every other run takes even steps between its new
neighbours; with no room the window widens one neighbour at a time toward the
nearer end until its average gap reaches `_widenedGap(m)` = `1 << (2 ×
m.bitLength)` capped at `positionStride ~/ 2` (a larger window must be
sparser), an open end steps by the stride, and while both ends are closed
the whole group is never rewritten; a stored position past ±2^61 respreads
the group from 0; position-only writes leave `updatedAt` alone.
`NoteDao.applyOrder` / `FolderDao.applyOrder(parentId, loadedOrder,
descending, windowAtTop)` run one transaction per kind: read the group's
`(id, position)` in display order, `spliceLoadedOrder` (unloaded rows that
sort above the window stay above it; `windowAtTop` for the first drag after
a title, date or label sort, whose page was never a stretch of the position
order, so what the user saw lands on top), plan, batch-update only the
changed rows under one stamp, `enqueueMany`; the repositories announce only
those ids; `MixedReorderService.reorderMixed` serialises per parent and the
page sends only the kinds the drag changed; `mergeByPosition`, the dense
`reorderNotes`/`reorderFolders` chains and `setNotePositions`/
`setFolderPositions` are gone. `NoteDao.moveNotes` / `FolderDao.moveFolders`
move a selection in one transaction under one HLC with `IN` lists chunked
at 500 (the folder cycle check walks the target's ancestors); duplicate
names follow the single-item rule through `planBulkMove` — each mover's key
is `bulkMoveNameKey` (`trim().toLowerCase()`, empty exempt) matched against
the target's `LOWER(TRIM(col)) IN (…)` and earlier movers — into a
`BulkMoveResult` (`moved`, `duplicates`, `unchanged`); `MoveHistoryService`
counts undo units (`batchId ?? id`) with `moveHistoryMaxUnits` 20 and
`moveHistoryMaxEntries` 2000, the newest unit always whole; `undoBatch`
restores the unit, uses `_firstAvailableFolderId` for a vanished source and
says `moveUndone` only when every item went back. The page keeps the
optimistic order only while `_reorderPending` is set (set when a drop
changed a kind; cleared by the confirming load, a different id set, leaving
selection, or a failed write); drops queue on `_dragChain`, each working out
its flip, rollback point and `windowAtTop` when its turn comes, written even
after the page was popped and discarded only when `_dragEpoch` moved (an
earlier write failed); a failed write puts the flipped sorts back and saves
them before any `mounted` check, then drops the optimistic list and reloads;
a programming error in the chain reaches `FlutterError.reportError` and the
chain carries on. **Measured:** a drag in a gapped 1,000-note folder plans 1
row — pinned at ≤ 3 rows written and 0 `updatedAt` changes in both
directions (the first dense planner of pass 1 wrote 298 rows; HEAD wrote the
50 loaded); 300 dense notes with a tombstone, rows 4 and 5 swapped: 5 rows,
4 statements; a 200-note move: one prepared `UPDATE` run 200 times, ≤ 4
SELECTs, one HLC; 300 drags into one gap: 1,176 rows in total (max 189,
average 3.92; a fixed half-stride bar wrote 3,958); 1,000 random drags over
positions 0..299 with one row missing: average 1.29 rows; a fully tied group
of 300 writes 299 once, then 1 per drag. Suites: `position_plan_test` (19),
`reorder_and_move_dao_test` (21), `mixed_reorder_service_test` (7),
`move_coordinator_test` (5), `move_history_service_test` (6), the page suite
+10 cases (118), pins moved in `query_count_test`, `sync_outbox_test`
(`importFolders` positions `[s, 0, s, s, 2s, 2s]`) and `item_label_dao_test`.
Review history: the whole-group dense renumber and its `updatedAt` churn,
the sort-flip window anchor, a pending-flag leak, half-group rebalances
(replaced by the widened-gap rule), the failed-write sort restore, the drop
queue dying with the page, a swallowing `catchError`, a timed test drain —
all fixed. Deferred: the forward sort save on a flip is fire-and-forget
without a catch; a dense part's heal can still write up to 150 rows once; a
device pass and a large folder on a phone.

**S16 — built 2026-11-08 in the main tree (one implementer, resumed once at
the turn cap; one code reviewer and one fix pass; one design review of the
launch state and one visual fix pass; the design re-check follows),
uncommitted. Migration v47 (`v47StorageHygiene`).** The purge is one
statement over `content_chunks`: the chunks of notes that are not live and
the tombstoned chunks of live notes go, except the tombstoned chunks of a
live note that claims text (`content_length > 0`) but has no live chunk — a
half-applied per-chunk sync of an older build left such rows; their text
reads as empty today but is still on disk and the purge would lose it for
good. It runs while the partial `idx_chunks_note_index` still stands (it
answers that exception's lookup), then the partial index becomes the full
`idx_content_chunks_note(note_id, chunk_index)`, `idx_sync_outbox_order(hlc,
table_name, row_key)` arrives for the row-value keyset resume in
`pending()`, and `idx_notes_folder` / `idx_folders_parent` go (strict
prefixes of the position indexes under the same predicate); the plan is
pinned at one `SCAN content_chunks`. Chunk rows are hard-deleted at
tombstone time on all four paths — single, bulk, the remote merge after the
loser-content read, the folder cascade over its RETURNING ids — the one
deliberate exception to soft deletes; `deleteChunksForNotes` slices its ids
by `AppConstants.sqlIdBatch` (500) because SQLite binds at most 32,766
variables (a 33,000-note cascade failed whole before the fix; pinned at about
0.6 s, and 1,001 ids → 3 statements); `hardDeleteChunksForNote`, the
deprecated `deleteChunksForNote`, `getChunk`, `getChunkCount`,
`getChunksSince` and `mergeChunk` are gone, and `_indexMergedBody` no longer
deletes first (no tombstoned chunk exists after v47); `_seedFromRows` in
`onUpgrade` is gated on no stored `last_hlc`. Pragmas: `journal_size_limit`
is the fifth connection pragma; Android gets `sqlite3.tempDirectory` once
before `createInBackground` (a VACUUM spills to a temp file SQLite cannot
open in Android's default temp dir). Optimize runs FTS rebuild → tombstone
FTS cleanup → VACUUM → `wal_checkpoint(TRUNCATE)` — without the checkpoint
the compacted copy sat in the WAL (main file unchanged, `-wal` 861 KB on a
3.2 MB file; about 520 MB on the owner's 766 MB file) and the page read a
negative delta as "already optimized"; the page now judges "already
optimized" from `reclaimableBytes()` (`freelist_count × page_size`) read
before the run and shows the saved size when positive; the reclaimable
caption is read in the page's first load and always in the tree — a
`FormCaptionSlot` with two sizing twins keeps its height whether the value
is known or not — with `databaseReclaimableUnknown` as the neutral text.
Launch: `openDatabaseForLaunch` runs after `QaBootstrap.beforeDependencies`
and before Firebase; `AppBootstrap.updating()` shows "Updating your data…"
only when `from < to`; `AppBootstrap.failed(error, onRetry:)` shows the
failed state and waits — Retry re-runs the open, a second tap does nothing,
launch continues once it succeeds. The surface is the app's **launch
state** idiom: `AppSystemBars` (moved to `lib/widgets/app_system_bars.dart`)
around the `MaterialApp` builder; a centred 48 dp slot
(`RowMetrics.emptyStateGlyphSize`) that holds the spinner or the error glyph
so the title never moves; `titleMedium`; a next-step line ("Try again, or
restart the app. If this keeps happening, free up some storage space." —
the Databases page cannot be reached while the open fails); the detail as a
selectable text, 4 visible lines, cut at `AppConstants.errorDetailLimit`
(300, shared with `buildAppErrorWidget`), the exception's own words by
design; a tonal Retry; the spinner's `semanticsLabel` in a live region, the
failed title a live level-1 heading; it follows the device locale and
brightness because the user's choices live in the database that is not
open yet. 17 bootstrap cases with the guideline matchers and en/de/ro at
2.0. **Measured:** the v47 purge 7.3 s on the 766 MB fixture (245 MB
reclaimable) with the earlier two-scan form; not re-measured after the
single statement (the benchmark runs 20 min). Review history: the code
review found the cascade regression (F1), the missing checkpoint (F3),
stale merge docs, the stale skill, the two-scan purge and its recoverability
hole, the caption's geometry, leftovers and an S18 load flake — all fixed;
the design review of the launch state found the system bars, the idiom, the
dead end and the raw detail — all fixed. Deferred: the folder cascade binds every
descendant folder id in three statements (a 32k-folder tree, theoretical)
— the selection's own note update was batched by `sqlIdBatch` in the
round's closing sweep, pinned with a 33,000-note selection;
the 41-site `is_deleted` literal sweep waits for a device `sqlite_version()`
probe; the Android `tempDirectory` gate has no test. Not verified: a device
run of the launch states and of the caption (TalkBack on the swap, the real
system bars).

**S11 — built 2026-11-08 (one implementer, one reviewer, two fix passes,
one re-review) in its own worktree, written as v47 and renumbered to v48 at
the merge into the main tree, uncommitted.** A device-local contentless FTS5
trigram table `note_body_fts` with a `note_search_ledger` (per note: the
stamp projected and a fingerprint), created empty by the migration step,
which reads no body and swallows a refusal (a SQLite without the trigram
tokenizer): `NoteSearchDao.probeCapability()` answers `usable`,
`unsupported` (no such table / tokenizer / module — the tables are created
once more and probed again, then cached for the database; the search then
scores every note in scope with no index writes) or `unknown` (logged, not
cached, probed again next search). `BodySearchIndexer`, one per database
generation, fills the index lazily after launch and never on save — the
`OptimizedNoteBloc` → `FolderSearchService` dependency is gone entirely
(`removeFromIndex`, `FolderSearchService.dispose`, the `searchService:`
constructor argument) — in cooperative pages cut by bytes and capped at
`SearchConstants.bodyPageMaxNotes` (500), pausing behind an unsaved editor
at most `bodyIndexEditorPauseLimit` (15 s) per drain, with the checkpoint
only after a real write. A full search probes `hasPendingWork()` once
(any stale ledger row or orphan; an O(N) walk of live notes and ledger:
1.2 ms at 5,000 notes, 10 ms at 50,000, in memory) unless a drain is
running, drains what is stale, and answers through
`FolderSearchService.searchWithCoverage()` → `({results, incomplete})`;
the bloc re-runs once on `SearchIndexSettled`. The fingerprint is
`group_concat(COALESCE(content_hash, hlc_timestamp), ',' ORDER BY
chunk_index)` over the live chunks, so a chunk plan that only reordered rows
re-projects the note (the pin fails on the old `MAX(hlc_timestamp)` form —
the reviewer ran it); an undecodable note settles by its title under the
`'unreadable'` fingerprint, and any later write to it re-projects it. The
label filter maps an out-of-palette value to `none` (`CASE … BETWEEN 0 AND
7`). `BodySearchIndexer.markActiveDirty()` is a static hint called by the
note change stream (and by Optimize, wired at the merge); the probe finds
every change anyway. The projection keeps today's match rules (the parity
suite, 48 cases, against the legacy index). `notes_fts` stays in step on
every write until S12 retires it. **Counts:** one warm full search = 3
statements (the probe, the MATCH, one batched body read) at 7 notes and at
122; 1,200 empty notes → 3 batched body reads in the backfill and 3 in the
scoring. Review history: the first review found edits made before the first
search or after a database switch were never indexed (the dirty channel
lived on the service), reorders invisible to the fingerprint, an unbounded
editor pause, no page cap, a dropped table unrecovered, the label filter,
and the dead bloc dependency; the re-review found the undecodable note
re-running the drain on every search (a cycle with the bloc's re-run), the
undocumented `group_concat` order, a silent cached probe failure and a
vacuous reorder pin — all fixed. Deferred: probe only when dirty if the
O(N) probe ever shows; a covering partial index `(note_id, chunk_index,
content_hash, hlc_timestamp) WHERE is_deleted = 0` if the fingerprint's
overflow-page reads show (`content_hash` sits after `content`); a pin for
the transient-probe path; broad queries (10.9 s at 5,000 × 15 KB before
S12's bm25 ranking), the 300 ms target, and note-open and folder-list
latency during a backfill — S12. Not verified: a device run; the volume
benchmark (tagged, minutes long).

**S5 — built 2026-11-08 (one implementer, one reviewer, one fix pass, one
re-review), merged into the main tree, uncommitted.** All eight items: (a)
the note bloc no longer re-indexes after a save (the repository's change
stream marks the note stale; the index refreshes at the next search);
`SearchIndex.removeNote` walks the note's own terms, `addNote` removes the
old entry first and resets the sorted prefix list, a `@visibleForTesting
isConsistent` invariant; (b) the capped preview reads lazily and stops once
the collapsed output passes the cap — not literally three lines, because
that would change the preview of short-lined notes; a front-matter or
leading-rule first line no longer forces a whole split (lazy line count);
(c) `CodeLine.graphemeCount` cached per line in an `Expando`,
`CodeLines.graphemeCount` the sum plus breaks, the stats tracker counts
nothing while the bar is hidden (`markStale`/`resume`); (d) find sends
`asString(lf)` to the isolate and gets positions back, one-pass mapping
(`CodeFindPositions.map`), a `LatestWinsQueue` for find only, no match cap,
a delivered result marked dirty when the lines moved; the preview-mode
search counts newlines running and never throws on a lengthened lower-case
text; (e) the ledger keeps a `_dirty` set and refolds dirty notes on a 1 s
trailing debounce (`AppConstants.ledgerRefoldDebounce`); `refresh()` still
refolds every linked note because the sync apply hooks invalidate without
announcing; (f) `LruCache` weighted (`maxWeight`/`weigh`), the content cache
bounded at 8 Mi code units (about 16 MB, `AppConstants.maxContentCacheCodeUnits`)
beside the 50-entry cap, the newest entry never evicted;
`didHaveMemoryPressure` in `lib/main.dart` calls `invalidateAll()`; (g) the
first load above `AppConstants.asyncLineBuildThreshold` (256 K code units)
uses the fork's `codeLinesAsync`, a remote merge announced during the await
is remembered and replayed through the normal remote path once the load
lands (the clean editor re-reads the merged row, a dirty one files the
conflict copy), a failed split falls back to the synchronous load;
`loadCodeLines` seeds the `asString` cache for `\n` text; (h) the live
preview's large-note path also triggers above
`AppConstants.previewPreloadCodeUnitThreshold` (100,000 code units) — a
behaviour change recorded in §6.2. Fork ledger entry in
`docs/re-editor-performance-2026-07.md`. Not done here: `shouldCompress`
(S4 did it); the browser's preload size check (the lists stream). Review
(no blocker after the fix pass): a confirmed regression — a brand-new note
could not be found by prefix because `removeNote`'s early return skipped the
sorted-list reset — fixed and pinned; the merge-during-load window widened
by (g) — closed by the replay and pinned with a 360,000-code-unit page test;
the find dirty-marking swaps a correct result for a disabled one on undo
(follow-up: drop the stale result instead); the preview-search guard is dead
code on the VM (`toLowerCase` never lengthens there; the comment and the
vacuous test are a follow-up); the conflict-copy branch of the replay and
the async-load error fallback are unpinned (follow-up). Suites green one
file at a time; the integration gate (S4 + S5 + S18) 14,055 passed.

**S18 — built 2026-11-08 (one implementer, one reviewer, one fix pass, one
re-review), merged into the main tree, uncommitted.** Export streams
through `ZipFileEncoder.createWithStream(…, level: DeflateLevel.bestSpeed)`
over a handle the service keeps (`openArchiveHandle` seam), under a
provisional `anta_exports/archive_<ts>.part` renamed after close; a failed
write or close closes the handle directly and deletes the partial file;
import decodes from an `InputFileStream`, each entry `clear()`-ed after use,
the stream closed in a finally; sibling folders whose cleaned names collide
get ` (n)` names from the directory's shared name set (before, duplicate
entries silently dropped the second folder's notes on import). The `.db`
share hands over a `VACUUM INTO` snapshot (`<temp>/anta_db_share_<ms>/<name>.db`)
taken on a short-lived read-write never-create connection inside
`Isolate.run` for the open database too, so the app's connection is never
held and no `PRAGMA temp_store` toggle is needed; earlier snapshot folders
are deleted first, a failed copy deletes its own folder; cleanup after the
share on Android (share_plus copies the file), deferred on desktop and on
`unavailable`; a busy WAL no longer refuses the share (pin flipped). The
sweep deletes only ANTA-prefixed entries; note and archive exports moved
under `anta_exports/`; the three names live in
`lib/constants/temp_file_names.dart`. Deleted: `BackupService.exportAllData`,
`exportToFile`, `shareBackup` (it called `SharePlus` directly), the helpers,
`lib/utils/isolate_worker.dart`, `test/services/backup_service_sync_keys_test.dart`
(its export-side intent is moot; the restore side stays pinned). The retired
exporter lives on verbatim as the test fixture
`test/services/support/backup_archive.dart` for the round-trip suites. The
onboarding JSON restore decodes once in `Isolate.run` (`readBackupFile`,
`validateBackupData`, `importFromData`; the `String` APIs stay). Skill
references updated (feature-areas, import-export, flutter-principles).
Reviews: no blocker; the first found the write-failure handle leak and the
sibling-name collision (both fixed and pinned), the Android `temp_store`
risk and the connection hold (both removed by the snapshot connection);
the second confirmed every fix. Not verified: Android on a device
(share_plus's real result, the copy's duration on a phone), a real
`SQLITE_FULL`. Pre-existing, out of scope: `pairing_sheet.dart`'s text share
through `SharePlus`; desktop deletes non-snapshot temporary exports right
after `share()` returns.

### 8.3 Device passes (2026-11-08, `emulator-5556`)

On the main tree holding every slice but S6, S7 and S12 (the QA build
d6648966+dirty): calendar 35/35 green (677 s), alerts 5/5 green (the two
event alarms and the test alarm fired on time, none stray, 0 armed after),
settings 20/20 green, browser 3/3 green (the drag flow included). A
hand-driven Optimize on the Databases page: "Already compact" on both taps,
the page in place with no spinner, the caption "Reclaimable: 0 B"
throughout; the Statistics size read 1.86 MB before and 352 KB after,
because the shown size counts the `-wal` file and Optimize's checkpoint
truncates it — correct, and worth a caption word if it confuses. Not
observed on device: the upgrade of a stored database (every flow reseeds a
fresh one; the chain is pinned from the real v30 file in
`upgrade_chain_test`), the import dialog, the launch states, the held-back
list (no saved flow reaches them; §11.1's device bucket). **On the final
tree** (all twenty slices, the QA build rebuilt): settings 20/20 and
browser 3/3 green again; the install's first launch, which carried the QA
database through v50, logged no error.

### 8.4 The commit

The round is one change: its slices interleave in `note_dao.dart`, the
migrations, the sync engine and the l10n files, so it does not split into
clean per-slice commits after the fact. The owner commits from the main
tree once S7 has landed and the gate is green:

- The set is everything `git status` shows under `frontend/anta/` except
  the plugin registrants under `linux/`, `macos/` and `windows/flutter/`
  (restored after every test run; if they show, `git checkout -- frontend/
  anta/linux frontend/anta/macos frontend/anta/windows` first). Generated
  files are part of it: `lib/database/database.g.dart` (the counter columns)
  and the `lib/l10n/app_localizations*.dart` files; so are `firestore.rules`,
  `firestore.indexes.json`, `tool/firebase/rules_probe.ps1`, the
  `android/app/src/main/res/xml/` backup rules, the `.claude/` skill
  references and this record.
- Suggested message: `scalability: content-defined chunks on the device and
  on the wire, a body search index, targeted calendar reloads, gapped list
  positions, streamed backups, verified imports, PN counters, storage
  hygiene (v46–v50, wire 46)`, with the per-slice lines from §8.2 as the
  body if a long message is wanted.
- Before installing the build on a phone: §8.2 S6's owner steps (deploy the
  rules and indexes first; both phones the same day; the second phone's sync
  stopped or offline until it runs the new build).
- **The first-install fix (§8.5) is a second commit** after the round's
  `20d5da9c`: its 43 files — the 40 of the patch, the seed-guard test's
  allow-list entry, this record and the two references — staged by name
  (another session's 35 uncommitted editor files sit beside them, so never
  `git add -A`); suggested message `sync: the update's first run
  holds the database only to write — bodies cut and encoded off the lock,
  pages in 2 MiB parts, no spurious copy from the re-queue (v51 republish),
  "Finishing the update" on the Sync page and in the drawer`.

### 8.5 After the first install (2026-11-08)

**Read with §8.6.** The stall described here had another cause — the
upgrade launch's first frame bound to Drift's open-time zone — found when it
recurred under this section's fix; the costs named below were real and their
fixes stand.

**What happened.** The owner installed `20d5da9c` on their phone at 13:12.
The first launch sat on spinners on every page for minutes — the Calendar
page a full-page spinner, the Folders root its list spinner under the static
"All notes / Recent" card and a bottom bar without its count caption (the
round changed nothing in that bar; the QA root screenshots before and after
it are identical) — then Settings → Sync → "Stop syncing" ended the app, and
the second launch was fine. The phone was not on USB, so its crash buffer is
unread and the death unexplained; the stall is explained by the code and
reproduced in tests.

**Diagnosis.** (1) The run that cuts over (`SyncEngine._cutOverWire`)
re-reads every note document whole and re-queues every live note. (2)
`SyncPuller._apply` applied a page (50 notes) in one transaction with each
body's decode, content cut, SHA-256 and gzip inside it; Drift's executor is
exclusive during a transaction, so every UI query — the folder list, the
calendar — waited behind each page. On the phone most pages merged at equal
stamps, which cuts nothing, so (3) was the longer phase: the drain pushed
every re-queued note, and each note still stored as pre-v46 slices — every
note, since v46 only added `content_hash` — went through
`ContentChunkDao.hashLegacy`, which encoded every chunk inside its
transaction, and `NotesBinding._manifestOf` opened a transaction per note to
decompress and hash the whole body. (4) Nothing told the user: the drawer and
the Sync page said "Receiving…" / "Downloading N rows". (5) Found on the way:
the re-queue gives every note an outbox entry at its own stamp, which
`CrdtMerge.mergeRemoteRow` read as a pending edit, so a note another device
edited since this device's last pull got a conflict copy of a text the space
already held — on the first device today (search "conflict copy"), and on
the second device at its cutover, which has no `note_seen` keys yet (they
arrived in the same commit).

**Fixed the same day** — six implementer passes in one worktree
(`%TEMP%\anta-wt-fix`), two independent reviews (the sixth pass closes the
second review's findings), merged into the main tree, UNCOMMITTED:

- *Pull.* `NotesBinding.prepareBodies` assembles the bodies before the page
  transaction and `readyBodies` cuts and encodes each part in one isolate
  hop (`ContentChunkDao.encodeBodies`, `BodyCut.ofEach`;
  `CrdtMerge.remoteWrites` predicts which bodies the merge stores, a wrong
  prediction falls back to cutting inside). A page commits in parts of at
  most `SyncEngine.pullBodyBudget` (2 MiB of body text): each part its own
  transaction, parks, copies, clock advance and hooks; the cursor, `skipped`
  and `gone` go with the last part, so the cursor never passes an unstored
  park; a run cut between parts re-reads the page and the stored rows merge
  unchanged (the S9 branch re-queues each legacy-shape note once, no
  duplicate entry). `fetched`/`asked` reach the fallback merge (first review's
  finding: a replaced chunk parked the note instead of failing the part).
  `_checkHalt` runs before the reads. A body whose cut or encode throws parks
  alone inside its savepoint.
- *Push.* `_manifestOf` reads the chunk rows in one statement and hashes
  outside any transaction (`ContentChunkDao.bodyHashOf`, off the UI isolate
  above `BodyCut.isolateThreshold`); `hashLegacy` cuts and encodes the whole
  text before its transaction (`EncodedBody` through `applyWrite`'s
  `ready:`), the rows-unchanged guard kept.
- *Conflict check.* The local text a copy would need is pre-read
  (`PreparedNoteBody.localBody`) and used only while the local stamp still
  matches; an accepted foreign version (`note_seen` equal to the local stamp)
  files no copy; **v51** adds `sync_outbox.republish` — `requeueBodies` and
  the S9 branch set it, every real write's upsert resets it (MIN(old, new),
  so a re-queue never turns a real edit into a republish), and
  `localHadPendingPush`, now read through `SyncOutboxDao.ackUnpushedThrough`,
  ignores it — so the cutover files no spurious copy on any device, and a
  real unpushed edit is still filed once with its text.
- *Status.* `SyncStatus.updating`, `updatingTotal`, `updatingSent`,
  `updatingSending`: the Sync page says "Finishing update — notes N of M"
  through the pull (live merged notes only) and "Finishing update — sending
  N of M" through the drain — the phase is the flag, set as the drain
  starts, so no emit between the two phases words one with the other's
  total; both strings sit in the page's `_statusLineTemplates`, so the
  status row keeps its height (one-height test in en/de/ro at 1.0–2.0, the
  second review's finding); the drawer's one-line row "Finishing update
  (N of M)" (`drawerSyncUpdating`, fits 360 dp in en/de/ro); pauses outrank
  it; false on a bind's first run. en/de/ro. The S9 republish branch skips a
  document at the seed stamp (the merge runs no ack there), the guard
  test's allow-list naming the comparison.
- *Body search indexer.* Already loads and decompresses outside its
  transaction; pinned.

**Measured (desktop).** First pull of 40 × 300 KB notes: the longest wait of
a trivial UI query 440–467 → 25–138 ms. Drain of the same: transactions
44 → 4, time held 371 → 105 ms. The phone's scenario (every note held as
legacy rows, whole-body documents in the space, the wire rolled back): time
transactions were held 577 → 289–358 ms, the longest single transaction
unchanged (~40 ms, a pull page). On a phone each removed hold is several
times longer. `test/services/sync/sync_cutover_stall_benchmark_test.dart`
(tag `benchmark`, skipped by default) prints the three numbers.

**Pins.** `test/services/sync/sync_pull_page_work_test.dart` — no cut or
encode inside a pull transaction, parts and the cursor, a run stopped
between parts, the fallback with a replaced chunk, the re-read after a part
split, the legacy re-cut encodes outside, the progress count, "Stop syncing"
mid-cutover settles within the engine stop limit and a later bind cuts over
cleanly; `sync_lost_edit_copy_test.dart`, group "the run that cuts over to
the chunked wire" — no copy for an accepted or an own pushed version, a real
edit filed once, a device without `note_seen` keys; the indexer's
transaction scope in `test/services/body_search_indexer_test.dart`; v51 in
`test/database/upgrade_chain_test.dart` and `schema_parity_test.dart`; the
status and its precedence in the drawer, Sync-section and bloc suites; the
drawer fit test in `test/widgets/app_drawer_test.dart`.

**Gate.** `dart analyze lib test` clean; the whole suite 14,902 green on the
main tree (14,897 before the sixth pass), beside the editor list-nesting
session's 35 uncommitted files.
**Device:** the QA build on `emulator-5556`, settings suite 20/20 green
twice — before the sixth pass
(`build/qa/pass/settings_20261108_155454_748_emulator-5556`) and on the
final tree (`settings_20261108_163215_418_emulator-5556`) — twenty
relaunches each of the QA database carried through v51 with no migration,
Drift or `[SyncEngine]` error in any log; the saved suites cannot exercise
the cutover itself (the QA database is unbound), so the cutover's device
behaviour rests on the pins and the benchmark.

**Not verified / open.** Why the app died on "Stop syncing" (the phone's
crash buffer over USB would say); the cutover itself has run on no device
(the saved suites' QA database is unbound — a two-device check against the
Firestore emulator would be the proof); a status line on the Folders root
during the re-sync (the owner's call). Accepted as they are from the second
review: the progress totals are approximate (notes new from the space count
past the local total and clamp at "N of N"; the drain's total includes
parked entries, so the line can stop short); a transient encode failure
parks the bodies that fail again, as before the fix; `syncUpdating` and
`drawerSyncUpdatingNoTotal` are defensive fallbacks that never show in
practice; `_manifestOf` reads a legacy note's rows twice on its first push.

**Owner's steps.** Install this build on the phone, then on the second
device the same day — its cutover runs under the fix and files no spurious
copies; on the phone, search "conflict copy" for copies filed today and
delete those whose text the other device already had; put the phone on USB
once so the crash buffer can be read; commit (§8.4, the second commit).

### 8.6 The upgrade-launch stall, found (2026-11-08, evening)

**What happened.** The owner installed `d9f34776` (v51, §8.5's fix
included) over the v50 build at 16:51 and saw the same picture as at 13:12:
spinners on every page — the Folders root with "All notes" bare of its
count, no folder rows, no caption in the bottom bar, no calendar, no note
would open — until the app was closed and opened again. Sync was bound both
times, which is what pointed §8.5 at the cutover; its diagnosis named real
costs, not the stall.

**Reproduced** on `emulator-5556` with sync off entirely (`cloud=off`): the
QA build of `6f4d7b2d` (v50) installed, `relaunch --fresh --seed` with 403
notes (4.4 MB of bodies), one plain relaunch (healthy), then the
`d9f34776` QA build installed over it and launched — "Updating your data…",
then the Folders root with "All notes" bare, no rows, no "3 folders"
caption, unchanged after 30 s. `qa errors` empty; the only app log line
`[AlertScheduler] reconcile(launch) skipped: nothing can arm`, so database
reads from that path were answered; `qa perf` counted 242 frames in 4.4 s,
so the spinners animate and nothing below the UI is blocked.

**Diagnosis**, read off the stuck process through the VM service (object
walks — the debug APK carries no expression compiler). The Drift client
channel held six requests the database isolate never answered:
`FolderDao.getFolderCount` from the folder bloc (twice), `NoteDao.getNoteCount`
from the root page, `UserSettingsDao.getValue` from the page's settings load
and from `AppNavigator.restoreLastLocation` (via `_promptForPermissions`),
and `SearchBloc._reloadLabelsInUse` — every trace resuming in a
`_CustomZone`. In the database isolate, `ServerImplementation._executorBacklog`
was **empty** and no executor was managed, so each waiting request named an
executor id the server had already released: `_waitForTurn(id)` returns only
when that id is first in the backlog. `PlatformDispatcher._onBeginFrameZone`
and `_onDrawFrameZone` were that same `_CustomZone` (parent root), while
`_onPointerDataPacketZone` was `_RootZone`. The chain: Drift runs `onUpgrade`
inside `_runConnectionZoned(BeforeOpenRunner(this, executor), …)`, a zone
whose value makes every statement issued under it resolve to the executor the
open runs through (`RunBeforeOpen`'s `createdExecutor`, released when
`beforeOpen` returns). `AppDatabase.onUpgrade` calls `onUpgradeStarting`
there, and its `runApp(AppBootstrap.updating())` is the process's first
`scheduleFrame`; `SchedulerBinding.ensureFrameCallbacksRegistered` sets
`platformDispatcher.onBeginFrame` / `onDrawFrame` once (`??=`) and `dart:ui`
stores `Zone.current` beside them — so every frame for the rest of the
process ran in Drift's open-time zone: every build, `initState`, post-frame
callback, every bloc a page creates and every read they start carried the
retired id and waited for good. Reads rooted elsewhere kept working (the
alert scheduler's serialized queue, `main`'s own awaits, `SettingsService`
before the first frame), which is why the page itself drew and the log stayed
clean; a restart's first `scheduleFrame` is `runApp(MyApp())` from `main`,
in the root zone — hence "fine the second time". Neither sync nor the
migration's content plays a part: v50 → v51 is one `ALTER TABLE`, and any
launch that migrates stalled the same way, which is why both installs of the
day did and no QA relaunch ever had (the QA database never migrates).

**Fix.** `AppDatabase.onUpgradeStarting` is a setter/getter pair: the setter
records `Zone.current`, the getter hands back the hook bound to that zone
(`zone.run(hook)`), so Drift's `onUpgrade` — or anything standing in for it —
runs the bootstrap in launch's zone and the engine's frame callbacks bind
there. `main.dart` is unchanged. Pins in
`test/widgets/app_bootstrap_test.dart`: a hook installed from a marked zone
runs in that zone when a real file-backed open migrates (v46 → current), and
`openDatabaseForLaunch`'s `show` runs in the launch zone when the open fires
the hook from a forked zone; both fail on the previous code.

**Verified on device** (`emulator-5556`, sync off): the same cycle — the v50
QA build, `relaunch --fresh --seed` with 403 notes, a plain relaunch, the
fixed `d9f34776` build installed over it and launched — showed the Folders
root with its rows ("Inbox 400", "Money 1", "Training 2") and the "3
folders" caption within the launch's first seconds; the Inbox listed its
notes and "Big note 399" opened in the editor; the drawer's Calendar landed
on the grid with "Lifting session" and no spinner. Gate: `dart analyze lib
test` clean, the whole suite 14,904 green (17 benchmarks skipped). Left to
the owner: install on the phone (the fix takes effect at the next schema
bump — v51 → v51 migrates nothing), then commit with §8.4's second commit.

**What §8.5 keeps.** Its changes stand on their own measurements (body work
off the lock, pull parts, `republish`, the status line); none of them
addressed the stall, and its "the cutover itself has run on no device" line
still holds. The death on "Stop syncing" at 13:12 stays unread; a tap handled
in a frame zone whose reads never return is a plausible path to an ANR-style
kill, not a proven one.

## 9. Definition of done

1. Every acceptance line in §5 shown by a pin or a benchmark figure
   recorded in §8.2, before and after.
2. The owner's complaint, measured: a one-character edit to a 300 KB note
   costs ≤ 20 KB up and ≤ 20 KB down per device (D1 A) and never more than
   three documents; a rename costs one document under 4 KB; a 5 MB note
   syncs; nothing is parked silently.
3. No two-device offline edit of one note loses text (the three
   `sync_pair` scenarios of S8 green).
4. A rebind of identical data uploads nothing; an idle resume costs one
   read; a 900 KB document pulls on a 0.25 Mbit/s link.
5. A one-character edit near the top of a 3 MB note performs no
   decompression and at most four chunk row writes; nothing of it runs on
   the UI isolate above 64 K code units; an emoji on a chunk boundary
   survives save and sync.
6. Body search works over every note from a persistent index: no
   per-launch rebuild, memory O(one page), a word deep in an old note
   appears while typing.
7. At 20k events: a remote presence tap costs one small read and no
   re-plan; a delete, a page return and a pulled event each cost O(changed
   rows); a year run and a picker month meet §5.6's bounds.
8. A tombstoned note holds no body; chunk deletes use the index; the
   migration showed its cost on the 500 MB fixture; an upgrade shows its
   screen.
9. A drag writes the moved rows only, in both sort directions; a 200-item
   move is one transaction.
10. Peak export memory is the largest note; the `.db` share is a snapshot;
    a corrupt or newer-schema import is refused.
11. Offline taps on two devices add up; no orphan counter values.
12. The gate green after every slice; the saved device passes green at the
    end of phases 4, 5 and 6; the owner's two-device check after phases 2
    and 3; every string in three ARBs; every retire-list item gone when its
    slice ships (grep); this record's status line and the sync record's
    §11 addendum current.

## 10. Checked and sound

Verified by the audit and **not** to be re-audited; each was reproduced in
the code and then judged negligible or already handled at the stated
scales:

- The database runs on a background isolate (`createInBackground`) with
  WAL and `synchronous=NORMAL`, benchmarked; partial indices cover most hot
  reads; the Android SQLite is the bundled 3.53 (the bound-parameter
  partial-index comments are stale — confirm with one `sqlite_version()`
  probe); `pending()`'s `ORDER BY … LIMIT 499` uses a bounded top-N sorter.
- Folder and note lists paginate (20) and are virtualised (`SliverList`
  builder); per-folder counts are one recursive aggregate per visible page,
  not N+1; bulk delete is set-based; bloc refreshes coalesce per tick; the
  search bloc debounces and drops stale results by generation; breadcrumb
  ancestor walks hit the folder cache; within-folder sorts over small
  metadata rows; the title/preview LIKE scans a small table.
- The live markdown passes are incremental (segment identity), highlighting
  is off, layout is virtualised, undo is capped at 200 with structural
  sharing; the `isCompressed` UTF-8 pass and the ledger refold are small
  beside the save they ride on (S5 removes them anyway).
- Alerts: OS registrations are capped (48 + 20); a single-event save's full
  re-plan is bounded by the horizon; dense rules (workdays, weekends,
  holidays-only) are three kinds; `SpecificDates` sets are small; the
  month-change partition rebuild is one pass; per-day descriptions are
  capped by the user setting (500–10,000, default 2,000) and were measured
  at 2,000 rows.
- Sync: the outbox grows only with distinct rows changed; the space
  document write per batch is negligible; the status emit's reads are
  cheap; counter pages reload a small store; conflict copies do not cascade;
  tombstones are a few hundred bytes each and partial indices hide them;
  re-queuing tombstones at bind is small; Firestore persistence is off, so
  no duplicate on-disk cache; blind-set pushes without a server HLC compare
  converge through the next pull (S8 handles the text).
- Backup: the JSON export path is dead code (S18 deletes it); whole-folder
  reads have no live caller; the 50-entry content cache is small in
  practice (S5 bounds it by bytes anyway).
- Vocabulary: every finding refuted at the stated scale (hundreds of terms);
  nothing to do.
- The multi-database switch is a cold restart by design; `listDatabases`
  and the clock seed scan are one-off and small.

## 11. Deferred

Each with the trigger that reopens it and enough to resume from here.

- **Chunk garbage collection in the space** (D1 A). Unreferenced chunk
  documents accumulate at a few KB per changed chunk per push; the rules
  forbid deletes. Trigger: the budget table shows stored bytes past
  ~500 MB. Design: a grace window (30 days unreferenced by any manifest a
  device still holds), `allow delete` for `content_chunks` by the owner
  only, a sweep on the device that last wrote.
- **The windowed calendar store** (D7 B). Trigger: a real store past ~10k
  event rows, or the 20k benchmark's phone cold open over 500 ms. Design:
  date-windowed DAO queries with an index on the start day, a sliding cache
  around the visible range, async all-of-time surfaces, an event FTS for
  search.
- **The bounded alert window read** at launch and resume. Trigger: a
  profile run with alerts enabled shows the launch load. Design: the
  scheduler reads its window from its own bound database, resolves every
  referenced event id through `liveByIds` before settling fires and
  orphaned snoozes, pins both halves' query plans.
- **A worker isolate** for the overview marks tier, the report fold and the
  digest scans; **overview incremental invalidation** (forget only the
  changed events' months). Trigger: more than one dropped frame per re-run
  year on the device after S13.
- **The echo skip** (a clean-push mark decided inside the push transaction,
  ≤ 1 MiB batches only, cleared on stop/rebind/`exists:false`). Trigger:
  the budget table shows the own read-back matters. **Server
  compare-and-swap** on `baseHlc` and **`data.baseHlc` on the wire** (D4 B).
  Trigger: old builds retired, or a three-device residual seen.
- **Background pull** (readiness D7 B: a Cloudflare Worker → FCM "pull
  now"). Trigger: the owner's Cloudflare account exists. **The Android
  foreground data-transfer hold** for a large first sync. Trigger: a
  measured first sync of the real database over ~2 minutes on screen.
- **Tombstone row GC** with device presence, a horizon and a rules change;
  **a per-event `childrenClearedHlc`** to make cascade deletes one write
  (the wire-implied cascade was rejected: it diverges after a revival).
  Trigger: row counts measured on a device, or the budget table.
- **Blaze** (D12). Trigger: ~15k synced rows or a second account.
- **`PRAGMA optimize` / ANALYZE** with a "with statistics" plan-test group;
  **per-folder sort indices** `(folder_id, updated_at, id)` etc., designed
  with the keyset order that will use them; the **`is_deleted` literal
  sweep** (41 sites) only if the device probe shows an old SQLite.
- **A three-way text merge** on conflict, per chunk (after D1 A), with
  bases stored and the merge off the UI isolate. Trigger: conflict copies
  become frequent.
- **An editor large-note notice** ("this note is getting large"). Trigger:
  the 3 MB benchmark janks after S4 and S5; otherwise there is no cap to
  warn about under D1 A.
- **Undo to the original position** after a move; **a find match cap**
  with a "1000+" label; **`qa meminfo`** and device instrumentation (spans,
  a profile build); a **low-end device** in the fleet. Triggers: a device
  pass shows the need.
- **Vocabulary**: nothing deferred; every finding refuted at scale.

### 11.1 Found during the build (2026-11-08)

Each is recorded in its slice's as-built note; this list is the index.

- **D4 B items** (`data.baseHlc` on the wire, server compare-and-swap).
  A lost acknowledgement on the OTHER device gives two copies of one text
  (the incoming copy under S8's rule, then D3's when the newer version
  overwrites the still-pending text); the newer device's background drain
  pushing before it pulled loses the older edit with no copy (pre-existing;
  neither device can see the overwrite); three devices editing one note with
  the third's clock behind the second's can lose the third's text; a row
  accepted before the `note_seen` rule shipped can file one false copy on a
  bulk write followed by an edit, once per such row. Trigger: any of them
  seen on the owner's devices, or old builds retired.
- **Chunked sync** (S6): a manifest grows with the body (about 30 KB
  of hashes for a 5 MB note), so an edit's bytes are the changed chunk plus
  the whole hash list; the lazy re-cut of legacy notes runs one short
  transaction per note during the cutover's drain (5,000 in the volume
  fixture); the rules say a chunk document is immutable but enforce only
  `op == 'upsert'` (an identical rewrite is allowed; only the owner can
  write); a tombstone's chunk cascade leaves dead chunk entries to be thrown
  away at push. Spec deviations as built: the durable park replaced the
  "body-pending" row (a note whose chunks the space lacks does not appear
  until they do); per-id `get`s in batches of 30 replaced the `whereIn`
  fetch and the `sync_chunk_cache` table. Trigger for GC and the rest: the
  §11 chunk-GC item.
- **`note_seen` growth**: one `sync_metadata` row per note that ever lost a
  foreign version or was accepted from the wire, never pruned. Trigger:
  `sync_metadata` past ~100k rows; design: prune with the note's hard delete.
- **Counters** (S20): a join equal on both sides with different stamps
  pushes the local entry once more (no ack on an echo whose content is
  equal); two genesis-epoch rows with different start values keep the larger
  `epochValue` whole; the mixed-version window — an older build's write or
  echo of a counter value is an absolute state at its stamp and wins whole
  over the new build's concurrent taps until both devices run the new build
  (the wire version did not bump: the keys are optional and the old build
  reads `value`). Trigger: the owner updates both devices within a day; the
  budget table shows the extra uploads.
- **Search** (S11/S12): the once-per-search `hasPendingWork` probe is O(N)
  (1.2 ms at 5,000 notes, 10 ms at 50,000, in memory) — probe only when the
  dirty hint is set if it shows; the fingerprint reads each chunk's overflow
  pages because `content_hash` sits after `content` — a covering partial
  index `(note_id, chunk_index, content_hash, hlc_timestamp) WHERE
  is_deleted = 0` if `touchUnchanged` after a bulk label shows. **The FULL
  search's broad query** (S12b, not built): a common word over 5,000 notes ×
  15 KB takes 11.0 s on the desktop (the scorer reads every candidate's body
  for match offsets; quick search over the same corpus answers in 19 ms from
  the index). Design: rank the candidates by `bm25` in SQL, read bodies only
  for the shown page (`SearchConstants.fullSearchBodyPage`, about 200), and
  say "showing the N best matches" with a way to the rest; the parity suite
  then pins the page, not the whole set. Trigger: a full search over 300 ms
  on the owner's phone, or the corpus past ~2,000 notes.
- **Deletes past SQLite's 32,766 variables**: the chunk delete (S16) and the
  selection's note update (the closing sweep, 2026-11-08: one `UPDATE …
  RETURNING` per `AppConstants.sqlIdBatch` ids, pinned with a 33,000-note
  selection) bind in batches; the folder cascade still binds every
  descendant folder id in three statements (a 32k-folder tree, theoretical).
- **Lists** (S17): the forward sort save on a flip is fire-and-forget
  without a catch; a dense group's heal can write up to 150 rows once.
- **Alerts** (S15): `pendingEntries()` at launch is unbounded, as the full
  pass's listing always was; a launch that finds an entry lists the platform
  twice; a live snooze or a ring keeps launches on the full pass until it
  fires.
- **Calendar** (S13/S14): the alert reconcile and the ledger refresh stay
  O(store) when they run; presence, skip and description pulls re-read their
  whole (small) tables.
- **Sync runs** (S10): a page of 1 for a document the link cannot carry in
  60 s blocks the run until S6; one-row parts re-read row metadata per part;
  a learned page size lasts the process; an unsettled table's whole-window
  re-read costs about one window of reads per run during a peer's bulk
  upload.
- **The Databases page**: create, import, rename and delete still reload the
  page behind the full spinner (Optimize and pull-to-refresh update in place
  since S16's second visual pass).
- **Device-only checks** gathered by the design reviewers (the launch states
  with TalkBack and real system bars, the import progress dialog, the
  Optimize snackbars in de/ro, a drag in a large folder on a phone, the
  alert listing's cost at launch): the `qa-runner` passes at the end of the
  round and the owner's phone.
